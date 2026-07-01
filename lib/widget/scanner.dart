import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';
import '../crypto/auth_crypto.dart';
import '../firestore_repository/scanner_validate.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';
import 'driver_home_support.dart';

/// Length-guarded slot access for Scanner text slots.
///
/// Returns [fallback] when [index] is out of range OR when the value
/// at [index] is empty. Exported as a top-level function so tests can
/// import and exercise the real implementation.
String scannerSlot(List<String> arr, int index, String fallback) {
  return arr.length > index && arr[index].isNotEmpty ? arr[index] : fallback;
}

/// Extract the first search field name from the component `search` value.
///
/// Multi-field values are separated by `★` (U+2605). v1 uses only the first
/// field; subsequent fields are documented as UNSUPPORTED (the non-scan value
/// source is OPEN per spec). Returns empty string if [raw] is empty/whitespace.
///
/// Exported as a top-level function so tests can exercise the real implementation.
String scannerSearchField(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split('★').first.trim();
}

/// SDUI component: in-page rounded viewport card with a **live inline camera**
/// that auto-starts and auto-detects QR/barcodes. On successful scan:
///
/// - If `component['qr'] == 'uqr'`: decrypts the QR via [getVidUQR] to obtain
///   the VID. Non-uqr or absent `qr`: uses the raw scan string as the VID.
/// - Stores the resolved VID in `#has_user_login`.
/// - Validates against the workforce table (local-first with Firestore fallback).
/// - Writes a session event through [saveSend] and navigates to
///   `component['route']`.
///
/// Invalid/unrecognized scans show a snackbar and restart the camera.
///
/// ## Text slot map (v1, server location-style)
///
/// Diamond-delimited `component['text']`:
///
/// Server uses the location-style slot layout. The lean inline widget READS
/// slots 0/1/7/9/10 only; others are documented for server alignment.
///
/// | Index | Meaning                     | Read | Default      |
/// |-------|-----------------------------|------|--------------|
/// | 0     | Card title                  | yes  | `'Scan'`     |
/// | 1     | Card subtitle               | yes  | `''`         |
/// | 2-6   | (server-reserved, not read) | no   | --           |
/// | 7     | Success snackbar message    | yes  | `'Berhasil'` |
/// | 8     | OK label                    | no   | --           |
/// | 9     | Wrong-result title          | yes  | `'QR salah'` |
/// | 10    | Wrong-result message        | yes  | `''`         |
/// | 11    | Retry label                 | no   | --           |
class Scanner extends StatefulWidget {
  const Scanner({
    super.key,
    required this.component,
    required this.scrName,
    this.lPad = 0,
    this.tPad = 0,
    this.rPad = 0,
    this.bPad = 0,
  });

  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  State<Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<Scanner> with SingleTickerProviderStateMixin {
  bool _isProcessing = false;

  /// Session gate: set true once the auto-skip has decided to navigate away
  /// (driver already logged in). Idempotent guard — prevents a second
  /// post-frame navigation on rebuild. See [_maybeAutoSkip].
  bool _didAutoSkip = false;

  late final MobileScannerController _cameraController;
  late final AnimationController _scanLineController;
  late final Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();

    // Camera controller -- autoStart means it begins as soon as MobileScanner
    // widget attaches (which happens in build). Mirrors
    // ftz_scanner_screen.dart:23-28.
    _cameraController = MobileScannerController(
      autoStart: true,
      facing: CameraFacing.back,
    );

    // Scan-line animation (retained from round 2)
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    // ── Table pre-load (round 7 bug fix) ──────────────────────────────
    // Pre-load the workforce table into #TABLE<code> so scannerVidInWorkforce
    // can use the fast local findData path instead of the Firestore fallback.
    // Without this, #TABLE<code> is never populated and the compare always
    // failed -> "QR salah" for every valid QR. Mirrors otq_txf_2.dart:230-246.
    //
    // scannerTableCode (scanner_validate.dart) derives the SAME key that
    // scannerVidInWorkforce reads, guaranteeing the load key == lookup key.
    //
    // Fire-and-forget: no await, no .then, no unsubscribe at dispose (matches
    // txf -- "todo unsubscribe if desirable"; #REFTABLE<code> guards against
    // double-subscribe on remount).
    final String tableRaw = (widget.component['table'] ?? '').toString().trim();
    final String tableCode = scannerTableCode(tableRaw);
    if (tableCode.isNotEmpty) {
      subscribeToTable(
        tableCode,
        getTableVid(widget.component['com']),
        indexTableType: 'K',
      );
    }

    // ---- Session gate (W1/W2): skip camera if the driver is already logged
    // in. #has_user_login is restored from secure storage in globalInit. We
    // attempt the skip here first; build() retries it on every rebuild while
    // still pending so a cold start (DriverHome page not yet built ->
    // routeExist false in initState) still fires once the page set is ready.
    _maybeAutoSkip();
  }

