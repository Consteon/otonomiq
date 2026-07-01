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
      _dataCode = '${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _dataCode);
    }

    // Gate table (vehicle_check) — for self-gating visibility
    final String rawGateTable = (widget.component['gateTable'] ?? '')
        .toString()
        .trim();
    if (rawGateTable.isNotEmpty) {
      final TablePath gtp = parseTablePath(rawGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        _gateCode = '${gtp.tableDocId}/${gtp.subColl}';
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
    if (rawSearch.isEmpty) return docs;
    return filterDriverHomeDocs(docs, rawSearch, widget.scrName);
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

      final String title = _t(0, 'Return Kendaraan');
      final String bodyDefault = _t(
        1,
        'Balik & serahkan kendaraan + sisa muatan ke gudang',
      );
      final String bodyReady = _t(
        2,
        'Semua kelar — balik & serahkan ke gudang',
      );

      final String body = allClosed ? bodyReady : bodyDefault;
      final Color accentColor = allClosed
          ? const Color(0xFF16A34A)
          : const Color(0xFF9CA3AF);
      final Color bgColor = allClosed ? const Color(0xFFF0FDF4) : Colors.white;
      final Color borderColor = allClosed
          ? const Color(0xFF16A34A)
          : const Color(0xFFE5E7EB);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    allClosed
                        ? Icons.check_circle
                        : Icons.directions_car_outlined,
                    size: 20,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: allClosed
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Body text
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  color: allClosed
                      ? const Color(0xFF166534) // green-800
                      : const Color(0xFF9CA3AF), // gray-400
                  height: 1.4,
                ),
              ),
              // CTA button (enabled only when allClosed)
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: allClosed ? _onCtaTap : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allClosed
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFE5E7EB),
                    foregroundColor: allClosed
                        ? Colors.white
                        : const Color(0xFF9CA3AF),
                    disabledBackgroundColor: const Color(0xFFF3F4F6),
                    disabledForegroundColor: const Color(0xFFD1D5DB),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text('$title →'), // →
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
