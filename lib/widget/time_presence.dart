import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart'; // Obx — mapTableContent is an RxMap
import 'package:intl/intl.dart'; // DateFormat — device-local by construction

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart';
import '../sdui_spec.dart'; // SduiSpec — decode + trim for the v2 keys
import '../theme_tokens.dart'; // OtqPalette, otqContrast — v4 colours
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs, pickNewestDoc
import 'notif_ui.dart'; // notifNormalizeMs — the repo's seconds-vs-ms normaliser
import 'panel_card_support.dart'; // TablePath, parseTablePath

// ─── lastAction (v2) ────────────────────────────────────────────────────────
// Pure helpers for the "Aksi terakhir" slot: no Firestore, no widget state, no
// ambient clock (`now` is injected). Unit-tested in
// test/time_presence_last_action_test.dart. Contract:
// docs/widgets/time_presence.md.

/// Parsed `lastAction` / `checkIn` config — the five ◆-positions of dev spec
/// (1) §3.1. ONE grammar, TWO slots; the class name is historical (round 1
/// shipped only `lastAction`) and is left alone so the public helper names and
/// their 39 existing tests do not churn for zero behaviour.
class LastActionSpec {
  const LastActionSpec({
    required this.sortField,
    required this.descending,
    required this.valueField,
    required this.format,
    required this.filter,
  });

  /// Position 1 — the field that decides which doc is "newest". Epoch ms.
  final String sortField;

  /// Position 2 — `desc` (default) or `asc`.
  final bool descending;

  /// Position 3 — the field whose VALUE is printed in the slot.
  final String valueField;

  /// Position 4 — DateFormat pattern, applied only when the value is an epoch.
  final String format;

  /// Position 5 (OPTIONAL) — extra WHERE clauses `key◼value⭘…`, AND-ed onto
  /// the component `search` by [composeLedgerSearch]. Empty = no extra filter.
  /// e.g. `ty◼clock-in` for the Check-in slot.
  final String filter;
}

/// Parse the decoded `lastAction` config string.
///
/// Returns null — meaning v1 behaviour, zero query, no Obx — when the field is
/// absent, blank, the global `empty` sentinel `--`, or an unreplaced sheet
/// template token such as `[LASTACTIONCFG]` / `[CHECKINCFG]` / `[LASTACTION]`
/// (same `[`-prefix idiom the widget
/// already uses for time slots).
///
/// The gate is on the trimmed RAW string, never on the split length:
/// `diamondTextToList('')` returns `['']` (length 1), not `[]`, because its
/// guard compares against `empty == "--"` (global.dart:364).
///
/// Every position is length-guarded (`p.length > N ? … : def`), never
/// `p[N] ?? def` — an out-of-range index throws and would crash a lean tenant.
LastActionSpec? parseLastAction(String raw) {
  final String s = raw.trim();
  if (s.isEmpty || s == empty || s.startsWith('[')) return null;
  final List<String> p = diamondTextToList(s);
  final String sortField = (p.isNotEmpty && p[0].trim().isNotEmpty)
      ? p[0].trim()
      : 't';
  final String dir = p.length > 1 ? p[1].trim().toLowerCase() : '';
  final String valueField = (p.length > 2 && p[2].trim().isNotEmpty)
      ? p[2].trim()
      : sortField;
  final String format = (p.length > 3 && p[3].trim().isNotEmpty)
      ? p[3].trim()
      : 'HH:mm';
  // Position 5 is optional and its default is the empty string, so no
  // isNotEmpty branch: absent, empty and blank all mean "no extra filter".
  final String filter = p.length > 4 ? p[4].trim() : '';
  return LastActionSpec(
    sortField: sortField,
    // Only an explicit `asc` flips direction; every other value — including a
    // typo — means descending, which is what "aksi terakhir" always wants.
    descending: dir != 'asc',
    valueField: valueField,
    format: format,
    filter: filter,
  );
}

/// Epoch-ms reading of a raw Firestore field value, or null when the value is
/// not a plausible timestamp.
///
/// Tolerates String (the production shape: `t` is a Firestore stringValue) and
/// num. [notifNormalizeMs] upgrades a 10-digit seconds epoch to ms — the repo's
/// single answer to the seconds-vs-ms question (dev spec §12). The plausibility
/// band then rejects small numbers (a count, an index) that would otherwise
/// render as a 1970 clock time.
int? lastActionEpochMs(dynamic raw) {
  int? n;
  if (raw is int) {
    n = raw;
  } else if (raw is num) {
    n = raw.toInt();
  } else if (raw != null) {
    n = int.tryParse(raw.toString().trim());
  }
  n = notifNormalizeMs(n);
  if (n == null) return null;
  // 2001-09-09 .. 2100-01-01, on the ms value itself.
  if (n < 1000000000000 || n >= 4102444800000) return null;
  return n;
}

