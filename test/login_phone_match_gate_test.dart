import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

/// Local mirror of the gate decision in getFirestoreUserData (api.dart).
///
/// Returns true when login should PROCEED (gate passes).
/// Returns false when login should FAIL with PhoneNotMatch (status 3).
///
/// Exactly replicates the production logic:
///   final storedI = (user['i'] ?? '').toString().trim();
///   if (storedI.isNotEmpty &&
///       phoneCanonical62(inv) != phoneCanonical62(storedI)) {
///     return 3; // fail
///   }
bool gatePassesMirror(String rawInput, String storedI) {
  final stored = storedI.trim();
  if (stored.isEmpty) return true; // gate skipped
  return phoneCanonical62(rawInput) == phoneCanonical62(stored);
}

void main() {
  group('phone match gate — core decision matrix', () {
    test('exact match (both 08xx) -> pass', () {
      expect(gatePassesMirror('089537229865', '089537229865'), isTrue);
    });

    test('cross-format match: typed 08xx vs stored 62xx -> pass', () {
      expect(gatePassesMirror('089537229865', '6289537229865'), isTrue);
    });

    test('cross-format match: typed 62xx vs stored 08xx -> pass', () {
      expect(gatePassesMirror('6289537229865', '089537229865'), isTrue);
    });

    test('cross-format match: typed national vs stored 62xx -> pass', () {
      expect(gatePassesMirror('89537229865', '6289537229865'), isTrue);
    });

    test('cross-format match: typed +62 with separators vs stored national -> pass', () {
      expect(gatePassesMirror('+62 895-3722-9865', '89537229865'), isTrue);
    });

    test('mismatch: different numbers -> fail', () {
      expect(gatePassesMirror('089537229865', '6281234567890'), isFalse);
    });

    test('mismatch: different numbers both 08xx -> fail', () {
      expect(gatePassesMirror('08123456789', '08987654321'), isFalse);
    });

    test('stored empty string -> skip gate (pass)', () {
      expect(gatePassesMirror('089537229865', ''), isTrue);
    });

    test('stored whitespace-only -> skip gate (pass)', () {
      expect(gatePassesMirror('089537229865', '   '), isTrue);
    });

    test('input empty + stored present -> fail', () {
      expect(gatePassesMirror('', '6289537229865'), isFalse);
    });

    test('input empty + stored 08xx -> fail', () {
      expect(gatePassesMirror('', '089537229865'), isFalse);
    });

    test('both empty -> pass (stored empty triggers skip)', () {
      expect(gatePassesMirror('', ''), isTrue);
    });
  });

  group('phone match gate — dynamic safety (storedI from Firestore)', () {
    // In production, user['i'] is dynamic. The gate does:
    //   (user['i'] ?? '').toString().trim()
    // These tests verify the .toString() behavior for non-String values.

    test('storedI null equivalent (empty after toString) -> skip gate (pass)', () {
      // Simulates user['i'] == null: (user['i'] ?? '').toString().trim() = ''.
      // Route through a dynamic var so this mirrors the real dynamic Firestore
      // read (a literal `null ?? ''` would be a compile-time no-op / lint).
      final dynamic iField = null;
      final storedI = (iField ?? '').toString().trim();
      expect(gatePassesMirror('089537229865', storedI), isTrue);
    });

    test('storedI numeric (unlikely) -> toString then compare', () {
      // Simulates user['i'] = 6289537229865 (a number, not a string).
      // (6289537229865).toString() = '6289537229865'
      final storedI = 6289537229865.toString().trim();
      // Input matches the numeric stored value after canonicalization
      expect(gatePassesMirror('089537229865', storedI), isTrue);
      // Different number does not match
      expect(gatePassesMirror('08123456789', storedI), isFalse);
    });
  });

  group('phone match gate — second number family', () {
    // Verify with a different number to confirm no hard-coded test artifacts.

    test('match: typed 08123456789 vs stored 628123456789 -> pass', () {
      expect(gatePassesMirror('08123456789', '628123456789'), isTrue);
    });

    test('match: typed 628123456789 vs stored 8123456789 -> pass', () {
      expect(gatePassesMirror('628123456789', '8123456789'), isTrue);
    });

    test('mismatch: typed 08123456789 vs stored 6289537229865 -> fail', () {
      expect(gatePassesMirror('08123456789', '6289537229865'), isFalse);
    });
  });
}
