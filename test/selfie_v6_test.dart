import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/photo_camera.dart';

// Vertika v6 selfie screen (`variant: "v6"` on the attendance block).
//
// The screen itself cannot be pumped -- PhotoCamera reaches for the camera
// plugin and this repo carries no mock packages -- so what is covered here is
// the one pure decision that breaks silently on a real device: where the face
// oval lands, and how big it is, on a screen that is not the 390x844 the mock
// was drawn on.

void main() {
  group('selfieOvalRect', () {
    test('the oval is 77 % of the screen width', () {
      // 390 dp phone: 0.77 * 390 = 300.3, the spec's "300 dp di 390".
      final Rect r = selfieOvalRect(
        box: const Size(390, 844),
        topInset: 47,
        bottomInset: 34,
      );
      expect(r.width, closeTo(300.3, 0.01));
      expect(r.left, closeTo(44.85, 0.01));
      expect(r.top, 47 + 56 + 32);
    });

    test('height is 1.27x the width -- face plus shoulders', () {
      for (final Size box in <Size>[
        Size(390, 844),
        Size(412, 915),
        Size(360, 780),
      ]) {
        final Rect r = selfieOvalRect(
          box: box,
          topInset: 24,
          bottomInset: 24,
        );
        expect(r.height / r.width, closeTo(1.27, 0.001), reason: '$box');
      }
    });

    test('a narrow phone is clamped up to 280 dp, not left at 77 %', () {
      // 0.77 * 320 = 246.4, under the floor the spec sets for the clamp.
      final Rect r = selfieOvalRect(
        box: const Size(320, 900),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.width, 280);
    });

    test('a wide screen is clamped down to 340 dp, not a portal', () {
      // 0.77 * 480 = 369.6.
      final Rect r = selfieOvalRect(
        box: const Size(480, 1000),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.width, 340);
    });

    test('a short screen collapses the gap before it shrinks the oval', () {
      final Rect r = selfieOvalRect(
        box: const Size(360, 640),
        topInset: 24,
        bottomInset: 0,
      );
      expect(r.top, 24 + 56, reason: 'gap goes first');
      expect(r.width, lessThan(280));
      expect(r.height / r.width, closeTo(1.27, 0.001), reason: 'ratio held');
    });

    test('an absurdly short screen stops at the 170 dp floor', () {
      final Rect r = selfieOvalRect(
        box: const Size(320, 480),
        topInset: 20,
        bottomInset: 0,
      );
      expect(r.width, closeTo(170, 0.01));
    });

    test('never returns an oval hanging off the left edge', () {
      // Narrower than the 170 dp floor: the oval is centred on whatever is
      // left rather than pulled negative.
      final Rect r = selfieOvalRect(
        box: const Size(100, 900),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.width, closeTo(170, 0.01));
    });

    test('the oval always sits below the bar, whatever the insets', () {
      for (final double top in <double>[0, 24, 47, 59]) {
        final Rect r = selfieOvalRect(
          box: const Size(390, 844),
          topInset: top,
          bottomInset: 34,
        );
        expect(r.top, greaterThanOrEqualTo(top + 56));
      }
    });

    test('the full two-line hint clears the sheet on real phone shapes', () {
      // 28 dp gap + a two-line hint is the 100 dp the geometry reserves; the
      // sheet owns the bottom 120 dp.
      const List<Size> boxes = <Size>[
        Size(390, 844),
        Size(360, 640),
        Size(412, 915),
        Size(320, 568),
        Size(360, 780),
      ];
      for (final Size box in boxes) {
        final Rect r = selfieOvalRect(
          box: box,
          topInset: 24,
          bottomInset: 16,
        );
        expect(r.bottom + 100, lessThanOrEqualTo(box.height - 120 - 16 + 0.001),
            reason: 'oval overruns its hint on $box');
      }
    });

    test('below the 170 dp floor the oval wins and the hint is what gives', () {
      // 20 + 56 + 100 + 120 of fixed furniture plus a 216 dp floor needs
      // 512 dp; a 480 dp screen cannot have all of it. The floor holds -- an
      // oval too small to frame a face and shoulders guides nothing -- so the
      // hint's second line is what gets squeezed. Its FIRST line, the one that
      // carries the instruction, still clears the sheet.
      final Rect r = selfieOvalRect(
        box: const Size(320, 480),
        topInset: 20,
        bottomInset: 0,
      );
      expect(r.width, closeTo(170, 0.01), reason: 'floor holds');
      expect(r.bottom + 28 + 21, lessThanOrEqualTo(480 - 120));
    });
  });
}
