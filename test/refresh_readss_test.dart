import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otonomiq/api.dart';
import 'package:otonomiq/global.dart';

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

  group('getFunctionBody url', () {
    // The readSS cutover gate. getFunctionBody is the only place in the tree
    // that builds a readSS URL, so all 12 call sites — proxyRead, getLqrList,
    // readSettingsStart, readUIPages, readSettings, readSettingsContext,
    // getLifProfileData, launchCheck — move with it and none needed editing.

    // What lib/global.dart actually declares. Read during test-tree
    // construction, before any setUp has run, so this is the shipped
    // initialiser and not a value some earlier test left behind. Restoring
    // THIS in tearDown (rather than '') is what keeps the process-wide global
    // correct for anything running later in the isolate.
    final String shippedDefault = readSSUrl;

    const String legacyDomain = 'asia-northeast1-otq-01.cloudfunctions.net';
    const String legacyUrl =
        'https://asia-northeast1-otq-01.cloudfunctions.net/readSS';
    const String goUrl =
        'https://asia-southeast1-authenium-prod1.cloudfunctions.net/readSSg';
    const List<String> ranges = ['JSON!B6:E49', 'op1!I12:M211'];

    setUp(() {
      // globalInit() never runs in a unit test, so autsorzFunctionDomain is
      // still "--" and functionName is still {}. Seed them with the real
      // production values, otherwise the legacy branch asserts "https://--null"
      // and proves nothing.
      autsorzFunctionDomain = legacyDomain;
      functionName['readSS'] = '/readSS';
      readSSUrl = '';
    });

    tearDown(() {
      // All three are process-wide globals, and setUp mutated all three.
      // Leaving any of them set would leak into the other groups in this file
      // and into any later test in the same isolate. readSSUrl goes back to the
      // SHIPPED value, not to '': '' is the rollback state, so resetting to it
      // would hand a wrong constant to whatever runs next.
      readSSUrl = shippedDefault;
      autsorzFunctionDomain = '--';
      functionName.remove('readSS');
    });

    test('the shipped default routes readSS at the Go endpoint', () {
      // The cutover itself, and the only test here that proves it is LIVE
      // rather than merely possible. It reads the value the build actually
      // declares — a literal re-typed here would assert nothing about what
      // ships. This is also what would have caught round 1's boot wipe.
      readSSUrl = shippedDefault;
      final fb = getFunctionBody('ssid-1', ranges);

      expect(fb.url, isNot(legacyUrl));
      expect(fb.url, shippedDefault); // the gate passes it through verbatim
      expect(shippedDefault, goUrl); // and it is the URL spec 2.1/4.1 names
    });

    test('nothing in api.dart assigns readSSUrl — the boot-wipe regression', () {
      // Round 1 filled readSSUrl from the /appSettings3 payload at the three
      // settingUp decode sites. That field does not exist in the response and
      // is cancelled (spec 2.1 / 9), so the expression always yielded '' — and
      // settingUp is awaited from serverSetup (main.dart:156) BEFORE the first
      // readSS call (main.dart:298). Every boot would have blanked the constant
      // before it was ever read: no crash, no log, no analyzer finding, cutover
      // silently reverted.
      //
      // The runtime path crosses four platform boundaries (secureRead,
      // getDataFromCloud, secureWrite, internetConnected) and this repo has no
      // mocking infrastructure, so the removal is pinned at the source level
      // instead. dart:io is available under flutter_test and already used by
      // test/ocr_capture_support_test.dart.
      final File api = File('lib/api.dart');
      expect(
        api.existsSync(),
        isTrue,
        reason: 'must run from the package root, or this check is vacuous',
      );

      // getFunctionBody READS the global; nothing in api.dart may WRITE it.
      // (?!=) keeps a future `readSSUrl ==` comparison from tripping this.
      final Iterable<RegExpMatch> writes = RegExp(
        r'\breadSSUrl\s*=(?!=)',
      ).allMatches(api.readAsStringSync());

      expect(
        writes.length,
        0,
        reason: 'a fill would blank readSSUrl at boot — spec 4.2 defers it',
      );
    });

    test('empty readSSUrl keeps the legacy URL', () {
      // The rollback state (spec 6): clearing readSSUrl and shipping a release
      // is how the app goes back to the legacy endpoint.
      final fb = getFunctionBody('ssid-1', ranges);

      expect(fb.url, legacyUrl);
      // Spec section 5: the gate moves the URL and nothing else.
      expect(fb.body['eData'], '--');
      expect(fb.body['clt'], defaultCluster);
      expect(
        fb.body['job'],
        '[{"ssid":"ssid-1","type":"A1","rg":"JSON!B6:E49"},'
        '{"ssid":"ssid-1","type":"A1","rg":"op1!I12:M211"}]',
      );
    });

    test('an https readSSUrl is used verbatim, with an identical body', () {
      final legacy = getFunctionBody('ssid-1', ranges);
      readSSUrl = goUrl;
      final go = getFunctionBody('ssid-1', ranges);

      expect(go.url, goUrl);
      expect(go.url, isNot(legacy.url));
      // Byte-compatible contract: only the host moves.
      expect(go.body, legacy.body);
    });

    test('a plain http readSSUrl falls back to the legacy URL', () {
      readSSUrl =
          'http://asia-southeast1-authenium-prod1.cloudfunctions.net/readSSg';
      expect(getFunctionBody('ssid-1', ranges).url, legacyUrl);
    });

    test('a garbage readSSUrl falls back to the legacy URL', () {
      // Acceptance section 8: a typo must not break every read.
      readSSUrl = 'bukan-url';
      expect(getFunctionBody('ssid-1', ranges).url, legacyUrl);
    });
  });
}
