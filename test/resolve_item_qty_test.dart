import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/task_manifest_list.dart';

void main() {
  // ── resolveItemQty ─────────────────────────────────────────────────────

  group('resolveItemQty', () {
    test('actual present and numeric returns actual', () {
      final e = {'pd': '10', 'ad': '7'};
      expect(resolveItemQty(e, 'pd', 'ad'), 7);
    });

    test('actual zero returns 0 (not plan)', () {
      final e = {'pd': '10', 'ad': '0'};
      expect(resolveItemQty(e, 'pd', 'ad'), 0);
    });

    test('actual absent falls back to plan', () {
      final e = {'pd': '10'};
      expect(resolveItemQty(e, 'pd', 'ad'), 10);
    });

    test('actual null falls back to plan (load-bearing for toItMap shape)', () {
      final e = {'pd': '5', 'ad': null};
      expect(resolveItemQty(e, 'pd', 'ad'), 5);
    });

    test('actual empty string falls back to plan', () {
      final e = {'pd': '8', 'ad': ''};
      expect(resolveItemQty(e, 'pd', 'ad'), 8);
    });

    test('actual whitespace-only falls back to plan', () {
      final e = {'pd': '8', 'ad': '  '};
      expect(resolveItemQty(e, 'pd', 'ad'), 8);
    });

    test('actual unparseable returns 0', () {
      final e = {'pd': '10', 'ad': 'abc'};
      expect(resolveItemQty(e, 'pd', 'ad'), 0);
    });

    test('both absent returns 0', () {
      final e = <String, dynamic>{};
      expect(resolveItemQty(e, 'pd', 'ad'), 0);
    });

    test('plan absent and actual absent returns 0', () {
      final e = {'other': '99'};
      expect(resolveItemQty(e, 'pd', 'ad'), 0);
    });

    test('actual is int (not string) parses correctly', () {
      final e = {'pd': '10', 'ad': 3};
      expect(resolveItemQty(e, 'pd', 'ad'), 3);
    });
  });

  // ── aggregateItemCirculation with actuals ──────────────────────────────

  group('aggregateItemCirculation actual-over-plan', () {
    test('uses actual when present, plan when absent', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            // Task 1: Aqua has actuals, LPG has only plan
            {'in': 'Aqua', 'pd': '8', 'pp': '4', 'ad': '6', 'ap': '2'},
            {'in': 'LPG', 'pd': '5', 'pp': '0'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      // Aqua: drop=6(actual), pickup=2(actual)
      expect(result.items[0].totalDrop, 6);
      expect(result.items[0].totalPickup, 2);
      // LPG: drop=5(plan fallback), pickup=0(plan fallback)
      expect(result.items[1].totalDrop, 5);
      expect(result.items[1].totalPickup, 0);
    });

    test('actual zero does not fall back to plan', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'pd': '4', 'pp': '4', 'ad': '0', 'ap': '0'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items[0].totalDrop, 0);
      expect(result.items[0].totalPickup, 0);
      expect(result.grandDrop, 0);
      expect(result.grandPickup, 0);
    });

    test('production pre-execution shape: ad/ap null falls back to plan', () {
      // This is the shape admin_create_task_support.dart:87-102 toItMap()
      // produces: ad and ap keys present but null.
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'pd': '8', 'pp': '4', 'ad': null, 'ap': null},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.items[0].totalDrop, 8);
      expect(result.items[0].totalPickup, 4);
      expect(result.grandDrop, 8);
      expect(result.grandPickup, 4);
    });

    test('grand totals reflect actuals', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'A', 'pd': '10', 'pp': '4', 'ad': '8', 'ap': '2'},
            {'in': 'B', 'pd': '5', 'pp': '2'},
          ],
        },
        {
          'it': [
            {'in': 'A', 'pd': '7', 'pp': '3', 'ad': '7', 'ap': '3'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      // A: 8+7=15 drop, 2+3=5 pickup (actuals)
      // B: 5 drop, 2 pickup (plan fallback)
      expect(result.grandDrop, 20);
      expect(result.grandPickup, 7);
    });
  });

  // ── aggregateTxCirculation with actuals ────────────────────────────────

  group('aggregateTxCirculation actual-over-plan', () {
    test('deliver flow uses actual drop/pickup', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'tx': 'deliver', 'pd': '8', 'pp': '4', 'ad': '6', 'ap': '2'},
          ],
        },
      ];
      final result = aggregateTxCirculation(taskDocs);
      expect(result.items[0].drop, 6);
      expect(result.items[0].pickup, 2);
    });

    test('actual zero pickup (literal section 1 case)', () {
      // Spec section 1: plan pickup 4, actual pickup 0 -> display 0
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'tx': 'deliver', 'pd': '2', 'pp': '4', 'ad': '2', 'ap': '0'},
          ],
        },
      ];
      final result = aggregateTxCirculation(taskDocs);
      expect(result.items[0].drop, 2);
      expect(result.items[0].pickup, 0);
      expect(result.grandDrop, 2);
      expect(result.grandPickup, 0);
    });

    test('sale flow uses actual sale', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Widget', 'tx': 'sale', 'ps': '10', 'as': '10'},
          ],
        },
      ];
      final result = aggregateTxCirculation(taskDocs);
      expect(result.items[0].sale, 10);
      expect(result.grandSale, 10);
    });

    test('empty tx defaults to deliver flow with actuals', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'pd': '10', 'pp': '4', 'ad': '8', 'ap': '2'},
          ],
        },
      ];
      final result = aggregateTxCirculation(taskDocs);
      expect(result.items[0].drop, 8);
      expect(result.items[0].pickup, 2);
    });

    test('pre-execution items with no actuals fall back to plan', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'tx': 'deliver', 'pd': '8', 'pp': '4'},
            {'in': 'Widget', 'tx': 'sale', 'ps': '10'},
          ],
        },
      ];
      final result = aggregateTxCirculation(taskDocs);
      expect(result.items[0].drop, 8);
      expect(result.items[0].pickup, 4);
      expect(result.items[1].sale, 10);
    });
  });

  // ── aggregateTaskDropPickup with actuals ───────────────────────────────

  group('aggregateTaskDropPickup actual-over-plan', () {
    test('uses actual when present', () {
      final doc = <String, dynamic>{
        'it': [
          {'in': 'Aqua', 'pd': '8', 'pp': '4', 'ad': '6', 'ap': '2'},
          {'in': 'LPG', 'pd': '5', 'pp': '0'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      // Aqua: 6+2, LPG: 5+0
      expect(agg.totalDrop, 11);
      expect(agg.totalPickup, 2);
      expect(agg.itemLineCount, 2);
    });

    test('no actuals falls back to plan (legacy shape)', () {
      final doc = <String, dynamic>{
        'it': [
          {'in': 'Aqua', 'pd': '8', 'pp': '4'},
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.totalDrop, 8);
      expect(agg.totalPickup, 4);
    });

    test('production pre-execution shape: ad/ap null falls back to plan', () {
      // This is the shape toItMap() produces at task creation.
      final doc = <String, dynamic>{
        'it': [
          {'in': 'Aqua', 'pd': '8', 'pp': '4', 'ad': null, 'ap': null},
          {'in': 'LPG', 'pd': '3', 'pp': '1', 'ad': null, 'ap': null},
        ],
      };
      final agg = aggregateTaskDropPickup(doc);
      expect(agg.totalDrop, 11);
      expect(agg.totalPickup, 5);
      expect(agg.itemLineCount, 2);
    });
  });

  // ── buildItemAnnotations with actuals ──────────────────────────────────

  group('buildItemAnnotations actual-over-plan', () {
    test('legacy mode uses actual when present', () {
      final entry = {'pd': '8', 'pp': '4', 'ad': '6', 'ap': '2'};
      final annotations = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
      );
      expect(annotations.length, 2);
      expect(annotations[0], contains('6'));
      expect(annotations[1], contains('2'));
    });

    test('legacy mode falls back to plan when actual absent', () {
      final entry = {'pd': '8', 'pp': '4'};
      final annotations = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
      );
      expect(annotations.length, 2);
      expect(annotations[0], contains('8'));
      expect(annotations[1], contains('4'));
    });

    test('tx deliver uses actual', () {
      final entry = {'pd': '8', 'pp': '4', 'ad': '6', 'ap': '2', 'tx': 'deliver'};
      final annotations = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
      );
      expect(annotations.length, 2);
      expect(annotations[0], contains('6'));
      expect(annotations[1], contains('2'));
    });

    test('tx sale uses actual', () {
      final entry = {'ps': '10', 'as': '10', 'tx': 'sale'};
      final annotations = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: 'pd',
        pickupField: 'pp',
        dropLabel: 'drop',
        pickupLabel: 'pickup',
        txField: 'tx',
        saleField: 'ps',
        saleLabel: 'Jual',
      );
      expect(annotations.length, 1);
      expect(annotations[0], contains('10'));
    });
  });
}
