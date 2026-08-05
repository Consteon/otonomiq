import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // isNetworkDownError decides whether errorReport suppresses a Crashlytics
  // non-fatal while the app knows it is offline. Too broad = real bugs go
  // silent; too narrow = the offline noise comes back.

  group('isNetworkDownError — suppress (radio down)', () {
    test('the reported readSS failure', () {
      expect(
        isNetworkDownError(
          'ClientException with SocketException: Connection failed '
          '(OS Error: Network is unreachable, errno = 101), '
          'address = asia-northeast1-otq-01.cloudfunctions.net, port = 443, '
          'uri=https://asia-northeast1-otq-01.cloudfunctions.net/readSS',
        ),
        isTrue,
      );
    });

    test('real SocketException object', () {
      expect(
        isNetworkDownError(
          const SocketException('Failed host lookup: firestore.googleapis.com'),
        ),
        isTrue,
      );
    });
  });

  group('isNetworkDownError — still report', () {
    test('non-network runtime error', () {
      expect(isNetworkDownError(RangeError.index(3, [1, 2])), isFalse);
    });

    test('firestore permission denied', () {
      expect(
        isNetworkDownError(
          '[cloud_firestore/permission-denied] Missing or insufficient '
          'permissions.',
        ),
        isFalse,
      );
    });

    test('plain string from a tagged call site', () {
      expect(isNetworkDownError('[safeFsUpdate] task write failed'), isFalse);
    });
  });
}
