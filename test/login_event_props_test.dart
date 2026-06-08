import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/login/bloc_login/login_event.dart';

// Fix E (BUG 6): every LoginEvent had `props => []`, so two events of the same
// type with DIFFERENT payloads compared equal. Harmless today (bloc doesn't
// dedup events), but a landmine for any future distinct/dedup transformer.
// Events must include their fields in Equatable props.
void main() {
  group('LoginEvent equality (Equatable props)', () {
    test('same-type events with different payloads are NOT equal', () {
      expect(
        const EmailChanged(email: 'a') == const EmailChanged(email: 'b'),
        isFalse,
      );
    });

    test('same-type events with identical payloads ARE equal', () {
      expect(
        const EmailChanged(email: 'a') == const EmailChanged(email: 'a'),
        isTrue,
      );
    });

    test('multi-field events compare every field', () {
      expect(
        const LoginWithGooglePressed(country: 'ID', inv: '1') ==
            const LoginWithGooglePressed(country: 'ID', inv: '2'),
        isFalse,
      );
      expect(
        const LoginWithGooglePressed(country: 'ID', inv: '1') ==
            const LoginWithGooglePressed(country: 'ID', inv: '1'),
        isTrue,
      );
    });

    test('status-bearing events differ by status', () {
      expect(
        const LoginFailWithStatus(uid: 'u', status: 2) ==
            const LoginFailWithStatus(uid: 'u', status: 7),
        isFalse,
      );
    });

    test('different event types are never equal', () {
      expect(
        const EmailChanged(email: 'a') == const PhoneChanged(phone: 'a'),
        isFalse,
      );
    });
  });
}
