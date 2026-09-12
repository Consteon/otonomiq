import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // mapTableContent, devPrint, routeStack, gotoRoute, routeExist
import '../global2.dart' show stringToIconData; // config-named icons
import '../sdui_spec.dart';
import '../theme_tokens.dart'; // OtqPalette, otqContentInset, otqSectionHead
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs, coerceNum, stripRouteWrapper
import 'list_card_support.dart'; // parseLimit, applyLimit
import 'panel_card_support.dart'; // parseTablePath, TablePath, statusColor, statusBgColor
import 'timeline_card_support.dart';
// `show` is load-bearing: timeline_ledger_support and list_card_support each
// declare a public `BadgeEntry` / `parseBadgeMap`, so an unrestricted import of
// both is an ambiguous-import error. Only the formatter is needed here.
import 'timeline_ledger_support.dart' show formatEpochHHmm;

/// TIMELINE_CARD — day-grouped timeline card: a left dot rail, a big time set
/// inline with its label, and a status chip inferred from the newest row. The
/// chip draws on the FIRST day separator when there is one, and falls back to
/// the header otherwise (groupByDay FALSE / empty list / blank time field).
///
/// Fully config-driven (spec section 2): `vidtable`/`table`/`search`,
/// `sortField`/`sortDir`, `limit`, `moreRoute`, `row`, `dotMap`,
/// `chipField`+`chipMap`, `groupByDay`, `text`. No hardcoded labels — every
/// display string comes from `text` or from the `row` template.
///
/// Holds NO per-screen state: everything is derived per build inside the Obx, so
/// there is nothing to key by scrName and nothing to reset in `clearData`.
class TimelineCard extends StatefulWidget {
  const TimelineCard({
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

  @override
  State<TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<TimelineCard> {
  late final SduiSpec _spec;

  /// vid-scoped subscription key; `''` when `table` is absent/unusable.
  String _code = '';

  List<String> _rowSlots = const [];
  String _timeField = '';
  Map<String, String> _dotMap = const {};
  String _chipField = '';
  List<ChipEntry> _chipMap = const [];
  bool _groupByDay = true;
  int _limit = 0;
  String _moreRoute = '';
  String _rawSearch = '';
  String _sortField = '';
  bool _sortDesc = false;

  /// Vertika v6 log list. Absent or unrecognised `variant` keeps the card every
  /// screen draws today.
  bool _v6 = false;

  /// Icon NAMES (see `stringToIconData`) for `row` slots 2 and 3, in that
  /// order. Config, never hardcoded: the design puts a pin on the location and
  /// a method mark on the note, but which icon that is belongs to the tenant.
  List<String> _metaIcons = const [];

  /// Blank-aware `text` segment accessor.
  ///
  /// NOT a plain `_spec.text(i)`: SduiSpec.text is length-guard only, so its
  /// own `def` fires ONLY when the index is out of range. A PRESENT-but-blank
  /// ◆ slot (`'…◆   ◆…'`) comes back as whitespace. All five spec section 5
  /// segments are optional and must read as EMPTY when blank, so they all go
  /// through here.
  ///
  /// There is deliberately NO `def` parameter: not one segment has a hardcoded
  /// fallback (see `_empty()` — "no hardcoded labels" is this class's
  /// contract), so a default parameter would be dead API inviting someone to
  /// bake a label back in.
  String _seg(int i) {
    final String v = _spec.text(i);
    return v.trim().isEmpty ? '' : v;
  }

  @override
  void initState() {
    super.initState();
    _spec = SduiSpec(widget.component);
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    // row: decoded + ◆-split by SduiSpec.list (returns const [] for empty, so
    // no diamondTextToList('') => [''] trap).
    _rowSlots = _spec.list('row');
    _timeField = timeFieldOf(_rowSlots);

    _dotMap = parseDotMap(_spec.str('dotMap'));
    _chipField = _spec.str('chipField');
    _chipMap = parseChipMap(_spec.str('chipMap'));

    // Absent or anything but FALSE => grouped (spec section 2 states only the
    // FALSE behaviour; grouping is the widget's headline feature).
    _groupByDay = _spec.str('groupByDay', 'TRUE').toUpperCase() != 'FALSE';

    // limit is a plain NUMBER, read RAW — never through SduiSpec.str, which
    // trims and autheniumDecodes a value that is neither ◼- nor ⭘-encoded.
    _limit = parseLimit(widget.component['limit']);

    _moreRoute = stripRouteWrapper(_spec.str('moreRoute'));

    // search stays RAW: filterDriverHomeDocs autheniumDecodes and resolves
    // {token}s internally, in that order.
    _rawSearch = (widget.component['search'] ?? '').toString().trim();

    _sortField = _spec.str('sortField');
    _sortDesc = _spec.str('sortDir').toLowerCase() == 'desc';

    _v6 = _spec.str('variant').toLowerCase() == 'v6';
    _metaIcons = _spec.list('metaIcons');
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    // vid-scoped key prevents a cross-tenant subscription collision.
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  /// search filter + sort. Fail-CLOSED: a throwing search yields an empty list,
  /// never the unfiltered set.
  List<Map<String, dynamic>> _filtered() {
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );

    List<Map<String, dynamic>> out = all;
    if (_rawSearch.isNotEmpty) {
      try {
        out = List<Map<String, dynamic>>.from(
          filterDriverHomeDocs(all, _rawSearch, widget.scrName),
        );
      } catch (e) {
        devPrint(
          '[timelineCard] search FAILED CLOSED (empty list) for '
          '"$_rawSearch" on ${widget.scrName}: $e',
        );
        return const <Map<String, dynamic>>[];
      }
    }

    if (_sortField.isNotEmpty) {
      out.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final num va = coerceNum(a[_sortField]);
        final num vb = coerceNum(b[_sortField]);
        return _sortDesc ? vb.compareTo(va) : va.compareTo(vb);
      });
    }
    return out;
  }

  /// Header "see all" tap. Convention 1: routeStack.push BEFORE gotoRoute.
  void _onMoreTap() {
    if (_moreRoute.isEmpty || !routeExist(_moreRoute)) return;
    routeStack.push(_moreRoute);
    gotoRoute(_moreRoute);
  }

  // ── palette ────────────────────────────────────────────────────────────
  //
  // Every neutral this card paints, in one place. TIER colours still come from
  // the shared `statusColor` / `statusBgColor` (panel_card_support) — the
  // redesign does NOT fork that palette, it only adds local neutrals and the
  // link accent. All five values below clear WCAG AA (>= 4.5:1) on both the
  // white card and the `_panel` sheet.
  static const Color _ink = Color(0xFF0F172A); // slate-900 — title, time
  static const Color _body = Color(0xFF334155); // slate-700 — description
  static const Color _muted = Color(0xFF64748B); // slate-500 — label/note/day
  static const Color _line = Color(0xFFE2E8F0); // slate-200 — rail + rule
  static const Color _panel = Color(0xFFF8FAFC); // slate-50  — inner sheet
  static const Color _panelEdge = Color(0xFFEEF2F6);
  static const Color _cardEdge = Color(0xFFEAEDF1);
  static const Color _accent = Color(0xFF0E7490); // cyan-700 — 4.9:1 on white

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Observable read FIRST and unconditionally — an Obx whose build path can
      // reach zero observable reads throws at runtime.
      final List<Map<String, dynamic>> rows = _filtered();
      // applyLimit returns the SAME list instance when _limit <= 0 (and when
      // the cap is >= length), so `displayed` can literally BE `rows`. That is
      // safe only because _filtered() already builds a fresh List.from(...)
      // every build. Do NOT add a defensive copy here — it would allocate on
      // every frame to protect against an alias that is already private.
      final List<Map<String, dynamic>> displayed = applyLimit(rows, _limit);
      final DateTime now = DateTime.now();

      // v6 renders a flat log list instead of a card: no surface, no rail, a
      // chip on EVERY row. The summary chip is deliberately not inferred here —
      // in v6 that answer lives in the attendance strip, and inferChip is the
      // most expensive thing on this path.
      if (_v6) return _buildV6(displayed, now);

      // Chip reads the UNCAPPED list. applyLimit runs after the sort, so
      // rows.first and displayed.first are the same object whenever the list is
      // non-empty — the two are structurally equivalent, and reading the
      // uncapped list makes "the newest event" obviously cap-independent.
      final TimelineChip chip = inferChip(
        sortedDocs: rows,
        chipField: _chipField,
        chipMap: _chipMap,
        timeField: _timeField,
        emptyLabel: _seg(3),
        now: now,
      );

      // Day groups are computed HERE, not inside _timeline, because the header
      // has to know whether the chip will land on the first day separator.
      final List<TimelineDayGroup> groups = _groupByDay && displayed.isNotEmpty
          ? groupDocsByDay(displayed, _timeField, _seg(2), now)
          : const <TimelineDayGroup>[];

      // The chip renders in exactly ONE place, never two (a duplicate would
      // also break the widget tests' findsOneWidget). Preferred slot is the
      // first day separator; it falls back to the header whenever no separator
      // will be emitted at all — groupByDay FALSE, an empty list, or a blank
      // `row` slot 0 time token (which leaves every group label '').
      final bool chipInline =
          chip.label.isNotEmpty &&
          groups.isNotEmpty &&
          groups.first.label.isNotEmpty;

      final String title = _seg(0);
      final String moreLabel = _seg(1);
      final bool showMore = moreLabel.isNotEmpty && _moreRoute.isNotEmpty;
      final bool showHeader =
          title.isNotEmpty ||
          showMore ||
          (!chipInline && chip.label.isNotEmpty);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardEdge),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (showHeader)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 0, 12),
                  child: _header(
                    title,
                    moreLabel,
                    showMore,
                    chipInline ? null : chip,
                  ),
                ),
              // Inner sheet: the timeline sits on its own surface so the header
              // reads as a separate layer (mock ronde 2). One Container, no
              // shadow — the border alone carries the elevation.
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _panelEdge),
                ),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                // ponytail: a plain Column builds every row (no lazy viewport).
                // Fine for a card capped by `limit`, and for the uncapped
                // "Lihat Semua" page the host SingleChildScrollView in
                // main_page still scrolls it. Switch to ListView.builder only
                // if a tenant renders hundreds.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (displayed.isEmpty)
                      _empty()
                    else
                      ..._timeline(displayed, groups, chipInline ? chip : null),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Card header: title on the left, optional chip + "see all" link on the
  /// right. [chip] is null when the chip is being drawn on the first day
  /// separator instead.
  Widget _header(
    String title,
    String moreLabel,
    bool showMore,
    TimelineChip? chip,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: _ink,
            ),
          ),
        ),
        if (chip != null && chip.label.isNotEmpty) _chipPill(chip),
        if (showMore)
          TextButton(
            onPressed: _onMoreTap,
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // 44 high, not 36: this is the card's only tap target.
              minimumSize: const Size(0, 44),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              moreLabel,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  /// Status pill: tier dot + label.
  ///
  /// Casing is NOT forced — the mock's all-caps look comes from the sheet's
  /// `chipMap` label, so a tenant that authors sentence case keeps it (this
  /// class's "no hardcoded labels" contract covers transforms too).
  Widget _chipPill(TimelineChip chip) {
    final Color tone = statusColor(chip.tier);
    // The shared statusColor/statusBgColor pairs land at 3.1–3.9:1 — under AA
    // for 11px text. Darkening the tone 25% toward black lifts every tier to
    // >= 4.7:1 on its own background without forking the shared palette (which
    // half a dozen other widgets read).
    final Color ink = Color.lerp(tone, const Color(0xFF000000), 0.25)!;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: statusBgColor(chip.tier),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            chip.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state. NO hardcoded fallback label: `text` segment 5 is the only
  /// source, which keeps this class's "no hardcoded labels" contract true and
  /// matches every other `_seg` call (all default to `''`). A blank segment 5
  /// deliberately renders an empty spacer rather than inventing an Indonesian
  /// string on a tenant that never asked for one.
  // ── Vertika v6 log list ──────────────────────────────────────────────────

  /// Flat list: shared section head, day headings, one row per doc.
  ///
  /// No card and no inner panel. v6 separates page blocks with a 1 dp rule
  /// (drawn by [otqSectionHead]) rather than boxing each one, so a surface here
  /// would read as a second, competing layer.
  Widget _buildV6(List<Map<String, dynamic>> displayed, DateTime now) {
    final List<TimelineDayGroup> groups = _groupByDay && displayed.isNotEmpty
        ? groupDocsByDay(displayed, _timeField, _seg(2), now)
        : const <TimelineDayGroup>[];

    final String title = _seg(0);
    final String moreLabel = _seg(1);
    final bool showMore = moreLabel.isNotEmpty && _moreRoute.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title.isNotEmpty || showMore)
          otqSectionHead(
            context: context,
            label: title,
            v6: true,
            linkLabel: showMore ? moreLabel : '',
            onLink: showMore ? _onMoreTap : null,
          ),
        Padding(
          padding: otqContentInset(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: displayed.isEmpty
                ? <Widget>[_empty()]
                : _timelineV6(displayed, groups),
          ),
        ),
      ],
    );
  }

  List<Widget> _timelineV6(
    List<Map<String, dynamic>> docs,
    List<TimelineDayGroup> groups,
  ) {
    if (groups.isEmpty) {
      return <Widget>[
        for (int i = 0; i < docs.length; i++)
          _rowTileV6(docs[i], i == docs.length - 1),
      ];
    }
    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final TimelineDayGroup grp = groups[g];
      if (grp.label.isNotEmpty) out.add(_daySeparatorV6(grp.label, g));
      final bool lastGroup = g == groups.length - 1;
      for (int i = 0; i < grp.docs.length; i++) {
        out.add(_rowTileV6(grp.docs[i], lastGroup && i == grp.docs.length - 1));
      }
    }
    return out;
  }

  /// Day heading. Same ValueKey as the classic separator — the two never render
  /// together, and the tests count separators through it either way.
  Widget _daySeparatorV6(String label, int index) => Padding(
    key: ValueKey<String>('tlcard-day-$index'),
    padding: EdgeInsets.only(top: index == 0 ? 0 : 14, bottom: 2),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: OtqPalette.v6MutedFg,
      ),
    ),
  );

  /// One log row: `44 dp` time · `10 dp` dot · the rest.
  ///
  /// NOT tappable. v6 shows a press state, but this widget has no per-row route
  /// (spec section 10, v1 scope) — a row that highlights and then does nothing
  /// is worse than a row that plainly does not respond.
  Widget _rowTileV6(Map<String, dynamic> doc, bool isLast) {
    final String time = formatEpochHHmm(docEpochMs(doc, _timeField));
    final String name = resolveRowSlot(_rowSlots, 1, doc);
    final List<String> meta = <String>[
      resolveRowSlot(_rowSlots, 2, doc),
      resolveRowSlot(_rowSlots, 3, doc),
    ];

    final String dotValue = _chipField.isEmpty
        ? ''
        : (doc[_chipField] ?? '').toString().trim();
    final Color dotColor = statusColor(_dotMap[dotValue] ?? 'muted');
    final TimelineChip? chip = rowChip(doc, _chipField, _chipMap);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: isLast
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: OtqPalette.v6Border)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                time,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: OtqPalette.foreground,
                  // Tabular: without it the times jitter column to column and
                  // the 44 dp gutter stops reading as a column at all.
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (name.isNotEmpty || chip != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: OtqPalette.foreground,
                          ),
                        ),
                      ),
                      // ★ INFLEXIBLE beside the Expanded name. A Flexible chip
                      // here would split the free space 50/50 before either
                      // child is measured and strand the chip mid-row.
                      if (chip != null && chip.label.isNotEmpty)
                        _chipPillV6(chip),
                    ],
                  ),
                if (meta.any((String m) => m.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: _metaLine(meta),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Meta line: the row's last two slots, each optionally prefixed by an icon.
  ///
  /// One `Text.rich`, not a Wrap of Rows: a Wrap hands its children UNBOUNDED
  /// width, so a Row inside it cannot use Flexible and a long location would
  /// overflow the line instead of wrapping. Inline spans wrap like text, which
  /// is what they are.
  Widget _metaLine(List<String> meta) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < meta.length; i++) {
      if (meta[i].isEmpty) continue;
      if (spans.isNotEmpty) {
        spans.add(const WidgetSpan(child: SizedBox(width: 12)));
      }
      final String iconName = i < _metaIcons.length ? _metaIcons[i].trim() : '';
      if (iconName.isNotEmpty) {
        // Guarded on blank because stringToIconData answers help_outline for
        // anything it does not know — a blank name would draw a "?" bubble.
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                stringToIconData(iconName),
                size: 15,
                color: OtqPalette.v6MutedFg,
              ),
            ),
          ),
        );
      }
      spans.add(TextSpan(text: meta[i]));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: OtqPalette.v6MutedFg,
      ),
    );
  }

  /// Per-row status pill. Same contrast correction as [_chipPill] — see there
  /// for why the shared tier colour is darkened 25% before it carries text.
  Widget _chipPillV6(TimelineChip chip) {
    final Color ink = Color.lerp(
      statusColor(chip.tier),
      const Color(0xFF000000),
      0.25,
    )!;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      height: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: statusBgColor(chip.tier),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        chip.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
          color: ink,
        ),
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Text(_seg(4), style: const TextStyle(fontSize: 13, color: _muted)),
    ),
  );

  /// [groups] empty => flat render (groupByDay FALSE). [inlineChip] is drawn on
  /// the FIRST separator only.
  List<Widget> _timeline(
    List<Map<String, dynamic>> docs,
    List<TimelineDayGroup> groups,
    TimelineChip? inlineChip,
  ) {
    if (groups.isEmpty) {
      return <Widget>[
        for (int i = 0; i < docs.length; i++)
          _rowTile(docs[i], i == docs.length - 1),
      ];
    }

    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final TimelineDayGroup grp = groups[g];
      if (grp.label.isNotEmpty) {
        out.add(_daySeparator(grp.label, g, g == 0 ? inlineChip : null));
      }
      final bool lastGroup = g == groups.length - 1;
      for (int i = 0; i < grp.docs.length; i++) {
        out.add(_rowTile(grp.docs[i], lastGroup && i == grp.docs.length - 1));
      }
    }
    return out;
  }

  /// Day separator: date on the left, then EITHER the status chip (first group)
  /// or a hairline rule running to the edge.
  ///
  /// The label is a plain Text, never Flexible: a Flexible and an Expanded in
  /// one Row split the free space 50/50 BEFORE either child is measured, which
  /// would ellipsize `HARI INI · 31 AUG 2026` on a 360dp screen.
  ///
  /// The ValueKey is a real debugging affordance AND the seam the widget tests
  /// use to count separators without re-running the date formatter (a test that
  /// recomputes the production expression certifies nothing).
  Widget _daySeparator(String label, int index, TimelineChip? chip) => Padding(
    key: ValueKey<String>('tlcard-day-$index'),
    padding: EdgeInsets.only(top: index == 0 ? 0 : 16, bottom: 12),
    child: Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: _muted,
          ),
        ),
        if (chip != null && chip.label.isNotEmpty) ...<Widget>[
          const Spacer(),
          _chipPill(chip),
        ] else ...<Widget>[
          const SizedBox(width: 10),
          const Expanded(
            child: ColoredBox(color: _line, child: SizedBox(height: 1)),
          ),
        ],
      ],
    ),
  );

  Widget _rowTile(Map<String, dynamic> doc, bool isLast) {
    final int ms = docEpochMs(doc, _timeField);
    final String time = formatEpochHHmm(ms);
    final String label = resolveRowSlot(_rowSlots, 1, doc);
    final String desc = resolveRowSlot(_rowSlots, 2, doc);
    final String note = resolveRowSlot(_rowSlots, 3, doc);

    // dotMap is keyed on the SAME field as chipField (spec section 2). An
    // unmapped value falls back to `muted`, never to statusColor's default
    // green — which is exactly why `muted` was added to the shared palette.
    final String dotValue = _chipField.isEmpty
        ? ''
        : (doc[_chipField] ?? '').toString().trim();
    final Color dotColor = statusColor(_dotMap[dotValue] ?? 'muted');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Rail FIRST (redesign): dot + connector run down the left edge, so
          // the time is free to sit inline with the label instead of taking a
          // fixed 52dp column that squeezed the description on small screens.
          SizedBox(
            width: 16,
            child: Column(
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                // Expanded is legal here: IntrinsicHeight + stretch gives this
                // Column a tight height. Same shape as otq_txt's history rail.
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _line,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 2 : 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (time.isNotEmpty || label.isNotEmpty)
                    Row(
                      // Baseline, not centre: the 21px time and the 12.5px
                      // label sit on one line and must share a text baseline.
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              height: 1.05,
                              color: _ink,
                            ),
                          ),
                        if (time.isNotEmpty && label.isNotEmpty)
                          const SizedBox(width: 10),
                        if (label.isNotEmpty)
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: _muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: _body,
                        ),
                      ),
                    ),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        note,
                        style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: 0.2,
                          color: _muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
