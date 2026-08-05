import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'admin_home_support.dart';
import 'admin_vehicle_picker_sheet.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ADMIN_UPCOMING_TASK_LIST -- "AKAN DATANG" stat-list for Admin H1.
///
/// Shows today's scheduled tasks (tst=assigned, tdt={today}, excluding
/// load_rejected). Each card: customer + time pill + item roll-up + vehicle
/// plate or inline "+ Tugaskan Kendaraan" button.
///
/// Read-only except the inline "+ Tugaskan Kendaraan" which launches the
/// shared VehiclePickerSheet.
///
/// Empty -> renders section header + config-driven emptyText (spec section 5.2).
class AdminUpcomingTaskList extends StatefulWidget {
  const AdminUpcomingTaskList({
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
  State<AdminUpcomingTaskList> createState() => _AdminUpcomingTaskListState();
}

class _AdminUpcomingTaskListState extends State<AdminUpcomingTaskList> {
  List<String> _textArray = [];
  String _taskCode = '';
  String _slCode = '';

  // Field config (from component, defaults = current hardcoded values)
  String _titleField = 'kn';
  String _schedField = 'tdt';
  String _summaryField = 'it';
  String _assignField = 'vv';
  String _plateField = 'vv';
  String _vehicleNameField = 'ln';
  // updateEventRow DSL template (raw -- executeUpdateEventRow decodes at write-time)
  String _updateEventRowDsl = '';
  // Config-driven empty-state text (spec section 5.2: never hide section silently)
  String _emptyText = 'Tidak ada order terjadwal hari ini';

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
    String cfgStr(String key, String def) {
      final String v = (widget.component[key] ?? '').toString().trim();
      return v.isNotEmpty ? v : def;
    }

    _titleField = cfgStr('titleField', 'kn');
    _schedField = cfgStr('schedField', 'tdt');
    _summaryField = cfgStr('summaryField', 'it');
    _assignField = cfgStr('assignField', 'vv');
    _plateField = cfgStr('plateField', 'vv');
    _vehicleNameField = cfgStr('vehicleNameField', 'ln');
    _updateEventRowDsl = (widget.component['updateEventRow'] ?? '')
        .toString()
        .trim();
    _emptyText = cfgStr('emptyText', 'Tidak ada order terjadwal hari ini');
  }

  /// Text slot accessors:
  ///  [0] section header (default "AKAN DATANG")
  ///  [1] drop label (default "Drop")
  ///  [2] pickup label (default "Pickup")
  ///  [3] assign button label (default "+ Tugaskan Kendaraan")
  ///  [4] vehiclePicker title (default "Pilih Kendaraan")
  ///  [5] vehiclePicker confirm (default "Konfirmasi")
  ///  [6] task aktif suffix (default "task aktif")
  ///  [7] offline error (default "Perlu koneksi internet")
  ///  [8] write fail error (default "Gagal menyimpan")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Task
    final String rawTaskTable = (widget.component['table'] ?? '')
        .toString()
        .trim();
    if (rawTaskTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTaskTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }

    // Stock_location (vehicle plate lookup)
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
  }

  void _onAssignTap(String taskVid) {
    final List<Map<String, dynamic>> stockLocations =
        List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);
    final List<Map<String, dynamic>> tasks = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
    );

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => VehiclePickerSheet(
        mode: 'assign',
        taskVid: taskVid,
        stockLocations: stockLocations,
        tasks: tasks,
        updateEventRowDsl: _updateEventRowDsl,
        component: widget.component,
        scrName: widget.scrName,
        titleAssign: _t(4, 'Pilih Kendaraan'),
        confirmLabel: _t(5, 'Konfirmasi'),
        activeTaskSuffix: _t(6, 'task aktif'),
        offlineError: _t(7, 'Perlu koneksi internet'),
        writeFailError: _t(8, 'Gagal menyimpan'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> allTasks =
          List<Map<String, dynamic>>.from(
            mapTableContent[_taskCode] ?? const [],
          );
      final List<Map<String, dynamic>> stockLocations =
          List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);

      final String todayStr = todayEpochMidnightWib();

      // Index: vehicles by lv
      final Map<String, Map<String, dynamic>> vehiclesByLv = {};
      for (final sl in stockLocations) {
        if ((sl['lt'] ?? '').toString().trim() == 'vehicle') {
          final String lv = (sl['lv'] ?? '').toString().trim();
          if (lv.isNotEmpty) vehiclesByLv[lv] = sl;
        }
      }

      // Filter: tst=assigned, tdt=today, exclude load_rejected
      final List<Map<String, dynamic>> upcoming = [];
      for (final t in allTasks) {
        final String tst = (t['tst'] ?? '').toString().trim();
        if (tst != 'assigned') continue;
        final String tdt = (t[_schedField] ?? '').toString().trim();
        if (tdt != todayStr) continue;
        upcoming.add(t);
      }

      // Section header (always visible -- spec section 5.2: never hide section)
      final String sectionHeader = _t(0, 'AKAN DATANG');

      if (upcoming.isEmpty) {
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
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  _emptyText,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AdminTierColors.subText,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // Labels (only needed when cards exist)
      final String dropLabel = _t(1, 'Drop');
      final String pickupLabel = _t(2, 'Pickup');
      final String assignLabel = _t(3, '+ Tugaskan Kendaraan');

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
            for (final task in upcoming) ...[
              _buildCard(
                context,
                task: task,
                vehiclesByLv: vehiclesByLv,
                dropLabel: dropLabel,
                pickupLabel: pickupLabel,
                assignLabel: assignLabel,
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
    required Map<String, dynamic> task,
    required Map<String, Map<String, dynamic>> vehiclesByLv,
    required String dropLabel,
    required String pickupLabel,
    required String assignLabel,
  }) {
    final String kn = (task[_titleField] ?? '').toString().trim();
    final String tnm = (task['tnm'] ?? '').toString().trim();
    final String vv = (task[_assignField] ?? '').toString().trim();
    final dynamic rawTdt = task[_schedField];
    final String timePill = formatTimePill(rawTdt);

    // Item roll-up
    final String itemSummary = summarizeItems(
      task[_summaryField],
      dropLabel: dropLabel,
      pickupLabel: pickupLabel,
    );

    // Vehicle plate
    final String plateVv = (task[_plateField] ?? '').toString().trim();
    final String plate = (vehiclesByLv[plateVv]?[_vehicleNameField] ?? '')
        .toString()
        .trim();

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
          // Top row: customer name + time pill
          Row(
            children: [
              Expanded(
                child: Text(
                  kn.isNotEmpty ? kn : tnm,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminTierColors.titleText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timePill.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AdminTierColors.neutralPillBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timePill,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminTierColors.neutralPillText,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Item summary
          if (itemSummary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              itemSummary,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AdminTierColors.subText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Footer: vehicle plate or assign button
          const SizedBox(height: 8),
          if (vv.isNotEmpty && plate.isNotEmpty) ...[
            // Has vehicle: show truck icon + plate
            Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Text(
                  plate,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AdminTierColors.subText,
                  ),
                ),
              ],
            ),
          ] else ...[
            // No vehicle: inline assign button
            GestureDetector(
              onTap: () => _onAssignTap(tnm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  border: Border.all(color: AdminTierColors.okAction),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add,
                      size: 16,
                      color: AdminTierColors.okAction,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      assignLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTierColors.okAction,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
