import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/logout_transition_support.dart';

// Exercises the SAME pure helper that signOut() calls to decide between the
// instant warm-cache restore and the cold/corrupt network fallback. The helper
// lives in lib/widget/logout_transition_support.dart (a tiny pure file, no
// Firebase/secrets) so production and test share one implementation.

void main() {
  group('shouldRestoreGuestSnapshot', () {
    test('returns false when both are null', () {
      expect(shouldRestoreGuestSnapshot(null, null), isFalse);
    });

    test('returns false when screenUI is null', () {
      expect(shouldRestoreGuestSnapshot(null, '{"ThemeAgenia":{}}'), isFalse);
    });

    test('returns false when systemUI is null', () {
      expect(shouldRestoreGuestSnapshot('{"home":[]}', null), isFalse);
    });

    test('returns false when screenUI is empty string', () {
      expect(shouldRestoreGuestSnapshot('', '{"ThemeAgenia":{}}'), isFalse);
    });

    test('returns false when systemUI is empty string', () {
      expect(shouldRestoreGuestSnapshot('{"home":[]}', ''), isFalse);
    });

    test('returns false when screenUI is not valid JSON', () {
      expect(
          shouldRestoreGuestSnapshot('not json', '{"ThemeAgenia":{}}'), isFalse);
    });

    test('returns false when systemUI is not valid JSON', () {
      expect(shouldRestoreGuestSnapshot('{"home":[]}', 'not json'), isFalse);
    });

    test('returns true when both are valid JSON maps', () {
      expect(
        shouldRestoreGuestSnapshot(
          '{"home":[{"type":"txt"}],"_Legal":[]}',
          '{"ThemeAgenia":{"primaryColor":4278196850}}',
        ),
        isTrue,
      );
    });

    test('returns false when screenUI decodes to a list (not a map)', () {
      expect(shouldRestoreGuestSnapshot('[1,2,3]', '{"ThemeAgenia":{}}'),
          isFalse);
    });

    test('returns false when systemUI decodes to a primitive', () {
      expect(shouldRestoreGuestSnapshot('{"home":[]}', '"just a string"'),
          isFalse);
    });
  });
}
