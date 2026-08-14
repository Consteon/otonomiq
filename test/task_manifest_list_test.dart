// test/task_manifest_list_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/task_manifest_list.dart';

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
      expect(agg.totalSale, 0);
      expect(agg.totalBuy, 0);
      expect(agg.totalRefill, 0);
    });

    test('non-List it field returns zeros', () {
      final agg = aggregateTaskDropPickup({'it': 'not a list'});
      expect(agg.itemLineCount, 0);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
      expect(agg.totalSale, 0);
      expect(agg.totalBuy, 0);
      expect(agg.totalRefill, 0);
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

  // ── aggregateTaskDropPickup tx-aware ───────────────────────────────────

  group('aggregateTaskDropPickup tx-aware', () {
    test('mixed task sums per type', () {
      final doc = {
        'it': [
          {'in': 'Galon', 'tx': 'deliver', 'pd': '8', 'pp': '2'},
          {'in': 'Aqua 330ml', 'tx': 'sale', 'ps': '5'},
          {'in': 'Tabung', 'tx': 'purchase', 'pb': '3'},
          {'in': 'Botol', 'tx': 'refill', 'pr': '4'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc,
          txField: 'tx',
          saleField: 'ps',
          buyField: 'pb',
          refillField: 'pr');
      expect(agg.itemLineCount, 4);
      expect(agg.totalDrop, 8);
      expect(agg.totalPickup, 2);
      expect(agg.totalSale, 5);
      expect(agg.totalBuy, 3);
      expect(agg.totalRefill, 4);
    });

    test('all-sale task produces zero drop/pickup', () {
      final doc = {
        'it': [
          {'in': 'Aqua 330ml', 'tx': 'sale', 'ps': '10'},
          {'in': 'Aqua 1500ml', 'tx': 'sale', 'ps': '5'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc,
          txField: 'tx', saleField: 'ps');
      expect(agg.itemLineCount, 2);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
      expect(agg.totalSale, 15);
    });

    test('unknown tx falls to drop/pickup', () {
      final doc = {
        'it': [
          {'in': 'Mystery', 'tx': 'unknown_type', 'pd': '7', 'pp': '3'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc, txField: 'tx');
      expect(agg.totalDrop, 7);
      expect(agg.totalPickup, 3);
      expect(agg.totalSale, 0);
    });

    test('absent tx value falls to drop/pickup', () {
      // Item has no tx field at all -- default: case triggers.
      final doc = {
        'it': [
          {'in': 'NoTx', 'pd': '6', 'pp': '1'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc, txField: 'tx');
      expect(agg.totalDrop, 6);
      expect(agg.totalPickup, 1);
      expect(agg.totalSale, 0);
    });

    test('legacy mode (txField empty) sums all pd/pp, sale/buy/refill stay zero', () {
      final doc = {
        'it': [
          {'in': 'A', 'tx': 'sale', 'pd': '0', 'pp': '0', 'ps': '5'},
          {'in': 'B', 'tx': 'deliver', 'pd': '3', 'pp': '1'},
        ],
      };
      // No txField -> legacy mode
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.totalDrop, 3); // pd from both items (0 + 3)
      expect(agg.totalPickup, 1);
      expect(agg.totalSale, 0); // not computed in legacy mode
    });

    test('sale with empty saleField is ignored', () {
      final doc = {
        'it': [
          {'in': 'Aqua', 'tx': 'sale', 'ps': '5'},
        ],
      };
      // txField set but saleField empty -> sale qty not summed
      final agg = aggregateTaskDropPickup(doc, txField: 'tx');
      expect(agg.totalSale, 0);
    });

    test('actual-over-plan works for sale fields', () {
      final doc = {
        'it': [
          {'in': 'Aqua', 'tx': 'sale', 'ps': '10', 'as': '7'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc,
          txField: 'tx', saleField: 'ps');
      // resolveItemQty prefers actual (as=7) over plan (ps=10)
      expect(agg.totalSale, 7);
    });

    test('integer qty values work in tx-aware mode', () {
      final doc = {
        'it': [
          {'in': 'Aqua', 'tx': 'deliver', 'pd': 8, 'pp': 3},
          {'in': 'Cola', 'tx': 'sale', 'ps': 5},
        ],
      };
      final agg = aggregateTaskDropPickup(doc,
          txField: 'tx', saleField: 'ps');
      expect(agg.totalDrop, 8);
      expect(agg.totalSale, 5);
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

  // ── draft source: synthetic task from draftToItArray ─────────────────────

  group('draft source: synthetic task from draftToItArray', () {
    test('mixed-tx draft wrapped as synthetic task aggregates only deliver pd/pp', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'Galon', tx: 'deliver', pd: 10, pp: 5),
        DraftItem(ii: 'b', itemName: 'LPG', tx: 'sale', ps: 3),
        DraftItem(ii: 'c', itemName: 'Tabung', tx: 'purchase', pb: 2),
        DraftItem(ii: 'd', itemName: 'Air', tx: 'refill', pr: 4),
      ];
      final itArray = AdminCreateTaskSupport.draftToItArray(items);
      final syntheticTask = <String, dynamic>{'it': itArray};
      final agg = aggregateTaskDropPickup(syntheticTask);
      // Only deliver items contribute to pd/pp aggregates
      expect(agg.itemLineCount, 4);
      expect(agg.totalDrop, 10);
      expect(agg.totalPickup, 5);
    });

    test('all-deliver draft aggregates pd and pp correctly', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'Galon', tx: 'deliver', pd: 8, pp: 3),
        DraftItem(ii: 'b', itemName: 'LPG', tx: 'deliver', pd: 5, pp: 2),
      ];
      final itArray = AdminCreateTaskSupport.draftToItArray(items);
      final syntheticTask = <String, dynamic>{'it': itArray};
      final agg = aggregateTaskDropPickup(syntheticTask);
      expect(agg.itemLineCount, 2);
      expect(agg.totalDrop, 13);
      expect(agg.totalPickup, 5);
    });

    test('all-sale draft produces zero drop/pickup aggregates', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 10),
        DraftItem(ii: 'b', itemName: 'LPG', tx: 'sale', ps: 5),
      ];
      final itArray = AdminCreateTaskSupport.draftToItArray(items);
      final syntheticTask = <String, dynamic>{'it': itArray};
      final agg = aggregateTaskDropPickup(syntheticTask);
      expect(agg.itemLineCount, 2);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });

    test('empty draft produces empty itArray and zero aggregates', () {
      final itArray = AdminCreateTaskSupport.draftToItArray([]);
      expect(itArray, isEmpty);
      final syntheticTask = <String, dynamic>{'it': itArray};
      final agg = aggregateTaskDropPickup(syntheticTask);
      expect(agg.itemLineCount, 0);
      expect(agg.totalDrop, 0);
      expect(agg.totalPickup, 0);
    });
  });

  // ── draft source: buildItemAnnotations ──────────────────────────────────

  group('draft source: buildItemAnnotations', () {
    test('deliver entry shows drop and pickup arrows', () {
      final entry = {'tx': 'deliver', 'pd': '10', 'pp': '5'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(result, ['\u{2193} 10 drop', '\u{2191} 5 pickup']);
    });

    test('deliver entry with zero pickup shows only drop', () {
      final entry = {'tx': 'deliver', 'pd': '8', 'pp': '0'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(result, ['\u{2193} 8 drop']);
    });

    test('sale entry shows qty with config sale label (Jual)', () {
      // W1: sale label is config-driven; _buildDraftMode supplies _t(4,'Jual').
      final entry = {'tx': 'sale', 'ps': '3'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: 'Jual',
      );
      expect(result, ['\u{2192} 3 Jual']);
    });

    test('purchase entry shows qty with config buy label (Beli)', () {
      // W1: purchase label is config-driven; _buildDraftMode supplies _t(5,'Beli').
      final entry = {'tx': 'purchase', 'pb': '7'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        buyField: 'pb',
        buyLabel: 'Beli',
      );
      expect(result, ['\u{2192} 7 Beli']);
    });

    test('refill entry shows qty with config refill label (Refill)', () {
      // W1: refill label is config-driven; _buildDraftMode supplies _t(6,'Refill').
      final entry = {'tx': 'refill', 'pr': '4'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        refillField: 'pr',
        refillLabel: 'Refill',
      );
      expect(result, ['\u{2192} 4 Refill']);
    });

    test('unknown tx falls through to drop/pickup', () {
      final entry = {'tx': 'unknown', 'pd': '3', 'pp': '1'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(result, ['\u{2193} 3 drop', '\u{2191} 1 pickup']);
    });

    test('all-zero quantities produce empty annotations', () {
      final entry = {'tx': 'deliver', 'pd': '0', 'pp': '0'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(result, isEmpty);
    });

    test('sale entry with zero qty produces empty annotations', () {
      final entry = {'tx': 'sale', 'ps': '0'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: 'Jual',
      );
      expect(result, isEmpty);
    });

    test('legacy mode (txField empty) reads drop/pickup only', () {
      // Sale entry with non-zero ps, but txField empty -> legacy mode ignores ps
      final entry = {'tx': 'sale', 'pd': '0', 'pp': '0', 'ps': '5'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        // txField defaults to '' -> legacy mode
      );
      expect(result, isEmpty); // pd=0, pp=0 -> no annotations
    });

    test('legacy mode with drop/pickup values works like existing behavior', () {
      final entry = {'pd': '6', 'pp': '2'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
      );
      expect(result, ['\u{2193} 6 drop', '\u{2191} 2 pickup']);
    });

    test('missing fields default to 0 safely', () {
      final entry = <String, dynamic>{'tx': 'deliver'}; // no pd, no pp
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(result, isEmpty);
    });

    test('integer qty values work (not just strings)', () {
      final entry = {'tx': 'deliver', 'pd': 8, 'pp': 3};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(result, ['\u{2193} 8 drop', '\u{2191} 3 pickup']);
    });

    test('sale entry with saleField empty produces no annotation', () {
      final entry = {'tx': 'sale', 'ps': '5'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        // saleField defaults to '' -> no sale annotation
      );
      expect(result, isEmpty);
    });

    test('custom field names honored', () {
      final entry = {'kind': 'deliver', 'planned_drop': '4', 'planned_pick': '2'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'planned_drop',
        pickupField: 'planned_pick',
        dropLabel: 'kirim',
        pickupLabel: 'ambil',
        txField: 'kind',
      );
      expect(result, ['\u{2193} 4 kirim', '\u{2191} 2 ambil']);
    });
  });

  // ── collection-mode annotation rendering ───────────────────────────────

  group('collection-mode annotation rendering', () {
    test('sale entry with arrow prefix and Jual label', () {
      final entry = {'tx': 'sale', 'ps': '3'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'antar',
        pickupLabel: 'ambil',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: 'Jual',
      );
      expect(result, ['\u{2192} 3 Jual']);
    });

    test('buy entry with arrow prefix and Beli label', () {
      final entry = {'tx': 'purchase', 'pb': '7'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'antar',
        pickupLabel: 'ambil',
        txField: 'tx',
        buyField: 'pb',
        buyLabel: 'Beli',
      );
      expect(result, ['\u{2192} 7 Beli']);
    });

    test('refill entry with arrow prefix and Tukar label', () {
      final entry = {'tx': 'refill', 'pr': '4'};
      final result = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'antar',
        pickupLabel: 'ambil',
        txField: 'tx',
        refillField: 'pr',
        refillLabel: 'Tukar',
      );
      expect(result, ['\u{2192} 4 Tukar']);
    });

    test('mixed task: deliver + sale items produce correct annotations', () {
      final deliverEntry = {'tx': 'deliver', 'pd': '4', 'pp': '4'};
      final saleEntry = {'tx': 'sale', 'ps': '3'};

      final deliverResult = TaskManifestList.buildItemAnnotations(
        deliverEntry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'antar',
        pickupLabel: 'ambil',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: 'jual',
      );
      expect(deliverResult, ['\u{2193} 4 antar', '\u{2191} 4 ambil']);

      final saleResult = TaskManifestList.buildItemAnnotations(
        saleEntry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'antar',
        pickupLabel: 'ambil',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: 'jual',
      );
      expect(saleResult, ['\u{2192} 3 jual']);
    });
  });

  // ── draft source: text slot mapping ─────────────────────────────────────

  group('draft source: text slot mapping', () {
    test('draft config text parses to correct slot mapping', () {
      final text = 'Item Order\u{25C6}item line\u{25C6}drop\u{25C6}pickup\u{25C6}';
      final arr = diamondTextToList(text);
      // Draft slots: [0] title, [1] count unit, [2] drop label, [3] pickup label, [4] ''
      expect(arr.isNotEmpty ? arr[0] : '', 'Item Order');
      expect(arr.length > 1 ? arr[1] : 'item line', 'item line');
      expect(arr.length > 2 ? arr[2] : 'drop', 'drop');
      expect(arr.length > 3 ? arr[3] : 'pickup', 'pickup');
    });

    test('empty draft text: slot 0 is the single empty element, slots 1+ default', () {
      // diamondTextToList('') yields [''] (length 1, NOT []). The length guard
      // therefore returns '' for index 0 (the single empty element); the
      // defaults only kick in at index >= 1. Mirrors the existing
      // diamondTextToList('') contract test in this file (and the documented
      // gotcha). The plan's original assertion expected arr[0] isNotEmpty,
      // which contradicts this contract -- corrected here.
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.isNotEmpty ? arr[0] : 'Item Order', ''); // index 0 = '' (no default)
      expect(arr.length > 1 ? arr[1] : 'item line', 'item line');
      expect(arr.length > 2 ? arr[2] : 'drop', 'drop');
      expect(arr.length > 3 ? arr[3] : 'pickup', 'pickup');
    });

    test('live 4-diamond draft text: slot 4 is trailing-empty, slots 5/6 default', () {
      // W1 nuance: live op1Screen P4 text "Item Order◆item line◆drop◆pickup◆"
      // has a TRAILING diamond, so diamondTextToList yields 5 segments (the 5th
      // being the trailing empty string). Slot 4 (sale label) therefore resolves
      // to '' here, while slots 5/6 (buy/refill) are out-of-range and fall back
      // to the Indonesian defaults. _t(4,'Jual') returns '' for this exact text;
      // _t(5,'Beli')/_t(6,'Refill') return their defaults.
      final text = 'Item Order\u{25C6}item line\u{25C6}drop\u{25C6}pickup\u{25C6}';
      final arr = diamondTextToList(text);
      expect(arr.length, 5);
      expect(arr.length > 4 ? arr[4] : 'Jual', ''); // trailing empty, NOT 'Jual'
      expect(arr.length > 5 ? arr[5] : 'Beli', 'Beli'); // out-of-range -> default
      expect(arr.length > 6 ? arr[6] : 'Refill', 'Refill'); // out-of-range -> default
    });

    test('empty-aware label (_tOr) resolves trailing-empty slot 4 so sale renders "3 Jual"', () {
      // W-1 fix: _buildDraftMode reads the sale/buy/refill labels via the
      // empty-aware _tOr helper. Under the live text the trailing diamond makes
      // slot 4 a trailing-empty string, so raw _t(4,'Jual') returns '' (in range
      // -> no default) which previously rendered a bare "3". _tOr falls back to
      // the default, so the sale line now renders "3 Jual". This mirrors _tOr's
      // logic (private helper, not directly callable from the test).
      final text = 'Item Order\u{25C6}item line\u{25C6}drop\u{25C6}pickup\u{25C6}';
      final arr = diamondTextToList(text);

      // Mirror _t (raw): in-range slot returned verbatim, even when empty.
      final String rawSlot4 = arr.length > 4 ? arr[4] : 'Jual';
      expect(rawSlot4, ''); // raw _t fact -- still the bug input

      // Mirror _tOr (empty-aware): empty slot falls back to the default.
      final String saleLabel = rawSlot4.isEmpty ? 'Jual' : rawSlot4;
      expect(saleLabel, 'Jual');

      // The resolved label now renders through buildItemAnnotations: no bare "3".
      final result = TaskManifestList.buildItemAnnotations(
        {'tx': 'sale', 'ps': '3'},
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: saleLabel,
      );
      expect(result, ['\u{2192} 3 Jual']);
    });
  });

  // ── isTxAwareConfig ────────────────────────────────────────────────────

  group('isTxAwareConfig', () {
    test('returns false for null component', () {
      expect(TaskManifestList.isTxAwareConfig(null), false);
    });

    test('returns false for non-Map component', () {
      expect(TaskManifestList.isTxAwareConfig('string'), false);
    });

    test('returns false when none of the four keys are present', () {
      expect(TaskManifestList.isTxAwareConfig({'type': 'task_manifest_list'}), false);
    });

    test('returns false when all four keys are empty strings', () {
      expect(TaskManifestList.isTxAwareConfig({
        'txField': '',
        'saleField': '',
        'buyField': '',
        'refillField': '',
      }), false);
    });

    test('returns false when all four keys are whitespace-only', () {
      expect(TaskManifestList.isTxAwareConfig({
        'txField': '  ',
        'saleField': ' ',
        'buyField': '   ',
        'refillField': '\t',
      }), false);
    });

    test('returns true when only saleField is set', () {
      expect(TaskManifestList.isTxAwareConfig({'saleField': 'ps'}), true);
    });

    test('returns true when only buyField is set', () {
      expect(TaskManifestList.isTxAwareConfig({'buyField': 'pb'}), true);
    });

    test('returns true when only refillField is set', () {
      expect(TaskManifestList.isTxAwareConfig({'refillField': 'pr'}), true);
    });

    test('returns true when only txField is set', () {
      expect(TaskManifestList.isTxAwareConfig({'txField': 'tx'}), true);
    });

    test('returns true when saleField + buyField + refillField set (no txField)', () {
      // This is the D1348 config shape: saleField/buyField/refillField
      // without txField. The gate must still arm.
      expect(TaskManifestList.isTxAwareConfig({
        'saleField': 'ps',
        'buyField': 'pb',
        'refillField': 'pr',
      }), true);
    });
  });
}
