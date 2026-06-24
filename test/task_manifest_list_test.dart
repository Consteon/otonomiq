// test/task_manifest_list_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── aggregateTaskDropPickup ──────────────────────────────────────────────

  group('aggregateTaskDropPickup', () {
    test('sums pd and pp from a normal it[] array', () {
      final doc = {
        'it': [
          {'in': 'Aqua', 'pd': '8', 'pp': '2'},
          {'in': 'LPG', 'pd': '5', 'pp': '0'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.itemLineCount, 2);
      expect(agg.totalDrop, 13);
      expect(agg.totalPickup, 2);
    });

    test('absent it field returns zeros', () {
      final agg = aggregateTaskDropPickup({'kn': 'Toko A'});
      expect(agg.itemLineCount, 0);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });

    test('non-List it field returns zeros', () {
      final agg = aggregateTaskDropPickup({'it': 'not a list'});
      expect(agg.itemLineCount, 0);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });

    test('non-Map entries inside it[] are skipped', () {
      final doc = {
        'it': [
          'rogue string',
          {'in': 'Aqua', 'pd': '3', 'pp': '1'},
          42,
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.itemLineCount, 1);
      expect(agg.totalDrop, 3);
      expect(agg.totalPickup, 1);
    });

    test('missing pd/pp fields default to 0', () {
      final doc = {
        'it': [
          {'in': 'Aqua'}, // no pd, no pp
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.itemLineCount, 1);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });

    test('non-numeric pd/pp parse to 0', () {
      final doc = {
        'it': [
          {'in': 'Aqua', 'pd': 'abc', 'pp': 'xyz'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });

    test('integer (not String) qty values work', () {
      final doc = {
        'it': [
          {'in': 'Aqua', 'pd': 6, 'pp': 3},
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.totalDrop, 6);
      expect(agg.totalPickup, 3);
    });

    test('custom field names honored', () {
      final doc = {
        'lines': [
          {'name': 'X', 'drop': '4', 'pick': '2'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc,
          itemsField: 'lines', dropField: 'drop', pickupField: 'pick');
      expect(agg.totalDrop, 4);
      expect(agg.totalPickup, 2);
    });

    test('empty it[] returns zeros with zero line count', () {
      final doc = {'it': <dynamic>[]};
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.itemLineCount, 0);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });
  });

  // ── aggregateItemCirculation ────────────────────────────────────────────

  group('aggregateItemCirculation', () {
    test('groups by item name and sums pd/pp across tasks', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'Aqua Galon', 'pd': '8', 'pp': '2'},
            {'in': 'LPG 3kg', 'pd': '5', 'pp': '0'},
          ],
        },
        {
          'it': [
            {'in': 'Aqua Galon', 'pd': '4', 'pp': '3'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items.length, 2);
      // First-seen order preserved
      expect(result.items[0].itemName, 'Aqua Galon');
      expect(result.items[0].totalDrop, 12); // 8 + 4
      expect(result.items[0].totalPickup, 5); // 2 + 3
      expect(result.items[1].itemName, 'LPG 3kg');
      expect(result.items[1].totalDrop, 5);
      expect(result.items[1].totalPickup, 0);
      // Grand totals
      expect(result.grandDrop, 17);
      expect(result.grandPickup, 5);
    });

    test('empty task list returns empty items and zero totals', () {
      final result = aggregateItemCirculation([]);
      expect(result.items, isEmpty);
      expect(result.grandDrop, 0);
      expect(result.grandPickup, 0);
    });

    test('tasks with absent/non-List it are skipped', () {
      final taskDocs = [
        {'kn': 'No items'},
        {'it': 'string not list'},
        {
          'it': [
            {'in': 'Aqua', 'pd': '3', 'pp': '1'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items.length, 1);
      expect(result.items[0].itemName, 'Aqua');
      expect(result.grandDrop, 3);
      expect(result.grandPickup, 1);
    });

    test('non-Map entries inside it[] are skipped', () {
      final taskDocs = [
        {
          'it': [42, 'rogue', {'in': 'Galon', 'pd': '7', 'pp': '1'}],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items.length, 1);
      expect(result.grandDrop, 7);
    });

    test('entries with empty/absent label are skipped', () {
      final taskDocs = [
        {
          'it': [
            {'in': '', 'pd': '5', 'pp': '5'},
            {'pd': '9', 'pp': '9'},
            {'in': 'Valid', 'pd': '2', 'pp': '1'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items.length, 1);
      expect(result.items[0].itemName, 'Valid');
    });

    test('non-numeric pd/pp parse to 0', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'Aqua', 'pd': 'abc', 'pp': 'xyz'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items[0].totalDrop, 0);
      expect(result.items[0].totalPickup, 0);
      expect(result.grandDrop, 0);
    });

    test('integer qty values work', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'LPG', 'pd': 10, 'pp': 3},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items[0].totalDrop, 10);
      expect(result.items[0].totalPickup, 3);
    });

    test('custom field names honored', () {
      final taskDocs = [
        {
          'lines': [
            {'name': 'X', 'drop': '4', 'pick': '2'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs,
          itemsField: 'lines',
          labelField: 'name',
          dropField: 'drop',
          pickupField: 'pick');
      expect(result.items.length, 1);
      expect(result.items[0].totalDrop, 4);
    });
  });

  // ── taskManifestList text parsing ───────────────────────────────────────

  group('taskManifestList text parsing', () {
    test('6-slot text parsed and length-guarded', () {
      final text = [
        'Task Manifest', // 0
        'task', // 1
        'item line', // 2
        'drop', // 3
        'pickup', // 4
        'tap untuk lihat detail', // 5
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 6);
      expect(arr.isNotEmpty ? arr[0] : '', 'Task Manifest');
      expect(arr.length > 5 ? arr[5] : '', 'tap untuk lihat detail');
    });

    test('short text array uses defaults via length guard', () {
      final arr = diamondTextToList('OnlyOne');
      expect(arr.isNotEmpty ? arr[0] : 'def', 'OnlyOne');
      expect(arr.length > 1 ? arr[1] : 'task', 'task');
      expect(arr.length > 5 ? arr[5] : 'tap', 'tap');
    });

    test('empty text yields single-empty-element array (diamondTextToList contract)', () {
      final arr = diamondTextToList('');
      // global `empty` sentinel is "--", not ""; '' takes the jsonDecode path
      // and yields [''] (length 1). Index 1+ still falls through to defaults.
      expect(arr.length > 1 ? arr[1] : 'task', 'task');
    });
  });

  // ── Manifest header string assembly ─────────────────────────────────────

  group('manifest header assembly', () {
    test('N task . M item line computed from task docs', () {
      final taskDocs = [
        {
          'tnm': 'T-001',
          'it': [
            {'in': 'A', 'pd': '1', 'pp': '0'},
            {'in': 'B', 'pd': '2', 'pp': '0'},
          ],
        },
        {
          'tnm': 'T-002',
          'it': [
            {'in': 'A', 'pd': '3', 'pp': '1'},
          ],
        },
      ];

      // Simulate the header computation
      int taskCount = taskDocs.length;
      int itemLineCount = 0;
      for (final doc in taskDocs) {
        final agg = aggregateTaskDropPickup(doc);
        itemLineCount += agg.itemLineCount;
      }
      expect(taskCount, 2);
      expect(itemLineCount, 3);
    });

    test('task with no it[] contributes 0 item lines', () {
      final taskDocs = [
        {'tnm': 'T-001', 'kn': 'Toko A'},
        {
          'tnm': 'T-002',
          'it': [
            {'in': 'X', 'pd': '1', 'pp': '0'},
          ],
        },
      ];
      int itemLineCount = 0;
      for (final doc in taskDocs) {
        itemLineCount += aggregateTaskDropPickup(doc).itemLineCount;
      }
      expect(itemLineCount, 1);
    });
  });

  // ── excludeByStatus + aggregateTaskDropPickup composition ────────────────

  group('excludeByStatus + aggregateTaskDropPickup composition', () {
    test('load_rejected task excluded from aggregation', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tnm': 'T-001', 'tst': 'assigned',
          'it': [{'in': 'Aqua', 'pd': '8', 'pp': '2'}],
        },
        {
          'tnm': 'T-002', 'tst': 'load_rejected',
          'it': [{'in': 'LPG', 'pd': '5', 'pp': '3'}],
        },
      ];

      final filtered = excludeByStatus(taskDocs, 'load_rejected');
      expect(filtered.length, 1);
      expect(filtered[0]['tnm'], 'T-001');

      int totalDrop = 0;
      int totalPickup = 0;
      int totalItemLines = 0;
      for (final doc in filtered) {
        final agg = aggregateTaskDropPickup(doc);
        totalDrop += agg.totalDrop;
        totalPickup += agg.totalPickup;
        totalItemLines += agg.itemLineCount;
      }
      // Only T-001 contributes: pd=8, pp=2, 1 item line
      expect(totalDrop, 8);
      expect(totalPickup, 2);
      expect(totalItemLines, 1);
    });

    test('empty excludeStatus includes all tasks in aggregation', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tnm': 'T-001', 'tst': 'assigned',
          'it': [{'in': 'Aqua', 'pd': '8', 'pp': '2'}],
        },
        {
          'tnm': 'T-002', 'tst': 'load_rejected',
          'it': [{'in': 'LPG', 'pd': '5', 'pp': '3'}],
        },
      ];

      final filtered = excludeByStatus(taskDocs, '');
      expect(filtered.length, 2);

      int totalDrop = 0;
      int totalPickup = 0;
      for (final doc in filtered) {
        final agg = aggregateTaskDropPickup(doc);
        totalDrop += agg.totalDrop;
        totalPickup += agg.totalPickup;
      }
      // Both tasks contribute: pd=8+5=13, pp=2+3=5
      expect(totalDrop, 13);
      expect(totalPickup, 5);
    });

    test('failed status is NOT excluded when excludeStatus is load_rejected', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tnm': 'T-001', 'tst': 'failed',
          'it': [{'in': 'Aqua', 'pd': '6', 'pp': '1'}],
        },
        {
          'tnm': 'T-002', 'tst': 'load_rejected',
          'it': [{'in': 'LPG', 'pd': '4', 'pp': '2'}],
        },
      ];

      final filtered = excludeByStatus(taskDocs, 'load_rejected');
      expect(filtered.length, 1);
      expect(filtered[0]['tst'], 'failed');

      final agg = aggregateTaskDropPickup(filtered[0]);
      expect(agg.totalDrop, 6);
      expect(agg.totalPickup, 1);
    });
  });
}
