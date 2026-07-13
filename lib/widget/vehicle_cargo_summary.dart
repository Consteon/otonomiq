import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'notice_bar.dart';
import 'panel_card_support.dart';

/// VEHICLE_CARGO_SUMMARY -- intro paragraph + "Sisa di Kendaraan" per-item
/// cargo card for P12 ReturnVehicle.
///
/// **STATEFUL PUBLISHER of vehicleId.** P12 has no other publisher, so this
/// widget fills the vehicleId publisher role. It:
/// 1. Subscribes stock_location via `vehicleTable`.
/// 2. Finds the vehicle doc by `lt=='vehicle' && dv==driverVid` (driverVid
///    from `#has_user_login`), mirroring vehicle_custody_header._findVehicleDoc.
/// 3. Publishes `lv` into `getDriverHomeState(scrName).vehicleId` via
///    `_publishVehicleId()` (post-frame callback with mounted + equality guard).
/// 4. Reads plate (`ln`) from the SAME derived vehicle doc.
///
/// Also subscribes `asset_cache` for the cargo card and `item` for name
/// resolution. Groups asset_cache docs by item id (`ii`), sums quantity
/// per condition (`cd`), resolves item names from the item master collection
/// via the shared [computePerItemCargoRows] / [buildItemNameMap] helpers.
///
/// Read-only: no txfController, no saveSend, no history.
class VehicleCargoSummary extends StatefulWidget {
  const VehicleCargoSummary({
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

  // ---- Field codes for asset_cache ----
  // Real schema: lv, lt, ii, cd, qt, et, lm, t.
  // Doc id format: {lv}__{ii}__{cd}.
  static const String kConditionField = 'cd';
  static const String kQtyField = 'qt';
  static const String kItemField = 'ii';

  // Condition filter values
  static const String kConditionFull = 'full'; // isi
  static const String kConditionEmpty = 'empty'; // kosong

  @override
  State<VehicleCargoSummary> createState() => _VehicleCargoSummaryState();
}

class _VehicleCargoSummaryState extends State<VehicleCargoSummary> {
  List<String> _textArray = [];
  String _slCode = ''; // stock_location subscription code
  String _cacheCode = ''; // asset_cache subscription code
  String _itemCode = ''; // item collection subscription code (name FK)

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

  /// text slot accessors (6 slots):
  ///  [0] introA ("Serahkan kendaraan")
  ///  [1] introB (" + sisa muatan ke gudang. ...")
  ///  [2] cardTitle ("Sisa di Kendaraan")
  ///  [3] fullLabel ("isi")
  ///  [4] emptyLabel ("kosong")
  ///  [5] emptyState ("Tidak ada sisa muatan")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // stock_location subscription (vehicleId derivation + plate display)
    final String rawVehicleTable = (widget.component['vehicleTable'] ?? '')
        .toString()
        .trim();
    if (rawVehicleTable.isNotEmpty) {
      final TablePath vtp = parseTablePath(rawVehicleTable);
      if (vtp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _slCode = '$appVid/${vtp.tableDocId}/${vtp.subColl}';
        subscribeToMapCollection(appVid, vtp.tableDocId, vtp.subColl, _slCode);
      }
    }

    // asset_cache subscription (cargo counts)
    final String rawCacheTable = (widget.component['cacheTable'] ?? '')
        .toString()
        .trim();
    if (rawCacheTable.isNotEmpty) {
      final TablePath ctp = parseTablePath(rawCacheTable);
      if (ctp.tableDocId.isNotEmpty) {
        _cacheCode = '$appVid/${ctp.tableDocId}/${ctp.subColl}';
        subscribeToMapCollection(
          appVid,
          ctp.tableDocId,
          ctp.subColl,
          _cacheCode,
        );
      }
    }

    // CHANGED: item collection subscription (name FK resolution: ii -> in)
    // Follows the inventory_bucket_card / precondition_gate_card pattern.
    // component['itemTable'] = "84214220504259//item" or bare "item".
    final String rawItemTable = (widget.component['itemTable'] ?? '')
        .toString()
        .trim();
    if (rawItemTable.isNotEmpty) {
      final TablePath ctp = parseTablePath(rawCacheTable);
      final String mainTableDocId = ctp.tableDocId;
      if (!rawItemTable.contains('//') && mainTableDocId.isNotEmpty) {
        // Bare name: subscribe as subcollection under the cache table's docId
        _itemCode = '$appVid/$mainTableDocId/$rawItemTable';
        subscribeToMapCollection(
          appVid,
          mainTableDocId,
          rawItemTable,
          _itemCode,
        );
      } else {
        final TablePath itp = parseTablePath(rawItemTable);
        if (itp.tableDocId.isNotEmpty) {
          _itemCode = '$appVid/${itp.tableDocId}/${itp.subColl}';
          subscribeToMapCollection(
            appVid,
            itp.tableDocId,
            itp.subColl,
            _itemCode,
          );
        }
      }
    }
  }

  /// Find the stock_location vehicle doc assigned to the current driver.
  ///
  /// Iterates mapTableContent[_slCode] for a doc where lt=='vehicle' AND
  /// dv==driverVid (driverVid from #has_user_login). Returns the full doc Map
  /// for both vehicleId derivation (_publishVehicleId reads `lv`) and plate
  /// display (build reads `ln` via plateField).
  ///
  /// Mirrors vehicle_custody_header._findVehicleDoc,
  /// route_feed_header._findVehicleDoc (rph:124-138).
  Map<String, dynamic>? _findVehicleDoc() {
    if (_slCode.isEmpty) return null;
    final String driverVid =
        (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
    if (driverVid.isEmpty) return null;
    final List<Map<String, dynamic>> slDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_slCode] ?? const [],
    );
    for (final doc in slDocs) {
      final String lt = (doc['lt'] ?? '').toString().trim();
      final String dv = (doc['dv'] ?? '').toString().trim();
      if (lt == 'vehicle' && dv == driverVid) return doc;
    }
    return null;
  }

