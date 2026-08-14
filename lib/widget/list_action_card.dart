import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // saveSend, getLocationString, getRealTime, internetConnected, defaultVid
import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // mapTableContent, diamondTextToList, autheniumDecode, routeExist, routeStack, gotoRoute, devPrint, emptyString
import '../global2.dart'; // txfController, txfControllerCheck
import '../model/input_controller.dart'; // InputController
import '../model/otq_state.dart'; // OtqState
import '../screen_session.dart';
import 'driver_home_support.dart'; // resolveAppVid, writeRouteParamsFromRow, filterDriverHomeDocs, coerceNum, stripRouteWrapper
import 'list_card_support.dart'; // BadgeEntry, StatsDef, parseBadgeMap, lookupBadge, parseStatsDefs, computeStatsCounts
import 'panel_card_support.dart'; // TablePath, parseTablePath, resolveMapTokens, statusColor, statusBgColor

// ─── Pure parsers (tested in test/list_action_card_test.dart) ─────────────

/// Parsed action metadata entry.
class ActionMetaEntry {
  final String tone; // ok|warn|danger|neutral
  final String flag; // savesend flag
  final int? notePosition; // txfController position for note; null = direct
  const ActionMetaEntry(this.tone, this.flag, this.notePosition);
}

/// Known action tones. Unrecognised → 'neutral'.
const Set<String> _knownActionTones = {'ok', 'warn', 'danger', 'neutral'};

/// The 4 saveSend operation keys a button can carry, in canonical order.
/// `updateEventRow` and `addToEvent` get `resolveDriverCurlyTokens` inside
/// saveSend (api.dart:4553/4576). `addToTable` and `updateTableRow` do NOT --
/// session tokens ({userVid}, {userName}, etc.) are only safe in the Event ops.
///
/// Additionally, saveSend injects `tableVid` into positional DSLs containing
/// `◼A⭘`/`◼D⭘`/`◼S⭘` using `currentTableVid = appVid` (api.dart:4506-4508),
/// which is `defaultVid()` -- NOT the widget's `vidtable`. Positional ops on
/// this widget must therefore author an explicit `tableVid◼` segment in the DSL
/// (same as the keyed ops' `⭘tablevid◼`). See widget doc for details.
const List<String> writeOpKeys = [
  'updateEventRow',
  'addToEvent',
  'addToTable',
  'updateTableRow',
];

/// Parse `actionMeta`: `tone◼flag[◼posisiNote]◆tone2◼flag2[◼posisiNote2]`.
///
/// Split on ◆ first, then each segment split on ◼ (up to 3 parts).
/// Empty/blank entries skipped. Unknown tone → 'neutral'.
List<ActionMetaEntry> parseActionMeta(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<ActionMetaEntry> out = [];
  for (final part in raw.split('\u{25C6}')) {
    // ◆ separates actions
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final List<String> segs = trimmed.split('\u{25FC}'); // ◼
    String tone = segs.isNotEmpty ? segs[0].trim().toLowerCase() : 'neutral';
    if (!_knownActionTones.contains(tone)) {
      debugPrint(
        'WARN ListActionCard: unknown tone "$tone", falling back to neutral',
      );
      tone = 'neutral';
    }
    final String flag = segs.length > 1 ? segs[1].trim() : '';
    final int? notePos = segs.length > 2 ? int.tryParse(segs[2].trim()) : null;
    out.add(ActionMetaEntry(tone, flag, notePos));
  }
  return out;
}

/// Parsed `fields` config (6 fixed positions).
class ListActionFields {
  final String titleTpl;
  final String subtitleTpl;
  final String imageField;
  final String metaTpl;
  final String badgeField;
  final String rawBadgeMap;
  const ListActionFields(
    this.titleTpl,
    this.subtitleTpl,
    this.imageField,
    this.metaTpl,
    this.badgeField,
    this.rawBadgeMap,
  );
}

/// Parse `fields`: 6 ◆-segments (title tpl, subtitle tpl, image field,
/// meta tpl, badgeField, badgeMap). Missing segments = empty string.
ListActionFields parseListActionFields(String raw) {
  final List<String> segs = diamondTextToList(raw);
  return ListActionFields(
    segs.isNotEmpty ? segs[0] : '',
    segs.length > 1 ? segs[1] : '',
    segs.length > 2 ? segs[2].trim() : '',
    segs.length > 3 ? segs[3] : '',
    segs.length > 4 ? segs[4].trim() : '',
    segs.length > 5 ? segs[5] : '',
  );
}

