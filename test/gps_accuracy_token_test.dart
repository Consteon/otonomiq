// Pins the GPS-accuracy system token to its slot number (slug: timeline-card,
// spec section 6).
//
// The number is NOT derived by reading code. The chain is three hops
// (getLocationString -> saveSendRows framing -> parseEventString ->
// resolveValueTokens); each hop looks right in isolation and this offset has
// been documented WRONG before. These tests drive the real functions end to end.
//
// Deliberately NOT modelled on test/add_to_event_test.dart or
// test/event_push_config_test.dart: both hand-construct `ref` and bypass
// parseEventString, so they prove nothing about WHICH slot is which.
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart'; // getLocationString
import 'package:otonomiq/firestore_repository/table_repository.dart'; // parseEventString, resolveValueTokens
import 'package:otonomiq/global.dart'; // separator, forbiddenCharacter, invalidLocation
import 'package:otonomiq/model/otq_state.dart';

/// The black system token ◀n▶ — forbiddenCharacter[7] / [9]. Never a pasted glyph.
String tok(int n) => '${forbiddenCharacter[7]}$n${forbiddenCharacter[9]}';

/// Exactly what saveSendRows composes into a history row[2]:
///   '0' (encryption type) + flag + locString + ⬤ + <★-joined form data>
List<dynamic> historyRow(String flag, String locString) => <dynamic>[
      1756600000000,
      'probePage',
      '0$flag$locString${separator[0]}p1${separator[3]}p2',
    ];

String resolve(String notation, List<dynamic> ref) => resolveValueTokens(
      notation,
      ref,
      tableVid: 20342033315492,
      appVid: 99999,
      timeReceived: 1756600000000,
      receivingPage: 'probePage',
    );

/// A sensor with a real fix.
OtqState fixed() => OtqState()
  ..nowTime = DateTime.fromMillisecondsSinceEpoch(1756600000000)
  ..latitude = -6.3211
  ..longitude = 106.6534
  ..accuracy = 8.37
  ..isoCountryCode = 'ID'
  ..locality = 'Kecamatan Cisauk'
  ..locationStatus = 'true-location';

void main() {
  group('getLocationString slot shape', () {
    test('emits 17 ◆ fields — the 16 legacy slots plus the accuracy slot', () {
      expect(
        getLocationString('', '', '', fixed()).split(separator[1]).length,
        17,
      );
    });

    test('index 16 is the accuracy, ROUNDED to whole metres', () {
      final List<String> parts =
          getLocationString('', '', '', fixed()).split(separator[1]);
      expect(parts[16], '8'); // 8.37 -> 8
    });

    test('no fix: index 16 is EMPTY, never "0"', () {
      // Catches: writing accuracy unconditionally. "0" is non-empty, so the
      // TIMELINE_CARD note line would render a fake "GPS ±0 m" instead of
      // vanishing (spec section 3 auto-hide).
      final List<String> parts =
          getLocationString('', '', '', OtqState()).split(separator[1]);
      expect(parts.length, 17);
      expect(parts[16], '');
    });

    test('appending shifted NO legacy slot', () {
      // Catches: inserting the new slot anywhere but the end, which would
      // silently repoint every deployed ◀N▶ config.
      final List<String> parts =
          getLocationString('QR-1', 'https://x/s.jpg', 'checkpoint', fixed())
              .split(separator[1]);
      expect(parts[1], '1756600000000');
      expect(parts[2], 'checkpoint');
      expect(parts[3], 'QR-1');
      expect(parts[4], '-6.3211');
      expect(parts[5], '106.6534');
      expect(parts[6], 'https://x/s.jpg');
      expect(parts[7], 'ID');
      expect(parts[15], 'true-location');
    });
  });

  group('◀N▶ resolution through the real history framing', () {
    test('◀17▶ IS the GPS accuracy — the number the sheet builder must use', () {
      final List<dynamic> ref = parseEventString(
        historyRow('attendance-check-in', getLocationString('', '', '', fixed())),
      );
      expect(resolve(tok(17), ref), '8');
    });

    test('the deployed live-config tokens still hit the same slots', () {
      // docs/firestore/update_table_row.md records a real attendance addToTable
      // bound to ◀2▶ (timestamp), ◀5▶ (lat), ◀6▶ (lng).
      final List<dynamic> ref = parseEventString(
        historyRow('attendance-check-in', getLocationString('', '', '', fixed())),
      );
      expect(resolve(tok(2), ref), '1756600000000');
      expect(resolve(tok(5), ref), '-6.3211');
      expect(resolve(tok(6), ref), '106.6534');
      expect(resolve(tok(16), ref), 'true-location');
    });

    test('◀1▶ is the submit FLAG, not an empty slot', () {
      // getLocationString opens with a bare ◆ and saveSendRows prepends the
      // flag, so the flag occupies the leading element. Documenting this stops
      // the next reader from off-by-oneing the whole table.
      final List<dynamic> ref = parseEventString(
        historyRow('attendance-check-in', getLocationString('', '', '', fixed())),
      );
      expect(resolve(tok(1), ref), 'attendance-check-in');
    });

    test('no fix: ◀17▶ resolves to EMPTY so the config slot collapses', () {
      final List<dynamic> ref = parseEventString(
        historyRow('f', getLocationString('', '', '', OtqState())),
      );
      expect(resolve(tok(17), ref), '');
    });

    test('out of range stamps the error notation "*", never a real value', () {
      // Load-bearing: this is WHY every hand-rolled locString literal had to be
      // extended to 17 fields. A short one makes ◀17▶ write a literal "*" into
      // the doc, and the card renders "GPS ±* m".
      final List<dynamic> ref = parseEventString(
        historyRow('f', getLocationString('', '', '', fixed())),
      );
      expect(resolve(tok(18), ref), '*');
    });
  });
}
