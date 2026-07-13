import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// LIST_STATISTIC_CARD — per-point Patroli & Cleaning detail for one cost center.
/// Filters the `site` subcollection to the doc whose `<av>` == screenTx['ccVid'],
/// renders that doc's `ll[]` points as cards: period selector + 3 stat boxes +
/// status-sorted point list (recency, last-by, visit count, evidence badge),
/// each tapping `route` with the point context (`pointId`/`pointName`).
class ListStatisticCard extends StatefulWidget {
  const ListStatisticCard({
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
  State<ListStatisticCard> createState() => _ListStatisticCardState();
}

class _ListStatisticCardState extends State<ListStatisticCard> {
  List<String> _textArray = [];
  List<String> _contentArray = [];
  List<PeriodOption> _periods = [];
  List<StatSpec> _statSpecs = [];
  int _selectedMs = 86400000;
  int _staleMs = 43200000;
  String _siteCode = '';
  String _eventCode = '';
  String _siteSv = '';
  String _searchQuery = '';
  String _mergeTyped = '';
  // Child-collection config (point-list source swap)
  String _childTable = ''; // empty = embedded array (default behavior)
  String _childArrayField = 'll'; // embedded array field name
  String _parentKey = 'sv'; // field on parent doc for filtering children
  String _childKey = 'sv'; // field on child doc matched to parentKey
  String _childCode = ''; // subscription code (empty = no subscribe)

  // Build-scoped child index (rebuilt each Obx pass).
  Map<String, List<Map<String, dynamic>>> _childByKey = const {};
  final TextEditingController _searchController = TextEditingController();

  // Build-scoped indexes (rebuilt each Obx pass).
  int _nowMs = 0;
  int _windowStartMs = 0;
  Map<String, List<Map<String, dynamic>>> _byLn = const {};

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    try {
      _contentArray = diamondTextToList(
        (widget.component['content'] ?? '').toString(),
      );
    } catch (_) {
      _contentArray = [];
    }
    final String periodRaw = (widget.component['period'] ?? '').toString();
    _periods = parsePeriods(autheniumDecode(periodRaw) ?? periodRaw);
    final String statsRaw = (widget.component['stats'] ?? '').toString();
    _statSpecs = parseStatSpecs(autheniumDecode(statsRaw) ?? statsRaw);
    _staleMs =
        int.tryParse((widget.component['staleMs'] ?? '').toString()) ??
        43200000;
    final int def =
        int.tryParse((widget.component['periodDefault'] ?? '').toString()) ?? 0;
    _selectedMs = _periods.any((p) => p.ms == def)
        ? def
        : (_periods.isNotEmpty ? _periods.first.ms : 86400000);
    _mergeTyped = (widget.component['mergeTyped'] ?? '').toString().trim();
    // Child-collection point-list source (backward compat: all defaults = embedded ll)
    // These are plain config values (collection paths, field names) -- no autheniumDecode needed.
    _childTable = (widget.component['childTable'] ?? '').toString().trim();
    _childArrayField = (widget.component['childArrayField'] ?? '')
        .toString()
        .trim();
    if (_childArrayField.isEmpty) _childArrayField = 'll';
    _parentKey = (widget.component['parentKey'] ?? '').toString().trim();
    if (_parentKey.isEmpty) _parentKey = 'sv';
    _childKey = (widget.component['childKey'] ?? '').toString().trim();
    if (_childKey.isEmpty) _childKey = 'sv';
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '')
        .toString()
        .trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    // vid-scoped keys: mapTableContent/_mapSubscribed key by code without vid,
    // so a same tableDocId/subColl on another tenant would dedup our stream away.
    _siteCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
    _eventCode = '$appVid/${tp.tableDocId}/event';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _siteCode);
    subscribeToMapCollection(appVid, tp.tableDocId, 'event', _eventCode);
    // Child collection subscribe (only when childTable is configured)
    if (_childTable.isNotEmpty) {
      final TablePath childTp = parseTablePath(_childTable);
      if (childTp.tableDocId.isNotEmpty) {
        _childCode = '$appVid/${childTp.tableDocId}/${childTp.subColl}';
        subscribeToMapCollection(
          appVid,
          childTp.tableDocId,
          childTp.subColl,
          _childCode,
        );
      }
    }
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  /// Resolve the {ccVid} token from screenTx for event-side av filtering.
  /// Uses the same conditions/search field (same precedence as [_points]) to
  /// extract the token name, then looks it up in _screenTx.
  String get _resolvedCcVid {
    final String raw =
        (widget.component['conditions'] ?? widget.component['search'] ?? '')
            .toString();
    final String decoded = autheniumDecode(raw) ?? raw;
    // Extract the token name from the pattern (e.g. "av◼{ccVid}" -> "ccVid").
    final RegExp tok = RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}');
    final Match? m = tok.firstMatch(decoded);
    if (m == null) return '';
    final String key = m.group(1) ?? '';
    return (_screenTx[key] ?? '').toString().trim();
  }

  String get _selectedLabel {
    for (final p in _periods) {
      if (p.ms == _selectedMs) return p.label;
    }
    return '';
  }

  /// The matched site doc's `ll[]` points (cc filtered by av == ccVid).
  List<Map<String, dynamic>> _points(List<Map<String, dynamic>> siteDocs) {
    final String condRaw =
        (widget.component['conditions'] ?? widget.component['search'] ?? '')
            .toString();
    final String cond = autheniumDecode(condRaw) ?? condRaw;
    final List<Map<String, dynamic>> matched = filterByCharCodeEquality(
      siteDocs,
      cond,
      _screenTx,
    );
    _siteSv = matched.isNotEmpty ? (matched.first['sv'] ?? '').toString() : '';
    if (matched.isEmpty) return const [];
    if (_childTable.isEmpty) {
      final dynamic ll = matched.first[_childArrayField];
      if (ll is! List) return const [];
      return ll
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    // child-collection: location docs grouped by _childKey, filtered by parent[_parentKey]
    final String key = (matched.first[_parentKey] ?? '').toString();
    return _childByKey[key] ?? const [];
  }

  List<Map<String, dynamic>> _search(List<Map<String, dynamic>> points) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return points;
    return points
        .where((p) => (p['ln'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  void _onPointTap(Map<String, dynamic> point) {
    final String route = (widget.component['route'] ?? '').toString();
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          'point': (point['ln'] ?? '').toString(),
          'pointId': (point['li'] ?? '').toString(),
          'pointName': (point['ln'] ?? '').toString(),
          'point_route': route,
          'site': _siteSv,
        }),
      ),
    );
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> siteDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_siteCode] ?? const [],
          );
      final List<Map<String, dynamic>> events = List<Map<String, dynamic>>.from(
        mapTableContent[_eventCode] ?? const [],
      );
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _windowStartMs = _nowMs - _selectedMs;

      // Index child docs by childKey (only when child collection is active)
      if (_childCode.isNotEmpty) {
        _childByKey = groupByField(
          List<Map<String, dynamic>>.from(
            mapTableContent[_childCode] ?? const [],
          ),
          _childKey,
        );
      } else {
        _childByKey = const {};
      }

      final List<Map<String, dynamic>> points = _points(siteDocs);

      // --- Merge-typed path vs legacy path ---
      final List<MapEntry<Map<String, dynamic>, PointStat>> entries;
      final StatsSummary summary;

      if (_mergeTyped.isNotEmpty) {
        // MERGE MODE: scope events, lowercase matching, orphan merge.
        final String ccVid = _resolvedCcVid;
        final List<Map<String, dynamic>> scoped = scopePatrolEvents(
          events,
          'report-patrol',
          ccVid,
          _windowStartMs,
        );
        final Map<String, List<Map<String, dynamic>>> byLnLower =
            eventsByLnLower(scoped);

        // Official points set (lowercase).
        final Set<String> officialNamesLower = points
            .map((p) => (p['ln'] ?? '').toString().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();

        // Typed entries (orphans).
        final List<TypedEntry> typedEntries = groupOrphans(
          byLnLower,
          officialNamesLower,
        );

        // Stats.
        summary = computeStatsSummaryMerge(
          points: points,
          typedEntries: typedEntries,
          scopedEvents: scoped,
          byLnLower: byLnLower,
        );

        // Build entry pairs: official points.
        final List<MapEntry<Map<String, dynamic>, PointStat>> officialEntries =
            points.map((p) {
              final String lnLower = (p['ln'] ?? '').toString().toLowerCase();
              final stat = computePointStat(
                byLnLower[lnLower] ?? const [],
                _nowMs,
                _windowStartMs,
                _staleMs,
              );
              return MapEntry(p, stat);
            }).toList();

        // Build entry pairs: typed entries.
        final List<MapEntry<Map<String, dynamic>, PointStat>> typedPairs =
            typedEntries.map((te) {
              final Map<String, dynamic> pseudoPoint = {'ln': te.ln, 'li': ''};
              final stat = computeTypedPointStat(te.events, _nowMs);
              return MapEntry(pseudoPoint, stat);
            }).toList();

        // Union then search.
        final List<MapEntry<Map<String, dynamic>, PointStat>> union = [
          ...officialEntries,
          ...typedPairs,
        ];

        // Apply search filter.
        final String q = _searchQuery.trim().toLowerCase();
        final List<MapEntry<Map<String, dynamic>, PointStat>> searched =
            q.isEmpty
            ? union
            : union
                  .where(
                    (e) => (e.key['ln'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(q),
                  )
                  .toList();

        // Sort: severity desc, oldest first.
        searched.sort((a, b) {
          final int ra = statusOrder.indexOf(a.value.ps);
          final int rb = statusOrder.indexOf(b.value.ps);
          final int sa = ra < 0 ? statusOrder.length : ra;
          final int sb = rb < 0 ? statusOrder.length : rb;
          if (sa != sb) return sa - sb;
          return a.value.lastEpoch.compareTo(b.value.lastEpoch);
        });

        entries = searched;
      } else {
        // LEGACY MODE: exact-case matching, old stats.
        _byLn = eventsByLn(events);
        summary = computeStatsSummary(points, _byLn, _nowMs, _windowStartMs);
        final List<Map<String, dynamic>> searched = _search(points);

        final List<MapEntry<Map<String, dynamic>, PointStat>> legacy = searched
            .map((p) {
              final stat = computePointStat(
                _byLn[(p['ln'] ?? '').toString()] ?? const [],
                _nowMs,
                _windowStartMs,
                _staleMs,
              );
              return MapEntry(p, stat);
            })
            .toList();
        legacy.sort((a, b) {
          final int ra = statusOrder.indexOf(a.value.ps);
          final int rb = statusOrder.indexOf(b.value.ps);
          final int sa = ra < 0 ? statusOrder.length : ra;
          final int sb = rb < 0 ? statusOrder.length : rb;
          if (sa != sb) return sa - sb;
          return a.value.lastEpoch.compareTo(b.value.lastEpoch);
        });
        entries = legacy;
      }

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
              if (_periods.isNotEmpty) _buildPeriodTabs(),
              const SizedBox(height: 14),
              if (_statSpecs.isNotEmpty) _buildStatBoxes(summary),
              const SizedBox(height: 14),
              _buildSearchField(),
              const SizedBox(height: 12),
              Expanded(
                child: entries.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final e in entries)
                            _buildPointCard(e.key, e.value),
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

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

  Widget _buildStatBoxes(StatsSummary summary) {
    final Map<String, String> tokens = summary.toTokens();
    // IntrinsicHeight bounds the row height to the tallest box so the
    // CrossAxisAlignment.stretch (equal-height boxes) resolves. Without it the
    // stretch inherits the parent Column's unbounded height and throws
    // "BoxConstraints forces an infinite height".
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _statSpecs.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: _statBox(i, _statSpecs[i], tokens)),
          ],
        ],
      ),
    );
  }

  Widget _statBox(int index, StatSpec spec, Map<String, String> tokens) {
    final String value = resolveMapTokens(spec.template, const {}, tokens);
    final bool neutral = index == 0;
    final bool good = value.trim() == '0';
    final Color bg = neutral
        ? Colors.white
        : (good ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7));
    final Color fg = neutral
        ? const Color(0xFF1A2233)
        : (good ? const Color(0xFF16A34A) : const Color(0xFFD97706));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: neutral ? Border.all(color: const Color(0xFFE5E7EB)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec.label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final String hint = _textArray.isNotEmpty ? _textArray[0] : 'Cari';
    return TextFormField(
      controller: _searchController,
      keyboardType: TextInputType.text,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
        hintText: hint,
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

  Widget _buildEmptyState() {
    final String empty = _textArray.length > 2
        ? _textArray[2]
        : 'Data tidak ditemukan';
    return Center(
      child: Text(
        empty,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
    );
  }

  Widget _buildPointCard(Map<String, dynamic> point, PointStat stat) {
    final Map<String, String> tokens = stat.toTokens()
      ..['period'] = _selectedLabel;
    String at(int i) => _contentArray.length > i
        ? resolveMapTokens(_contentArray[i], point, tokens)
        : '';
    final String name = at(0);
    final String type = at(1);
    final String line2 = at(2);
    final String line3 = at(3);
    final String ps = stat.ps;
    final Color sColor = statusColor(ps);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onPointTap(point),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      color: sColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A2233),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (stat.hasEvent) _evidenceBadge(stat.evidence),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFFC7CCD4),
                                size: 20,
                              ),
                            ],
                          ),
                          if (type.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: Color(0xFF8A93A6),
                              ),
                            ),
                          ],
                          if (line2.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              line2,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: normalizeStatus(ps) == 'ok'
                                    ? const Color(0xFF6B7280)
                                    : sColor,
                              ),
                            ),
                          ],
                          if (line3.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              line3,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9AA1AD),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _evidenceBadge(String evidence) {
    final bool strong = evidence == 'Bukti kuat';
    final String mapped = strong ? 'ok' : 'warn';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusBgColor(mapped),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            strong ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
            size: 14,
            color: statusColor(mapped),
          ),
          const SizedBox(width: 4),
          Text(
            evidence,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: statusColor(mapped),
            ),
          ),
        ],
      ),
    );
  }
}
