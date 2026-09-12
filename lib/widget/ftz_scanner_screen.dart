import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme_tokens.dart';

/// The v6 camera-bar title: `"<block> · <method>"` — e.g. `"Absen Masuk · QR"`.
///
/// [block] is the attendance block's own heading, stamped onto the child by the
/// `horizontal_icon` v6 branch, and [method] is the tile label; both come from
/// the sheet, so no Indonesian wording is invented here. Either half missing
/// falls back to [fallback] (text slot 26), which is exactly what the classic
/// screen has always shown in its AppBar.
String scannerBarTitle(String block, String method, String fallback) {
  final String b = block.trim();
  final String m = method.trim();
  if (b.isNotEmpty && m.isNotEmpty) return '$b · $m';
  if (b.isNotEmpty) return b;
  if (m.isNotEmpty) return m;
  return fallback.trim();
}

/// Where the viewfinder square sits inside [box], given the screen's safe areas.
///
/// v6 puts the frame 120 dp below the status bar — 64 dp under the 56 dp bar —
/// and 240 dp on a side. Those numbers are written for a 390x844 mock. On a
/// short or narrow screen the gap collapses FIRST and only then does the frame
/// shrink, so the hint never slides under the bottom sheet; the frame is never
/// allowed below 140 dp, under which a QR at arm's length stops resolving.
Rect scannerFrameRect({
  required Size box,
  required double topInset,
  required double bottomInset,
}) {
  const double bar = 56; // camera top bar
  const double gapMax = 64; // 120 dp below the status bar, bar included
  const double hintBlock = 92; // 20 dp gap + a two-line hint
  const double sheetBlock = 92; // grab + one row of 48 dp buttons + padding
  const double sideMax = 240;
  const double sideMin = 140;
  const double margin = 48;

  final double fixed = topInset + bar + hintBlock + sheetBlock + bottomInset;
  double side = math.min(sideMax, box.width - margin * 2);
  double room = box.height - fixed - side;
  if (room < 0) {
    side = math.max(sideMin, side + room);
    room = box.height - fixed - side;
  }
  if (side < sideMin) side = sideMin;
  final double gap = room > 0 ? math.min(gapMax, room) : 0;
  return Rect.fromLTWH(
    math.max(0, (box.width - side) / 2),
    topInset + bar + gap,
    side,
    side,
  );
}

/// A screen that displays a camera view for scanning QR codes.
class FtzScannerScreen extends StatefulWidget {
  // NEW: Parameter for the AppBar title.
  final String title;

  // UPDATED: The initial camera is now a String ('front' or 'back').
  final String camera;

  /// `v6` opts into the Vertika v6 camera layout (corner viewfinder, scrim,
  /// labelled controls in a bottom sheet). Absent, blank or anything else keeps
  /// the black-AppBar screen every caller has today.
  final String variant;

  /// Second line under [title] on the v6 bar. Ignored by the classic screen.
  final String subtitle;

  const FtzScannerScreen({
    super.key,
    required this.title,
    this.camera = 'back',
    this.variant = '',
    this.subtitle = '',
  });

  @override
  State<FtzScannerScreen> createState() => _FtzScannerScreenState();
}

