import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'admin_home_support.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ADMIN_ACTIVE_TRIP_LIST -- "BERJALAN" stat-list for Admin H1.
///
/// Shows vehicles currently on confirmed trips today. Each card:
/// plate title + "{driver} . Stop {x} dari {y}" + "{lastStop} selesai"
/// + BERJALAN badge.
///
/// Read-only, no write. Empty -> SizedBox.shrink().
///
/// Subscribes to: vehicle_check, task, stock_location, workforce.
class AdminActiveTripList extends StatefulWidget {
  const AdminActiveTripList({
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
  State<AdminActiveTripList> createState() => _AdminActiveTripListState();
}

class _AdminActiveTripListState extends State<AdminActiveTripList> {
  List<String> _textArray = [];
  String _vcCode = '';
  String _taskCode = '';
  String _slCode = '';
  String _wfCode = '';
  String _vehicleNameField = 'ln';
  String _execField = 'dv';
  String _nameField = 'n';
  String _itemsField = 'it';
  String _doneMarker = 'ad,ap';

  @override
  void initState() {
    super.initState();
    _parseText();
    _parseConfig();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _parseConfig() {
    final String vnf = (widget.component['vehicleNameField'] ?? '')
        .toString()
        .trim();
    if (vnf.isNotEmpty) _vehicleNameField = vnf;
    final String ef = (widget.component['execField'] ?? '').toString().trim();
    if (ef.isNotEmpty) _execField = ef;
    final String nf = (widget.component['nameField'] ?? '').toString().trim();
    if (nf.isNotEmpty) _nameField = nf;
    final String iff = (widget.component['itemsField'] ?? '').toString().trim();
    if (iff.isNotEmpty) _itemsField = iff;
    final String dmf = (widget.component['doneMarker'] ?? '').toString().trim();
    if (dmf.isNotEmpty) _doneMarker = dmf;
  }

  /// Text slot accessors:
  ///  [0] section header (default "BERJALAN")
  ///  [1] badge label (default "BERJALAN")
  ///  [2] stop prefix (default "Stop")
  ///  [3] stop separator (default "dari")
  ///  [4] last stop suffix (default "selesai")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Vehicle_check
    final String rawVcTable = (widget.component['checkTable'] ?? '')
        .toString()
        .trim();
    if (rawVcTable.isNotEmpty) {
      final TablePath vcp = parseTablePath(rawVcTable);
      if (vcp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _vcCode = '$appVid/${vcp.tableDocId}/${vcp.subColl}';
        subscribeToMapCollection(appVid, vcp.tableDocId, vcp.subColl, _vcCode);
      }
    }

    // Task
    final String rawTaskTable = (widget.component['taskTable'] ?? '')
        .toString()
        .trim();
    if (rawTaskTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTaskTable);
      if (tp.tableDocId.isNotEmpty) {
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }

    // Stock_location (plate lookup)
    final String rawSlTable = (widget.component['vehicleTable'] ?? '')
        .toString()
        .trim();
    if (rawSlTable.isNotEmpty) {
      final TablePath slp = parseTablePath(rawSlTable);
      if (slp.tableDocId.isNotEmpty) {
        _slCode = '$appVid/${slp.tableDocId}/${slp.subColl}';
        subscribeToMapCollection(appVid, slp.tableDocId, slp.subColl, _slCode);
      }
    }

    // Workforce (driver name lookup)
    final String rawWfTable = (widget.component['workforceTable'] ?? '')
        .toString()
        .trim();
    if (rawWfTable.isNotEmpty) {
      final TablePath wtp = parseTablePath(rawWfTable);
      if (wtp.tableDocId.isNotEmpty) {
        _wfCode = '$appVid/${wtp.tableDocId}/${wtp.subColl}';
        subscribeToMapCollection(appVid, wtp.tableDocId, wtp.subColl, _wfCode);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> vehicleChecks =
          List<Map<String, dynamic>>.from(mapTableContent[_vcCode] ?? const []);
      final List<Map<String, dynamic>> tasks = List<Map<String, dynamic>>.from(
        mapTableContent[_taskCode] ?? const [],
      );
      final List<Map<String, dynamic>> stockLocations =
          List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);
      final List<Map<String, dynamic>> workforceDocs =
          List<Map<String, dynamic>>.from(mapTableContent[_wfCode] ?? const []);

      final String todayStr = todayEpochMidnightWib();

      // Index: stock_location vehicles by lv
      final Map<String, Map<String, dynamic>> vehiclesByLv = {};
      for (final sl in stockLocations) {
        if ((sl['lt'] ?? '').toString().trim() == 'vehicle') {
          final String lv = (sl['lv'] ?? '').toString().trim();
          if (lv.isNotEmpty) vehiclesByLv[lv] = sl;
        }
      }

      // Index: workforce by vid for driver name.
      // JOIN-KEY ASSUMPTION (best-guess, degrade-safe): the driver name is the
      // workforce doc whose id (`vid`, fallback `lv`) equals the vehicle's `dv`
      // field. If this tenant keys workforce differently from stock_location.dv,
      // the lookup misses and driverName resolves to '' -> the subline degrades
      // to stop-progress only (no crash). Not a guaranteed join.
      final Map<String, String> workforceNames = {};
      for (final wf in workforceDocs) {
        final String vid = (wf['vid'] ?? wf['lv'] ?? '').toString().trim();
        if (vid.isNotEmpty) {
          workforceNames[vid] = (wf[_nameField] ?? '').toString().trim();
        }
      }

      // Filter active vehicle_checks: cst=custody_confirmed, cdt=today
      final List<Map<String, dynamic>> activeChecks = [];
      for (final vc in vehicleChecks) {
        final String cst = (vc['cst'] ?? '').toString().trim();
        final String cdt = (vc['cdt'] ?? '').toString().trim();
        if (cst == 'custody_confirmed' && cdt == todayStr) {
          activeChecks.add(vc);
        }
      }

      // Empty -> collapse
      if (activeChecks.isEmpty) return const SizedBox.shrink();

      // Labels
      final String sectionHeader = _t(0, 'BERJALAN');
      final String badgeLabel = _t(1, 'BERJALAN');
      final String stopPrefix = _t(2, 'Stop');
      final String stopSep = _t(3, 'dari');
      final String lastStopSuffix = _t(4, 'selesai');

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
            // Section header
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                sectionHeader.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AdminTierColors.sectionCaps,
                ),
              ),
            ),
            // Cards
            for (final vc in activeChecks) ...[
              _buildCard(
                context,
                vc: vc,
                tasks: tasks,
                vehiclesByLv: vehiclesByLv,
                workforceNames: workforceNames,
                badgeLabel: badgeLabel,
                stopPrefix: stopPrefix,
                stopSep: stopSep,
                lastStopSuffix: lastStopSuffix,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildCard(
    BuildContext context, {
    required Map<String, dynamic> vc,
    required List<Map<String, dynamic>> tasks,
    required Map<String, Map<String, dynamic>> vehiclesByLv,
    required Map<String, String> workforceNames,
    required String badgeLabel,
    required String stopPrefix,
    required String stopSep,
    required String lastStopSuffix,
  }) {
    final String vv = (vc['vv'] ?? '').toString().trim();

    // Plate from stock_location
    final Map<String, dynamic>? veh = vehiclesByLv[vv];
    final String plate = (veh?[_vehicleNameField] ?? '').toString().trim();

    // Driver name from workforce (vehicle's dv field; see JOIN-KEY ASSUMPTION
    // note in build()).
    final String dv = (veh?[_execField] ?? '').toString().trim();
    final String driverName = workforceNames[dv] ?? '';

    // Stop progress: aggregate it[] across all tasks for this vehicle
    int totalDone = 0;
    int totalItems = 0;
    for (final t in tasks) {
      final String taskVv = (t['vv'] ?? '').toString().trim();
      if (taskVv != vv) continue;
      final String taskTst = (t['tst'] ?? '').toString().trim();
      if (taskTst == 'load_rejected') continue;
      final (int done, int total) = progressFromItems(
        t,
        doneMarker: _doneMarker,
        itemsField: _itemsField,
      );
      totalDone += done;
      totalItems += total;
    }

    // Last completed stop
    final String lastStop = lastCompletedStopName(tasks, vv);

    // Subline: "{driver} . Stop {x} dari {y}"
    final List<String> subParts = [];
    if (driverName.isNotEmpty) subParts.add(driverName);
    if (totalItems > 0) {
      subParts.add('$stopPrefix $totalDone $stopSep $totalItems');
    }
    final String subline = subParts.join(' \u{00B7} ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTierColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: plate + BERJALAN badge
          Row(
            children: [
              Expanded(
                child: Text(
                  plate.isNotEmpty ? plate : vv,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AdminTierColors.titleText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AdminTierColors.okBadgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AdminTierColors.okBadgeText,
                  ),
                ),
              ),
            ],
          ),

          // Subline: driver + stop progress
          if (subline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subline,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AdminTierColors.subText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Last stop
          if (lastStop.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '$lastStop $lastStopSuffix',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AdminTierColors.mutedText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
