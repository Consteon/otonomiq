// test/custody_latest_match_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  group('pickNewestDoc', () {
    test('two closing docs same vehicle same day — largest t wins regardless of list order', () {
      // Trip-1 closing submitted at 09:00, trip-2 closing submitted at 14:00.
      final Map<String, dynamic> trip1Closing = {
        'cty': 'closing',
        'vv': 'V-001',
        'cdt': 1785690000000, // 2026-08-03 WIB midnight epoch-ms (int, == int.parse(today))
        't': 1785722400000, // 2026-08-03 09:00 WIB (02:00Z)
        'ip': [
          {'ii': 'ITEM-A', 'qt': 5}
        ],
      };
      final Map<String, dynamic> trip2Closing = {
        'cty': 'closing',
        'vv': 'V-001',
        'cdt': 1785690000000,
        't': 1785740400000, // 2026-08-03 14:00 WIB (07:00Z)
        'ip': [
          {'ii': 'ITEM-A', 'qt': 12}
        ],
      };

      // trip-2 is second in the list — must still win
      final result1 = pickNewestDoc([trip1Closing, trip2Closing]);
      expect(result1, same(trip2Closing));

      // trip-2 is first in the list — must still win (order-independent)
      final result2 = pickNewestDoc([trip2Closing, trip1Closing]);
      expect(result2, same(trip2Closing));
    });

    test('single match returns that doc (regression guard)', () {
      final Map<String, dynamic> onlyDoc = {
        'cty': 'closing',
        'vv': 'V-002',
        'cdt': 1785690000000,
        't': 1785722400000,
        'ip': [
          {'ii': 'ITEM-B', 'qt': 3}
        ],
      };
      expect(pickNewestDoc([onlyDoc]), same(onlyDoc));
    });

    test('all t equal returns the first doc (stable tie-break)', () {
      final Map<String, dynamic> docA = {
        'cty': 'opening',
        'vv': 'V-003',
        't': 1785722400000,
      };
      final Map<String, dynamic> docB = {
        'cty': 'opening',
        'vv': 'V-003',
        't': 1785722400000,
      };
      expect(pickNewestDoc([docA, docB]), same(docA));
    });

    test('t missing on every doc returns the first (today behavior preserved)', () {
      final Map<String, dynamic> docA = {
        'cty': 'closing',
        'vv': 'V-004',
        'cdt': 1785690000000,
      };
      final Map<String, dynamic> docB = {
        'cty': 'closing',
        'vv': 'V-004',
        'cdt': 1785690000000,
      };
      // Both default to t=0; first-max-wins returns docA
      expect(pickNewestDoc([docA, docB]), same(docA));
    });

    test('t as String is parsed to a number and wins on magnitude', () {
      // The winner carries its t as a String; the loser as an int. The String
      // must be int.tryParse'd and compared by magnitude — if String parsing
      // silently failed it would read as 0 and this (larger, later) doc would
      // wrongly lose to the smaller int, so the assertion catches that break.
      final Map<String, dynamic> docLargeStringT = {
        'cty': 'closing',
        'vv': 'V-005',
        't': '1785740400000', // 14:00 WIB, as a String — must win
      };
      final Map<String, dynamic> docSmallIntT = {
        'cty': 'closing',
        'vv': 'V-005',
        't': 1785722400000, // 09:00 WIB, as an int
      };
      expect(pickNewestDoc([docLargeStringT, docSmallIntT]), same(docLargeStringT));
    });

    test('empty list returns null', () {
      expect(pickNewestDoc([]), isNull);
    });

    test('one doc has t:null and another a real t — real t wins', () {
      final Map<String, dynamic> docNullT = {
        'cty': 'closing',
        'vv': 'V-006',
        't': null,
        'ip': [],
      };
      final Map<String, dynamic> docRealT = {
        'cty': 'closing',
        'vv': 'V-006',
        't': 1785740400000,
        'ip': [
          {'ii': 'ITEM-C', 'qt': 7}
        ],
      };
      expect(pickNewestDoc([docNullT, docRealT]), same(docRealT));
    });
  });
}
