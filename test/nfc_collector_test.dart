import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/nfc_reader.dart';

void main() {
  // ---- parseGroups ----
  group('parseGroups', () {
    test('parses single group with all 6 fields', () {
      final gs = parseGroups('in◼Diterima◼Scan Tabung◼Isi◼12◼24');
      expect(gs.length, 1);
      expect(gs[0].key, 'in');
      expect(gs[0].title, 'Diterima');
      expect(gs[0].labelScan, 'Scan Tabung');
      expect(gs[0].pillLabel, 'Isi');
      expect(gs[0].rawTarget, '12');
      expect(gs[0].position, 24);
    });

    test('parses dual groups joined by star', () {
      final gs = parseGroups(
          'out◼Isi keluar◼Scan isi◼Isi◼2◼24★in◼Kosong masuk◼Scan kosong◼Kosong◼2◼25');
      expect(gs.length, 2);
      expect(gs[0].key, 'out');
      expect(gs[0].position, 24);
      expect(gs[1].key, 'in');
      expect(gs[1].pillLabel, 'Kosong');
      expect(gs[1].position, 25);
    });

    test('empty target field yields empty rawTarget', () {
      final gs = parseGroups('in◼Tabung◼Scan◼Isi◼◼24');
      expect(gs.length, 1);
      expect(gs[0].rawTarget, '');
    });

    test('skips group with missing position (fewer than 6 segments)', () {
      final gs = parseGroups('in◼Tabung◼Scan◼Isi◼12');
      expect(gs.length, 0);
    });

    test('skips group with non-numeric position', () {
      final gs = parseGroups('in◼Tabung◼Scan◼Isi◼12◼abc');
      expect(gs.length, 0);
    });

    test('empty string returns empty list', () {
      expect(parseGroups(''), isEmpty);
      expect(parseGroups('  '), isEmpty);
    });

    test('short fields get defaults (length-guard)', () {
      // Only key + position (indices 0 and 5), middle fields defaulted
      final gs = parseGroups('x◼◼◼◼◼7');
      expect(gs.length, 1);
      expect(gs[0].key, 'x');
      expect(gs[0].title, '');
      expect(gs[0].labelScan, '');
      expect(gs[0].pillLabel, '');
      expect(gs[0].rawTarget, '');
      expect(gs[0].position, 7);
    });
  });

  // ---- resolveTarget ----
  group('resolveTarget', () {
    test('literal integer', () {
      expect(resolveTarget('12', {}), 12);
    });

    test('token resolves from screenTx', () {
      expect(resolveTarget('{doQty}', {'doQty': '8'}), 8);
    });

    test('token resolves numeric value stored as int', () {
      expect(resolveTarget('{doQty}', {'doQty': 15}), 15);
    });

    test('empty string returns null', () {
      expect(resolveTarget('', {}), isNull);
      expect(resolveTarget('  ', {}), isNull);
    });

    test('unresolved token returns null (not numeric)', () {
      expect(resolveTarget('{doQty}', {}), isNull);
    });

    test('non-numeric literal returns null', () {
      expect(resolveTarget('abc', {}), isNull);
    });

    test('token resolving to empty returns null', () {
      expect(resolveTarget('{doQty}', {'doQty': ''}), isNull);
    });
  });

  // ---- isDuplicate ----
  group('isDuplicate', () {
    test('finds id in first group', () {
      expect(isDuplicate('A-1', [['A-1', 'A-2'], ['B-1']]), isTrue);
    });

    test('finds id in second group', () {
      expect(isDuplicate('B-1', [['A-1'], ['B-1', 'B-2']]), isTrue);
    });

    test('returns false when not present', () {
      expect(isDuplicate('C-1', [['A-1'], ['B-1']]), isFalse);
    });

    test('handles empty groups', () {
      expect(isDuplicate('A-1', [[], []]), isFalse);
      expect(isDuplicate('A-1', []), isFalse);
    });
  });

  // ---- joinIds ----
  group('joinIds', () {
    test('joins with star separator', () {
      expect(joinIds(['A-1067', 'A-1051', 'A-1043']), 'A-1067★A-1051★A-1043');
    });

    test('single id has no separator', () {
      expect(joinIds(['A-1067']), 'A-1067');
    });

    test('empty list yields empty string', () {
      expect(joinIds([]), '');
    });
  });

  // ---- mismatchNote ----
  group('mismatchNote', () {
    test('returns text when count differs from target', () {
      expect(mismatchNote(3, 5, 'Selisih!'), 'Selisih!');
    });

    test('returns null when count equals target', () {
      expect(mismatchNote(5, 5, 'Selisih!'), isNull);
    });

    test('returns null when target is null', () {
      expect(mismatchNote(3, null, 'Selisih!'), isNull);
    });

    test('returns null when mismatchText is empty', () {
      expect(mismatchNote(3, 5, ''), isNull);
      expect(mismatchNote(3, 5, '  '), isNull);
    });
  });

  // ---- nfcSlot (existing, sanity) ----
  group('nfcSlot', () {
    test('returns value at index when present and non-empty', () {
      expect(nfcSlot(['a', 'b', 'c'], 1, 'x'), 'b');
    });

    test('returns fallback when index out of range', () {
      expect(nfcSlot(['a'], 3, 'x'), 'x');
    });

    test('returns fallback when value is empty', () {
      expect(nfcSlot(['a', '', 'c'], 1, 'x'), 'x');
    });
  });
}
