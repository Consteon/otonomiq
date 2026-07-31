import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── aggregateGrandDropPickup ────────────────────────────────────────────

  group('aggregateGrandDropPickup', () {
    test('sums pd, pp, ad, ap across multiple docs', () {
      final docs = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Aqua', 'pd': '8', 'pp': '2', 'ad': '7', 'ap': '1'},
            {'in': 'LPG', 'pd': '5', 'pp': '0', 'ad': '5', 'ap': '0'},
          ],
        },
        {
          'it': [
            {'in': 'Aqua', 'pd': '3', 'pp': '1', 'ad': '3', 'ap': '1'},
          ],
        },
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 16); // 8+5+3
      expect(gdp.totalPickup, 3); // 2+0+1
      expect(gdp.actualDrop, 15); // 7+5+3
      expect(gdp.actualPickup, 2); // 1+0+1
    });

    test('empty docs returns zeros', () {
      final gdp = aggregateGrandDropPickup([]);
      expect(gdp.totalDrop, 0);
      expect(gdp.totalPickup, 0);
      expect(gdp.actualDrop, 0);
      expect(gdp.actualPickup, 0);
    });

    test('docs without it field returns zeros', () {
      final docs = <Map<String, dynamic>>[
        {'kn': 'Toko A'},
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 0);
      expect(gdp.totalPickup, 0);
      expect(gdp.actualDrop, 0);
      expect(gdp.actualPickup, 0);
    });

    test('non-List it field is skipped', () {
      final docs = <Map<String, dynamic>>[
        {'it': 'not a list'},
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 0);
    });

    test('non-Map entries inside it[] are skipped', () {
      final docs = <Map<String, dynamic>>[
        {
          'it': [
            'rogue string',
            {'pd': '3', 'pp': '1', 'ad': '2', 'ap': '0'},
            42,
          ],
        },
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 3);
      expect(gdp.totalPickup, 1);
      expect(gdp.actualDrop, 2);
      expect(gdp.actualPickup, 0);
    });

    test('missing ad/ap fields default to 0', () {
      final docs = <Map<String, dynamic>>[
        {
          'it': [
            {'pd': '5', 'pp': '2'},
          ],
        },
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 5);
      expect(gdp.totalPickup, 2);
      expect(gdp.actualDrop, 0);
      expect(gdp.actualPickup, 0);
    });

    test('non-numeric values parse to 0', () {
      final docs = <Map<String, dynamic>>[
        {
          'it': [
            {'pd': 'abc', 'pp': 'xyz', 'ad': 'nope', 'ap': ''},
          ],
        },
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 0);
      expect(gdp.totalPickup, 0);
      expect(gdp.actualDrop, 0);
      expect(gdp.actualPickup, 0);
    });

    test('integer (not String) qty values work', () {
      final docs = <Map<String, dynamic>>[
        {
          'it': [
            {'pd': 6, 'pp': 3, 'ad': 4, 'ap': 2},
          ],
        },
      ];
      final gdp = aggregateGrandDropPickup(docs);
      expect(gdp.totalDrop, 6);
      expect(gdp.totalPickup, 3);
      expect(gdp.actualDrop, 4);
      expect(gdp.actualPickup, 2);
    });

    test('custom field names work', () {
      final docs = <Map<String, dynamic>>[
        {
          'items': [
            {'d': '4', 'p': '2', 'xd': '3', 'xp': '1'},
          ],
        },
      ];
      final gdp = aggregateGrandDropPickup(
        docs,
        itemsField: 'items',
        dropField: 'd',
        pickupField: 'p',
        actualDropField: 'xd',
        actualPickupField: 'xp',
      );
      expect(gdp.totalDrop, 4);
      expect(gdp.totalPickup, 2);
      expect(gdp.actualDrop, 3);
      expect(gdp.actualPickup, 1);
    });
  });

  // ── load_rejected exclusion ────────────────────────────────────────────
  // These tests cover excludeByStatus composed with aggregateGrandDropPickup
  // and the stopStatusOf count loop. They do NOT exercise the widget's
  // _getFilteredTasks() wiring — that call site is verified by the
  // device-QA steps in the Verification section of the plan.

  group('load_rejected exclusion', () {
    test('rejected task pd/pp excluded from grand totals', () {
      // Spec §4: trip 2 tasks, 1 rejected → header counts only non-rejected.
      final docs = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'pd': '4', 'pp': '1', 'ad': '0', 'ap': '0'},
            {'pd': '2', 'pp': '0', 'ad': '0', 'ap': '0'},
          ],
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'pd': '6', 'pp': '3', 'ad': '0', 'ap': '0'},
          ],
        },
      ];
      final filtered = excludeByStatus(docs, kDefaultExcludeStatus);
      final gdp = aggregateGrandDropPickup(filtered);
      // Only the assigned task's items counted: pd 4+2=6, pp 1+0=1
      expect(gdp.totalDrop, 6);
      expect(gdp.totalPickup, 1);
      // Rejected task's pd=6, pp=3 are absent
    });

    test('rejected task excluded from stop count and progress', () {
      final docs = <Map<String, dynamic>>[
        {'tst': 'completed'},
        {'tst': 'load_rejected'},
        {'tst': 'assigned'},
      ];
      final filtered = excludeByStatus(docs, kDefaultExcludeStatus);
      expect(filtered.length, 2); // total stops (rejected excluded)

      // Mirrors build() lines 249-259
      int completedCount = 0;
      int failedCount = 0;
      for (final doc in filtered) {
        final status = stopStatusOf(doc);
        if (status == 'done') {
          completedCount++;
        } else if (status == 'failed') {
          failedCount++;
        }
      }
      expect(completedCount, 1);
      expect(failedCount, 0);
      // Progress: (1+0)/2 = 0.5 (widget line 299)
      final double progress = filtered.isNotEmpty
          ? (completedCount + failedCount) / filtered.length
          : 0;
      expect(progress, 0.5);
    });

    test('exclusion respects configured stateField', () {
      // route_feed_header reads stateField from component config.
      // When stateField = 'st', exclusion must compare doc['st'].
      final docs = <Map<String, dynamic>>[
        {'st': 'assigned'},
        {'st': 'load_rejected'},
      ];
      final filtered = excludeByStatus(docs, kDefaultExcludeStatus,
          statusField: 'st');
      expect(filtered.length, 1);
      expect(filtered[0]['st'], 'assigned');
    });
  });
}
