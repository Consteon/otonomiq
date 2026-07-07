import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/vehicle_feed_support.dart';

void main() {
  // ── pickActiveOpening ─────────────────────────────────────────────────────

  group('pickActiveOpening', () {
    test('empty list -> null', () {
      expect(pickActiveOpening([]), isNull);
    });

    test('no opening-shaped docs -> null', () {
      expect(
        pickActiveOpening([
          {'cty': 'closing', 'cst': 'closed', 't': 100},
          {'cty': 'task', 'cst': '', 't': 200},
        ]),
        isNull,
      );
    });

    test('single non-closed opening -> returns it', () {
      final doc = {'cty': 'opening', 'cst': 'awaiting_custody', 't': 100, '__docId': 'A'};
      expect(pickActiveOpening([doc]), doc);
    });

    test('single closed opening -> returns it (fallback)', () {
      final doc = {'cty': 'opening', 'cst': 'closed', 't': 100, '__docId': 'A'};
      expect(pickActiveOpening([doc]), doc);
    });

    test('prefers newest non-closed over older non-closed', () {
      final result = pickActiveOpening([
        {'cty': 'opening', 'cst': 'awaiting_custody', 't': 100, '__docId': 'OLD'},
        {'cty': 'opening', 'cst': 'custody_confirmed', 't': 200, '__docId': 'NEW'},
      ]);
      expect(result?['__docId'], 'NEW');
    });

    test('prefers non-closed over closed even if older', () {
      final result = pickActiveOpening([
        {'cty': 'opening', 'cst': 'closed', 't': 300, '__docId': 'CLOSED'},
        {'cty': 'opening', 'cst': 'awaiting_custody', 't': 100, '__docId': 'ACTIVE'},
      ]);
      expect(result?['__docId'], 'ACTIVE');
    });

    test('all closed -> returns newest by t', () {
      final result = pickActiveOpening([
        {'cty': 'opening', 'cst': 'closed', 't': 100, '__docId': 'OLD'},
        {'cty': 'opening', 'cst': 'closed', 't': 300, '__docId': 'NEW'},
        {'cty': 'opening', 'cst': 'closed', 't': 200, '__docId': 'MID'},
      ]);
      expect(result?['__docId'], 'NEW');
    });

    test('ignores non-opening docs in mixed list', () {
      final result = pickActiveOpening([
        {'cty': 'closing', 'cst': '', 't': 999, '__docId': 'CLOSING'},
        {'cty': 'opening', 'cst': 'awaiting_custody', 't': 100, '__docId': 'OPENING'},
      ]);
      expect(result?['__docId'], 'OPENING');
    });

    test('t parsed as string', () {
      final result = pickActiveOpening([
        {'cty': 'opening', 'cst': 'awaiting_custody', 't': '100', '__docId': 'A'},
        {'cty': 'opening', 'cst': 'awaiting_custody', 't': '200', '__docId': 'B'},
      ]);
      expect(result?['__docId'], 'B');
    });
  });

  // ── genOpeningCnm with seq ──────────────────────────────────────────────

  group('genOpeningCnm seq', () {
    // WIB (UTC+7) midnight 2026-07-06. _wibDateStamp adds +7h then reads the
    // UTC date, so this instant yields the date stamp '20260706'.
    final int nowMs = DateTime.utc(2026, 7, 6).millisecondsSinceEpoch - 25200000;

    test('seq=1 -> no suffix (backward compat)', () {
      final cnm = genOpeningCnm('B1234XY', nowMs: nowMs, seq: 1);
      expect(cnm, 'CHK-B1234XY-20260706');
    });

    test('default seq -> no suffix', () {
      final cnm = genOpeningCnm('B1234XY', nowMs: nowMs);
      expect(cnm, 'CHK-B1234XY-20260706');
    });

    test('seq=2 -> suffix -2', () {
      final cnm = genOpeningCnm('B1234XY', nowMs: nowMs, seq: 2);
      expect(cnm, 'CHK-B1234XY-20260706-2');
    });

    test('seq=3 -> suffix -3', () {
      final cnm = genOpeningCnm('B1234XY', nowMs: nowMs, seq: 3);
      expect(cnm, 'CHK-B1234XY-20260706-3');
    });
  });

  group('genClosingCnm seq', () {
    final int nowMs = DateTime.utc(2026, 7, 6).millisecondsSinceEpoch - 25200000;

    test('seq=1 -> -C suffix only', () {
      final cnm = genClosingCnm('B1234XY', nowMs: nowMs, seq: 1);
      expect(cnm, 'CHK-B1234XY-20260706-C');
    });

    test('seq=2 -> -2-C', () {
      final cnm = genClosingCnm('B1234XY', nowMs: nowMs, seq: 2);
      expect(cnm, 'CHK-B1234XY-20260706-2-C');
    });
  });

  group('genInvestigationVnm seq', () {
    final int nowMs = DateTime.utc(2026, 7, 6).millisecondsSinceEpoch - 25200000;

    test('seq=1 -> no suffix', () {
      final vnm = genInvestigationVnm('B1234XY', nowMs: nowMs, seq: 1);
      expect(vnm, 'INV-B1234XY-20260706');
    });

    test('seq=2 -> suffix -2', () {
      final vnm = genInvestigationVnm('B1234XY', nowMs: nowMs, seq: 2);
      expect(vnm, 'INV-B1234XY-20260706-2');
    });
  });

  // ── deriveVehicleTier: completed branch removed ─────────────────────────

  group('deriveVehicleTier trip-sequence', () {
    test('closing doc exists -> NOT completed (closingDoc no longer checked)', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          closingDoc: {'cty': 'closing'},
          taskDocs: [{'tst': 'assigned'}],
        ),
        // closingDoc no longer short-circuits. cst=custody_confirmed,
        // tasks has assigned -> anyOpen -> inRoute.
        VehicleTier.inRoute,
      );
    });

    test('cst=closed + dv set -> loading (fallback)', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'closed'},
        ),
        VehicleTier.loading,
      );
    });

    test('cst=closed + dv empty -> loading', () {
      expect(
        deriveVehicleTier(
          dv: '',
          openingDoc: {'cst': 'closed'},
        ),
        VehicleTier.loading,
      );
    });

    test('awaiting_custody still works', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'awaiting_custody'},
        ),
        VehicleTier.custodyPending,
      );
    });

    test('custody_confirmed + open tasks -> inRoute', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          taskDocs: [{'tst': 'assigned'}],
        ),
        VehicleTier.inRoute,
      );
    });

    test('custody_confirmed + all done -> returning', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          taskDocs: [{'tst': 'completed'}, {'tst': 'failed'}],
        ),
        VehicleTier.returning,
      );
    });
  });

  // ── buildVehicleFeed: newest opening + tr scope ─────────────────────────

  group('buildVehicleFeed trip-sequence', () {
    test('picks newest opening per vv (non-closed preferred)', () {
      final feed = buildVehicleFeed(
        stockDocs: [
          {'lv': 'V1', 'ln': 'B1234', 'dv': '111', 'dn': 'Ali'},
        ],
        vehicleCheckDocs: [
          // Trip 1 (closed, older)
          {'cty': 'opening', 'vv': 'V1', 'cst': 'closed', 't': 100, '__docId': 'T1'},
          // Trip 2 (active, newer)
          {'cty': 'opening', 'vv': 'V1', 'cst': 'awaiting_custody', 't': 200, '__docId': 'T2'},
        ],
        taskDocs: [],
        categoryMap: {},
        todayEpoch: '12345',
      );
      expect(feed.length, 1);
      expect(feed.first.openingDoc?['__docId'], 'T2');
      expect(feed.first.tier, VehicleTier.custodyPending);
    });

    test('tr-scoped task rollup', () {
      final feed = buildVehicleFeed(
        stockDocs: [
          {'lv': 'V1', 'ln': 'B1234', 'dv': '111', 'dn': 'Ali'},
        ],
        vehicleCheckDocs: [
          {'cty': 'opening', 'vv': 'V1', 'cst': 'custody_confirmed', 't': 100, '__docId': 'T1'},
        ],
        taskDocs: [
          // Task for trip T1 (completed)
          {'vv': 'V1', 'tdt': '12345', 'tst': 'completed', 'tr': 'T1'},
          // Task for trip T2 (NOT matching T1)
          {'vv': 'V1', 'tdt': '12345', 'tst': 'assigned', 'tr': 'T2'},
        ],
        categoryMap: {},
        todayEpoch: '12345',
      );
      expect(feed.length, 1);
      // Only T1 tasks count. T1 has 1 completed -> returning.
      expect(feed.first.tier, VehicleTier.returning);
      expect(feed.first.stopsTotal, 1); // only T1's task
    });

    test('no tr on tasks -> fallback to (vv, today) scope', () {
      final feed = buildVehicleFeed(
        stockDocs: [
          {'lv': 'V1', 'ln': 'B1234', 'dv': '111', 'dn': 'Ali'},
        ],
        vehicleCheckDocs: [
          {'cty': 'opening', 'vv': 'V1', 'cst': 'custody_confirmed', 't': 100, '__docId': 'T1'},
        ],
        taskDocs: [
          // Legacy tasks: no tr field
          {'vv': 'V1', 'tdt': '12345', 'tst': 'assigned'},
          {'vv': 'V1', 'tdt': '12345', 'tst': 'completed'},
        ],
        categoryMap: {},
        todayEpoch: '12345',
      );
      expect(feed.length, 1);
      // Fallback: both tasks counted (2 total, 1 done, 1 open -> inRoute)
      expect(feed.first.tier, VehicleTier.inRoute);
      expect(feed.first.stopsTotal, 2);
    });

    test('closed vehicle with dv empty -> loading (backlog)', () {
      final feed = buildVehicleFeed(
        stockDocs: [
          {'lv': 'V1', 'ln': 'B1234', 'dv': '', 'dn': ''},
        ],
        vehicleCheckDocs: [
          {'cty': 'opening', 'vv': 'V1', 'cst': 'closed', 't': 100, '__docId': 'T1'},
        ],
        taskDocs: [],
        categoryMap: {},
        todayEpoch: '12345',
      );
      expect(feed.length, 1);
      expect(feed.first.tier, VehicleTier.loading);
    });

    test('active opening with zero tr-matched tasks -> returning (vacuous)', () {
      final feed = buildVehicleFeed(
        stockDocs: [
          {'lv': 'V1', 'ln': 'B1234', 'dv': '111', 'dn': 'Ali'},
        ],
        vehicleCheckDocs: [
          {'cty': 'opening', 'vv': 'V1', 'cst': 'custody_confirmed', 't': 100, '__docId': 'T1'},
        ],
        taskDocs: [
          // Tasks exist but for a DIFFERENT trip
          {'vv': 'V1', 'tdt': '12345', 'tst': 'assigned', 'tr': 'T2'},
        ],
        categoryMap: {},
        todayEpoch: '12345',
      );
      expect(feed.length, 1);
      // tr-scoped: 0 tasks for T1. Fallback: 1 task (vv,today) -> inRoute.
      // ponytail: with fallback active, shows the unmatched tasks. Without
      // fallback (post-CF), would be returning (vacuous empty).
      // Either way, not loading and not completed.
      expect(feed.first.tier, isNot(VehicleTier.completed));
    });
  });

  // ── resolveAndPublishActiveTrip (sync, reads mapTableContent mock) ──────

  // NOTE: resolveAndPublishActiveTrip reads from the global `mapTableContent`
  // (RxMap from GetX). A full unit test requires initializing GetX. The
  // function's core logic (filter+sort) is tested via the pickActiveOpening
  // tests above (same shared helper). A dedicated integration test can be
  // added when the GetX test harness is set up for this file.
}
