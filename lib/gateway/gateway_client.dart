import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// What the caller must do with an outbox entry after one POST attempt.
enum PublishOutcomeKind {
  /// `202 Accepted`, including `duplicate: true` — remove the entry.
  success,

  /// Permanent client/config error (400/404/405/409/413/422 and any other
  /// non-401 4xx). Retrying cannot help: mark the entry failed, keep draining.
  rejected,

  /// `401` after one forced token refresh, or no ID token at all. Keep the
  /// entry, stop the cycle, NEVER sign the user out.
  unauthenticated,

  /// 5xx / timeout / socket / non-JSON 5xx — keep the entry, try a later cycle.
  retryable,
}

/// Result of one publish attempt. NEVER carries the request body.
class PublishOutcome {
  const PublishOutcome({
    required this.kind,
    this.statusCode,
    this.errorCode = '',
    this.errorId = '',
    this.duplicate = false,
    this.retryAfterSeconds,
    this.responseBody = '',
  });

  final PublishOutcomeKind kind;

  /// null for transport failures (timeout / connection error).
  final int? statusCode;

  /// Gateway `error` (closed vocabulary), or `network_error` /
  /// `network_timeout` / `unexpected_response`.
  final String errorCode;

  /// Gateway `errorId`, else the `X-Request-Id` header. The only id the backend
  /// can use to find the matching log line.
  final String errorId;

  /// `202` with `duplicate: true` — still success.
  final bool duplicate;

  /// `Retry-After` in seconds when the gateway sent one (seconds format only;
  /// an HTTP-date value yields null).
  final int? retryAfterSeconds;

  /// Raw response body (UTF-8, malformed bytes replaced); '' when no response
  /// arrived. For DEBUG logging only — never forward it to Crashlytics.
  final String responseBody;

  @override
  String toString() =>
      'PublishOutcome(${kind.name} $statusCode $errorCode errorId=$errorId'
      '${duplicate ? ' duplicate' : ''}'
      '${retryAfterSeconds == null ? '' : ' retryAfter=$retryAfterSeconds'})';
}

/// Case-insensitive header read. `dart:io` lowercases response header names, but
/// `MockClient` hands back exactly what the test wrote — reading both ways keeps
/// a test assertion on the same code path production uses.
String gatewayHeader(Map<String, String> headers, String name) {
  final String want = name.toLowerCase();
  for (final MapEntry<String, String> e in headers.entries) {
    if (e.key.toLowerCase() == want) return e.value;
  }
  return '';
}

/// POST one already-encoded [body] to
/// `{baseUrl}/v1/ledgers/{ledgerCode}/messages`.
///
/// Seams ([client], [getIdToken], [baseUrl]) are injected so this is unit
/// testable with `package:http/testing.dart` MockClient and no Firebase.
///
/// Deliberately different from the reference client in `FLUTTER_v2.md` §5: NO
/// internal retry loop (one attempt per drain cycle — the outbox owns retry) and
/// NO signOut on 401 (a background job must never log the user out).
Future<PublishOutcome> publishToGateway({
  required http.Client client,
  required Uri baseUrl,
  required Future<String?> Function({bool forceRefresh}) getIdToken,
  required String ledgerCode,
  required String idempotencyKey,
  required String body,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final Uri uri = baseUrl.replace(
    path: '/v1/ledgers/${Uri.encodeComponent(ledgerCode)}/messages',
  );
  bool refreshed = false;
  while (true) {
    String? token;
    try {
      token = await getIdToken(forceRefresh: refreshed);
    } catch (_) {
      // Token fetch failed (network-request-failed, user-token-expired, …).
      // Same cycle-stopping outcome as a transport failure; never escapes.
      return const PublishOutcome(
        kind: PublishOutcomeKind.retryable,
        errorCode: 'token_error',
      );
    }
    if (token == null || token.isEmpty) {
      return const PublishOutcome(
        kind: PublishOutcomeKind.unauthenticated,
        statusCode: 401,
        errorCode: 'unauthenticated',
      );
    }
    http.Response res;
    try {
      res = await client
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Idempotency-Key': idempotencyKey,
              'Content-Type': 'application/json',
              'X-Client-Source': 'mobile',
            },
            body: utf8.encode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      return const PublishOutcome(
        kind: PublishOutcomeKind.retryable,
        errorCode: 'network_timeout',
      );
    } on SocketException {
      return const PublishOutcome(
        kind: PublishOutcomeKind.retryable,
        errorCode: 'network_error',
      );
    } on http.ClientException {
      return const PublishOutcome(
        kind: PublishOutcomeKind.retryable,
        errorCode: 'network_error',
      );
    } catch (_) {
      // Any other transport failure. This runs inside an un-awaited drain, and
      // an escaping error is recorded as a FATAL by platformDispatcher.onError
      // (main.dart), so nothing may escape.
      return const PublishOutcome(
        kind: PublishOutcomeKind.retryable,
        errorCode: 'network_error',
      );
    }

    // Decoded once: parsed below and handed back for debug logging.
    final String resBody = utf8.decode(res.bodyBytes, allowMalformed: true);

    if (res.statusCode == 202) {
      bool duplicate = false;
      try {
        final dynamic j = jsonDecode(resBody);
        if (j is Map) duplicate = j['duplicate'] == true;
      } catch (_) {
        // A 202 with an unreadable body is still success.
      }
      return PublishOutcome(
        kind: PublishOutcomeKind.success,
        statusCode: 202,
        duplicate: duplicate,
        responseBody: resBody,
      );
    }

    String errorCode = 'unexpected_response';
    String errorId = gatewayHeader(res.headers, 'X-Request-Id');
    try {
      final dynamic j = jsonDecode(resBody);
      if (j is Map) {
        final Object? code = j['error'];
        if (code != null && code.toString().isNotEmpty) {
          errorCode = code.toString();
        }
        final Object? id = j['errorId'];
        if (id != null && id.toString().isNotEmpty) errorId = id.toString();
      }
    } catch (_) {
      // Non-JSON body: a 5xx HTML page from Google infra in front of Cloud Run.
    }

    if (res.statusCode == 401) {
      if (!refreshed) {
        refreshed = true;
        continue; // force-refresh the ID token and try exactly once more
      }
      return PublishOutcome(
        kind: PublishOutcomeKind.unauthenticated,
        statusCode: 401,
        errorCode: errorCode,
        errorId: errorId,
        responseBody: resBody,
      );
    }
    if (res.statusCode >= 500) {
      return PublishOutcome(
        kind: PublishOutcomeKind.retryable,
        statusCode: res.statusCode,
        errorCode: errorCode,
        errorId: errorId,
        retryAfterSeconds: int.tryParse(
          gatewayHeader(res.headers, 'Retry-After').trim(),
        ),
        responseBody: resBody,
      );
    }
    return PublishOutcome(
      kind: PublishOutcomeKind.rejected,
      statusCode: res.statusCode,
      errorCode: errorCode,
      errorId: errorId,
      responseBody: resBody,
    );
  }
}
