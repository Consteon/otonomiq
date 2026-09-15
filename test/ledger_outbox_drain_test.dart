import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otonomiq/gateway/gateway_client.dart';
import 'package:otonomiq/gateway/ledger_publish.dart';

void main() {
  const int now = 1789101600000;
  final Uri base = Uri.parse('https://gw.example.run.app');

  LedgerEntry entry(
    String key, {
    int actionAt = now,
    String uid = 'uid-1',
    bool attempted = false,
    int notBefore = 0,
    bool failed = false,
    int failedAt = 0,
  }) =>
      LedgerEntry(
        key: key,
        uid: uid,
        ledgerCode: 'TESTMOBILE',
        body: '{"schemaVersion":1,"data":{"a":"$key"}}',
        actionAt: actionAt,
        historyId: actionAt,
        attempted: attempted,
        notBefore: notBefore,
        failed: failed,
        failedAt: failedAt,
      );

  /// Fake store + ordered event log. `persist` and `send` both append, so the
  /// log proves the ORDER of side effects, not just that they happened.
  ({
    LedgerDrainDeps deps,
    List<String> log,
    List<LedgerEntry> entries,
  }) harness(
    List<LedgerEntry> entries,
    PublishOutcome Function(LedgerEntry e) respond, {
    int nowMs = now,
    String currentUid = 'uid-1',
  }) {
    final List<String> log = <String>[];
    final LedgerDrainDeps deps = LedgerDrainDeps(
      entries: entries,
      nowMs: nowMs,
      currentUid: currentUid,
      persist: () async => log.add('persist:${entries.length}'),
      send: (LedgerEntry e) async {
        log.add('send:${e.key}:attempted=${e.attempted}');
        return respond(e);
      },
    );
    return (deps: deps, log: log, entries: entries);
  }

  const PublishOutcome ok = PublishOutcome(
    kind: PublishOutcomeKind.success,
    statusCode: 202,
  );

  // =========================================================================
  group('runLedgerDrain — outcomes', () {
    test('success removes the entry and persists', () async {
      final h = harness(<LedgerEntry>[entry('k1')], (_) => ok);
      await runLedgerDrain(h.deps);
      expect(h.entries, isEmpty);
      expect(h.log, <String>[
        'persist:1', // attempted=true, BEFORE the POST
        'send:k1:attempted=true',
        'persist:0', // after removal
      ]);
    });

    test('attempted is persisted BEFORE the request', () async {
      final h = harness(<LedgerEntry>[entry('k1')], (_) => ok);
      await runLedgerDrain(h.deps);
      expect(h.log.first, 'persist:1');
      expect(h.log[1], 'send:k1:attempted=true');
    });

    test('4xx marks the entry failed and CONTINUES to the next entry',
        () async {
      final h = harness(
        <LedgerEntry>[
          entry('k1', actionAt: now - 2000),
          entry('k2', actionAt: now - 1000),
        ],
        (LedgerEntry e) => e.key == 'k1'
            ? const PublishOutcome(
                kind: PublishOutcomeKind.rejected,
                statusCode: 404,
                errorCode: 'ledger_not_found',
                errorId: 'E-404',
              )
            : ok,
      );
      await runLedgerDrain(h.deps);
      expect(h.entries.length, 1);
      final LedgerEntry dead = h.entries.single;
      expect(dead.key, 'k1');
      expect(dead.failed, true);
      expect(dead.error, 'ledger_not_found');
      expect(dead.errorId, 'E-404');
      expect(dead.failedAt, now);
      // k2 was still attempted and succeeded.
      expect(h.log.where((String s) => s.startsWith('send:')).toList(),
          <String>['send:k1:attempted=true', 'send:k2:attempted=true']);
    });

    test('5xx STOPS the cycle — the second entry is never requested', () async {
      final h = harness(
        <LedgerEntry>[
          entry('k1', actionAt: now - 2000),
          entry('k2', actionAt: now - 1000),
        ],
        (_) => const PublishOutcome(
          kind: PublishOutcomeKind.retryable,
          statusCode: 503,
          errorCode: 'publish_unavailable',
          retryAfterSeconds: 7,
        ),
      );
      await runLedgerDrain(h.deps);
      expect(h.log.where((String s) => s.startsWith('send:')).toList(),
          <String>['send:k1:attempted=true']);
      expect(h.entries.length, 2);
      expect(h.entries.first.notBefore, now + 7000); // Retry-After honoured
      expect(h.entries.first.failed, false);
    });

    test('retryable with NO Retry-After sets notBefore to now', () async {
      final h = harness(
        <LedgerEntry>[entry('k1')],
        (_) => const PublishOutcome(
          kind: PublishOutcomeKind.retryable,
          errorCode: 'network_error',
        ),
      );
      await runLedgerDrain(h.deps);
      expect(h.entries.single.notBefore, now);
    });

    test('401 STOPS the cycle and keeps the entry unfailed', () async {
      final h = harness(
        <LedgerEntry>[entry('k1', actionAt: now - 2000), entry('k2')],
        (_) => const PublishOutcome(
          kind: PublishOutcomeKind.unauthenticated,
          statusCode: 401,
          errorCode: 'unauthenticated',
        ),
      );
      await runLedgerDrain(h.deps);
      expect(h.entries.length, 2);
      expect(h.entries.first.failed, false);
      expect(h.log.where((String s) => s.startsWith('send:')).toList(),
          <String>['send:k1:attempted=true']);
    });
  });

  // =========================================================================
  group('runLedgerDrain — skips', () {
    test('failed entries are skipped', () async {
      final h = harness(
        <LedgerEntry>[entry('k1', failed: true, failedAt: now)],
        (_) => ok,
      );
      await runLedgerDrain(h.deps);
      expect(h.log, isEmpty);
      expect(h.entries.length, 1);
    });

    test('notBefore in the future is honoured', () async {
      final h = harness(
        <LedgerEntry>[entry('k1', notBefore: now + 1)],
        (_) => ok,
      );
      await runLedgerDrain(h.deps);
      expect(h.log, isEmpty);
    });

    test('an entry belonging to ANOTHER uid is skipped', () async {
      final h = harness(<LedgerEntry>[entry('k1', uid: 'uid-other')], (_) => ok);
      await runLedgerDrain(h.deps);
      expect(h.log, isEmpty);
      expect(h.entries.length, 1);
    });

    test('an entry with NO uid is sent and adopts the current user', () async {
      final h = harness(<LedgerEntry>[entry('k1', uid: '')], (_) => ok);
      await runLedgerDrain(h.deps);
      expect(h.log.any((String s) => s.startsWith('send:')), true);
      expect(h.entries, isEmpty);
    });

    test('a stale attempted entry older than 24h is STILL sent', () async {
      final h = harness(
        <LedgerEntry>[
          entry('k1', attempted: true, actionAt: now - ledgerIdempotencyWindowMs - 1),
        ],
        (_) => ok,
      );
      await runLedgerDrain(h.deps);
      expect(h.entries, isEmpty);
    });
  });

  // =========================================================================
  test('entries are drained FIFO by actionAt', () async {
    final h = harness(
      <LedgerEntry>[
        entry('newest', actionAt: now - 100),
        entry('oldest', actionAt: now - 900),
        entry('middle', actionAt: now - 500),
      ],
      (_) => ok,
    );
    await runLedgerDrain(h.deps);
    expect(h.log.where((String s) => s.startsWith('send:')).toList(), <String>[
      'send:oldest:attempted=true',
      'send:middle:attempted=true',
      'send:newest:attempted=true',
    ]);
  });

  // =========================================================================
  group('runLedgerDrain over the real client (MockClient)', () {
    Future<void> drainWith(
      List<LedgerEntry> entries,
      MockClient client,
      List<String> log,
    ) =>
        runLedgerDrain(LedgerDrainDeps(
          entries: entries,
          nowMs: now,
          currentUid: 'uid-1',
          persist: () async => log.add('persist:${entries.length}'),
          send: (LedgerEntry e) => publishToGateway(
            client: client,
            baseUrl: base,
            getIdToken: ({bool forceRefresh = false}) async => 'tok',
            ledgerCode: e.ledgerCode,
            idempotencyKey: e.key,
            body: e.body,
          ),
        ));

    test('202 duplicate:true drains the entry', () async {
      final List<LedgerEntry> entries = <LedgerEntry>[entry('k1')];
      final List<String> log = <String>[];
      await drainWith(
        entries,
        MockClient((_) async => http.Response('{"duplicate":true}', 202)),
        log,
      );
      expect(entries, isEmpty);
    });

    test('404 from the gateway marks the entry failed, body untouched',
        () async {
      final List<LedgerEntry> entries = <LedgerEntry>[entry('k1')];
      final List<String> log = <String>[];
      await drainWith(
        entries,
        MockClient((_) async =>
            http.Response('{"error":"ledger_not_found","errorId":"E1"}', 404)),
        log,
      );
      expect(entries.single.failed, true);
      expect(entries.single.error, 'ledger_not_found');
      expect(entries.single.errorId, 'E1');
      expect(entries.single.body, '{"schemaVersion":1,"data":{"a":"k1"}}');
    });
  });

  // =========================================================================
  group('trimLedgerOutbox', () {
    test('removes only FAILED entries older than 30 days', () async {
      final int old = now - (ledgerFailedMaxDayAge + 1) * 86400000;
      final List<LedgerEntry> entries = <LedgerEntry>[
        entry('oldFailed', failed: true, failedAt: old),
        entry('newFailed', failed: true, failedAt: now - 1000),
        entry('oldPending', actionAt: old), // pending: never trimmed by age
      ];
      final int removed = trimLedgerOutbox(entries, now);
      expect(removed, 1);
      expect(entries.map((LedgerEntry e) => e.key).toList(),
          <String>['newFailed', 'oldPending']);
    });

    test('a failed entry with failedAt 0 is never trimmed', () {
      final List<LedgerEntry> entries = <LedgerEntry>[
        entry('k1', failed: true),
      ];
      expect(trimLedgerOutbox(entries, now), 0);
      expect(entries.length, 1);
    });
  });

  // =========================================================================
  group('ledgerEntryToAppend (enqueue idempotency)', () {
    LedgerBuild goodBuild(String key) => LedgerBuild.ok(entry(key));

    test('a key already queued yields null — enqueue is a no-op', () {
      final List<LedgerEntry> queued = <LedgerEntry>[entry('k1')];
      expect(
        ledgerEntryToAppend(queued, goodBuild('k1'),
            key: 'k1', uid: 'uid-1', historyId: now, nowMs: now),
        isNull,
      );
    });

    test('a new key yields the built entry', () {
      final List<LedgerEntry> queued = <LedgerEntry>[entry('k1')];
      final LedgerEntry? e = ledgerEntryToAppend(queued, goodBuild('k2'),
          key: 'k2', uid: 'uid-1', historyId: now, nowMs: now);
      expect(e, isNotNull);
      expect(e!.key, 'k2');
      expect(e.failed, false);
    });

    test('an invalid build yields a FAILED entry with no body', () {
      final LedgerEntry? e = ledgerEntryToAppend(
        <LedgerEntry>[],
        LedgerBuild.invalid('_v is missing or not an int',
            key: 'k9', ledgerCode: 'TESTMOBILE'),
        key: 'k9',
        uid: 'uid-1',
        historyId: now,
        nowMs: now,
      );
      expect(e, isNotNull);
      expect(e!.failed, true);
      expect(e.error, 'invalid_config');
      expect(e.body, '');
      expect(e.ledgerCode, 'TESTMOBILE');
      expect(e.failedAt, now);
    });

    test('an invalid build whose key is already queued is still a no-op', () {
      final List<LedgerEntry> queued = <LedgerEntry>[
        entry('k9', failed: true, failedAt: now),
      ];
      expect(
        ledgerEntryToAppend(
          queued,
          LedgerBuild.invalid('bad', key: 'k9', ledgerCode: 'TESTMOBILE'),
          key: 'k9',
          uid: 'uid-1',
          historyId: now,
          nowMs: now,
        ),
        isNull,
      );
    });
  });

  // =========================================================================
  test('a drained failed entry is NOT re-sent on the next cycle', () async {
    final List<LedgerEntry> entries = <LedgerEntry>[entry('k1')];
    final h1 = harness(
      entries,
      (_) => const PublishOutcome(
        kind: PublishOutcomeKind.rejected,
        statusCode: 400,
        errorCode: 'validation_failed',
      ),
    );
    await runLedgerDrain(h1.deps);
    expect(entries.single.failed, true);
    final h2 = harness(entries, (_) => ok);
    await runLedgerDrain(h2.deps);
    expect(h2.log, isEmpty);
  });
}
