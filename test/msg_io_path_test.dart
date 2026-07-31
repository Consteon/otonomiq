import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

// Guards the inbox path shape. The three call sites (main.dart warm start,
// api.dart:2162 settings load, firebase_notification_handler.dart background
// bridge) must agree -- the bridge used to hardcode 'msg_' and would have
// silently written to a different collection if msgPrefix ever changed.
void main() {
  test('msgIoPath composes msgPrefix/cluster/msgId/io', () {
    expect(msgIoPath('DEV2', 'abc123'), 'msg_DEV2/abc123/io');
  });

  test('msgIoPath yields an odd segment count (valid Firestore collection)', () {
    expect(msgIoPath('DEV2', 'abc123').split('/').length.isOdd, isTrue);
  });

  test('msgIoPath follows msgPrefix', () {
    final saved = msgPrefix;
    msgPrefix = 'test_';
    addTearDown(() => msgPrefix = saved);
    expect(msgIoPath('C1', 'M1'), 'test_C1/M1/io');
  });
}