/// True when [epochMs] falls on the same DEVICE-LOCAL calendar day as [now].
///
/// `DateTime.fromMillisecondsSinceEpoch` without `isUtc: true` is local, so
/// year/month/day equality is exactly "≥ local midnight today and < local
/// midnight tomorrow" with no DST arithmetic to get wrong.
bool isSameLocalDay(int epochMs, DateTime now) {
  final DateTime dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return dt.year == now.year && dt.month == now.month && dt.day == now.day;
}

/// Render the `valueField` value for the slot.
///
/// Epoch → `DateFormat([format])` in the DEVICE timezone — never a manual +7
/// (dev spec §7.4). Non-epoch → returned as-is with [format] ignored (dev spec
/// §3.1 position 4, e.g. `valueField:"ts"` holding "07 Sep 2026 09:37:34").
/// Absent / blank / `--` → empty string, which the caller turns into the
/// no-data placeholder.
String formatLastActionValue(dynamic rawValue, String format) {
  final String s = (rawValue ?? '').toString().trim();
  if (s.isEmpty || s == empty) return '';
  final int? ms = lastActionEpochMs(rawValue);
  if (ms == null) return s;
  return DateFormat(format).format(DateTime.fromMillisecondsSinceEpoch(ms));
}

/// The component `search` AND this slot's position-5 `filter`, as ONE
/// condition string.
///
/// [filterDriverHomeDocs] already decodes and AND-splits on `⭘` (U+2B58), so
/// composing here means the widget has exactly ONE search evaluator — there is
/// no second implementation to keep in sync with the shared one. An empty
/// [filter] returns [search] unchanged; the trim is behaviour-neutral because
/// both `filterDriverHomeDocs` and `filterByMultiClause` trim before they test
/// for emptiness.
///
/// ★ Both inputs also get a local `_2B58_` -> `⭘` pass. `autheniumDecode` —
/// which `SduiSpec.str` runs on the way in and `filterDriverHomeDocs` runs
/// again — handles `_u2B58_` and the legacy `_25FC_`, but its `_2B58_` line is
/// COMMENTED OUT (`global.dart:1197`), and position 5 is this widget's first
/// field whose documented shape is a `⭘`-joined chain. A server emitting the
/// legacy no-`u` dialect would otherwise leave the AND separator intact,
/// collapse the chain into ONE clause with the value `clock-in_2B58_p◼home`,
/// and blank the slot silently and forever. `global.dart` is off-limits, so
/// the guard lives here — the same local pass `parseKeyedDsl` already carries
/// (`driver_home_support.dart:518-536`). `_u2B58_` never contains `_2B58_` as
/// a substring, so running this pass after `autheniumDecode` is safe.
String composeLedgerSearch(String search, String filter) {
  final String s = search.trim().replaceAll('_2B58_', '\u{2B58}');
  final String f = filter.trim().replaceAll('_2B58_', '\u{2B58}');
  if (f.isEmpty) return s;
  if (s.isEmpty) return f;
  return '$s\u{2B58}$f';
}

