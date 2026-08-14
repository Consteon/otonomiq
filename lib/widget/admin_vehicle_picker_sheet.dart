import 'package:flutter/material.dart';

import '../global.dart';
import 'admin_home_support.dart'; // executeUpdateEventRow
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'picker_list.dart'; // PickerList.countForRow (static reuse, no coupling)

/// Reusable bottom-sheet for assigning/reassigning a vehicle to a task.
///
/// Lists stock_location vehicles (lt=='vehicle'), shows plate + N task aktif.
/// Tap + confirm -> [executeUpdateEventRow] merge via the `updateEventRow` DSL
/// template (offline-aware: the SDK cache serves the query and queues the
/// write; bypasses the history queue).
///
/// NOT a dispatch branch -- launched imperatively via showModalBottomSheet.
/// Shared between CoordinationSignalList (signal actions) and
/// AdminUpcomingTaskList (inline "+ Tugaskan Kendaraan").
class VehiclePickerSheet extends StatefulWidget {
  const VehiclePickerSheet({
    super.key,
    required this.mode,
    required this.taskVid,
    required this.stockLocations,
    required this.tasks,
    required this.updateEventRowDsl,
    required this.component,
    required this.scrName,
    this.titleAssign = 'Pilih Kendaraan',
    this.titleReassign = 'Assign Ulang Kendaraan',
    this.confirmLabel = 'Konfirmasi',
    this.activeTaskSuffix = 'task aktif',
    this.offlineError = 'Perlu koneksi internet',
    this.writeFailError = 'Gagal menyimpan',
    this.busySearch = '',
    this.busyLabel = '',
    this.busyDocs = const <Map<String, dynamic>>[],
    this.busySelfField = '',
    this.busySelfLabelField = '',
  });

  final String mode; // 'assign' or 'reassign'
  final String taskVid;
  final List<Map<String, dynamic>> stockLocations;
  final List<Map<String, dynamic>> tasks;
  final String updateEventRowDsl;
  final dynamic component; // kept for resolveAppVid
  final String scrName; // for {today}/{now}/session token resolution
  final String titleAssign;
  final String titleReassign;
  final String confirmLabel;
  final String activeTaskSuffix;
  final String offlineError;
  final String writeFailError;

  /// Gate-DSL query for busy-vehicle check. Token `{lv}` is resolved per row.
  /// Empty = guard off (all vehicles selectable). Evaluated against [busyDocs].
  final String busySearch;

  /// Badge text shown on busy rows (e.g. "Lagi Jalan"). Empty = disabled but
  /// no visible badge text.
  final String busyLabel;

  /// Docs [busySearch] runs against -- the `assignBusyTable` pool when that
  /// table is configured, otherwise the caller's own table docs.
  ///
  /// Deliberately separate from [tasks]: "lagi jalan" is NOT a task status.
  /// The app derives it from vehicle_check (`cty=opening` + `cst=custody_confirmed`,
  /// see deriveVehicleTier in vehicle_feed_support.dart) while task.tst stays
  /// `assigned` -- and `assigned` must stay selectable (a loaded-but-not-departed
  /// vehicle can take a joined trip).
  final List<Map<String, dynamic>> busyDocs;

  /// Field on the vehicle row itself that signals busy when non-empty
  /// (e.g. `dv` -- a driver is holding the vehicle). Empty = self-guard off.
  ///
  /// Mirrors `PickerList`'s `busySelfField` (picker_list.dart:384-406). Wider
  /// than [busySearch]: `dv` stays set from warehouse designation through the
  /// closing check, so it also blocks a vehicle still loading. Independent of
  /// [busySearch] -- a row is busy when EITHER fires.
  final String busySelfField;

  /// Field supplying the badge text for a [busySelfField] hit (e.g. `dn`, the
  /// driver name). Empty = row still disabled, no name shown.
  final String busySelfLabelField;

  /// mapTableContent key for the [busyDocs] pool, or `''` when the caller
  /// should use its own table's docs.
  ///
  /// Empty when the guard is off ([assignBusySearch] blank) or no separate
  /// table is configured. The key is vid-scoped like every other subscription
  /// here -- two tenants can share one tableDocId.
  static String busyPoolCode({
    required String assignBusySearch,
    required String assignBusyTable,
    required String appVid,
  }) {
    if (assignBusySearch.trim().isEmpty) return '';
    final String bt = assignBusyTable.trim();
    if (bt.isEmpty) return '';
    final TablePath tp = parseTablePath(bt);
    if (tp.tableDocId.isEmpty) return '';
    return '$appVid/${tp.tableDocId}/${tp.subColl}';
  }

  /// Whether vehicle [lv] is busy per [busySearch] against [docs].
  ///
  /// Delegates to [PickerList.countForRow] which handles autheniumDecode,
  /// token substitution (`{lv}` -> [lv]), and evaluateGate.
  /// Empty [busySearch] -> always false (guard off).
  static bool isVehicleBusy(
    List<Map<String, dynamic>> docs,
    String busySearch,
    String lv,
  ) {
    if (busySearch.trim().isEmpty) return false;
    return PickerList.countForRow(docs, busySearch, 'lv', lv) > 0;
  }

