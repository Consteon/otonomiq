import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_CONFIRMED_LIST -- P7 read-only list of driver-confirmed items.
///
/// Subscribes vehicle_check (opening doc) + item (name + category JOIN).
/// Reads `ip[]` (driver's counts, written at P6). Renders per item:
/// name, category chip, qty, green checkmark. No edits, no store.
///
/// Component JSON fields:
///   `table`      -- vehicle_check path (e.g. `84214220504259//vehicle_check`)
///   `search`     -- opening doc search (`cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}`)
///   `joinTable`  -- item table path (e.g. `84214220504259//item`)
///   `text`       -- diamond-separated label slots
///   `actualField`-- field name for ip[] (default `ip`)
///   `vidtable`   -- explicit appVid override
///   `com`        -- tenant container (`con`)
class CustodyConfirmedList extends StatefulWidget {
  const CustodyConfirmedList({
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
  State<CustodyConfirmedList> createState() => _CustodyConfirmedListState();
}

class _CustodyConfirmedListState extends State<CustodyConfirmedList> {
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

  /// Text slot accessor.
  ///  [0] "Yang Dikonfirmasi"  (section title)
  ///  [1] "returnable"         (category label: returnable)
  ///  [2] "consumable"         (category label: consumable)
  ///  [3] hint label            (e.g. "Selanjutnya")
  ///  [4] hint body             (e.g. "Mulai eksekusi task hari ini, ...")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // vehicle_check
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }

    // item (JOIN)
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
    final Color primary = Theme.of(context).primaryColor;
    final Color pillBg = HSLColor.fromColor(
      primary,
    ).withLightness(0.92).withSaturation(0.35).toColor();
    final Color pillText = HSLColor.fromColor(
      primary,
    ).withLightness(0.35).withSaturation(0.8).toColor();
    // Hint tints (same HSL pattern; all lightness/saturation in [0,1]).
    final Color hintBg = HSLColor.fromColor(
      primary,
    ).withLightness(0.97).withSaturation(0.35).toColor();
    final Color hintBorder = HSLColor.fromColor(
      primary,
    ).withLightness(0.90).withSaturation(0.35).toColor();
    final Color hintIconBg = HSLColor.fromColor(
      primary,
    ).withLightness(0.90).withSaturation(0.40).toColor();
    final Color hintAccent = HSLColor.fromColor(
      primary,
    ).withLightness(0.40).withSaturation(0.70).toColor();

    return Obx(() {
      // Touch reactive source to register Obx dependency.
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

      final String actualField = (widget.component['actualField'] ?? 'ip')
          .toString();
      final List<Map<String, dynamic>> ipEntries = _extractArray(
        checkDoc,
        actualField,
      );

      // Build item detail map for JOIN.
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
        itemDocs,
      );

      // Build display rows.
      final List<_ConfirmedRow> rows = [];
      for (final entry in ipEntries) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        if (ii.isEmpty) continue;
        final ItemDetail? detail = itemDetailMap[ii];
        rows.add(
          _ConfirmedRow(
            name: detail?.name ?? ii,
            category: detail?.category ?? cd,
            qty: qt,
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
            // ── Eyebrow row: section title + summary count pill ──
            if (_t(0).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text(
                      _t(0, 'Yang Dikonfirmasi'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${rows.length} item',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: pillText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // ── Grouped card ──
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0F1F3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    _buildRow(rows[i]),
                    if (i < rows.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF1F2F4),
                        indent: 50, // 16 pad + 22 icon + 12 gap
                        endIndent: 16,
                      ),
                  ],
                ],
              ),
            ),
            // ── Optional next-step hint footer ──
            if (_t(3).isNotEmpty || _t(4).isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildHint(hintBg, hintBorder, hintIconBg, hintAccent),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildRow(_ConfirmedRow r) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Green checkmark
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF16A34A),
            size: 22,
          ),
          const SizedBox(width: 12),
          // Name + category
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                if (r.category.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r.category,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Qty
          Text(
            '${r.qty}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(
    Color hintBg,
    Color hintBorder,
    Color hintIconBg,
    Color hintAccent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: hintBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hintBorder, width: 1),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon chip
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: hintIconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(
                Icons.arrow_forward_rounded,
                color: hintAccent,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Label + body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_t(3).isNotEmpty)
                  Text(
                    _t(3).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: hintAccent,
                    ),
                  ),
                if (_t(3).isNotEmpty && _t(4).isNotEmpty)
                  const SizedBox(height: 4),
                if (_t(4).isNotEmpty)
                  Text(
                    _t(4),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: Color(0xFF374151),
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

class _ConfirmedRow {
  final String name;
  final String category;
  final int qty;
  const _ConfirmedRow({
    required this.name,
    required this.category,
    required this.qty,
  });
}
