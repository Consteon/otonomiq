import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'admin_home_support.dart';
import 'admin_vehicle_picker_sheet.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// COORDINATION_SIGNAL_LIST -- "Perlu Tindakan" signal list for Admin H1.
///
/// Derives signals client-side from 5 Firestore collections (task,
/// stock_location, vehicle_check, evidence, asset_cache). Renders clustered
/// cards with admin actions (vehiclePicker assign/reassign) and cross-runtime
/// nav (Gudang).
///
/// The derive uses [deriveAdminSignals] from admin_home_support.dart --
/// the SINGLE source of truth (header reads the same function for counts).
///
/// 0 signals -> SizedBox.shrink() (widget collapse).
///
/// Read-only except vehiclePicker which calls [writeNativeFields].
class CoordinationSignalList extends StatefulWidget {
  const CoordinationSignalList({
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
  State<CoordinationSignalList> createState() => _CoordinationSignalListState();
}

class _CoordinationSignalListState extends State<CoordinationSignalList> {
  List<String> _textArray = [];

  // Subscription codes
  String _taskCode = '';
  String _slCode = '';
  String _vcCode = '';
  String _evCode = '';
  // asset_cache subscribed for future use (genesis-nudge count etc.)
  // but not consumed by signal derive in slice 1
  String _acCode = '';

  int? _dangerAgeMs;
  int? _warnAgeMs;

  // Field config (from component, defaults = current hardcoded values)
  String _statusField = 'tst';
  String _vehicleField = 'vv';
  String _customerNameField = 'kn';
  String _addressField = 'al';
  String _scheduleField = 'tdt';
  String _plateField = 'ln';
  String _driverField = 'dv';
  String _locationTypeField = 'lt';
  String _locationIdField = 'lv';
  String _checkTypeField = 'cty';
  String _checkStatusField = 'cst';
  String _checkVehicleField = 'vv';
  String _evidenceTypeField = 'ept';
  String _evidenceRefField = 'erf';
  String _reasonNoteField = 'd';
  // Gate DSL strings (autheniumDecode'd)
  String _unassignedGate = '';
  String _returnedGate = '';
  String _noExecutorGate = '';
  String _blockedGate = '';
  // updateEventRow DSL template (raw -- executeUpdateEventRow decodes at write-time)
  String _updateEventRowDsl = '';
  // Busy-vehicle guard for vehiclePicker (raw config + resolved pool code)
  String _assignBusySearch = '';
  String _assignBusyLabel = '';
  String _assignBusyTable = '';
  String _busyCode = '';
  // Self-field busy guard (mirrors PICKER_LIST): row's own field non-empty
  String _busySelfField = '';
  String _busySelfLabelField = '';
  // Invoice tier config
  String _invoiceGate = '';
  String _invoiceRoute = '';
  String _invoiceRouteParams = '';

  @override
  void initState() {
    super.initState();
    _parseText();
    _parseThresholds();
    _parseFieldConfig();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _parseThresholds() {
    final dynamic rawDanger = widget.component['dangerAge'];
    final dynamic rawWarn = widget.component['warnAge'];
    if (rawDanger != null) {
      final int mins = int.tryParse(rawDanger.toString().trim()) ?? 0;
      if (mins > 0) _dangerAgeMs = mins * 60 * 1000;
    }
    if (rawWarn != null) {
      final int mins = int.tryParse(rawWarn.toString().trim()) ?? 0;
      if (mins > 0) _warnAgeMs = mins * 60 * 1000;
    }
  }

  void _parseFieldConfig() {
    String cfgStr(String key, String def) {
      final String v = (widget.component[key] ?? '').toString().trim();
      return v.isNotEmpty ? v : def;
    }

    _statusField = cfgStr('statusField', 'tst');
    _vehicleField = cfgStr('vehicleField', 'vv');
    _customerNameField = cfgStr('customerNameField', 'kn');
    _addressField = cfgStr('addressField', 'al');
    _scheduleField = cfgStr('scheduleField', 'tdt');
    _plateField = cfgStr('plateField', 'ln');
    _driverField = cfgStr('driverField', 'dv');
    _locationTypeField = cfgStr('locationTypeField', 'lt');
    _locationIdField = cfgStr('locationIdField', 'lv');
    _checkTypeField = cfgStr('checkTypeField', 'cty');
    _checkStatusField = cfgStr('checkStatusField', 'cst');
    _checkVehicleField = cfgStr('checkVehicleField', 'vv');
    _evidenceTypeField = cfgStr('evidenceTypeField', 'ept');
    _evidenceRefField = cfgStr('evidenceRefField', 'erf');
    _reasonNoteField = cfgStr('reasonNoteField', 'd');

    // Busy-vehicle guard for vehiclePicker (assignBusySearch/Table/Label).
    // Absent -> guard off (all vehicles selectable, unchanged behavior).
    // assignBusyTable normally points at a DIFFERENT table than `table`:
    // "lagi jalan" lives in vehicle_check (cty=opening + cst=custody_confirmed),
    // never in task.tst. _subscribe() subscribes that pool.
    _assignBusyLabel = (widget.component['assignBusyLabel'] ?? '')
        .toString()
        .trim();
    _assignBusySearch = (widget.component['assignBusySearch'] ?? '')
        .toString()
        .trim();
    _assignBusyTable = (widget.component['assignBusyTable'] ?? '')
        .toString()
        .trim();
    // Self-field guard, same key names as PICKER_LIST. Independent of the
    // search guard above -- a vehicle is busy when either fires.
    _busySelfField = (widget.component['busySelfField'] ?? '')
        .toString()
        .trim();
    _busySelfLabelField = (widget.component['busySelfLabelField'] ?? '')
        .toString()
        .trim();

    // Gate DSLs -- autheniumDecode before storing (server sends _25FC_/_2B58_)
    final String rawUG = (widget.component['unassignedGate'] ?? '')
        .toString()
        .trim();
    _unassignedGate = rawUG.isNotEmpty ? (autheniumDecode(rawUG) ?? rawUG) : '';
    final String rawRG = (widget.component['returnedGate'] ?? '')
        .toString()
        .trim();
    _returnedGate = rawRG.isNotEmpty ? (autheniumDecode(rawRG) ?? rawRG) : '';
    final String rawNG = (widget.component['noExecutorGate'] ?? '')
        .toString()
        .trim();
    _noExecutorGate = rawNG.isNotEmpty ? (autheniumDecode(rawNG) ?? rawNG) : '';
    final String rawBG = (widget.component['blockedGate'] ?? '')
        .toString()
        .trim();
    _blockedGate = rawBG.isNotEmpty ? (autheniumDecode(rawBG) ?? rawBG) : '';

    // Invoice tier gate + route
    final String rawIG = (widget.component['invoiceGate'] ?? '')
        .toString()
        .trim();
    _invoiceGate = rawIG.isNotEmpty ? (autheniumDecode(rawIG) ?? rawIG) : '';

    // Misconfig visibility: if ALL 5 gates are empty, signals will never render
    if (_unassignedGate.isEmpty &&
        _returnedGate.isEmpty &&
        _noExecutorGate.isEmpty &&
        _blockedGate.isEmpty &&
        _invoiceGate.isEmpty) {
      devPrint(
        '[coordinationSignalList] all 5 gates empty -- '
        'no signals will render; check component gate config',
      );
    }

    _updateEventRowDsl = (widget.component['updateEventRow'] ?? '')
        .toString()
        .trim();

    _invoiceRoute = (widget.component['invoiceRoute'] ?? '').toString().trim();
    _invoiceRouteParams = (widget.component['invoiceRouteParams'] ?? '')
        .toString()
        .trim();
  }

  /// Text slot accessors:
  ///  [0] section title (default "Perlu Tindakan")
  ///  [1] assign button label (default "Tugaskan")
  ///  [2] reassign button label (default "Assign Ulang")
  ///  [3] no_executor button label (default "Tunjuk di Gudang")
  ///  [4] blocked_departure button label (default "Lihat di Gudang")
  ///  [5] cluster: unassigned_vehicle template (default "{n} order menunggu kendaraan")
  ///  [6] cluster: task_returned template (default "{n} order dikembalikan driver")
  ///  [7] cluster: no_executor template (default "{n} kendaraan tanpa pengantar")
  ///  [8] cluster: blocked_departure template (default "{n} kendaraan menunggu opening")
  ///  [9] vehiclePicker assign title (default "Pilih Kendaraan")
  ///  [10] vehiclePicker reassign title (default "Assign Ulang Kendaraan")
  ///  [11] vehiclePicker confirm label (default "Konfirmasi")
  ///  [12] "task aktif" suffix (default "task aktif")
  ///  [13] offline error (default "Perlu koneksi internet")
  ///  [14] write fail error (default "Gagal menyimpan")
  ///  [15] cluster: invoice_pending template (default "{n} selesai - perlu invoice")
  ///  [16] invoice action button label (default "Cetak Invoice")
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

    // Stock_location
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

    // Vehicle_check
    final String rawVcTable = (widget.component['checkTable'] ?? '')
        .toString()
        .trim();
    if (rawVcTable.isNotEmpty) {
      final TablePath vcp = parseTablePath(rawVcTable);
      if (vcp.tableDocId.isNotEmpty) {
        _vcCode = '$appVid/${vcp.tableDocId}/${vcp.subColl}';
        subscribeToMapCollection(appVid, vcp.tableDocId, vcp.subColl, _vcCode);
      }
    }

    // Evidence
    final String rawEvTable = (widget.component['evidenceTable'] ?? '')
        .toString()
        .trim();
    if (rawEvTable.isNotEmpty) {
      final TablePath evp = parseTablePath(rawEvTable);
      if (evp.tableDocId.isNotEmpty) {
        _evCode = '$appVid/${evp.tableDocId}/${evp.subColl}';
        subscribeToMapCollection(appVid, evp.tableDocId, evp.subColl, _evCode);
      }
    }

    // Busy-guard pool (assignBusyTable) -- usually vehicle_check, i.e. a table
    // none of the blocks above subscribe under this component's own keys.
    // subscribeToMapCollection dedups by code, so an overlap is a no-op.
    _busyCode = VehiclePickerSheet.busyPoolCode(
      assignBusySearch: _assignBusySearch,
      assignBusyTable: _assignBusyTable,
      appVid: appVid,
    );
    if (_busyCode.isNotEmpty) {
      final TablePath bp = parseTablePath(_assignBusyTable);
      subscribeToMapCollection(appVid, bp.tableDocId, bp.subColl, _busyCode);
    }

    // Asset_cache (subscribed but not consumed by signals in slice 1)
    final String rawAcTable = (widget.component['assetTable'] ?? '')
        .toString()
        .trim();
    if (rawAcTable.isNotEmpty) {
      final TablePath acp = parseTablePath(rawAcTable);
      if (acp.tableDocId.isNotEmpty) {
        _acCode = '$appVid/${acp.tableDocId}/${acp.subColl}';
        subscribeToMapCollection(appVid, acp.tableDocId, acp.subColl, _acCode);
      }
    }
  }

  // ── Signal actions ─────────────────────────────────────────────────────

  void _onSignalTap(Signal signal) {
    switch (signal.type) {
      case 'unassigned_vehicle':
        _launchVehiclePicker(mode: 'assign', taskVid: signal.taskVid);
        break;
      case 'task_returned':
        _launchVehiclePicker(mode: 'reassign', taskVid: signal.taskVid);
        break;
      case 'no_executor':
      case 'blocked_departure':
        _navigateCross(signal.vehicleId);
        break;
      case 'invoice_pending':
        _navigateInvoice(signal.taskVid);
        break;
    }
  }

  void _launchVehiclePicker({required String mode, required String taskVid}) {
    final List<Map<String, dynamic>> stockLocations =
        List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);
    final List<Map<String, dynamic>> tasks = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
    );
    // Busy-guard pool: the assignBusyTable docs, or our own tasks when no
    // separate table is configured.
    final List<Map<String, dynamic>> busyDocs = _busyCode.isEmpty
        ? tasks
        : List<Map<String, dynamic>>.from(
            mapTableContent[_busyCode] ?? const [],
          );
    if (_assignBusySearch.isNotEmpty && busyDocs.isEmpty) {
      devPrint(
        '[coordinationSignalList] busy-guard pool empty for '
        '"$_busyCode" -- no vehicle will be blocked',
      );
    }

    // The base DSL from config already has vv and tst in the body.
    // The spec(2) DSL includes tst=assigned:
    // "84214220504259//task...search◼tnm★{taskVid}⭘vv◼{vehicleId}⭘tst◼assigned"
    // So both assign and reassign use the same DSL (it sets vv AND tst=assigned).

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => VehiclePickerSheet(
        mode: mode,
        taskVid: taskVid,
        stockLocations: stockLocations,
        tasks: tasks,
        updateEventRowDsl: _updateEventRowDsl,
        component: widget.component,
        scrName: widget.scrName,
        titleAssign: _t(9, 'Pilih Kendaraan'),
        titleReassign: _t(10, 'Assign Ulang Kendaraan'),
        confirmLabel: _t(11, 'Konfirmasi'),
        activeTaskSuffix: _t(12, 'task aktif'),
        offlineError: _t(13, 'Perlu koneksi internet'),
        writeFailError: _t(14, 'Gagal menyimpan'),
        busySearch: _assignBusySearch,
        busyLabel: _assignBusyLabel,
        busyDocs: busyDocs,
        busySelfField: _busySelfField,
        busySelfLabelField: _busySelfLabelField,
      ),
    );
  }

  void _navigateCross(String vehicleId) {
    final String crossRoute = (widget.component['crossRoute'] ?? '')
        .toString()
        .trim();
    if (crossRoute.isEmpty) return;

    // Build routeParams DSL: "gudangVehicle◼{vehicleId}" with literal vehicleId
    final String rawDsl = (widget.component['crossRouteParams'] ?? '')
        .toString()
        .trim();
    if (rawDsl.isNotEmpty) {
      // Replace {vehicleId} token with the actual value
      final String resolved = rawDsl.replaceAll('{vehicleId}', vehicleId);
      // writeRouteParams handles autheniumDecode + dispatch
      writeRouteParams(resolved, widget.scrName);
    }

    // Dead-route silent-skip
    if (!routeExist(crossRoute)) return;
    routeStack.push(crossRoute);
    gotoRoute(crossRoute);
  }

  void _navigateInvoice(String taskVid) {
    if (_invoiceRoute.isEmpty) return;

    // Resolve routeParams with {tnm} -> taskVid
    if (_invoiceRouteParams.isNotEmpty) {
      final String resolved = _invoiceRouteParams.replaceAll('{tnm}', taskVid);
      writeRouteParams(resolved, widget.scrName);
    }

    // Dead-route silent-skip
    if (!routeExist(_invoiceRoute)) return;
    routeStack.push(_invoiceRoute);
    gotoRoute(_invoiceRoute);
  }

  // ── Cluster header text ────────────────────────────────────────────────

  String _clusterLabel(String type, int count) {
    switch (type) {
      case 'unassigned_vehicle':
        return _t(
          5,
          '{n} order menunggu kendaraan',
        ).replaceAll('{n}', '$count');
      case 'task_returned':
        return _t(
          6,
          '{n} order dikembalikan driver',
        ).replaceAll('{n}', '$count');
      case 'no_executor':
        return _t(
          7,
          '{n} kendaraan tanpa pengantar',
        ).replaceAll('{n}', '$count');
      case 'blocked_departure':
        return _t(
          8,
          '{n} kendaraan menunggu opening',
        ).replaceAll('{n}', '$count');
      case 'invoice_pending':
        return _t(
          15,
          '{n} selesai - perlu invoice',
        ).replaceAll('{n}', '$count');
      default:
        return '$count sinyal';
    }
  }

  String _actionLabel(String type) {
    switch (type) {
      case 'unassigned_vehicle':
        return _t(1, 'Tugaskan');
      case 'task_returned':
        return _t(2, 'Assign Ulang');
      case 'no_executor':
        return _t(3, 'Tunjuk di Gudang');
      case 'blocked_departure':
        return _t(4, 'Lihat di Gudang');
      case 'invoice_pending':
        return _t(16, 'Cetak Invoice');
      default:
        return '';
    }
  }

  IconData _clusterIcon(String type) {
    switch (type) {
      case 'unassigned_vehicle':
        return Icons.local_shipping_outlined;
      case 'task_returned':
        return Icons.assignment_return_outlined;
      case 'no_executor':
        return Icons.person_off_outlined;
      case 'blocked_departure':
        return Icons.block_outlined;
      case 'invoice_pending':
        return Icons.receipt_long_outlined;
      default:
        return Icons.warning_amber_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch all reactive deps
      final List<Map<String, dynamic>> tasks = List<Map<String, dynamic>>.from(
        mapTableContent[_taskCode] ?? const [],
      );
      final List<Map<String, dynamic>> stockLocations =
          List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);
      final List<Map<String, dynamic>> vehicleChecks =
          List<Map<String, dynamic>>.from(mapTableContent[_vcCode] ?? const []);
      final List<Map<String, dynamic>> evidenceDocs =
          List<Map<String, dynamic>>.from(mapTableContent[_evCode] ?? const []);
      // Touch asset_cache to keep subscription alive
      mapTableContent[_acCode];

      final String todayStr = todayEpochMidnightWib();
      final List<Signal> signals = deriveAdminSignals(
        tasks: tasks,
        stockLocations: stockLocations,
        vehicleChecks: vehicleChecks,
        evidenceDocs: evidenceDocs,
        todayStr: todayStr,
        dangerMs: _dangerAgeMs,
        warnMs: _warnAgeMs,
        statusField: _statusField,
        vehicleField: _vehicleField,
        customerNameField: _customerNameField,
        addressField: _addressField,
        scheduleField: _scheduleField,
        plateField: _plateField,
        driverField: _driverField,
        locationTypeField: _locationTypeField,
        locationIdField: _locationIdField,
        checkTypeField: _checkTypeField,
        checkStatusField: _checkStatusField,
        checkVehicleField: _checkVehicleField,
        evidenceTypeField: _evidenceTypeField,
        evidenceRefField: _evidenceRefField,
        reasonNoteField: _reasonNoteField,
        unassignedGate: _unassignedGate,
        returnedGate: _returnedGate,
        noExecutorGate: _noExecutorGate,
        blockedGate: _blockedGate,
        invoiceGate: _invoiceGate,
      );

      // 0 signals -> collapse
      if (signals.isEmpty) return const SizedBox.shrink();

      // Group signals by type for cluster headers
      final List<_Cluster> clusters = _buildClusters(signals);

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
            for (final cluster in clusters) ...[
              // Cluster header
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Row(
                  children: [
                    Text(
                      _clusterLabel(cluster.type, cluster.signals.length),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTierColors.titleText,
                      ),
                    ),
                    // GUDANG badge for cross clusters
                    if (cluster.type == 'no_executor' ||
                        cluster.type == 'blocked_departure') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AdminTierColors.crossBadgeBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'GUDANG',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AdminTierColors.crossBadgeText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Signal cards
              for (final signal in cluster.signals)
                _buildSignalCard(context, signal),
            ],
          ],
        ),
      );
    });
  }

  List<_Cluster> _buildClusters(List<Signal> signals) {
    final Map<String, _Cluster> map = {};
    for (final s in signals) {
      map.putIfAbsent(s.type, () => _Cluster(s.type)).signals.add(s);
    }
    // Preserve the order from deriveAdminSignals (already sorted by maxAge)
    final List<_Cluster> result = [];
    final Set<String> seen = {};
    for (final s in signals) {
      if (seen.add(s.type)) {
        result.add(map[s.type]!);
      }
    }
    return result;
  }

  Widget _buildSignalCard(BuildContext context, Signal signal) {
    final bool isCross =
        signal.type == 'no_executor' || signal.type == 'blocked_departure';
    final bool isSoft = signal.type == 'blocked_departure';
    final bool isDanger = signal.tier == 'danger' || (isCross && !isSoft);
    // Invoice tier reads "done, just bill" -- green accent, not the blue
    // used by the other to-do tiers.
    final bool isInvoice = signal.type == 'invoice_pending';

    // Card colors via centralized palette
    final (Color cardBg, Color cardBorderColor, double borderWidth) =
        AdminTierColors.signalCard(isDanger);

    // Button colors via centralized palette
    final (
      Color buttonBg,
      Color buttonFg,
      bool isOutline,
    ) = AdminTierColors.signalButton(
      isSoft: isSoft,
      isDanger: isDanger,
      isCross: isCross,
      isOk: isInvoice,
    );

    // Age pill colors via centralized palette
    final (Color agePillBg, Color agePillFg) = AdminTierColors.signalAgePill(
      signal.tier,
      green: isInvoice,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorderColor, width: borderWidth),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: icon tile + head + age pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 40x40 icon tile
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isInvoice
                        ? AdminTierColors.okBadgeBg
                        : AdminTierColors.iconTileBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _clusterIcon(signal.type),
                    size: 20,
                    color: isInvoice
                        ? AdminTierColors.okActionGreen
                        : AdminTierColors.okAction,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    signal.head,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AdminTierColors.titleText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: agePillBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    formatAge(signal.ageMs),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: agePillFg,
                    ),
                  ),
                ),
              ],
            ),

            // Summary (indented past icon tile)
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 50), // 40 tile + 10 gap
              child: Text(
                signal.summary,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AdminTierColors.subText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Address (if present)
            if (signal.address.isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 12,
                      color: AdminTierColors.mutedText,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        signal.address,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AdminTierColors.mutedText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action button (full-width, min-height 44)
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: isOutline
                  ? OutlinedButton.icon(
                      onPressed: () => _onSignalTap(signal),
                      icon: isCross
                          ? const Icon(Icons.open_in_new, size: 14)
                          : const SizedBox.shrink(),
                      label: Text(
                        _actionLabel(signal.type),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: buttonFg,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: buttonFg),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _onSignalTap(signal),
                      icon: isCross
                          ? const Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: Colors.white,
                            )
                          : isInvoice
                          ? const Icon(
                              Icons.receipt_long_outlined,
                              size: 16,
                              color: Colors.white,
                            )
                          : const SizedBox.shrink(),
                      label: Text(
                        _actionLabel(signal.type),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: buttonFg,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cluster helper ──────────────────────────────────────────────────────────

class _Cluster {
  final String type;
  final List<Signal> signals = [];
  _Cluster(this.type);
}
