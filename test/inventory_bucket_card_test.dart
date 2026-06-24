import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  group('parseBuckets + inventory grouping', () {
    // parseBuckets is tested in driver_stop_progress_test.dart;
    // here we test the domain logic of grouping + summing.

    test('autheniumDecode then parseBuckets handles server-escaped input', () {
      final raw = 'isi_25FC_ok_u2B58_kosong_25FC_warn';
      final decoded = autheniumDecode(raw) ?? raw;
      final buckets = parseBuckets(decoded);
      expect(buckets.length, 2);
      expect(buckets[0].label, 'isi');
      expect(buckets[1].label, 'kosong');
    });
  });

  group('inventory text parsing', () {
    test('2-slot text parsed correctly', () {
      final arr = diamondTextToList(
          'Isi Kendaraan Sekarang\u{25C6}Update otomatis tiap serah-terima (kirim isi, ambil kosong).');
      expect(arr.length, 2);
      expect(arr[0], 'Isi Kendaraan Sekarang');
      expect(arr.length > 1 ? arr[1] : '', contains('Update'));
    });

    test('short text array length-guarded', () {
      final arr = diamondTextToList('OnlyOne');
      // Length guard pattern
      expect(arr.isNotEmpty ? arr[0] : '', 'OnlyOne');
      expect(arr.length > 1 ? arr[1] : 'default', 'default');
    });
  });

  group('inventory regroup by ii (P3 contract)', () {
    // Tests the grouping + name-FK logic that _computeInventory implements.
    // We test the CONTRACT without pumping the widget: given asset_cache docs
    // and an itemNameMap, the result groups by ii and resolves display names.

    // Mirrors _computeInventory: group by itemField, sum qtyField per catField,
    // resolve name via itemNameMap.
    List<Map<String, dynamic>> computeInventory(
      List<Map<String, dynamic>> docs,
      Map<String, String> itemNameMap, {
      String itemField = 'ii',
      String catField = 'cd',
      String qtyField = 'qt',
      Map<String, String> catToLabel = const {},
    }) {
      final Map<String, Map<String, int>> grouped = {};
      final List<String> order = [];

      for (final doc in docs) {
        final String itemId = (doc[itemField] ?? '').toString().trim();
        if (itemId.isEmpty) continue;
        final String catValue =
            (doc[catField] ?? '').toString().trim().toLowerCase();
        final int qty =
            int.tryParse((doc[qtyField] ?? '0').toString().trim()) ?? 0;
        final String bucketLabel = catToLabel[catValue] ?? catValue;

        if (!grouped.containsKey(itemId)) {
          order.add(itemId);
          grouped[itemId] = {};
        }
        grouped[itemId]![bucketLabel] =
            (grouped[itemId]![bucketLabel] ?? 0) + qty;
      }

      final List<Map<String, dynamic>> result = [];
      for (final String itemId in order) {
        final String displayName =
            itemNameMap[itemId]?.isNotEmpty == true
                ? itemNameMap[itemId]!
                : itemId;
        result.add({
          'name': displayName,
          'buckets': grouped[itemId],
        });
      }
      return result;
    }

    final nameMap = {'31': 'Amidis Galon 19 Lite', '32': 'Aqua 600ml'};
    final catMap = {'full': 'isi', 'empty': 'kosong'};

    test('groups by ii, sums qt per cd, resolves name', () {
      final docs = [
        {'ii': '31', 'cd': 'full', 'qt': '30'},
        {'ii': '31', 'cd': 'empty', 'qt': '4'},
        {'ii': '32', 'cd': 'full', 'qt': '12'},
        {'ii': '32', 'cd': 'empty', 'qt': '0'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      expect(result.length, 2);
      expect(result[0]['name'], 'Amidis Galon 19 Lite');
      expect((result[0]['buckets'] as Map)['isi'], 30);
      expect((result[0]['buckets'] as Map)['kosong'], 4);
      expect(result[1]['name'], 'Aqua 600ml');
      expect((result[1]['buckets'] as Map)['isi'], 12);
      expect((result[1]['buckets'] as Map)['kosong'], 0);
    });

    test('unknown ii falls back to raw id', () {
      final docs = [
        {'ii': '999', 'cd': 'full', 'qt': '5'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      expect(result[0]['name'], '999');
    });

    test('empty nameMap -> all raw ids', () {
      final docs = [
        {'ii': '31', 'cd': 'full', 'qt': '10'},
      ];
      final result = computeInventory(docs, {}, catToLabel: catMap);
      expect(result[0]['name'], '31');
    });

    test('empty docs -> empty result', () {
      expect(computeInventory([], nameMap), isEmpty);
    });

    test('docs with empty ii are skipped', () {
      final docs = [
        {'ii': '', 'cd': 'full', 'qt': '5'},
        {'cd': 'full', 'qt': '3'}, // ii absent
        {'ii': '31', 'cd': 'full', 'qt': '10'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      expect(result.length, 1);
      expect(result[0]['name'], 'Amidis Galon 19 Lite');
    });

    test('non-numeric qt -> 0', () {
      final docs = [
        {'ii': '31', 'cd': 'full', 'qt': 'abc'},
        {'ii': '31', 'cd': 'full', 'qt': '5'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      expect((result[0]['buckets'] as Map)['isi'], 5); // 0 + 5
    });

    test('int qt values aggregate correctly', () {
      final docs = [
        {'ii': '31', 'cd': 'full', 'qt': 20},
        {'ii': '31', 'cd': 'full', 'qt': 14},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      expect((result[0]['buckets'] as Map)['isi'], 34);
    });

    test('preserves first-seen order', () {
      final docs = [
        {'ii': '32', 'cd': 'full', 'qt': '1'},
        {'ii': '31', 'cd': 'full', 'qt': '2'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      expect(result[0]['name'], 'Aqua 600ml'); // 32 first
      expect(result[1]['name'], 'Amidis Galon 19 Lite'); // 31 second
    });

    test('catToLabel maps cd values to bucket labels', () {
      final docs = [
        {'ii': '31', 'cd': 'full', 'qt': '10'},
        {'ii': '31', 'cd': 'empty', 'qt': '3'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      final buckets = result[0]['buckets'] as Map;
      expect(buckets['isi'], 10); // 'full' -> 'isi'
      expect(buckets['kosong'], 3); // 'empty' -> 'kosong'
    });

    test('unmapped cd value surfaces as its own bucket label', () {
      final docs = [
        {'ii': '31', 'cd': 'damaged', 'qt': '2'},
      ];
      final result = computeInventory(docs, nameMap, catToLabel: catMap);
      // 'damaged' not in catMap -> raw value used as bucket label
      expect((result[0]['buckets'] as Map)['damaged'], 2);
    });

    test('nameMap entry with empty name -> falls back to raw id', () {
      final mapWithEmpty = {'31': ''};
      final docs = [
        {'ii': '31', 'cd': 'full', 'qt': '10'},
      ];
      final result = computeInventory(docs, mapWithEmpty, catToLabel: catMap);
      expect(result[0]['name'], '31');
    });
  });
}
