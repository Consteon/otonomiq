import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:otonomiq/api.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/model/otq_state.dart';

// Tests for getLocationString (api.dart:786) and OtqState.getDataFrom
// (model/otq_state.dart) as exercised by the qr-selfie write path.
//
// Slot numbering follows the code comments (//N = Nth diamond boundary):
//   split[0] = ''          (before leading diamond)
//   split[1] = timestamp   (//2)
//   split[2] = position3   (//3)  ← fromLinkOption
//   split[3] = locId       (//4)  ← QR-scanned text
//   split[4] = latitude    (//5)
//   split[5] = longitude   (//6)
//   split[6] = imageUrl    (//7)  ← Firebase Storage selfie URL
//   split[7..15] = address fields + locationStatus

void main() {
  final diamond = separator[1]; // ◆ (U+25C6) — never paste raw glyph

  // ── helper: OtqState with deterministic field values (no platform calls) ──
  OtqState mkSensor({DateTime? nowTime}) {
    final s = OtqState();
    s.nowTime = nowTime ?? DateTime.fromMillisecondsSinceEpoch(1700000000000);
    s.latitude = -6.1234;
    s.longitude = 106.5678;
    s.isoCountryCode = 'ID';
    s.postalCode = '40000';
    s.administrativeArea = 'Jawa Barat';
    s.subAdministrativeArea = 'Kota Bandung';
    s.locality = 'Cicendo';
    s.subLocality = 'Husein Sastranegara';
    s.thoroughfare = 'Jl Istana Raya';
    s.subThoroughfare = 'E12';
    s.locationStatus = 'true-location';
    return s;
  }

  // ── getLocationString slot composition ────────────────────────────────────
  group('getLocationString — qr-selfie write shape', () {
    test('output has exactly 16 diamond-separated segments', () {
      final parts = getLocationString(
              'LOC-QR-01', 'https://storage.googleapis.com/b/s.jpg', 'checkpoint', mkSensor())
          .split(diamond);
      expect(parts.length, 16);
    });

    test('output starts with diamond separator', () {
      final result = getLocationString('QR', 'URL', 'checkpoint', mkSensor());
      expect(result.startsWith(diamond), isTrue);
    });

    test('locId (QR-scanned text) is at split[3] — slot 4', () {
      final parts = getLocationString(
              'SCANNED-QR-LOCATION-ID', 'URL', 'checkpoint', mkSensor())
          .split(diamond);
      expect(parts[3], 'SCANNED-QR-LOCATION-ID');
    });

    test('imageUrl (selfie Firebase Storage URL) is at split[6] — slot 7', () {
      const url = 'https://storage.googleapis.com/bucket/images/selfie.jpg';
      final parts =
          getLocationString('QR', url, 'checkpoint', mkSensor()).split(diamond);
      expect(parts[6], url);
    });

    test('position3 (fromLinkOption) is at split[2] — slot 3', () {
      // All five fromLinkOption values used by qr-selfie must land at split[2]
      for (final opt in [
        'checkpoint',
        'normal-clock-in',
        'normal-clock-out',
        'clock-out-overtime',
        'forgot-clock-out',
      ]) {
        final parts =
            getLocationString('QR', 'URL', opt, mkSensor()).split(diamond);
        expect(parts[2], opt,
            reason: 'fromLinkOption="$opt" must be at split[2]');
      }
    });

    test('split[1] timestamp matches OtqState.nowTime.millisecondsSinceEpoch', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      final parts =
          getLocationString('QR', 'URL', 'checkpoint', mkSensor(nowTime: t))
              .split(diamond);
      expect(parts[1], '1720000000000');
    });

    // ── Mandatory edge cases ───────────────────────────────────────────────

    test('empty locId → split[3] is empty, 16 parts maintained, imageUrl at split[6]', () {
      // Edge: QR text is empty (abnormal, but must not corrupt other slots)
      final parts = getLocationString(
              '', 'https://storage.googleapis.com/b/s.jpg', 'checkpoint', mkSensor())
          .split(diamond);
      expect(parts.length, 16);
      expect(parts[3], '');
      expect(parts[6], 'https://storage.googleapis.com/b/s.jpg');
    });

    test('empty imageUrl → split[6] is empty, 16 parts maintained, locId at split[3]', () {
      // Edge: upload failed and empty URL written (no write path should reach here,
      // but the slot structure must stay valid)
      final parts =
          getLocationString('SCANNED-QR-01', '', 'checkpoint', mkSensor())
              .split(diamond);
      expect(parts.length, 16);
      expect(parts[6], '');
      expect(parts[3], 'SCANNED-QR-01');
    });

    test('sparse OtqState (default invalidLocation values) → valid 16-part structure, no throw', () {
      // Sparse: GPS unavailable; OtqState fields stay at their default sentinels
      final sensor = OtqState(); // latitude/longitude = invalidLocation (888.888...)
      sensor.nowTime = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      expect(
        () {
          final parts =
              getLocationString('QR', 'URL', 'checkpoint', sensor).split(diamond);
          expect(parts.length, 16);
          expect(parts[3], 'QR');
          expect(parts[6], 'URL');
        },
        returnsNormally,
      );
    });

    test('address fields with quotes are cleaned by cleanupString — key slots unaffected', () {
      // cleanupString removes double-quotes, replaces single-quote with /
      // Verify this does not shift any slot positions
      final sensor = mkSensor();
      sensor.administrativeArea = 'Jawa "Barat"'; // double-quote stripped
      sensor.subLocality = "O'ck";                // single-quote → /
      final parts =
          getLocationString('QR', 'URL', 'checkpoint', sensor).split(diamond);
      expect(parts.length, 16);
      expect(parts[9], 'Jawa Barat'); // administrativeArea cleaned
      expect(parts[12], 'O/ck');      // subLocality cleaned
      // Critical slots unchanged in the normal case (nothing hostile to strip)
      expect(parts[3], 'QR');
      expect(parts[6], 'URL');
    });

    // ── JSON / record-framing safety invariant ────────────────────────────
    // A `"` arriving from the OS geocoder used to reach the sheet backend
    // verbatim and break its JSON composition, losing the attendance record.
    // No slot may carry a quote, a backslash, a control char, or any framing
    // separator — whatever the geocoder or the scanned QR hands us.
    test('hostile geocoder text is neutralised in every slot; 16 slots survive',
        () {
      const hostile = 'Jl "A" \\ B';
      final sensor = mkSensor();
      sensor.isoCountryCode = 'I"D'; // was written RAW before the fix
      sensor.postalCode = '401"74'; // was written RAW before the fix
      sensor.administrativeArea = hostile;
      sensor.subAdministrativeArea = 'Kota\nBandung'; // real newline
      sensor.locality = 'Cicendo\t01'; // control char
      sensor.subLocality = 'Husein${separator[1]}Sastranegara'; // ◆ framing
      sensor.thoroughfare = 'Jl${separator[0]}Istana'; // ⬤ framing
      sensor.subThoroughfare = 'E${separator[3]}12'; // ★ framing
      sensor.locationStatus = 'true"location';

      final parts = getLocationString(
              'QR"01', 'https://x/s.jpg', 'check"point', sensor)
          .split(diamond);

      expect(parts.length, 16, reason: 'framing must not shift');
      for (var i = 0; i < parts.length; i++) {
        expect(parts[i], isNot(contains('"')), reason: 'slot $i has a quote');
        expect(parts[i], isNot(contains('\\')),
            reason: 'slot $i has a backslash');
        expect(parts[i], isNot(matches(RegExp(r'[\x00-\x1F\x7F]'))),
            reason: 'slot $i has a control char');
        for (final c in forbiddenCharacter) {
          expect(parts[i], isNot(contains(c)),
              reason: 'slot $i has framing char U+${c.codeUnitAt(0).toRadixString(16)}');
        }
      }
      // Spot-check the two slots that had no sanitiser at all before the fix
      expect(parts[7], 'ID'); // isoCountryCode
      expect(parts[8], '40174'); // postalCode
    });
  });

  // ── OtqState.getDataFrom feasibility (Position/Placemark constructible) ──
  group('OtqState.getDataFrom — pure path, no platform channels needed', () {
    test('reads latitude/longitude/isMocked from Position', () {
      final pos = Position(
        longitude: 106.5678,
        latitude: -6.1234,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        accuracy: 10.0,
        altitude: 50.0,
        altitudeAccuracy: 5.0,
        heading: 90.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 0.5,
        isMocked: false,
      );
      final sensor = OtqState().getDataFrom(
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
        pos,
        [],
      );
      expect(sensor.latitude, -6.1234);
      expect(sensor.longitude, 106.5678);
      expect(sensor.locationStatus, 'true-location'); // isMocked=false
      expect(sensor.gpsOn, isTrue);
    });

    test('reads address fields from Placemark', () {
      final pos = Position(
        longitude: 106.5678,
        latitude: -6.1234,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      const place = Placemark(
        isoCountryCode: 'ID',
        postalCode: '40000',
        administrativeArea: 'Jawa Barat',
        subAdministrativeArea: 'Kota Bandung',
        locality: 'Cicendo',
        subLocality: 'Husein',
        thoroughfare: 'Jl Istana',
        subThoroughfare: 'E12',
      );
      final sensor = OtqState().getDataFrom(
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
        pos,
        [place],
      );
      expect(sensor.isoCountryCode, 'ID');
      expect(sensor.postalCode, '40000');
      expect(sensor.administrativeArea, 'Jawa Barat');
      expect(sensor.gpsDone, isTrue);
    });

    test('null Position → sensor keeps invalidLocation defaults, gpsOn stays false', () {
      final sensor = OtqState().getDataFrom(
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
        null,
        [],
      );
      expect(sensor.latitude, invalidLocation); // 888.8888888
      expect(sensor.gpsOn, isFalse);
      expect(sensor.gpsDone, isTrue);
    });
  });
}
