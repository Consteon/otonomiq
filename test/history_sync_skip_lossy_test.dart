import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';

/// History row shape used by historySync: the sent marker lives at index 9.
List<dynamic> row({required num sent, int length = 15}) {
  final List<dynamic> r = List<dynamic>.filled(length, '', growable: true);
  r[0] = 1700000000000;
  r[9] = sent;
  return r;
}

void main() {
  group('historySyncSkipIsLossy', () {
    test('null / absent queue is not lossy (pre-login)', () {
      expect(historySyncSkipIsLossy(null), isFalse);
    });

    test('empty queue is not lossy (pre-login)', () {
      expect(historySyncSkipIsLossy(<dynamic>[]), isFalse);
    });

    test('non-list queue is not lossy', () {
      expect(historySyncSkipIsLossy('--'), isFalse);
    });

    test('all records already sent is not lossy', () {
      expect(
        historySyncSkipIsLossy([row(sent: 1), row(sent: 5)]),
        isFalse,
      );
    });

    test('one unsent record makes the skip lossy', () {
      expect(historySyncSkipIsLossy([row(sent: 1), row(sent: 0)]), isTrue);
    });

    test('negative sent marker counts as unsent', () {
      expect(historySyncSkipIsLossy([row(sent: -1)]), isTrue);
    });

    test('short / malformed rows are skipped, not crashed on', () {
      expect(historySyncSkipIsLossy([<dynamic>[1, 2, 3], 'junk', null]), isFalse);
      expect(
        historySyncSkipIsLossy([<dynamic>[1, 2, 3], row(sent: 0)]),
        isTrue,
      );
    });

    test('non-numeric sent marker is not treated as unsent', () {
      final List<dynamic> r = row(sent: 0);
      r[9] = 'x';
      expect(historySyncSkipIsLossy([r]), isFalse);
    });
  });
}
