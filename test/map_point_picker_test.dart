import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/map_point_picker.dart';

void main() {
  // ── formatLatLng ───────────────────────────────────────────────────

  group('formatLatLng (anti-corruption: dot-decimal, 6dp)', () {
    test('standard negative/positive pair', () {
      expect(formatLatLng(-6.302154, 106.653428), '-6.302154,106.653428');
    });

    test('rounds to 6 decimal places', () {
      expect(formatLatLng(-6.3021541234, 106.6534289999),
          '-6.302154,106.653429');
    });

    test('zero coordinates', () {
      expect(formatLatLng(0, 0), '0.000000,0.000000');
    });

    test('always uses dot, never comma-decimal (locale-independent)', () {
      final result = formatLatLng(-6.302154, 106.653428);
      // Exactly two parts separated by comma
      final parts = result.split(',');
      expect(parts.length, 2);
      // Each part uses dot as decimal separator
      expect(parts[0], contains('.'));
      expect(parts[1], contains('.'));
      // No space around comma
      expect(result, isNot(contains(', ')));
      expect(result, isNot(contains(' ,')));
    });

    test('extreme values', () {
      expect(formatLatLng(-90, -180), '-90.000000,-180.000000');
      expect(formatLatLng(90, 180), '90.000000,180.000000');
    });
  });

  // ── parseOptionalPosition ──────────────────────────────────────────

  group('parseOptionalPosition', () {
    test('null -> null', () {
      expect(parseOptionalPosition(null), isNull);
    });

    test('empty string -> null', () {
      expect(parseOptionalPosition(''), isNull);
    });

    test('whitespace-only string -> null', () {
      expect(parseOptionalPosition('  '), isNull);
    });

    test('valid int string -> int', () {
      expect(parseOptionalPosition('14'), 14);
    });

    test('int value passthrough -> int', () {
      expect(parseOptionalPosition(15), 15);
    });

    test('zero -> null (positions are 1-based)', () {
      expect(parseOptionalPosition('0'), isNull);
    });

    test('negative -> null', () {
      expect(parseOptionalPosition('-1'), isNull);
    });

    test('non-numeric string -> null', () {
      expect(parseOptionalPosition('abc'), isNull);
    });

    test('float string -> null (int.tryParse rejects)', () {
      expect(parseOptionalPosition('14.5'), isNull);
    });
  });

  // ── mapPickerSlot ──────────────────────────────────────────────────

  group('mapPickerSlot (length-guarded text segments)', () {
    test('full text: all 9 segments accessible', () {
      final input = 'Belum ada'
          '${separator[1]}Lokasi Saya'
          '${separator[1]}Cari di Peta'
          '${separator[1]}Ganti'
          '${separator[1]}Cari alamat...'
          '${separator[1]}Pakai'
          '${separator[1]}Mencari...'
          '${separator[1]}GPS gagal'
          '${separator[1]}Jaringan error';
      final slots = diamondTextToList(input);
      expect(slots.length, 9);
      expect(mapPickerSlot(slots, 0, 'def'), 'Belum ada');
      expect(mapPickerSlot(slots, 1, 'def'), 'Lokasi Saya');
      expect(mapPickerSlot(slots, 4, 'def'), 'Cari alamat...');
      expect(mapPickerSlot(slots, 8, 'def'), 'Jaringan error');
    });

    test('sparse text (only 2 segments): out-of-range -> fallback', () {
      final input = 'Placeholder${separator[1]}GPS btn';
      final slots = diamondTextToList(input);
      expect(slots.length, 2);
      expect(mapPickerSlot(slots, 0, 'def'), 'Placeholder');
      expect(mapPickerSlot(slots, 1, 'def'), 'GPS btn');
      expect(mapPickerSlot(slots, 2, 'fallback'), 'fallback');
      expect(mapPickerSlot(slots, 8, 'fallback'), 'fallback');
    });

    test('empty text: diamondTextToList("") returns [""] -> all fallbacks',
        () {
      // diamondTextToList('') returns [''] (one empty element) because
      // global empty sentinel is '--' not ''.
      final slots = diamondTextToList('');
      expect(slots.length, 1);
      expect(slots[0], isEmpty);
      expect(mapPickerSlot(slots, 0, 'placeholder'), 'placeholder');
      expect(mapPickerSlot(slots, 1, 'fallback'), 'fallback');
    });

    test('segment present but empty -> fallback', () {
      // Simulate "FirstSeg◆◆ThirdSeg" -- middle is empty
      final input = 'First${separator[1]}${separator[1]}Third';
      final slots = diamondTextToList(input);
      expect(mapPickerSlot(slots, 0, 'def'), 'First');
      expect(mapPickerSlot(slots, 1, 'def'), 'def'); // empty -> fallback
      expect(mapPickerSlot(slots, 2, 'def'), 'Third');
    });
  });

  // ── parseLatLng ────────────────────────────────────────────────────

  group('parseLatLng', () {
    test('valid "lat,long" -> LatLng', () {
      final result = parseLatLng('-6.302154,106.653428');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.302154, 0.000001));
      expect(result.longitude, closeTo(106.653428, 0.000001));
    });

    test('with whitespace -> still parses', () {
      final result = parseLatLng(' -6.302154 , 106.653428 ');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.302154, 0.000001));
    });

    test('null -> null', () {
      expect(parseLatLng(null), isNull);
    });

    test('empty string -> null', () {
      expect(parseLatLng(''), isNull);
    });

    test('single number (no comma) -> null', () {
      expect(parseLatLng('123.456'), isNull);
    });

    test('lat out of range (>90) -> null', () {
      expect(parseLatLng('91.0,0.0'), isNull);
    });

    test('lng out of range (>180) -> null', () {
      expect(parseLatLng('0.0,181.0'), isNull);
    });

    test('non-numeric -> null', () {
      expect(parseLatLng('abc,def'), isNull);
    });

    test('round-trip: formatLatLng -> parseLatLng', () {
      final formatted = formatLatLng(-6.302154, 106.653428);
      final parsed = parseLatLng(formatted);
      expect(parsed, isNotNull);
      expect(parsed!.latitude, closeTo(-6.302154, 0.000001));
      expect(parsed.longitude, closeTo(106.653428, 0.000001));
    });
  });
}
