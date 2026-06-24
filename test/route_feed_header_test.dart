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
}
