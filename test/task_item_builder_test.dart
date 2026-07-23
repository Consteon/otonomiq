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

  // ── Picker sort (sortPickerItems) ─────────────────────────────────────
  //
  // TaskItemBuilder.sortPickerItems sorts in-place:
  //   sortField empty -> name asc only (current default).
  //   sortField non-empty -> primary numeric (coerceNum), secondary name asc.
  //   Dart List.sort is unstable -> name tiebreak is mandatory.

  group('sortPickerItems: no sortField (default name-asc)', () {
    test('sorts by name ascending, case-insensitive', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Galon 19L', 'freq': 5},
        {'in': 'Botol 600ml', 'freq': 20},
        {'in': 'Aqua 1500ml', 'freq': 1},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: '',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), [
        'Aqua 1500ml',
        'Botol 600ml',
        'Galon 19L',
      ]);
    });

    test('ignores sortDir when sortField is empty', () {
      final items = <Map<String, dynamic>>[
        {'in': 'B'},
        {'in': 'A'},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: '',
        sortDir: 'asc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['A', 'B']);
    });
  });

  group('sortPickerItems: freq desc (primary + tiebreak)', () {
    test('highest freq first', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Botol 600ml', 'freq': 3},
        {'in': 'Aqua 1500ml', 'freq': 50},
        {'in': 'Galon 19L', 'freq': 10},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), [
        'Aqua 1500ml',
        'Galon 19L',
        'Botol 600ml',
      ]);
    });

    test('same freq tiebreaks by name asc', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Galon 19L', 'freq': 10},
        {'in': 'Botol 600ml', 'freq': 10},
        {'in': 'Aqua 1500ml', 'freq': 10},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), [
        'Aqua 1500ml',
        'Botol 600ml',
        'Galon 19L',
      ]);
    });

    test('absent freq field on doc treated as 0 (falls to bottom)', () {
      final items = <Map<String, dynamic>>[
        {'in': 'NoFreq Item'},
        {'in': 'Popular', 'freq': 100},
        {'in': 'Another NoFreq'},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), [
        'Popular',
        'Another NoFreq',
        'NoFreq Item',
      ]);
    });

    test('freq as String coerced via coerceNum', () {
      final items = <Map<String, dynamic>>[
        {'in': 'A', 'freq': '5'},
        {'in': 'B', 'freq': 20},
        {'in': 'C', 'freq': '100'},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['C', 'B', 'A']);
    });

    test('null freq coerced to 0', () {
      final items = <Map<String, dynamic>>[
        {'in': 'B', 'freq': null},
        {'in': 'A', 'freq': 1},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['A', 'B']);
    });
  });

  group('sortPickerItems: freq asc', () {
    test('lowest freq first, tiebreak name asc', () {
      final items = <Map<String, dynamic>>[
        {'in': 'B', 'freq': 10},
        {'in': 'A', 'freq': 1},
        {'in': 'C', 'freq': 10},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'asc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['A', 'B', 'C']);
    });
  });

  group('sortPickerItems: empty list / single item', () {
    test('empty list is a no-op', () {
      final items = <Map<String, dynamic>>[];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items, isEmpty);
    });

    test('single item is a no-op', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Only', 'freq': 5},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.length, 1);
      expect(items[0]['in'], 'Only');
    });
  });

  // ── Sort + search composition ───────────────────────────────────────────
  //
  // _ProductPickerSheet.filtered does widget.items.where(...).toList()
  // which preserves input order. Verify that filtering a pre-sorted list
  // keeps the sort order in the result.

  group('search over sorted list preserves order', () {
    test('filter preserves freq-desc order', () {
      // Pre-sorted by freq desc: Popular(100), Galon(10), Botol(3)
      final sorted = <Map<String, dynamic>>[
        {'in': 'Popular Galon 19L', 'freq': 100},
        {'in': 'Galon 12L', 'freq': 10},
        {'in': 'Botol 600ml', 'freq': 3},
      ];
      // Simulate the sheet filter (search for "Galon")
      final filtered = filterPickerItems(sorted, 'Galon', 'in');
      expect(filtered.length, 2);
      // Order must be freq-desc: Popular Galon first, then Galon 12L
      expect(filtered[0]['in'], 'Popular Galon 19L');
      expect(filtered[1]['in'], 'Galon 12L');
    });
  });

  // ── sortField/sortDir config resolution ────────────────────────────────

  group('sortField config resolution', () {
    String resolveSortField(Map<String, dynamic> component) {
      final String raw =
          (component['sortField'] ?? '').toString().trim();
      return raw;
    }

    test('absent key -> empty string (name-only sort)', () {
      expect(resolveSortField({}), '');
    });

    test('explicit sortField', () {
      expect(resolveSortField({'sortField': 'freq'}), 'freq');
    });

    test('empty string -> empty (name-only sort)', () {
      expect(resolveSortField({'sortField': ''}), '');
    });
  });

  group('sortDir config resolution', () {
    String resolveSortDir(Map<String, dynamic> component) {
      final String raw =
          (component['sortDir'] ?? '').toString().trim().toLowerCase();
      return raw.isNotEmpty ? raw : 'desc';
    }

    test('absent key -> desc (default)', () {
      expect(resolveSortDir({}), 'desc');
    });

    test('explicit asc', () {
      expect(resolveSortDir({'sortDir': 'asc'}), 'asc');
    });

    test('explicit desc', () {
      expect(resolveSortDir({'sortDir': 'desc'}), 'desc');
    });

    test('empty string -> desc', () {
      expect(resolveSortDir({'sortDir': ''}), 'desc');
    });

    test('case insensitive (DESC -> desc)', () {
      expect(resolveSortDir({'sortDir': 'DESC'}), 'desc');
    });
  });

  // ── I3: sortField set but absent on ALL docs ────────────────────────────
  //
  // Until the Go CF ships `freq`, no doc in production has that field.
  // coerceNum(null) == 0 for every pair → primary always 0 → name-asc
  // tiebreak takes over. This pins the degrade path used today.

  group('sortPickerItems: sortField set, field absent on ALL docs (I3 degrade)', () {
    test('all docs missing sortField -> pure name-asc regardless of sortDir', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Zebra'},
        {'in': 'Apple'},
        {'in': 'Mango'},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['Apple', 'Mango', 'Zebra']);
    });
  });

  // ── I2: unknown sortDir → treated as desc ──────────────────────────────
  //
  // The comparator does `sortDir == 'asc' ? ... : vb.compareTo(va)`.
  // Any value that is not exactly 'asc' falls to the desc branch.
  // Lock this contract so a typo like 'descending' doesn't silently flip order.

  group('sortPickerItems: unknown sortDir treated as desc (I2)', () {
    test('sortDir "descending" (not "asc") -> highest freq first', () {
      final items = <Map<String, dynamic>>[
        {'in': 'A', 'freq': 1},
        {'in': 'B', 'freq': 10},
        {'in': 'C', 'freq': 5},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'descending',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['B', 'C', 'A']);
    });

    test('garbage sortDir -> treated as desc', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Low', 'freq': 1},
        {'in': 'High', 'freq': 100},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'bogus',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['High', 'Low']);
    });
  });

  // ── Negative freq values ────────────────────────────────────────────────
  //
  // coerceNum returns the numeric value as-is for negatives (v is num branch).
  // Verify they sort below zero in desc and above zero in asc correctly.

  group('sortPickerItems: negative freq values', () {
    test('negative freq sorts below zero in desc order', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Negative', 'freq': -5},
        {'in': 'Zero', 'freq': 0},
        {'in': 'Positive', 'freq': 10},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(),
          ['Positive', 'Zero', 'Negative']);
    });

    test('negative freq asc -> negative first', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Zero', 'freq': 0},
        {'in': 'Negative', 'freq': -3},
        {'in': 'Positive', 'freq': 7},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'asc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(),
          ['Negative', 'Zero', 'Positive']);
    });
  });

  // ── double/int freq mix ─────────────────────────────────────────────────
  //
  // coerceNum returns num for both int and double (v is num branch).
  // Dart's num.compareTo works across int/double — no type error.

  group('sortPickerItems: double/int freq mix', () {
    test('double and int freq sort correctly without type error', () {
      final items = <Map<String, dynamic>>[
        {'in': 'A', 'freq': 3},    // int
        {'in': 'B', 'freq': 3.5},  // double
        {'in': 'C', 'freq': 2},    // int
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['B', 'A', 'C']);
    });
  });

  // ── Garbage type freq → coerceNum 0 ────────────────────────────────────
  //
  // coerceNum: non-null, non-num → num.tryParse(v.toString()) ?? 0.
  // bool.toString() = 'true'/'false'; Map.toString() = '{...}' — both
  // fail tryParse and yield 0, so these items sort as if freq were absent.

  group('sortPickerItems: garbage type freq coerced to 0', () {
    test('bool freq coerced to 0 -> falls to name-asc tiebreak in desc', () {
      final items = <Map<String, dynamic>>[
        {'in': 'GarbageBool', 'freq': true},
        {'in': 'Normal', 'freq': 5},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['Normal', 'GarbageBool']);
    });

    test('map freq coerced to 0 -> falls to name-asc tiebreak in desc', () {
      final items = <Map<String, dynamic>>[
        {'in': 'GarbageMap', 'freq': <String, dynamic>{'x': 1}},
        {'in': 'Normal', 'freq': 10},
      ];
      TaskItemBuilder.sortPickerItems(
        items,
        sortField: 'freq',
        sortDir: 'desc',
        nameField: 'in',
      );
      expect(items.map((e) => e['in']).toList(), ['Normal', 'GarbageMap']);
    });
  });

  // ── Duplicate name + equal freq → comparator consistency ───────────────
  //
  // When both primary and tiebreak return 0 the comparator returns 0.
  // Dart List.sort requires a consistent comparator (must not throw).

  group('sortPickerItems: duplicate name and equal freq (comparator consistency)', () {
    test('identical name and freq -> no crash, higher-freq items precede lower', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Same', 'freq': 5},
        {'in': 'Same', 'freq': 5},
        {'in': 'Other', 'freq': 3},
      ];
      expect(
        () => TaskItemBuilder.sortPickerItems(
          items,
          sortField: 'freq',
          sortDir: 'desc',
          nameField: 'in',
        ),
        returnsNormally,
      );
      // Both 'Same' items (freq=5) precede 'Other' (freq=3)
      expect(items[0]['in'], 'Same');
      expect(items[1]['in'], 'Same');
      expect(items[2]['in'], 'Other');
    });
  });
}