class _FtzScannerScreenState extends State<FtzScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final MobileScannerController _controller = MobileScannerController(
    // UPDATED: Logic to convert the 'cameraSide' string to a CameraFacing enum.
    facing: widget.camera == 'front' ? CameraFacing.front : CameraFacing.back,
  );
  bool _isProcessing = false;

  // Manually manage the torch state
  bool _isTorchOn = false;

  bool get _isV6 => widget.variant.trim().toLowerCase() == 'v6';

  /// The 2.4 s sweep inside the viewfinder. Idle on the classic screen and
  /// stopped for the rest of the screen's life once a code is read.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  Timer? _popTimer;

  @override
  void initState() {
    super.initState();
    // mobile_scanner only self-manages the app lifecycle when it OWNS the
    // controller (see its _initializeController: addObserver runs only when
    // widget.controller == null). We pass our own controller, so we must
    // restart/stop the camera on resume/inactive here — otherwise the preview
    // stays blank white after a permission dialog or app background/foreground.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isV6) return;
    // Read here, not in build: repeat() is a side effect and MediaQuery can
    // change under us (a rotation, or the user flipping "reduce motion").
    if (MediaQuery.of(context).disableAnimations || _isProcessing) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // v6 shows an explicit "camera not allowed" screen with a route into the
    // system settings, so it has to try again on the way back — at which point
    // permission is exactly what has just changed. The classic screen keeps its
    // original guard.
    if (!_isV6 && !_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _fireAndForget(_controller.start());
        break;
      case AppLifecycleState.inactive:
        _fireAndForget(_controller.stop());
        break;
      default:
        break;
    }
  }

  /// A camera call whose result nobody waits for.
  ///
  /// `unawaited` alone is not enough here: start/stop reject when the platform
  /// side has already torn the camera down, and an un-awaited rejection is an
  /// unhandled async error, which this app reports as a fatal. There is nothing
  /// to recover -- the camera is being handed back either way.
  void _fireAndForget(Future<void> call) {
    unawaited(call.catchError((Object _) {}));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String? qrResult = barcodes.first.rawValue;
    if (qrResult == null || qrResult.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });
    if (!_isV6) {
      // Same release-before-pop as the v6 branch below: the checker alternates
      // this scanner and the selfie camera over ONE back camera on every scan.
      _fireAndForget(_controller.stop());
      Navigator.of(context).pop(qrResult);
      return;
    }
    // v6: hold the read state briefly. The screen knows the code was READ; it
    // does not know it is VALID -- the caller verifies. So the brackets go
    // green, the sweep stops and one haptic fires, and the hint says
    // "memverifikasi", never "berhasil": a success this screen cannot promise
    // is a success it would have to take back.
    _sweep.stop();
    HapticFeedback.mediumImpact();
    _popTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      // ★ Release the camera HERE, not in dispose(). dispose() runs only once
      // the pop transition has finished, so the back camera stayed held for
      // this 420 ms hold PLUS the animation -- and the attendance flow opens
      // the selfie camera on the same hardware a few hundred ms later. That
      // overlap is what leaves the next screen on a black preview
      // (camerax: "Unknown camera ID 0", then an open-retry loop that never
      // recovers). Nothing is lost visually: the last frame stays on screen
      // until the route is gone.
      _fireAndForget(_controller.stop());
      Navigator.of(context).pop(qrResult);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isV6) return _buildClassic(context);
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (BuildContext context, MobileScannerState state, Widget? _) {
        if (state.error?.errorCode == MobileScannerErrorCode.permissionDenied) {
          return _buildDenied(context);
        }
        return _buildV6(context, state);
      },
    );
  }

  // ── Classic — what every caller without `variant: "v6"` still renders. ─────
  Widget _buildClassic(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // UPDATED: Using the 'title' parameter from the widget.
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withAlpha(128),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 250,
                    width: 250,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.only(top: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 32.0,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                    ),
                    onPressed: () => _controller.switchCamera(),
                    iconSize: 32.0,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.bolt,
                      color: _isTorchOn ? Colors.amber : Colors.white,
                    ),
                    onPressed: () {
                      _controller.toggleTorch();
                      setState(() {
                        _isTorchOn = !_isTorchOn;
                      });
                    },
                    iconSize: 32.0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── v6 ────────────────────────────────────────────────────────────────────

  Widget _buildV6(BuildContext context, MobileScannerState state) {
    final MediaQueryData mq = MediaQuery.of(context);
    final bool front = state.cameraDirection == CameraFacing.front;
    final bool torchOn = state.torchState == TorchState.on;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final Rect frame = scannerFrameRect(
              box: Size(box.maxWidth, box.maxHeight),
              topInset: mq.padding.top,
              bottomInset: mq.padding.bottom,
            );
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ViewfinderPainter(
                        frame: frame,
                        // Non-text mark, so the 3:1 bar applies and
                        // #6EE7B7 measures 3.30:1 on the scrim over a
                        // fully-white scene. The hint LABEL stays white --
                        // green text would be 3.30:1 at 16/600, which is
                        // under the 4.5:1 it owes.
                        corner: _isProcessing
                            ? OtqPalette.successOnDark
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
                if (!_isProcessing && !mq.disableAnimations)
                  _sweepLine(frame)
                else if (_isProcessing)
                  _readBadge(frame),
                _hint(frame, front: front, torchOn: torchOn),
                _bar(mq.padding.top),
                _sheet(mq.padding.bottom, front: front, torchOn: torchOn),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sweepLine(Rect frame) {
    return Positioned(
      left: frame.left + 12,
      top: frame.top,
      width: frame.width - 24,
      height: frame.height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _sweep,
          builder: (BuildContext context, Widget? _) {
            final double travel = frame.height - 28;
            return Padding(
              padding: EdgeInsets.only(top: 14 + travel * _sweep.value),
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _readBadge(Rect frame) {
    return Positioned(
      left: frame.center.dx - 32,
      top: frame.center.dy - 32,
      width: 64,
      height: 64,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                OtqPalette.successOnDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(Rect frame, {required bool front, required bool torchOn}) {
    final String head;
    final String body;
    if (_isProcessing) {
      head = 'Kode terbaca';
      body = 'Memverifikasi…';
    } else if (front) {
      head = 'Kamera depan aktif';
      body =
          'Untuk kode QR di layar perangkat lain; '
          'ketuk Balik kamera untuk kembali';
    } else {
      head = 'Arahkan kamera ke kode QR';
      body = torchOn
          ? 'Senter menyala · jaga jarak ±20 cm dari kode'
          : 'Pindai berjalan otomatis, tidak perlu menekan apa pun';
    }
    return Positioned(
      left: 24,
      right: 24,
      top: frame.bottom + 20,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                head,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  // v6 writes this line at 86% white, which measures 4.22:1 on
                  // the scrim over a fully-white scene -- under the 4.5:1 a
                  // 14 dp line owes. 92% measures 4.54:1 and is the same line
                  // to look at.
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(double topInset) {
    final String sub = widget.subtitle.trim();
    return Positioned(
      left: 0,
      right: 0,
      top: topInset,
      height: 56,
      child: Row(
        children: <Widget>[
          // One way out, and it always means the same thing: cancel and go
          // back. The classic screen had both an AppBar arrow and a floating X.
          SizedBox(
            width: 56,
            height: 56,
            child: IconButton(
              tooltip: 'Tutup pemindai',
              icon: const Icon(Icons.close, color: Colors.white),
              iconSize: 26,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
                if (sub.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _sheet(
    double bottomInset, {
    required bool front,
    required bool torchOn,
  }) {
    // Controls live on their own white surface instead of floating over the
    // camera: an icon on the scene contrasts with whatever happens to be behind
    // it, which at a bright guard post is nothing.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(16, 14, 16, 18 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: OtqPalette.v6DisabledFg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _sheetButton(
                    icon: Icons.bolt,
                    label: torchOn ? 'Senter nyala' : 'Senter',
                    on: torchOn,
                    // No flash on a front camera; say so rather than let the
                    // tap do nothing.
                    onTap: front ? null : () => _controller.toggleTorch(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sheetButton(
                    icon: Icons.flip_camera_ios,
                    label: front ? 'Kamera depan' : 'Balik kamera',
                    on: front,
                    onTap: () => _controller.switchCamera(),
                  ),
                ),
              ],
            ),
            if (front) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Senter tidak tersedia di kamera depan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sheetButton({
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback? onTap,
  }) {
    final Color primary = Theme.of(context).primaryColor;
    final bool off = onTap == null;
    final Color fg = off
        ? OtqPalette.v6DisabledFg
        : (on ? primary : OtqPalette.foreground);
    return Semantics(
      button: true,
      enabled: !off,
      toggled: on,
      child: Material(
        color: on ? primary.withValues(alpha: 0.10) : OtqPalette.v6Muted,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: on
                  ? Border.all(color: primary, width: 1.5)
                  : Border.all(color: Colors.transparent, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Camera permission denied. Not a black rectangle: say why, offer the one
  /// thing that fixes it, and leave a way back to the other attendance methods.
  Widget _buildDenied(BuildContext context) {
    final Color primary = Theme.of(context).primaryColor;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: OtqPalette.v6Muted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.videocam_off_outlined,
                  size: 34,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Kamera belum diizinkan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: OtqPalette.foreground,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aplikasi butuh akses kamera untuk memindai kode QR absensi. '
                'Aktifkan izin Kamera di pengaturan, lalu kembali ke sini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OtqPalette.v6Accent,
                    foregroundColor: OtqPalette.v6OnAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => unawaited(openAppSettings()),
                  child: const Text('Buka Pengaturan'),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Kembali',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    _sweep.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }
}

/// Paints the scrim everywhere except the viewfinder, plus the four corner
/// brackets. One painter so the two can never drift out of registration; the
/// sweep line is a separate widget so an animating line does not repaint this.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.frame, required this.corner});

  final Rect frame;
  final Color corner;

  @override
  void paint(Canvas canvas, Size size) {
    // Same 14 dp as the bracket corners, so the two register exactly.
    const double radius = 14;
    final Path outer = Path()..addRect(Offset.zero & size);
    final Path hole = Path()
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(radius)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, hole),
      Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.62),
    );

    const double arm = 32;
    const double r = 14;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = corner;
    final Path b = Path()
      // top-left
      ..moveTo(frame.left, frame.top + arm)
      ..lineTo(frame.left, frame.top + r)
      ..arcToPoint(
        Offset(frame.left + r, frame.top),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.left + arm, frame.top)
      // top-right
      ..moveTo(frame.right - arm, frame.top)
      ..lineTo(frame.right - r, frame.top)
      ..arcToPoint(
        Offset(frame.right, frame.top + r),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.right, frame.top + arm)
      // bottom-right
      ..moveTo(frame.right, frame.bottom - arm)
      ..lineTo(frame.right, frame.bottom - r)
      ..arcToPoint(
        Offset(frame.right - r, frame.bottom),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.right - arm, frame.bottom)
      // bottom-left
      ..moveTo(frame.left + arm, frame.bottom)
      ..lineTo(frame.left + r, frame.bottom)
      ..arcToPoint(
        Offset(frame.left, frame.bottom - r),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.left, frame.bottom - arm);
    canvas.drawPath(b, stroke);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.frame != frame || old.corner != corner;
}
