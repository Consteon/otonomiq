import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/task_item_builder.dart';

void main() {
  // ── Product picker filter (mirrors _ProductPickerSheetState.build) ──────
  //
  // The filter in the sheet does:
  //   if (query.isEmpty) return true;
  //   final val = (doc[searchField] ?? '').toString().trim().toLowerCase();
  //   return val.contains(query.toLowerCase());
  //
  // searchField controls WHICH item field the query matches against.
  // When searchField == nameField, behavior is identical to the pre-change code.

  List<Map<String, dynamic>> filterPickerItems(
    List<Map<String, dynamic>> items,
    String query,
    String searchField,
  ) {
    if (query.isEmpty) return items;
    final String q = query.toLowerCase();
    return items.where((doc) {
      final String val =
          (doc[searchField] ?? '').toString().trim().toLowerCase();
      return val.contains(q);
    }).toList();
  }

  group('Product picker filter (searchField)', () {
    final List<Map<String, dynamic>> items = [
      {'in': 'Galon 19L RO', 'code': 'G19', 'ic': 'returnable'},
      {'in': 'Galon 12L', 'code': 'G12', 'ic': 'returnable'},
      {'in': 'Botol 600ml', 'code': 'B06', 'ic': 'consumable'},
    ];

    test('empty query returns all items', () {
      expect(filterPickerItems(items, '', 'in'), items);
    });

    test('filters by searchField = name field (in)', () {
      final result = filterPickerItems(items, 'Galon', 'in');
      expect(result.length, 2);
      expect(result[0]['in'], 'Galon 19L RO');
      expect(result[1]['in'], 'Galon 12L');
    });

    test('filters by searchField = code field', () {
      final result = filterPickerItems(items, 'G19', 'code');
      expect(result.length, 1);
      expect(result[0]['code'], 'G19');
    });

    test('filters by searchField = category field', () {
      final result = filterPickerItems(items, 'consumable', 'ic');
      expect(result.length, 1);
      expect(result[0]['in'], 'Botol 600ml');
    });

    test('no match returns empty list', () {
      expect(filterPickerItems(items, 'xyz', 'in'), isEmpty);
    });

    test('case insensitive match', () {
      final result = filterPickerItems(items, 'galon', 'in');
      expect(result.length, 2);
    });

    test('partial match works', () {
      final result = filterPickerItems(items, '19', 'in');
      expect(result.length, 1);
      expect(result[0]['in'], 'Galon 19L RO');
    });

    test('missing field in item gracefully returns false', () {
      final result = filterPickerItems(items, 'test', 'nonexistent');
      expect(result, isEmpty);
    });

    test('trims whitespace before matching', () {
      final padded = [
        {'in': '  Galon 19L  '},
      ];
      final result = filterPickerItems(padded, 'galon', 'in');
      expect(result.length, 1);
    });
  });

  // ── searchField config default ──────────────────────────────────────────
  //
  // Mirrors the resolution in _showProductPicker:
  //   final nameField = (component['itemNameField'] ?? 'in').toString().trim();
  //   final searchField = (component['searchField'] ?? nameField).toString().trim();

  group('searchField config resolution', () {
    String resolveSearchField(Map<String, dynamic> component) {
      final String nameField =
          (component['itemNameField'] ?? 'in').toString().trim();
      final String raw =
          (component['searchField'] ?? '').toString().trim();
      return raw.isNotEmpty ? raw : nameField;
    }

    test('absent searchField falls back to nameField default (in)', () {
      expect(resolveSearchField({}), 'in');
    });

    test('absent searchField falls back to custom nameField', () {
      expect(resolveSearchField({'itemNameField': 'nm'}), 'nm');
    });

    test('explicit searchField overrides nameField', () {
      expect(
        resolveSearchField({
          'itemNameField': 'nm',
          'searchField': 'code',
        }),
        'code',
      );
    });

    test('empty string searchField falls back to nameField', () {
      expect(resolveSearchField({'searchField': ''}), 'in');
    });
  });

  // ── searchHint config default ───────────────────────────────────────────

  group('searchHint config resolution', () {
    String resolveSearchHint(Map<String, dynamic> component) {
      final String v =
          (component['searchHint'] ?? '').toString().trim();
      return v.isNotEmpty ? v : 'Cari...';
    }

    test('absent key -> default', () {
      expect(resolveSearchHint({}), 'Cari...');
    });

    test('custom hint', () {
      expect(resolveSearchHint({'searchHint': 'Cari produk\u{2026}'}),
          'Cari produk\u{2026}');
    });

    test('empty string -> default', () {
      expect(resolveSearchHint({'searchHint': ''}), 'Cari...');
    });
  });

  // ── emptyText config default ────────────────────────────────────────────

  group('picker emptyText config resolution', () {
    String resolveEmptyText(Map<String, dynamic> component) {
      final String v =
          (component['emptyText'] ?? '').toString().trim();
      return v.isNotEmpty ? v : 'Semua item sudah ditambahkan';
    }

    test('absent key -> default', () {
      expect(resolveEmptyText({}), 'Semua item sudah ditambahkan');
    });

    test('custom emptyText', () {
      expect(resolveEmptyText({'emptyText': 'No items'}), 'No items');
    });

    test('empty string -> default', () {
      expect(resolveEmptyText({'emptyText': ''}),
          'Semua item sudah ditambahkan');
    });
  });

  // ── txTypes parse and CTA gating ─────────────────────────────────────────
  //
  // TaskItemBuilder.parseTxTypes reads component['txTypes'], splits on comma,
  // trims, drops empties. Empty/absent -> all 4 default types.
  // Unknown types are preserved by the parser; the renderer skips them
  // (only known types produce a CTA button via _ctaLabel).

  group('txTypes parse and gating', () {
    test('absent txTypes key -> all 4 in default order', () {
      expect(
        TaskItemBuilder.parseTxTypes({}),
        ['deliver', 'sale', 'purchase', 'refill'],
      );
    });

    test('null txTypes value -> all 4', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': null}),
        ['deliver', 'sale', 'purchase', 'refill'],
      );
    });

    test('empty string txTypes -> all 4', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': ''}),
        ['deliver', 'sale', 'purchase', 'refill'],
      );
    });

    test('whitespace-only txTypes -> all 4', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': '   '}),
        ['deliver', 'sale', 'purchase', 'refill'],
      );
    });

    test('only commas txTypes -> all 4 (all entries empty after split)', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': ',,'}),
        ['deliver', 'sale', 'purchase', 'refill'],
      );
    });

    test('single type "deliver" -> [deliver]', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': 'deliver'}),
        ['deliver'],
      );
    });

    test('two types preserve order', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': 'sale,deliver'}),
        ['sale', 'deliver'],
      );
    });

    test('all 4 in non-default order preserves that order', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': 'refill,purchase,deliver,sale'}),
        ['refill', 'purchase', 'deliver', 'sale'],
      );
    });

    test('whitespace around entries is trimmed', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': ' deliver , sale '}),
        ['deliver', 'sale'],
      );
    });

    test('unknown type preserved in parsed list (renderer skips it)', () {
      expect(
        TaskItemBuilder.parseTxTypes({'txTypes': 'deliver,custom,sale'}),
        ['deliver', 'custom', 'sale'],
      );
    });
  });

  // ── Pickup breakdown math ─────────────────────────────────────────────
  //
  // TaskItemBuilder.pickupExchange(pd, pp) = min(pd, pp)
  //   -> empties returned in exchange for drops
  // TaskItemBuilder.pickupClearing(pd, pp) = max(0, pp - pd)
  //   -> additional outstanding being cleared

  group('pickupExchange', () {
    test('pd < pp -> exchange = pd', () {
      expect(TaskItemBuilder.pickupExchange(3, 8), 3);
    });

    test('pd > pp -> exchange = pp', () {
      expect(TaskItemBuilder.pickupExchange(8, 3), 3);
    });

    test('pd == pp -> exchange = pd (all exchange, no clearing)', () {
      expect(TaskItemBuilder.pickupExchange(5, 5), 5);
    });

    test('pd=0, pp=5 -> exchange = 0 (all clearing)', () {
      expect(TaskItemBuilder.pickupExchange(0, 5), 0);
    });

    test('both zero -> 0', () {
      expect(TaskItemBuilder.pickupExchange(0, 0), 0);
    });
  });

  group('pickupClearing', () {
    test('pp > pd -> clearing = pp - pd', () {
      expect(TaskItemBuilder.pickupClearing(3, 8), 5);
    });

    test('pp < pd -> clearing = 0', () {
      expect(TaskItemBuilder.pickupClearing(8, 3), 0);
    });

    test('pp == pd -> clearing = 0', () {
      expect(TaskItemBuilder.pickupClearing(5, 5), 0);
    });

    test('pd=0, pp=5 -> clearing = 5 (outstanding only)', () {
      expect(TaskItemBuilder.pickupClearing(0, 5), 5);
    });

    test('both zero -> 0', () {
      expect(TaskItemBuilder.pickupClearing(0, 0), 0);
    });
  });

  // ── Pickup breakdown identity: exchange + clearing == pp ──────────────

  group('pickupBreakdown identity', () {
    test('exchange + clearing == pp for various inputs', () {
      for (final (int pd, int pp) in [
        (0, 0), (0, 5), (3, 8), (5, 5), (8, 3), (10, 0), (1, 100),
      ]) {
        final int ex = TaskItemBuilder.pickupExchange(pd, pp);
        final int cl = TaskItemBuilder.pickupClearing(pd, pp);
        expect(ex + cl, pp,
            reason: 'pd=$pd pp=$pp -> exchange=$ex clearing=$cl');
      }
    });
  });
}