/// SCOPE the docs to the current DEVICE-LOCAL day, THEN pick per [cfg].
/// Returns the winning doc, or null when nothing is in scope.
///
/// ★ ORDER MATTERS — this is the whole of dev spec (1) change C. §3.2.2 makes
/// the day a SCOPE applied BEFORE the pick, not a guard applied after it.
/// Picking first and guarding the winner (round 1) is equivalent only under
/// `desc`: with `asc`, `pickNewestDoc(descending: false)` returns the oldest
/// doc in the WHOLE ledger, the guard rejects it, and the Check-in slot reads
/// `--:--` forever.
///
/// The scope also ESTABLISHES the precondition `pickNewestDoc` documents for
/// ascending: every surviving doc carries a [LastActionSpec.sortField] that
/// `int.tryParse` accepts, so that helper's `?? 0` fallback — which otherwise
/// makes a doc that is MISSING the field always win `asc` — can no longer
/// fire. That is why the shared helper needs no change.
///
/// ★ It takes TWO parses to be able to say that, and crossing them is the
/// point. The scope reads the value with [lastActionEpochMs] (tolerates `num`,
/// upgrades a 10-digit seconds epoch, checks a plausibility band); the pick
/// reads the SAME value with `int.tryParse(...)`. The scope's parser is
/// strictly the more permissive of the two — a Firestore `double`
/// `1757400000000.0` satisfies `raw is num` but stringifies to
/// `"1757400000000.0"`, which `int.tryParse` rejects — so on the scope's
/// predicate alone such a doc would pass and still score 0. Requiring both is
/// what makes the sentence above true rather than aspirational. NOT covered by
/// it: a 10-digit seconds epoch satisfies both parses, and the pick then
/// compares it raw against 13-digit siblings.
///
/// A doc whose `sortField` is unreadable is simply out of scope: it cannot be
/// placed in "today". This deliberately revokes round 1's fail-open day-guard
/// (decision D5 → R2-2). A blank is a legitimate "no event today"; keeping the
/// escape would let `asc` return the oldest event of all time.
///
/// The scope bounds BOTH ends: it is exactly ONE calendar day in the device
/// timezone. §3.2.2 words it as `t >= awal hari 00:00`, a lower bound only;
/// [isSameLocalDay] also excludes tomorrow. Be precise about what that does
/// NOT buy — it excludes yesterday and tomorrow, not "the future". A doc
/// stamped 23:59 today is in scope from 00:00 onwards and still wins `desc`
/// when read at 08:00, so realistic clock skew (minutes, hours) is not
/// filtered out; only skew of a full calendar day or more is.
Map<String, dynamic>? pickLedgerDoc(
  List<Map<String, dynamic>> matched,
  LastActionSpec cfg,
  DateTime now,
) {
  final List<Map<String, dynamic>> scoped = matched.where((
    Map<String, dynamic> d,
  ) {
    final int? ms = lastActionEpochMs(d[cfg.sortField]);
    if (ms == null || !isSameLocalDay(ms, now)) return false;
    // Require what the PICK requires, not just what the scope can read — see
    // the ★ paragraph above. Without this a `num`-typed sortField passes here
    // and still scores 0 in pickNewestDoc, i.e. still always wins `asc`.
    return int.tryParse(d[cfg.sortField].toString().trim()) != null;
  }).toList();
  // [pickNewestDoc] is a single linear scan with a strict comparison, so ties
  // keep the first doc in list order; `List.sort` is unstable in Dart and the
  // live ledger already holds 86 docs.
  return pickNewestDoc(
    scoped,
    field: cfg.sortField,
    descending: cfg.descending,
  );
}

