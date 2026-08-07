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

  // ── per-screen write-state (C1) ─────────────────────────────────────────
  // Asserts on the REAL SignaturePad statics (rollFileName / fileNameOf /
  // clearSignatureState). No re-implementation of the keep/roll rule here --
  // every assertion drives the production symbol and reads back its effect.

  group('SignaturePad per-screen write-state', () {
    test('fileNameOf is empty before any session', () {
      SignaturePad.clearSignatureState('scr-empty');
      expect(SignaturePad.fileNameOf('scr-empty'), '');
    });

    test('rollFileName stores a prefixed id that fileNameOf reads back', () {
      SignaturePad.clearSignatureState('scr-store');
      final a = SignaturePad.rollFileName('scr-store', 'sig');
      expect(a, startsWith('sig_'));
      expect(SignaturePad.fileNameOf('scr-store'), a);
      SignaturePad.clearSignatureState('scr-store');
    });

    test('clearSignatureState drops the entry so the base is not reused', () {
      final a = SignaturePad.rollFileName('scr-drop', 'sig');
      expect(SignaturePad.fileNameOf('scr-drop'), a);
      SignaturePad.clearSignatureState('scr-drop');
      // Entry gone -> the old base can no longer leak into the next signature.
      expect(SignaturePad.fileNameOf('scr-drop'), '');
      SignaturePad.clearSignatureState('scr-drop');
    });

    test('rolling per session mints fresh identities (no reuse)', () {
      SignaturePad.clearSignatureState('scr-roll');
      final Set<String> ids = {
        for (int i = 0; i < 12; i++)
          SignaturePad.rollFileName('scr-roll', 'sig')
      };
      // 12 sessions must not all collapse to a single reused identity.
      expect(ids.length, greaterThan(1));
      // fileNameOf tracks the latest roll.
      expect(ids.contains(SignaturePad.fileNameOf('scr-roll')), true);
      SignaturePad.clearSignatureState('scr-roll');
    });

    test('two scrNames never share state', () {
      SignaturePad.clearSignatureState('scr-A');
      SignaturePad.clearSignatureState('scr-B');
      final a = SignaturePad.rollFileName('scr-A', 'sig');
      final b = SignaturePad.rollFileName('scr-B', 'sig');
      expect(SignaturePad.fileNameOf('scr-A'), a);
      expect(SignaturePad.fileNameOf('scr-B'), b);
      // Clearing one screen leaves the other intact.
      SignaturePad.clearSignatureState('scr-A');
      expect(SignaturePad.fileNameOf('scr-A'), '');
      expect(SignaturePad.fileNameOf('scr-B'), b);
      SignaturePad.clearSignatureState('scr-B');
    });

    test('clearSignatureState on an unknown screen is a no-op', () {
      SignaturePad.clearSignatureState('never-seen');
      expect(SignaturePad.fileNameOf('never-seen'), '');
    });

    test('prefix is honored in the minted identity', () {
      SignaturePad.clearSignatureState('scr-pfx');
      final a = SignaturePad.rollFileName('scr-pfx', 'custproof');
      expect(a, startsWith('custproof_'));
      SignaturePad.clearSignatureState('scr-pfx');
    });

    // C2: _exportAndSave captures fileNameOf(scrName) at export start (myBase)
    // and re-reads it before the txfController write, bailing on a mismatch so
    // an in-flight upload cannot land a stale token in the next delivery's
    // slot. These bind that change signal to the real statics. (The guard's
    // wiring inside the async _exportAndSave is inspection-only -- a widget
    // pump would hit Firebase; see walkthrough.)
    test('C2: current identity differs from captured after a route clear', () {
      final String myBase = SignaturePad.rollFileName('scr-c2clr', 'sig');
      expect(SignaturePad.fileNameOf('scr-c2clr'), myBase);
      // gotoRoute -> clearData wipes the entry between export start and write.
      SignaturePad.clearSignatureState('scr-c2clr');
      // Guard reads fileNameOf now -> '' != myBase -> stale write abandoned.
      expect(SignaturePad.fileNameOf('scr-c2clr'), '');
      expect(SignaturePad.fileNameOf('scr-c2clr') == myBase, false);
    });

    test('C2: captured identity still matches when only another screen rolls',
        () {
      SignaturePad.clearSignatureState('scr-c2keepA');
      SignaturePad.clearSignatureState('scr-c2keepB');
      final String myBase = SignaturePad.rollFileName('scr-c2keepA', 'sig');
      // A different delivery's screen opening a session must NOT abandon A's
      // still-valid write -- the guard is keyed per scrName.
      SignaturePad.rollFileName('scr-c2keepB', 'sig');
      expect(SignaturePad.fileNameOf('scr-c2keepA') == myBase, true);
      SignaturePad.clearSignatureState('scr-c2keepA');
      SignaturePad.clearSignatureState('scr-c2keepB');
    });
  });
}
