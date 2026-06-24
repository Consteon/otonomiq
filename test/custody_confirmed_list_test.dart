// test/custody_confirmed_list_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── ip[] -> display rows ──────────────────────────────────────────────

  group('buildConfirmedRows', () {
    /// Pure-logic: transform ip[] entries into display rows by JOINing item
    /// detail map. Each row has: name, category, qty, itemId.
    List<Map<String, dynamic>> buildConfirmedRows(
      List<Map<String, dynamic>> ipEntries,
      Map<String, ItemDetail> itemDetailMap,
    ) {
      final List<Map<String, dynamic>> rows = [];
      for (final entry in ipEntries) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        if (ii.isEmpty) continue;
        final ItemDetail? detail = itemDetailMap[ii];
        rows.add({
          'itemId': ii,
          'category': detail?.category ?? cd,
          'name': detail?.name ?? ii,
          'qty': qt,
        });
      }
      return rows;
    }

    test('joins item names from detail map', () {
      final ip = [
        {'ii': 'galon', 'cd': 'returnable', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'returnable', 'qt': 17},
      ];
      final details = {
        'galon': const ItemDetail(name: 'Galon 19L', category: 'returnable'),
        'lpg12': const ItemDetail(name: 'LPG 12kg', category: 'returnable'),
      };
      final rows = buildConfirmedRows(ip, details);
      expect(rows.length, 2);
      expect(rows[0]['name'], 'Galon 19L');
      expect(rows[0]['qty'], 25);
      expect(rows[1]['name'], 'LPG 12kg');
      expect(rows[1]['qty'], 17);
    });

    test('falls back to ii when detail map has no entry', () {
      final ip = [
        {'ii': 'unknown', 'cd': 'misc', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows[0]['name'], 'unknown');
      expect(rows[0]['category'], 'misc');
    });

    test('skips entries with empty ii', () {
      final ip = [
        {'ii': '', 'cd': 'returnable', 'qt': 10},
        {'ii': 'galon', 'cd': 'returnable', 'qt': 25},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows.length, 1);
      expect(rows[0]['itemId'], 'galon');
    });

    test('empty ip[] -> empty rows', () {
      expect(buildConfirmedRows([], {}), isEmpty);
    });

    test('qt parses from string', () {
      final ip = [
        {'ii': 'galon', 'cd': 'r', 'qt': '25'},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows[0]['qty'], 25);
    });

    test('non-numeric qt defaults to 0', () {
      final ip = [
        {'ii': 'galon', 'cd': 'r', 'qt': 'abc'},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows[0]['qty'], 0);
    });
  });
}
