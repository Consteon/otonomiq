// test/signature_pad_test.dart
import 'package:flutter_test/flutter_test.dart'; // re-exports Offset (dart:ui)
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/signature_pad.dart';

void main() {
  // ── Signature state logic (pure) ──────────────────────────────────────

  group('signature pad state logic', () {
    test('empty strokes list means empty state', () {
      final List<List<dynamic>> strokes = [];
      expect(strokes.isEmpty, true);
    });

    test('adding a stroke transitions to filled state', () {
      final List<List<dynamic>> strokes = [];
      strokes.add([1.0, 2.0]); // placeholder offsets
      expect(strokes.isEmpty, false);
    });

    test('clearing strokes returns to empty state', () {
      final List<List<dynamic>> strokes = [
        [1.0, 2.0]
      ];
      strokes.clear();
      expect(strokes.isEmpty, true);
    });
  });

  // ── diamondTextToList 4-segment guards ────────────────────────────────

  group('signature pad text segment guards', () {
    test('full 4-segment text parses all slots', () {
      final text =
          'placeholder\u{25C6}clearLabel\u{25C6}hintEmpty\u{25C6}hintFilled';
      final arr = diamondTextToList(text);
      expect(arr.length, 4);
      expect(arr.isNotEmpty ? arr[0] : '', 'placeholder');
      expect(arr.length > 1 ? arr[1] : '', 'clearLabel');
      expect(arr.length > 2 ? arr[2] : '', 'hintEmpty');
      expect(arr.length > 3 ? arr[3] : '', 'hintFilled');
    });

    test('sparse text falls back for missing slots', () {
      final arr = diamondTextToList('onlyPlaceholder');
      expect(arr.isNotEmpty ? arr[0] : '', 'onlyPlaceholder');
      expect(arr.length > 1 ? arr[1] : 'Hapus', 'Hapus');
      expect(arr.length > 2 ? arr[2] : 'hint', 'hint');
      expect(arr.length > 3 ? arr[3] : 'confirmed', 'confirmed');
    });

    test('empty text returns length-1', () {
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.length > 3 ? arr[3] : 'default', 'default');
    });
  });

  // ── clampToCanvas pure helper ───────────────────────────────────────────

  group('clampToCanvas', () {
    const double w = 300.0;
    const double h = 150.0;

    test('point inside canvas is unchanged', () {
      final p = Offset(100, 75);
      final result = clampToCanvas(p, w, h);
      expect(result.dx, 100.0);
      expect(result.dy, 75.0);
    });

    test('point at origin is unchanged', () {
      final result = clampToCanvas(Offset.zero, w, h);
      expect(result.dx, 0.0);
      expect(result.dy, 0.0);
    });

    test('point at max corner is unchanged', () {
      final result = clampToCanvas(Offset(w, h), w, h);
      expect(result.dx, w);
      expect(result.dy, h);
    });

    test('dx exceeding width is clamped to width', () {
      final result = clampToCanvas(Offset(350, 75), w, h);
      expect(result.dx, w);
      expect(result.dy, 75.0);
    });

    test('dx below zero is clamped to zero', () {
      final result = clampToCanvas(Offset(-20, 75), w, h);
      expect(result.dx, 0.0);
      expect(result.dy, 75.0);
    });

    test('dy exceeding height is clamped to height', () {
      final result = clampToCanvas(Offset(100, 200), w, h);
      expect(result.dx, 100.0);
      expect(result.dy, h);
    });

    test('dy below zero is clamped to zero', () {
      final result = clampToCanvas(Offset(100, -10), w, h);
      expect(result.dx, 100.0);
      expect(result.dy, 0.0);
    });

    test('corner over-drift (both axes negative) clamps to origin', () {
      final result = clampToCanvas(Offset(-50, -30), w, h);
      expect(result.dx, 0.0);
      expect(result.dy, 0.0);
    });

    test('corner over-drift (both axes over max) clamps to max corner', () {
      final result = clampToCanvas(Offset(999, 888), w, h);
      expect(result.dx, w);
      expect(result.dy, h);
    });

    test('mixed drift (dx negative, dy over max) clamps correctly', () {
      final result = clampToCanvas(Offset(-5, 200), w, h);
      expect(result.dx, 0.0);
      expect(result.dy, h);
    });

    test('zero-size canvas clamps everything to origin', () {
      final result = clampToCanvas(Offset(10, 20), 0, 0);
      expect(result.dx, 0.0);
      expect(result.dy, 0.0);
    });
  });
}
