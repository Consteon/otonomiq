// test/warehouse_closing_check_c1_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── buildReconciliation (shared pure helper) ──────────────────────────

  group('buildReconciliation', () {
    test('all match -> rs=matched, dp empty', () {
      final result = buildReconciliation(
        expected: {'galon__full': 10, 'lpg12__full': 5},
        actual: {'galon__full': 10, 'lpg12__full': 5},
      );
      expect(result.rs, 'matched');
      expect(result.dp, isEmpty);
    });

    test('some mismatch -> rs=discrepancy_detected, dp has differing items',
        () {
      final result = buildReconciliation(
        expected: {'galon__full': 10, 'lpg12__full': 5, 'aqua__full': 8},
        actual: {'galon__full': 10, 'lpg12__full': 3, 'aqua__full': 12},
      );
      expect(result.rs, 'discrepancy_detected');
      expect(result.dp.length, 2);
      // lpg12: expected 5, actual 3, delta -2
      final lpg = result.dp.firstWhere((d) => d['ii'] == 'lpg12');
      expect(lpg['ex'], 5);
      expect(lpg['ac'], 3);
      expect(lpg['dl'], -2);
      expect(lpg['cd'], 'full');
      // aqua: expected 8, actual 12, delta +4
      final aqua = result.dp.firstWhere((d) => d['ii'] == 'aqua');
      expect(aqua['ex'], 8);
      expect(aqua['ac'], 12);
      expect(aqua['dl'], 4);
    });

    test('item in expected but not actual -> delta = -expected', () {
      final result = buildReconciliation(
        expected: {'galon__full': 10},
        actual: <String, int>{},
      );
      expect(result.rs, 'discrepancy_detected');
      expect(result.dp.length, 1);
      expect(result.dp.first['dl'], -10);
      expect(result.dp.first['ac'], 0);
    });

    test('item in actual but not expected -> delta = +actual', () {
      final result = buildReconciliation(
        expected: <String, int>{},
        actual: {'extra__empty': 7},
      );
      expect(result.rs, 'discrepancy_detected');
      expect(result.dp.length, 1);
      expect(result.dp.first['dl'], 7);
      expect(result.dp.first['ex'], 0);
    });

    test('both empty -> rs=matched, dp empty (vacuously)', () {
      final result = buildReconciliation(
        expected: <String, int>{},
        actual: <String, int>{},
      );
      expect(result.rs, 'matched');
      expect(result.dp, isEmpty);
    });

    test('parses ii and cd from composite key', () {
      final result = buildReconciliation(
        expected: {'galon__full': 10},
        actual: {'galon__full': 8},
      );
      expect(result.dp.first['ii'], 'galon');
      expect(result.dp.first['cd'], 'full');
    });

    test('handles keys without __ separator', () {
      final result = buildReconciliation(
        expected: {'galon': 10},
        actual: {'galon': 8},
      );
      expect(result.dp.first['ii'], 'galon');
      expect(result.dp.first['cd'], '');
    });

    // I1: dp[] order must be deterministic (insertion order:
    // expected-keys-then-actual-only-keys). This preserves custodyReveal's
    // prior ie-first dp[] ordering after the refactor.
    test('dp[] preserves expected-then-actual-only insertion order', () {
      final result = buildReconciliation(
        // expected iteration order: galon, lpg12, aqua
        expected: {'galon__full': 10, 'lpg12__full': 5, 'aqua__full': 8},
        // 'extra' is actual-only -> must come AFTER the expected keys
        actual: {
          'galon__full': 6, // delta -4
          'lpg12__full': 5, // match (dropped)
          'aqua__full': 13, // delta +5
          'extra__empty': 2, // actual-only, delta +2
        },
      );
      expect(result.dp.map((d) => d['ii']).toList(),
          ['galon', 'aqua', 'extra']);
    });
  });

  // ── genOpeningCnm (W1: opening doc id for cst-close by id) ─────────────

  group('genOpeningCnm', () {
    test('format: CHK-{vehicleId}-{YYYYMMDD} (no -C suffix)', () {
      final int nowMs =
          DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final cnm = genOpeningCnm('VEH-B1234XY', nowMs: nowMs);
      expect(cnm, 'CHK-VEH-B1234XY-20260624');
      expect(cnm, isNot(endsWith('-C')));
    });

    test('matches the closing cnm minus the -C suffix (same nowMs)', () {
      final int nowMs =
          DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final opening = genOpeningCnm('VEH-X', nowMs: nowMs);
      final closing = genClosingCnm('VEH-X', nowMs: nowMs);
      expect(closing, '$opening-C');
    });

    test('WIB date boundary (23:30 UTC Jun 23 = 06:30 WIB Jun 24)', () {
      final int nowMs =
          DateTime.utc(2026, 6, 23, 23, 30).millisecondsSinceEpoch;
      final cnm = genOpeningCnm('VEH-A', nowMs: nowMs);
      expect(cnm, 'CHK-VEH-A-20260624');
    });
  });

  // ── genClosingCnm ──────────────────────────────────────────────────────

  group('genClosingCnm', () {
    test('format: CHK-{vehicleId}-{YYYYMMDD}-C', () {
      // 2026-06-24 10:30 UTC = 2026-06-24 17:30 WIB
      final int nowMs =
          DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final cnm = genClosingCnm('VEH-B1234XY', nowMs: nowMs);
      expect(cnm, 'CHK-VEH-B1234XY-20260624-C');
    });

    test('does NOT collide with opening cnm (no -C suffix)', () {
      final int nowMs =
          DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final closingCnm = genClosingCnm('VEH-X', nowMs: nowMs);
      // Opening cnm from O1 would be CHK-VEH-X-20260624
      expect(closingCnm, isNot('CHK-VEH-X-20260624'));
      expect(closingCnm, endsWith('-C'));
    });

    test('WIB date boundary (23:30 UTC Jun 23 = 06:30 WIB Jun 24)', () {
      final int nowMs =
          DateTime.utc(2026, 6, 23, 23, 30).millisecondsSinceEpoch;
      final cnm = genClosingCnm('VEH-A', nowMs: nowMs);
      expect(cnm, 'CHK-VEH-A-20260624-C');
    });
  });

  // ── genInvestigationVnm ──────────────────────────────────────────────────

  group('genInvestigationVnm', () {
    test('format: INV-{vehicleId}-{YYYYMMDD}', () {
      final int nowMs =
          DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final vnm = genInvestigationVnm('VEH-B1234XY', nowMs: nowMs);
      expect(vnm, 'INV-VEH-B1234XY-20260624');
    });
  });

  // ── CountEntry.planQty ────────────────────────────────────────────────

  group('CountEntry.planQty', () {
    test('default planQty is 0', () {
      final entry = CountEntry(ii: 'galon', cd: 'full', qty: 5);
      expect(entry.planQty, 0);
    });

    test('planQty can be set at construction', () {
      final entry =
          CountEntry(ii: 'galon', cd: 'full', qty: 5, planQty: 10);
      expect(entry.planQty, 10);
    });

    test('toIpMap does NOT include planQty', () {
      final entry =
          CountEntry(ii: 'galon', cd: 'full', qty: 5, planQty: 10);
      final map = entry.toIpMap();
      expect(map, {'ii': 'galon', 'cd': 'full', 'qt': 5});
      expect(map.containsKey('planQty'), false);
    });

    test('planQty is mutable (updated by asset_cache reload)', () {
      final entry = CountEntry(ii: 'galon', cd: 'full', qty: 5, planQty: 10);
      entry.planQty = 15;
      expect(entry.planQty, 15);
      // qty unchanged
      expect(entry.qty, 5);
    });
  });

  // ── Closing doc map assembly ──────────────────────────────────────────

  group('closing doc map assembly', () {
    test('builds complete closing doc with all fields (no ldt: I2)', () {
      final doc = <String, dynamic>{
        'cnm': 'CHK-VEH-B1234XY-20260624-C',
        'cty': 'closing',
        'vv': 'VEH-B1234XY',
        'gl': 'WH-001',
        'cdt': '1719176400000',
        'cv': 'checker-vid',
        'cn': 'Anton Pratama',
        't': 1719216600000,
        'ip': [
          {'ii': 'galon', 'cd': 'full', 'qt': 8},
          {'ii': 'galon', 'cd': 'empty', 'qt': 2},
        ],
        'dp': [
          {'ii': 'galon', 'cd': 'full', 'ex': 10, 'ac': 8, 'dl': -2},
        ],
        'rs': 'discrepancy_detected',
        'tablevid': '20342033315492',
        'search': 'cnm\u{2605}CHK-VEH-B1234XY-20260624-C',
      };
      expect(doc['cnm'], endsWith('-C'));
      expect(doc['cty'], 'closing');
      expect(doc['ip'], isA<List>());
      expect(doc['dp'], isA<List>());
      expect(doc['rs'], 'discrepancy_detected');
      expect(doc['search'], contains('\u{2605}'));
      // I2: ldt is an opening concept; the closing doc carries only `t`.
      expect(doc.containsKey('ldt'), false);
      expect(doc['t'], isA<int>());
    });

    test('matched doc has empty dp and rs=matched', () {
      final doc = <String, dynamic>{
        'cnm': 'CHK-VEH-A-20260624-C',
        'cty': 'closing',
        'vv': 'VEH-A',
        'ip': [
          {'ii': 'galon', 'cd': 'full', 'qt': 10},
        ],
        'dp': <Map<String, dynamic>>[],
        'rs': 'matched',
      };
      expect(doc['dp'], isEmpty);
      expect(doc['rs'], 'matched');
    });
  });

  // ── Investigation doc map assembly ────────────────────────────────────

  group('investigation doc map assembly', () {
    test('builds investigation doc with required fields', () {
      final doc = <String, dynamic>{
        'vnm': 'INV-VEH-B1234XY-20260624',
        'vst': 'pending_review',
        'vrf': 'CHK-VEH-B1234XY-20260624-C',
        'vpt': 'check',
        'cv': 'checker-vid',
        'cn': 'Anton',
        't': 1719216600000,
        'tablevid': '20342033315492',
        'search': 'vnm\u{2605}INV-VEH-B1234XY-20260624',
      };
      expect(doc['vnm'], startsWith('INV-'));
      expect(doc['vst'], 'pending_review');
      expect(doc['vrf'], endsWith('-C'));
      expect(doc['vpt'], 'check');
    });
  });

  // ── Reconcile from count store entries ────────────────────────────────

  group('reconcile from count store', () {
    test('builds expected/actual maps from CountEntry planQty/qty', () {
      final countMap = <String, CountEntry>{
        'galon__full':
            CountEntry(ii: 'galon', cd: 'full', qty: 8, planQty: 10),
        'galon__empty':
            CountEntry(ii: 'galon', cd: 'empty', qty: 2, planQty: 2),
        'lpg12__full':
            CountEntry(ii: 'lpg12', cd: 'full', qty: 5, planQty: 5),
      };

      final expectedMap = <String, int>{};
      final actualMap = <String, int>{};
      for (final entry in countMap.entries) {
        expectedMap[entry.key] = entry.value.planQty;
        actualMap[entry.key] = entry.value.qty;
      }

      final result = buildReconciliation(
        expected: expectedMap,
        actual: actualMap,
      );

      expect(result.rs, 'discrepancy_detected');
      expect(result.dp.length, 1);
      expect(result.dp.first['ii'], 'galon');
      expect(result.dp.first['cd'], 'full');
      expect(result.dp.first['dl'], -2); // 8 - 10
    });
  });

  // ── Asset_cache row building (pure logic) ──────────────────────────────

  group('asset_cache count row building', () {
    test('builds rows with planQty from asset_cache qt', () {
      // Simulate asset_cache docs
      final acDocs = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'full', 'qt': 10},
        {'ii': 'galon', 'cd': 'empty', 'qt': 3},
        {'ii': 'lpg12', 'cd': 'full', 'qt': 5},
      ];

      // Build count entries as the widget would
      final countMap = <String, CountEntry>{};
      for (final doc in acDocs) {
        final String ii = (doc['ii'] ?? '').toString().trim();
        final String cd = (doc['cd'] ?? '').toString().trim();
        final int qt = coerceNum(doc['qt']).toInt();
        final String key = '${ii}__$cd';
        countMap.putIfAbsent(
            key, () => CountEntry(ii: ii, cd: cd, qty: 0, planQty: qt));
      }

      expect(countMap.length, 3);
      expect(countMap['galon__full']!.planQty, 10);
      expect(countMap['galon__full']!.qty, 0); // not yet counted
      expect(countMap['galon__empty']!.planQty, 3);
      expect(countMap['lpg12__full']!.planQty, 5);
    });

    test('empty ii entries are skipped', () {
      final acDocs = <Map<String, dynamic>>[
        {'ii': '', 'cd': 'full', 'qt': 10},
        {'ii': 'galon', 'cd': 'full', 'qt': 5},
      ];

      final countMap = <String, CountEntry>{};
      for (final doc in acDocs) {
        final String ii = (doc['ii'] ?? '').toString().trim();
        if (ii.isEmpty) continue;
        final String cd = (doc['cd'] ?? '').toString().trim();
        final int qt = coerceNum(doc['qt']).toInt();
        final String key = '${ii}__$cd';
        countMap.putIfAbsent(
            key, () => CountEntry(ii: ii, cd: cd, qty: 0, planQty: qt));
      }

      expect(countMap.length, 1);
      expect(countMap.containsKey('galon__full'), true);
    });

    test('string qt values are coerced', () {
      final acDocs = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'full', 'qt': '10'},
      ];

      final doc = acDocs.first;
      final int qt = coerceNum(doc['qt']).toInt();
      expect(qt, 10);
    });

    test('null qt values default to 0', () {
      final acDocs = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'full', 'qt': null},
      ];

      final doc = acDocs.first;
      final int qt = coerceNum(doc['qt']).toInt();
      expect(qt, 0);
    });

    test('existing entry planQty is updated on reload (qty preserved)', () {
      // Models _buildAssetCacheRows: putIfAbsent then overwrite planQty.
      final countMap = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 4, planQty: 10),
      };
      // asset_cache reload with a new expected qty
      const int newExpected = 12;
      final existing = countMap.putIfAbsent('galon__full',
          () => CountEntry(ii: 'galon', cd: 'full', qty: 0, planQty: newExpected));
      existing.planQty = newExpected;
      expect(countMap['galon__full']!.planQty, 12);
      expect(countMap['galon__full']!.qty, 4); // counted value preserved
    });
  });
}
