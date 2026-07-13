// test/custody_count_submit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── ip[] builder ──────────────────────────────────────────────────────

  group('buildIpArray', () {
    /// Pure-logic extraction: iterate count entries, produce ip[] array.
    List<Map<String, dynamic>> buildIpArray(
        Map<String, CountEntry> countMap) {
      final List<Map<String, dynamic>> ip = <Map<String, dynamic>>[];
      for (final entry in countMap.values) {
        ip.add(entry.toIpMap());
      }
      return ip;
    }

    test('builds ip[] from count entries', () {
      final map = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 25),
        'lpg12__full': CountEntry(ii: 'lpg12', cd: 'full', qty: 17),
        'aqua600__full': CountEntry(ii: 'aqua600', cd: 'full', qty: 20),
      };
      final ip = buildIpArray(map);
      expect(ip.length, 3);
      expect(ip[0], {'ii': 'galon', 'cd': 'full', 'qt': 25});
      expect(ip[1], {'ii': 'lpg12', 'cd': 'full', 'qt': 17});
      expect(ip[2], {'ii': 'aqua600', 'cd': 'full', 'qt': 20});
    });

    test('empty map -> empty array', () {
      expect(buildIpArray({}), isEmpty);
    });

    test('entries with qty 0 are included', () {
      final map = <String, CountEntry>{
        'galon__full': CountEntry(ii: 'galon', cd: 'full', qty: 0),
      };
      final ip = buildIpArray(map);
      expect(ip.length, 1);
      expect(ip[0]['qt'], 0);
    });
  });

  // ── n/N + enable logic ────────────────────────────────────────────────

  group('submit button enable logic', () {
    /// Pure-logic: compute (n, N, enabled) from count entries.
    ({int n, int total, bool enabled}) computeEnable(
        Map<String, CountEntry> countMap) {
      final int total = countMap.length;
      final int n = countMap.values.where((e) => e.qty > 0).length;
      final bool enabled = total > 0 && n == total;
      return (n: n, total: total, enabled: enabled);
    }

    test('all > 0 -> enabled', () {
      final map = <String, CountEntry>{
        'a__x': CountEntry(ii: 'a', cd: 'x', qty: 5),
        'b__y': CountEntry(ii: 'b', cd: 'y', qty: 3),
      };
      final r = computeEnable(map);
      expect(r.n, 2);
      expect(r.total, 2);
      expect(r.enabled, true);
    });

    test('some == 0 -> disabled', () {
      final map = <String, CountEntry>{
        'a__x': CountEntry(ii: 'a', cd: 'x', qty: 5),
        'b__y': CountEntry(ii: 'b', cd: 'y', qty: 0),
        'c__z': CountEntry(ii: 'c', cd: 'z', qty: 3),
      };
      final r = computeEnable(map);
      expect(r.n, 2);
      expect(r.total, 3);
      expect(r.enabled, false);
    });

    test('empty map -> disabled (N=0)', () {
      final r = computeEnable({});
      expect(r.n, 0);
      expect(r.total, 0);
      expect(r.enabled, false);
    });

    test('all == 0 -> disabled', () {
      final map = <String, CountEntry>{
        'a__x': CountEntry(ii: 'a', cd: 'x', qty: 0),
        'b__y': CountEntry(ii: 'b', cd: 'y', qty: 0),
      };
      final r = computeEnable(map);
      expect(r.n, 0);
      expect(r.total, 2);
      expect(r.enabled, false);
    });

    /// Mirrors CustodyCountSubmit's label logic (pure-string extraction).
    String labelFor({required bool enabled, required int n, required int total}) {
      return enabled
          ? 'LIHAT CATATAN WAREHOUSE'
          : 'HITUNG SEMUA ITEM ($n/$total)';
    }

    test('label disabled shows n/N', () {
      expect(labelFor(enabled: false, n: 3, total: 4),
          'HITUNG SEMUA ITEM (3/4)');
    });

    test('label enabled shows warehouse text', () {
      expect(labelFor(enabled: true, n: 0, total: 0),
          'LIHAT CATATAN WAREHOUSE');
    });
  });

  // ── stripRouteWrapper ─────────────────────────────────────────────────

  group('stripRouteWrapper', () {
    test('strips [ROUTE:xxx] wrapper', () {
      expect(stripRouteWrapper('[ROUTE:custodyReveal]'), 'custodyReveal');
    });

    test('strips with spaces', () {
      expect(stripRouteWrapper(' [ROUTE: custodySuccess ] '), 'custodySuccess');
    });

    test('leaves bare route unchanged', () {
      expect(stripRouteWrapper('vertikaTeknoLokaciptaCustodyReveal'),
          'vertikaTeknoLokaciptaCustodyReveal');
    });

    test('empty string -> empty', () {
      expect(stripRouteWrapper(''), '');
    });

    test('partial match not stripped', () {
      expect(stripRouteWrapper('[ROUTE:incomplete'), '[ROUTE:incomplete');
    });

    test('nested brackets: outer [ROUTE:...] wrapper is stripped', () {
      // The wrapper matches startsWith('[ROUTE:') && endsWith(']'), so the
      // outer wrapper is removed, leaving the inner literal.
      expect(stripRouteWrapper('[ROUTE:[nested]]'), '[nested]');
    });
  });

  // ── CountEntry ────────────────────────────────────────────────────────

  group('CountEntry', () {
    test('default qty is 0', () {
      final e = CountEntry(ii: 'galon', cd: 'full');
      expect(e.qty, 0);
    });

    test('toIpMap shape', () {
      final e = CountEntry(ii: 'lpg12', cd: 'empty', qty: 7);
      expect(e.toIpMap(), {'ii': 'lpg12', 'cd': 'empty', 'qt': 7});
    });

    test('qty is mutable', () {
      final e = CountEntry(ii: 'x', cd: 'y', qty: 0);
      e.qty = 10;
      expect(e.qty, 10);
      expect(e.toIpMap()['qt'], 10);
    });
  });

  // ── diamondTextToList edge case ───────────────────────────────────────

  group('diamondTextToList empty-string edge case (submit context)', () {
    test("diamondTextToList('') returns [''] (length 1)", () {
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.length > 1 ? arr[1] : 'default', 'default');
    });
  });

  // ── warehouse vehicleId resolution (O1/C1 #ACTIVE_VEHICLE hand-off) ────
  //
  // Pure mirror of _resolveWarehouseVehicleId: prefer a published per-screen
  // vehicleId, else fall back to screenTx['#ACTIVE_VEHICLE']. O1/C1 have no
  // publisher (warehouse vehicle dv empty) -> a direct dhState read was always
  // empty, so the opening/closing doc wrote vv:"" + cnm:"CHK--{date}".

  group('warehouse vehicleId resolution', () {
    String resolveWarehouseVehicleId(
        String published, Map<String, dynamic> screenTx) {
      final String p = published.trim();
      if (p.isNotEmpty) return p;
      return (screenTx['#ACTIVE_VEHICLE'] ?? '').toString().trim();
    }

    test('published value wins (driver P6 / forward-compat)', () {
      expect(
        resolveWarehouseVehicleId('VEH-PUB', {'#ACTIVE_VEHICLE': 'VEH-ACT'}),
        'VEH-PUB',
      );
    });

    test('falls back to #ACTIVE_VEHICLE when unpublished (warehouse O1/C1)', () {
      expect(
        resolveWarehouseVehicleId('', {'#ACTIVE_VEHICLE': 'F629GD0000099'}),
        'F629GD0000099',
      );
    });

    test('both empty -> empty (pending-safe)', () {
      expect(resolveWarehouseVehicleId('', <String, dynamic>{}), '');
    });

    test('fallback value is trimmed', () {
      expect(
        resolveWarehouseVehicleId('', {'#ACTIVE_VEHICLE': '  F629GD0000099  '}),
        'F629GD0000099',
      );
    });

    test('whitespace-only published falls through to fallback', () {
      expect(
        resolveWarehouseVehicleId('   ', {'#ACTIVE_VEHICLE': 'VEH-ACT'}),
        'VEH-ACT',
      );
    });
  });

  // ── cnm format: the empty-vv double-dash regression ───────────────────
  //
  // genOpeningCnm/genClosingCnm build CHK-{vv}-{date}. With vv empty the doc id
  // collapses to "CHK--{date}", which H1's openingGate (vv◼{lv}) cannot link.
  // The submit fix guarantees vv is non-empty; these lock the format.

  group('cnm format guards the empty-vv double-dash bug', () {
    const int fixedNow = 1782000000000; // fixed epoch -> deterministic stamp

    test('non-empty vv -> CHK-{vv}-{date}, no double dash', () {
      final cnm = genOpeningCnm('F629GD0000099', nowMs: fixedNow);
      expect(cnm.startsWith('CHK-F629GD0000099-'), isTrue);
      expect(cnm.contains('CHK--'), isFalse);
    });

    test('empty vv reproduces the CHK--{date} defect (what the fix prevents)',
        () {
      final cnm = genOpeningCnm('', nowMs: fixedNow);
      expect(cnm.startsWith('CHK--'), isTrue);
    });

    test('closing cnm carries the vv too', () {
      final cnm = genClosingCnm('F629GD0000099', nowMs: fixedNow);
      expect(cnm.contains('F629GD0000099'), isTrue);
      expect(cnm.contains('CHK--'), isFalse);
    });
  });

  // ── buildReconciliation empty-maps (empty vehicle close) ───────────────
  // Guards the C1 empty-vehicle close: an all-zero / hideZero vehicle yields
  // an empty countMap, so both expected and actual are {}. Reconciliation must
  // report 'matched' with no discrepancies (routes to WarehouseClosingMatch).

  group('buildReconciliation empty maps (empty vehicle close)', () {
    test('empty expected + empty actual -> matched, dp empty', () {
      final result = buildReconciliation(expected: {}, actual: {});
      expect(result.rs, 'matched');
      expect(result.dp, isEmpty);
    });

    test('empty expected + non-empty actual -> discrepancy (surplus)', () {
      final result = buildReconciliation(
        expected: {},
        actual: {'galon__full': 5},
      );
      expect(result.rs, 'discrepancy_detected');
      expect(result.dp.length, 1);
      expect(result.dp[0]['dl'], 5); // surplus
    });
  });
}
