import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/nfc_reader.dart';

void main() {
  group('pickCardValue', () {
    test('first non-empty NDEF text wins over UID', () {
      expect(pickCardValue(['ABC123'], '04a2b3'), 'ABC123');
    });

    test('skips empty/whitespace records to the next text', () {
      expect(pickCardValue(['', '  ', 'REAL'], '04a2b3'), 'REAL');
    });

    test('falls back to UID when no text records', () {
      expect(pickCardValue(const [], '04A2B3C4'), '04A2B3C4');
    });

    test('falls back to UID when all texts are blank', () {
      expect(pickCardValue(['', '   '], '04A2B3C4'), '04A2B3C4');
    });

    test('trims the chosen value', () {
      expect(pickCardValue(['  spaced  '], 'uid'), 'spaced');
      expect(pickCardValue(const [], '  0405  '), '0405');
    });
  });

  group('nfcSlot', () {
    final slots = ['title', '', 'button'];

    test('returns value when in range and non-empty', () {
      expect(nfcSlot(slots, 0, 'def'), 'title');
      expect(nfcSlot(slots, 2, 'def'), 'button');
    });

    test('returns fallback when index empty', () {
      expect(nfcSlot(slots, 1, 'def'), 'def');
    });

    test('returns fallback when index out of range', () {
      expect(nfcSlot(slots, 9, 'def'), 'def');
    });
  });
}
