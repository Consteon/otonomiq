import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/gateway/ledger_publish.dart';
import 'package:otonomiq/global.dart';

void main() {
  final String hollow = separator[8]; // ⭘ pair separator
  final String square = separator[2]; // ◼ key/value separator
  final String circle = separator[0]; // ⬤ tb segment separator
  final String ro = forbiddenCharacter[8]; // ◁ form-position open
  final String rc = forbiddenCharacter[10]; // ▷ form-position close

  const String uuid36 = 'b1f0d2ce-4bd1-4c0e-9a9e-5a1a7a6a1234';
  const int t = 1789101600000;

  // ref[1][N-1] = form slot N (NO +1).
  List<dynamic> refWith(List<String> form) => <dynamic>[<String>[], form];

  LedgerBuild build(String segment, {List<String> form = const <String>[]}) =>
      buildLedgerEntry(
        segment,
        refWith(form),
        tableVid: 1212121212,
        appVid: 1212121212,
        timeReceived: t,
        receivingPage: 'wfReqLeave',
        uid: 'uid-1',
      );

  // =========================================================================
  group('buildPublishSegment (compose side)', () {
    test('appends ⭘_k◼<uuid v4> with the dashes kept (36 chars)', () {
      final String out =
          buildPublishSegment('TESTMOBILE${hollow}_v${square}1');
      expect(out.startsWith('TESTMOBILE${hollow}_v${square}1'), true);
      final String tail = out.substring('TESTMOBILE${hollow}_v${square}1'.length);
      expect(tail.startsWith('${hollow}_k$square'), true);
      final String key = tail.substring('${hollow}_k$square'.length);
      expect(key.length, 36);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
              r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(key), true);
    });

    test('strips ⬤ to a space so the outer tb frame cannot shift', () {
      final String out = buildPublishSegment(
        'TESTMOBILE${hollow}_v${square}1${hollow}note${square}a${circle}b',
        idempotencyKey: uuid36,
      );
      expect(out.contains(circle), false);
      expect(out.contains('note${square}a b'), true);
      expect(out.endsWith('${hollow}_k$square$uuid36'), true);
    });

    test('empty in -> empty out (no _k on an absent config)', () {
      expect(buildPublishSegment(''), '');
    });
  });

  // =========================================================================
  group('publishSegmentFromTb (length guard)', () {
    String tb(List<String> segs) => segs.join(circle);

    test('1 / 3 / 4 / 5 segments -> empty publish segment', () {
      expect(publishSegmentFromTb(''), '');
      expect(publishSegmentFromTb(tb(<String>['add'])), '');
      expect(publishSegmentFromTb(tb(<String>['add', 'upd', 'del'])), '');
      expect(publishSegmentFromTb(tb(<String>['add', 'upd', 'del', 'ev'])), '');
      expect(
        publishSegmentFromTb(tb(<String>['add', 'upd', 'del', 'ev', 'uev'])),
        '',
      );
    });

    test('6 segments -> the 6th', () {
      expect(
        publishSegmentFromTb(
          tb(<String>['add', 'upd', 'del', 'ev', 'uev', 'PUB']),
        ),
        'PUB',
      );
    });

    test('6 segments with all the earlier ones empty -> still the 6th', () {
      expect(
        publishSegmentFromTb(tb(<String>['', '', '', '', '', 'PUB'])),
        'PUB',
      );
    });
  });

  // =========================================================================
  group('buildLedgerEntry happy path', () {
    final String segment = 'TESTMOBILE'
        '${hollow}_v${square}1'
        '${hollow}requestType${square}leave'
        '${hollow}days$square${ro}1$rc'
        '${hollow}_k$square$uuid36';

    test('ledgerCode, key, actionAt, meta excluded, all values String', () {
      final LedgerBuild b = build(segment, form: <String>['2']);
      expect(b.valid, true);
      final LedgerEntry e = b.entry!;
      expect(e.ledgerCode, 'TESTMOBILE');
      expect(e.key, uuid36);
      expect(e.actionAt, t);
      expect(e.historyId, t);
      expect(e.uid, 'uid-1');
      expect(e.attempted, false);
      expect(e.failed, false);

      final Map<String, dynamic> decoded =
          jsonDecode(e.body) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), <String>{'schemaVersion', 'data'});
      expect(decoded['schemaVersion'], 1);
      expect(decoded['schemaVersion'], isA<int>());
      final Map<String, dynamic> data =
          decoded['data'] as Map<String, dynamic>;
      expect(data, <String, dynamic>{
        'requestType': 'leave',
        'days': '2', // ◁1▷ resolved from ref[1][0], emitted as a String
        'actionAt': '1789101600000',
      });
      for (final dynamic v in data.values) {
        expect(v, isA<String>());
      }
      expect(data.containsKey('_v'), false);
      expect(data.containsKey('_k'), false);
      expect(data.containsKey('_collection'), false);
    });

    test('body is encoded ONCE and is byte-stable across two builds', () {
      final String b1 = build(segment, form: <String>['2']).entry!.body;
      final String b2 = build(segment, form: <String>['2']).entry!.body;
      expect(utf8.encode(b1), utf8.encode(b2));
      // A double-encode would yield a JSON *string* starting with a quote.
      expect(b1.startsWith('{'), true);
      expect(b1, '{"schemaVersion":1,"data":{"requestType":"leave",'
          '"days":"2","actionAt":"1789101600000"}}');
    });

    test('unknown _x meta key is ignored, not published', () {
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}_v${square}1${hollow}_x${square}whatever'
        '${hollow}a${square}b${hollow}_k$square$uuid36',
      );
      expect(b.valid, true);
      final Map<String, dynamic> data =
          (jsonDecode(b.entry!.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(data.containsKey('_x'), false);
      expect(data['a'], 'b');
    });

    test('a config-written actionAt is OVERWRITTEN by the queue time', () {
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}_v${square}1${hollow}actionAt${square}999'
        '${hollow}_k$square$uuid36',
      );
      expect(b.valid, true);
      final Map<String, dynamic> data =
          (jsonDecode(b.entry!.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(data['actionAt'], '1789101600000');
    });

    test('schemaVersion 2 stays an int (not coerced to a string)', () {
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}_v${square}2${hollow}a${square}b'
        '${hollow}_k$square$uuid36',
      );
      expect((jsonDecode(b.entry!.body) as Map<String, dynamic>)['schemaVersion'],
          2);
    });
  });

  // =========================================================================
  group('buildLedgerEntry invalid config', () {
    test('missing _v', () {
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}a${square}b${hollow}_k$square$uuid36',
      );
      expect(b.valid, false);
      expect(b.reason.contains('_v'), true);
      expect(b.ledgerCode, 'TESTMOBILE');
      expect(b.key, uuid36);
    });

    test('non-int _v', () {
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}_v${square}one${hollow}a${square}b'
        '${hollow}_k$square$uuid36',
      );
      expect(b.valid, false);
      expect(b.reason.contains('_v'), true);
    });

    test('lowercase ledgerCode', () {
      final LedgerBuild b = build(
        'testmobile${hollow}_v${square}1${hollow}a${square}b'
        '${hollow}_k$square$uuid36',
      );
      expect(b.valid, false);
      expect(b.reason.contains('ledgerCode'), true);
      // The key is still recovered so the failed entry can be de-duplicated.
      expect(b.key, uuid36);
    });

    test('ledgerCode too short', () {
      expect(
        build('ABC${hollow}_v${square}1${hollow}a${square}b'
                '${hollow}_k$square$uuid36')
            .valid,
        false,
      );
    });

    test('ledgerCode carrying a form token', () {
      expect(
        build('${ro}1$rc${hollow}_v${square}1${hollow}a${square}b'
                '${hollow}_k$square$uuid36')
            .valid,
        false,
      );
    });

    test('missing _k', () {
      final LedgerBuild b =
          build('TESTMOBILE${hollow}_v${square}1${hollow}a${square}b');
      expect(b.valid, false);
      expect(b.reason.contains('_k'), true);
      expect(b.key, '');
    });

    test('body over 256 KiB', () {
      final String big = 'x' * (256 * 1024 + 10);
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}_v${square}1${hollow}blob$square$big'
        '${hollow}_k$square$uuid36',
      );
      expect(b.valid, false);
      expect(b.reason, contains('> $ledgerMaxBodyBytes'));
    });

    test('a body just UNDER the cap is accepted', () {
      final String big = 'x' * (200 * 1024);
      final LedgerBuild b = build(
        'TESTMOBILE${hollow}_v${square}1${hollow}blob$square$big'
        '${hollow}_k$square$uuid36',
      );
      expect(b.valid, true);
    });
  });

  // =========================================================================
  group('convertStorageUrls (photo references)', () {
    const String url1 =
        'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/'
        'vertriz%2Fa%2Fone.jpg?alt=media&token=998fac83-0ead-4252-b7d1-aaa';
    const String url2 =
        'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/'
        'vertriz%2Fa%2Ftwo.jpg?alt=media&token=118fac83-0ead-4252-b7d1-bbb';
    const String gs1 = 'gs://otq-01-ase2/vertriz/a/one.jpg';
    const String gs2 = 'gs://otq-01-ase2/vertriz/a/two.jpg';

    test('single URL -> gs:// with the path URL-decoded', () {
      expect(convertStorageUrls(url1), gs1);
    });

    test('two URLs joined by a SPACE (post stringCleanUp shape)', () {
      expect(convertStorageUrls('$url1 $url2'), '$gs1 $gs2');
    });

    test('two URLs joined by ◇ (raw multi-image shape)', () {
      final String d = forbiddenCharacter[1]; // ◇
      expect(convertStorageUrls('$url1$d$url2'), '$gs1$d$gs2');
    });

    test('defaultImage becomes an EMPTY string, never a gs:// path', () {
      expect(convertStorageUrls(defaultImage), '');
      expect(convertStorageUrls(defaultImage).contains('gs://'), false);
      expect(convertStorageUrls('$defaultImage $url1'), ' $gs1');
    });

    test('non-URL value untouched', () {
      expect(convertStorageUrls('Lift macet'), 'Lift macet');
      expect(convertStorageUrls(''), '');
    });

    test('malformed URL (empty bucket) untouched', () {
      const String bad =
          'https://firebasestorage.googleapis.com/v0/b//o/x.jpg?alt=media';
      expect(convertStorageUrls(bad), bad);
    });

    test('a non-Firebase host untouched', () {
      const String other = 'https://example.com/v0/b/x/o/y.jpg?alt=media';
      expect(convertStorageUrls(other), other);
    });

    test('builder converts a URL arriving through ◁N▷ and flags the '
        'placeholder', () {
      final LedgerBuild ok = build(
        'TESTMOBILE${hollow}_v${square}1${hollow}photo$square${ro}1$rc'
        '${hollow}_k$square$uuid36',
        form: <String>[url1],
      );
      final Map<String, dynamic> data =
          (jsonDecode(ok.entry!.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(data['photo'], gs1);
      expect(ok.placeholderDropped, false);

      final LedgerBuild lost = build(
        'TESTMOBILE${hollow}_v${square}1${hollow}photo$square${ro}1$rc'
        '${hollow}_k$square$uuid36',
        form: <String>[defaultImage],
      );
      final Map<String, dynamic> lostData =
          (jsonDecode(lost.entry!.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(lostData['photo'], '');
      expect(lost.placeholderDropped, true);
    });
  });

  // =========================================================================
  // W3: `Uri.tryParse` returns non-null for almost anything, and a scheme-less
  // base yields a host-less request URI that `http` rejects with an
  // ArgumentError — mapped to `retryable` and retried forever, with the
  // one-per-session "GATEWAY_URL" report never firing. The gate must reject
  // those values BEFORE the POST.
  group('parseGatewayBaseUrl', () {
    test('empty -> null', () {
      expect(parseGatewayBaseUrl(''), null);
    });

    test('"not a url" parses but has no scheme -> null', () {
      expect(Uri.tryParse('not a url'), isNotNull); // the trap
      expect(parseGatewayBaseUrl('not a url'), null);
    });

    test('host only, no scheme -> null', () {
      expect(parseGatewayBaseUrl('gw.example.run.app'), null);
    });

    test('unparseable -> null', () {
      expect(parseGatewayBaseUrl(':::'), null);
    });

    test('absolute https -> non-null with the host preserved', () {
      final Uri? u = parseGatewayBaseUrl('https://gw.example.run.app');
      expect(u, isNotNull);
      expect(u!.host, 'gw.example.run.app');
    });

    test('http is rejected in release, allowed only with allowHttp', () {
      expect(parseGatewayBaseUrl('http://10.0.2.2:8080', allowHttp: false),
          null);
      expect(parseGatewayBaseUrl('http://10.0.2.2:8080', allowHttp: true),
          isNotNull);
    });

    test('surrounding whitespace is trimmed', () {
      expect(parseGatewayBaseUrl(' https://gw.example.run.app '), isNotNull);
    });

    test('a base path is rejected (the client builds /v1/ledgers/… itself)',
        () {
      expect(parseGatewayBaseUrl('https://gw.example.run.app/v1'), null);
      expect(parseGatewayBaseUrl('https://gw.example.run.app/api/'), null);
    });

    test('a bare trailing slash is accepted', () {
      expect(parseGatewayBaseUrl('https://gw.example.run.app/'), isNotNull);
    });

    test('the compiled-in default parses to the otq-01 gateway host', () {
      expect(parseGatewayBaseUrl(gatewayUrl, allowHttp: false)?.host,
          'pub-sub-gateway-721538991284.asia-southeast2.run.app');
    });
  });
}
