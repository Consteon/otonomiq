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

  // isNoRouteError is the half of the gate that ignores internetConnectionFlag.
  // getLqrList throws AFTER the flag was set true and AFTER an unbounded wait
  // on locRange, so "the app thinks it is online" carries no information there.
  group('isNoRouteError — suppress even while the flag says online', () {
    test('the reported readSS failure (errno 101)', () {
      expect(
        isNoRouteError(
          'ClientException with SocketException: Connection failed '
          '(OS Error: Network is unreachable, errno = 101), '
          'address = asia-northeast1-otq-01.cloudfunctions.net, port = 443, '
          'uri=https://asia-northeast1-otq-01.cloudfunctions.net/readSS',
        ),
        isTrue,
      );
    });

    test('host lookup failure (errno 7)', () {
      expect(
        isNoRouteError(
          const SocketException('Failed host lookup: firestore.googleapis.com'),
        ),
        isTrue,
      );
    });
  });

  group('isNoRouteError — narrower than isNetworkDownError', () {
    test('connection reset is network-shaped but NOT proof of no route', () {
      // Server / TLS side failure: still reported when the app is online.
      const String reset =
          'ClientException with SocketException: Connection reset by peer '
          '(OS Error: Connection reset by peer, errno = 104), '
          'address = asia-northeast1-otq-01.cloudfunctions.net, port = 443';
      expect(isNetworkDownError(reset), isTrue);
      expect(isNoRouteError(reset), isFalse);
    });

    test('non-network error is neither', () {
      const String denied =
          '[cloud_firestore/permission-denied] Missing or insufficient '
          'permissions.';
      expect(isNetworkDownError(denied), isFalse);
      expect(isNoRouteError(denied), isFalse);
    });
  });

  // The mid-flight abort: socket established, then torn down by the device
  // (Wi-Fi<->LTE handoff, doze) during the unbounded readSS post in
  // getLqrList. Network-shaped, flag says online, no route evidence — so the
  // pre-existing gate reported it.
  const String abort = 'ClientException: Software caused connection abort, '
      'uri=https://asia-northeast1-otq-01.cloudfunctions.net/readSS';

  group('skipCrashReport — composition, not single predicates', () {
    test('the reported readSS abort is dropped while online', () {
      // Every input the old gate saw, unchanged:
      expect(isNetworkDownError(abort), isTrue);
      expect(isNoRouteError(abort), isFalse); // there WAS a route
      // ...and the old wiring (down && (!online || noRoute)) therefore
      // reported it. The new disjunct is the whole fix.
      expect(isConnectionAbortError(abort), isTrue);
      expect(skipCrashReport(abort, true), isTrue);
    });

    test('connection RESET while online is still reported', () {
      // Far-end / TLS fault — deliberately NOT covered by the new disjunct.
      const String reset =
          'ClientException with SocketException: Connection reset by peer '
          '(OS Error: Connection reset by peer, errno = 104), '
          'address = asia-northeast1-otq-01.cloudfunctions.net, port = 443';
      expect(isConnectionAbortError(reset), isFalse);
      expect(skipCrashReport(reset, true), isFalse);
    });

    test('no-route while online is still dropped', () {
      expect(
        skipCrashReport(
          'ClientException with SocketException: Connection failed '
          '(OS Error: Network is unreachable, errno = 101)',
          true,
        ),
        isTrue,
      );
    });

    test('any network shape while offline is dropped', () {
      const String reset = 'ClientException: Connection reset by peer';
      expect(skipCrashReport(reset, false), isTrue);
    });

    test('non-network error reports in both flag states', () {
      final Object range = RangeError.index(3, [1, 2]);
      expect(skipCrashReport(range, true), isFalse);
      expect(skipCrashReport(range, false), isFalse);
    });

    test('an abort that is NOT network-shaped still reports', () {
      // The AND-half still holds: the message must look like transport.
      expect(
        skipCrashReport('Software caused connection abort', true),
        isFalse,
      );
    });

    test('the gRPC DNS failure from launchCheck is dropped while online', () {
      // Native-stack wording for the same errno-7 DNS failure dart:io calls
      // "Failed host lookup". Reached errorReport only after the un-awaited
      // runTransaction in launchCheck was wrapped in safeUnawaited; before
      // that it went straight to platformDispatcher.onError as a FATAL.
      const String dns = '[cloud_firestore/unavailable] UNAVAILABLE: Unable to '
          'resolve host firestore.googleapis.com';
      expect(isNoRouteError(dns), isTrue);
      expect(isNetworkDownError(dns), isTrue); // via the isNoRouteError leg
      expect(skipCrashReport(dns, true), isTrue);
      expect(skipCrashReport(dns, false), isTrue);
    });

    test('other firestore/unavailable causes are still reported', () {
      // A backend outage or deadline is NOT a device-side DNS failure.
      expect(
        skipCrashReport(
          '[cloud_firestore/unavailable] The service is currently unavailable.',
          true,
        ),
        isFalse,
      );
    });

    test('tagged call sites keep their prefix and are still matched', () {
      // callHttpPost reports 'callHttpPost <uri>: <e>' — a string, not the
      // exception object. Substring matching must survive that.
      expect(
        skipCrashReport(
          'callHttpPost https://asia-northeast1-otq-01.cloudfunctions.net/'
          'readSS: $abort',
          true,
        ),
        isTrue,
      );
    });
  });
}
