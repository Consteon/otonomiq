import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// VEHICLE_CUSTODY_HEADER -- vehicle custody card for P5 CustodyNotification.
///
/// **STATEFUL PUBLISHER of vehicleId.** P5 has no route_progress_header, so
/// this widget fills the vehicleId publisher role. It:
/// 1. Subscribes stock_location via `vehicleTable`.
/// 2. Finds the vehicle doc by `lt=='vehicle' && dv==driverVid` (driverVid
///    from `#has_user_login`), mirroring route_progress_header._findVehicleDoc
///    (rph:124-138).
/// 3. Publishes `lv` into `getDriverHomeState(scrName).vehicleId` via
///    `_publishVehicleId()` (post-frame callback with mounted + equality guard),
///    mirroring route_progress_header._publishVehicleId (rph:145-158).
/// 4. Once vehicleId is published, its own vehicle_check search
///    (`vv◼{vehicleId}`) resolves reactively on the next Obx pass.
///
/// Also reads the `vehicle_check` opening doc to display:
///   - Vehicle plate (from stock_location `ln`, via vehicleDoc)
///   - Custody event id (`cnm`)
///   - Dimuat oleh (`gn`) -- FUTURE field, shows "--" when absent
///   - Waktu loading (`ldt`) -- FUTURE field, shows "--" when absent
///
/// The `vehicleSearch` component field is unused/legacy -- the join is by
/// driverVid, not by a curly-token search.
///
/// `transactionStore` is read (not dispatched) for `#has_user_login`; it is a
/// top-level `dynamic` in global.dart, so no `screen_transaction.dart` import
/// is needed (I5 -- avoid the unused-import warning).
///
/// Read-only: no txfController, no saveSend, no history.
class VehicleCustodyHeader extends StatefulWidget {
  const VehicleCustodyHeader({
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
  State<VehicleCustodyHeader> createState() => _VehicleCustodyHeaderState();
}

class _VehicleCustodyHeaderState extends State<VehicleCustodyHeader> {
  List<String> _textArray = [];
  String _checkCode = ''; // vehicle_check subscription code
  String _slCode = ''; // stock_location subscription code

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
  ///  [0] "Penerimaan Muatan"  (parsed but unused on icon row -- title is app bar)
  ///  [1] "Dimuat oleh"        (loader label)
  ///  [2] "Waktu loading"      (loadtime label)
  ///  [3] "Custody event"      (event label)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // vehicle_check subscription
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }

    // stock_location subscription (vehicleId derivation + plate display)
    final String rawVehicleTable = (widget.component['vehicleTable'] ?? '')
        .toString()
        .trim();
    if (rawVehicleTable.isNotEmpty) {
      final TablePath vtp = parseTablePath(rawVehicleTable);
      if (vtp.tableDocId.isNotEmpty) {
        _slCode = '$appVid/${vtp.tableDocId}/${vtp.subColl}';
        subscribeToMapCollection(appVid, vtp.tableDocId, vtp.subColl, _slCode);
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
  /// This mirrors route_progress_header._findVehicleDoc (rph:124-138).
  ///
  /// Returns null when: _slCode empty, no docs loaded, no match, or
  /// driverVid empty.
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
  /// This mirrors route_progress_header._publishVehicleId (rph:145-158).
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

  /// Find the first matching vehicle_check opening doc.
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
    return matched.isNotEmpty ? matched.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch vehicleId to register Obx dependency (downstream searches use
      // {vehicleId} which resolves after _publishVehicleId fires).
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;

      // Step 1: Find vehicle doc and publish vehicleId.
      final Map<String, dynamic>? vehicleDoc = _findVehicleDoc();
      _publishVehicleId(vehicleDoc);

      // Publish activeTrip from vehicle_check data (GAP A fix for P5:
      // CustodyNotification has no gate widget pointing at vehicle_check,
      // so evaluateGateSearch never fires resolveAndPublishActiveTrip on
      // this page). Safe: idempotent + deferred + guarded.
      resolveAndPublishActiveTrip(widget.scrName, _checkCode);

      // Step 2: Read plate from the vehicle doc (same doc).
      final String plateField = (widget.component['plateField'] ?? 'ln')
          .toString();
      final String plate = (vehicleDoc?[plateField] ?? '').toString().trim();

      // Step 3: Find vehicle_check doc (search resolves once vehicleId is
      // published on the reactive Obx pass).
      final Map<String, dynamic>? checkDoc = _findCheckDoc();

      // Field reads from component config (server-overridable)
      final String eventField = (widget.component['eventField'] ?? 'cnm')
          .toString();
      final String loaderField = (widget.component['loaderField'] ?? 'gn')
          .toString();
      final String loadtimeField = (widget.component['loadtimeField'] ?? 'ldt')
          .toString();

      // Resolved values
      final String eventId = (checkDoc?[eventField] ?? '').toString().trim();
      final String loader = (checkDoc?[loaderField] ?? '').toString().trim();
      final String loadtime = (checkDoc?[loadtimeField] ?? '')
          .toString()
          .trim();

      // Labels from text slots
      final String loaderLabel = _t(1, 'Dimuat oleh');
      final String loadtimeLabel = _t(2, 'Waktu loading');
      final String eventLabel = _t(3, 'Custody event');

      // FUTURE fields: show em-dash when empty
      final String loaderDisplay = loader.isNotEmpty ? loader : '\u{2014}';
      final String loadtimeDisplay = loadtime.isNotEmpty
          ? loadtime
          : '\u{2014}';
      final String eventDisplay = eventId.isNotEmpty ? eventId : '\u{2014}';

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
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
              // Header: rounded-square truck icon + plate as large primary text
              Row(
                children: [
                  // Rounded-square icon container (gray-100 bg)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6), // gray-100
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.local_shipping,
                      size: 22,
                      color: Color(0xFF4338CA),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Plate as primary element
                  Expanded(
                    child: Text(
                      plate.isNotEmpty ? plate : '\u{2014}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: plate.isNotEmpty
                            ? const Color(0xFF1F2937) // gray-900
                            : const Color(0xFF9CA3AF), // gray-400 for dash
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              // Divider separating header from detail rows
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0F1F3),
                ),
              ),
              // Loader label/value row
              _buildInfoRow(loaderLabel, loaderDisplay),
              const SizedBox(height: 8),
              // Loadtime label/value row
              _buildInfoRow(loadtimeLabel, loadtimeDisplay),
              const SizedBox(height: 8),
              // Event label/value row
              _buildInfoRow(eventLabel, eventDisplay),
            ],
          ),
        ),
      );
    });
  }

  /// A label/value row: left-aligned label (grey), right-aligned value.
  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF6B7280), // gray-500
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: value == '\u{2014}'
                ? const Color(0xFF9CA3AF) // gray-400 for dash
                : const Color(0xFF1F2937), // gray-900 for value
          ),
        ),
      ],
    );
  }
}
