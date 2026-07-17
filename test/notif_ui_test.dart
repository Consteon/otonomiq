import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/notif_ui.dart';

void main() {
  group('notifInitials', () {
    test('single word -> first letter upper', () {
      expect(notifInitials('test'), 'T');
    });
    test('two words -> two initials upper', () {
      expect(notifInitials('Test One'), 'TO');
    });
    test('extra whitespace collapsed', () {
      expect(notifInitials('  budi   santoso  '), 'BS');
    });
    test('empty -> ?', () {
      expect(notifInitials(''), '?');
      expect(notifInitials('   '), '?');
    });
  });

  group('notifAvatarColor', () {
    test('deterministic per name', () {
      expect(notifAvatarColor('Test 1'), notifAvatarColor('Test 1'));
    });
  });

  group('notifRelTime', () {
    test('null / non-positive -> empty', () {
      expect(notifRelTime(null), '');
      expect(notifRelTime(0), '');
      expect(notifRelTime(-5), '');
    });
    test('under a minute -> baru', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(notifRelTime(now - 10 * 1000), 'baru');
    });
    test('minutes', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(notifRelTime(now - 5 * 60 * 1000), '5m');
    });
    test('hours', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(notifRelTime(now - 3 * 60 * 60 * 1000), '3j');
    });
    test('yesterday', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(notifRelTime(now - 26 * 60 * 60 * 1000), 'Kemarin');
    });
  });
}
