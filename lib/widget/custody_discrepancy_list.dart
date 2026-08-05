import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_DISCREPANCY_LIST -- P8 read-only discrepancy list.
///
/// Subscribes vehicle_check (opening doc) + item (name JOIN).
/// Reads `dp[]` ({ii, cd, ex, ac, dl}) written at custodyReveal.
/// Per item: a card with name, Kurang/Lebih severity pill, and a stat strip
/// (Gudang -> Hitung -> Selisih), left-accented by severity. A summary strip
/// above the cards counts total / kurang / lebih.
///
/// Component JSON fields:
///   `table`           -- vehicle_check path
///   `search`          -- opening doc search
///   `joinTable`       -- item table path
///   `text`            -- diamond-separated label slots
///   `discrepancyField`-- field name for dp[] (default `dp`)
///   `vidtable`        -- explicit appVid override
///   `com`             -- tenant container
class CustodyDiscrepancyList extends StatefulWidget {
  const CustodyDiscrepancyList({
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
  State<CustodyDiscrepancyList> createState() => _CustodyDiscrepancyListState();
}

class _CustodyDiscrepancyListState extends State<CustodyDiscrepancyList> {
  // ── Severity palette (shared with the driver widgets) ──────────────────
  static const Color _kAmberStrong = Color(0xFFD97706); // amber-600 (Kurang)
  static const Color _kAmberPillBg = Color(0xFFFEF3C7); // amber-100
  static const Color _kAmberPillFg = Color(0xFFB45309); // amber-700
  static const Color _kVioletStrong = Color(0xFF7C3AED); // violet-600 (Lebih)
  static const Color _kVioletPillBg = Color(0xFFEDE9FE); // violet-100
  static const Color _kVioletPillFg = Color(0xFF6D28D9); // violet-700
  static const Color _kNeutral = Color(0xFF6B7280); // gray-500
  static const Color _kInk = Color(0xFF1F2937); // gray-800/900
  static const Color _kLabel = Color(0xFF6B7280); // gray-500
  static const Color _kBorder = Color(0xFFE5E7EB); // gray-200
  static const Color _kArrow = Color(0xFF9CA3AF); // gray-400

  String _checkCode = '';
  String _itemCode = '';
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Text slot accessor (length-guarded; `diamondTextToList('')` -> `['']`).
  ///  [0] "Daftar Selisih"  (section title)
  ///  [1] "Gudang"          (stat label: warehouse)
  ///  [2] "Hitung"          (stat label: counted)
  ///  [3] "Selisih"         (stat label: delta)
  ///  [4] "Kurang"          (severity pill, delta < 0)
  ///  [5] "Lebih"           (severity pill, delta > 0)
  ///  [6] "item selisih"    (summary strip: total noun)
  ///  [7] "kurang"          (summary strip: short count noun)
  ///  [8] "lebih"           (summary strip: over count noun)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }

    final String rawJoinTable = (widget.component['joinTable'] ?? '')
        .toString()
        .trim();
    if (rawJoinTable.isNotEmpty) {
      final TablePath jtp = parseTablePath(rawJoinTable);
      if (jtp.tableDocId.isNotEmpty) {
        _itemCode = '$appVid/${jtp.tableDocId}/${jtp.subColl}';
        subscribeToMapCollection(
          appVid,
          jtp.tableDocId,
          jtp.subColl,
          _itemCode,
        );
      }
    }
  }

  Map<String, dynamic>? _findCheckDoc() {
    if (_checkCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_checkCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      docs,
      rawSearch,
      widget.scrName,
    );
    return pickNewestDoc(matched);
  }

  List<Map<String, dynamic>> _extractArray(
    Map<String, dynamic>? doc,
    String fieldName,
  ) {
    if (doc == null) return const [];
    final dynamic raw = doc[fieldName];
    if (raw is! List) return const [];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic entry in raw) {
      if (entry is! Map) continue;
      out.add(Map<String, dynamic>.from(entry));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      mapTableContent[_checkCode];
      mapTableContent[_itemCode];

      final Map<String, dynamic>? checkDoc = _findCheckDoc();
      if (checkDoc == null) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      final String dpField = (widget.component['discrepancyField'] ?? 'dp')
          .toString();
      final List<Map<String, dynamic>> dpEntries = _extractArray(
        checkDoc,
        dpField,
      );

      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
        itemDocs,
      );

      // Build rows (data mapping unchanged).
      final List<_DiscrepancyRow> rows = [];
      for (final entry in dpEntries) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        if (ii.isEmpty) continue;
        final int ex =
            int.tryParse((entry['ex'] ?? '0').toString().trim()) ?? 0;
        final int ac =
            int.tryParse((entry['ac'] ?? '0').toString().trim()) ?? 0;
        final int dl =
            int.tryParse((entry['dl'] ?? '0').toString().trim()) ?? 0;
        final ItemDetail? detail = itemDetailMap[ii];
        rows.add(
          _DiscrepancyRow(
            name: detail?.name ?? ii,
            category: detail?.category ?? cd,
            warehouse: ex,
            actual: ac,
            delta: dl,
          ),
        );
      }

