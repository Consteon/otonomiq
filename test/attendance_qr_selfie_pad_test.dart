import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/attendance_qr_selfie_gps_verify.dart';

void main() {
  group('padTextArray', () {
    test('empty list pads to 31 with index 26 = Scan QR', () {
      // diamondTextToList('') returns [''] (length 1)
      final result = AttendQrGpsSelfieState.padTextArray(['']);
      expect(result.length, 31);
      expect(result[0], '');
      expect(result[26], 'Scan QR');
      for (int i = 1; i < 26; i++) {
        expect(result[i], '', reason: 'index $i should be empty');
      }
      for (int i = 27; i < 31; i++) {
        expect(result[i], '', reason: 'index $i should be empty');
      }
    });

    test('short list (10 elements) pads to 31', () {
      final input = List.generate(10, (i) => 'text$i');
      final result = AttendQrGpsSelfieState.padTextArray(input);
      expect(result.length, 31);
      for (int i = 0; i < 10; i++) {
        expect(result[i], 'text$i');
      }
      expect(result[26], 'Scan QR');
      for (int i = 10; i < 26; i++) {
        expect(result[i], '');
      }
      for (int i = 27; i < 31; i++) {
        expect(result[i], '');
      }
    });

    test('existing 27-element list pads to 31', () {
      final input = List.generate(27, (i) => 'seg$i');
      final result = AttendQrGpsSelfieState.padTextArray(input);
      expect(result.length, 31);
      // Original 27 elements preserved
      for (int i = 0; i < 27; i++) {
        expect(result[i], 'seg$i');
      }
      // New slots 27-30 are empty
      for (int i = 27; i < 31; i++) {
        expect(result[i], '');
      }
    });

    test('full 31-element list unchanged', () {
      final input = List.generate(31, (i) => 'v$i');
      final result = AttendQrGpsSelfieState.padTextArray(input);
      expect(result.length, 31);
      for (int i = 0; i < 31; i++) {
        expect(result[i], 'v$i');
      }
    });

    test('list longer than 31 is not truncated', () {
      final input = List.generate(35, (i) => 'x$i');
      final result = AttendQrGpsSelfieState.padTextArray(input);
      expect(result.length, 35);
      for (int i = 0; i < 35; i++) {
        expect(result[i], 'x$i');
      }
    });

    test('does not mutate the original list', () {
      final input = ['a', 'b', 'c'];
      final original = List.from(input);
      AttendQrGpsSelfieState.padTextArray(input);
      expect(input, original);
    });

    test('index 26 only defaults to Scan QR when slot was added by pad', () {
      // If input already has 27+ elements, index 26 keeps its original value
      final input = List.generate(27, (i) => i == 26 ? 'CustomQR' : 'x');
      final result = AttendQrGpsSelfieState.padTextArray(input);
      expect(result[26], 'CustomQR');
    });
  });

  // ── diamondTextToList + padTextArray pipeline ─────────────────────────────
  // These tests exercise the full ingestion path: server text field
  // → diamondTextToList → padTextArray → index reads.
  group('diamondTextToList + padTextArray pipeline', () {
    final diamond = separator[1]; // ◆ (U+25C6)
    String joinDiamond(List<String> segs) => segs.join(diamond);

    test('empty string → diamondTextToList gives [""] → padded index 26 = Scan QR', () {
      // diamondTextToList('') ≠ diamondTextToList('--'); '' returns [''] (len 1)
      final list = diamondTextToList('');
      expect(list, ['']);
      final padded = AttendQrGpsSelfieState.padTextArray(list);
      expect(padded.length, 31);
      expect(padded[26], 'Scan QR');
      for (int i = 27; i < 31; i++) {
        expect(padded[i], '', reason: 'index $i is empty; doQrSelfieFlow uses hardcoded fallback');
      }
    });

    test('double-dash sentinel → diamondTextToList gives [] → padded index 26 = Scan QR', () {
      // "--" is the global `empty` constant; diamondTextToList returns [] not ['--']
      final list = diamondTextToList('--');
      expect(list, isEmpty);
      final padded = AttendQrGpsSelfieState.padTextArray(list);
      expect(padded.length, 31);
      expect(padded[26], 'Scan QR');
      for (int i = 27; i < 31; i++) {
        expect(padded[i], '');
      }
    });

    test('old 26-segment sheet → indexes 26-30 padded: Scan QR + empty strings', () {
      // Sparse: tenant sheet predates qr-selfie — only 26 segments (0-25) present.
      // padTextArray must fill slot 26='Scan QR', 27-30='' so doQrSelfieFlow
      // falls back to hardcoded Indonesian strings.
      final segs = List.generate(26, (i) => 'seg$i');
      final list = diamondTextToList(joinDiamond(segs));
      expect(list.length, 26);
      final padded = AttendQrGpsSelfieState.padTextArray(list);
      expect(padded.length, 31);
      for (int i = 0; i < 26; i++) {
        expect(padded[i], 'seg$i', reason: 'original segment $i must be preserved');
      }
      expect(padded[26], 'Scan QR');
      for (int i = 27; i < 31; i++) {
        expect(padded[i], '', reason: 'index $i absent → qr-selfie fallback text applies');
      }
    });

    test('full 31-segment qr-selfie sheet → spec values at 27-30 survive unchanged', () {
      // Sheet owner appends 5 segments per the deploy spec (§2.1 index map)
      final segs = List.generate(26, (i) => 'text$i')
        ..add('Scan QR')         // 26 — QR scanner title
        ..add('QR Berhasil')     // 27 — success-QR dialog title
        ..add('QR valid. Lanjutkan foto wajah (selfie) untuk mencatat absensi') // 28 body
        ..add('Ambil Selfie')    // 29 — CTA button
        ..add('Check IN dg QR + Selfie berhasil'); // 30 — checkpoint success msg
      expect(segs.length, 31);
      final list = diamondTextToList(joinDiamond(segs));
      expect(list.length, 31);
      final padded = AttendQrGpsSelfieState.padTextArray(list);
      expect(padded[26], 'Scan QR');
      expect(padded[27], 'QR Berhasil');
      expect(padded[28], 'QR valid. Lanjutkan foto wajah (selfie) untuk mencatat absensi');
      expect(padded[29], 'Ambil Selfie');
      expect(padded[30], 'Check IN dg QR + Selfie berhasil');
    });

    test('single segment (no diamond, malformed) → 1-element list → padded with Scan QR at 26', () {
      // Malformed: server sends text field with no separators at all
      final list = diamondTextToList('onlyone');
      expect(list.length, 1);
      final padded = AttendQrGpsSelfieState.padTextArray(list);
      expect(padded.length, 31);
      expect(padded[0], 'onlyone');
      expect(padded[26], 'Scan QR');
      for (int i = 27; i < 31; i++) {
        expect(padded[i], '');
      }
    });
  });
}
