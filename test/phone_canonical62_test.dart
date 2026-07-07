import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  group('phoneCanonical62', () {
    test('strips leading 0 and prepends 62', () {
      expect(phoneCanonical62('089537229865'), '6289537229865');
    });

    test('strips separators and country code from +62 format', () {
      expect(phoneCanonical62('+62 895-3722-9865'), '6289537229865');
    });

    test('idempotent on already-canonical input', () {
      expect(phoneCanonical62('6289537229865'), '6289537229865');
    });

    test('handles national-only without leading 0', () {
      expect(phoneCanonical62('89537229865'), '6289537229865');
    });

    test('strips leading 0 from 08xx format', () {
      expect(phoneCanonical62('08123456789'), '628123456789');
    });

    test('idempotent on 628xx format', () {
      expect(phoneCanonical62('628123456789'), '628123456789');
    });

    test('handles 620-prefixed input (CC + trunk prefix)', () {
      expect(phoneCanonical62('6208123456'), '628123456');
    });

    test('returns empty string for empty input', () {
      expect(phoneCanonical62(''), '');
    });

    test('returns empty string for non-digit-only input', () {
      expect(phoneCanonical62('+--'), '');
    });

    test('handles spaces and dots in number', () {
      expect(phoneCanonical62('0812 345 6789'), '628123456789');
    });

    test('handles parentheses and dots', () {
      expect(phoneCanonical62('(+62) 812.345.6789'), '628123456789');
    });
  });

  group('phoneCanonical62 + phoneCleanup candidate set (login tolerant read)', () {
    // These tests verify that the SET {phoneCanonical62(x), phoneCleanup(x)}
    // always covers both the old (national) and new (62+national) storage forms.
    // This is the pure logic behind the whereIn query; Firestore is not needed.

    test('from 08xx input: set covers both forms', () {
      final raw = '089537229865';
      final canon = phoneCanonical62(raw);
      final legacy = phoneCleanup(raw);
      expect(canon, '6289537229865');  // new canonical
      expect(legacy, '89537229865');   // old national
      final forms = <String>{if (canon.isNotEmpty) canon, if (legacy.isNotEmpty) legacy};
      expect(forms, {'6289537229865', '89537229865'});
    });

    test('from 62-prefixed input: set covers both forms', () {
      final raw = '6289537229865';
      final canon = phoneCanonical62(raw);
      final legacy = phoneCleanup(raw);
      expect(canon, '6289537229865');
      expect(legacy, '89537229865');
      final forms = <String>{if (canon.isNotEmpty) canon, if (legacy.isNotEmpty) legacy};
      expect(forms, {'6289537229865', '89537229865'});
    });

    test('from national-only input: set covers both forms', () {
      final raw = '89537229865';
      final canon = phoneCanonical62(raw);
      final legacy = phoneCleanup(raw);
      expect(canon, '6289537229865');
      expect(legacy, '89537229865');
      final forms = <String>{if (canon.isNotEmpty) canon, if (legacy.isNotEmpty) legacy};
      expect(forms, {'6289537229865', '89537229865'});
    });

    test('empty input: set is empty (sentinel path)', () {
      final raw = '';
      final canon = phoneCanonical62(raw);
      final legacy = phoneCleanup(raw);
      expect(canon, '');
      expect(legacy, '');
      final forms = <String>{if (canon.isNotEmpty) canon, if (legacy.isNotEmpty) legacy};
      expect(forms, <String>{});
    });
  });

  group('phoneCanonical62 idempotency — full vector table', () {
    // φ(φ(x)) == φ(x) for every realistic input form.
    // Verifies the function is stable under repeated application — e.g. if a
    // stored canonical value is passed through again on read-back.

    test('08xx format: idempotent', () {
      final once = phoneCanonical62('089537229865');
      expect(phoneCanonical62(once), once);
    });

    test('+62 international format: idempotent', () {
      final once = phoneCanonical62('+62 895-3722-9865');
      expect(phoneCanonical62(once), once);
    });

    test('national-only (no leading 0): idempotent', () {
      final once = phoneCanonical62('89537229865');
      expect(phoneCanonical62(once), once);
    });

    test('08xx shorter number: idempotent', () {
      final once = phoneCanonical62('08123456789');
      expect(phoneCanonical62(once), once);
    });

    test('spaces-and-dots format: idempotent', () {
      final once = phoneCanonical62('0812 345 6789');
      expect(phoneCanonical62(once), once);
    });

    test('parentheses-and-dots format: idempotent', () {
      final once = phoneCanonical62('(+62) 812.345.6789');
      expect(phoneCanonical62(once), once);
    });

    test('620-prefixed (CC + trunk prefix): idempotent', () {
      final once = phoneCanonical62('6208123456');
      expect(phoneCanonical62(once), once);
    });

    test('empty string: idempotent', () {
      final once = phoneCanonical62('');
      expect(phoneCanonical62(once), once);
    });
  });

  group('phoneCanonical62 convergence — same number, all input forms', () {
    // Multiple representations of the same underlying national number must all
    // produce the same canonical output. This is the core "adaptive" guarantee.

    test('national 89537229865: five input forms converge', () {
      const target = '6289537229865';
      for (final raw in [
        '089537229865',       // trunk prefix + national
        '+62 895-3722-9865',  // intl format with separators
        '6289537229865',      // already canonical
        '89537229865',        // bare national
        '62 0895 3722 9865',  // CC + trunk prefix + separators
      ]) {
        expect(phoneCanonical62(raw), target, reason: 'input: $raw');
      }
    });

    test('national 8123456789: four input forms converge', () {
      const target = '628123456789';
      for (final raw in [
        '08123456789',        // trunk prefix + national
        '+62 812-345-6789',   // intl format with separators
        '628123456789',       // already canonical
        '62-0812-345-6789',   // CC + separator + trunk prefix + national
      ]) {
        expect(phoneCanonical62(raw), target, reason: 'input: $raw');
      }
    });
  });

  group('tolerant-read candidate set — additional input forms', () {
    // Supplement existing candidate-set tests with input forms not yet covered.
    // Invariant: {phoneCanonical62(raw), phoneCleanup(raw)} contains the doc.i
    // value regardless of which storage regime (migrated 62+national, or legacy
    // national) the doc was written under. This is the pure model of the
    // api.dart whereIn query.

    test('+62 international format: set covers both storage forms', () {
      const raw = '+62 895-3722-9865';
      final canon = phoneCanonical62(raw);
      final legacy = phoneCleanup(raw);
      expect(canon, '6289537229865'); // migrated doc.i
      expect(legacy, '89537229865');  // legacy doc.i
      final forms = <String>{if (canon.isNotEmpty) canon, if (legacy.isNotEmpty) legacy};
      // migrated doc: i == canonical is reachable
      expect(forms.contains(canon), isTrue);
      // legacy doc: i == national is reachable
      expect(forms.contains(legacy), isTrue);
    });

    test('second number family (08123456789): set covers both storage forms', () {
      const raw = '08123456789';
      final canon = phoneCanonical62(raw);
      final legacy = phoneCleanup(raw);
      expect(canon, '628123456789'); // migrated doc.i
      expect(legacy, '8123456789');  // legacy doc.i
      final forms = <String>{if (canon.isNotEmpty) canon, if (legacy.isNotEmpty) legacy};
      expect(forms.contains(canon), isTrue);
      expect(forms.contains(legacy), isTrue);
    });
  });

  group('phoneCanonical62 edge robustness — short and pathological inputs', () {
    // Document actual behavior for unusual inputs.
    // None of these represent realistic Indonesian phone numbers typed by a user;
    // findings here are observations only — see test-report-r1.md.

    test("'0': all-zero digit-only input reduces to empty", () {
      // d = '0', strip ^62 (no-op), strip ^0 -> '', return ''
      expect(phoneCanonical62('0'), '');
    });

    test("'62': country-code-only input reduces to empty", () {
      // d = '62', strip ^62 -> '', return ''
      expect(phoneCanonical62('62'), '');
    });

    test("'8': single national digit gets 62 prepended — no minimum-length guard", () {
      // The function does not enforce a minimum length on the national part.
      // Observation: single-digit input produces '628', not a real phone number.
      expect(phoneCanonical62('8'), '628');
    });

    test("double leading zero: first application leaves embedded trunk prefix (non-idempotent)", () {
      // '00812345678' -> strip non-digits -> '00812345678'
      //   -> strip ^62 (no match) -> '00812345678'
      //   -> strip ^0 (one zero) -> '0812345678'
      //   -> prepend 62 -> '620812345678'
      // A second application then resolves the remaining trunk prefix:
      //   -> strip ^62 -> '0812345678' -> strip ^0 -> '812345678' -> '62812345678'
      // The function needs two passes for double-zero inputs.
      // Observation only: '00...' is not a realistic Indonesian phone entry.
      final once = phoneCanonical62('00812345678');
      expect(once, '620812345678');
      // Second pass differs — documents non-idempotency for this pathological input.
      expect(phoneCanonical62(once), '62812345678');
    });
  });
}
