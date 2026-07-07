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

    test('closing doc exists -> ignored for tier (trip-sequence: falls through to cst)', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'custody_confirmed'},
          closingDoc: {'cty': 'closing'},
          taskDocs: [{'tst': 'assigned'}],
        ),
        VehicleTier.inRoute,
      );
    });

    test('cst == closed -> loading (trip-sequence: backlog, completed tier removed)', () {
      expect(
        deriveVehicleTier(
          dv: '111',
          openingDoc: {'cst': 'closed'},
        ),
        VehicleTier.loading,
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

    test('closed opening + dv set -> loading backlog (completed-drop removed)', () {
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

      // Trip-sequence (Task 11): the completed tier + its cdt-drop are removed.
      // A closed opening whose vehicle still has dv set now derives `loading`
      // and surfaces in the backlog (ready to re-open) instead of being dropped.
      expect(feed.length, 1);
      expect(feed.first.tier, VehicleTier.loading);
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
          'tst': 'assigned',
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

  // ── buildVehicleFeed summary status-scope (warehouse-feed-summary-status) ──

  group('buildVehicleFeed summary status-scope', () {
    // Shared fixture: a stock_location with no driver (-> loading tier).
    // Tier is loading because dv is empty; this is intentional so we can test
    // the summary independently of tier transitions (loading has no date filter
    // on the completed-drop gate, so the entry always appears).
    final baseStock = <Map<String, dynamic>>[
      {'lv': 'V1', 'ln': 'B 1234 XY', 'dv': '', 'dn': ''},
    ];
    final catMap = <String, String>{
      'A1': 'returnable',
      'A2': 'returnable',
      'L1': 'consumable',
    };

    test('all tasks completed -> categorySummary is empty', () {
      // Two tasks, both completed. Before the fix this would yield
      // "2 returnable . 1 consumable"; after the fix, empty.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'completed',
          'it': [
            {'ii': 'A1'},
            {'ii': 'L1'},
          ],
        },
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'completed',
          'it': [
            {'ii': 'A2'},
          ],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      expect(feed.first.categorySummary, '',
          reason: 'Completed tasks must not contribute to summary');
    });

    test('mix of assigned + completed -> summary counts only assigned items', () {
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'assigned',
          'it': [
            {'ii': 'A1'},
          ],
        },
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'completed',
          'it': [
            {'ii': 'A2'},
            {'ii': 'L1'},
          ],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      // Only the assigned task's item A1 (returnable) appears.
      expect(feed.first.categorySummary, '1 returnable',
          reason: 'Only assigned task items contribute to summary');
    });

    test('tier and stop-progress unchanged by summary scope', () {
      // custody_confirmed + all tasks completed -> tier = returning.
      // Stop progress: done=2, total=2 (all tasks counted).
      // Summary: empty (no assigned tasks).
      final stock = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'B 1234 XY', 'dv': 'D1', 'dn': 'Driver'},
      ];
      final checks = <Map<String, dynamic>>[
        {'cty': 'opening', 'vv': 'V1', 'cst': 'custody_confirmed', 'cdt': '100'},
      ];
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'completed',
          'it': [
            {'ii': 'A1'},
          ],
        },
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'completed',
          'it': [
            {'ii': 'L1'},
          ],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      final entry = feed.first;
      // Tier: custody_confirmed + all completed + no closing -> returning
      expect(entry.tier, VehicleTier.returning,
          reason: 'Tier must see all statuses including completed');
      // Stop progress: both tasks count
      expect(entry.stopsTotal, 2,
          reason: 'Stop progress total must count ALL tasks');
      expect(entry.stopsDone, 2,
          reason: 'Stop progress done must count completed tasks');
      // Summary: empty because no assigned tasks
      expect(entry.categorySummary, '',
          reason: 'Summary must exclude completed tasks');
    });

    test('no tasks at all -> empty summary (regression guard)', () {
      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: [],
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      expect(feed.first.categorySummary, '',
          reason: 'No tasks -> no summary');
      expect(feed.first.stopsTotal, 0);
      expect(feed.first.stopsDone, 0);
    });

    // ── load_rejected exclusion ──────────────────────────────────────────────

    test('load_rejected task excluded from summary (raw-status filter)', () {
      // stopStatusOf('load_rejected') -> 'pending', which is the same result as
      // stopStatusOf('assigned') -> 'pending'. A normalized filter would wrongly
      // include load_rejected tasks in the summary. The raw comparison
      // (tst.trim() == kLoadableStatus) must drop load_rejected.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'load_rejected',
          'it': [
            {'ii': 'A1'},
            {'ii': 'L1'},
          ],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      expect(feed.first.categorySummary, '',
          reason: 'load_rejected must be excluded from summary by raw-tst filter, '
              'not the normalized stopStatusOf result');
      // Stop progress must still count the task in the total (it is not done).
      expect(feed.first.stopsTotal, 1,
          reason: 'load_rejected task contributes to stop total (tier uses full list)');
      expect(feed.first.stopsDone, 0,
          reason: 'load_rejected is not done/failed; stop-done unchanged');
    });

    // ── missing / empty tst ──────────────────────────────────────────────────

    test('task with absent tst key excluded from summary', () {
      // No 'tst' key at all: (doc[tstField] ?? '').toString().trim() -> ''.
      // '' != 'assigned' -> excluded.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          // deliberately no 'tst' key
          'it': [{'ii': 'A1'}],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.categorySummary, '',
          reason: 'Absent tst field resolves to empty string; not assigned -> excluded from summary');
    });

    test('task with tst=empty string excluded from summary', () {
      // tst: '' trims to ''; '' != 'assigned' -> excluded.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': '',
          'it': [{'ii': 'L1'}],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.categorySummary, '',
          reason: 'Empty tst string -> not assigned -> excluded from summary');
    });

    // ── whitespace / case sensitivity ────────────────────────────────────────

    test('tst=" assigned " (whitespace-padded) is trimmed and counted in summary', () {
      // kLoadableStatus comparison uses .trim() before ==; padding must be stripped.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': ' assigned ',
          'it': [{'ii': 'A1'}],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.categorySummary, '1 returnable',
          reason: 'Whitespace-padded "assigned" must be trimmed and matched; '
              'item must appear in summary');
    });

    test('tst="Assigned" (capital A) is NOT counted in summary (filter is case-sensitive)', () {
      // The filter is (t[tstField] ?? '').toString().trim() == kLoadableStatus.
      // kLoadableStatus = 'assigned' (lowercase). No toLower applied -> case-sensitive.
      // This documents current behavior: server must send lowercase 'assigned'.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'Assigned',
          'it': [{'ii': 'A1'}],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.categorySummary, '',
          reason: 'Filter is case-sensitive: "Assigned" != "assigned"; '
              'item must NOT appear in summary');
    });

    // ── multi-assigned aggregation + distinct dedup ──────────────────────────

    test('two assigned tasks sharing the same item id -> counted once (distinct dedup)', () {
      // A1 appears in both tasks; countDistinctItemsByCategory must dedup by Set.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'assigned',
          'it': [{'ii': 'A1'}],
        },
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'assigned',
          'it': [{'ii': 'A1'}],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.categorySummary, '1 returnable',
          reason: 'Same item id across two assigned tasks must be deduped to one');
    });

    test('two assigned tasks with distinct item ids -> both counted (cross-task aggregation)', () {
      // A1 and A2 are both returnable. Each appears in one task; together = 2 returnable.
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'assigned',
          'it': [{'ii': 'A1'}],
        },
        {
          'vv': 'V1',
          'tdt': '100',
          'tst': 'assigned',
          'it': [{'ii': 'A2'}],
        },
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: [],
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.categorySummary, '2 returnable',
          reason: 'Two assigned tasks with distinct ids must each contribute: '
              '2 distinct returnable items');
      // Stop progress must count both tasks in total.
      expect(feed.first.stopsTotal, 2,
          reason: 'Stop progress total must include all tasks regardless of status');
    });
  });

  // ── buildVehicleFeed trip scoping (task.tr vs opening __docId) ────────────

  group('buildVehicleFeed trip scoping', () {
    final baseStock = <Map<String, dynamic>>[
      {'lv': 'V1', 'ln': 'B 1234 XY', 'dv': '', 'dn': ''},
    ];
    final catMap = <String, String>{
      'A1': 'returnable',
      'A2': 'returnable',
      'L1': 'consumable',
    };

    test(
        'REGRESSION: closed trip-1 opening + new unstamped trip-2 tasks '
        '-> summary shows the new tasks', () {
      // Trip 1 done: opening OP1 closed, its tasks stamped tr=OP1, completed.
      // Trip 2: 3 new tasks created (tst=assigned, no tr yet), next opening
      // not created yet. Before the fix the feed scoped tasks to OP1 (the
      // closed opening still carried its __docId), so only trip-1's completed
      // tasks survived and the summary went empty -- the new tasks vanished
      // from the card.
      final checks = <Map<String, dynamic>>[
        {'cty': 'opening', 'vv': 'V1', 'cst': 'closed', 't': '100', '__docId': 'OP1'},
      ];
      final tasks = <Map<String, dynamic>>[
        {'vv': 'V1', 'tdt': '100', 'tst': 'completed', 'tr': 'OP1', 'it': [{'ii': 'A1'}]},
        {'vv': 'V1', 'tdt': '100', 'tst': 'assigned', 'it': [{'ii': 'A2'}]},
        {'vv': 'V1', 'tdt': '100', 'tst': 'assigned', 'it': [{'ii': 'L1'}]},
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      expect(feed.first.categorySummary, '1 returnable \u{00B7} 1 consumable',
          reason: 'New unstamped assigned tasks must appear when the only '
              'opening is closed (finished trip must not claim the scope)');
    });

    test('active opening scopes out other-trip stamped tasks, keeps unstamped', () {
      // Trip 2 opening OP2 active. Trip-1 tasks stamped OP1 must be dropped;
      // unstamped tasks (admin-created, not yet executed) and OP2-stamped
      // tasks both belong to the active trip.
      final checks = <Map<String, dynamic>>[
        {'cty': 'opening', 'vv': 'V1', 'cst': 'closed', 't': '100', '__docId': 'OP1'},
        {'cty': 'opening', 'vv': 'V1', 'cst': 'custody_confirmed', 't': '200', '__docId': 'OP2'},
      ];
      final stock = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'B 1234 XY', 'dv': 'D1', 'dn': 'Driver'},
      ];
      final tasks = <Map<String, dynamic>>[
        {'vv': 'V1', 'tdt': '100', 'tst': 'completed', 'tr': 'OP1', 'it': [{'ii': 'A1'}]},
        {'vv': 'V1', 'tdt': '100', 'tst': 'completed', 'tr': 'OP2', 'it': [{'ii': 'A2'}]},
        {'vv': 'V1', 'tdt': '100', 'tst': 'assigned', 'it': [{'ii': 'L1'}]},
      ];

      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.length, 1);
      final entry = feed.first;
      // Scope = OP2-stamped + unstamped: 2 tasks, 1 done.
      expect(entry.stopsTotal, 2,
          reason: 'OP1-stamped task excluded; OP2 + unstamped counted');
      expect(entry.stopsDone, 1);
      expect(entry.tier, VehicleTier.inRoute,
          reason: 'Unstamped assigned task keeps the trip open');
      expect(entry.categorySummary, '1 consumable',
          reason: 'Only the assigned unstamped task feeds the summary');
    });

    test('active opening + all tasks stamped other trip -> fallback to all (pre-CF)', () {
      final checks = <Map<String, dynamic>>[
        {'cty': 'opening', 'vv': 'V1', 'cst': 'custody_confirmed', 't': '200', '__docId': 'OP2'},
      ];
      final tasks = <Map<String, dynamic>>[
        {'vv': 'V1', 'tdt': '100', 'tst': 'assigned', 'tr': 'OP1', 'it': [{'ii': 'A1'}]},
      ];

      final feed = buildVehicleFeed(
        stockDocs: baseStock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: catMap,
        todayEpoch: '100',
      );

      expect(feed.first.stopsTotal, 1,
          reason: 'No task matches the active trip -> (vv, today) fallback keeps all');
      expect(feed.first.categorySummary, '1 returnable');
    });
  });
}
