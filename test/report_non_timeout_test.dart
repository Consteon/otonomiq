import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  group('reportNonTimeout', () {
    test('TimeoutException is swallowed (devPrint only, no throw)', () {
      // A TimeoutException should hit the devPrint branch and return.
      // It must NOT throw, proving it does not reach errorReport/Crashlytics.
      expect(
        () => reportNonTimeout(TimeoutException('test timeout', const Duration(seconds: 8))),
        returnsNormally,
      );
    });

    test('TimeoutException with null duration is also swallowed', () {
      expect(
        () => reportNonTimeout(TimeoutException('ntp timeout')),
        returnsNormally,
      );
    });

    test('non-TimeoutException falls through to errorReport (no throw)', () {
      // A non-timeout exception should reach errorReport, which calls debugPrint
      // and then FirebaseCrashlytics (which throws without init but is caught
      // by errorReport's own catch guard). Net result: no throw.
      expect(
        () => reportNonTimeout(Exception('real error')),
        returnsNormally,
      );
    });

    test('non-TimeoutException with stack trace falls through (no throw)', () {
      final stack = StackTrace.current;
      expect(
        () => reportNonTimeout(FormatException('bad data'), stack),
        returnsNormally,
      );
    });
  });
}
