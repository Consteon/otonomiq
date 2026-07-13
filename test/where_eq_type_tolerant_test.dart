import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/where_eq_type_tolerant.dart';

void main() {
  group('numArmValue — returns num arm for canonical numeric strings', () {
    test('14-digit VID returns int', () {
      final result = numArmValue('83674161979544');
      expect(result, isA<int>());
      expect(result, 83674161979544);
    });

    test('negative integer returns int', () {
      final result = numArmValue('-42');
      expect(result, isA<int>());
      expect(result, -42);
    });

    test('zero returns int', () {
      expect(numArmValue('0'), 0);
    });

    test('single digit returns int', () {
      expect(numArmValue('7'), 7);
    });

    test('13-digit epoch returns int', () {
      final result = numArmValue('1782838800000');
      expect(result, 1782838800000);
    });

    test('15-digit value returns num (at boundary)', () {
      final result = numArmValue('123456789012345');
      expect(result, 123456789012345);
    });
  });

  group('numArmValue — returns null for string-only values', () {
    test('leading-zero code "007" returns null (round-trip fails)', () {
      // num.tryParse("007") = 7, 7.toString() = "7" != "007"
      expect(numArmValue('007'), isNull);
    });

    test('>15-digit value returns null (precision unsafe)', () {
      expect(numArmValue('1234567890123456'), isNull);
    });

    test('20-digit value returns null', () {
      expect(numArmValue('12345678901234567890'), isNull);
    });

    test('non-digit string "MENUNGGU" returns null', () {
      expect(numArmValue('MENUNGGU'), isNull);
    });

    test('alphanumeric "REQ-2026-000295" returns null', () {
      expect(numArmValue('REQ-2026-000295'), isNull);
    });

    test('string with letters "client" returns null', () {
      expect(numArmValue('client'), isNull);
    });

    test('empty string returns null', () {
      expect(numArmValue(''), isNull);
    });

    test('whitespace-only returns null', () {
      expect(numArmValue('   '), isNull);
    });

    test('decimal that does not round-trip "1.10" returns null', () {
      // num.tryParse("1.10") = 1.1, 1.1.toString() = "1.1" != "1.10"
      expect(numArmValue('1.10'), isNull);
    });

    test('decimal "3.14" round-trips — returns double', () {
      // num.tryParse("3.14") = 3.14, 3.14.toString() = "3.14" == "3.14"
      final result = numArmValue('3.14');
      expect(result, isA<double>());
      expect(result, 3.14);
    });

    test('negative decimal "-0.5" round-trips — returns double', () {
      final result = numArmValue('-0.5');
      expect(result, -0.5);
    });
  });

  group('numArmValue — edge cases', () {
    test('value with leading/trailing whitespace is trimmed', () {
      expect(numArmValue('  42  '), 42);
    });

    test('"+1" does not round-trip (toString = "1")', () {
      // num.tryParse("+1") = 1, 1.toString() = "1" != "+1"
      expect(numArmValue('+1'), isNull);
    });

    test('"0.0" round-trips as double', () {
      // num.tryParse("0.0") = 0.0, 0.0.toString() = "0.0" == "0.0"
      expect(numArmValue('0.0'), 0.0);
    });

    test('"-0" does not round-trip', () {
      // num.tryParse("-0") = -0.0 or 0, toString != "-0"
      expect(numArmValue('-0'), isNull);
    });
  });
}
