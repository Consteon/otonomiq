import 'package:flutter/material.dart';

import '../global.dart';

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
/// DEFERRED: strokes are LOCAL widget state only. No image-bytes export,
/// no txfController write this round. When writes land:
///   - position: 3 (from component['position'])
///   - writeField: "sig" (from component['writeField'])
///   - Export strokes as PNG bytes, write to txfController[scrName][3].
///
/// Read-only for Firestore: no txfController, no saveSend, no history.
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

  @override
  State<SignaturePad> createState() => _SignaturePadState();
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

  List<String> _textArray = [];
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  double _canvasWidth = 0;

  @override
  void initState() {
    super.initState();
    _parseText();
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

  void _onPanStart(DragStartDetails details) {
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
  }

  void _onClear() {
    _strokes.clear();
    _currentStroke = [];
    setState(() {});
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

    // DEFERRED: position and writeField for future write integration.
    // final int position = int.tryParse(
    //     (widget.component['position'] ?? '').toString()) ?? -1;
    // final String writeField =
    //     (widget.component['writeField'] ?? '').toString();

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
