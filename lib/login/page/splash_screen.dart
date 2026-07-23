import 'package:flutter/material.dart';

/// otonomiq startup splash / loading screen.
///
/// Rendered by `_BootstrapLoadingApp` BEFORE Firebase + `globalInit()`, and
/// again while the authentication bloc is `Uninitialized`. It MUST stay
/// self-contained: no Firebase, no globals, no `Theme`/brand dependency — the
/// tenant brand is not loaded this early in the lifecycle. Only Flutter
/// material and the bundled logo asset are used.
///
/// Visually identical to the native splash: white background with the brand
/// logo centred at ~the same footprint, so the native → Flutter handoff during
/// the multi-second Firebase/globalInit bootstrap is seamless (no spinner —
/// the native splash has none either).
///
/// White-label: change [_logoAsset] / [_bgColor] only — and keep [_logoAsset]
/// pointing at the same file fed to `flutter_native_splash`.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // ── White-label swap points ──────────────────────────────────────────────
  static const String _logoAsset = 'assets/images/initial_logo.png';
  static const Color _bgColor = Color(0xFFFFFFFF); // == native splash `color`

  @override
  Widget build(BuildContext context) {
    // Size the logo to roughly the native splash footprint: the native
    // density-specific bitmap renders at ~2/3 of screen width, so match that
    // and there is no size jump when the native splash hands off to this frame.
    final double w = MediaQuery.maybeOf(context)?.size.width ?? 360;
    final double logoSize = (w * 0.6).clamp(120.0, 320.0);

    return Scaffold(
      backgroundColor: _bgColor,
      body: Center(
        child: Image.asset(_logoAsset, width: logoSize, height: logoSize),
      ),
    );
  }
}