/// The moment a winning ledger doc represents — its `sortField` epoch, which
/// [pickLedgerDoc]'s scope has already proved parseable and on today.
///
/// Read from `sortField`, never from the formatted display string: `format`
/// may be `HH.mm`, and `valueField` may be the human-text `ts`. Feeds the live
/// Durasi counter when the Check-in slot is ledger-driven (R2-1).
DateTime? ledgerDocTime(Map<String, dynamic>? doc, LastActionSpec cfg) {
  if (doc == null) return null;
  final int? ms = lastActionEpochMs(doc[cfg.sortField]);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Resolve a ledger slot's display string from already search-filtered docs.
/// Returns null when the slot must fall back to the no-data placeholder.
///
/// Dev spec (1) §3.2 rules 2 and 3: day-scope + sort + take 1
/// ([pickLedgerDoc]), then render `valueField` with `format`.
String? resolveLastActionText(
  List<Map<String, dynamic>> matched,
  LastActionSpec cfg,
  DateTime now,
) {
  final Map<String, dynamic>? doc = pickLedgerDoc(matched, cfg, now);
  if (doc == null) return null; // rule 3: nothing in scope
  final String out = formatLastActionValue(doc[cfg.valueField], cfg.format);
  return out.isEmpty ? null : out;
}

// text index mapping (◆-separated from server):
// [0] header label
// [1] check-in column label
// [2] live column label
// [3] last action column label
// [4] no-data fallback display (e.g. "-" or "-:-")
// [5] check-in time: "HH:mm" or "[CHECKIN]" placeholder
// [6] last action time: "HH:mm" or "[LASTACTION]" placeholder
// [7] checkout time: "HH:mm" or "[CHECKOUT]" placeholder / empty = no checkout

class TimePresence extends StatefulWidget {
  const TimePresence({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final bool single;

  @override
  State<TimePresence> createState() => _TimePresenceState();
}

class _TimePresenceState extends State<TimePresence> {
  late List<String> _texts;
  late double _borderRadius;

  /// v2 `lastAction` config — the Aksi-terakhir slot. Null = v1 `text[6]`
  /// literal, zero query, no Obx. Per-instance state — not Redux, not GetX,
  /// not global.dart.
  LastActionSpec? _lastAction;

  /// r2 `checkIn` config — the Check-in slot, SAME 5-position grammar
  /// (dev spec (1) §3.1). Null = v1 `text[5]` literal, zero query, no Obx.
  LastActionSpec? _checkIn;

  /// True when `lastAction` OR `checkIn` IS configured but `search` is blank.
  /// Fail-closed: filterDriverHomeDocs (driver_home_support.dart:1000) and
  /// filterByMultiClause (:951, :976) all RETURN EVERY DOC for an empty
  /// condition, so an unscoped query would print another tenant user's event
  /// on this worker's card — in EITHER slot. Render the placeholder in every
  /// configured slot, run no query.
  bool _searchBlocked = false;

  /// Decoded `search`. Passed to filterDriverHomeDocs, which decodes again
  /// idempotently and owns the ◼/⭘ decode contract (convention #2).
  String _rawSearch = '';

  /// Vid-scoped subscription code. Stays '' when no `table` is configured,
  /// which reads an always-absent mapTableContent entry -> zero docs ->
  /// placeholder (fail-closed by construction).
  String _code = '';

  /// Server-driven look. Absent -> the original 3-tile card, unchanged. Only
  /// `v4` opts a screen in to the redesign, so a tenant that never edits its
  /// screen JSON keeps exactly what it has. Same idiom as every other variant
  /// widget in the repo (display_list.dart:59, location_detector.dart:44).
  late String _variant;
  bool get _isV4 => _variant == 'v4';

  @override
  void initState() {
    super.initState();
    _texts = diamondTextToList(widget.component['text'] as String? ?? '');
    _borderRadius =
        (widget.component['borderRadius'] as num?)?.toDouble() ?? 12;
    _variant = (widget.component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    // v2/r2: read the five NEW keys through SduiSpec (decode + trim, blank -> def).
    // `text` and `borderRadius` deliberately stay on their v1 reads: SduiSpec
    // short-circuits an empty `text` to `const []` where diamondTextToList('')
    // yields [''], which would flip the v1 header default from '' to
    // 'TIME PRESENCE'. On-touch migration stops here.
    final SduiSpec spec = SduiSpec(widget.component);
    // SduiSpec.str's default is '' here, so the isEmpty guards below are live
    // (a non-empty default would make them dead code).
    _lastAction = parseLastAction(spec.str('lastAction'));
    // One grammar, two slots (dev spec (1) §3.1). `checkIn` absent -> null ->
    // the widget is INERT for that slot, which is what keeps this renderer
    // safe to ship before the builder adds [CHECKINCFG] to Widget!337.
    _checkIn = parseLastAction(spec.str('checkIn'));
    _rawSearch = spec.str('search');
    // ONE subscription serves BOTH slots (dev spec (1) §3.2.5): same `table`,
    // same `search`, only the position-5 filter and the sort differ, and both
    // are applied client-side per slot. Never open a second one.
    if (_lastAction != null || _checkIn != null) {
      if (_rawSearch.isEmpty) {
        _searchBlocked = true;
      } else {
        _subscribe(spec.str('table'));
      }
    }
  }

  /// Subscribe to the tenant event ledger.
  ///
  /// Idempotent per code (table_repository.dart keeps a `_mapSubscribed` Set),
  /// and nothing is cancelled on dispose — every sibling reader widget shares
  /// the same stream. The `code` MUST carry the appVid: mapTableContent and
  /// _mapSubscribed are keyed by it alone, and `84214220504259/event` exists
  /// under two appVids (20342033315492 and 60936087747650) with different
  /// content. Same shape as nav_action_card.dart:66.
  void _subscribe(String rawTable) {
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return; // no table -> _code stays ''
    final String appVid = resolveAppVid(widget.component);
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  bool _isPlaceholder(String s) => s.isEmpty || s.startsWith('[');

  DateTime? _parseTime(String raw) {
    if (_isPlaceholder(raw)) return null;
    try {
      final parts = raw.split(':');
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Docs this slot selects: the component `search` AND the slot's own
  /// position-5 `filter`, through the ONE shared search evaluator
  /// (autheniumDecode -> resolveDriverCurlyTokens -> resolveScreenTxTokens ->
  /// filterByMultiClause). The two slots need DIFFERENT filters, so they
  /// cannot share a pre-filtered list — but they do share the one
  /// subscription and the one `search`.
  List<Map<String, dynamic>> _matched(
    List<Map<String, dynamic>> docs,
    LastActionSpec cfg,
  ) => filterDriverHomeDocs(
    docs,
    composeLedgerSearch(_rawSearch, cfg.filter),
    widget.scrName,
  );

  /// Accent for v4's live column and node ring: the tenant's own
  /// `primaryColor`, but only when it is actually readable on white. A light
  /// brand colour (`#1CACC4` = 2.71:1) steps down to the foreground instead —
  /// the same measure-don't-assume rule otq_bottom_nav_bar.dart uses.
  Color _v4Accent(BuildContext context) {
    final Color primary = Theme.of(context).primaryColor;
    return otqContrast(primary, Colors.white) >= 4.5
        ? primary
        : OtqPalette.foreground;
  }

  /// v4: the attendance timeline of the mockup — a section heading, three
  /// status nodes joined by connectors, three value columns. No card, no
  /// border, no tiles: the module sits straight on the page.
  Widget _buildV4(
    BuildContext context, {
    required String header,
    required String checkInLabel,
    required String liveLabel,
    required String lastActionLabel,
    required String checkInDisplay,
    required String lastActionDisplay,
    required String noDataLabel,
    required DateTime? liveCheckIn,
  }) {
    final Color accent = _v4Accent(context);
    final bool hasCheckInValue = checkInDisplay != noDataLabel;
    final bool hasLastAction = lastActionDisplay != noDataLabel;
    return Padding(
      // The page pads the body by the sheet's `leftPad` (8 in this
      // workbook); v4 and v6 both specify a 16 dp content edge, so top up
      // the difference rather than sitting flush against the page padding.
      padding: otqContentInset(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (header.isNotEmpty) ...<Widget>[
            Text(
              header,
              // MASTER type scale calls "Judul bagian" 18/600; on a real
              // handset that read oversized next to 12px labels, so the whole
              // module is one step down from the mockup. The v1 11px
              // letter-spaced caps label is a different role and does not survive.
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: OtqPalette.foreground,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _V4Track(
            checkIn: hasCheckInValue ? _Node.done : _Node.todo,
            live: liveCheckIn != null ? _Node.live : _Node.todo,
            lastAction: hasLastAction ? _Node.done : _Node.todo,
            accent: accent,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _TimeColumn(
                  v4: true,
                  label: checkInLabel,
                  value: checkInDisplay,
                  valueColor: hasCheckInValue ? null : OtqPalette.mutedFg,
                ),
              ),
              Expanded(
                child: _LiveCounter(
                  v4: true,
                  accent: accent,
                  label: liveLabel,
                  checkInDt: liveCheckIn,
                  noDataLabel: noDataLabel,
                ),
              ),
              Expanded(
                child: _TimeColumn(
                  v4: true,
                  label: lastActionLabel,
                  value: lastActionDisplay,
                  valueColor: hasLastAction ? null : OtqPalette.mutedFg,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = _texts.isNotEmpty ? _texts[0] : 'TIME PRESENCE';
    final checkInLabel = _texts.length > 1 ? _texts[1] : 'CHECK-IN';
    final liveLabel = _texts.length > 2 ? _texts[2] : 'LIVE';
    final lastActionLabel = _texts.length > 3 ? _texts[3] : 'LAST ACTION';
    final noDataLabel = _texts.length > 4 ? _texts[4] : '--:--';

    final rawCheckIn = _texts.length > 5 ? _texts[5] : '';
    final rawLastAction = _texts.length > 6 ? _texts[6] : '';
    final rawCheckOut = _texts.length > 7 ? _texts[7] : '';

    final hasCheckIn = !_isPlaceholder(rawCheckIn);
    final hasCheckOut = !_isPlaceholder(rawCheckOut);

    final checkInDt = hasCheckIn ? _parseTime(rawCheckIn) : null;

    String checkInDisplay;
    String lastActionDisplay;

    if (hasCheckOut) {
      checkInDisplay = noDataLabel;
      lastActionDisplay = noDataLabel;
    } else {
      checkInDisplay = checkInDt != null ? _fmt(checkInDt) : noDataLabel;

      final lastActionDt = _isPlaceholder(rawLastAction)
          ? null
          : _parseTime(rawLastAction);
      lastActionDisplay = lastActionDt != null
          ? _fmt(lastActionDt)
          : noDataLabel;
    }

    // ── Ledger slots ─────────────────────────────────────────────────────
    // Two INDEPENDENTLY configurable live slots (dev spec (1) §3.2, per slot):
    //   cfg == null              -> that slot keeps its v1 `text` literal.
    //   cfg set, search blank    -> that slot shows the no-data label.
    //   cfg set, checkout filled -> no-data label (R2-3, checkout wins).
    //   otherwise                -> live ledger read for that slot.
    // A CONFIGURED slot never falls back to its literal: the config exists to
    // replace that frozen number.
    //
    // ★ Obx rule: never build an Obx whose closure can complete without
    // reading an observable — it throws ObxError (six prior production
    // instances; detail_card.dart:118 carries the same warning). The three
    // inert shapes have no observable at all, so they must NOT be wrapped.
    // Because BOTH slots read the same mapTableContent[_code], ONE Obx serves
    // both — never one per slot, never one per column.
    final LastActionSpec? ci = _checkIn; // instance fields are not promotable
    final LastActionSpec? la = _lastAction;

    /// The ONE call site both render paths go through. Anything added here
    /// lands on the classic card and on v4 at the same time.
    Widget module({
      required String checkInText,
      required DateTime? checkInAt,
      required String lastActionText,
    }) => _isV4
        ? _buildV4(
            context,
            header: header,
            checkInLabel: checkInLabel,
            liveLabel: liveLabel,
            lastActionLabel: lastActionLabel,
            checkInDisplay: checkInText,
            lastActionDisplay: lastActionText,
            noDataLabel: noDataLabel,
            liveCheckIn: checkInAt,
          )
        : _buildCard(
            header: header,
            checkInLabel: checkInLabel,
            liveLabel: liveLabel,
            lastActionLabel: lastActionLabel,
            checkInDisplay: checkInText,
            lastActionDisplay: lastActionText,
            noDataLabel: noDataLabel,
            liveCheckIn: checkInAt,
          );

    // The v1 counter origin, unchanged: `text[5]`, suppressed by a checkout.
    final DateTime? literalCheckInAt = (hasCheckIn && !hasCheckOut)
        ? checkInDt
        : null;

    if ((ci == null && la == null) || _searchBlocked || hasCheckOut) {
      // Zero observables in this subtree — an Obx here would throw ObxError.
      // With a checkout the v1 values are already all noDataLabel/null, so the
      // ternaries below are no-ops in that case.
      return module(
        checkInText: ci == null ? checkInDisplay : noDataLabel,
        checkInAt: ci == null ? literalCheckInAt : null,
        lastActionText: la == null ? lastActionDisplay : noDataLabel,
      );
    }

    return Obx(() {
      // ★ FIRST statement, UNCONDITIONAL, outside every ?: / && / ?? — THIS
      // read is the Obx dependency registration. Reading an absent key on an
      // RxMap still registers on the whole map, so a missing `table` (_code
      // == '') yields zero docs -> placeholder, fail-closed by construction.
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_code] ?? const [],
      );
      final DateTime now = DateTime.now();

      String checkInText = checkInDisplay;
      DateTime? checkInAt = literalCheckInAt;
      if (ci != null) {
        final Map<String, dynamic>? doc = pickLedgerDoc(
          _matched(docs, ci),
          ci,
          now,
        );
        final String v = doc == null
            ? ''
            : formatLastActionValue(doc[ci.valueField], ci.format);
        checkInText = v.isEmpty ? noDataLabel : v;
        // R2-1: the Durasi counter ticks from the LEDGER check-in, never from
        // the frozen sheet literal — two contradicting numbers on one card.
        // Tied to the same condition as the display string, so the card can
        // never show `--:--` for Check-in while Durasi runs.
        checkInAt = v.isEmpty ? null : ledgerDocTime(doc, ci);
      }

      String lastActionText = lastActionDisplay;
      if (la != null) {
        lastActionText =
            resolveLastActionText(_matched(docs, la), la, now) ?? noDataLabel;
      }

      return module(
        checkInText: checkInText,
        checkInAt: checkInAt,
        lastActionText: lastActionText,
      );
    });
  }

  /// The classic three-tile card — what every screen that does not set
  /// `variant: "v4"` keeps. Same parameter shape as [_buildV4] so both render
  /// paths are driven from the single `module` call site in [build].
  Widget _buildCard({
    required String header,
    required String checkInLabel,
    required String liveLabel,
    required String lastActionLabel,
    required String checkInDisplay,
    required String lastActionDisplay,
    required String noDataLabel,
    required DateTime? liveCheckIn,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadius),
        border: Border.all(color: Color(0xffE2E8F0)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_outlined,
                size: 15,
                color: Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
              Text(
                header,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _TimeColumn(
                    label: checkInLabel,
                    value: checkInDisplay,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _LiveCounter(
                    label: liveLabel,
                    checkInDt: liveCheckIn,
                    noDataLabel: noDataLabel,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _TimeColumn(
                    label: lastActionLabel,
                    value: lastActionDisplay,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final String value;

  /// v4 drops the tile entirely: label + number, centred, on the page.
  final bool v4;

  /// Classic-only override — _LiveCounter's elapsed clock is 15, not 17.
  final double? valueSize;

  /// v4-only override — accent for a running counter, muted for a placeholder.
  final Color? valueColor;

  const _TimeColumn({
    required this.label,
    required this.value,
    this.v4 = false,
    this.valueSize,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    if (v4) {
      // One step below MASTER's 13/600 label + 22/600 number: the mockup
      // sizes read oversized on a handset, and 12 is MASTER's own absolute
      // floor. Muted foreground is #4A5F66 (6.73:1) rather than the mockup's
      // --color-disabled-fg #93A6AC, which is 2.53:1 and fails at any size.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OtqPalette.mutedFg,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize ?? 18,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: valueColor ?? OtqPalette.foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize ?? 17,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF111827),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCounter extends StatefulWidget {
  final String label;
  final DateTime? checkInDt;
  final String noDataLabel;
  final bool v4;

  /// v4 only: colour of a running counter. Null while it shows the placeholder.
  final Color? accent;

  const _LiveCounter({
    required this.label,
    required this.checkInDt,
    required this.noDataLabel,
    this.v4 = false,
    this.accent,
  });

  @override
  State<_LiveCounter> createState() => _LiveCounterState();
}

class _LiveCounterState extends State<_LiveCounter> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _arm();
  }

  @override
  void didUpdateWidget(_LiveCounter old) {
    super.didUpdateWidget(old);
    // ★ The LEDGER check-in (R2-1) lands on a later frame than the first
    // paint: frame 1 has zero docs, the Firestore snapshot arrives after it.
    // The State is reused across that Obx rebuild, so initState never runs
    // again — without this the counter would freeze at the _now captured at
    // mount. A literal check-in never changes, so this is a no-op for v1.
    if (widget.checkInDt != old.checkInDt) {
      _now = DateTime.now();
      _arm();
    }
  }

  /// (Re)arm the 1 s tick for the CURRENT checkInDt. Idempotent: always
  /// cancels first, so a check-in that goes away leaves no timer running.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (widget.checkInDt == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _display {
    final dt = widget.checkInDt;
    if (dt == null) return widget.noDataLabel;
    final d = _now.difference(dt);
    final clamped = d.isNegative ? Duration.zero : d;
    final h = clamped.inHours.toString().padLeft(2, '0');
    final m = (clamped.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // Same two shapes as _TimeColumn, only the value differs — so render
    // through it. Classic keeps its 15px elapsed clock; v4 tints a running
    // counter with the tenant accent and mutes the placeholder.
    return _TimeColumn(
      v4: widget.v4,
      label: widget.label,
      value: _display,
      valueSize: widget.v4 ? null : 15,
      valueColor: widget.v4
          ? (widget.checkInDt != null ? widget.accent : OtqPalette.mutedFg)
          : null,
    );
  }
}

// ─── v4 timeline ────────────────────────────────────────────────────────────

/// The three states a node can be in — the mockup's `.node-done` /
/// `.node-live` / `.node-todo`.
enum _Node { done, live, todo }

/// Node fill for a completed step. #059669 is 3.77:1 on white and 3.77:1
/// against the white check inside it — both clear the 3:1 non-text bar.
const Color _kNodeDone = Color(0xFF059669);

/// Node ring and connector for a step that has not happened. A state
/// indicator carries meaning, so it owes 3:1: the mockup's #C5D3D7 is 1.54:1,
/// #7E9298 is 3.25:1.
const Color _kNodeTodo = Color(0xFF7E9298);

/// Dashed connector between two timeline nodes.
///
/// Public for testability only — the same reason location_detector.dart's
/// BleedPainter is public. Nothing outside this file should construct it.
class DashConnectorPainter extends CustomPainter {
  const DashConnectorPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.butt;
    final double y = size.height / 2;
    // 6 on, 5 off — the mockup's repeating-linear-gradient period.
    for (double x = 0; x < size.width; x += 11) {
      final double end = x + 6 > size.width ? size.width : x + 6;
      canvas.drawLine(Offset(x, y), Offset(end, y), p);
    }
  }

  @override
  bool shouldRepaint(DashConnectorPainter old) => old.color != color;
}

/// Three status nodes joined by connectors, aligned to the value columns
/// below: node centres sit at 1/6, 1/2 and 5/6 of the width.
class _V4Track extends StatefulWidget {
  const _V4Track({
    required this.checkIn,
    required this.live,
    required this.lastAction,
    required this.accent,
  });

  final _Node checkIn;
  final _Node live;
  final _Node lastAction;
  final Color accent;

  @override
  State<_V4Track> createState() => _V4TrackState();
}

class _V4TrackState extends State<_V4Track>
    with SingleTickerProviderStateMixin {
  static const double _kNode = 18;

  /// The v4 system allows exactly two automatic motions and the Live node is
  /// one of them. Stopped outright under `disableAnimations` — a repeating
  /// controller keeps requesting frames even with nothing listening.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not readable in initState, so the reduced-motion decision
    // lands here — and re-lands if the user flips the OS setting.
    _syncPulse();
  }

  @override
  void didUpdateWidget(_V4Track old) {
    super.didUpdateWidget(old);
    _syncPulse(); // check-in can arrive after the first build
  }

  void _syncPulse() {
    final bool wanted =
        widget.live == _Node.live &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (wanted && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!wanted && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double third = c.maxWidth / 3;
        // Node radius plus a 6dp breathing gap on each end — the mockup's
        // `left: calc(16.667% + 17px); width: calc(33.333% - 34px)`.
        final double gap = _kNode / 2 + 5;
        final double lineW = third - gap * 2;
        return SizedBox(
          height: _kNode,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (lineW > 0) ...<Widget>[
                // A segment is solid once progress has passed THROUGH it,
                // i.e. neither end is still pending. Keying it on one end
                // alone dashes the line between two reached nodes.
                _connector(
                  third * 0.5 + gap,
                  lineW,
                  widget.checkIn != _Node.todo && widget.live != _Node.todo,
                ),
                _connector(
                  third * 1.5 + gap,
                  lineW,
                  widget.live != _Node.todo && widget.lastAction != _Node.todo,
                ),
              ],
              Row(
                children: <Widget>[
                  Expanded(child: Center(child: _node(widget.checkIn))),
                  Expanded(child: Center(child: _node(widget.live))),
                  Expanded(child: Center(child: _node(widget.lastAction))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _connector(double left, double width, bool done) => Positioned(
    left: left,
    top: _kNode / 2 - 1,
    width: width,
    height: 2,
    child: done
        ? const DecoratedBox(decoration: BoxDecoration(color: _kNodeDone))
        : const CustomPaint(painter: DashConnectorPainter(_kNodeTodo)),
  );

  Widget _node(_Node state) {
    switch (state) {
      case _Node.done:
        return Container(
          width: _kNode,
          height: _kNode,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _kNodeDone,
          ),
          child: const Icon(Icons.check, size: 11, color: Colors.white),
        );
      case _Node.live:
        return _liveNode();
      case _Node.todo:
        return Container(
          width: _kNode,
          height: _kNode,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: _kNodeTodo, width: 2),
          ),
        );
    }
  }

  Widget _liveNode() {
    final Widget core = Container(
      width: _kNode,
      height: _kNode,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: widget.accent, width: 2),
      ),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.accent),
      ),
    );
    if (!_pulse.isAnimating) return core;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext context, Widget? child) {
            final double t = _pulse.value;
            return Opacity(
              opacity: (0.6 * (1 - t)).clamp(0.0, 1.0),
              // Tops out at 1.25x = 22.5dp: it spills past the 18dp track but
              // stays inside the 6dp gap above the labels.
              child: Transform.scale(scale: 0.7 + t * 0.55, child: child),
            );
          },
          child: Container(
            width: _kNode,
            height: _kNode,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.accent, width: 2),
            ),
          ),
        ),
        core,
      ],
    );
  }
}

class _ColumnDivider extends StatelessWidget {
  const _ColumnDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 8);
  }
}
