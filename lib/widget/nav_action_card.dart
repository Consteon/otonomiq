import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// NAV_ACTION_CARD — "Return Kendaraan" CTA (DriverHome P4).
///
/// HIDDEN when pending (!confirmed). Confirmed: shown; fully active (enabled
/// CTA) only when all stops are closed (done | failed). Otherwise muted.
class NavActionCard extends StatefulWidget {
  const NavActionCard({
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
  State<NavActionCard> createState() => _NavActionCardState();
}

class _NavActionCardState extends State<NavActionCard> {
  List<String> _textArray = [];
  String _dataCode = ''; // task subscription code
  String _gateCode = ''; // vehicle_check gate subscription code

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

  /// text slot accessors (3 slots per spec §3.6):
  ///  [0] "Return Kendaraan"
  ///  [1] "Balik & serahkan kendaraan + sisa muatan ke gudang"
  ///  [2] "Semua kelar — balik & serahkan ke gudang"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Primary data table (task)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _dataCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _dataCode);
    }

    // Gate table (vehicle_check) — for self-gating visibility
    final String rawGateTable = (widget.component['gateTable'] ?? '')
        .toString()
        .trim();
    if (rawGateTable.isNotEmpty) {
      final TablePath gtp = parseTablePath(rawGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        _gateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
        subscribeToMapCollection(
          appVid,
          gtp.tableDocId,
          gtp.subColl,
          _gateCode,
        );
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredStops() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_dataCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final String rawExclude = (widget.component['excludeStatus'] ?? '')
        .toString()
        .trim();
    final String excludeStatus = rawExclude.isEmpty
        ? kDefaultExcludeStatus
        : rawExclude;

    List<Map<String, dynamic>> filtered = rawSearch.isEmpty
        ? docs
        : filterDriverHomeDocs(docs, rawSearch, widget.scrName);

    return excludeByStatus(filtered, excludeStatus);
  }

  void _onCtaTap() {
    final String route = (widget.component['route'] ?? '').toString().trim();
    if (route.isEmpty) return;
    if (routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Layar belum tersedia'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      // Touch confirmed + vehicleId to register Obx dependency (search uses
      // vehicleId; confirmed kept reactive even though gating is self-driven).
      dhState.confirmed.value;
      dhState.vehicleId.value;
      dhState.activeTrip.value; // register activeTrip dependency (GAP B fix)

      // ── Vehicle scope gate (scope-leak prevention) ──────────────────
      // When the driver has no assigned vehicle, hide the card entirely.
      if (dhState.vehicleIdResolved.value && dhState.vehicleId.value.isEmpty) {
        return const SizedBox.shrink();
      }

      // Fix 2: self-gate on own gateTable/gateSearch, not DriverHomeState.confirmed
      final String rawGateSearch = (widget.component['gateSearch'] ?? '')
          .toString()
          .trim();
      final bool gateConfirmed = evaluateGateSearch(
        _gateCode,
        rawGateSearch,
        widget.scrName,
      );

      // HIDDEN when gate not confirmed
      if (!gateConfirmed) return const SizedBox.shrink();

      final List<Map<String, dynamic>> stops = _getFilteredStops();
      final StopProgress progress = computeStopProgress(stops);
      final bool allClosed = progress.allClosed;

      // HIDDEN when not all stops are closed
      if (!allClosed) return const SizedBox.shrink();

      final String title = _t(0, 'Return Kendaraan');
      final String body = _t(2, 'Semua kelar — balik & serahkan ke gudang');

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF16A34A)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 20,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Body text
              Text(
                body,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF166534), // green-800
                  height: 1.4,
                ),
              ),
              // CTA button (always enabled -- card only renders when allClosed)
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onCtaTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text('$title →'), // right arrow
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
