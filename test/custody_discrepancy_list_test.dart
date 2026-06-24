// test/custody_discrepancy_list_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  group('buildDiscrepancyRows', () {
    /// Pure-logic: transform dp[] entries into display rows.
    /// Each dp entry: {ii, cd, ex (warehouse expected), ac (driver actual), dl (delta)}.
    List<Map<String, dynamic>> buildDiscrepancyRows(
      List<Map<String, dynamic>> dpEntries,
      Map<String, ItemDetail> itemDetailMap,
    ) {
      final List<Map<String, dynamic>> rows = [];
      for (final entry in dpEntries) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        if (ii.isEmpty) continue;
        final int ex =
            int.tryParse((entry['ex'] ?? '0').toString().trim()) ?? 0;
        final int ac =
            int.tryParse((entry['ac'] ?? '0').toString().trim()) ?? 0;
        final int dl =
            int.tryParse((entry['dl'] ?? '0').toString().trim()) ?? 0;
        final ItemDetail? detail = itemDetailMap[ii];
        final String chipLabel = dl < 0 ? 'Kurang' : 'Lebih';
        final String chipColor = dl < 0 ? 'amber' : 'violet';
        rows.add({
          'itemId': ii,
          'name': detail?.name ?? ii,
          'category': detail?.category ?? cd,
          'warehouse': ex,
          'actual': ac,
          'delta': dl,
          'chipLabel': chipLabel,
          'chipColor': chipColor,
        });
      }
      return rows;
    }

    test('negative delta -> Kurang amber', () {
      final dp = [
        {'ii': 'galon', 'cd': 'r', 'ex': 30, 'ac': 25, 'dl': -5},
      ];
      final details = {
        'galon': const ItemDetail(name: 'Galon 19L', category: 'returnable'),
      };
      final rows = buildDiscrepancyRows(dp, details);
      expect(rows.length, 1);
      expect(rows[0]['name'], 'Galon 19L');
      expect(rows[0]['warehouse'], 30);
      expect(rows[0]['actual'], 25);
      expect(rows[0]['delta'], -5);
      expect(rows[0]['chipLabel'], 'Kurang');
      expect(rows[0]['chipColor'], 'amber');
    });

    test('positive delta -> Lebih violet', () {
      final dp = [
        {'ii': 'lpg12', 'cd': 'r', 'ex': 15, 'ac': 18, 'dl': 3},
      ];
      final rows = buildDiscrepancyRows(dp, {});
      expect(rows[0]['chipLabel'], 'Lebih');
      expect(rows[0]['chipColor'], 'violet');
      expect(rows[0]['delta'], 3);
    });

    test('zero delta -> Lebih (edge case, should not appear in dp[])', () {
      // dp[] should only contain mismatched items, but guard anyway
      final dp = [
        {'ii': 'galon', 'cd': 'r', 'ex': 25, 'ac': 25, 'dl': 0},
      ];
      final rows = buildDiscrepancyRows(dp, {});
      // dl == 0 is technically not < 0, so chipLabel = 'Lebih'
      expect(rows[0]['chipLabel'], 'Lebih');
    });

    test('skips entries with empty ii', () {
      final dp = [
        {'ii': '', 'cd': 'r', 'ex': 30, 'ac': 25, 'dl': -5},
        {'ii': 'galon', 'cd': 'r', 'ex': 30, 'ac': 25, 'dl': -5},
      ];
      final rows = buildDiscrepancyRows(dp, {});
      expect(rows.length, 1);
    });

    test('empty dp[] -> empty rows', () {
      expect(buildDiscrepancyRows([], {}), isEmpty);
    });

    test('string numeric values parsed correctly', () {
      final dp = [
        {'ii': 'galon', 'cd': 'r', 'ex': '30', 'ac': '25', 'dl': '-5'},
      ];
      final rows = buildDiscrepancyRows(dp, {});
      expect(rows[0]['warehouse'], 30);
      expect(rows[0]['actual'], 25);
      expect(rows[0]['delta'], -5);
    });
  });
}
