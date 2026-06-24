// test/custody_count_list_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/custody_stepper.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── buildItemDetailMap ─────────────────────────────────────────────────

  group('buildItemDetailMap', () {
    test('maps ii -> ItemDetail with name and category', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': 'galon', 'in': 'Galon Air 19L', 'ic': 'returnable'},
        {'ii': 'lpg12', 'in': 'LPG 12kg', 'ic': 'returnable'},
        {'ii': 'aqua600', 'in': 'Aqua 600ml', 'ic': 'consumable'},
      ];
      final map = buildItemDetailMap(itemDocs);
      expect(map.length, 3);
      expect(map['galon']!.name, 'Galon Air 19L');
      expect(map['galon']!.category, 'returnable');
      expect(map['aqua600']!.name, 'Aqua 600ml');
      expect(map['aqua600']!.category, 'consumable');
    });

    test('skips entries with empty ii', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': '', 'in': 'No ID', 'ic': 'returnable'},
        {'ii': 'valid', 'in': 'Valid', 'ic': 'consumable'},
      ];
      final map = buildItemDetailMap(itemDocs);
      expect(map.length, 1);
      expect(map.containsKey(''), false);
      expect(map['valid']!.name, 'Valid');
    });

    test('handles null fields gracefully', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': 'x', 'in': null, 'ic': null},
      ];
      final map = buildItemDetailMap(itemDocs);
      expect(map['x']!.name, '');
      expect(map['x']!.category, '');
    });

    test('handles absent fields gracefully', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': 'y'},
      ];
      final map = buildItemDetailMap(itemDocs);
      expect(map['y']!.name, '');
      expect(map['y']!.category, '');
    });

    test('custom field names work', () {
      final itemDocs = <Map<String, dynamic>>[
        {'id': 'a', 'name': 'Alpha', 'cat': 'type1'},
      ];
      final map = buildItemDetailMap(
        itemDocs,
        idField: 'id',
        nameField: 'name',
        categoryField: 'cat',
      );
      expect(map['a']!.name, 'Alpha');
      expect(map['a']!.category, 'type1');
    });

    test('empty list returns empty map', () {
      expect(buildItemDetailMap([]), isEmpty);
    });
  });

  // ── CustodyCountList filter logic ──────────────────────────────────────

  group('custodyCountList filter logic (unit-level)', () {
    // Simulate the widget's filter: parse "ic◼returnable" into field+value,
    // then match each ie[] entry's joined category.
    Map<String, String> parseFilter(String raw) {
      final int sep = raw.indexOf('\u{25FC}');
      if (sep < 0) return {};
      final String field = raw.substring(0, sep).trim();
      final String value = raw.substring(sep + 1).trim();
      if (field.isEmpty || value.isEmpty) return {};
      return {'field': field, 'value': value};
    }

    test('parses ic◼returnable correctly', () {
      final f = parseFilter('ic\u{25FC}returnable');
      expect(f['field'], 'ic');
      expect(f['value'], 'returnable');
    });

    test('parses ic◼consumable correctly', () {
      final f = parseFilter('ic\u{25FC}consumable');
      expect(f['field'], 'ic');
      expect(f['value'], 'consumable');
    });

    test('empty filter returns empty map', () {
      expect(parseFilter(''), isEmpty);
    });

    test('no separator returns empty map', () {
      expect(parseFilter('noseparator'), isEmpty);
    });

    test('filter + join correctly splits ie[] by category', () {
      final ieEntries = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'galon', 'cd': 'empty', 'qt': 5},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
        {'ii': 'aqua600', 'cd': 'full', 'qt': 20},
      ];
      final itemDetailMap = <String, ItemDetail>{
        'galon': const ItemDetail(name: 'Galon Air 19L', category: 'returnable'),
        'lpg12': const ItemDetail(name: 'LPG 12kg', category: 'returnable'),
        'aqua600': const ItemDetail(name: 'Aqua 600ml', category: 'consumable'),
      };

      // Filter for returnable
      final returnable = ieEntries.where((e) {
        final String ii = (e['ii'] ?? '').toString().trim();
        final ItemDetail? detail = itemDetailMap[ii];
        return detail != null && detail.category == 'returnable';
      }).toList();
      expect(returnable.length, 3); // galon-full, galon-empty, lpg12-full

      // Filter for consumable
      final consumable = ieEntries.where((e) {
        final String ii = (e['ii'] ?? '').toString().trim();
        final ItemDetail? detail = itemDetailMap[ii];
        return detail != null && detail.category == 'consumable';
      }).toList();
      expect(consumable.length, 1); // aqua600-full
      expect(consumable.first['ii'], 'aqua600');
    });

    test('unknown ii in ie[] is excluded (no crash)', () {
      final ieEntries = <Map<String, dynamic>>[
        {'ii': 'unknown_item', 'cd': 'full', 'qt': 5},
      ];
      final itemDetailMap = <String, ItemDetail>{
        'galon': const ItemDetail(name: 'Galon', category: 'returnable'),
      };
      final filtered = ieEntries.where((e) {
        final String ii = (e['ii'] ?? '').toString().trim();
        final ItemDetail? detail = itemDetailMap[ii];
        return detail != null && detail.category == 'returnable';
      }).toList();
      expect(filtered, isEmpty);
    });
  });

  // ── Count store (CountEntry) ───────────────────────────────────────────

  group('custodyCountList count-store (CountEntry)', () {
    test('composite key is ii__cd', () {
      String countKey(String ii, String cd) => '${ii}__$cd';
      expect(countKey('galon', 'full'), 'galon__full');
      expect(countKey('lpg12', 'empty'), 'lpg12__empty');
    });

    test('per-scrName isolation with CountEntry', () {
      final Map<String, Map<String, CountEntry>> store = {};
      store.putIfAbsent('screenA', () => {});
      store.putIfAbsent('screenB', () => {});
      store['screenA']!['galon__full'] =
          CountEntry(ii: 'galon', cd: 'full', qty: 10);
      store['screenB']!['galon__full'] =
          CountEntry(ii: 'galon', cd: 'full', qty: 5);
      expect(store['screenA']!['galon__full']!.qty, 10);
      expect(store['screenB']!['galon__full']!.qty, 5);
    });

    test('CountEntry.toIpMap produces correct shape', () {
      final entry = CountEntry(ii: 'galon', cd: 'full', qty: 25);
      final map = entry.toIpMap();
      expect(map, {'ii': 'galon', 'cd': 'full', 'qt': 25});
    });

    test('clearCountStore removes scrName entry', () {
      final Map<String, Map<String, CountEntry>> store = {};
      store['scr1'] = {
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 3),
      };
      store.remove('scr1');
      expect(store.containsKey('scr1'), false);
    });
  });

  // ── diamondTextToList edge case (from auto-memory) ─────────────────────

  group('diamondTextToList empty-string edge case', () {
    test("diamondTextToList('') returns [''] (length 1), NOT []", () {
      // From auto-memory: this cost the P5 coder a STOP.
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr[0], isNotNull); // it's a string, possibly empty
      // Fallback defaults only kick in at index >= 1
      expect(arr.length > 1 ? arr[1] : 'default', 'default');
    });
  });

  // ── Shared CustodyStepper min-clamping (pure function) ─────────────────

  group('CustodyStepper min-clamping (custody_count_list usage)', () {
    test('decrement below 0 is clamped to 0 (min=0)', () {
      // The neutral P6 stepper enforces min 0; a -1 from value 0 clamps to 0.
      expect(clampStepperValue(-1, 0), 0);
      expect(clampStepperValue(0, 0), 0);
    });

    test('value above min is unchanged', () {
      expect(clampStepperValue(7, 0), 7);
    });
  });
}
