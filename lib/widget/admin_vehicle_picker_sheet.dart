import 'package:flutter/material.dart';

import '../global.dart';
import 'admin_home_support.dart'; // executeUpdateEventRow

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

                  return ListTile(
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
                    subtitle: Text(
                      '$activeCount ${widget.activeTaskSuffix}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: selected
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).primaryColor,
                          )
                        : null,
                    selected: selected,
                    onTap: () => setState(() => _selectedLv = lv),
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
