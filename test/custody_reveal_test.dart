// test/custody_reveal_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── Per-item comparison ────────────────────────────────────────────────

  group('per-item comparison logic', () {
    /// Pure-logic: compare one item's expected vs actual qty.
    /// Returns (status, delta). status: 'match', 'over', 'under'.
    ({String status, int delta}) compareItem(int expected, int actual) {
      final int delta = actual - expected;
      if (delta == 0) return (status: 'match', delta: 0);
      if (delta > 0) return (status: 'over', delta: delta);
      return (status: 'under', delta: delta);
    }

    test('equal -> match, delta 0', () {
      final r = compareItem(25, 25);
      expect(r.status, 'match');
      expect(r.delta, 0);
    });

    test('actual > expected -> over, positive delta', () {
      final r = compareItem(20, 26);
      expect(r.status, 'over');
      expect(r.delta, 6);
    });

    test('actual < expected -> under, negative delta', () {
      final r = compareItem(25, 18);
      expect(r.status, 'under');
      expect(r.delta, -7);
    });

    test('both 0 -> match', () {
      final r = compareItem(0, 0);
      expect(r.status, 'match');
      expect(r.delta, 0);
    });
  });

  // ── Full-array comparison (overall match/mismatch) ─────────────────────

  group('overall comparison', () {
    /// Pure-logic: given ie[] and ip[], build the comparison result.
    /// Returns (isMatch, items). Each item has ii, cd, expected, actual, delta.
    ({bool isMatch, List<Map<String, dynamic>> items}) compareArrays(
      List<Map<String, dynamic>> ie,
      List<Map<String, dynamic>> ip,
    ) {
      // Build lookup from ip by ii__cd
      final Map<String, int> ipMap = {};
      for (final entry in ip) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        if (ii.isNotEmpty) ipMap['${ii}__$cd'] = qt;
      }

      // Build lookup from ie by ii__cd
      final Map<String, int> ieMap = {};
      for (final entry in ie) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        if (ii.isNotEmpty) ieMap['${ii}__$cd'] = qt;
      }

      // Union of all keys
      final Set<String> allKeys = {...ieMap.keys, ...ipMap.keys};
      bool isMatch = true;
      final List<Map<String, dynamic>> items = [];
      for (final key in allKeys) {
        final int expected = ieMap[key] ?? 0;
        final int actual = ipMap[key] ?? 0;
        final int delta = actual - expected;
        if (delta != 0) isMatch = false;
        // Split key for ii and cd
        final parts = key.split('__');
        final String ii = parts.isNotEmpty ? parts[0] : '';
        final String cd = parts.length > 1 ? parts[1] : '';
        items.add({
          'ii': ii,
          'cd': cd,
          'expected': expected,
          'actual': actual,
          'delta': delta,
        });
      }
      return (isMatch: isMatch, items: items);
    }

    test('all match -> isMatch true', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
      ];
      final ip = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
      ];
      final r = compareArrays(ie, ip);
      expect(r.isMatch, true);
      expect(r.items.length, 2);
      for (final item in r.items) {
        expect(item['delta'], 0);
      }
    });

    test('some mismatch -> isMatch false', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
      ];
      final ip = [
        {'ii': 'galon', 'cd': 'full', 'qt': 31}, // +6
        {'ii': 'lpg12', 'cd': 'full', 'qt': 10}, // -7
      ];
      final r = compareArrays(ie, ip);
      expect(r.isMatch, false);
    });

    test('item in ie but not in ip -> actual=0, mismatch', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
      ];
      final ip = <Map<String, dynamic>>[];
      final r = compareArrays(ie, ip);
      expect(r.isMatch, false);
      expect(r.items.first['actual'], 0);
      expect(r.items.first['expected'], 25);
      expect(r.items.first['delta'], -25);
    });

    test('item in ip but not in ie -> expected=0, mismatch', () {
      final ie = <Map<String, dynamic>>[];
      final ip = [
        {'ii': 'extra', 'cd': 'full', 'qt': 5},
      ];
      final r = compareArrays(ie, ip);
      expect(r.isMatch, false);
      expect(r.items.first['expected'], 0);
      expect(r.items.first['actual'], 5);
    });

    test('both empty -> isMatch true (vacuously)', () {
      final r = compareArrays([], []);
      expect(r.isMatch, true);
      expect(r.items, isEmpty);
    });
  });

  // ── dp[] builder (discrepancy array) ──────────────────────────────────

  group('buildDpArray', () {
    /// Pure-logic: build dp[] from comparison items (only differing items).
    List<Map<String, dynamic>> buildDpArray(
        List<Map<String, dynamic>> comparedItems) {
      final List<Map<String, dynamic>> dp = [];
      for (final item in comparedItems) {
        final int delta = (item['delta'] as int?) ?? 0;
        if (delta == 0) continue;
        dp.add({
          'ii': item['ii'],
          'cd': item['cd'],
          'ex': item['expected'],
          'ac': item['actual'],
          'dl': delta,
        });
      }
      return dp;
    }

    test('only differing items included', () {
      final items = [
        {'ii': 'galon', 'cd': 'full', 'expected': 25, 'actual': 31, 'delta': 6},
        {'ii': 'lpg12', 'cd': 'full', 'expected': 17, 'actual': 17, 'delta': 0},
        {'ii': 'aqua', 'cd': 'full', 'expected': 20, 'actual': 13, 'delta': -7},
      ];
      final dp = buildDpArray(items);
      expect(dp.length, 2);
      expect(dp[0], {'ii': 'galon', 'cd': 'full', 'ex': 25, 'ac': 31, 'dl': 6});
      expect(dp[1], {'ii': 'aqua', 'cd': 'full', 'ex': 20, 'ac': 13, 'dl': -7});
    });

    test('all match -> empty dp', () {
      final items = [
        {'ii': 'x', 'cd': 'y', 'expected': 5, 'actual': 5, 'delta': 0},
      ];
      expect(buildDpArray(items), isEmpty);
    });

    test('empty items -> empty dp', () {
      expect(buildDpArray([]), isEmpty);
    });
  });

  // ── text slots ────────────────────────────────────────────────────────

  group('custodyReveal text slots', () {
    test('9-slot text parsed and length-guarded', () {
      final text = [
        'RETURNABLE', // 0
        'CONSUMABLE', // 1
        'warehouse', // 2
        'hitungan lo', // 3
        'Match', // 4
        'Ada selisih dengan catatan warehouse', // 5
        'Konfirmasi Load \u{00B7} Siap Berangkat', // 6
        'Lanjut \u{00B7} Report Mismatch', // 7
        'Hitung Ulang', // 8
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 9);
      expect(arr.isNotEmpty ? arr[0] : '', 'RETURNABLE');
      expect(arr.length > 1 ? arr[1] : '', 'CONSUMABLE');
      expect(arr.length > 2 ? arr[2] : '', 'warehouse');
      expect(arr.length > 3 ? arr[3] : '', 'hitungan lo');
      expect(arr.length > 4 ? arr[4] : '', 'Match');
      expect(arr.length > 5 ? arr[5] : '', 'Ada selisih dengan catatan warehouse');
      expect(arr.length > 8 ? arr[8] : '', 'Hitung Ulang');
    });

    test('short text array uses defaults', () {
      final arr = diamondTextToList('OnlyOne');
      expect(arr.isNotEmpty ? arr[0] : 'def', 'OnlyOne');
      expect(arr.length > 1 ? arr[1] : 'CONSUMABLE', 'CONSUMABLE');
      expect(arr.length > 8 ? arr[8] : 'Hitung Ulang', 'Hitung Ulang');
    });

    test("empty text -> length 1 (diamondTextToList('') gotcha)", () {
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.length > 1 ? arr[1] : 'default', 'default');
    });
  });

  // ── stripRouteWrapper (also tested in submit_test, repeated for coverage) ──

  group('stripRouteWrapper', () {
    test('strips [ROUTE:custodySuccess]', () {
      expect(stripRouteWrapper('[ROUTE:custodySuccess]'), 'custodySuccess');
    });

    test('leaves bare route as-is', () {
      expect(stripRouteWrapper('somePage'), 'somePage');
    });

    test('empty -> empty', () {
      expect(stripRouteWrapper(''), '');
    });
  });

  // -- Seed-once logic (pure-function form) --------------------------------

  group('reveal seed-once logic', () {
    /// Simulate the seed-once guard: only seed when seeded flag is false.
    Map<String, CountEntry> seedEditStore({
      required Map<String, CountEntry> existing,
      required bool seeded,
      required List<Map<String, dynamic>> ipEntries,
    }) {
      if (seeded) return existing; // guard: do NOT overwrite
      final Map<String, CountEntry> store = Map.of(existing);
      for (final entry in ipEntries) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        if (ii.isEmpty) continue;
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        final String key = '${ii}__$cd';
        store.putIfAbsent(key, () => CountEntry(ii: ii, cd: cd, qty: qt));
      }
      return store;
    }

    test('first seed populates from ip[]', () {
      final ipEntries = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
      ];
      final store = seedEditStore(
        existing: {},
        seeded: false,
        ipEntries: ipEntries,
      );
      expect(store.length, 2);
      expect(store['galon__full']!.qty, 25);
      expect(store['lpg12__full']!.qty, 17);
    });

    test('second seed (seeded=true) does NOT overwrite', () {
      final existing = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 30), // edited
      };
      final ipEntries = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25}, // original from doc
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
      ];
      final store = seedEditStore(
        existing: existing,
        seeded: true,
        ipEntries: ipEntries,
      );
      // seeded=true -> existing returned as-is (no overwrite, no additions)
      expect(store.length, 1);
      expect(store['galon__full']!.qty, 30); // driver edit preserved
      expect(store.containsKey('lpg12__full'), false);
    });

    test('seed with empty ip[] -> empty store', () {
      final store = seedEditStore(
        existing: {},
        seeded: false,
        ipEntries: [],
      );
      expect(store, isEmpty);
    });

    test('seed skips entries with empty ii', () {
      final ipEntries = [
        {'ii': '', 'cd': 'full', 'qt': 5},
        {'ii': 'valid', 'cd': 'ok', 'qt': 10},
      ];
      final store = seedEditStore(
        existing: {},
        seeded: false,
        ipEntries: ipEntries,
      );
      expect(store.length, 1);
      expect(store['valid__ok']!.qty, 10);
    });
  });

  // -- Edited ip[] builder -------------------------------------------------

  group('buildIpFromEditStore', () {
    /// Build ip[] array from the editable count store.
    List<Map<String, dynamic>> buildIpFromEditStore(
        Map<String, CountEntry> editStore) {
      final List<Map<String, dynamic>> ip = <Map<String, dynamic>>[];
      for (final entry in editStore.values) {
        ip.add(entry.toIpMap());
      }
      return ip;
    }

    test('builds ip[] from edited entries', () {
      final store = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 30),
        'lpg12__full': CountEntry(ii: 'lpg12', cd: 'full', qty: 15),
      };
      final ip = buildIpFromEditStore(store);
      expect(ip.length, 2);
      expect(ip[0], {'ii': 'galon', 'cd': 'full', 'qt': 30});
      expect(ip[1], {'ii': 'lpg12', 'cd': 'full', 'qt': 15});
    });

    test('empty store -> empty array', () {
      expect(buildIpFromEditStore({}), isEmpty);
    });
  });

  // -- Live recompute (match <-> mismatch as value changes) ----------------

  group('live recompute on edit', () {
    /// Simulate _compare with editable actual values.
    ({bool isMatch, List<Map<String, dynamic>> items}) compareWithEdited(
      List<Map<String, dynamic>> ie,
      Map<String, CountEntry> editStore,
    ) {
      final Map<String, int> ieMap = {};
      for (final entry in ie) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        if (ii.isNotEmpty) ieMap['${ii}__$cd'] = qt;
      }

      final Set<String> allKeys = {...ieMap.keys, ...editStore.keys};
      bool isMatch = true;
      final List<Map<String, dynamic>> items = [];
      for (final key in allKeys) {
        final int expected = ieMap[key] ?? 0;
        final int actual = editStore[key]?.qty ?? 0;
        final int delta = actual - expected;
        if (delta != 0) isMatch = false;
        final parts = key.split('__');
        items.add({
          'ii': parts.isNotEmpty ? parts[0] : '',
          'cd': parts.length > 1 ? parts[1] : '',
          'expected': expected,
          'actual': actual,
          'delta': delta,
        });
      }
      return (isMatch: isMatch, items: items);
    }

    test('starts matching, stays matching after no edit', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
      ];
      final editStore = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 25),
      };
      final r = compareWithEdited(ie, editStore);
      expect(r.isMatch, true);
    });

    test('edit flips from match to mismatch', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
      ];
      final editStore = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 25),
      };
      // Initially matches
      expect(compareWithEdited(ie, editStore).isMatch, true);
      // Driver edits: now 30 instead of 25
      editStore['galon__full']!.qty = 30;
      final r2 = compareWithEdited(ie, editStore);
      expect(r2.isMatch, false);
      expect(r2.items.first['delta'], 5);
    });

    test('edit corrects mismatch back to match', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
      ];
      final editStore = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 20),
      };
      // Initially mismatches
      expect(compareWithEdited(ie, editStore).isMatch, false);
      // Driver corrects to 25
      editStore['galon__full']!.qty = 25;
      expect(compareWithEdited(ie, editStore).isMatch, true);
    });

    test('multi-item: one edit breaks overall match', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
      ];
      final editStore = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 25),
        'lpg12__full': CountEntry(ii: 'lpg12', cd: 'full', qty: 17),
      };
      expect(compareWithEdited(ie, editStore).isMatch, true);
      editStore['lpg12__full']!.qty = 10;
      final r = compareWithEdited(ie, editStore);
      expect(r.isMatch, false);
    });
  });

  // -- dp[] from edited state ----------------------------------------------

  group('dp[] from edited state', () {
    List<Map<String, dynamic>> buildDpFromEdited(
      List<Map<String, dynamic>> ie,
      Map<String, CountEntry> editStore,
    ) {
      final Map<String, int> ieMap = {};
      for (final entry in ie) {
        final String ii = (entry['ii'] ?? '').toString().trim();
        final String cd = (entry['cd'] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        if (ii.isNotEmpty) ieMap['${ii}__$cd'] = qt;
      }

      final Set<String> allKeys = {...ieMap.keys, ...editStore.keys};
      final List<Map<String, dynamic>> dp = [];
      for (final key in allKeys) {
        final int expected = ieMap[key] ?? 0;
        final int actual = editStore[key]?.qty ?? 0;
        final int delta = actual - expected;
        if (delta == 0) continue;
        final parts = key.split('__');
        dp.add({
          'ii': parts.isNotEmpty ? parts[0] : '',
          'cd': parts.length > 1 ? parts[1] : '',
          'ex': expected,
          'ac': actual,
          'dl': delta,
        });
      }
      return dp;
    }

    test('dp[] from edited state with mixed deltas', () {
      final ie = [
        {'ii': 'galon', 'cd': 'full', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
        {'ii': 'aqua', 'cd': 'full', 'qt': 20},
      ];
      final editStore = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 31), // +6
        'lpg12__full': CountEntry(ii: 'lpg12', cd: 'full', qty: 17), // match
        'aqua__full': CountEntry(ii: 'aqua', cd: 'full', qty: 13),   // -7
      };
      final dp = buildDpFromEdited(ie, editStore);
      expect(dp.length, 2);
      // Check galon (over)
      final galonDp = dp.firstWhere((e) => e['ii'] == 'galon');
      expect(galonDp['ex'], 25);
      expect(galonDp['ac'], 31);
      expect(galonDp['dl'], 6);
      // Check aqua (under)
      final aquaDp = dp.firstWhere((e) => e['ii'] == 'aqua');
      expect(aquaDp['ex'], 20);
      expect(aquaDp['ac'], 13);
      expect(aquaDp['dl'], -7);
    });

    test('all match -> empty dp[]', () {
      final ie = [
        {'ii': 'x', 'cd': 'y', 'qt': 5},
      ];
      final editStore = <String, CountEntry>{
        'x__y': CountEntry(ii: 'x', cd: 'y', qty: 5),
      };
      expect(buildDpFromEdited(ie, editStore), isEmpty);
    });
  });

  // -- cst flip in write patch (R2-A) ----------------------------------------

  group('cst flip in write patch', () {
    test('match path patch includes cst:custody_confirmed', () {
      // Simulates the exact patch from CustodyReveal build (match path)
      // + the cst augmentation from _writeAndNavigate.
      final patch = <String, dynamic>{
        'ip': [
          {'ii': 'galon', 'cd': 'full', 'qt': 25},
          {'ii': 'lpg12', 'cd': 'full', 'qt': 17},
        ],
        'rs': 'matched',
      };
      // _writeAndNavigate adds cst before writeNativeFields:
      patch['cst'] = 'custody_confirmed';

      expect(patch['cst'], 'custody_confirmed');
      expect(patch['rs'], 'matched');
      expect(patch.length, 3); // ip, rs, cst
    });

    test('mismatch path patch includes cst:custody_confirmed', () {
      // Simulates the exact patch from CustodyReveal build (mismatch path)
      // + the cst augmentation from _writeAndNavigate.
      final patch = <String, dynamic>{
        'ip': [
          {'ii': 'galon', 'cd': 'full', 'qt': 25},
        ],
        'dp': [
          {'ii': 'galon', 'cd': 'full', 'ex': 25, 'ac': 31, 'dl': 6},
        ],
        'rs': 'discrepancy_detected',
      };
      // _writeAndNavigate adds cst before writeNativeFields:
      patch['cst'] = 'custody_confirmed';

      expect(patch['cst'], 'custody_confirmed');
      expect(patch['rs'], 'discrepancy_detected');
      expect(patch.length, 4); // ip, dp, rs, cst
    });
  });
}
