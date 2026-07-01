import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/vehicle_feed_support.dart';

void main() {
  // ── deriveVehicleTier ────────────────────────────────────────────────────

  group('deriveVehicleTier', () {
    test('dv empty -> loading', () {
      expect(
        deriveVehicleTier(dv: ''),
        VehicleTier.loading,
      );
    });

    test('dv empty ignores opening doc', () {
      expect(
        deriveVehicleTier(
          dv: '',
          openingDoc: {'cst': 'awaiting_custody'},
        ),
        VehicleTier.loading,
      );
    });

    test('dv set + awaiting_custody -> custodyPending', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'awaiting_custody'},
        ),
        VehicleTier.custodyPending,
      );
    });

    test('dv set + custody_confirmed + open tasks -> inRoute', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          taskDocs: [
            {'tst': 'assigned'},
            {'tst': 'completed'},
          ],
        ),
        VehicleTier.inRoute,
      );
    });

    test('dv set + custody_confirmed + all done + no closing -> returning', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          taskDocs: [
            {'tst': 'completed'},
            {'tst': 'failed'},
          ],
        ),
        VehicleTier.returning,
      );
    });

    test('dv set + custody_confirmed + no tasks -> returning (vacuous)', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          taskDocs: [],
        ),
        VehicleTier.returning,
      );
    });

    test('closing doc exists -> completed (overrides cst)', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          closingDoc: {'cty': 'closing'},
          taskDocs: [{'tst': 'assigned'}],
        ),
        VehicleTier.completed,
      );
    });

    test('cst == closed -> completed', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'closed'},
        ),
        VehicleTier.completed,
      );
    });

    test('dv set + no opening doc -> loading fallback', () {
      expect(
        deriveVehicleTier(dv: '111'),
        VehicleTier.loading,
      );
    });
  });

  // ── countDistinctItemsByCategory ─────────────────────────────────────────

  group('countDistinctItemsByCategory', () {
    test('counts distinct items per category', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'ii': 'A1', 'in': 'Aqua'},
            {'ii': 'L1', 'in': 'LPG'},
          ]
        },
        {
          'it': [
            {'ii': 'A1', 'in': 'Aqua'}, // duplicate
            {'ii': 'A2', 'in': 'Aqua 2'},
          ]
        },
      ];
      final catMap = {'A1': 'returnable', 'A2': 'returnable', 'L1': 'consumable'};
      final result = countDistinctItemsByCategory(tasks, catMap);
      expect(result['returnable'], 2); // A1, A2
      expect(result['consumable'], 1); // L1
    });

    test('empty tasks -> empty map', () {
      final result = countDistinctItemsByCategory([], {});
      expect(result, isEmpty);
    });

    test('items not in categoryMap -> unknown', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'ii': 'X1'},
          ]
        },
      ];
      final result = countDistinctItemsByCategory(tasks, {});
      expect(result['unknown'], 1);
    });

    test('non-List it field is skipped', () {
      final tasks = <Map<String, dynamic>>[
        {'it': 'not a list'},
      ];
      final result = countDistinctItemsByCategory(tasks, {});
      expect(result, isEmpty);
    });

    test('non-Map entries in it[] are skipped', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': ['rogue', {'ii': 'A1'}]
        },
      ];
      final catMap = {'A1': 'returnable'};
      final result = countDistinctItemsByCategory(tasks, catMap);
      expect(result['returnable'], 1);
    });
  });

  // ── formatCategorySummary ────────────────────────────────────────────────

  group('formatCategorySummary', () {
    test('returnable first, consumable second', () {
      expect(
        formatCategorySummary({'returnable': 3, 'consumable': 1}),
        '3 returnable \u{00B7} 1 consumable',
      );
    });

    test('empty map -> empty string', () {
      expect(formatCategorySummary({}), '');
    });

    test('only consumable', () {
      expect(formatCategorySummary({'consumable': 2}), '2 consumable');
    });

    test('zero values are omitted', () {
      expect(
        formatCategorySummary({'returnable': 0, 'consumable': 1}),
        '1 consumable',
      );
    });

    test('unknown categories appear after known', () {
      expect(
        formatCategorySummary({'unknown': 1, 'returnable': 2}),
        '2 returnable \u{00B7} 1 unknown',
      );
    });

    // Issue W3: an all-unknown summary degrades to no summary line.
    test('only unknown -> empty string (W3)', () {
      expect(formatCategorySummary({'unknown': 4}), '');
    });

    test('returnable + unknown keeps known, suppresses nothing (W3)', () {
      expect(
        formatCategorySummary({'returnable': 2, 'unknown': 1}),
        '2 returnable \u{00B7} 1 unknown',
      );
    });

    test('returnable only with explicit unknown:0 -> returnable shown (W3)', () {
      // Demonstrates W3 guard fires only when the ONLY non-zero entry is unknown.
      expect(formatCategorySummary({'returnable': 2, 'unknown': 1}),
          '2 returnable \u{00B7} 1 unknown');
      expect(formatCategorySummary({'unknown': 4}), '');
    });
  });

  // ── formatEpochTime ──────────────────────────────────────────────────────

  group('formatEpochTime', () {
    test('valid epoch -> HH:mm', () {
      // 2026-06-24 07:30:00 UTC = 1750750200000
      final result = formatEpochTime(1750750200000);
      // Exact output depends on local timezone; just check format
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(result), isTrue);
    });

    test('null -> empty', () {
      expect(formatEpochTime(null), '');
    });

    test('0 -> empty', () {
      expect(formatEpochTime(0), '');
    });

    test('empty string -> empty', () {
      expect(formatEpochTime(''), '');
    });

    test('string epoch parses correctly', () {
      final result = formatEpochTime('1750750200000');
      expect(result.isNotEmpty, isTrue);
    });
  });

  // ── countStopProgress ────────────────────────────────────────────────────

  group('countStopProgress', () {
    test('mixed states', () {
      final docs = [
        {'tst': 'completed'},
        {'tst': 'assigned'},
        {'tst': 'failed'},
      ];
      final result = countStopProgress(docs);
      expect(result.done, 2); // completed + failed
      expect(result.total, 3);
    });

    test('empty docs', () {
      final result = countStopProgress([]);
      expect(result.done, 0);
      expect(result.total, 0);
    });

    test('all done', () {
      final docs = [
        {'tst': 'completed'},
        {'tst': 'closed'},
      ];
      final result = countStopProgress(docs);
      expect(result.done, 2);
      expect(result.total, 2);
    });
  });

  // ── computeSnapshot ──────────────────────────────────────────────────────

  group('computeSnapshot', () {
    test('counts tiers correctly', () {
      final entries = [
        VehicleFeedEntry(lv: '1', plate: '', driverVid: '', driverName: '', tier: VehicleTier.loading),
        VehicleFeedEntry(lv: '2', plate: '', driverVid: '', driverName: '', tier: VehicleTier.returning),
        VehicleFeedEntry(lv: '3', plate: '', driverVid: '', driverName: '', tier: VehicleTier.custodyPending),
        VehicleFeedEntry(lv: '4', plate: '', driverVid: '', driverName: '', tier: VehicleTier.inRoute),
        VehicleFeedEntry(lv: '5', plate: '', driverVid: '', driverName: '', tier: VehicleTier.completed),
      ];
      final snap = computeSnapshot(entries);
      expect(snap.perluTindakan, 2); // returning + custodyPending
      expect(snap.openingCheck, 1); // loading
      expect(snap.hariIni, 5);      // total
    });

    test('empty entries -> all zeros', () {
      final snap = computeSnapshot([]);
      expect(snap.perluTindakan, 0);
      expect(snap.openingCheck, 0);
      expect(snap.hariIni, 0);
    });
  });

  // ── groupFeedBySections ──────────────────────────────────────────────────

  group('groupFeedBySections', () {
    test('groups and orders correctly, omits empty', () {
      final entries = [
        VehicleFeedEntry(lv: '1', plate: '', driverVid: '', driverName: '', tier: VehicleTier.loading),
        VehicleFeedEntry(lv: '2', plate: '', driverVid: '', driverName: '', tier: VehicleTier.returning),
        VehicleFeedEntry(lv: '3', plate: '', driverVid: '', driverName: '', tier: VehicleTier.completed),
      ];
      final labels = ['PT', 'PB', 'DP', 'SHI'];
      final sections = groupFeedBySections(entries, labels);

      expect(sections.length, 3); // no in_route section
      expect(sections[0].label, 'PT'); // Perlu Tindakan first
      expect(sections[0].entries.length, 1); // returning only
      expect(sections[1].label, 'PB'); // Pengecekan Pembukaan
      expect(sections[1].entries.length, 1); // loading
      expect(sections[2].label, 'SHI'); // Selesai Hari Ini
    });

    test('all empty -> no sections', () {
      final sections = groupFeedBySections([], ['A', 'B', 'C', 'D']);
      expect(sections, isEmpty);
    });

    test('length-guards section labels', () {
      final entries = [
        VehicleFeedEntry(lv: '1', plate: '', driverVid: '', driverName: '', tier: VehicleTier.loading),
      ];
      // Only 1 label provided (short text segment)
      final sections = groupFeedBySections(entries, ['Only']);
      expect(sections.first.label, 'Pengecekan Pembukaan'); // fallback
    });
  });

  // ── buildItemCategoryMap ─────────────────────────────────────────────────

  group('buildItemCategoryMap', () {
    test('builds map from item docs', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'A1', 'ic': 'returnable'},
        {'ii': 'L1', 'ic': 'consumable'},
        {'ii': '', 'ic': 'skip'}, // empty id skipped
      ];
      final map = buildItemCategoryMap(docs);
      expect(map['A1'], 'returnable');
      expect(map['L1'], 'consumable');
      expect(map.length, 2);
    });

    test('empty ic is skipped', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'A1', 'ic': ''},
      ];
      final map = buildItemCategoryMap(docs);
      expect(map.containsKey('A1'), isFalse);
    });
  });

  // ── buildVehicleFeed integration ─────────────────────────────────────────

  group('buildVehicleFeed', () {
    test('full pipeline: multiple vehicles, correct tiers', () {
      final stockDocs = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'B 1234', 'dv': '', 'dn': ''},          // loading
        {'lv': 'V2', 'ln': 'B 5678', 'dv': 'D1', 'dn': 'Driver1'}, // check below
      ];
      final checkDocs = <Map<String, dynamic>>[
        {'cty': 'opening', 'vv': 'V2', 'cst': 'awaiting_custody', 'cdt': '123'},
      ];
      final taskDocs = <Map<String, dynamic>>[];
      final catMap = <String, String>{};

      final feed = buildVehicleFeed(
        stockDocs: stockDocs,
        vehicleCheckDocs: checkDocs,
        taskDocs: taskDocs,
        categoryMap: catMap,
        todayEpoch: '123',
      );

      expect(feed.length, 2);
      expect(feed[0].tier, VehicleTier.loading);   // V1: dv empty
      expect(feed[1].tier, VehicleTier.custodyPending); // V2: awaiting_custody
    });

    test('completed filtered by today', () {
      final stockDocs = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'B 1234', 'dv': 'D1', 'dn': 'Driver1'},
      ];
      final checkDocs = <Map<String, dynamic>>[
        {'cty': 'opening', 'vv': 'V1', 'cst': 'closed', 'cdt': '999'}, // yesterday
      ];
      final feed = buildVehicleFeed(
        stockDocs: stockDocs,
        vehicleCheckDocs: checkDocs,
        taskDocs: [],
        categoryMap: {},
        todayEpoch: '123', // today != 999
      );

      expect(feed, isEmpty); // old completed trip dropped
    });

    test('empty stock_location docs -> empty feed', () {
      final feed = buildVehicleFeed(
        stockDocs: [],
        vehicleCheckDocs: [],
        taskDocs: [],
        categoryMap: {},
        todayEpoch: '123',
      );
      expect(feed, isEmpty);
    });

    test('category summary computed correctly', () {
      final stockDocs = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'B 1234', 'dv': '', 'dn': ''},
      ];
      final taskDocs = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '123',
          'it': [
            {'ii': 'A1'},
            {'ii': 'L1'},
          ],
        },
      ];
      final catMap = {'A1': 'returnable', 'L1': 'consumable'};

      final feed = buildVehicleFeed(
        stockDocs: stockDocs,
        vehicleCheckDocs: [],
        taskDocs: taskDocs,
        categoryMap: catMap,
        todayEpoch: '123',
      );

      expect(feed.first.categorySummary, '1 returnable \u{00B7} 1 consumable');
    });
  });
}
