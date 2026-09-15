import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/gateway/ledger_publish.dart';

void main() {
  LedgerEntry entry({
    String key = 'b1f0d2ce-4bd1-4c0e-9a9e-5a1a7a6a1234',
    String body = '{"schemaVersion":1,"data":{"a":"b"}}',
    bool attempted = false,
    int notBefore = 0,
    bool failed = false,
    String error = '',
    String errorId = '',
    int failedAt = 0,
  }) =>
      LedgerEntry(
        key: key,
        uid: 'uid-1',
        ledgerCode: 'TESTMOBILE',
        body: body,
        actionAt: 1789101600000,
        historyId: 1789101600000,
        attempted: attempted,
        notBefore: notBefore,
        failed: failed,
        error: error,
        errorId: errorId,
        failedAt: failedAt,
      );

  group('encode/decode round trip', () {
    test('two entries survive with EVERY field intact', () {
      final LedgerEntry a = entry(attempted: true, notBefore: 1789101700000);
      final LedgerEntry b = entry(
        key: 'c2a1e3df-5ce2-4d1f-8b0f-6b2b8b7b2345',
        attempted: true,
        failed: true,
        error: 'validation_error',
        errorId: 'req-abc123',
        failedAt: 1789101800000,
      );

      final List<LedgerEntry> back =
          decodeLedgerOutbox(encodeLedgerOutbox(<LedgerEntry>[a, b]));

      expect(back.length, 2);
      expect(back[0].key, a.key);
      expect(back[0].uid, 'uid-1');
      expect(back[0].ledgerCode, 'TESTMOBILE');
      expect(back[0].body, a.body);
      expect(back[0].actionAt, 1789101600000);
      expect(back[0].historyId, 1789101600000);
      expect(back[0].attempted, true);
      expect(back[0].notBefore, 1789101700000);
      expect(back[0].failed, false);
      expect(back[1].key, b.key);
      expect(back[1].failed, true);
      expect(back[1].error, 'validation_error');
      expect(back[1].errorId, 'req-abc123');
      expect(back[1].failedAt, 1789101800000);
    });

    test('an empty outbox round-trips as an empty list', () {
      expect(encodeLedgerOutbox(<LedgerEntry>[]), '[]');
      expect(decodeLedgerOutbox('[]'), isEmpty);
    });
  });

  group('decodeLedgerOutbox tolerates every stored shape', () {
    test('null / empty / the literal "null" -> empty list', () {
      // 'null' is what clearLedgerOutbox writes, and secure storage hands back
      // an empty string on some platforms.
      expect(decodeLedgerOutbox(null), isEmpty);
      expect(decodeLedgerOutbox(''), isEmpty);
      expect(decodeLedgerOutbox('null'), isEmpty);
    });

    test('a JSON object (not a list) -> empty list, NO error reported', () {
      final List<String> reported = <String>[];
      expect(
        decodeLedgerOutbox('{"key":"x"}', onError: reported.add),
        isEmpty,
      );
      expect(reported, isEmpty); // valid JSON, just the wrong shape
    });

    test('a non-Map element is skipped, the Map next to it survives', () {
      final String raw = '[3,"x",null,${jsonEncode(entry().toJson())}]';
      final List<LedgerEntry> back = decodeLedgerOutbox(raw);
      expect(back.length, 1);
      expect(back[0].key, 'b1f0d2ce-4bd1-4c0e-9a9e-5a1a7a6a1234');
    });
  });

  group('LedgerEntry.fromJson coercion (stored JSON is dynamic)', () {
    test('String numbers are parsed; only a real true counts as true', () {
      final LedgerEntry e = LedgerEntry.fromJson(<String, dynamic>{
        'key': 'k',
        'actionAt': '123',
        'historyId': '456',
        'notBefore': '789',
        'failedAt': '1011',
        'attempted': 'true', // a String, NOT a bool
        'failed': 1, // a number, NOT a bool
      });
      expect(e.actionAt, 123);
      expect(e.historyId, 456);
      expect(e.notBefore, 789);
      expect(e.failedAt, 1011);
      expect(e.attempted, false);
      expect(e.failed, false);
    });

    test('missing fields fall back to defaults instead of throwing', () {
      final LedgerEntry e = LedgerEntry.fromJson(<String, dynamic>{});
      expect(e.key, '');
      expect(e.uid, '');
      expect(e.ledgerCode, '');
      expect(e.body, '');
      expect(e.actionAt, 0);
      expect(e.historyId, 0);
      expect(e.attempted, false);
      expect(e.notBefore, 0);
      expect(e.failed, false);
      expect(e.error, '');
      expect(e.errorId, '');
      expect(e.failedAt, 0);
    });

    test('a non-numeric actionAt degrades to 0, it does not throw', () {
      final LedgerEntry e =
          LedgerEntry.fromJson(<String, dynamic>{'actionAt': 'abc'});
      expect(e.actionAt, 0);
    });
  });

  // W2 regression. A kill mid-secureWrite leaves a truncated blob, and
  // `FormatException.toString()` embeds ~78 characters of its source around the
  // offset. The source here is the outbox, whose `body` field holds the encoded
  // request payload — so `errorReport('...: $e')` would ship real `data` values
  // to Crashlytics. The report must carry the blob LENGTH and
  // `FormatException.message` only.
  group('decode failure never reports the payload', () {
    const String marker = 'SECRET-PAYLOAD-MARKER';

    String truncatedBlob() {
      final String full = encodeLedgerOutbox(<LedgerEntry>[
        entry(body: '{"schemaVersion":1,"data":{"reason":"$marker"}}'),
      ]);
      final int at = full.indexOf(marker);
      expect(at, greaterThan(-1));
      // Cut a few chars past the marker: the parse then fails at end-of-input,
      // which is exactly where FormatException's context window sits.
      return full.substring(0, at + marker.length + 5);
    }

    test('the RAW FormatException really does leak the payload', () {
      // Pins the premise — without it the assertion below proves nothing.
      final String raw = truncatedBlob();
      Object? caught;
      try {
        jsonDecode(raw);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FormatException>());
      expect(caught.toString().contains(marker), true);
    });

    test('truncated blob -> empty list, ONE report, payload NOT in it', () {
      final String raw = truncatedBlob();
      final List<String> reported = <String>[];
      expect(decodeLedgerOutbox(raw, onError: reported.add), isEmpty);
      expect(reported.length, 1);
      expect(reported.first.contains(marker), false);
      expect(reported.first.contains('${raw.length} chars'), true);
      expect(reported.first.contains('Unexpected end of input'), true);
    });
  });

  // C1 regression. `loadLedgerOutbox` must NOT turn a FAILED secure-storage
  // read into an empty outbox: `_outbox = []` would be cached for the rest of
  // the process and the next `saveLedgerOutbox()` would overwrite the stored
  // queue — the entries there are the ONLY copy (their history records are
  // already marked sent), so the loss is permanent and silent. This is the
  // `_HISTORY` blank-overwrite class of bug.
  //
  // Fault injection = the read genuinely throwing. In a plain `flutter_test`
  // nothing initialises the global `storage` (`lib/global.dart:520` declares it
  // as an uninitialised `dynamic`, assigned only inside `globalInit`), and the
  // flutter_secure_storage plugin is not registered either, so
  // `storage.read(...)` throws — a `NoSuchMethodError` here, a
  // `MissingPluginException` once `storage` holds a real instance, a
  // `LateInitializationError` if it were declared `late`. Any of the three is
  // the "read failed" path, which is why the assertion is `throwsA(anything)`.
  group('a FAILED read never becomes an empty outbox', () {
    test('load throws, and no blank list is cached or persisted', () async {
      resetLedgerOutboxForTest();

      await expectLater(loadLedgerOutbox(), throwsA(anything));

      // Nothing cached: `saveLedgerOutbox` is a no-op, so the stored queue is
      // untouched. (secureWrite swallows its own failures, so "did not throw"
      // alone proves nothing — the retry below is what pins it.)
      await saveLedgerOutbox();

      // The load was NOT memoised as []: the next caller retries the read.
      await expectLater(loadLedgerOutbox(), throwsA(anything));
    });
  });
}