  /// W1 (cold-start race) + W2 (back-nav = home): if the driver already holds
  /// a session (#has_user_login non-empty) and the target route exists, replace
  /// the scanner in the route stack with the target and navigate there.
  ///
  /// Idempotent via [_didAutoSkip]: the post-frame navigation is scheduled at
  /// most once. Until it fires, this is a no-op when the target route isn't
  /// built yet (`routeExist(route)` false on a cold start), and build() calls
  /// it again on the next rebuild — so the skip *eventually* fires once the
  /// SDUI page set becomes ready, instead of silently falling through to the
  /// camera forever.
  void _maybeAutoSkip() {
    if (_didAutoSkip) return;
    final String existingVid =
        (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
    final String route = (widget.component['route'] ?? '').toString();
    if (existingVid.isEmpty || route.isEmpty || !routeExist(route)) return;

    // Commit the decision now (before scheduling) so build() renders the
    // loading placeholder instead of the camera on this and later frames.
    _didAutoSkip = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // W2: replace the scanner in the stack rather than push on top.
      // routeStack.push(home) truncates the stack to [home]
      // (route_stack.dart:11-13); then push(route) yields [home, DriverHome],
      // so AppBar back from DriverHome -> home (no re-skip loop).
      routeStack.push(home);
      routeStack.push(route);
      gotoRoute(route);
    });
  }

  @override
  void dispose() {
    // Order matters -- camera first, animation second.
    _cameraController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  // ── Scan detect handler (qr-gated decrypt + store + hybrid compare) ── round 6 ──
  Future<void> _onScanDetected(String rawQR) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // 1. Stop camera immediately to prevent further onDetect callbacks.
    _cameraController.stop();

    // 2. QR MODE GATE (round 6): branch on component['qr'].
    //    'uqr' = encrypted user-QR -> decrypt via getVidUQR.
    //    absent/empty/other = plain -> raw scan string IS the value.
    //    Mirrors otq_txf_2.dart:274-279 gating pattern.
    final String qrMode = (widget.component['qr'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    String vidStr;

    if (qrMode == 'uqr') {
      // DECRYPT path: getVidUQR decrypts the encrypted URL -> VID int, or -1.
      //    auth_crypto.dart is a gitignored secret; CALL ONLY, never modify.
      //    Mirrors getQRContent qrType=='U' path (api.dart).
      final int vid = await getVidUQR(rawQR);
      if (!mounted) return;

      // DIAGNOSTIC (kDebugMode-only via devPrint): a vid of -1 here surfaces to
      // the user as "tidak dikenal". Logging the raw QR + format probes + the
      // decrypt result tells the two failure modes apart:
      //   - no `http` / no `/qr/` segment  -> malformed or non-user QR (format)
      //   - well-formed http+/qr/ URL but vid == -1 -> the cipher did NOT
      //     decrypt to the marker with THIS device's getSharedKey(1), i.e. the
      //     tag was minted under a different sd1/sd2 secret-generation than the
      //     device holds (a working tag of the same domain proves the device
      //     key itself is valid).
      // Scan a failing tag and a working tag; compare. Remove once the
      // "tidak dikenal" reports are resolved.
      final int qrSegIdx = rawQR.lastIndexOf('/qr/');
      final String qrCipher = qrSegIdx >= 0
          ? rawQR.substring(qrSegIdx + 4)
          : '';
      final bool hasHttp = rawQR.length >= 4 && rawQR.substring(0, 4) == 'http';
      devPrint(
        'scanner UQR decode: vid=$vid hasHttp=$hasHttp '
        'hasQrSeg=${qrSegIdx >= 0} cipherLen=${qrCipher.length} raw=$rawQR',
      );

      if (vid == -1) {
        // Decrypt-fail: unrecognized QR (not a valid encrypted URL).
        // Do NOT store #has_user_login. Show "tidak dikenal" snackbar + rescan.
        _doInvalid('tidak dikenal');
        return;
      }
      vidStr = vid.toString();
    } else {
      // PLAIN path: raw scan string IS the value (no decrypt).
      vidStr = rawQR.trim();
      if (vidStr.isEmpty) {
        // Empty scan result. Do NOT store #has_user_login.
        _doInvalid('tidak dikenal');
        return;
      }
    }

    // 3. BOTH paths continue identically from here.
    //    Resolve the tenant container vid (round 8 fix). component['com']
    //    selects which tenant's MobileTable container the workforce
    //    subcollection lives under. getTableVid('con') = 20342033315492
    //    (Consteon master container, where the VTL tables live). null/'' ->
    //    applicationTableVid (current tenant, backward-compatible). getTableVid
    //    (api.dart:74) is reachable via the existing api.dart import.
    final int tenantVid = getTableVid(widget.component['com']?.toString());
    devPrint('scanner _onScanDetected vidStr=$vidStr tenantVid=$tenantVid');

    //    STORE #has_user_login = resolved VID in Redux transactionStore.
    //    This is a #-prefixed datastore key (documented in documentation.md).
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#has_user_login': vidStr})),
    );
    // Mirror to secure storage so the driver stays logged in across app
    // restarts. Fire-and-forget (local I/O must not block the scan flow);
    // cleared again below if the workforce compare fails (not-found path).
    unawaited(persistDriverLogin(vidStr));

    // 4. Parse validation fields from component JSON.
    final String tableRaw = (widget.component['table'] ?? '').toString().trim();
    final String searchRaw = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final String searchField = scannerSearchField(searchRaw);

    // 5. Validation gate (same fail-open / fail-closed structure as round 4).
    //    - Both empty: fail-open (legacy configs without table/search).
    //    - Only one populated: fail-closed (misconfigured).
    //    - Both populated + valid searchField: hybrid workforce compare.
    if (tableRaw.isEmpty && searchRaw.isEmpty) {
      // No validation fields -- skip validation, go straight to success.
      await _doSuccess(vidStr);
      return;
    }
    if (tableRaw.isEmpty || searchField.isEmpty) {
      // Misconfigured: one side missing. Fail closed.
      _doInvalidNotFound();
      return;
    }

    // 6. Hybrid workforce compare (local-first + Firestore fallback).
    //    Pass tenantVid (round 8) so the Firestore fallback path queries the
    //    correct tenant container.
    try {
      final bool found = await scannerVidInWorkforce(
        tableRaw,
        searchField,
        vidStr,
        tenantVid: tenantVid,
      );
      if (!mounted) return;
      if (found) {
        await _doSuccess(vidStr);
      } else {
        _doInvalidNotFound();
      }
    } catch (_) {
      // Query error (offline, permission, path error) -> treat as not-found.
      if (!mounted) return;
      _doInvalidNotFound();
    }
  }

  // ── Success path (validated or validation-skipped) ─────────────────
  Future<void> _doSuccess(String vidStr) async {
    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );

    // 1. Write BARE screen-tx marker with the resolved VID for
    //    <SCAN_RESULT> DSL resolution by _resolveScreenTxMarkers
    //    (api.dart:3779). No '#' prefix. #has_user_login stays set.
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'SCAN_RESULT': vidStr})),
    );

    // 2. Acquire timestamp and location for saveSend
    final int timeStamp = await getRealTime();
    if (!mounted) return;
    final OtqState locSensor = await OtqState().setAllDataAsync();
    if (!mounted) return;
    final String locString = getLocationString('', '', '', locSensor);

    // 3. Call saveSend (enqueues offline, never awaits network).
    //    saveSend autheniumDecodes addToTable internally -- do NOT double-decode.
    saveSend(
      timeStamp,
      widget.scrName,
      widget.component,
      locString,
      defaultVid(),
    );

    // 4. Clear scan result marker (safe: resolution is synchronous
    //    inside saveSend at api.dart:3884)
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'SCAN_RESULT': ''})),
    );

    // 5. Brief non-blocking SnackBar success feedback (slot 7)
    if (mounted) {
      final successMsg = scannerSlot(slots, 7, 'Berhasil');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // 6. Navigate (routeStack.push BEFORE gotoRoute -- Convention #1)
    if (!mounted) return;
    final String route = (widget.component['route'] ?? '').toString();
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
    // No finally reset of _isProcessing -- after a successful scan the widget
    // navigates away. If the route is empty/invalid the camera stays stopped
    // and the user sees the last frame (acceptable v1).
  }

  // ── Invalid path (decrypt-fail / plain-empty) ── round 5, refined round 6 ──
  void _doInvalid(String message) {
    // Show snackbar with the provided message (e.g. "tidak dikenal").
    // Do NOT touch #has_user_login (was never stored for this path).
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }

    // Restart camera for re-scan + reset processing flag.
    _cameraController.start();
    if (mounted) setState(() => _isProcessing = false);
  }

  // ── Not-found path (VID not in workforce / query-error / misconfigured) ──
  void _doInvalidNotFound() {
    // 1. Clear #has_user_login (VID was stored in _onScanDetected step 3
    //    but is not in the workforce table -- clean up).
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#has_user_login': ''})),
    );
    // Clear persisted driver login (mirrors the Redux clear above) so a
    // not-found scan never leaves a stale session on disk.
    unawaited(clearDriverLogin());

    // 2. Show "QR salah" snackbar from slots 9 and 10.
    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );
    if (mounted) {
      final wrongTitle = scannerSlot(slots, 9, 'QR salah');
      final wrongMsg = scannerSlot(slots, 10, '');
      final String snackText = wrongMsg.isNotEmpty
          ? '$wrongTitle: $wrongMsg'
          : wrongTitle;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackText),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // 3. Restart camera for re-scan + reset processing flag.
    _cameraController.start();
    if (mounted) setState(() => _isProcessing = false);
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // W1: re-attempt the session-gate skip on every rebuild while it is still
    // pending. On a cold start the DriverHome route may not be built yet at
    // initState (routeExist false); this catches the later rebuild once the
    // SDUI page set is ready, so a logged-in driver is never stranded on the
    // camera. No-op once _didAutoSkip is committed.
    _maybeAutoSkip();

    // If the skip is committed, show a minimal loading indicator instead of the
    // camera (avoids a camera init + immediate dispose flash before the
    // post-frame navigation fires).
    if (_didAutoSkip) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );
    final title = scannerSlot(slots, 0, 'Scan');
    final subtitle = scannerSlot(slots, 1, '');

    return Container(
      margin: EdgeInsets.only(
        top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
        bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble(),
      ),
      padding: EdgeInsets.fromLTRB(
        widget.lPad + (widget.component['leftPadding'] ?? 0.0).toDouble(),
        widget.tPad,
        widget.rPad + (widget.component['rightPadding'] ?? 0.0).toDouble(),
        widget.bPad,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Viewport card with live camera ──
          _buildViewportCard(context),
          const SizedBox(height: 16),
          // ── Title ──
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF1A1A2E),
            ),
          ),
          // ── Subtitle ──
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewportCard(BuildContext context) {
    const double bracketLength = 32;
    const double bracketThickness = 3;
    const double bracketInset = 22;
    const Color neonIndigo = Color(0xFF5B6CFF);
    const Color cardBg = Color(0xFF0F1729);
    const double borderRadius = 28;

    // Camera viewport size is driven by the server JSON `width`/`height`,
    // clamped to the available screen width while preserving the
    // width:height aspect ratio. Falls back to a 220 square when missing/invalid.
    // Guarded reads: `component` is dynamic server data.
    const double fallbackSize = 220;
    final num? wRaw = widget.component['width'] is num
        ? widget.component['width'] as num
        : null;
    final num? hRaw = widget.component['height'] is num
        ? widget.component['height'] as num
        : null;
    final double jsonW = (wRaw != null && wRaw > 0)
        ? wRaw.toDouble()
        : fallbackSize;
    final double jsonH = (hRaw != null && hRaw > 0) ? hRaw.toDouble() : jsonW;
    final double aspect = jsonW / jsonH; // width / height
    final double availW =
        MediaQuery.of(context).size.width - widget.lPad - widget.rPad - 24;
    final double cardW = (availW > 0 && jsonW > availW) ? availW : jsonW;
    final double cardH = cardW / aspect; // preserve aspect ratio

    return SizedBox(
      key: const Key('scanner-viewport'),
      width: cardW,
      height: cardH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // ── Layer 0: Live camera feed (or error/placeholder) ──
            Positioned.fill(
              child: ColoredBox(
                color: cardBg,
                child: MobileScanner(
                  controller: _cameraController,
                  fit: BoxFit.cover,
                  onDetect: (BarcodeCapture capture) {
                    if (_isProcessing) return;
                    final barcodes = capture.barcodes;
                    if (barcodes.isEmpty) return;
                    final String? rawValue = barcodes.first.rawValue;
                    if (rawValue == null || rawValue.isEmpty) return;
                    _onScanDetected(rawValue);
                  },
                  placeholderBuilder: (context) {
                    // Shown while camera is initializing
                    return ColoredBox(
                      color: cardBg,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: neonIndigo.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error) {
                    // Permission denied / camera unavailable -- inline fallback
                    return ColoredBox(
                      color: cardBg,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_off,
                              color: neonIndigo.withValues(alpha: 0.5),
                              size: 36,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              error.errorCode ==
                                      MobileScannerErrorCode.permissionDenied
                                  ? 'Izin kamera ditolak'
                                  : 'Kamera tidak tersedia',
                              style: TextStyle(
                                color: neonIndigo.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                _cameraController.start();
                              },
                              child: Text(
                                'Coba Lagi',
                                style: TextStyle(
                                  color: neonIndigo,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Layer 1: Corner brackets (4 corners) ──
            // Top-left
            Positioned(
              top: bracketInset,
              left: bracketInset,
              child: _CornerBracket(
                length: bracketLength,
                thickness: bracketThickness,
                color: neonIndigo,
                corner: _Corner.topLeft,
              ),
            ),
            // Top-right
            Positioned(
              top: bracketInset,
              right: bracketInset,
              child: _CornerBracket(
                length: bracketLength,
                thickness: bracketThickness,
                color: neonIndigo,
                corner: _Corner.topRight,
              ),
            ),
            // Bottom-left
            Positioned(
              bottom: bracketInset,
              left: bracketInset,
              child: _CornerBracket(
                length: bracketLength,
                thickness: bracketThickness,
                color: neonIndigo,
                corner: _Corner.bottomLeft,
              ),
            ),
            // Bottom-right
            Positioned(
              bottom: bracketInset,
              right: bracketInset,
              child: _CornerBracket(
                length: bracketLength,
                thickness: bracketThickness,
                color: neonIndigo,
                corner: _Corner.bottomRight,
              ),
            ),

            // ── Layer 2: Animated scan-line ──
            AnimatedBuilder(
              animation: _scanLineAnimation,
              builder: (context, child) {
                return Positioned(
                  top: cardH * _scanLineAnimation.value,
                  left: cardW * 0.1,
                  right: cardW * 0.1,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          neonIndigo.withValues(alpha: 0.0),
                          neonIndigo,
                          neonIndigo,
                          neonIndigo.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.15, 0.85, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: neonIndigo.withValues(alpha: 0.55),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Corner bracket helper ─────────────────────────────────────────────

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerBracket extends StatelessWidget {
  const _CornerBracket({
    required this.length,
    required this.thickness,
    required this.color,
    required this.corner,
  });

  final double length;
  final double thickness;
  final Color color;
  final _Corner corner;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: length,
      height: length,
      child: CustomPaint(
        painter: _CornerBracketPainter(
          thickness: thickness,
          color: color,
          corner: corner,
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({
    required this.thickness,
    required this.color,
    required this.corner,
  });

  final double thickness;
  final Color color;
  final _Corner corner;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    switch (corner) {
      case _Corner.topLeft:
        path.moveTo(0, size.height);
        path.lineTo(0, 0);
        path.lineTo(size.width, 0);
        break;
      case _Corner.topRight:
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width, size.height);
        break;
      case _Corner.bottomLeft:
        path.moveTo(0, 0);
        path.lineTo(0, size.height);
        path.lineTo(size.width, size.height);
        break;
      case _Corner.bottomRight:
        path.moveTo(size.width, 0);
        path.lineTo(size.width, size.height);
        path.lineTo(0, size.height);
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter old) =>
      old.color != color || old.thickness != thickness || old.corner != corner;
}
