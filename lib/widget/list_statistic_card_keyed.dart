import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// LIST_STATISTIC_CARD · variant:"keyed" — attendance worker list (today).
/// Reads the KEYED `workforce` subcollection (one doc per worker), filters to
/// `sv == {ccVid}`, renders one card per worker with attendance aggregate stat
/// boxes and a per-card status strip. Tapping a card pushes the worker's `vid`
/// to screenTx and routes to the correction page.
class ListStatisticCardKeyed extends StatefulWidget {
  const ListStatisticCardKeyed({
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
  State<ListStatisticCardKeyed> createState() => _ListStatisticCardKeyedState();
}

class _ListStatisticCardKeyedState extends State<ListStatisticCardKeyed> {
  List<String> _textArray = [];
  List<String> _contentArray = [];
  List<StatSpec> _statSpecs = [];
  String _code = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
      final String contentRaw = (widget.component['content'] ?? '').toString();
      _contentArray = diamondTextToList(
        autheniumDecode(contentRaw) ?? contentRaw,
      );
    } catch (_) {
      _contentArray = [];
    }
    final String statsRaw = (widget.component['stats'] ?? '').toString();
    _statSpecs = parseStatSpecs(autheniumDecode(statsRaw) ?? statsRaw);
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '')
        .toString()
        .trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    // vid-scoped: without vid, another tenant's same tableDocId/subColl dedups
    // our stream away (mapTableContent/_mapSubscribed key omits vid).
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  /// Workers matching the `sv == {ccVid}` filter (one card each).
  List<Map<String, dynamic>> _workers(List<Map<String, dynamic>> docs) {
    final String condRaw =
        (widget.component['conditions'] ?? widget.component['search'] ?? '')
            .toString();
    final String cond = autheniumDecode(condRaw) ?? condRaw;
    return filterByCharCodeEquality(docs, cond, _screenTx);
  }

