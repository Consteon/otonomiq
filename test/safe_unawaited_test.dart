import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // safeUnawaited exists for one reason: a fire-and-forget Future whose
  // rejection has no handler escapes to platformDispatcher.onError (main.dart)
  // and is recorded as a FATAL crash. flutter_test fails a test on exactly that
  // escape, so "the test finished" IS the assertion — remove the .catchError in
  // safeUnawaited and these tests fail with the unhandled error.

  test('a rejected future does not escape as an unhandled async error', () {
    safeUnawaited(
      Future<void>.error(StateError('boom')),
      'safeUnawaited unit test',
    );
    // Two microtask turns: one for the rejection, one for the handler.
    return Future<void>.delayed(Duration.zero);
  });

  test('the real PlatformException shape is swallowed', () {
    safeUnawaited(
      Future<void>.error(
        'PlatformException(Clear Failed, clearCredentialStateAsync no provider '
        'dependencies found - please ensure the desired provider dependencies '
        'are added, null, null)',
      ),
      'kickedOut GoogleSignIn',
    );
    return Future<void>.delayed(Duration.zero);
  });

  test('a future that completes normally is untouched', () async {
    bool ran = false;
    safeUnawaited(
      Future<void>.value().then((_) => ran = true),
      'safeUnawaited happy path',
    );
    await Future<void>.delayed(Duration.zero);
    expect(ran, isTrue);
  });
}
