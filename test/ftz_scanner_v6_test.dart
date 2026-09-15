import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:otonomiq/widget/ftz_scanner_screen.dart';

// Vertika v6 QR camera screen (`variant: "v6"` on the attendance block).
//
// The screen itself cannot be pumped -- MobileScanner reaches for the camera
// plugin and this repo carries no mock packages -- so what is covered here is
// the two decisions that are pure and that break silently on a real device:
// what the bar says, and where the viewfinder lands on a screen that is not
// the 390x844 the mock was drawn on. The dispose group drives mobile_scanner's
// real Dart side with its native side faked on the platform channels.

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

  // Field bug: the checker's "1. Scan QR ID Card" came up with "The
  // MobileScannerController is already running" (twice: code + detail). The
  // plugin keeps ONE camera session per app, and a scanner disposed while its
  // native start was still in flight left that session running with no owner.
  group('disposeScannerController', () {
    const MethodChannel method =
        MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
    const List<EventChannel> events = <EventChannel>[
      EventChannel('dev.steenbakker.mobile_scanner/scanner/event'),
      EventChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
    ];

    testWidgets('a scanner closed mid-start does not block the next one',
        (WidgetTester tester) async {
      final TestDefaultBinaryMessenger messenger =
          tester.binding.defaultBinaryMessenger;
      Completer<void>? slowStart;
      int nextTexture = 0;
      messenger.setMockMethodCallHandler(method, (MethodCall call) async {
        if (call.method == 'state') return 1; // authorized
        if (call.method != 'start') return null; // stop, updateScanWindow
        final Map<String, Object?> view = <String, Object?>{
          'textureId': ++nextTexture,
          'cameraDirection': 1,
          'numberOfCameras': 2,
          'currentTorchState': 0,
          'size': <String, Object?>{'width': 1920.0, 'height': 1080.0},
        };
        final Completer<void>? hold = slowStart;
        if (hold != null) await hold.future;
        return view;
      });
      for (final EventChannel c in events) {
        messenger.setMockStreamHandler(
            c, MockStreamHandler.inline(onListen: (_, _) {}));
      }
      addTearDown(() {
        messenger.setMockMethodCallHandler(method, null);
        for (final EventChannel c in events) {
          messenger.setMockStreamHandler(c, null);
        }
      });

      final MobileScannerController a =
          MobileScannerController(autoStart: false);
      final MobileScannerController b =
          MobileScannerController(autoStart: false);
      Widget scanners({required bool withA}) => Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: <Widget>[
              if (withA)
                SizedBox(
                    key: const ValueKey<String>('a'),
                    height: 100,
                    child: MobileScanner(controller: a)),
              SizedBox(
                  key: const ValueKey<String>('b'),
                  height: 100,
                  child: MobileScanner(controller: b)),
            ]),
          );

      // Mount both up front: MobileScanner force-stops the platform on every
      // mount in debug, which would wipe the leak before B could trip on it.
      await tester.pumpWidget(scanners(withA: true));
      await tester.pump();

      final Completer<void> landing = Completer<void>();
      slowStart = landing;
      final Future<void> aStarting = a.start();
      await tester.pump();
      expect(a.value.isStarting, isTrue);

      // A closes before its preview came up: the child MobileScanner unmounts
      // first, then the screen's State.dispose hands the controller back...
      await tester.pumpWidget(scanners(withA: false));
      disposeScannerController(a);

      // ...and only then does its native start land.
      slowStart = null;
      landing.complete();
      await aStarting;
      await tester.pump();

      await b.start();
      await tester.pump();
      expect(b.value.error?.errorDetails?.message, isNull);
      expect(b.value.isRunning, isTrue);

      await tester.pumpWidget(const SizedBox());
      await b.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
