import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// LIST_MULTIPLE_PANEL_CARD — reusable card-list widget for any domain.
///
/// Renders a list of cards from a Firestore map-collection, each card showing
/// N nav panels. Config-driven: `variant` ('grouped' for accordion+summary,
/// flat for plain list), `statusLabels` for label vocabulary, `groupBy` for
/// grouping token, `searchFields` for client search, `routeParam` for nav
/// context dispatch, `conditions`/`search` for client-side equality filter.
///
/// Aggregation is TYPE-BOUND: `computeKehadiran` + `computePatroli` always run
/// (harmless on non-patrol docs where `{computed}` tokens resolve empty).
/// Pure `<charcode>` panels bypass aggregation naturally via `resolveMapTokens`.
///
/// Subscriptions: unconditionally subscribes to site + workforce + event
/// subcollections (empty reads in non-patrol domains are harmless).
class ListMultiplePanelCard extends StatefulWidget {
  const ListMultiplePanelCard({
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
  State<ListMultiplePanelCard> createState() => _ListMultiplePanelCardState();
}

class _ListMultiplePanelCardState extends State<ListMultiplePanelCard> {
  List<String> _textArray = [];
  List<PanelConfig> _panels = [];
  int _thresholdMs = 43200000; // 12h default
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expanded = {};

  // Config fields parsed from component JSON
  String _variant = ''; // '' / non-'grouped' = flat; 'grouped' = accordion
  List<StatusLabelEntry> _statusLabels = const [];
  String _groupByTemplate = '{ws}';
  List<String> _searchFieldCodes = const ['an', 'sn'];
  RouteParamConfig _routeParam = const RouteParamConfig('av', 'ccVid');
  bool _showIcon = true;
  String _conditionsRaw = '';

  // Child-collection config (point-list source swap)
  String _childTable = ''; // empty = embedded array (default behavior)
  String _childArrayField = 'll'; // embedded array field name
  String _parentKey = 'sv'; // field on parent doc for filtering children
  String _childKey = 'sv'; // field on child doc matched to parentKey

  // Subscription codes
  String _code = ''; // site subcollection code
  String _workforceCode = '';
  String _eventCode = '';
  String _childCode = ''; // child subcollection code (empty = no subscribe)

  // Build-scoped precomputed indexes (rebuilt each Obx pass).
  int _nowMs = 0;
  Map<String, List<Map<String, dynamic>>> _workersBySv = const {};
  Map<String, int> _lastVisitByLn = const {};
  Map<String, List<Map<String, dynamic>>> _childByKey = const {};

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
    _panels = parsePanels(widget.component['panels']);
    _thresholdMs =
        int.tryParse((widget.component['thresholdMs'] ?? '').toString()) ??
        43200000;

    // variant: 'grouped' keeps accordion+summary; anything else = flat
    _variant = (widget.component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    // statusLabels: autheniumDecode before ◼ split (server sends _25FC_)
    final String slRaw = (widget.component['statusLabels'] ?? '').toString();
    _statusLabels = parseStatusLabels(autheniumDecode(slRaw) ?? slRaw);

    // Pre-seed _expanded from statusLabels (all open by default)
    for (final entry in _statusLabels) {
      _expanded[entry.value] = true;
    }

    // groupBy: only meaningful when grouped, but parse always
    final String gbRaw = (widget.component['groupBy'] ?? '').toString().trim();
    _groupByTemplate = gbRaw.isEmpty ? '{ws}' : gbRaw;

    // searchFields: autheniumDecode, then diamondTextToList
    final String sfRaw = (widget.component['searchFields'] ?? '').toString();
    final String sfDecoded = autheniumDecode(sfRaw) ?? sfRaw;
    try {
      final List<String> parsed = diamondTextToList(sfDecoded);
      _searchFieldCodes = parsed.where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      _searchFieldCodes = const ['an', 'sn'];
    }
    if (_searchFieldCodes.isEmpty) _searchFieldCodes = const ['an', 'sn'];

    // routeParam: autheniumDecode before ◼ split
    final String rpRaw = (widget.component['routeParam'] ?? '').toString();
    _routeParam = parseRouteParam(autheniumDecode(rpRaw) ?? rpRaw);

    // showIcon: absent = true; 'FALSE' (case-insensitive) = false
    _showIcon =
        (widget.component['showIcon'] ?? '').toString().toUpperCase() !=
        'FALSE';
    // showProgress: accepted, NO-OP (reserved)

    // conditions/search: raw string, decoded + filtered at build time
    _conditionsRaw =
        (widget.component['conditions'] ?? widget.component['search'] ?? '')
            .toString();

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
    _code =
        '$appVid/${tp.tableDocId}/${tp.subColl}'; // site (or whatever subColl)
    _workforceCode = '$appVid/${tp.tableDocId}/workforce';
    _eventCode = '$appVid/${tp.tableDocId}/event';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    subscribeToMapCollection(
      appVid,
      tp.tableDocId,
      'workforce',
      _workforceCode,
    );
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

  /// Real aggregation from the build-scoped indexes: Kehadiran (workforce by
  /// sv) + Patroli (events joined to ll[].ln). `{ws}` = worst(ps, qs).
  Map<String, String> _computeCardValues(Map<String, dynamic> doc) {
    final String sv = (doc['sv'] ?? '').toString();
    final KehadiranAgg keh = computeKehadiran(
      _workersBySv[sv] ?? const <Map<String, dynamic>>[],
    );
    final List<dynamic> points = _childTable.isEmpty
        ? ((doc[_childArrayField] is List)
              ? doc[_childArrayField] as List
              : const [])
        : (_childByKey[(doc[_parentKey] ?? '').toString()] ?? const []);
    final PatroliAgg pat = computePatroli(
      points,
      _lastVisitByLn,
      _nowMs,
      _thresholdMs,
    );
    return {
      'hadir': '${keh.hadir}',
      'issues': keh.issues,
      'ps': keh.ps,
      'llCount': '${pat.llCount}',
      'staleCount': '${pat.staleCount}',
      'longestGap': '${pat.longestGapHours}',
      'qs': pat.qs,
      'ws': worstStatus([keh.ps, pat.qs]),
    };
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  String _resolve(
    String tmpl,
    Map<String, dynamic> doc,
    Map<String, String> v,
  ) => resolveMapTokens(tmpl, doc, v);

  String _panelStatus(
    PanelConfig p,
    Map<String, dynamic> doc,
    Map<String, String> v,
  ) => resolveMapTokens(p.status, doc, v);

  String _cardWorstStatus(Map<String, dynamic> doc, Map<String, String> v) {
    final String topLevel = resolveMapTokens(
      (widget.component['status'] ?? '').toString(),
      doc,
      v,
    );
    final all = <String>[
      topLevel,
      ..._panels.map((p) => _panelStatus(p, doc, v)),
    ];
    return worstStatus(all);
  }

  void _onPanelTap(Map<String, dynamic> doc, PanelConfig panel) {
    // Resolve routeParam: panel-level override if non-empty, else card-level
    final RouteParamConfig rp = panel.routeParam.isNotEmpty
        ? parseRouteParam(autheniumDecode(panel.routeParam) ?? panel.routeParam)
        : _routeParam;
    final String value = (doc[rp.docField] ?? '').toString();
    if (value.isNotEmpty) {
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            rp.token: value,
            'request_vid': value,
            'panel_route': panel.route,
          }),
        ),
      );
    }
    if (panel.route.isNotEmpty && routeExist(panel.route)) {
      routeStack.push(panel.route);
      gotoRoute(panel.route);
    }
  }