/// Parsed sort config.
class SortConfig {
  final String field;
  final bool descending;
  const SortConfig(this.field, this.descending);
}

/// Parse `sort`: `field◼dir`. Dir = 'desc' → descending; else ascending.
/// No ◼ → field only, asc.
SortConfig parseSortConfig(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return const SortConfig('', false);
  final int sep = trimmed.indexOf('\u{25FC}');
  if (sep < 0) return SortConfig(trimmed, false);
  final String field = trimmed.substring(0, sep).trim();
  final String dir = trimmed.substring(sep + 1).trim().toLowerCase();
  return SortConfig(field, dir == 'desc');
}

/// Collect write DSLs for buttons 1 and 2 from a component config.
///
/// Returns a list of length 2 (button 1, button 2). Each inner list has 4
/// entries matching [writeOpKeys] order (updateEventRow, addToEvent,
/// addToTable, updateTableRow). Values are autheniumDecode'd (via [decode])
/// and trimmed. `_cfg` does NOT trim; this function owns the trim so
/// whitespace-only config cells collapse to '' and `buttonHasWrites` returns
/// false.
///
/// [decode] is the autheniumDecode accessor (injected for testability -- in
/// production this is the `_cfg` method which calls autheniumDecode).
List<List<String>> collectButtonWrites(String Function(String key) decode) {
  final List<List<String>> result = [];
  for (int n = 1; n <= 2; n++) {
    final List<String> ops = [];
    for (final String op in writeOpKeys) {
      ops.add(decode('$op$n').trim());
    }
    result.add(ops);
  }
  return result;
}

/// Whether button [n] (0-indexed) has at least one non-empty write DSL.
bool buttonHasWrites(List<List<String>> buttonWrites, int n) {
  if (n < 0 || n >= buttonWrites.length) return false;
  return buttonWrites[n].any((s) => s.isNotEmpty);
}

/// Build a sanitised component copy for saveSend from [component], setting
/// the bare op keys from [resolvedWrites] and [flag].
///
/// Hygiene steps:
/// 1. Removes ALL 8 numbered write keys (updateEventRow1..2, etc.) so a
///    stale key from the other button cannot leak into the history record.
/// 2. Removes ALL 4 bare op keys, then re-sets only those where
///    [resolvedWrites] has a non-empty value.
/// 3. Strips `route` (would trigger clearData inside saveSend) and `delay`
///    (would push a wait-screen). Both are card-tap concerns, not inline
///    row-action concerns.
/// 4. Sets `flag`.
Map<String, dynamic> buildSaveSendComponent(
  Map<String, dynamic> component,
  List<String> resolvedWrites,
  String flag,
) {
  final Map<String, dynamic> copy = Map<String, dynamic>.from(component);
  // Clean: remove ALL numbered write keys and bare op keys.
  for (final String op in writeOpKeys) {
    copy.remove(op);
    copy.remove('${op}1');
    copy.remove('${op}2');
  }
  // Set: write this button's resolved ops into the bare keys.
  for (int i = 0; i < writeOpKeys.length; i++) {
    if (i < resolvedWrites.length && resolvedWrites[i].isNotEmpty) {
      copy[writeOpKeys[i]] = resolvedWrites[i];
    }
  }
  copy['flag'] = flag;
  // C1: `route` is the card-tap detail route and is always present; leaving
  // it in makes saveSend call clearData(scrName) (api.dart:4602), wiping the
  // whole screen's txfController plus every per-screen store (incl. _inflight).
  // `delay` would push a wait-screen -- neither belongs on an inline action.
  copy.remove('route');
  copy.remove('delay');
  return copy;
}

