import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/logout_transition_support.dart';

void main() {
  group('shouldRestoreAuthedSystemUI', () {
    test('returns false when null', () {
      expect(shouldRestoreAuthedSystemUI(null), isFalse);
    });

    test('returns false when empty string', () {
      expect(shouldRestoreAuthedSystemUI(''), isFalse);
    });

    test('returns false when invalid JSON', () {
      expect(shouldRestoreAuthedSystemUI('not json'), isFalse);
    });

    test('returns false when JSON decodes to a list', () {
      expect(shouldRestoreAuthedSystemUI('[1,2,3]'), isFalse);
    });

    test('returns false when JSON decodes to a primitive', () {
      expect(shouldRestoreAuthedSystemUI('"just a string"'), isFalse);
    });

    test('returns false when Mobile key is missing', () {
      expect(
        shouldRestoreAuthedSystemUI('{"ThemeAgenia":{"primaryColor":123}}'),
        isFalse,
      );
    });

    test('returns false when Mobile is not a map', () {
      expect(shouldRestoreAuthedSystemUI('{"Mobile":"not a map"}'), isFalse);
    });

    test('returns false when bottomBar is missing from Mobile', () {
      expect(
        shouldRestoreAuthedSystemUI('{"Mobile":{"leftPad":0}}'),
        isFalse,
      );
    });

    test('returns false when bottomBar is not a list', () {
      expect(
        shouldRestoreAuthedSystemUI('{"Mobile":{"bottomBar":"not a list"}}'),
        isFalse,
      );
    });

    test('returns false when bottomBar is an empty list', () {
      expect(
        shouldRestoreAuthedSystemUI('{"Mobile":{"bottomBar":[]}}'),
        isFalse,
      );
    });

    test('returns true when bottomBar is a non-empty list', () {
      expect(
        shouldRestoreAuthedSystemUI(
          '{"Mobile":{"bottomBar":[{"icon":"home","route":"_Home","label":"Home"},'
          '{"icon":"notifications","route":"_Notif","label":"Notif"},'
          '{"icon":"person","route":"_Profile","label":"Profile"}],'
          '"leftPad":0,"topPad":0,"rightPad":0,"bottomPad":0},'
          '"ThemeAgenia":{"primaryColor":4278196850}}',
        ),
        isTrue,
      );
    });

    test('returns true with minimal valid structure', () {
      expect(
        shouldRestoreAuthedSystemUI(
            '{"Mobile":{"bottomBar":[{"icon":"home"}]}}'),
        isTrue,
      );
    });

    // The existing shouldRestoreGuestSnapshot still works
    test('shouldRestoreGuestSnapshot still passes basic smoke', () {
      expect(
        shouldRestoreGuestSnapshot(
          '{"home":[{"type":"txt"}]}',
          '{"ThemeAgenia":{"primaryColor":4278196850}}',
        ),
        isTrue,
      );
      expect(shouldRestoreGuestSnapshot(null, null), isFalse);
    });
  });
}