  List<Map<String, dynamic>> _search(
    String query,
    List<Map<String, dynamic>> docs,
  ) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return docs;
    return docs.where((d) {
      for (final field in _searchFieldCodes) {
        final String val = (d[field] ?? '').toString().toLowerCase();
        if (val.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
        mapTableContent[_code] ?? const [],
      );
      // Read workforce + event observables INSIDE Obx (reactivity) and index
      // them once per build; per-card aggregation is then O(points)/O(1).
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _workersBySv = groupBySv(
        List<Map<String, dynamic>>.from(
          mapTableContent[_workforceCode] ?? const [],
        ),
      );
      _lastVisitByLn = latestPatrolByPoint(
        List<Map<String, dynamic>>.from(
          mapTableContent[_eventCode] ?? const [],
        ),
      );
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

      // Client-side conditions filter (search/conditions field)
      final String condDecoded =
          autheniumDecode(_conditionsRaw) ?? _conditionsRaw;
      final List<Map<String, dynamic>> condFiltered = filterByCharCodeEquality(
        all,
        condDecoded,
        _screenTx,
      );

      // Client search box filter
      final List<Map<String, dynamic>> filtered = _search(
        _searchQuery,
        condFiltered,
      );

      final double availableH = MediaQuery.of(context).size.height * 0.79;
      final bool isGrouped = _variant == 'grouped';

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
              _buildSearchField(),
              const SizedBox(height: 14),
              if (isGrouped) ..._buildGroupedContent(filtered),
              if (!isGrouped) ..._buildFlatContent(filtered),
            ],
          ),
        ),
      );
    });
  }

  List<Widget> _buildGroupedContent(List<Map<String, dynamic>> filtered) {
    // Group by resolved groupBy template, in statusLabels order.
    final List<String> order = statusLabelOrder(_statusLabels);
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final s in order) {
      groups[s] = <Map<String, dynamic>>[];
    }
    // W2: unknown group keys (outside the statusLabels tier set) fall into the
    // LAST entry of the order so they always render and stay counted.
    final String fallbackKey = order.isNotEmpty ? order.last : '';
    for (final doc in filtered) {
      final Map<String, String> v = _computeCardValues(doc);
      final String rawGroup = resolveMapTokens(_groupByTemplate, doc, v);
      final String groupKey = normalizeStatus(rawGroup);
      if (groups.containsKey(groupKey)) {
        groups[groupKey]!.add(doc);
      } else if (fallbackKey.isNotEmpty) {
        groups[fallbackKey]!.add(doc);
      }
    }

    // Summary line
    final Map<String, int> counts = {};
    for (final entry in groups.entries) {
      counts[entry.key] = entry.value.length;
    }
    final List<TextSpan> summarySpans = buildSummarySpans(
      _statusLabels,
      counts,
    );

    return [
      if (summarySpans.isNotEmpty) ...[
        Text.rich(TextSpan(children: summarySpans)),
        const SizedBox(height: 12),
      ],
      Expanded(
        child: filtered.isEmpty
            ? _buildEmptyState()
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final status in order)
                    if ((groups[status] ?? []).isNotEmpty)
                      ..._buildGroup(status, groups[status]!),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    ];
  }

  List<Widget> _buildFlatContent(List<Map<String, dynamic>> filtered) {
    return [
      Expanded(
        child: filtered.isEmpty
            ? _buildEmptyState()
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final doc in filtered) _buildCard(doc),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    ];
  }

  Widget _buildSearchField() {
    final String hint = _textArray.length > 4 ? _textArray[4] : 'Cari';
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
    final String empty = _textArray.length > 5
        ? _textArray[5]
        : 'Data tidak ditemukan';
    return Center(
      child: Text(
        empty,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
    );
  }

  List<Widget> _buildGroup(String status, List<Map<String, dynamic>> docs) {
    final bool open = _expanded[status] ?? true;
    return [
      _buildGroupHeader(status, docs.length, open),
      if (open)
        for (final doc in docs) _buildCard(doc),
      const SizedBox(height: 6),
    ];
  }

  Widget _buildGroupHeader(String status, int count, bool open) {
    final Color sColor = statusColor(status);
    final String label = lookupGroupLabel(_statusLabels, status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: statusBgColor(status),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded[status] = !open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: sColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: sColor,
                  ),
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: sColor,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: sColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> doc) {
    final Map<String, String> v = _computeCardValues(doc);
    final String worst = _cardWorstStatus(doc, v);
    final String name = _textArray.length > 1
        ? _resolve(_textArray[1], doc, v)
        : '';
    final String sub = _textArray.length > 2
        ? _resolve(_textArray[2], doc, v)
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
                    color: statusColor(worst),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2233),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9AA1AD),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        for (int i = 0; i < _panels.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: Color(0xFFEEF0F2)),
                          _buildPanel(_panels[i], doc, v),
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
    );
  }

  Widget _buildPanel(
    PanelConfig p,
    Map<String, dynamic> doc,
    Map<String, String> v,
  ) {
    final PanelText t = splitPanelText(_resolve(p.text, doc, v));
    final String status = _panelStatus(p, doc, v);
    final String normalizedStatus = normalizeStatus(status);
    final String details = (normalizedStatus == 'ok' && p.okText.isNotEmpty)
        ? p.okText
        : t.details;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onPanelTap(doc, p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_showIcon) ...[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  panelIcon(p.icon),
                  size: 22,
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF8A93A6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusPill(status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (t.headline.isNotEmpty)
                    Text(
                      t.headline,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2233),
                      ),
                    ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9AA1AD),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFC7CCD4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final String label = lookupPillLabel(_statusLabels, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: statusBgColor(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: statusColor(status),
        ),
      ),
    );
  }
}
