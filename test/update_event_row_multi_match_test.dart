import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';

/// Guards the multi-trip fix for `writeUpdateEventRow`:
/// a (cty, vv, cdt) search legitimately matches EVERY opening of the day once
/// a vehicle runs a second trip, so the write must target the active trip
/// instead of refusing (which cost 5 blocked sync cycles + a dropped record).
Map<String, dynamic> opening(String id, {required int t, String cst = ''}) => {
  '__docId': id,
  'cty': 'opening',
  'vv': 'MBL-01',
  'cdt': 1785862800000,
  'rt': 'pending',
  't': t,
  if (cst.isNotEmpty) 'cst': cst,
};

void main() {
  group('resolveAmbiguousEventTarget', () {
    test('empty -> null (caller keeps its own 0-match branch)', () {
      expect(resolveAmbiguousEventTarget([]), isNull);
    });

    test('single match -> that doc (unchanged behaviour)', () {
      final d = opening('a', t: 1);
      expect(resolveAmbiguousEventTarget([d])?['__docId'], 'a');
    });

    test('two openings same day -> newest non-closed (the live MBL-01 case)', () {
      final picked = resolveAmbiguousEventTarget([
        opening('trip1', t: 100, cst: 'closed'),
        opening('trip2', t: 200, cst: 'custody_confirmed'),
      ]);
      expect(picked?['__docId'], 'trip2');
    });

    test('order-independent: newest non-closed wins even when listed first', () {
      final picked = resolveAmbiguousEventTarget([
        opening('trip2', t: 200, cst: 'awaiting_custody'),
        opening('trip1', t: 100, cst: 'closed'),
      ]);
      expect(picked?['__docId'], 'trip2');
    });

    // Real otq-01 data, MBL-01 2026-08-05: trip-3 was CANCELLED (empty ie[])
    // and trip-4 closed 10s after the failing sync. `cancelled` is written
    // config-side and is not 'closed', so the old rule ranked the abandoned
    // trip as active.
    test('cancelled opening is terminal, never the active trip', () {
      final picked = resolveAmbiguousEventTarget([
        opening('trip3', t: 1785909160028, cst: 'cancelled'),
        opening('trip4', t: 1785920566099, cst: 'closed'),
      ]);
      expect(picked?['__docId'], 'trip4');
    });

    test('cancelled loses to a genuinely live newer trip', () {
      final picked = resolveAmbiguousEventTarget([
        opening('trip3', t: 100, cst: 'cancelled'),
        opening('trip4', t: 200, cst: 'custody_confirmed'),
      ]);
      expect(picked?['__docId'], 'trip4');
    });

    test('all closed -> newest overall (write follows read)', () {
      final picked = resolveAmbiguousEventTarget([
        opening('trip1', t: 100, cst: 'closed'),
        opening('trip2', t: 200, cst: 'closed'),
      ]);
      expect(picked?['__docId'], 'trip2');
    });

    test('non-opening in the match set -> null (genuine corrupt uniqueness)', () {
      final picked = resolveAmbiguousEventTarget([
        opening('trip1', t: 100),
        {'__docId': 'closing1', 'cty': 'closing', 't': 200},
      ]);
      expect(picked, isNull);
    });

    test('no cty at all -> null (not an opening-shaped collection)', () {
      final picked = resolveAmbiguousEventTarget([
        {'__docId': 'x', 't': 1},
        {'__docId': 'y', 't': 2},
      ]);
      expect(picked, isNull);
    });
  });

  group('isAmbiguousMatchResult', () {
    test('matches writeUpdateEventRow ambiguous output', () {
      expect(isAmbiguousMatchResult('error: 2 matches'), isTrue);
      expect(isAmbiguousMatchResult('  Error: 13 MATCHES  '), isTrue);
    });

    test('does not swallow retryable errors', () {
      expect(isAmbiguousMatchResult('error: bad collection "x"'), isFalse);
      expect(isAmbiguousMatchResult('error: no match'), isFalse);
      expect(isAmbiguousMatchResult('ok'), isFalse);
      // A network error mentioning "matches" is still retryable.
      expect(isAmbiguousMatchResult('error: nothing matches here'), isFalse);
    });
  });
}
