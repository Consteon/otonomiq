import 'dart:math' as math;

import 'package:flutter/material.dart';

/// otonomiq startup splash / loading screen.
///
/// Rendered by `_BootstrapLoadingApp` BEFORE Firebase + `globalInit()`, and
/// again while the authentication bloc is `Uninitialized`. It MUST stay
/// self-contained: no Firebase, no globals, no `Theme`/brand dependency — the
/// tenant brand is not loaded this early in the lifecycle. Only Flutter
/// material is imported.
///
/// Modernised: gradient backdrop, a gradient brand badge with a hand-drawn
/// orbit glyph (the orbiting node doubles as the loading indicator), the
/// wordmark, and a slim indeterminate bar. Dark-mode and reduced-motion aware
/// via `MediaQuery` (it cannot use `Theme.of`, since the real theme is not up
/// yet). The `const` constructor is preserved so the existing const call-sites
/// in `main.dart` keep compiling.
///
/// White-label: change [_brandStart] / [_brandEnd] / [_appName] only — these
/// are the single swap points for a rebrand.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── White-label swap points ──────────────────────────────────────────────
  static const Color _brandStart = Color(0xFF2563EB); // blue-600
  static const Color _brandEnd = Color(0xFF7C3AED); // violet-600
  static const String _caption = 'Memuat…';

  late final AnimationController _intro; // one-shot entrance (fade + scale)
  late final AnimationController _loop; // continuous orbit + bar sweep
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is available here (not in initState); start once.
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_started) return;
    _started = true;
    if (reduceMotion) {
      _intro.value = 1.0; // skip the entrance animation entirely
    } else {
      _intro.forward();
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData? media = MediaQuery.maybeOf(context);
    final bool reduceMotion = media?.disableAnimations ?? false;
    final bool isDark =
        (media?.platformBrightness ?? Brightness.light) == Brightness.dark;

    final Color bgTop = isDark ? const Color(0xFF0B1120) : Colors.white;
    final Color bgBottom =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFEEF2F7);
    final Color caption =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);
    final Color barTrack =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Brand badge with orbit glyph (entrance fade + scale) ──
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, child) {
                    final double t =
                        Curves.easeOutCubic.transform(_intro.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
                    );
                  },
                  child: _BrandBadge(
                    start: _brandStart,
                    end: _brandEnd,
                    loop: _loop,
                    reduceMotion: reduceMotion,
                  ),
                ),
                const SizedBox(height: 30),

                // ── Slim indeterminate bar ──
                SizedBox(
                  width: 140,
                  height: 4,
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (context, _) => CustomPaint(
                      painter: _IndeterminateBarPainter(
                        t: _loop.value,
                        track: barTrack,
                        start: _brandStart,
                        end: _brandEnd,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Caption ──
                Text(
                  _caption,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The gradient app badge holding the orbit glyph. Sized 92×92 with a soft
/// brand-tinted shadow; the orbiting node is driven by [loop] (static when
/// [reduceMotion]).
class _BrandBadge extends StatelessWidget {
  const _BrandBadge({
    required this.start,
    required this.end,
    required this.loop,
    required this.reduceMotion,
  });

  final Color start;
  final Color end;
  final Animation<double> loop;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: end.withValues(alpha: 0.32),
            blurRadius: 28,
            spreadRadius: -2,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) => CustomPaint(
          painter: _OrbitGlyphPainter(
            t: reduceMotion ? 0.0 : loop.value,
            reduceMotion: reduceMotion,
          ),
          size: const Size(92, 92),
        ),
      ),
    );
  }
}

/// Draws a white orbit ring with a single node travelling around it — an
/// automation/loading motif. The node sits static at the top when motion is
/// reduced.
class _OrbitGlyphPainter extends CustomPainter {
  _OrbitGlyphPainter({required this.t, required this.reduceMotion});

  final double t; // 0..1 loop phase
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width * 0.26;

    final Paint ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    // Orbit ring with a small gap (open ring reads more "dynamic").
    final Rect orbitRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(orbitRect, -math.pi / 2 + 0.5, math.pi * 1.7, false, ring);

    // Inner core dot.
    final Paint core = Paint()..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawCircle(center, 4.0, core);

    // Orbiting node.
    final double angle = -math.pi / 2 + t * 2 * math.pi;
    final Offset node = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    // Soft halo behind the node.
    canvas.drawCircle(
      node,
      8.5,
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.drawCircle(node, 5.0, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OrbitGlyphPainter old) =>
      old.t != t || old.reduceMotion != reduceMotion;
}

/// A slim rounded indeterminate progress bar. A brand-gradient segment sweeps
/// across the track; when motion is reduced it shows a static centred segment.
class _IndeterminateBarPainter extends CustomPainter {
  _IndeterminateBarPainter({
    required this.t,
    required this.track,
    required this.start,
    required this.end,
    required this.reduceMotion,
  });

  final double t; // 0..1 loop phase
  final Color track;
  final Color start;
  final Color end;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect full = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height),
    );
    canvas.drawRRect(full, Paint()..color = track);

    final double segW = size.width * 0.42;
    final double dx;
    if (reduceMotion) {
      dx = (size.width - segW) / 2; // static centred segment
    } else {
      // Ease in-out sweep that travels off both edges and back.
      final double phase =
          Curves.easeInOut.transform((math.sin(t * 2 * math.pi) + 1) / 2);
      dx = (size.width + segW) * phase - segW;
    }

    final Rect segRect = Rect.fromLTWH(
      dx.clamp(-segW, size.width),
      0,
      segW,
      size.height,
    );
    final Paint seg = Paint()
      ..shader = LinearGradient(colors: [start, end]).createShader(segRect);

    canvas.save();
    canvas.clipRRect(full); // keep the sweeping segment inside the track
    canvas.drawRRect(
      RRect.fromRectAndRadius(segRect, Radius.circular(size.height)),
      seg,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IndeterminateBarPainter old) =>
      old.t != t || old.reduceMotion != reduceMotion;
}
