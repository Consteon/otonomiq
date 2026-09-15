import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // The guard that keeps an oversized write out of the offline overlay, where
  // it becomes `SQLiteBlobTooBigException` -> AsyncQueue panic -> a FATAL that
  // repeats on every launch. Too loose and the poison write still lands; too
  // tight and ordinary writes are silently dropped.

  String chars(int n) => 'x' * n;

  test('ordinary small write passes', () {
    expect(fsPayloadTooBig({'h': '[]', 'i': '{}'}), isFalse);
  });

  test('exactly at the budget still passes', () {
    expect(fsPayloadTooBig({'h': chars(fsMaxPayloadChars)}), isFalse);
  });

  test('one char over the budget is rejected', () {
    expect(fsPayloadTooBig({'h': chars(fsMaxPayloadChars + 1)}), isTrue);
  });

  test('the budget is the SUM across fields, not per field', () {
    // The Proxy backup writes 'h' and 'i' in one update; either alone fits.
    final int half = (fsMaxPayloadChars ~/ 2) + 1;
    expect(fsPayloadTooBig({'h': chars(half)}), isFalse);
    expect(fsPayloadTooBig({'h': chars(half), 'i': chars(half)}), isTrue);
  });

  test('the budget stays under the 1 MiB Firestore document limit', () {
    // Field names and encoding overhead are counted by the server on top of
    // the values, so the budget must leave headroom.
    expect(fsMaxPayloadChars, lessThan(1048576));
  });

  test('empty map passes (safeFsUpdate has its own empty guard)', () {
    expect(fsPayloadTooBig(<String, dynamic>{}), isFalse);
  });

  test('KNOWN BLIND SPOT: only String values are measured', () {
    // Every oversized payload this app produces is a jsonEncode'd String
    // ('h', 'i', 'h2', 'i2'). A huge List/Map value would slip through — if a
    // caller ever writes one, widen the measurement, do not widen the budget.
    expect(
      fsPayloadTooBig({'rows': List<String>.filled(20, 'y' * 100000)}),
      isFalse,
    );
  });
}