/// Resolve `{field}` tokens in [dsl] from [rowDoc]. Returns the resolved
/// string, or `null` if ANY token could not be resolved -- the ABORT signal.
///
/// Token scope: row doc fields first, then session tokens known to
/// resolveDriverCurlyTokens (resolved later inside saveSend). A token
/// resolvable by neither source triggers ABORT.
///
/// When a token is absent/empty in [rowDoc] but recognised by
/// resolveDriverCurlyTokens (i.e. returns a different string), the token is
/// left as a literal `{name}` so saveSend's own resolveDriverCurlyTokens
/// resolves it downstream. This allows DSLs to contain session tokens like
/// `{userVid}` / `{userName}` without tripping the ABORT rule.
///
/// [scrName] is forwarded to resolveDriverCurlyTokens for screen-scoped state.
String? resolveActionTokensOrAbort(
  String dsl,
  Map<String, dynamic> rowDoc,
  String scrName,
) {
  if (!dsl.contains('{')) return dsl; // no tokens, pass-through
  bool aborted = false;
  final String resolved = dsl.replaceAllMapped(
    RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
    (Match m) {
      final String name = m.group(1)!;
      // 1. Try the row doc first.
      final dynamic val = rowDoc[name];
      if (val != null) {
        final String s = val.toString().trim();
        if (s.isNotEmpty) return s;
      }
      // 2. Row doc miss -- probe session resolver. If it recognises the token
      //    (returns something other than the literal), leave it for saveSend.
      final String probe = resolveDriverCurlyTokens('{$name}', scrName);
      if (probe != '{$name}') {
        // Known session token -- leave literal so saveSend resolves it.
        return m.group(0)!;
      }
      // 3. Neither source knows this token -- ABORT.
      aborted = true;
      return m.group(0)!;
    },
  );
  return aborted ? null : resolved;
}

/// Tone → foreground color for action buttons.
Color _actionFgColor(String tone) {
  switch (tone) {
    case 'ok':
      return const Color(0xFF16A34A);
    case 'warn':
      return const Color(0xFFD97706);
    case 'danger':
      return const Color(0xFFDC2626);
    case 'neutral':
    default:
      return const Color(0xFF4B5563);
  }
}

/// Tone → background color for action buttons.
Color _actionBgColor(String tone) {
  switch (tone) {
    case 'ok':
      return const Color(0xFFDCFCE7);
    case 'warn':
      return const Color(0xFFFEF3C7);
    case 'danger':
      return const Color(0xFFFEE2E2);
    case 'neutral':
    default:
      return const Color(0xFFF3F4F6);
  }
}

// ─── LIST_ACTION_CARD widget ──────────────────────────────────────────────

