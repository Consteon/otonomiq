import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';

/// LIST_MULTIPLE_PANEL_CARD — cost-center list bound to char-code-map docs in a
/// subcollection (`MobileTable/{appVid}/tables/{tableDocId}/{subColl}`).
/// Search + colored status summary + collapsible status accordions (PERLU
/// TINDAK / PERHATIAN / AMAN) + cost-center cards: header (`<an>`/`<sn>`) +
/// colored left strip (worst status) + N nested nav panels (icon box +
/// UPPERCASE label + status pill + bold headline + details + chevron), each
/// tapping its own route with `{ccVid}` = `<av>` context.
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
  String _code = ''; // site subcollection code
  String _workforceCode = '';
  String _eventCode = '';
  int _staleMs = 43200000; // 12h default, configurable via component['staleMs']
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expanded = {'danger': true, 'warn': true, 'ok': true};
  // Build-scoped precomputed indexes (rebuilt each Obx pass).
  int _nowMs = 0;
  Map<String, List<Map<String, dynamic>>> _workersBySv = const {};
  Map<String, int> _lastVisitByLi = const {};

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
    _staleMs =
        int.tryParse((widget.component['staleMs'] ?? '').toString()) ?? 43200000;
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    _code = '${tp.tableDocId}/${tp.subColl}'; // site (or whatever subColl)
    _workforceCode = '${tp.tableDocId}/workforce';
    _eventCode = '${tp.tableDocId}/event';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    subscribeToMapCollection(appVid, tp.tableDocId, 'workforce', _workforceCode);
    subscribeToMapCollection(appVid, tp.tableDocId, 'event', _eventCode);
  }

  /// Real aggregation from the build-scoped indexes: Kehadiran (workforce by
  /// sv) + Patroli (events joined to ll[].li). `{ws}` = worst(ps, qs).
  Map<String, String> _computeCardValues(Map<String, dynamic> doc) {
    final String sv = (doc['sv'] ?? '').toString();
    final KehadiranAgg keh =
    computeKehadiran(_workersBySv[sv] ?? const <Map<String, dynamic>>[]);
    final List<dynamic> ll =
    (doc['ll'] is List) ? doc['ll'] as List : const [];
    final PatroliAgg pat =
    computePatroli(ll, _lastVisitByLi, _nowMs, _staleMs);
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

  String _resolve(String tmpl, Map<String, dynamic> doc, Map<String, String> v) =>
      resolveMapTokens(tmpl, doc, v);

  String _panelStatus(
      PanelConfig p, Map<String, dynamic> doc, Map<String, String> v) =>
      resolveMapTokens(p.status, doc, v);

  String _cardWorstStatus(Map<String, dynamic> doc, Map<String, String> v) {
    final String topLevel =
    resolveMapTokens((widget.component['status'] ?? '').toString(), doc, v);
    final all = <String>[topLevel, ..._panels.map((p) => _panelStatus(p, doc, v))];
    return worstStatus(all);
  }

  void _onPanelTap(Map<String, dynamic> doc, PanelConfig panel) {
    final String ccVid = (doc['av'] ?? '').toString();
    if (ccVid.isNotEmpty) {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'ccVid': ccVid,
        'request_vid': ccVid,
        'panel_route': panel.route,
      })));
    }
    if (panel.route.isNotEmpty && routeExist(panel.route)) {
      routeStack.push(panel.route);
      gotoRoute(panel.route);
    }
  }

  List<Map<String, dynamic>> _search(
      String query, List<Map<String, dynamic>> docs) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return docs;
    return docs.where((d) {
      final String an = (d['an'] ?? '').toString().toLowerCase();
      final String sn = (d['sn'] ?? '').toString().toLowerCase();
      return an.contains(q) || sn.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> all =
      List<Map<String, dynamic>>.from(mapTableContent[_code] ?? const []);
      // Read workforce + event observables INSIDE Obx (reactivity) and index
      // them once per build; per-card aggregation is then O(points)/O(1).
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _workersBySv = groupBySv(List<Map<String, dynamic>>.from(
          mapTableContent[_workforceCode] ?? const []));
      _lastVisitByLi = latestPatrolByPoint(List<Map<String, dynamic>>.from(
          mapTableContent[_eventCode] ?? const []));
      final List<Map<String, dynamic>> filtered = _search(_searchQuery, all);
      final groups = groupByStatus<Map<String, dynamic>>(
        filtered,
            (doc) => _cardWorstStatus(doc, _computeCardValues(doc)),
      );

      final double availableH = MediaQuery.of(context).size.height * 0.79;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              widget.lPad, widget.tPad, widget.rPad, widget.bPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(),
              const SizedBox(height: 14),
              _buildSummary(groups),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final status in statusOrder)
                      if ((groups[status] ?? []).isNotEmpty)
                        ..._buildGroup(status, groups[status]!),
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

  Widget _buildSummary(Map<String, List<Map<String, dynamic>>> groups) {
    final int d = groups['danger']?.length ?? 0;
    final int w = groups['warn']?.length ?? 0;
    final int o = groups['ok']?.length ?? 0;
    const TextStyle sep = TextStyle(fontSize: 13, color: Color(0xFF9CA3AF));
    TextSpan seg(String text, String status) => TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: statusColor(status)));
    return Text.rich(TextSpan(children: [
      seg('$d perlu tindak', 'danger'),
      const TextSpan(text: ' · ', style: sep),
      seg('$w perhatian', 'warn'),
      const TextSpan(text: ' · ', style: sep),
      seg('$o aman', 'ok'),
    ]));
  }

  Widget _buildEmptyState() {
    final String empty =
    _textArray.length > 5 ? _textArray[5] : 'Data tidak ditemukan';
    return Center(
      child: Text(empty,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
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
                    decoration:
                    BoxDecoration(color: sColor, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(statusGroupLabel(status).toUpperCase(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: sColor)),
                const Spacer(),
                Text('$count',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: sColor)),
                const SizedBox(width: 8),
                Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: sColor, size: 22),
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
    final String name = _textArray.length > 1 ? _resolve(_textArray[1], doc, v) : '';
    final String sub = _textArray.length > 2 ? _resolve(_textArray[2], doc, v) : '';

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
                  color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
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
                        Text(name,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A2233)),
                            overflow: TextOverflow.ellipsis),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(sub,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF9AA1AD)),
                              overflow: TextOverflow.ellipsis),
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
      PanelConfig p, Map<String, dynamic> doc, Map<String, String> v) {
    final PanelText t = splitPanelText(_resolve(p.text, doc, v));
    final String status = _panelStatus(p, doc, v);
    final String details = (normalizeStatus(status) == 'ok' && p.okText.isNotEmpty)
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
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(panelIcon(p.icon),
                  size: 22, color: const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(t.label.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: Color(0xFF8A93A6)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      _statusPill(status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (t.headline.isNotEmpty)
                    Text(t.headline,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2233))),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(details,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF9AA1AD))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFC7CCD4), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: statusBgColor(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(statusPillLabel(status),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: statusColor(status))),
    );
  }
}
