import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CLOSING_CONTEXT_RAIL -- green-tint single-line strip for C1.
///
/// Displays: driver name (from the opening vehicle_check doc `cn` field, or
/// "-") + " . N returnable . M consumable" (category summary from asset_cache
/// docs joined with item docs).
///
/// Pure display: no txfController, no saveSend, no history, no mutable state.
/// Renders its chrome unconditionally (driver "-" if unknown).
///
/// Config fields:
///   `table` -- asset_cache collection path (e.g. `84214220504259//asset_cache`)
///   `search` -- filter clause (e.g. `lv◼{vehicleId}`)
///   `checkTable` -- vehicle_check collection path (for opening doc driver name)
///   `checkSearch` -- search clause for opening doc
///   `joinTable` -- item collection path (for ic category)
///   `joinKey` -- item id field (default `ii`)
///   `catField` -- item category field (default `ic`)
///   `driverField` -- opening doc field for driver name (default `cn`)
///   `text` -- diamond-separated text slots (currently unused)
class ClosingContextRail extends StatefulWidget {
  const ClosingContextRail({
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
  State<ClosingContextRail> createState() => _ClosingContextRailState();
}

class _ClosingContextRailState extends State<ClosingContextRail> {
  String _assetCacheCode = '';
  String _checkCode = '';
  String _itemCode = '';

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // asset_cache subscription (for category summary)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _assetCacheCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
          appVid,
          tp.tableDocId,
          tp.subColl,
          _assetCacheCode,
        );
      }
    }

    // vehicle_check subscription (for opening doc driver name)
    final String rawCheckTable = (widget.component['checkTable'] ?? '')
        .toString()
        .trim();
    if (rawCheckTable.isNotEmpty) {
      final TablePath ctp = parseTablePath(rawCheckTable);
      if (ctp.tableDocId.isNotEmpty) {
        _checkCode = '$appVid/${ctp.tableDocId}/${ctp.subColl}';
        subscribeToMapCollection(
          appVid,
          ctp.tableDocId,
          ctp.subColl,
          _checkCode,
        );
      }
    }

    // item subscription (for category join)
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

  /// Find the opening vehicle_check doc for the driver name.
  String _resolveDriverName() {
    if (_checkCode.isEmpty) return '-';
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_checkCode] ?? const <Map<String, dynamic>>[],
    );
    final String rawSearch = (widget.component['checkSearch'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return '-';
    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      docs,
      rawSearch,
      widget.scrName,
    );
    if (matched.isEmpty) return '-';
    final String driverField = (widget.component['driverField'] ?? 'cn')
        .toString()
        .trim();
    final String name = (matched.first[driverField] ?? '').toString().trim();
    return name.isNotEmpty ? name : '-';
  }

  /// Count distinct items per category from asset_cache docs.
  /// Returns (returnableCount, consumableCount).
  ({int returnable, int consumable}) _countCategories() {
    if (_assetCacheCode.isEmpty) return (returnable: 0, consumable: 0);

    final List<Map<String, dynamic>> acDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_assetCacheCode] ?? const <Map<String, dynamic>>[],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final List<Map<String, dynamic>> filtered = rawSearch.isNotEmpty
        ? filterDriverHomeDocs(acDocs, rawSearch, widget.scrName)
        : acDocs;

    // Build item detail map for category join
    final List<Map<String, dynamic>> itemDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_itemCode] ?? const <Map<String, dynamic>>[],
    );
    final String joinKey = (widget.component['joinKey'] ?? 'ii')
        .toString()
        .trim();
    final String catField = (widget.component['catField'] ?? 'ic')
        .toString()
        .trim();
    final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
      itemDocs,
      idField: joinKey,
      categoryField: catField,
    );

    // Count distinct items per category
    final Set<String> returnableIds = <String>{};
    final Set<String> consumableIds = <String>{};
    for (final Map<String, dynamic> doc in filtered) {
      final String ii = (doc['ii'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final ItemDetail? detail = itemDetailMap[ii];
      final String category = detail?.category ?? '';
      if (category == 'returnable') {
        returnableIds.add(ii);
      } else if (category == 'consumable') {
        consumableIds.add(ii);
      }
    }
    return (returnable: returnableIds.length, consumable: consumableIds.length);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value; // register Obx dependency

      // Touch reactive stores to trigger rebuild on data arrival
      mapTableContent[_assetCacheCode];
      mapTableContent[_checkCode];
      mapTableContent[_itemCode];

      final String driverName = _resolveDriverName();
      final ({int returnable, int consumable}) cats = _countCategories();

      final String summary =
          '$driverName \u{00B7} ${cats.returnable} returnable \u{00B7} ${cats.consumable} consumable';

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5), // emerald-50
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFA7F3D0), // emerald-200
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Optional left accent bar
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981), // emerald-500
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF065F46), // emerald-800
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
