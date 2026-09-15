import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otonomiq/gateway/gateway_client.dart';

void main() {
  final Uri base = Uri.parse('https://gw.example.run.app');
  const String body = '{"schemaVersion":1,"data":{"a":"b"}}';

  // A getIdToken seam that records every forceRefresh value it was asked for.
  ({Future<String?> Function({bool forceRefresh}) fn, List<bool> calls})
      tokenSpy({String? token = 'tok'}) {
    final List<bool> calls = <bool>[];
    Future<String?> fn({bool forceRefresh = false}) async {
      calls.add(forceRefresh);
      return token;
    }
    return (fn: fn, calls: calls);
  }

  Future<PublishOutcome> run(
    MockClient client, {
    Future<String?> Function({bool forceRefresh})? getIdToken,
    String ledgerCode = 'TESTMOBILE',
    String key = 'b1f0d2ce-4bd1-4c0e-9a9e-5a1a7a6a1234',
  }) =>
      publishToGateway(
        client: client,
        baseUrl: base,
        getIdToken: getIdToken ?? tokenSpy().fn,
        ledgerCode: ledgerCode,
        idempotencyKey: key,
        body: body,
      );

  group('202 success', () {
    test('202 duplicate:false -> success', () async {
      final out = await run(MockClient((_) async => http.Response(
            '{"messageId":"1","requestId":"r","ledgerCode":"TESTMOBILE",'
            '"duplicate":false}',
            202,
          )));
      expect(out.kind, PublishOutcomeKind.success);
      expect(out.duplicate, false);
      expect(out.statusCode, 202);
      expect(out.responseBody, contains('"messageId":"1"'));
    });

    test('202 duplicate:true is ALSO success', () async {
      final out = await run(MockClient((_) async => http.Response(
            '{"messageId":"1","requestId":"r","ledgerCode":"TESTMOBILE",'
            '"duplicate":true}',
            202,
          )));
      expect(out.kind, PublishOutcomeKind.success);
      expect(out.duplicate, true);
    });

    test('202 with an unreadable body is still success', () async {
      final out = await run(MockClient((_) async => http.Response('', 202)));
      expect(out.kind, PublishOutcomeKind.success);
      expect(out.duplicate, false);
    });
  });

  test('headers, URL and body bytes', () async {
    http.Request? seen;
    final out = await run(MockClient((http.Request r) async {
      seen = r;
      return http.Response('{"duplicate":false}', 202);
    }));
    expect(out.kind, PublishOutcomeKind.success);
    expect(seen!.method, 'POST');
    expect(seen!.url.toString(),
        'https://gw.example.run.app/v1/ledgers/TESTMOBILE/messages');
    expect(seen!.headers['Authorization'], 'Bearer tok');
    expect(seen!.headers['Idempotency-Key'],
        'b1f0d2ce-4bd1-4c0e-9a9e-5a1a7a6a1234');
    expect(seen!.headers['Content-Type'], 'application/json');
    expect(seen!.headers['X-Client-Source'], 'mobile');
    // The bytes on the wire are exactly the stored body string.
    expect(seen!.bodyBytes, utf8.encode(body));
  });

  group('4xx -> rejected (non-retryable)', () {
    test('400 carries error + errorId from the JSON body', () async {
      final out = await run(MockClient((_) async => http.Response(
            '{"error":"validation_failed","errorId":"01M2040D0MXG"}',
            400,
          )));
      expect(out.kind, PublishOutcomeKind.rejected);
      expect(out.statusCode, 400);
      expect(out.errorCode, 'validation_failed');
      expect(out.errorId, '01M2040D0MXG');
      expect(out.responseBody,
          '{"error":"validation_failed","errorId":"01M2040D0MXG"}');
    });

    test('404 ledger_not_found -> rejected', () async {
      final out = await run(MockClient((_) async =>
          http.Response('{"error":"ledger_not_found","errorId":"e1"}', 404)));
      expect(out.kind, PublishOutcomeKind.rejected);
      expect(out.errorCode, 'ledger_not_found');
    });

    test('errorId falls back to the X-Request-Id header', () async {
      final out = await run(MockClient((_) async => http.Response(
            '{"error":"idempotency_conflict"}',
            409,
            headers: <String, String>{'x-request-id': 'HDR-ID'},
          )));
      expect(out.kind, PublishOutcomeKind.rejected);
      expect(out.errorCode, 'idempotency_conflict');
      expect(out.errorId, 'HDR-ID');
    });
  });

  group('401', () {
    test('401 then 202 -> success, forceRefresh asked exactly once', () async {
      final spy = tokenSpy();
      int calls = 0;
      final out = await run(
        MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('{"error":"unauthenticated"}', 401)
              : http.Response('{"duplicate":false}', 202);
        }),
        getIdToken: spy.fn,
      );
      expect(out.kind, PublishOutcomeKind.success);
      expect(calls, 2);
      expect(spy.calls, <bool>[false, true]);
    });

    test('401 twice -> unauthenticated, exactly two requests', () async {
      final spy = tokenSpy();
      int calls = 0;
      final out = await run(
        MockClient((_) async {
          calls++;
          return http.Response('{"error":"unauthenticated"}', 401);
        }),
        getIdToken: spy.fn,
      );
      expect(out.kind, PublishOutcomeKind.unauthenticated);
      expect(calls, 2);
      expect(spy.calls, <bool>[false, true]);
    });

    test('null ID token -> unauthenticated with ZERO requests', () async {
      int calls = 0;
      final out = await run(
        MockClient((_) async {
          calls++;
          return http.Response('{"duplicate":false}', 202);
        }),
        getIdToken: tokenSpy(token: null).fn,
      );
      expect(out.kind, PublishOutcomeKind.unauthenticated);
      expect(calls, 0);
    });

    // W1: `User.getIdToken` does a network round-trip and rejects with a
    // FirebaseAuthException (network-request-failed, user-token-expired, a
    // revoked refresh token). `send` MUST never throw — an escape aborts the
    // drain loop from the middle instead of taking the retryable path, and is
    // recorded as a FATAL by platformDispatcher.onError.
    test('getIdToken throws -> retryable token_error with ZERO requests',
        () async {
      int calls = 0;
      final out = await run(
        MockClient((_) async {
          calls++;
          return http.Response('{"duplicate":false}', 202);
        }),
        getIdToken: ({bool forceRefresh = false}) async =>
            throw StateError('auth down'),
      );
      expect(out.kind, PublishOutcomeKind.retryable);
      expect(out.errorCode, 'token_error');
      expect(calls, 0);
    });
  });

  group('retryable', () {
    test('503 honours Retry-After seconds', () async {
      final out = await run(MockClient((_) async => http.Response(
            '{"error":"publish_unavailable","errorId":"x"}',
            503,
            headers: <String, String>{'retry-after': '7'},
          )));
      expect(out.kind, PublishOutcomeKind.retryable);
      expect(out.retryAfterSeconds, 7);
      expect(out.errorCode, 'publish_unavailable');
    });

    test('500 -> retryable, no Retry-After', () async {
      final out = await run(MockClient(
          (_) async => http.Response('{"error":"internal_error"}', 500)));
      expect(out.kind, PublishOutcomeKind.retryable);
      expect(out.retryAfterSeconds, isNull);
      expect(out.errorCode, 'internal_error');
    });

    test('502 HTML body -> retryable + unexpected_response', () async {
      final out = await run(MockClient((_) async => http.Response(
            '<html><body>502 Bad Gateway</body></html>',
            502,
            headers: <String, String>{'content-type': 'text/html'},
          )));
      expect(out.kind, PublishOutcomeKind.retryable);
      expect(out.errorCode, 'unexpected_response');
      expect(out.responseBody, contains('502 Bad Gateway'));
    });

    test('ClientException -> retryable network_error', () async {
      final out = await run(
          MockClient((_) async => throw http.ClientException('broken pipe')));
      expect(out.kind, PublishOutcomeKind.retryable);
      expect(out.errorCode, 'network_error');
      expect(out.statusCode, isNull);
      expect(out.responseBody, '');
    });

    test('TimeoutException -> retryable network_timeout', () async {
      final out = await run(MockClient(
          (_) async => throw TimeoutException('slow', const Duration(
                seconds: 15,
              ))));
      expect(out.kind, PublishOutcomeKind.retryable);
      expect(out.errorCode, 'network_timeout');
    });
  });
}
