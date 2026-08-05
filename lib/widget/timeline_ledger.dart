import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';
import 'timeline_ledger_support.dart';
import 'timeline_periodic_support.dart';

/// TIMELINE variant `ledger` -- config-generic grouped + expandable audit
/// timeline. Supports two modes:
/// - **Grouped** (`groupField` non-empty): docs grouped by field value, one
///   card per group, expand/collapse to see item lines.
/// - **Flat** (`groupField` empty): one card per doc, no expand.
///
/// All labels, fields, and badge maps come from component config -- zero
/// hardcoded strings or colors. Reuses the keyed-doc subscription pipeline
/// from TimelinePeriodic.
///
/// Condition tokens (`{vehicleId}` etc.) resolve via [resolveScreenTxTokens]
/// which reads bare screenTx keys directly. Do NOT use
/// [resolveDriverCurlyTokens] -- its hardcoded `case 'vehicleId'` reads from
/// DriverHomeState (driver session vehicle), which SHADOWS the bare key that
/// routeParams dispatches and is EMPTY for admin/supervisor users.
class TimelineLedger extends StatefulWidget {
  const TimelineLedger({
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
  State<TimelineLedger> createState() => _TimelineLedgerState();
}

class _TimelineLedgerState extends State<TimelineLedger> {
  List<PeriodOption> _periods = [];
  int _selectedMs = 604800000;
  String _eventCode = '';
  String _timeField = 't';
  String _groupField = '';
  String _groupField2 = '';
  String _sectionText = '';
  String _badgeField = '';
  String _headText = '';
  String _titleText = '';
  String _subText = '';
  String _itemText = '';
  String _refText = '';
  bool _expandable = true;
  String _titleTemplate = '';
  String _subtitleTemplate = '';

  // Badge map lookup: value -> entry (carries palette index).
  final Map<String, BadgeEntry> _badgeLookup = {};

  // Condition relabel lookup: value -> entry (label only; index unused).
  final Map<String, BadgeEntry> _condLookup = {};

  // Expand/collapse state: set of expanded group keys.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    final dynamic c = widget.component;

    // Period selector.
    final String periodRaw = (c['period'] ?? '').toString();
    _periods = parsePeriods(autheniumDecode(periodRaw) ?? periodRaw);
    final int def = int.tryParse((c['periodDefault'] ?? '').toString()) ?? 0;
    _selectedMs = _periods.any((p) => p.ms == def)
        ? def
        : (_periods.isNotEmpty ? _periods.first.ms : 604800000);

    // Field configs.
    final String tf = (c['timeField'] ?? '').toString().trim();
    _timeField = tf.isEmpty ? 't' : tf;
    _groupField = (c['groupField'] ?? '').toString().trim();
    _groupField2 = (c['groupField2'] ?? '').toString().trim();
    _badgeField = (c['badgeField'] ?? '').toString().trim();

    // Badge map.
    final String bmRaw = (c['badgeMap'] ?? '').toString();
    final String bmDecoded = autheniumDecode(bmRaw) ?? bmRaw;
    _badgeLookup.clear();
    parseBadgeMap(bmDecoded, _badgeLookup);

    // Condition relabel map (same encoding as badgeMap).
    final String cmRaw = (c['condMap'] ?? '').toString();
    final String cmDecoded = autheniumDecode(cmRaw) ?? cmRaw;
    _condLookup.clear();
    parseBadgeMap(cmDecoded, _condLookup);

    // Template strings. autheniumDecode so structural chars the server encodes
    // (e.g. ◆ = _u25C6_, the ◆-segment separator in subText/itemText) become
    // literals BEFORE resolveMapTokens/split — else `_u25C6_` leaks to the UI
    // and the segment split is a no-op (Convention #2).
    String dec(String key) {
      final String raw = (c[key] ?? '').toString();
      return autheniumDecode(raw) ?? raw;
    }

    _headText = dec('headText');
    _titleText = dec('titleText');
    _subText = dec('subText');
    _itemText = dec('itemText');
    _refText = dec('refText');
    _titleTemplate = dec('title');
    _subtitleTemplate = dec('subtitle');
    _sectionText = dec('sectionText');

    // Expandable flag (default true).
    final String expRaw = (c['expandable'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    _expandable = expRaw != 'FALSE';
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '')
        .toString()
        .trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    // vid-scoped: mapTableContent/_mapSubscribed key by code; without vid a
    // same tableDocId/subColl on another tenant dedups our stream away.
    _eventCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _eventCode);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> events = List<Map<String, dynamic>>.from(
        mapTableContent[_eventCode] ?? const [],
      );
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final int windowStartMs = nowMs - _selectedMs;

      // ---- Conditions: autheniumDecode -> resolveScreenTxTokens -> fail-closed
      // IMPORTANT: uses resolveScreenTxTokens (via resolveConditionsFailClosed),
      // NOT resolveDriverCurlyTokens. The latter has a hardcoded
      // `case 'vehicleId'` that reads DriverHomeState (empty for admin users)
      // and SHADOWS the bare screenTx key from routeParams.
      final String condRaw = (widget.component['conditions'] ?? '').toString();
      final String condDecoded = autheniumDecode(condRaw) ?? condRaw;
      final String? condResolved = resolveConditionsFailClosed(
        condDecoded,
        _screenTx,
      );
      // Fail-closed: unresolved {token} -> show nothing.
      final List<Map<String, dynamic>> matched = condResolved == null
          ? const []
          : filterEventsByConditions(events, condResolved, _screenTx);

      // ---- Window by period + sort desc ----
      final List<Map<String, dynamic>> windowed =
          matched
              .where((e) => docEpoch(e, _timeField) >= windowStartMs)
              .toList()
            ..sort(
              (a, b) =>
                  docEpoch(b, _timeField).compareTo(docEpoch(a, _timeField)),
            );

      // ---- Title / subtitle ----
      final String title = resolveMapTokens(_titleTemplate, const {}, {
        'count': '${windowed.length}',
      });
      final String subtitle = resolveMapTokens(_subtitleTemplate, const {}, {
        'count': '${windowed.length}',
      });

      // ---- Group or flat ----
      final bool isGrouped = _groupField.isNotEmpty;
      final List<LedgerGroup> groups = isGrouped
          ? groupDocs(windowed, _groupField, _timeField)
          : windowed
                .map((d) => LedgerGroup('', [d], docEpoch(d, _timeField)))
                .toList();

      final double availableH = MediaQuery.of(context).size.height * 0.82;

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
              if (title.isNotEmpty)
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2233),
                  ),
                ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9AA1AD),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_periods.isNotEmpty) _buildPeriodTabs(),
              const SizedBox(height: 14),
              Expanded(
                child: windowed.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada data',
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : _groupField2.isNotEmpty
                    ? _buildSectionedList(windowed, nowMs, isGrouped)
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: groups.length,
                        itemBuilder: (ctx, i) =>
                            _buildCard(groups[i], nowMs, isGrouped),
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ---- Period tabs (mirrors TimelinePeriodic) ----

  Widget _buildPeriodTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final p in _periods)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedMs = p.ms),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.ms == _selectedMs
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: p.ms == _selectedMs
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    p.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.ms == _selectedMs
                          ? const Color(0xFF1A2233)
                          : const Color(0xFF8A93A6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- 2-level sectioned list ----

  Widget _buildSectionedList(
    List<Map<String, dynamic>> windowed,
    int nowMs,
    bool isGrouped,
  ) {
    final List<LedgerSection> sections = groupSections(
      windowed,
      _groupField2,
      _groupField,
      _timeField,
    );

    // Flatten sections + their cards into a single widget list for ListView.
    final List<Widget> items = [];
    for (final section in sections) {
      items.add(_buildSectionHeader(section));
      for (final group in section.groups) {
        items.add(
          _buildCard(
            group,
            nowMs,
            isGrouped,
            expandKey: '${section.key}\u{25C6}${group.key}',
          ),
        );
      }
    }

    return ListView(padding: EdgeInsets.zero, children: items);
  }

  Widget _buildSectionHeader(LedgerSection section) {
    // Representative doc: first doc of first group (for <field> tokens).
    // Guard: section.groups should never be empty (groupSections skips empty
    // sections), but defend anyway.
    final Map<String, dynamic> rep =
        section.groups.isNotEmpty && section.groups.first.docs.isNotEmpty
        ? section.groups.first.docs.first
        : const <String, dynamic>{};

    final String sectionTime = formatEpochHHmm(section.minEpoch);

    final String resolved =
        resolveMapTokens(_sectionText, applyCondMap(rep, _condLookup), {
          'sectionCount': '${section.sectionCount}',
          'groupCount': '${section.groupCount}',
          'sectionTime': sectionTime,
        });

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        resolved,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ---- Card rendering ----

  Widget _buildCard(
    LedgerGroup group,
    int nowMs,
    bool isGrouped, {
    String? expandKey,
  }) {
    // Expand-state key: in 2-level mode the same groupField value recurs across
    // sections (groupSections runs groupDocs per-section), so the sectioned
    // caller passes a section-scoped composite to stop two same-key groups
    // toggling as one. 1-level callers pass none -> eKey == group.key
    // (byte-identical).
    final String eKey = expandKey ?? group.key;
    // Representative doc: first doc in group (already sorted by epoch desc).
    final Map<String, dynamic> rep = group.docs.first;
    final int repEpoch = docEpoch(rep, _timeField);

    // Inject synthetic `ts` for relativeTimestamp.
    final Map<String, dynamic> repWithTs = Map<String, dynamic>.from(
      applyCondMap(rep, _condLookup),
    )..['ts'] = relativeTimestamp(repEpoch, nowMs);

    // Badge.
    final String badgeValue = _badgeField.isNotEmpty
        ? (rep[_badgeField] ?? '').toString().trim()
        : '';
    final BadgeEntry? badgeEntry = _badgeLookup[badgeValue];
    final String badgeLabel = badgeEntry != null
        ? badgeEntry.label
        : badgeValue;

    // Template resolution.
    final String headResolved = resolveMapTokens(
      _headText,
      repWithTs,
      const {},
    );
    final String titleResolved = resolveMapTokens(
      _titleText,
      repWithTs,
      const {},
    );
    final String subResolved = resolveMapTokens(_subText, repWithTs, {
      'n': '${group.docs.length}',
    });
    // Sub text may be diamond-segmented (e.g. "oleh <an>◆{n} item").
    final List<String> subSegments = subResolved.split('\u{25C6}');

    final bool isExpanded = _expanded.contains(eKey);
    final bool canExpand = isGrouped && _expandable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEF0F2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Header + Badge ----
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  // Dot indicator.
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: badgeFgColor(badgeEntry),
                    ),
                  ),
                  // Head text (e.g. timestamp).
                  Expanded(
                    child: Text(
                      headResolved,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9AA1AD),
                      ),
                    ),
                  ),
                  if (badgeLabel.isNotEmpty)
                    _buildBadgePill(badgeEntry, badgeLabel),
                ],
              ),
            ),
            // ---- Title ----
            if (titleResolved.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 6, 14, 0),
                child: Text(
                  titleResolved,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2233),
                  ),
                ),
              ),
            // ---- Sub row + chevron ----
            InkWell(
              onTap: canExpand
                  ? () {
                      setState(() {
                        if (isExpanded) {
                          _expanded.remove(eKey);
                        } else {
                          _expanded.add(eKey);
                        }
                      });
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 6, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            for (int s = 0; s < subSegments.length; s++) ...[
                              if (s > 0)
                                const TextSpan(
                                  text: ' \u{00B7} ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF9AA1AD),
                                  ),
                                ),
                              TextSpan(
                                text: subSegments.length > s
                                    ? subSegments[s]
                                    : '',
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    if (canExpand) ...[
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: const Color(0xFF9AA1AD),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ---- Expanded items ----
            if (isExpanded && canExpand) ...[
              const Divider(height: 1, color: Color(0xFFEEF0F2)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final doc in group.docs) _buildItemRow(doc),
                    if (_refText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        resolveMapTokens(_refText, repWithTs, const {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9AA1AD),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> doc) {
    if (_itemText.isEmpty) return const SizedBox.shrink();
    final List<String> segs = resolveSegmentedTemplate(
      _itemText,
      applyCondMap(doc, _condLookup),
      const {},
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Primary segment (index 0).
          Expanded(
            child: Text(
              segs.isNotEmpty ? segs[0] : '',
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
          // Secondary segment (index 1) if present.
          if (segs.length > 1 && segs[1].trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                segs[1],
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA1AD)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBadgePill(BadgeEntry? entry, String label) {
    final Color fg = badgeFgColor(entry);
    final Color bg = badgeBgColor(entry);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
