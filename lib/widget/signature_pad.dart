import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../screen_session.dart';

/// Clamps [p] so that dx stays in [0, width] and dy stays in [0, height].
/// Pure helper -- no side effects; importable for unit testing.
Offset clampToCanvas(Offset p, double width, double height) {
  return Offset(p.dx.clamp(0.0, width), p.dy.clamp(0.0, height));
}

/// SIGNATURE_PAD -- hand-drawn stroke capture for P11 DeliveryWorkspace.
///
/// Uses CustomPaint + GestureDetector. NO pub package dependency.
///
/// States:
///   - Empty: dashed slate border (CustomPaint), light bg, centered placeholder.
///   - Filled: solid emerald border, "Hapus" clear control, confirmed hint.
///
/// On each pan-end, strokes are rendered to a JPEG via PictureRecorder,
/// saved locally via prepareImageAsLocal(forceRename: true), registered
/// in imageMap, and written to txfController[scrName][position] as an
/// aum__ token. The existing submit/historySync pipeline carries the
/// signature to Firebase Storage with zero additional code.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
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

  /// Per-screen signature write-state, keyed by scrName. Kept STATIC (not
  /// instance fields) and reset per route change by [clearSignatureState]
  /// (wired into clearData) -- the codebase's per-screen-state convention.
  /// This does not depend on State lifetime: a normal gotoRoute disposes this
  /// State, but an AnyPage in-place reconciliation (any_page.dart:115,
  /// buildPage(clear:false)) can reuse it via identical ObjectKeys -- clearData
  /// resets the state in both cases, so signature A's ink and file identity
  /// never leak onto B. The identity also rolls per session in _onPanStart.
  /// Mirrors CustodyCountList.countStore.
  static final Map<String, _SigWriteState> _writeState = {};

  /// Drop [scrName]'s signature write-state so a revisit starts clean.
  /// Registered in clearData (api.dart) beside the sibling driver widgets.
  static void registerScreenSession() {
    ScreenSession.ensure(
      'SignaturePad.writeState',
      SignaturePad.clearSignatureState,
      rebuild: RebuildPolicy.none,
    );
  }

  static void clearSignatureState(String scrName) {
    _writeState.remove(scrName);
  }

  /// Current file identity for [scrName] ('' when no signature session is
  /// active). The write path (_exportAndSave) and tests share this reader --
  /// no re-implementation of the roll rule.
  static String fileNameOf(String scrName) =>
      _writeState[scrName]?.fileNameBase ?? '';

  /// Mint and store a fresh file identity for [scrName]'s new signature
  /// session, returning it. Called only on the empty->non-empty stroke edge
  /// so it stays stable across the strokes of ONE signature but rolls per
  /// submitted signature -- signature B never reuses signature A's key.
  static String rollFileName(String scrName, String prefix) {
    final String base =
        '${prefix}_'
        '${const Uuid().v4().replaceAll('-', '').substring(2, 7)}';
    _writeState.putIfAbsent(scrName, () => _SigWriteState()).fileNameBase =
        base;
    return base;
  }

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

/// Mutable per-screen signature state held in [SignaturePad._writeState].
/// Kept off the State and reset by SignaturePad.clearSignatureState on route
/// change, so an AnyPage in-place State reuse (any_page.dart:115) cannot carry
/// one delivery's strokes/identity into the next.
class _SigWriteState {
  final List<List<Offset>> strokes = [];
  String fileNameBase = '';
  bool saving = false;
  bool pendingExport = false;
}

class _SignaturePadState extends State<SignaturePad> {
  // ── Driver palette tokens ───────────────────────────────────────────────
  static const Color _ink = Color(0xFF1E293B); // slate-800 (label + ink)
  static const Color _emptyBg = Color(0xFFF8FAFC); // slate-50 (empty canvas)
  static const Color _dash = Color(0xFFCBD5E1); // slate-300 (dashed border)
  static const Color _emerald = Color(
    0xFF10B981,
  ); // emerald-500 (filled accent)
  static const Color _muted = Color(0xFF9CA3AF); // gray-400 (empty hint)
  static const Color _caption = Color(0xFF94A3B8); // slate-400 (placeholder)