  List<Map<String, dynamic>> _search(List<Map<String, dynamic>> workers) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return workers;
    return workers
        .where((w) => (w['n'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  void _onWorkerTap(Map<String, dynamic> worker) {
    final String route = (widget.component['route'] ?? '').toString();
    debugPrint(
      '[KeyedTap] worker.keys=${worker.keys.toList()} '
      'vid="${worker['vid']}" sv="${worker['sv']}" n="${worker['n']}"',
    );
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          'vid': (worker['vid'] ?? '').toString(),
          'sv': (worker['sv'] ?? '').toString(),
          'is': (worker['is'] ?? '').toString(),
          'os': (worker['os'] ?? '').toString(),
          'n': (worker['n'] ?? '').toString(),
          'worker': (worker['n'] ?? '').toString(),
          'worker_route': route,
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
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_code] ?? const [],
      );
      final List<Map<String, dynamic>> workers = _workers(docs);
      final KehadiranListAgg agg = computeKehadiranList(workers);
      final List<Map<String, dynamic>> searched = _search(workers);

      // severity-desc (danger, warn, ok), then name asc.
      searched.sort((a, b) {
        final int sa = statusOrder.indexOf(workerStatus(a));
        final int sb = statusOrder.indexOf(workerStatus(b));
        final int ra = sa < 0 ? statusOrder.length : sa;
        final int rb = sb < 0 ? statusOrder.length : sb;
        if (ra != rb) return ra - rb;
        return (a['n'] ?? '').toString().compareTo((b['n'] ?? '').toString());
      });

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
              if (_statSpecs.isNotEmpty) _buildStatBoxes(agg),
              const SizedBox(height: 14),
              _buildSearchField(),
              const SizedBox(height: 12),
              Expanded(
                child: searched.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final w in searched) _buildWorkerCard(w),
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

  Widget _buildStatBoxes(KehadiranListAgg agg) {
    final Map<String, String> tokens = agg.toTokens();
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
    final String hint = _textArray.isNotEmpty ? _textArray[0] : 'Cari worker';
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

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    final Map<String, String> tokens = {
      'status': workerStatus(worker),
      'statusLine': workerStatusLine(worker),
    };
    final String statusTemplate = (widget.component['status'] ?? '{status}')
        .toString();
    final String ps = normalizeStatus(
      resolveMapTokens(statusTemplate, worker, tokens),
    );
    final Color sColor = statusColor(ps);

    // Badge resolve + suppress
    final String badgeTemplate = (widget.component['badge'] ?? '').toString();
    final String badgeText = resolveBadge(badgeTemplate, worker, tokens);

    // Build content segments
    final List<Widget> bodyWidgets = [];
    final List<Widget> chipWidgets = [];
    bool titleDone = false;
    int plainLineIdx =
        0; // ordinal of plain non-title lines (for style selection)

    for (int i = 0; i < _contentArray.length; i++) {
      final String raw = _contentArray[i];
      final ChipSpec? chip = parseChipSpec(raw);

      if (chip == null) {
        // Plain text segment
        final String text = resolveMapTokens(raw, worker, tokens);
        if (!titleDone) {
          // First plain-text segment = title row (name + badge + chevron)
          titleDone = true;
          bodyWidgets.add(_buildTitleRow(text, badgeText, ps));
        } else {
          // Subsequent plain-text segments = text lines (backward compat)
          if (text.isNotEmpty) {
            if (plainLineIdx == 0) {
              // Line2 style (first non-title plain): 6px gap, 13px w600, constant gray
              bodyWidgets.add(const SizedBox(height: 6));
              bodyWidgets.add(
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              );
            } else {
              // Line3 style (second+ non-title plain): 4px gap, 12px w600, status-colored
              bodyWidgets.add(const SizedBox(height: 4));
              bodyWidgets.add(
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ps == 'ok' ? const Color(0xFF9AA1AD) : sColor,
                  ),
                ),
              );
            }
            plainLineIdx++;
          }
        }
      } else {
        // Chip segment -- collect into one Wrap row
        final String resolved = resolveMapTokens(
          chip.valueTemplate,
          worker,
          tokens,
        );
        final String formatted = formatTimeShort(resolved);
        final String tone = chipTone(formatted, ps);
        chipWidgets.add(_buildChip(chip.iconName, formatted, tone));
      }
    }

    // If no plain-text segment was found (unlikely but safe), ensure title
    if (!titleDone) {
      bodyWidgets.insert(0, _buildTitleRow('', badgeText, ps));
    }

    // Insert chip row after title, before any trailing text lines
    if (chipWidgets.isNotEmpty) {
      // Insert after index 0 (title row)
      final int insertIdx = bodyWidgets.length > 1 ? 1 : bodyWidgets.length;
      bodyWidgets.insert(insertIdx, const SizedBox(height: 8));
      bodyWidgets.insert(
        insertIdx + 1,
        Wrap(spacing: 16, runSpacing: 6, children: chipWidgets),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onWorkerTap(worker),
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
                        children: bodyWidgets,
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

  /// Title row: name (expanded) + optional badge pill + chevron.
  Widget _buildTitleRow(String name, String badgeText, String cardStatus) {
    return Row(
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
        if (badgeText.isNotEmpty) ...[
          const SizedBox(width: 8),
          _buildBadgePill(badgeText, cardStatus),
        ],
        const SizedBox(width: 8),
        const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFC7CCD4),
          size: 20,
        ),
      ],
    );
  }

  /// Badge pill -- mirrors _evidenceBadge style from list_statistic_card.dart.
  /// Tone = card status (danger/warn/ok).
  Widget _buildBadgePill(String text, String cardStatus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusBgColor(cardStatus),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: statusColor(cardStatus),
        ),
      ),
    );
  }

  /// One icon-chip: icon + formatted value, colored by tone.
  Widget _buildChip(String iconName, String formattedValue, String tone) {
    final Color fg = statusColor(tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stringToIconData(iconName), size: 16, color: fg),
        const SizedBox(width: 4),
        Text(
          formattedValue,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ],
    );
  }
}