  /// Whether the vehicle row itself signals busy: [busySelfField] non-empty
  /// on [veh]. Empty field name -> always false (self-guard off).
  ///
  /// Same rule as PickerList: the row stays visible, it just cannot be tapped.
  static bool isVehicleSelfBusy(
    Map<String, dynamic> veh,
    String busySelfField,
  ) {
    final String f = busySelfField.trim();
    if (f.isEmpty) return false;
    return (veh[f] ?? '').toString().trim().isNotEmpty;
  }

  /// Badge text for a busy row: [busyLabel], then the [busySelfLabelField]
  /// value when the self-guard fired, joined with " · ".
  ///
  /// Either part may be absent -- an empty result means "disabled, no text".
  static String busyBadgeText({
    required String busyLabel,
    required String selfLabel,
  }) {
    return <String>[
      if (busyLabel.trim().isNotEmpty) busyLabel.trim(),
      if (selfLabel.trim().isNotEmpty) selfLabel.trim(),
    ].join(' \u{00B7} ');
  }

  @override
  State<VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<VehiclePickerSheet> {
  String? _selectedLv;
  bool _writing = false;

  /// Get vehicles (stock_location where lt=='vehicle').
  List<Map<String, dynamic>> get _vehicles {
    return widget.stockLocations
        .where((sl) => (sl['lt'] ?? '').toString().trim() == 'vehicle')
        .toList();
  }

  /// Count active tasks for a vehicle (tst in {assigned, on_delivery}).
  int _activeTaskCount(String lv) {
    int count = 0;
    for (final t in widget.tasks) {
      final String vv = (t['vv'] ?? '').toString().trim();
      final String tst = (t['tst'] ?? '').toString().trim();
      if (vv == lv && (tst == 'assigned' || tst == 'on_delivery')) {
        count++;
      }
    }
    return count;
  }

  Future<void> _onConfirm() async {
    if (_selectedLv == null || _selectedLv!.isEmpty || _writing) return;

    setState(() => _writing = true);

    final bool success = await executeUpdateEventRow(
      rawDsl: widget.updateEventRowDsl,
      tokens: {'{taskVid}': widget.taskVid, '{vehicleId}': _selectedLv!},
      component: widget.component,
      scrName: widget.scrName,
    );

    if (!mounted) return;

    setState(() => _writing = false);

    if (success) {
      final bool offline = !internetConnectionFlag.value;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offline
                ? 'Tersimpan offline — dikirim otomatis saat online'
                : 'Berhasil',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      final bool offline = !internetConnectionFlag.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(offline ? widget.offlineError : widget.writeFailError),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.mode == 'reassign'
        ? widget.titleReassign
        : widget.titleAssign;
    final List<Map<String, dynamic>> vehicles = _vehicles;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            const Divider(height: 1),
            // Vehicle list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: vehicles.length,
                itemBuilder: (context, index) {
                  final Map<String, dynamic> veh = vehicles[index];
                  final String lv = (veh['lv'] ?? '').toString().trim();
                  final String ln = (veh['ln'] ?? '').toString().trim();
                  final int activeCount = _activeTaskCount(lv);
                  final bool selected = _selectedLv == lv;
                  final bool selfBusy = VehiclePickerSheet.isVehicleSelfBusy(
                    veh,
                    widget.busySelfField,
                  );
                  final bool isBusy =
                      selfBusy ||
                      VehiclePickerSheet.isVehicleBusy(
                        widget.busyDocs,
                        widget.busySearch,
                        lv,
                      );
                  final String busyBadge = !isBusy
                      ? ''
                      : VehiclePickerSheet.busyBadgeText(
                          busyLabel: widget.busyLabel,
                          selfLabel:
                              selfBusy &&
                                  widget.busySelfLabelField.trim().isNotEmpty
                              ? (veh[widget.busySelfLabelField.trim()] ?? '')
                                    .toString()
                                    .trim()
                              : '',
                        );
                  // I4: one subtitle base style, shared by both branches below.
                  final TextStyle subtitleBase = TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  );

                  return Opacity(
                    opacity: isBusy ? 0.45 : 1.0,
                    child: ListTile(
                      leading: Icon(
                        Icons.local_shipping_outlined,
                        color: selected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade400,
                      ),
                      title: Text(
                        ln.isNotEmpty ? ln : lv,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      subtitle: isBusy && busyBadge.isNotEmpty
                          ? Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        '$activeCount ${widget.activeTaskSuffix}',
                                    style: subtitleBase,
                                  ),
                                  TextSpan(
                                    text: ' \u{00B7} $busyBadge',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFEF4444), // red-500
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Text(
                              '$activeCount ${widget.activeTaskSuffix}',
                              style: subtitleBase,
                            ),
                      trailing: selected
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).primaryColor,
                            )
                          : null,
                      selected: selected,
                      onTap: isBusy
                          ? null
                          : () => setState(() => _selectedLv = lv),
                    ),
                  );
                },
              ),
            ),
            // Confirm button
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: (_selectedLv != null && !_writing)
                      ? _onConfirm
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _writing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.confirmLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