  static const double _canvasHeight = 150;

  // ── Write-path fields ──────────────────────────────────────────────────
  static const double _exportScale = 3.0;
  static const int _jpegQuality = 90;

  late final int? _position;
  late final String _folder;

  // Leak-prone state (strokes, file identity, export flags) lives in the
  // static SignaturePad._writeState keyed by scrName -- reset via clearData on
  // route change rather than relying on State lifetime (an AnyPage in-place
  // reconciliation can preserve this State; any_page.dart:115). Proxied here so
  // the render and write-path code reads the per-screen holder transparently.
  _SigWriteState get _state => SignaturePad._writeState.putIfAbsent(
    widget.scrName,
    () => _SigWriteState(),
  );
  List<List<Offset>> get _strokes => _state.strokes;
  String get _fileNameBase => SignaturePad.fileNameOf(widget.scrName);
  bool get _saving => _state.saving;
  set _saving(bool v) => _state.saving = v;
  bool get _pendingExport => _state.pendingExport;
  set _pendingExport(bool v) => _state.pendingExport = v;

  List<String> _textArray = [];
  List<Offset> _currentStroke = [];
  double _canvasWidth = 0;

  @override
  void initState() {
    super.initState();
    SignaturePad.registerScreenSession();
    _parseText();
    _position = int.tryParse((widget.component['position'] ?? '').toString());
    _folder = (widget.component['folder'] ?? 'signature').toString().trim();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (4 slots):
  ///  [0] placeholder  "✍️ Tap & tarik untuk tanda tangan customer"
  ///  [1] clearLabel   "Hapus"
  ///  [2] hintEmpty    "Opsional · jika customer berkenan tanda tangan"
  ///  [3] hintFilled   "✓ Tanda tangan tersimpan · customer confirmed"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  bool get _isEmpty => _strokes.isEmpty;

  /// Render strokes to JPEG, save locally, register in imageMap,
  /// write aum__ token to txfController.
  ///
  /// Guarded by [_saving] to serialise concurrent exports. If a pan-end
  /// fires while an export is in progress, [_pendingExport] ensures the
  /// latest strokes are re-exported when the current one finishes.
  Future<void> _exportAndSave() async {
    if (_position == null || _strokes.isEmpty) return;
    if (_saving) {
      _pendingExport = true;
      return;
    }
    _saving = true;
    // C2: pin this export to the signature session that started it. If a route
    // change (clearData) or a Hapus-then-redraw rolls the file identity while
    // the online upload below is still in flight, the captured token must NOT
    // land in the next delivery's txfController slot (proof-of-delivery loss).
    final String myBase = SignaturePad.fileNameOf(widget.scrName);
    try {
      final double w = _canvasWidth;
      final double h = _canvasHeight;
      if (w <= 0) return;

      // 1. Render strokes onto a fresh canvas with opaque white background.
      //    JPEG has no alpha channel; the white rect prevents black artifacts.
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.scale(_exportScale);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
      // Reuse the existing _SignaturePainter -- no new painting code.
      _SignaturePainter(
        strokes: _strokes,
        currentStroke: const [],
        inkColor: _ink,
      ).paint(canvas, Size(w, h));

      final int imgWidth = (w * _exportScale).round();
      final int imgHeight = (h * _exportScale).round();
      final ui.Image uiImage = await recorder.endRecording().toImage(
        imgWidth,
        imgHeight,
      );
      // I2: dispose the native handle even if toByteData throws.
      ByteData? rawBytes;
      try {
        rawBytes = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        uiImage.dispose();
      }
      if (rawBytes == null) return;

      // 2. Encode as JPEG via the image package (v4.9.1, already installed).
      final img_pkg.Image sigImage = img_pkg.Image.fromBytes(
        width: imgWidth,
        height: imgHeight,
        bytes: rawBytes.buffer,
        numChannels: 4,
        order: img_pkg.ChannelOrder.rgba,
      );
      final Uint8List jpegBytes = img_pkg.encodeJpg(
        sigImage,
        quality: _jpegQuality,
      );

      // 3. Write JPEG to a temp file in app support dir.
      final Directory appDir = await getApplicationSupportDirectory();
      final String tempPath = '${appDir.path}/sig_tmp_$_fileNameBase.jpg';
      await File(tempPath).writeAsBytes(jpegBytes, flush: true);

      // 4. Relocate via prepareImageAsLocal with forceRename: true.
      //    CRITICAL: without forceRename, renamePath's OTQC check fails
      //    (signature path has no OTQC artifact), the file is never moved,
      //    the path carries no ___ separator, and saveImagePutInImageMap's
      //    split('___') yields one element -- the upload targets a garbage
      //    folder and a later cache purge strands an aum__ entry, halting
      //    the entire history queue (image-poison wedge).
      //    See api.dart:5511-5518 (gallery path) for prior art.
      final String aumToken = await prepareImageAsLocal(
        imagePath: tempPath,
        folder: _folder,
        fileName: _fileNameBase,
        forceRename: true,
      );

      // 5. Register in imageMap and upload if online.
      // The eager upload here may no-op if a prior stroke already set the
      // imageMap URL (saveImagePutInImageMap skips a filled URL slot).
      // Harmless: at historySync, uploadImageToCloud
      // (table_repository.dart:3545-3599) does NOT short-circuit on an
      // existing URL -- when online it unconditionally re-uploads the CURRENT
      // local bytes (the finished signature) to the deterministic key
      // "$folder/$fileName.jpg", so intermediate strokes self-heal. Nothing
      // to defer. That same stable-key property is exactly what made C1
      // dangerous ACROSS signatures -- fixed by rolling _fileNameBase per
      // signature session (see _onPanStart / SignaturePad.rollFileName).
      await saveImagePutInImageMap(aumToken);

      // 6. Write to txfController (mirrors otq_get_images_2.dart:120-133).
      //    C2: bail if this State was disposed, no session was active at export
      //    start (empty myBase), or the identity rolled/cleared since -- the
      //    captured token no longer belongs to this scrName's current slot.
      if (!mounted ||
          myBase.isEmpty ||
          SignaturePad.fileNameOf(widget.scrName) != myBase) {
        return;
      }
      try {
        txfControllerCheck(widget.scrName, _position);
        txfController[widget.scrName]![_position]!.controller.text = aumToken;
        txfController[widget.scrName]![_position]!.finalData = aumToken;
      } catch (e) {
        errorReport(e);
      }
    } catch (e) {
      errorReport(e);
    } finally {
      _saving = false;
      if (_pendingExport) {
        _pendingExport = false;
        _exportAndSave();
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Empty -> non-empty edge = a new signature session begins. Roll a fresh
    // file identity now so this signature will not overwrite the previous one
    // at the same Storage key. No roll on later strokes -- the identity must
    // stay stable across the strokes of one signature (see I1).
    if (_strokes.isEmpty) {
      SignaturePad.rollFileName(
        widget.scrName,
        (widget.component['filename'] ?? 'sig').toString().trim(),
      );
    }
    _currentStroke = [
      clampToCanvas(details.localPosition, _canvasWidth, _canvasHeight),
    ];
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _currentStroke.add(
      clampToCanvas(details.localPosition, _canvasWidth, _canvasHeight),
    );
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.isNotEmpty) {
      _strokes.add(List<Offset>.from(_currentStroke));
    }
    _currentStroke = [];
    setState(() {});
    _exportAndSave();
  }

  void _onClear() {
    _strokes.clear();
    // End the session: next stroke rolls a fresh identity (see _onPanStart).
    _state.fileNameBase = '';
    _currentStroke = [];
    setState(() {});
    // Blank txfController so submit does not carry a stale signature.
    if (_position != null) {
      try {
        txfControllerCheck(widget.scrName, _position);
        txfController[widget.scrName]![_position]!.controller.text = '';
        txfController[widget.scrName]![_position]!.finalData = '';
      } catch (e) {
        errorReport(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOptional =
        (widget.component['optional'] ?? false).toString().toLowerCase() ==
        'true';

    final String placeholder = _t(
      0,
      '\u{270D}\u{FE0F} Tap & tarik untuk tanda tangan customer',
    );
    final String clearLabel = _t(1, 'Hapus');
    final String hintEmpty = _t(
      2,
      'Opsional \u{00B7} jika customer berkenan tanda tangan',
    );
    final String hintFilled = _t(
      3,
      '\u{2713} Tanda tangan tersimpan \u{00B7} customer confirmed',
    );

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
          // Label row: "Tanda Tangan Customer" + optional badge
          Row(
            children: [
              const Icon(Icons.draw_rounded, size: 16, color: _ink),
              const SizedBox(width: 6),
              const Text(
                'Tanda Tangan Customer',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              if (isOptional) ...[
                const SizedBox(width: 6),
                const Text(
                  '(opsional)',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Canvas area
          LayoutBuilder(
            builder: (context, constraints) {
              _canvasWidth = constraints.maxWidth;
              return GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: Container(
                  width: double.infinity,
                  height: _canvasHeight,
                  decoration: BoxDecoration(
                    color: _isEmpty ? _emptyBg : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: _isEmpty
                        ? null
                        : Border.all(color: _emerald, width: 2),
                  ),
                  // Dashed border for the empty state (CustomPaint, design pass).
                  foregroundDecoration: _isEmpty
                      ? _DashedBorderDecoration(
                          color: _dash,
                          radius: 14,
                          strokeWidth: 1.6,
                          dashLength: 6,
                          gapLength: 5,
                        )
                      : null,
                  child: Stack(
                    children: [
                      // Signature canvas -- clipped to the rounded box
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CustomPaint(
                          size: const Size(double.infinity, _canvasHeight),
                          painter: _SignaturePainter(
                            strokes: _strokes,
                            currentStroke: _currentStroke,
                            inkColor: _ink,
                          ),
                        ),
                      ),
                      // Placeholder (empty state)
                      if (_isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              placeholder,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _caption,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      // Clear button (filled state)
                      if (!_isEmpty)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _onClear,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2), // red-100
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: Color(0xFFDC2626), // red-600
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    clearLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFDC2626), // red-600
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),

          // Hint caption
          Text(
            _isEmpty ? hintEmpty : hintFilled,
            style: TextStyle(
              fontSize: 12,
              fontWeight: _isEmpty ? FontWeight.w400 : FontWeight.w600,
              color: _isEmpty ? _muted : _emerald,
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that draws smooth strokes.
class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color inkColor;

  _SignaturePainter({
    required this.strokes,
    required this.currentStroke,
    required this.inkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = inkColor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, paint);
    }
    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke, paint);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      return;
    }
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}

/// A rounded-rect DASHED border drawn as a foreground decoration. Flutter's
/// [Border] has no native dash support, so the empty-state signature canvas
/// uses this (design pass over the plan's solid fallback).
class _DashedBorderDecoration extends Decoration {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const _DashedBorderDecoration({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedBorderPainter(this);
}

class _DashedBorderPainter extends BoxPainter {
  final _DashedBorderDecoration deco;
  _DashedBorderPainter(this.deco);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final Size size = cfg.size ?? Size.zero;
    if (size.isEmpty) return;

    final Rect rect = offset & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect.deflate(deco.strokeWidth / 2),
      Radius.circular(deco.radius),
    );

    final Paint paint = Paint()
      ..color = deco.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = deco.strokeWidth
      ..strokeCap = StrokeCap.round;

    final Path src = Path()..addRRect(rrect);
    final Path dashed = Path();
    final double step = deco.dashLength + deco.gapLength;
    for (final metric in src.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final double end = (dist + deco.dashLength).clamp(0, metric.length);
        dashed.addPath(metric.extractPath(dist, end), Offset.zero);
        dist += step;
      }
    }
    canvas.drawPath(dashed, paint);
  }
}