/// LIST_ACTION_CARD -- LIST_CARD display + inline per-row action buttons.
///
/// Subscribes to a keyed Firestore collection, filters/sorts/searches, renders
/// a card list with thumbnail/title/subtitle/meta/badge and 2 action buttons
/// that perform updateEventRow writes via saveSend. One button may optionally
/// require a note bottom sheet before submission.
class ListActionCard extends StatefulWidget {
  const ListActionCard({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  // ── Per-screen in-flight state ──────────────────────────────────────────
  /// Set of row doc IDs currently being submitted, keyed by scrName.
  static final Map<String, Set<String>> _inflight = {};

  /// Clear per-screen state. Called from clearData (api.dart) and buildPage
  /// (ui_component.dart) on route change.
  static void registerScreenSession() {
    ScreenSession.ensure('ListActionCard.inflight', ListActionCard.clearState);
  }

  static void clearState(String scrName) {
    _inflight.remove(scrName);
  }

  @override
  State<ListActionCard> createState() => _ListActionCardState();
}

class _ListActionCardState extends State<ListActionCard> {
  String _code = '';
  String _gateCode = '';
  String _rawGateSearch = '';
  GateSlotConfig _gateSlotConfig = const GateSlotConfig('', '', '');

  /// True when the config ASKS for gating (`gateTable` authored), regardless of
  /// whether the rest of the gate config resolved. Drives fail-closed: a screen
  /// that requested gating must never fall back to showing every row.
  bool _gateIntended = false;

  // Parsed config (set once in initState)
  List<String> _textSegments = [];
  ListActionFields _fields = const ListActionFields('', '', '', '', '', '');
  List<ActionMetaEntry> _actionMetas = [];
  List<BadgeEntry> _badgeEntries = [];
  List<StatsDef> _statsDefs = [];
  bool _showStats =
      false; // W4: suppress strip when every StatsDef filter empty
  List<String> _searchFieldCodes = [];
  String _rawSearch = '';
  SortConfig _sort = const SortConfig('', false);
  String _routeStr = '';

  /// Per-button write DSLs: index 0 = button 1, index 1 = button 2.
  /// Each inner list has 4 entries matching [writeOpKeys] order.
  List<List<String>> _buttonWrites = [];
  String _noteTpl = '';

  // Local UI state
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  /// Length-guarded text segment accessor. 0-indexed.
  String _txt(int i, [String def = '']) =>
      _textSegments.length > i ? _textSegments[i] : def;

  /// Decode a component config field via autheniumDecode.
  String _cfg(String key) {
    final String raw = (widget.component[key] ?? '').toString();
    return autheniumDecode(raw) ?? raw;
  }

  @override
  void initState() {
    super.initState();
    ListActionCard.registerScreenSession();
    _initConfig();
    _subscribe();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initConfig() {
    // text: decode then split
    try {
      _textSegments = diamondTextToList(_cfg('text'));
    } catch (_) {
      _textSegments = [];
    }

    // fields: decode then parse
    _fields = parseListActionFields(_cfg('fields'));

    // badgeMap lives inside fields pos 5
    _badgeEntries = parseBadgeMap(_fields.rawBadgeMap);

    // actionMeta: decode then parse
    _actionMetas = parseActionMeta(_cfg('actionMeta'));

    // stats
    _statsDefs = parseStatsDefs(_cfg('stats'));
    // W4: only show the stats strip when at least one box has a real filter;
    // if every filter is empty the numbers just duplicate the header count.
    _showStats = _statsDefs.any((d) => d.filter.trim().isNotEmpty);

    // searchFields
    try {
      _searchFieldCodes = diamondTextToList(
        _cfg('searchFields'),
      ).where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      _searchFieldCodes = [];
    }

    // search: stored raw — filterDriverHomeDocs decodes internally
    _rawSearch = (widget.component['search'] ?? '').toString().trim();

    // sort: combined field◼dir
    _sort = parseSortConfig(_cfg('sort'));

    // route
    _routeStr = stripRouteWrapper(_cfg('route').trim());

    // Write DSLs per button: decoded via _cfg (autheniumDecode), trimmed by
    // collectButtonWrites (since _cfg does not trim).
    _buttonWrites = collectButtonWrites(_cfg);

    // gateSearch: stored raw — filterDriverHomeDocs decodes internally
    _rawGateSearch = (widget.component['gateSearch'] ?? '').toString().trim();

    // gateSlot: autheniumDecode (via _cfg) then parse
    _gateSlotConfig = parseGateSlot(_cfg('gateSlot'));

    // Intent flag: `gateTable` authored = this screen WANTS gating. Parsed here
    // (not in _subscribe) so it is set even when the subscription bails.
    _gateIntended = (widget.component['gateTable'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    _noteTpl = _cfg('note');
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);

    // Gate table subscription (slot-based approval queue gating).
    // Sits after _subscribe()'s early returns (lines 289,291), so a malformed
    // primary `table` also disables gating — benign, no _code means no primary
    // data to filter.
    // Skip subscription when gateSlot config is incomplete (I3: avoids a live
    // Firestore listener whose docs are never read).
    if (!_gateSlotConfig.isEmpty) {
      final String rawGateTable = (widget.component['gateTable'] ?? '')
          .toString()
          .trim();
      if (rawGateTable.isNotEmpty) {
        if (!rawGateTable.contains('//')) {
          // Bare name: subcollection under the main table's docId
          if (tp.tableDocId.isNotEmpty) {
            _gateCode = '$appVid/${tp.tableDocId}/$rawGateTable';
            subscribeToMapCollection(
              appVid,
              tp.tableDocId,
              rawGateTable,
              _gateCode,
            );
          }
        } else {
          final TablePath gtp = parseTablePath(rawGateTable);
          if (gtp.tableDocId.isNotEmpty) {
            _gateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
            subscribeToMapCollection(
              appVid,
              gtp.tableDocId,
              gtp.subColl,
              _gateCode,
            );
          }
        }
      }
    }
  }

  // ── Data pipeline ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _getServerFiltered() {
    // Unconditional observable read — MUST stay the first statement so the Obx
    // registers a dependency even when `_code` is '' (missing table config).
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );

    // Gate table observable read — unconditional (same Obx zero-obs rule).
    final List<Map<String, dynamic>> rawGateDocs =
        List<Map<String, dynamic>>.from(mapTableContent[_gateCode] ?? const []);

    final List<Map<String, dynamic>> searched = _rawSearch.isEmpty
        ? all
        : filterDriverHomeDocs(all, _rawSearch, widget.scrName);

    // Slot gate filter (D9: before sort/stats)
    final List<Map<String, dynamic>> gated = _applySlotGate(
      searched,
      rawGateDocs,
    );

    if (_sort.field.isNotEmpty) {
      gated.sort((a, b) {
        final num va = coerceNum(a[_sort.field]);
        final num vb = coerceNum(b[_sort.field]);
        return _sort.descending ? vb.compareTo(va) : va.compareTo(vb);
      });
    }

    return gated;
  }

  /// Apply slot gate filter. Identical semantics to ListCard._applySlotGate.
  ///
  /// Two distinct states, deliberately NOT the same:
  ///   * `gateTable` absent  → gating was never requested → docs pass through
  ///     untouched (back-compat for RewardReview and every pre-gating screen).
  ///   * `gateTable` present → gating WAS requested → any failure from here on
  ///     (unresolved config, dead subscription, no matching grant, unreadable
  ///     slot field, thrown exception) yields an EMPTY list, never the full
  ///     unfiltered set.
  ///
  /// The second rule is the whole point: an approval queue that cannot prove
  /// which slots the viewer holds must show nothing, not everything. Failing
  /// open here leaks every pending request to every approver — WITH working
  /// approve/reject buttons — while still looking gated.
  List<Map<String, dynamic>> _applySlotGate(
    List<Map<String, dynamic>> docs,
    List<Map<String, dynamic>> rawGateDocs,
  ) {
    // SS7.4: session identity for gate instrumentation. Uses the SAME
    // screenTx['#VID'] that filterDriverHomeDocs resolves {userVid} from
    // (driver_home_support.dart:303-306). Logging only, not a permission input.
    final String vid = sessionVidForLog();

    // Gating never requested → untouched. Log the raw gateTable value so
    // a device log can distinguish "gate never requested" from "gateTable
    // misspelled" from "gateTable present but _gateIntended somehow false."
    // Frequency: fires per Obx rebuild of _getServerFiltered, which re-runs
    // on ANY rebuild of the Obx subtree — including per-keystroke search
    // (the search field's onChanged setState). On non-gated screens: harmless
    // (pass-through is
    // the only branch that fires). On gated screens with a search bar:
    // one log line per keystroke. Accepted for now.
    // ponytail: if log noise bothers QA, suppress when outcome == previous call.
    if (!_gateIntended) {
      devPrint(
        'ListActionCard slot gate: _gateIntended=false '
        '(gateTable=${widget.component['gateTable']}) — pass-through',
      );
      return docs;
    }

    // Gating requested but the config did not fully resolve → FAIL CLOSED.
    if (_gateSlotConfig.isEmpty ||
        _gateCode.isEmpty ||
        _rawGateSearch.isEmpty) {
      devPrint(
        'ListActionCard slot gate: gateTable authored but gate '
        'incomplete (gateSlotEmpty=${_gateSlotConfig.isEmpty} '
        'gateCodeEmpty=${_gateCode.isEmpty} '
        'gateSearchEmpty=${_rawGateSearch.isEmpty}) '
        'vid=$vid visibleCount=0 — returning empty (fail-closed)',
      );
      // ponytail: growable (NOT const []) — callers .sort() this result
      return <Map<String, dynamic>>[];
    }

    try {
      final List<Map<String, dynamic>> matchedGrants = filterDriverHomeDocs(
        rawGateDocs,
        _rawGateSearch,
        widget.scrName,
      );

      if (matchedGrants.isEmpty) {
        devPrint(
          'ListActionCard slot gate: no grant docs match gateSearch '
          '"$_rawGateSearch" over ${rawGateDocs.length} gate docs '
          '(gateCode=$_gateCode) vid=$vid grantFound=false '
          'visibleCount=0 — returning empty (fail-closed)',
        );
        return <Map<String, dynamic>>[];
      }

      final Set<String> allConcrete = {};
      final Set<String> allWildcardLevels = {};
      final List<String> rawSlotValues = []; // I1: actual per-grant raw values
      for (final grantDoc in matchedGrants) {
        final String rawSlot = (grantDoc[_gateSlotConfig.slotField] ?? '')
            .toString()
            .trim();
        rawSlotValues.add(rawSlot);
        final SlotTerms terms = parseSlotTerms(rawSlot);
        allConcrete.addAll(terms.concrete);
        allWildcardLevels.addAll(terms.wildcardLevels);
      }

      if (allConcrete.isEmpty && allWildcardLevels.isEmpty) {
        devPrint(
          'ListActionCard slot gate: ${matchedGrants.length} grant '
          'doc(s) matched but slot field "${_gateSlotConfig.slotField}" '
          'yielded no terms (raw sc=$rawSlotValues) '
          'vid=$vid grantFound=true '
          'visibleCount=0 — returning empty (fail-closed)',
        );
        return <Map<String, dynamic>>[];
      }

      final List<Map<String, dynamic>> kept = filterBySlotGate(
        docs,
        allConcrete,
        allWildcardLevels,
        _gateSlotConfig.pointerField,
        _gateSlotConfig.levelField,
      );
      devPrint(
        'ListActionCard slot gate: grants=${matchedGrants.length} '
        'concrete=$allConcrete wildcardLevels=$allWildcardLevels '
        'ptr="${_gateSlotConfig.pointerField}" '
        'lvl="${_gateSlotConfig.levelField}" '
        'vid=$vid grantFound=true visibleCount=${kept.length}',
      );
      return kept;
    } catch (e) {
      // Any gate failure is a visibility failure → show nothing, never throw.
      devPrint(
        'ListActionCard slot gate: ERROR vid=$vid '
        'visibleCount=0 — returning empty (fail-closed): $e',
      );
      return <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _applySearchBar(List<Map<String, dynamic>> docs) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty || _searchFieldCodes.isEmpty) return docs;
    return docs.where((d) {
      for (final field in _searchFieldCodes) {
        final String val = (d[field] ?? '').toString().toLowerCase();
        if (val.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  // ── Row identity ─────────────────────────────────────────────────────────

  /// Row identity for in-flight tracking. Uses Firestore doc `__docId` if
  /// present (map subscription injects it), else falls back to a stable hash.
  String _rowId(Map<String, dynamic> doc) {
    final String docId = (doc['__docId'] ?? '').toString();
    if (docId.isNotEmpty) return docId;
    return doc.hashCode.toString();
  }

  bool _isInflight(String rowId) {
    return ListActionCard._inflight[widget.scrName]?.contains(rowId) ?? false;
  }

  void _setInflight(String rowId, bool value) {
    if (value) {
      (ListActionCard._inflight[widget.scrName] ??= <String>{}).add(rowId);
    } else {
      ListActionCard._inflight[widget.scrName]?.remove(rowId);
    }
    if (mounted) setState(() {});
  }

  /// Reset a note slot's stored value + input text back to empty. Called on
  /// every exit path that does NOT submit, and right after a submit reads it.
  void _clearNoteSlot(int notePosition) {
    final InputController? ctrl = txfController[widget.scrName]?[notePosition];
    if (ctrl != null) {
      ctrl.finalData = emptyString;
      ctrl.controller.text = '';
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _onCardTap(Map<String, dynamic> doc) {
    if (_routeStr.isEmpty) return;
    writeRouteParamsFromRow(
      widget.component['routeParams']?.toString(),
      doc,
      widget.scrName,
    );
    if (routeExist(_routeStr)) {
      routeStack.push(_routeStr);
      gotoRoute(_routeStr);
    }
  }

  Future<void> _onActionTap(
    Map<String, dynamic> doc,
    List<String> writes,
    ActionMetaEntry meta,
    String rowId,
  ) async {
    if (!writes.any((s) => s.isNotEmpty)) return;
    if (_isInflight(rowId)) return; // guard double-tap

    // All-or-nothing: resolve {field} tokens across ALL non-empty DSLs for
    // this button BEFORE any UI. If any single token in any single DSL cannot
    // be resolved, abort the entire submission (no note sheet, no write).
    final List<String> resolvedWrites = List<String>.filled(
      writeOpKeys.length,
      '',
    );
    for (int i = 0; i < writeOpKeys.length; i++) {
      if (writes[i].isEmpty) continue;
      final String? resolved = resolveActionTokensOrAbort(
        writes[i],
        doc,
        widget.scrName,
      );
      if (resolved == null) {
        devPrint(
          'WARN ListActionCard: unresolved token in ${writeOpKeys[i]} DSL, '
          'aborting all writes for this button. '
          'rowId=$rowId, doc keys=${doc.keys.toList()}',
        );
        return; // nothing written yet, nothing to clean up
      }
      resolvedWrites[i] = resolved;
    }

    // Only once ALL DSLs are known-good do we ask for a note.
    if (meta.notePosition != null) {
      final bool sent = await _showNoteSheet(meta.notePosition!);
      if (!sent) {
        _clearNoteSlot(meta.notePosition!);
        return; // user dismissed without sending
      }
    }

    _setInflight(rowId, true);

    // Build a sanitised component copy via the pure helper (testable).
    // `.from(… as Map)` not `as Map<String, dynamic>`: server JSON is dynamic
    // BY DESIGN, so a Map<dynamic, dynamic> would throw on a strict cast.
    // Matches custody_event_submit:278 / custody_count_submit:954.
    final Map<String, dynamic> saveSendComponent = buildSaveSendComponent(
      Map<String, dynamic>.from(widget.component as Map),
      resolvedWrites,
      meta.flag,
    );

    // GPS-less timestamp + locString (time-only, no real GPS).
    final int timeStamp = await getRealTime();
    final OtqState locSensor = OtqState();
    locSensor.nowTime = DateTime.fromMillisecondsSinceEpoch(timeStamp);
    final String locString = getLocationString('', '', '', locSensor);

    // C2: 5th arg is the history-row appVid (forwarded to appendToSheet); all
    // live saveSend callers pass defaultVid(). The table vid still reaches
    // Firestore through the DSL's own ⭘tablevid◼… segment.
    saveSend(
      timeStamp,
      widget.scrName,
      saveSendComponent,
      locString,
      defaultVid(),
    );

    // saveSend read the note slot synchronously into `row`; safe to clear now.
    if (meta.notePosition != null) {
      _clearNoteSlot(meta.notePosition!);
    }

    // W3: offline saveSend returns instantly and the row will never disappear
    // (no listener update), so release the buttons immediately after the
    // snackbar. Online, the row drops out reactively when its `st` stops
    // matching the search filter; the timer is a safety net.
    if (!internetConnected()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tersimpan offline \u{2014} dikirim otomatis saat online',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      _setInflight(rowId, false);
    } else {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _setInflight(rowId, false);
      });
    }
  }

  /// Show note bottom sheet. Returns true if user tapped send (note written
  /// to txfController), false if dismissed.
  Future<bool> _showNoteSheet(int notePosition) async {
    // Ensure txfController slot exists.
    txfControllerCheck(widget.scrName, notePosition);

    final TextEditingController noteCtrl = TextEditingController();
    bool sent = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title (text slot 7, 0-indexed)
                  if (_txt(7).isNotEmpty)
                    Text(
                      _txt(7),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (_txt(7).isNotEmpty) const SizedBox(height: 8),
                  // Body (text slot 8)
                  if (_txt(8).isNotEmpty)
                    Text(
                      _txt(8),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  if (_txt(8).isNotEmpty) const SizedBox(height: 16),
                  // Input field
                  TextFormField(
                    controller: noteCtrl,
                    maxLines: 3,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: _txt(9),
                      hintText: _txt(10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Send button (disabled until non-empty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: noteCtrl.text.trim().isEmpty
                          ? null
                          : () {
                              // Write to txfController.
                              txfController[widget.scrName]![notePosition]!
                                  .finalData = noteCtrl.text
                                  .trim();
                              txfController[widget.scrName]![notePosition]!
                                  .controller
                                  .text = noteCtrl.text
                                  .trim();
                              sent = true;
                              Navigator.of(ctx).pop();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE2E2),
                        foregroundColor: const Color(0xFFDC2626),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _txt(11, 'Kirim'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    noteCtrl.dispose();
    return sent;
  }

  // ── Template resolution ──────────────────────────────────────────────────

  String _resolve(String template, Map<String, dynamic> doc) =>
      resolveMapTokens(template, doc, const <String, String>{});

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Unconditional observable read — prevents Obx zero-observable crash.
      final List<Map<String, dynamic>> serverFiltered = _getServerFiltered();

      final List<int> statsCounts = _showStats
          ? computeStatsCounts(_statsDefs, serverFiltered)
          : const [];

      final List<Map<String, dynamic>> displayed = _applySearchBar(
        serverFiltered,
      );

      final double availableH = MediaQuery.of(context).size.height * 0.79;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              if (_txt(0).isNotEmpty) ...[
                _buildHeader(serverFiltered.length),
                const SizedBox(height: 10),
              ],
              // ── Stats strip ──
              if (_showStats && statsCounts.isNotEmpty) ...[
                _buildStatsStrip(statsCounts),
                const SizedBox(height: 10),
              ],
              // ── Search bar ──
              if (_searchFieldCodes.isNotEmpty) ...[
                _buildSearchBar(),
                const SizedBox(height: 14),
              ],
              // ── Card list ──
              Expanded(
                child: displayed.isEmpty
                    ? _buildEmpty()
                    : _buildFlat(displayed),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ── Subwidgets ───────────────────────────────────────────────────────────

  Widget _buildHeader(int totalCount) {
    final String title = _txt(0);
    final String subtitle = _txt(1);
    final String countLabel = _txt(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (countLabel.isNotEmpty)
              Text(
                '$totalCount $countLabel',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
          ],
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsStrip(List<int> counts) {
    return Row(
      children: [
        for (int i = 0; i < _statsDefs.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${counts.length > i ? counts[i] : 0}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statsDefs[i].label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextFormField(
      controller: _searchCtrl,
      keyboardType: TextInputType.text,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
        hintText: _txt(3, 'Cari'),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        _txt(4, 'Tidak ada data'),
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
    );
  }

  ListView _buildFlat(List<Map<String, dynamic>> docs) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final doc in docs) _buildCard(doc),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Shared grey placeholder for the thumbnail — used both when the URL is not
  /// a parseable absolute URL (W1) and by Image.network's errorBuilder.
  Widget _thumbPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image, size: 20, color: Color(0xFF9CA3AF)),
    );
  }

  Widget _buildCard(Map<String, dynamic> doc) {
    final String title = _resolve(_fields.titleTpl, doc);
    final String subtitle = _resolve(_fields.subtitleTpl, doc);
    final String meta = _resolve(_fields.metaTpl, doc);
    final String note = resolveNoteTemplate(_noteTpl, doc);
    final String rowId = _rowId(doc);
    final bool inflight = _isInflight(rowId);

    // Badge
    final String badgeValue = _fields.badgeField.isNotEmpty
        ? (doc[_fields.badgeField] ?? '').toString().trim()
        : '';
    final BadgeEntry? badge = badgeValue.isNotEmpty
        ? lookupBadge(_badgeEntries, badgeValue)
        : null;

    // Thumbnail
    // A multi-image field holds its urls joined by ◇; the row thumb shows the
    // first. The joined string must not reach Image.network — see
    // splitImageUrls.
    final List<String> imageUrls = _fields.imageField.isNotEmpty
        ? splitImageUrls((doc[_fields.imageField] ?? '').toString())
        : const <String>[];
    final String imageUrl = imageUrls.isEmpty ? '' : imageUrls.first;
    // W1: only hand a parseable absolute URL to Image.network — a malformed URL
    // throws inside _Uri.resolve at paint time, which errorBuilder cannot
    // reliably intercept (live crash class in this repo).
    final bool thumbOk =
        imageUrl.isNotEmpty && (Uri.tryParse(imageUrl)?.hasScheme ?? false);

    // Fallback subtitle
    final String displaySubtitle = subtitle.trim().isNotEmpty
        ? subtitle
        : _txt(12);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _onCardTap(doc),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    if (imageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: thumbOk
                            ? Image.network(
                                imageUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _thumbPlaceholder(),
                              )
                            : _thumbPlaceholder(),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Title + meta
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (meta.trim().isNotEmpty)
                                Text(
                                  meta,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                          // Subtitle
                          if (displaySubtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              displaySubtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          // Note (display line — unrelated to the notePosition bottom sheet)
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              note,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // Badge
                if (badge != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusBgColor(badge.tier),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor(badge.tier),
                      ),
                    ),
                  ),
                ],
                // Action buttons
                if (_actionMetas.isNotEmpty &&
                    (_buttonWrites.isNotEmpty &&
                        _buttonWrites.any(
                          (w) => w.any((s) => s.isNotEmpty),
                        ))) ...[
                  const SizedBox(height: 10),
                  _buildActionRow(doc, rowId, inflight),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(
    Map<String, dynamic> doc,
    String rowId,
    bool inflight,
  ) {
    final List<Widget> buttons = [];

    // Action 1
    if (_actionMetas.isNotEmpty && buttonHasWrites(_buttonWrites, 0)) {
      buttons.add(
        Expanded(
          child: _buildActionButton(
            label: _txt(5),
            meta: _actionMetas[0],
            writes: _buttonWrites[0],
            doc: doc,
            rowId: rowId,
            inflight: inflight,
          ),
        ),
      );
    }

    // Action 2
    if (_actionMetas.length > 1 && buttonHasWrites(_buttonWrites, 1)) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 10));
      buttons.add(
        Expanded(
          child: _buildActionButton(
            label: _txt(6),
            meta: _actionMetas[1],
            writes: _buttonWrites[1],
            doc: doc,
            rowId: rowId,
            inflight: inflight,
          ),
        ),
      );
    }

    return Row(children: buttons);
  }

  Widget _buildActionButton({
    required String label,
    required ActionMetaEntry meta,
    required List<String> writes,
    required Map<String, dynamic> doc,
    required String rowId,
    required bool inflight,
  }) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: inflight
            ? null
            : () => _onActionTap(doc, writes, meta, rowId),
        style: ElevatedButton.styleFrom(
          backgroundColor: _actionBgColor(meta.tone),
          foregroundColor: _actionFgColor(meta.tone),
          disabledBackgroundColor: const Color(0xFFF3F4F6),
          disabledForegroundColor: const Color(0xFF9CA3AF),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: inflight
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
