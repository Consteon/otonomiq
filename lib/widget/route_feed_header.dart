import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ROUTE_FEED_HEADER — sticky 3-row header for P10 TaskFeed.
///
/// Row 1: back arrow + title "Rute Hari Ini" + driver name / plate subtitle.
/// Row 2: progress label + completed/total stop + failed count + progress bar.
/// Row 3: two flex stat boxes (Drop + Pickup grand totals).
///
/// **PUBLISHER of vehicleId.** Derives vehicleId from stock_location doc
/// (lt=='vehicle' && dv==driverVid → lv) and publishes to
/// DriverHomeState.vehicleId via post-frame callback. Without this, downstream
/// widgets' {vehicleId} searches fail → blank page.
///
/// Subscribes: workforce (driver name), stock_location (vehicle/plate),
/// task (stop counts + item aggregates).
///
/// Read-only: no txfController, no saveSend, no history.
class RouteFeedHeader extends StatefulWidget {
  const RouteFeedHeader({
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
  State<RouteFeedHeader> createState() => _RouteFeedHeaderState();
}

class _RouteFeedHeaderState extends State<RouteFeedHeader> {
  List<String> _textArray = [];
  String _workforceCode = '';
  String _stockLocationCode = '';
  String _taskCode = '';

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

  /// text slot accessors (5 slots):
  ///  [0] "Rute Hari Ini"
  ///  [1] "stop"
  ///  [2] "gagal"
  ///  [3] "Drop"
  ///  [4] "Pickup"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Workforce subscription (driver name).
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

    // Stock_location subscription (vehicleId derivation + plate).
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

    // Task subscription (stops + item aggregates).
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
  }

  /// Find the workforce doc for the current driver.
  /// Mirrors route_progress_header._findDriverDoc (rph:102-113).
  Map<String, dynamic>? _findDriverDoc() {
    if (_workforceCode.isEmpty) return null;
    final String driverVid =
        (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
    if (driverVid.isEmpty) return null;
    final List<Map<String, dynamic>> wfDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_workforceCode] ?? const [],
    );
    for (final doc in wfDocs) {
      final String docVid = (doc['VID'] ?? doc['vid'] ?? '').toString().trim();
      if (docVid == driverVid) return doc;
    }
    return null;
  }

  /// Find the stock_location vehicle doc assigned to the current driver.
  /// Mirrors route_progress_header._findVehicleDoc (rph:124-138).
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
  /// Mirrors route_progress_header._publishVehicleId.
  /// W1: deferred to post-frame — never set an Rx during build.
  ///
  /// Sets `vehicleIdResolved = true` once the stock_location subscription has
  /// delivered data, EVEN when `derivedVehicleId` is empty (unassigned driver).
  /// The "data loaded" signal is `mapTableContent.containsKey(_stockLocationCode)`:
  /// before the first Firestore snapshot, `containsKey` is false, preventing a
  /// premature "unassigned" flash for assigned drivers.
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

  /// Publish driverName from workforce doc into DriverHomeState.
  /// Mirrors custody_step_header._publishDriverName.
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