      if (rows.isEmpty) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: const Text('--'),
        );
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_t(0).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _t(0, 'Daftar Selisih'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            _buildSummary(rows),
            const SizedBox(height: 10),
            ...rows.map(_buildCard),
          ],
        ),
      );
    });
  }

  // ── Summary strip: "N item selisih · X kurang · Y lebih" ───────────────
  Widget _buildSummary(List<_DiscrepancyRow> rows) {
    final int total = rows.length;
    final int kurang = rows.where((r) => r.delta < 0).length;
    final int lebih = rows.where((r) => r.delta > 0).length;

    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(
        text: '$total ${_t(6, 'item selisih')}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _kNeutral,
        ),
      ),
    ];
    if (kurang > 0) {
      spans.add(_dotSep());
      spans.add(
        TextSpan(
          text: '$kurang ${_t(7, 'kurang')}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _kAmberPillFg,
          ),
        ),
      );
    }
    if (lebih > 0) {
      spans.add(_dotSep());
      spans.add(
        TextSpan(
          text: '$lebih ${_t(8, 'lebih')}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _kVioletPillFg,
          ),
        ),
      );
    }
    return Text.rich(TextSpan(children: spans));
  }

  TextSpan _dotSep() => const TextSpan(
    text: '  ·  ',
    style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)), // slate-300
  );

  // ── One discrepancy card ───────────────────────────────────────────────
  Widget _buildCard(_DiscrepancyRow r) {
    final bool isShort = r.delta < 0;
    final bool isOver = r.delta > 0;

    final Color accent = isShort
        ? _kAmberStrong
        : (isOver ? _kVioletStrong : _kNeutral);
    final Color pillBg = isShort
        ? _kAmberPillBg
        : (isOver ? _kVioletPillBg : const Color(0xFFF3F4F6));
    final Color pillFg = isShort
        ? _kAmberPillFg
        : (isOver ? _kVioletPillFg : _kNeutral);
    final String pillLabel = isShort
        ? _t(4, 'Kurang')
        : (isOver ? _t(5, 'Lebih') : '—');
    final String deltaText = r.delta > 0 ? '+${r.delta}' : '${r.delta}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Severity accent bar (left, 4px)
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Name + severity pill ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              r.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              pillLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: pillFg,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── Stat strip: Gudang -> Hitung ........ Selisih ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _miniStat(_t(1, 'Gudang'), '${r.warehouse}'),
                          const Padding(
                            padding: EdgeInsets.only(
                              left: 12,
                              right: 12,
                              bottom: 3,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: _kArrow,
                            ),
                          ),
                          _miniStat(_t(2, 'Hitung'), '${r.actual}'),
                          const Spacer(),
                          _selisihStat(_t(3, 'Selisih'), deltaText, accent),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small left-aligned stat: muted label over a medium value.
  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kLabel,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _kInk,
          ),
        ),
      ],
    );
  }

  /// Emphasized right-aligned Selisih: muted label over a big colored value.
  Widget _selisihStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kLabel,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _DiscrepancyRow {
  final String name;
  final String category;
  final int warehouse;
  final int actual;
  final int delta;
  const _DiscrepancyRow({
    required this.name,
    required this.category,
    required this.warehouse,
    required this.actual,
    required this.delta,
  });
}
