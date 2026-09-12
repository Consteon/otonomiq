import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/ftz_scanner_screen.dart';

// Vertika v6 QR camera screen (`variant: "v6"` on the attendance block).
//
// The screen itself cannot be pumped -- MobileScanner reaches for the camera
// plugin and this repo carries no mock packages -- so what is covered here is
// the two decisions that are pure and that break silently on a real device:
// what the bar says, and where the viewfinder lands on a screen that is not
// the 390x844 the mock was drawn on.

void main() {
  group('scannerBarTitle', () {
    test('composes block and method the way the mock does', () {
      expect(scannerBarTitle('Absen Masuk', 'QR', 'Scan QR'),
          'Absen Masuk · QR');
      expect(scannerBarTitle('Absen Pulang', 'QR + Selfie', 'Scan QR'),
          'Absen Pulang · QR + Selfie');
    });

    test('no block stamped falls back to the sheet title', () {
      // A `location` component outside a v6 block never gets `blockTitle`.
      expect(scannerBarTitle('', 'QR', 'Scan QR'), 'QR');
      expect(scannerBarTitle('', '', 'Scan QR'), 'Scan QR');
    });

    test('everything blank yields blank, never a stray separator', () {
      expect(scannerBarTitle('', '', ''), '');
      expect(scannerBarTitle('  ', '  ', '  '), '');
    });

    test('whitespace around the halves is trimmed, not carried into the dot',
        () {
      expect(scannerBarTitle(' Absen Masuk ', ' QR ', 'x'), 'Absen Masuk · QR');
    });
  });

  group('scannerFrameRect', () {
    test('the mock phone gets the mock geometry', () {
      // 390x844 with an iPhone notch: v6 draws the frame 240 dp wide at
      // left 75, top 120 below the status bar.
      final Rect r = scannerFrameRect(
        box: const Size(390, 844),
        topInset: 47,
        bottomInset: 34,
      );
      expect(r.width, 240);
      expect(r.height, 240);
      expect(r.left, 75);
      expect(r.top, 47 + 56 + 64);
    });

    test('a 360x640 phone still gets the full frame and gap', () {
      final Rect r = scannerFrameRect(
        box: const Size(360, 640),
        topInset: 24,
        bottomInset: 0,
      );
      expect(r.width, 240);
      expect(r.top, 24 + 56 + 64);
    });

    test('a short screen collapses the gap before it shrinks the frame', () {
      final Rect r = scannerFrameRect(
        box: const Size(320, 480),
        topInset: 20,
        bottomInset: 0,
      );
      expect(r.top, 20 + 56, reason: 'gap goes first');
      expect(r.width, lessThan(240));
      expect(r.width, greaterThanOrEqualTo(140));
    });

    test('an absurdly short screen stops shrinking at the 140 dp floor', () {
      final Rect r = scannerFrameRect(
        box: const Size(320, 400),
        topInset: 20,
        bottomInset: 0,
      );
      expect(r.width, 140);
    });

    test('a narrow screen keeps the 48 dp side margin', () {
      final Rect r = scannerFrameRect(
        box: const Size(240, 800),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.width, 144);
      expect(r.left, 48);
    });

    test('never returns a frame hanging off the left edge', () {
      // Narrower than twice the margin plus the floor: the frame is centred on
      // whatever is left rather than pulled negative.
      final Rect r = scannerFrameRect(
        box: const Size(100, 800),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.width, 140);
    });

    test('the frame always sits below the bar, whatever the insets', () {
      for (final double top in <double>[0, 24, 47, 59]) {
        final Rect r = scannerFrameRect(
          box: const Size(390, 844),
          topInset: top,
          bottomInset: 34,
        );
        expect(r.top, greaterThanOrEqualTo(top + 56));
      }
    });
  });
}
