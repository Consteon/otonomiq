import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_STEP_HEADER -- title + plate + STEP badge for P6 CustodyCount.
///
/// **STATEFUL PUBLISHER of vehicleId.** P6 has no route_progress_header, so
/// this widget fills the vehicleId publisher role (same as
/// vehicle_custody_header on P5). It:
/// 1. Subscribes stock_location via `vehicleTable`.
/// 2. Finds the vehicle doc by `lt=='vehicle' && dv==driverVid` (driverVid
///    from `#has_user_login`), mirroring route_progress_header._findVehicleDoc.
/// 3. Publishes `lv` into `getDriverHomeState(scrName).vehicleId` via
///    `_publishVehicleId()` (post-frame callback with mounted + equality guard).
/// 4. Renders: title text (slot 0) + plate (from vehicleDoc) + STEP badge
///    (slot 1).
///
/// Back navigation is handled by the app-shell AppBar (main_page.dart:400);
/// this widget does NOT render its own back arrow.
///
/// Read-only: no txfController, no saveSend, no history.
class CustodyStepHeader extends StatefulWidget {
  const CustodyStepHeader({
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
  State<CustodyStepHeader> createState() => _CustodyStepHeaderState();
}

class _CustodyStepHeaderState extends State<CustodyStepHeader> {
  List<String> _textArray = [];
  String _slCode = ''; // stock_location subscription code
  String _wfCode = ''; // workforce subscription code (driverName derivation)

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

  /// text slot accessors (2 slots):
  ///  [0] "KONFIRMASI PENERIMAAN"  (title)
  ///  [1] "STEP 1/2"              (step badge)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Stock_location subscription (vehicleId derivation + plate display).
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

    // Workforce subscription (driverName derivation).
    // Optional: only if component['workforceTable'] is set. When absent, the
    // header behaves identically to its original implementation (no
    // subscription, driverName stays empty -- additive/backwards compatible).
    final String rawWorkforceTable = (widget.component['workforceTable'] ?? '')
        .toString()
        .trim();
    if (rawWorkforceTable.isNotEmpty) {
      final TablePath wtp = parseTablePath(rawWorkforceTable);
      if (wtp.tableDocId.isNotEmpty) {
        _wfCode = '$appVid/${wtp.tableDocId}/${wtp.subColl}';
        subscribeToMapCollection(appVid, wtp.tableDocId, wtp.subColl, _wfCode);
      }
    }
  }

  /// Find the workforce doc for the current driver.
  ///
  /// Matches on `VID == driverVid` (uppercase per spec, lowercase `vid`
  /// fallback -- mirrors route_progress_header._findDriverDoc:101-113).
  /// driverVid from #has_user_login. Returns null if no workforce subscription
  /// or no match.
  Map<String, dynamic>? _findDriverDoc() {
    if (_wfCode.isEmpty) return null;
    final String driverVid =
        (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
    if (driverVid.isEmpty) return null;
    final List<Map<String, dynamic>> wfDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_wfCode] ?? const [],
    );
    for (final doc in wfDocs) {
      final String docVid = (doc['VID'] ?? doc['vid'] ?? '').toString().trim();
      if (docVid == driverVid) return doc;
    }
    return null;
  }

  /// Publish driverName from the workforce doc into DriverHomeState.
  ///
  /// Post-frame deferred to avoid Rx mutation during build (mirrors
  /// _publishVehicleId). When [driverDoc] is null (no workforce subscription
  /// or no match), derivedName is empty; the equality guard prevents the
  /// post-frame callback from firing -- zero overhead for non-workforce pages.
  void _publishDriverName(Map<String, dynamic>? driverDoc) {
    final String nameField = (widget.component['nameField'] ?? 'n').toString();
    final String derivedName = (driverDoc?[nameField] ?? '').toString().trim();
    final DriverHomeState state = getDriverHomeState(widget.scrName);
    if (state.driverName.value == derivedName) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final DriverHomeState s = getDriverHomeState(widget.scrName);
      if (s.driverName.value != derivedName) {
        s.driverName.value = derivedName;
      }
    });
  }

  /// Find the stock_location vehicle doc assigned to the current driver.
  ///
  /// Iterates mapTableContent[_slCode] for a doc where lt=='vehicle' AND
  /// dv==driverVid (driverVid from #has_user_login). Returns the full doc Map
  /// for both vehicleId derivation (_publishVehicleId reads `lv`) and plate
  /// display (build reads `ln` via plateField).
  ///
  /// Mirrors route_progress_header._findVehicleDoc (rph:124-138) and
  /// vehicle_custody_header._findVehicleDoc.
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
  /// Mirrors route_progress_header._publishVehicleId (rph:145-158).
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

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch vehicleId to register Obx dependency.
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;

      // Step 1: Find vehicle doc and publish vehicleId.
      final Map<String, dynamic>? vehicleDoc = _findVehicleDoc();
      _publishVehicleId(vehicleDoc);

      // Step 1b: Publish driverName from the workforce doc (if subscribed).
      // Touch mapTableContent[_wfCode] inside the Obx so it re-publishes when
      // workforce docs arrive/change. No-op when _wfCode is empty.
      mapTableContent[_wfCode];
      final Map<String, dynamic>? driverDoc = _findDriverDoc();
      _publishDriverName(driverDoc);

      // Step 2: Read plate from the vehicle doc.
      final String plateField = (widget.component['plateField'] ?? 'ln')
          .toString();
      final String plate = (vehicleDoc?[plateField] ?? '').toString().trim();

      // Text slots
      final String title = _t(0, 'KONFIRMASI PENERIMAAN');
      final String stepBadge = _t(1, 'STEP 1/2');

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
            // Row: title + step badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937), // gray-900
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // STEP badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF), // indigo-50
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    stepBadge,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4338CA), // indigo-700
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Plate subtitle
            Row(
              children: [
                const Icon(
                  Icons.local_shipping,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  plate.isNotEmpty ? plate : '\u{2014}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: plate.isNotEmpty
                        ? const Color(0xFF374151) // gray-700
                        : const Color(0xFF9CA3AF), // gray-400 for dash
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