  /// Get filtered task docs.
  List<Map<String, dynamic>> _getFilteredTasks() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
    );
    final String rawSearch = (widget.component['taskSearch'] ?? '')
        .toString()
        .trim();

    final List<Map<String, dynamic>> filtered = rawSearch.isEmpty
        ? docs
        : filterDriverHomeDocs(docs, rawSearch, widget.scrName);

    // Unconditionally exclude load_rejected tasks. Raw tst compare, NOT
    // stopStatusOf (load_rejected normalizes to pending). stateField read
    // matches the build() read at the stopStatusOf loop.
    final String stateField = (widget.component['stateField'] ?? 'tst')
        .toString();
    return excludeByStatus(
      filtered,
      kDefaultExcludeStatus,
      statusField: stateField,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // --- Reactive reads (register Obx dependencies) ---
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;
      dhState.activeTrip.value; // register activeTrip dependency (GAP B fix)

      // Workforce (driver name)
      mapTableContent[_workforceCode]; // register dependency
      final Map<String, dynamic>? driverDoc = _findDriverDoc();
      _publishDriverName(driverDoc);

      final String nameField = (widget.component['nameField'] ?? 'n')
          .toString();
      final String driverName = (driverDoc?[nameField] ?? '').toString().trim();

      // Stock_location (vehicle + plate)
      final Map<String, dynamic>? vehicleDoc = _findVehicleDoc();
      _publishVehicleId(vehicleDoc);

      final String plateField = (widget.component['plateField'] ?? 'ln')
          .toString();
      final String plate = (vehicleDoc?[plateField] ?? '').toString().trim();

      // Task docs (progress + aggregates)
      final List<Map<String, dynamic>> tasks = _getFilteredTasks();

      // Count by state
      final String stateField = (widget.component['stateField'] ?? 'tst')
          .toString();
      int completedCount = 0;
      int failedCount = 0;
      for (final doc in tasks) {
        final String status = stopStatusOf(doc, tstField: stateField);
        if (status == 'done') {
          completedCount++;
        } else if (status == 'failed') {
          failedCount++;
        }
      }
      final int total = tasks.length;

      // Grand drop/pickup aggregates
      final String itemsField = (widget.component['itemsField'] ?? 'it')
          .toString();
      final String dropField = (widget.component['dropField'] ?? 'pd')
          .toString();
      final String pickupField = (widget.component['pickupField'] ?? 'pp')
          .toString();
      final String actualDropField =
          (widget.component['actualDropField'] ?? 'ad').toString();
      final String actualPickupField =
          (widget.component['actualPickupField'] ?? 'ap').toString();
      final GrandDropPickup gdp = aggregateGrandDropPickup(
        tasks,
        itemsField: itemsField,
        dropField: dropField,
        pickupField: pickupField,
        actualDropField: actualDropField,
        actualPickupField: actualPickupField,
      );

      // Text slots
      final String titleText = _t(0, 'Rute Hari Ini');
      final String stopLabel = _t(1, 'stop');
      final String failedLabel = _t(2, 'gagal');
      final String dropLabel = _t(3, 'Drop');
      final String pickupLabel = _t(4, 'Pickup');

      // Identity subtitle: "{driverName} · {plate}" or just one if other is empty
      final String subtitle = driverName.isNotEmpty && plate.isNotEmpty
          ? '$driverName \u{00B7} $plate'
          : driverName.isNotEmpty
          ? driverName
          : plate.isNotEmpty
          ? plate
          : '';

      // Progress bar fraction
      final double progressFraction = total > 0
          ? (completedCount + failedCount) / total
          : 0;

      // Stop count text: "{completed} / {total} stop"
      final String stopCountText = '$completedCount / $total $stopLabel';
      // Failed suffix: " · {failed} gagal" (amber) when failed > 0
      final String failedSuffix = failedCount > 0
          ? ' \u{00B7} $failedCount $failedLabel'
          : '';

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
            // ── Row 1: Title + Subtitle ─────────────────────────────
            // (back nav handled by main AppBar; no in-body back arrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937), // gray-900
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280), // textMid grey
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ── Row 2: Progress label + bar ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titleText.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Color(0xFF6B7280), // textMid
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stopCountText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Color(0xFF374151), // gray-700
                      ),
                    ),
                    if (failedCount > 0)
                      Text(
                        failedSuffix,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Color(0xFFD97706), // amber-600
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Progress bar (h6, slate100 track, indigo gradient fill)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    // Track
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9), // slate-100
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: progressFraction.clamp(0.0, 1.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF4338CA), // indigo-700
                              Color(0xFF312E81), // indigo-900
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Row 3: Drop + Pickup stat boxes ─────────────────────
            Row(
              children: [
                // Drop box (indigo bg)
                Expanded(
                  child: _buildStatBox(
                    icon: '\u{2193}', // ↓
                    label: dropLabel,
                    actual: gdp.actualDrop,
                    planned: gdp.totalDrop,
                    bgColor: const Color(0xFFEEF2FF), // indigo-50
                    fgColor: const Color(0xFF4338CA), // indigo-700
                  ),
                ),
                const SizedBox(width: 8),
                // Pickup box (violet bg)
                Expanded(
                  child: _buildStatBox(
                    icon: '\u{2191}', // ↑
                    label: pickupLabel,
                    actual: gdp.actualPickup,
                    planned: gdp.totalPickup,
                    bgColor: const Color(0xFFF5F3FF), // violet-50
                    fgColor: const Color(0xFF7C3AED), // violet-600
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatBox({
    required String icon,
    required String label,
    required int actual,
    required int planned,
    required Color bgColor,
    required Color fgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$icon $label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
          const Spacer(),
          Text(
            '$actual / $planned',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
