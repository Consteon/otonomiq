import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart';
import 'custody_count_list.dart';
import 'driver_home_support.dart';

/// CUSTODY_COUNT_SUBMIT -- P6 send-button replacing the plain RBT.
///
/// Reads the reactive count store from [CustodyCountList.countStore] (Obx) to:
/// - Show "HITUNG SEMUA ITEM (n/N)" when any rendered item has count == 0.
/// - Show "LIHAT CATATAN WAREHOUSE ->" when ALL items > 0.
///
/// On tap (enabled):
/// 1. Build `ip[]` = array of `{ii, cd, qt}` from the count store.
/// 2. Native write `{ip: ipArray}` to the opening vehicle_check doc via
///    [writeNativeFields] (set-merge, bypasses history queue).
/// 3. On success: nav to custodyReveal. On failure: snackbar, no nav.
///
/// The widget does NOT subscribe vehicle_check itself -- it reads the table
/// path and search from its component JSON and passes them to
/// [writeNativeFields], which resolves tokens and queries Firestore directly.
class CustodyCountSubmit extends StatelessWidget {
  const CustodyCountSubmit({
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

  /// Per-scrName writing-in-progress flag to prevent double taps.
  static final Map<String, bool> _writing = {};

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch the revision signal to register Obx dependency.
      CustodyCountList.countRev.value;

      final Map<String, CountEntry> countMap =
          CustodyCountList.getCountMap(scrName);

      final int total = countMap.length;
      final int n = countMap.values.where((e) => e.qty > 0).length;
      final bool enabled = total > 0 && n == total;
      final bool isWriting = _writing[scrName] ?? false;

      final String label = enabled
          ? 'LIHAT CATATAN WAREHOUSE \u{2192}' // right arrow
          : 'HITUNG SEMUA ITEM ($n/$total)';

      // Colors
      final Color bgColor = enabled && !isWriting
          ? const Color(0xFF4338CA) // indigo-700
          : const Color(0xFFD1D5DB); // gray-300
      final Color textColor = enabled && !isWriting
          ? Colors.white
          : const Color(0xFF6B7280); // gray-500

      return Padding(
        padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (enabled && !isWriting) ? () => _onTap(context) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              foregroundColor: textColor,
              disabledForegroundColor: const Color(0xFF6B7280),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isWriting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      );
    });
  }

  Future<void> _onTap(BuildContext context) async {
    if (_writing[scrName] == true) return; // debounce

    // 1. Build ip[]
    final Map<String, CountEntry> countMap =
        CustodyCountList.getCountMap(scrName);
    final List<Map<String, dynamic>> ipArray = <Map<String, dynamic>>[];
    for (final entry in countMap.values) {
      ipArray.add(entry.toIpMap());
    }

    if (ipArray.isEmpty) return; // safety

    // 2. Read table + search from component
    final String rawTable = (component['table'] ?? '').toString().trim();
    final String rawSearch = (component['search'] ?? '').toString().trim();
    final String writeField =
        (component['writeField'] ?? 'ip').toString().trim();

    if (rawTable.isEmpty || rawSearch.isEmpty) {
      _showSnackBar(context, 'Konfigurasi tidak lengkap');
      return;
    }

    // 3. Write natively
    _writing[scrName] = true;
    // Trigger rebuild to show spinner
    CustodyCountList.countRev.value++;

    try {
      final bool success = await writeNativeFields(
        component: component,
        rawTable: rawTable,
        rawSearch: rawSearch,
        scrName: scrName,
        patch: {writeField: ipArray},
      );

      if (!success) {
        if (context.mounted) {
          _showSnackBar(context, 'Gagal menyimpan data');
        }
        return;
      }

      // 4. Navigate to custodyReveal
      final String rawRoute = (component['route'] ?? '').toString().trim();
      final String route = stripRouteWrapper(rawRoute);
      if (route.isEmpty) return;

      if (routeExist(route)) {
        routeStack.push(route);
        gotoRoute(route);
      } else {
        if (context.mounted) {
          _showSnackBar(context, 'Layar belum tersedia');
        }
      }
    } finally {
      _writing[scrName] = false;
      CustodyCountList.countRev.value++;
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
