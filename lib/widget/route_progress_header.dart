import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ROUTE_PROGRESS_HEADER — driver identity header (data-bound, NO avatar).
///
/// variant:"identityOnly" renders driver name + plate/vehicle subtitle
/// + "Keluar" button. Name comes from the workforce doc field
/// (`component['nameField']`, default `n`). Plate comes from the stock_location
/// vehicle doc field (`component['plateField']`, default `ln`).
///
/// Subscribes to the workforce subcollection (driver name) and the
/// stock_location subcollection (`component['vehicleTable']`), derives the
/// vehicleId from the stock_location doc where `lt=='vehicle'` AND
/// `dv=={driverVid}` (taking `lv`), and publishes it into DriverHomeState for
/// downstream gate widgets.
class RouteProgressHeader extends StatefulWidget {
  const RouteProgressHeader({
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
  State<RouteProgressHeader> createState() => _RouteProgressHeaderState();
}

class _RouteProgressHeaderState extends State<RouteProgressHeader> {
  List<String> _textArray = [];
  String _workforceCode = '';
  String _stockLocationCode = '';

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

  /// text slot accessors (8 LABEL-ONLY slots per spec §2.1):
  ///  [0] "Rute Hari Ini"
  ///  [1] "stop"
  ///  [2] "gagal"
  ///  [3] "Drop"
  ///  [4] "Pickup"
  ///  [5] "kendaraan ditugaskan"
  ///  [6] "Keluar"
  ///  [7] "Belum ditugaskan kendaraan"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Workforce subscription (driver name for P2 display).
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _workforceCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
        appVid,
        tp.tableDocId,
        tp.subColl,
        _workforceCode,
      );
    }

