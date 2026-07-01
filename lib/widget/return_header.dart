import 'package:flutter/material.dart';

import '../global.dart';

/// RETURN_HEADER -- label + title header for P12 ReturnVehicle.
///
/// Pure presentational header. Reads `text` (2 diamond segments: label,
/// title) from component JSON. Back navigation is handled by the AppBar
/// back button (routeStack), so this header renders no in-body back arrow.
///
/// No table subscriptions, no txfController, no saveSend, no history.
class ReturnHeader extends StatelessWidget {
  const ReturnHeader({
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
  Widget build(BuildContext context) {
    // Parse text: [0] label (uppercase), [1] title
    List<String> textArray;
    try {
      textArray = diamondTextToList(component['text'] ?? '');
    } catch (_) {
      textArray = [];
    }
    String t(int i, String def) => textArray.length > i ? textArray[i] : def;

    final String label = t(0, 'Akhir Hari');
    final String title = t(1, 'Return Kendaraan');

    return Padding(
      padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Uppercase gray label
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: Color(0xFF9CA3AF), // gray-400
            ),
          ),
          const SizedBox(height: 2),
          // Bold dark title
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937), // gray-900
            ),
          ),
        ],
      ),
    );
  }
}
