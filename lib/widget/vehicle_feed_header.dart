import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';
import 'vehicle_feed_support.dart';

/// VEHICLE_FEED_HEADER -- sticky header for H1 VehicleFeed (warehouse checker).
///
/// Row 1: checker avatar (teal gradient, initial) + name + "{station} . Vehicle
/// Runtime" + menu icon.
/// Row 2: 3 flex snapshot count boxes (Perlu Tindakan / Opening Check / Hari Ini).
///
/// Subscribes: workforce (checker name), stock_location (feed rows),
/// vehicle_check (opening/closing gate), task (task state), item (category map).
///
/// Both header and list subscribe the SAME collections. Each computes counts
/// independently (no shared mutable store).
///
/// Read-only: no txfController, no saveSend, no history.
class VehicleFeedHeader extends StatefulWidget {
  const VehicleFeedHeader({
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
  State<VehicleFeedHeader> createState() => _VehicleFeedHeaderState();
}

class _VehicleFeedHeaderState extends State<VehicleFeedHeader> {
  List<String> _textArray = [];
  String _workforceCode = '';
  String _stockLocationCode = '';
  String _vehicleCheckCode = '';
  String _taskCode = '';
  String _itemCode = '';

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

  /// text slot accessors (4 slots):
  ///  [0] "Vehicle Runtime"
  ///  [1] "Perlu Tindakan"
  ///  [2] "Opening Check"
  ///  [3] "Hari Ini"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Workforce (checker name)
    final String rawWorkforceTable = (widget.component['workforceTable'] ?? '')
        .toString()
        .trim();
    if (rawWorkforceTable.isNotEmpty) {
      final TablePath wtp = parseTablePath(rawWorkforceTable);
      if (wtp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _workforceCode = '$appVid/${wtp.tableDocId}/${wtp.subColl}';
        subscribeToMapCollection(
          appVid,
          wtp.tableDocId,
          wtp.subColl,
          _workforceCode,
        );
      }
    }

    // Stock_location (feed rows)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        _stockLocationCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
          appVid,
          tp.tableDocId,
          tp.subColl,
          _stockLocationCode,
        );
      }
    }

    // Vehicle_check (opening/closing gate docs)
    // Subscribe the whole vehicle_check collection; per-lv filtering is in-memory.
    // Extract the tableDocId from openingGate (format: "docId//vehicle_check...")
    final String rawOpeningGate = (widget.component['openingGate'] ?? '')
        .toString()
        .trim();
    if (rawOpeningGate.isNotEmpty) {
      final String decoded = autheniumDecode(rawOpeningGate) ?? rawOpeningGate;
      // The gate string is "docId//vehicle_check⭘cty◼opening⭘vv◼{lv}"
      // parseTablePath extracts docId//subColl from the part before first ⭘
      final String tablePart = decoded.split('\u{2B58}').first.trim();
      final TablePath vtp = parseTablePath(tablePart);
      if (vtp.tableDocId.isNotEmpty) {
        _vehicleCheckCode = '$appVid/${vtp.tableDocId}/${vtp.subColl}';
        subscribeToMapCollection(
          appVid,
          vtp.tableDocId,
          vtp.subColl,
          _vehicleCheckCode,
        );
      }
    }

    // Task (task docs)
    final String rawTaskTable = (widget.component['taskTable'] ?? '')
        .toString()
        .trim();
    if (rawTaskTable.isNotEmpty) {
      final TablePath ttp = parseTablePath(rawTaskTable);
      if (ttp.tableDocId.isNotEmpty) {
        _taskCode = '$appVid/${ttp.tableDocId}/${ttp.subColl}';
        subscribeToMapCollection(
          appVid,
          ttp.tableDocId,
          ttp.subColl,
          _taskCode,
        );
      }
    }

    // Item (for category map -- derive from vidtable + 'item' subColl)
    // The item table is under the same vidtable, subcollection 'item'.
    final String rawVidtable = (widget.component['vidtable'] ?? '')
        .toString()
        .trim();
    if (rawVidtable.isNotEmpty) {
      // Use the same tableDocId from stock_location but subColl = 'item'
      final String rawSL = (widget.component['table'] ?? '').toString().trim();
      if (rawSL.isNotEmpty) {
        final TablePath sltp = parseTablePath(rawSL);
        if (sltp.tableDocId.isNotEmpty) {
          _itemCode = '$appVid/${sltp.tableDocId}/item';
          subscribeToMapCollection(appVid, sltp.tableDocId, 'item', _itemCode);
        }
      }
    }
  }

  /// Find the checker's workforce doc.
  Map<String, dynamic>? _findCheckerDoc() {
    if (_workforceCode.isEmpty) return null;
    final String checkerVid = (transactionStore.state.screenTx['#VID'] ?? '')
        .toString()
        .trim();
    if (checkerVid.isEmpty) return null;
    final List<Map<String, dynamic>> wfDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_workforceCode] ?? const [],
    );
    for (final doc in wfDocs) {
      final String docVid = (doc['VID'] ?? doc['vid'] ?? '').toString().trim();
      if (docVid == checkerVid) return doc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Register Obx dependencies by touching reactive maps
      mapTableContent[_workforceCode];
      mapTableContent[_stockLocationCode];
      mapTableContent[_vehicleCheckCode];
      mapTableContent[_taskCode];
      mapTableContent[_itemCode];

      // Checker identity
      final Map<String, dynamic>? checkerDoc = _findCheckerDoc();
      final String nameField = (widget.component['nameField'] ?? 'n')
          .toString();
      String checkerName = (checkerDoc?[nameField] ?? '').toString().trim();
      // Fallback to the logged-in user's name (#NAME) -- the same source the
      // Admin header uses -- when no workforce doc resolves (workforceTable
      // unconfigured or no #VID match). Guarantees the header shows who is
      // logged in instead of a bare "-".
      if (checkerName.isEmpty) {
        checkerName = (transactionStore.state.screenTx['#NAME'] ?? '')
            .toString()
            .trim();
      }
      final String initial = checkerName.isNotEmpty
          ? checkerName[0].toUpperCase()
          : '?';
      final String station = (widget.component['station'] ?? '')
          .toString()
          .trim();

      // Title from text[0]
      final String title = _t(0, 'Vehicle Runtime');
      final String subtitle = station.isNotEmpty
          ? '$station \u{00B7} $title'
          : title;

      // Build feed for snapshot counts
      final List<Map<String, dynamic>> stockDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_stockLocationCode] ?? const [],
          );
      // Apply the search filter from component config
      final String rawSearch = (widget.component['search'] ?? '')
          .toString()
          .trim();
      final List<Map<String, dynamic>> filteredStock = rawSearch.isNotEmpty
          ? filterDriverHomeDocs(stockDocs, rawSearch, widget.scrName)
          : stockDocs;

      final List<Map<String, dynamic>> checkDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_vehicleCheckCode] ?? const [],
          );
      final List<Map<String, dynamic>> taskDocsAll =
          List<Map<String, dynamic>>.from(
            mapTableContent[_taskCode] ?? const [],
          );
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );

      final Map<String, String> categoryMap = buildItemCategoryMap(itemDocs);
      final String todayEpoch = todayEpochMidnightWib();

      final List<VehicleFeedEntry> feed = buildVehicleFeed(
        stockDocs: filteredStock,
        vehicleCheckDocs: checkDocs,
        taskDocs: taskDocsAll,
        categoryMap: categoryMap,
        todayEpoch: todayEpoch,
      );

      final VehicleSnapshot snap = computeSnapshot(feed);

      // Text labels
      final String perluLabel = _t(1, 'Perlu Tindakan');
      final String openingLabel = _t(2, 'Opening Check');
      final String hariIniLabel = _t(3, 'Hari Ini');

      // Menu route
      final String menuRoute = (widget.component['menuRoute'] ?? '')
          .toString()
          .trim();

      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Row 1: Identity + menu ──────────────────────────────
            Row(
              children: [
                // Teal gradient avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Name + station subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        checkerName.isNotEmpty ? checkerName : '-',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937), // gray-900
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280), // textMid
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Menu icon -- rendered ONLY when menuRoute is configured.
                // Empty menuRoute (e.g. H1 warehouse feed) hides it entirely.
                if (menuRoute.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      routeStack.push(menuRoute);
                      gotoRoute(menuRoute);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.menu,
                        size: 22,
                        color: Color(0xFF374151), // gray-700
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Row 2: 3 Snapshot boxes ─────────────────────────────
            Row(
              children: [
                // Perlu Tindakan (amber highlight if > 0)
                Expanded(
                  child: _buildCountBox(
                    label: perluLabel,
                    count: snap.perluTindakan,
                    highlight: snap.perluTindakan > 0,
                  ),
                ),
                const SizedBox(width: 8),
                // Opening Check
                Expanded(
                  child: _buildCountBox(
                    label: openingLabel,
                    count: snap.openingCheck,
                    highlight: false,
                  ),
                ),
                const SizedBox(width: 8),
                // Hari Ini
                Expanded(
                  child: _buildCountBox(
                    label: hariIniLabel,
                    count: snap.hariIni,
                    highlight: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCountBox({
    required String label,
    required int count,
    required bool highlight,
  }) {
    final Color bgColor = highlight
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFF9FAFB);
    final Color countColor = highlight
        ? const Color(0xFFD97706)
        : const Color(0xFF1F2937);
    final Color labelColor = highlight
        ? const Color(0xFFB45309)
        : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight
              ? const Color(0xFFFDE68A) // amber-200
              : const Color(0xFFE5E7EB), // gray-200
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: countColor,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: labelColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
