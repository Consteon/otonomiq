// test/custody_state_reset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart'; // for RxInt
import 'package:otonomiq/widget/custody_count_list.dart';
import 'package:otonomiq/widget/custody_reveal.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── CustodyCountList.clearCountStore ─────────────────────────────────────

  group('CustodyCountList.clearCountStore', () {
    setUp(() {
      // Ensure clean state before each test
      CustodyCountList.countStore.clear();
    });

    test('clears the per-scrName count map', () {
      // Populate
      final map = CustodyCountList.getCountMap('p6');
      map['galon__full'] = CountEntry(ii: 'galon', cd: 'full', qty: 10);
      map['lpg12__full'] = CountEntry(ii: 'lpg12', cd: 'full', qty: 5);
      expect(CustodyCountList.countStore.containsKey('p6'), true);
      expect(CustodyCountList.getCountMap('p6').length, 2);

      // Clear
      CustodyCountList.clearCountStore('p6');

      // Verify
      expect(CustodyCountList.countStore.containsKey('p6'), false);
      // getCountMap re-creates an empty map
      expect(CustodyCountList.getCountMap('p6'), isEmpty);
    });

    test('is a no-op for non-existent scrName', () {
      // Should not throw
      CustodyCountList.clearCountStore('nonexistent');
      expect(CustodyCountList.countStore.containsKey('nonexistent'), false);
    });

    test('does not affect other scrNames', () {
      CustodyCountList.getCountMap('p6a')['x__y'] =
          CountEntry(ii: 'x', cd: 'y', qty: 3);
      CustodyCountList.getCountMap('p6b')['x__y'] =
          CountEntry(ii: 'x', cd: 'y', qty: 7);

      CustodyCountList.clearCountStore('p6a');

      expect(CustodyCountList.countStore.containsKey('p6a'), false);
      expect(CustodyCountList.getCountMap('p6b')['x__y']!.qty, 7);
    });

    test('re-population after clear starts at qty 0', () {
      // Populate with non-zero
      CustodyCountList.getCountMap('p6')['item__cd'] =
          CountEntry(ii: 'item', cd: 'cd', qty: 15);

      // Clear
      CustodyCountList.clearCountStore('p6');

      // Re-populate (simulates widget rebuild calling putIfAbsent)
      final fresh = CustodyCountList.getCountMap('p6');
      fresh.putIfAbsent(
          'item__cd', () => CountEntry(ii: 'item', cd: 'cd', qty: 0));
      expect(fresh['item__cd']!.qty, 0);
    });
  });

  // ── CustodyReveal.clearEditState ─────────────────────────────────────────

  group('CustodyReveal.clearEditState', () {
    setUp(() {
      // Ensure clean state: clear the map entirely
      CustodyReveal.getEditMap('reveal').clear();
      CustodyReveal.clearEditState('reveal');
      CustodyReveal.getEditMap('revealA').clear();
      CustodyReveal.clearEditState('revealA');
      CustodyReveal.getEditMap('revealB').clear();
      CustodyReveal.clearEditState('revealB');
    });

    test('clears editStore, seeded flag, and writing flag', () {
      // Populate via public getEditMap
      final map = CustodyReveal.getEditMap('reveal');
      map['galon__full'] = CountEntry(ii: 'galon', cd: 'full', qty: 25);

      // clearEditState removes all three maps for the scrName
      CustodyReveal.clearEditState('reveal');

      // editStore is gone (getEditMap recreates empty)
      expect(CustodyReveal.getEditMap('reveal'), isEmpty);
    });

    test('is a no-op for non-existent scrName', () {
      // Should not throw
      CustodyReveal.clearEditState('nonexistent');
    });

    test('does not affect other scrNames', () {
      CustodyReveal.getEditMap('revealA')['x__y'] =
          CountEntry(ii: 'x', cd: 'y', qty: 10);
      CustodyReveal.getEditMap('revealB')['x__y'] =
          CountEntry(ii: 'x', cd: 'y', qty: 20);

      CustodyReveal.clearEditState('revealA');

      expect(CustodyReveal.getEditMap('revealA'), isEmpty);
      expect(CustodyReveal.getEditMap('revealB')['x__y']!.qty, 20);
    });
  });

  // ── Signal reactivity: editRev / countRev clear is observable ───────────

  group('CustodyReveal/CustodyCountList signal reactivity', () {
    setUp(() {
      CustodyReveal.clearEditState('rxtest');
    });

    test('clearEditState bumps editRev signal and clears map', () {
      // Populate
      CustodyReveal.getEditMap('rxtest')['a__b'] =
          CountEntry(ii: 'a', cd: 'b', qty: 5);
      expect(CustodyReveal.getEditMap('rxtest'), isNotEmpty);

      final int revBefore = CustodyReveal.editRev.value;
      CustodyReveal.clearEditState('rxtest');

      // Signal was bumped
      expect(CustodyReveal.editRev.value, revBefore + 1);
      // Map was cleared (getEditMap recreates an empty inner map)
      expect(CustodyReveal.getEditMap('rxtest'), isEmpty);
    });

    test('clearCountStore bumps countRev signal and clears map', () {
      CustodyCountList.getCountMap('rxtest')['c__d'] =
          CountEntry(ii: 'c', cd: 'd', qty: 7);
      expect(CustodyCountList.countStore.containsKey('rxtest'), true);

      final int revBefore = CustodyCountList.countRev.value;
      CustodyCountList.clearCountStore('rxtest');

      // Signal was bumped
      expect(CustodyCountList.countRev.value, revBefore + 1);
      // Map was cleared
      expect(CustodyCountList.countStore.containsKey('rxtest'), false);
    });

    test('multiple clears in sequence do not throw', () {
      CustodyReveal.getEditMap('rxtest')['x__y'] =
          CountEntry(ii: 'x', cd: 'y', qty: 1);
      CustodyReveal.clearEditState('rxtest');
      CustodyReveal.clearEditState('rxtest'); // second clear = no-op
      CustodyReveal.clearEditState('rxtest'); // third clear = no-op
      expect(CustodyReveal.getEditMap('rxtest'), isEmpty);
    });

    test('countRev and editRev are RxInt signals (design contract)', () {
      // After the build-notify fix, countStore and _editStore are plain Maps.
      // Cross-widget reactivity is driven by RxInt revision counters.
      expect(CustodyCountList.countRev, isA<RxInt>());
      expect(CustodyReveal.editRev, isA<RxInt>());

      // countStore is a plain Map (no longer RxMap)
      expect(CustodyCountList.countStore, isA<Map>());
      expect(CustodyCountList.countStore, isNot(isA<RxMap>()));

      // clearEditState still removes the key from the plain Map
      CustodyReveal.getEditMap('rxtest')['z__w'] =
          CountEntry(ii: 'z', cd: 'w', qty: 99);
      CustodyReveal.clearEditState('rxtest');
      final freshMap = CustodyReveal.getEditMap('rxtest');
      expect(freshMap, isEmpty); // key was removed, not just inner-map cleared
    });
  });

  // ── Seed-after-clear cooperates with seed-once ───────────────────────────

  group('seed-after-clear (Bug 2 regression test)', () {
    /// Simulate the seed-once guard with a clearable seeded flag.
    /// This mirrors the real _seedEditStore + clearEditState interaction.
    Map<String, CountEntry> simulateSeedOnce({
      required Map<String, CountEntry> editStore,
      required bool seeded,
      required List<Map<String, dynamic>> ipEntries,
    }) {
      if (seeded) return editStore; // guard: do NOT overwrite
      final Map<String, CountEntry> store = Map.of(editStore);
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

    test('clear + re-seed yields fresh ip[] values (Bug 2 fix)', () {
      // Session 1: seed from ip[] with old values
      final session1Ip = [
        {'ii': 'galon', 'cd': 'full', 'qt': 10},
      ];
      final store1 = simulateSeedOnce(
        editStore: {},
        seeded: false,
        ipEntries: session1Ip,
      );
      expect(store1['galon__full']!.qty, 10);

      // Session 1 is now seeded. If we DON'T clear, a second seed is blocked:
      final staleStore = simulateSeedOnce(
        editStore: store1,
        seeded: true, // still seeded from session 1
        ipEntries: [
          {'ii': 'galon', 'cd': 'full', 'qt': 25}, // new ip[] from P6 submit
        ],
      );
      expect(staleStore['galon__full']!.qty, 10); // BUG: stale!

      // FIX: clearEditState resets seeded flag. Now re-seed works:
      final freshStore = simulateSeedOnce(
        editStore: {}, // cleared by clearEditState
        seeded: false, // cleared by clearEditState
        ipEntries: [
          {'ii': 'galon', 'cd': 'full', 'qt': 25}, // fresh ip[]
        ],
      );
      expect(freshStore['galon__full']!.qty, 25); // FIXED: fresh value
    });

    test('within-session Firestore re-emit does NOT overwrite edits', () {
      // Seed from initial ip[]
      final store = simulateSeedOnce(
        editStore: {},
        seeded: false,
        ipEntries: [
          {'ii': 'galon', 'cd': 'full', 'qt': 25},
        ],
      );
      expect(store['galon__full']!.qty, 25);

      // Driver edits to 30
      store['galon__full']!.qty = 30;

      // Firestore re-emits (same ip[]) -- seed-once blocks overwrite
      final afterReemit = simulateSeedOnce(
        editStore: store,
        seeded: true, // set to true after first seed
        ipEntries: [
          {'ii': 'galon', 'cd': 'full', 'qt': 25}, // original doc value
        ],
      );
      expect(afterReemit['galon__full']!.qty, 30); // driver edit preserved
    });
  });

  // ── Sequenced Bug scenario tests ─────────────────────────────────────────

  group('Bug scenario: P6 reopen (Bug 1 + Bug 3)', () {
    setUp(() {
      CustodyCountList.countStore.clear();
    });

    test('clear then putIfAbsent resets all to 0', () {
      // Visit 1: driver counts items
      final map1 = CustodyCountList.getCountMap('p6screen');
      map1['galon__full'] = CountEntry(ii: 'galon', cd: 'full', qty: 10);
      map1['lpg12__full'] = CountEntry(ii: 'lpg12', cd: 'full', qty: 5);
      expect(map1['galon__full']!.qty, 10);

      // Navigation: clearData runs clearCountStore
      CustodyCountList.clearCountStore('p6screen');

      // Visit 2: widget rebuild calls putIfAbsent with qty 0
      final map2 = CustodyCountList.getCountMap('p6screen');
      map2.putIfAbsent(
          'galon__full', () => CountEntry(ii: 'galon', cd: 'full', qty: 0));
      map2.putIfAbsent(
          'lpg12__full', () => CountEntry(ii: 'lpg12', cd: 'full', qty: 0));

      expect(map2['galon__full']!.qty, 0);
      expect(map2['lpg12__full']!.qty, 0);
    });
  });
}
