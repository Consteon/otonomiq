import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otonomiq/api.dart';

void main() {
  // Zero backoff everywhere: the real 1s pause is for a radio mid-handover,
  // it has nothing to prove here and would only slow the suite down.
  const Duration noWait = Duration.zero;

  group('postWithOneRetry', () {
    // The AppBar refresh's readSS pull. The failure it exists for is a socket
    // torn down mid-request (ClientException "Bad file descriptor"), which is
    // transient — the first attempt dies, the second lands.

    test('a clean call is not repeated', () async {
      int calls = 0;
      final http.Response? res = await postWithOneRetry(() async {
        calls++;
        return http.Response('[["home","{}"]]', 200);
      }, backoff: noWait);

      expect(calls, 1);
      expect(res?.body, '[["home","{}"]]');
    });

    test('a dropped socket is retried once and can succeed', () async {
      int calls = 0;
      final http.Response? res = await postWithOneRetry(() async {
        calls++;
        if (calls == 1) {
          throw http.ClientException(
            'Bad file descriptor',
            Uri.parse('https://asia-northeast1-otq-01.cloudfunctions.net/readSS'),
          );
        }
        return http.Response('[["home","{}"]]', 200);
      }, backoff: noWait);

      expect(calls, 2);
      expect(res?.body, '[["home","{}"]]');
    });

    test('two failures give up and return null', () async {
      // Null is what keeps the cached UI: readSettingsContext skips its whole
      // apply block and returns false, so the caller reports a kept cache
      // instead of painting a successful refresh.
      int calls = 0;
      final http.Response? res = await postWithOneRetry(() async {
        calls++;
        throw http.ClientException('Bad file descriptor');
      }, backoff: noWait);

      expect(calls, 2);
      expect(res, isNull);
    });

    test('it never runs a third time', () async {
      int calls = 0;
      await postWithOneRetry(() async {
        calls++;
        throw const FormatException('whatever the failure is');
      }, backoff: noWait);

      expect(calls, 2);
    });
  });

  group('lqrFetchNeeded', () {
    // Guards the second readSS POST that every refresh tap used to fire.
    // Skipping too eagerly is the expensive mistake: empty geofences make the
    // LOCATION card read "Unknown" and attendance stop working.

    test('fetched lif with a populated list is skipped', () {
      expect(
        lqrFetchNeeded('lif-A', 'lif-A', {'gate1': <String>[]}),
        isFalse,
      );
    });

    test('a different lif always fetches', () {
      // Logging in as another tenant/user must not inherit the old geofences.
      expect(lqrFetchNeeded('lif-B', 'lif-A', {'gate1': <String>[]}), isTrue);
    });

    test('nothing fetched yet always fetches', () {
      expect(lqrFetchNeeded('lif-A', null, null), isTrue);
      expect(lqrFetchNeeded('lif-A', null, {'gate1': <String>[]}), isTrue);
    });

    test('an emptied list re-opens the fetch for the same lif', () {
      // signOut drops #LQR_LIST; the next login must pull it again even though
      // the lif never changed. This is the re-login regression the old
      // appStartupRun gate caused.
      expect(lqrFetchNeeded('lif-A', 'lif-A', <String, dynamic>{}), isTrue);
      expect(lqrFetchNeeded('lif-A', 'lif-A', null), isTrue);
    });

    test('a non-map value in the store is treated as no list', () {
      expect(lqrFetchNeeded('lif-A', 'lif-A', 'not a map'), isTrue);
    });
  });
}