    // Stock_location subscription (vehicleId derivation per spec section 0-B).
    // component['vehicleTable'] = "84214220504259//stock_location"
    final String rawVehicleTable = (widget.component['vehicleTable'] ?? '')
        .toString()
        .trim();
    if (rawVehicleTable.isNotEmpty) {
      final TablePath vtp = parseTablePath(rawVehicleTable);
      if (vtp.tableDocId.isNotEmpty) {
        _stockLocationCode = '$appVid/${vtp.tableDocId}/${vtp.subColl}';
        subscribeToMapCollection(
          appVid,
          vtp.tableDocId,
          vtp.subColl,
          _stockLocationCode,
        );
      }
    }
  }

  /// Find the driver doc from workforce by matching VID field to (DRIVERVID).
  Map<String, dynamic>? _findDriverDoc(List<Map<String, dynamic>> docs) {
    final String driverVid =
        (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
    if (driverVid.isEmpty) return null;
    // workforce docs use field 'VID' (uppercase per spec) — verify against real
    // data; fall back to lowercase 'vid' if uppercase not found.
    for (final doc in docs) {
      final String docVid = (doc['VID'] ?? doc['vid'] ?? '').toString().trim();
      if (docVid == driverVid) return doc;
    }
    return null;
  }

  /// Find the stock_location vehicle doc assigned to the current driver.
  ///
  /// Iterates mapTableContent[_stockLocationCode] for a doc where
  /// lt=='vehicle' AND dv==driverVid. Returns the full doc Map for both
  /// vehicleId derivation (_publishVehicleId reads `lv`) and plate display
  /// (build reads `ln` via component['plateField']).
  ///
  /// Returns null when: _stockLocationCode empty, no docs loaded, no match,
  /// or driverVid empty.
  Map<String, dynamic>? _findVehicleDoc() {
    if (_stockLocationCode.isEmpty) return null;
    final String driverVid =
        (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
    if (driverVid.isEmpty) return null;
    final List<Map<String, dynamic>> slDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_stockLocationCode] ?? const [],
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
  /// Reads `lv` from the doc returned by `_findVehicleDoc()`.
  /// W1: deferred to a post-frame callback — never set an Rx that a mounted
  /// dependent Obx (the gate card) reads synchronously inside build.
  ///
  /// Sets `vehicleIdResolved = true` once the stock_location subscription has
  /// delivered data, EVEN when `derivedVehicleId` is empty (unassigned driver).
  /// Without this, the downstream gate `vehicleIdResolved && vehicleId.isEmpty`
  /// never fires and unassigned drivers see other vehicles' cards.
  ///
  /// The "data loaded" signal is `mapTableContent.containsKey(_stockLocationCode)`:
  /// `subscribeToMapCollection` sets `mapTableContent[code]` only when the first
  /// Firestore snapshot arrives. Before that, `containsKey` is false, so we do
  /// NOT set `vehicleIdResolved` prematurely (which would flash "unassigned" for
  /// an assigned driver whose vehicle doc hasn't arrived yet).
  void _publishVehicleId(Map<String, dynamic>? vehicleDoc) {
    final String derivedVehicleId = (vehicleDoc?['lv'] ?? '').toString().trim();
    final DriverHomeState state = getDriverHomeState(widget.scrName);

    // Data-loaded signal: stock_location subscription has delivered at least
    // one snapshot. Before that, mapTableContent[_stockLocationCode] is absent.
    final bool dataLoaded =
        _stockLocationCode.isNotEmpty &&
        mapTableContent.containsKey(_stockLocationCode);

    // Skip when both vehicleId value and resolved flag are already current.
    if (state.vehicleId.value == derivedVehicleId &&
        state.vehicleIdResolved.value == dataLoaded) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final DriverHomeState s = getDriverHomeState(widget.scrName);
      if (s.vehicleId.value != derivedVehicleId) {
        s.vehicleId.value = derivedVehicleId;
      }
      if (dataLoaded && !s.vehicleIdResolved.value) {
        s.vehicleIdResolved.value = true;
      }
    });
  }

  void _onLogoutTap() {
    // ---- Hard driver logout (NOT a Firebase signOut) ----
    // The driver is NOT a Firebase user; do NOT call signOut()/FirebaseAuth/
    // GoogleSignIn here. This only tears down the driver session.

    // 1. Clear #has_user_login in the Redux transactionStore.
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#has_user_login': ''})),
    );

    // 2. Clear the persisted driver login from secure storage (mirror of 1).
    unawaited(clearDriverLogin());

    // 3. Clear per-scrName DriverHomeState (reactive vehicleId, confirmed, ...).
    clearDriverHomeState(widget.scrName);

    // 4. Navigate to home. routeStack.push(home) truncates the stack to [home]
    //    (route_stack.dart:11-13 special case); gotoRoute dispatches
    //    #CURRENT_ROUTE internally. home is always built, so no routeExist gate.
    routeStack.push(home);
    gotoRoute(home);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // --- Reactive reads (register Obx dependencies) ---
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_workforceCode] ?? const [],
      );
      final Map<String, dynamic>? driverDoc = _findDriverDoc(docs);

      final Map<String, dynamic>? vehicleDoc = _findVehicleDoc();
      _publishVehicleId(vehicleDoc);

      // --- Data-bound name (workforce doc field, NOT text slot) ---
      final String nameField = (widget.component['nameField'] ?? 'n')
          .toString();
      final String driverName = (driverDoc?[nameField] ?? '').toString().trim();

      // --- Data-bound plate (stock_location vehicle doc field, NOT text slot) ---
      final String plateField = (widget.component['plateField'] ?? 'ln')
          .toString();
      final String plate = (vehicleDoc?[plateField] ?? '').toString().trim();

      // --- 8-slot label reads (indices 5/6/7) ---
      final String vehicleLabel = _t(5, 'kendaraan ditugaskan');
      final String logoutLabel = _t(6, 'Keluar');
      final String noVehicleLabel = _t(7, 'Belum ditugaskan kendaraan');

      // Determine subtitle
      final String subtitle = plate.isNotEmpty
          ? '$plate · $vehicleLabel'
          : noVehicleLabel;

      // Avatar initials: first letters of the first two name words (e.g.
      // "Agenia Demo" -> "AD"); single word -> first 2 chars; empty -> "?".
      String initials = '?';
      if (driverName.isNotEmpty) {
        final List<String> parts = driverName
            .split(RegExp(r'\s+'))
            .where((String w) => w.isNotEmpty)
            .toList();
        if (parts.length >= 2) {
          initials = (parts[0][0] + parts[1][0]).toUpperCase();
        } else if (parts.isNotEmpty) {
          final String w = parts[0];
          initials = w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
        }
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar (initials) — restored per the original design.
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF4338CA), // indigo-700
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    driverName.isNotEmpty ? driverName : '...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Logout button (outlined pill)
            OutlinedButton.icon(
              onPressed: _onLogoutTap,
              icon: const Icon(Icons.power_settings_new, size: 16),
              label: Text(logoutLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                textStyle: const TextStyle(fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
