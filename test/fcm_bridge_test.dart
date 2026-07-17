import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firebase_notification_handler.dart';

void main() {
  group('parseFcmPayload', () {
    test('valid payload returns msgDoc and threadUpdate', () {
      final result = parseFcmPayload({
        'threadVid': 'sender123',
        'nm': 'Alice',
        'pp': 'https://example.com/pic.jpg',
        'dp': 'Hello world',
        'dt': '{"key":"value"}',
        'route': 'delivery_detail',
      }, nowMs: 1700000000000);

      expect(result, isNotNull);
      expect(result!['threadVid'], 'sender123');

      final msgDoc = result['msgDoc'] as Map<String, dynamic>;
      expect(msgDoc['dp'], 'Hello world');
      expect(msgDoc['dt'], '{"key":"value"}');
      expect(msgDoc['tr'], 1700000000000);
      expect(msgDoc['im'], true);
      expect(msgDoc['id'], '');
      expect(msgDoc['st'], 0);
      expect(msgDoc['rt'], 'delivery_detail');

      final threadUpdate = result['threadUpdate'] as Map<String, dynamic>;
      expect(threadUpdate['nm'], 'Alice');
      expect(threadUpdate['pp'], 'https://example.com/pic.jpg');
      expect(threadUpdate['lm'], 'Hello world');
      expect(threadUpdate['lt'], 1700000000000);
    });

    test('missing threadVid returns null', () {
      expect(parseFcmPayload({}), isNull);
      expect(parseFcmPayload({'dp': 'hello'}), isNull);
    });

    test('empty threadVid returns null', () {
      expect(parseFcmPayload({'threadVid': ''}), isNull);
    });

    test('missing optional fields default to empty string', () {
      final result = parseFcmPayload({
        'threadVid': 'vid1',
      }, nowMs: 1000);

      expect(result, isNotNull);
      final msgDoc = result!['msgDoc'] as Map<String, dynamic>;
      expect(msgDoc['dp'], '');
      expect(msgDoc['dt'], '');
      expect(msgDoc['rt'], '');

      final threadUpdate = result['threadUpdate'] as Map<String, dynamic>;
      expect(threadUpdate['nm'], '');
      expect(threadUpdate['pp'], '');
      expect(threadUpdate['lm'], '');
    });

    test('nowMs parameter overrides timestamp', () {
      final result = parseFcmPayload({
        'threadVid': 'vid1',
      }, nowMs: 42);

      final msgDoc = result!['msgDoc'] as Map<String, dynamic>;
      expect(msgDoc['tr'], 42);

      final threadUpdate = result['threadUpdate'] as Map<String, dynamic>;
      expect(threadUpdate['lt'], 42);
    });

    test('without nowMs uses real timestamp', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final result = parseFcmPayload({'threadVid': 'vid1'});
      final after = DateTime.now().millisecondsSinceEpoch;

      final tr = (result!['msgDoc'] as Map<String, dynamic>)['tr'] as int;
      expect(tr, greaterThanOrEqualTo(before));
      expect(tr, lessThanOrEqualTo(after));
    });

    test('msgDoc fields match MessageEntity shape', () {
      final result = parseFcmPayload({
        'threadVid': 'v',
        'dp': 'd',
        'dt': 't',
        'route': 'r',
      }, nowMs: 1);

      final msgDoc = result!['msgDoc'] as Map<String, dynamic>;
      // Verify all 7 MessageEntity fields are present
      expect(msgDoc.keys.toSet(), {'dp', 'dt', 'tr', 'im', 'id', 'st', 'rt'});
    });

    test('threadUpdate fields match NotificationEntity update shape', () {
      final result = parseFcmPayload({
        'threadVid': 'v',
        'nm': 'n',
        'pp': 'p',
        'dp': 'd',
      }, nowMs: 1);

      final threadUpdate = result!['threadUpdate'] as Map<String, dynamic>;
      expect(threadUpdate.keys.toSet(), {'nm', 'pp', 'lm', 'lt'});
    });
  });
}