  /// Derive and publish vehicleId from the stock_location vehicle doc.
  ///
  /// Reads `lv` from the doc returned by [_findVehicleDoc].
  /// W1: deferred to a post-frame callback -- never set an Rx that a mounted
  /// dependent Obx reads synchronously inside build.
  ///
  /// Mirrors vehicle_custody_header._publishVehicleId,
  /// route_feed_header._publishVehicleId (rph:145-158).
  void _publishVehicleId(Map<String, dynamic>? vehicleDoc) {
    final String derivedVehicleId = (vehicleDoc?['lv'] ?? '').toString().trim();
    final DriverHomeState state = getDriverHomeState(widget.scrName);
    if (state.vehicleId.value == derivedVehicleId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final DriverHomeState s = getDriverHomeState(widget.scrName);
      if (s.vehicleId.value != derivedVehicleId) {
        s.vehicleId.value = derivedVehicleId;
        s.vehicleIdResolved.value = true;
      }
    });
  }

  /// Get filtered asset_cache docs for this vehicle.
  ///
  /// Uses filterDriverHomeDocs with the `cacheSearch` component field
  /// (e.g. `lv◼{vehicleId}`). The {vehicleId} token resolves reactively
  /// once _publishVehicleId fires. Before that, filterDriverHomeDocs returns
  /// empty (unresolved-token guard) -- degrade-safe.
  List<Map<String, dynamic>> _getFilteredCacheDocs() {
    if (_cacheCode.isEmpty) return const [];
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_cacheCode] ?? const [],
    );
    final String rawSearch = (widget.component['cacheSearch'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return docs;
    return filterDriverHomeDocs(docs, rawSearch, widget.scrName);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // --- Reactive reads (register Obx dependencies) ---
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;
      mapTableContent[_slCode]; // register dependency
      mapTableContent[_cacheCode]; // register dependency
      mapTableContent[_itemCode]; // CHANGED: register item dependency

      // Step 1: Find vehicle doc and publish vehicleId.
      final Map<String, dynamic>? vehicleDoc = _findVehicleDoc();
      _publishVehicleId(vehicleDoc);

      // Step 2: Read plate from the vehicle doc (same doc).
      final String plateField = (widget.component['plateField'] ?? 'ln')
          .toString();
      final String plate = (vehicleDoc?[plateField] ?? '').toString().trim();

      // Step 3: Get filtered asset_cache docs.
      final List<Map<String, dynamic>> cacheDocs = _getFilteredCacheDocs();

      // Spec §2 config keys: item-join + condition field/value overrides.
      // Defaults match the live asset_cache/item schema, so a JSON that omits
      // any of these behaves exactly as before.
      final String itemKey =
          (widget.component['itemKey'] ?? VehicleCargoSummary.kItemField)
              .toString()
              .trim();
      final String nameField = (widget.component['nameField'] ?? 'in')
          .toString()
          .trim();
      final String unitField = (widget.component['unitField'] ?? 'un')
          .toString()
          .trim();
      final String condField =
          (widget.component['condField'] ?? VehicleCargoSummary.kConditionField)
              .toString()
              .trim();
      final String fullValue =
          (widget.component['fullValue'] ?? VehicleCargoSummary.kConditionFull)
              .toString()
              .trim();
      final String emptyValue =
          (widget.component['emptyValue'] ??
                  VehicleCargoSummary.kConditionEmpty)
              .toString()
              .trim();

      // CHANGED: Step 4: Build item name + unit maps from item subscription
      // (name FK: ii -> in; unit FK: ii -> un, per spec §2 — drives the
      // per-condition "{un} isi {qty}" prefix instead of a hardcoded label).
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final Map<String, String> itemNameMap = buildItemNameMap(
        itemDocs,
        idField: itemKey,
        nameField: nameField,
      );
      final Map<String, String> itemUnitMap = buildItemUnitMap(
        itemDocs,
        idField: itemKey,
        unitField: unitField,
      );

      // CHANGED: Step 5: Compute per-item rows via the shared pure helper
      // (replaces the fixed bucket computation; aggregation lives in
      // driver_home_support.dart, not here).
      final List<CargoItemRow> rawRows = computePerItemCargoRows(
        cacheDocs,
        itemNameMap,
        itemUnitMap: itemUnitMap,
        itemField: itemKey,
        conditionField: condField,
        qtyField: VehicleCargoSummary.kQtyField,
        conditionFull: fullValue,
        conditionEmpty: emptyValue,
      );

      // hideZero: drop items whose full AND empty are both 0 (stale
      // asset_cache docs from past trips). Reuses the shared helper from
      // driver_home_support.dart (same as INVENTORY_BUCKET_CARD et al.).
      final bool hideZero = hideZeroEnabled(widget.component);
      final List<CargoItemRow> itemRows = hideZero
          ? rawRows.where((r) => r.fullQty != 0 || r.emptyQty != 0).toList()
          : rawRows;

      // Text slots with defaults
      final String introA = _t(0, 'Serahkan kendaraan');
      final String introB = _t(1, '');
      final String cardTitle = _t(2, 'Sisa di Kendaraan');
      final String fullLabel = _t(3, 'isi');
      final String emptyLabel = _t(4, 'kosong');
      final String emptyState = _t(5, 'Tidak ada sisa muatan');

      // Intro text: "Serahkan kendaraan **B 1234 XY** + sisa muatan ke gudang."
      // Bold plate injected between introA and introB via ** markers.
      final String platePart = plate.isNotEmpty ? ' **$plate**' : '';
      final String introSrc = '$introA$platePart$introB';

      // Parse inline **bold** for the plate
      const TextStyle introBase = TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: Color(0xFF6B7280), // gray-500
      );
      final List<InlineSpan> introSpans = parseInlineEmphasis(
        introSrc,
        introBase,
      );

      return Padding(
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
            // -- Intro paragraph --
            if (introSpans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text.rich(
                  TextSpan(children: introSpans),
                  textAlign: TextAlign.left,
                ),
              ),

            // -- Cargo card --
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Card title
                  Text(
                    cardTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937), // gray-900
                    ),
                  ),
                  const SizedBox(height: 12),
                  // CHANGED: per-item rows or empty state
                  if (itemRows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        emptyState,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF), // gray-400
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < itemRows.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFF0F1F3),
                        ),
                      Padding(
                        padding: EdgeInsets.only(
                          top: i > 0 ? 10 : 0,
                          bottom: i < itemRows.length - 1 ? 10 : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Item name header
                            Text(
                              itemRows[i].displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151), // gray-700
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Condition sub-row: fullLabel qty   emptyLabel qty
                            Row(
                              children: [
                                // Full (isi) -- "{un} isi" per spec §2; the
                                // unit degrades to a bare "isi" when absent.
                                Text(
                                  itemRows[i].unit.isEmpty
                                      ? fullLabel
                                      : '${itemRows[i].unit} $fullLabel',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280), // gray-500
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  itemRows[i].fullQty.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF1F2937), // gray-900
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // Empty (kosong) -- "{un} kosong" per spec §2;
                                // the unit degrades to a bare "kosong" when absent.
                                Text(
                                  itemRows[i].unit.isEmpty
                                      ? emptyLabel
                                      : '${itemRows[i].unit} $emptyLabel',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280), // gray-500
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  itemRows[i].emptyQty.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF1F2937), // gray-900
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
