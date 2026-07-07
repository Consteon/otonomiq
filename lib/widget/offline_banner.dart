import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart'; // internetConnectionFlag (RxBool, global.dart:263)

/// Global offline banner host for the MainPage shell.
///
/// Wraps the Scaffold body of MainPage (lib/page/main_page.dart) so EVERY
/// page -- login, home, any SDUI screen, the notification bypass -- shows a
/// thin "Offline" strip above the body while [internetConnectionFlag] is
/// false. Dart-level only: no JSON deploy, no dispatch branch, no per-screen
/// state, nothing added to global.dart (the flag already exists and is
/// maintained by the connectivity listener, global.dart:753).
///
/// NOT an SDUI component: launched structurally from main_page.dart, so it
/// is imported directly (like otq_bottom_nav_bar.dart), not via the
/// all_widget.dart barrel and not via build_display_component.
class OfflineBannerHost extends StatelessWidget {
  const OfflineBannerHost({super.key, required this.child});

  /// The original Scaffold body content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      // stretch = full-width children, reproducing the tight horizontal
      // constraint a bare Scaffold body gives its child (Column defaults to
      // center -> loose width, which could shrink-wrap odd interiors).
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => internetConnectionFlag.value
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  color: const Color(0xFF334155), // slate-700
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.cloud_off, size: 14, color: Colors.white70),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Offline — perubahan disimpan & dikirim otomatis',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
