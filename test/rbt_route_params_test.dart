import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // Seed the Redux store once before all tests (mirrors
  // driver_home_support_test.dart pattern). The global `transactionStore` is
  // null in a bare test, so any token-path test would throw NoSuchMethod.
  //
  // W2 (test store hygiene): there is NO tearDown — the store is shared across
  // groups. Each writeRouteParams/resolver test below re-dispatches the exact
  // bare keys it asserts on at the START of the test, so no test depends on
  // leftover state from a prior one. The setUpAll #ACTIVE_TASK seed is the
  // single source feeding {tnm}/{activeTaskVid}; tests that rely on it
  // re-dispatch it explicitly to stay self-sufficient.
  //
  // I1 (over-seeding trimmed): the exercised paths (parseRouteParams,
  // writeRouteParams, resolveDriverCurlyTokens default branch / {tnm} /
  // {activeTaskVid}) never call getNowMillisecondFromEpoch ({today}) or
  // getTableVid, so the NTP ref-time keys and appCodeController seed are NOT
  // needed and are omitted.
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#has_user_login': 'DRIVER-777',
      '#ACTIVE_TASK': 'TASK-ABC-123',
    })));
  });

  // ── parseRouteParams (pure helper) ────────────────────────────────────────

  group('parseRouteParams', () {
    test('single pair parses correctly', () {
      final result = parseRouteParams('failedTaskVid\u{25FC}{tnm}');
      expect(result.length, 1);
      expect(result[0].key, 'failedTaskVid');
      expect(result[0].value, '{tnm}');
    });

    test('multiple pairs separated by U+2B58', () {
      final result = parseRouteParams(
          'failedTaskVid\u{25FC}{tnm}\u{2B58}customerName\u{25FC}{kn}');
      expect(result.length, 2);
      expect(result[0].key, 'failedTaskVid');
      expect(result[0].value, '{tnm}');
      expect(result[1].key, 'customerName');
      expect(result[1].value, '{kn}');
    });

    test('literal value (no curly braces)', () {
      final result = parseRouteParams('mode\u{25FC}edit');
      expect(result.length, 1);
      expect(result[0].key, 'mode');
      expect(result[0].value, 'edit');
    });

    test('null input returns empty list', () {
      expect(parseRouteParams(null), isEmpty);
    });

    test('empty string returns empty list', () {
      expect(parseRouteParams(''), isEmpty);
    });

    test('whitespace-only string returns empty list', () {
      expect(parseRouteParams('   '), isEmpty);
    });

    test('malformed segment missing separator is skipped', () {
      // "badpair" has no ◼ separator -> skipped; valid pair still parsed
      final result = parseRouteParams('badpair\u{2B58}mode\u{25FC}edit');
      expect(result.length, 1);
      expect(result[0].key, 'mode');
      expect(result[0].value, 'edit');
    });

    test('empty key after separator is skipped', () {
      final result = parseRouteParams('\u{25FC}value');
      expect(result, isEmpty);
    });

    test('empty value after separator is preserved', () {
      // Empty value is valid (the write helper will skip it, but the parser
      // preserves it for the caller to decide).
      final result = parseRouteParams('key\u{25FC}');
      expect(result.length, 1);
      expect(result[0].key, 'key');
      expect(result[0].value, '');
    });

    test('value containing multiple separators preserves them', () {
      // Value: "a◼b" (the ◼ after the first is part of the value)
      final result = parseRouteParams('key\u{25FC}a\u{25FC}b');
      expect(result.length, 1);
      expect(result[0].key, 'key');
      expect(result[0].value, 'a\u{25FC}b');
    });

    test('whitespace around pairs and keys is trimmed', () {
      final result = parseRouteParams(
          ' key1\u{25FC}val1 \u{2B58} key2\u{25FC}val2 ');
      expect(result.length, 2);
      expect(result[0].key, 'key1');
      expect(result[0].value, 'val1');
      expect(result[1].key, 'key2');
      expect(result[1].value, 'val2');
    });
  });

  // ── writeRouteParams (integration with transactionStore) ──────────────────

  group('writeRouteParams', () {
    test('resolves {tnm} and dispatches bare key', () {
      // W2: self-seed #ACTIVE_TASK (source of {tnm}) at the start of the test.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      // {tnm} is an alias for #ACTIVE_TASK in resolveDriverCurlyTokens.
      writeRouteParams('failedTaskVid\u{25FC}{tnm}', 'testScr');
      final screenTx = transactionStore.state.screenTx;
      expect(screenTx['failedTaskVid'], 'TASK-ABC-123');
    });

    test('literal value dispatched as-is', () {
      writeRouteParams('mode\u{25FC}edit', 'testScr');
      final screenTx = transactionStore.state.screenTx;
      expect(screenTx['mode'], 'edit');
    });

    test('null input is no-op', () {
      // W2: self-seed the key we assert on.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'noopTestKey': 'BEFORE',
      })));
      writeRouteParams(null, 'testScr');
      // The key should still be 'BEFORE' (not cleared)
      expect(transactionStore.state.screenTx['noopTestKey'], 'BEFORE');
    });

    test('empty input is no-op', () {
      writeRouteParams('', 'testScr');
      // No crash, no dispatch
    });

    test('unresolved token is NOT dispatched (pending-safe)', () {
      // W2: self-seed the key to null so we can assert it stays null.
      // {unknownToken} has no matching case and no bare key -> left literal.
      // The literal still contains '{' -> writeRouteParams skips it.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'shouldNotExist': null,
      })));
      writeRouteParams('shouldNotExist\u{25FC}{unknownToken}', 'testScr');
      // shouldNotExist should NOT have been set to a value
      expect(transactionStore.state.screenTx['shouldNotExist'], isNull);
    });

    test('multiple pairs dispatched in one action', () {
      // W2: self-seed #ACTIVE_TASK (source of {tnm}).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      writeRouteParams(
          'keyA\u{25FC}{tnm}\u{2B58}keyB\u{25FC}literal', 'testScr');
      final screenTx = transactionStore.state.screenTx;
      expect(screenTx['keyA'], 'TASK-ABC-123');
      expect(screenTx['keyB'], 'literal');
    });

    test('overwrites previous value on re-declare', () {
      writeRouteParams('overKey\u{25FC}first', 'testScr');
      expect(transactionStore.state.screenTx['overKey'], 'first');
      writeRouteParams('overKey\u{25FC}second', 'testScr');
      expect(transactionStore.state.screenTx['overKey'], 'second');
    });
  });

  // ── resolveDriverCurlyTokens default-branch change ────────────────────────

  group('resolveDriverCurlyTokens default branch (bare screenTx lookup)', () {
    test('unknown token with matching bare key resolves', () {
      // W2: self-seed the bare key under test.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'failedTaskVid': 'TSK-999',
      })));
      final result = resolveDriverCurlyTokens(
        'tnm\u{25FC}{failedTaskVid}',
        'resolverScr',
      );
      expect(result, 'tnm\u{25FC}TSK-999');
    });

    test('unknown token with no bare key stays literal', () {
      final result = resolveDriverCurlyTokens(
        'f\u{25FC}{noSuchBareKey}',
        'resolverScr',
      );
      expect(result, 'f\u{25FC}{noSuchBareKey}');
    });

    test('unknown token with empty bare key stays literal', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'emptyBareKey': '',
      })));
      final result = resolveDriverCurlyTokens(
        'f\u{25FC}{emptyBareKey}',
        'resolverScr',
      );
      expect(result, 'f\u{25FC}{emptyBareKey}');
    });

    test('reserved token wins over bare key of same name', () {
      // Even if someone dispatches a bare key named 'tnm', the hardcoded
      // switch case for 'tnm' (-> #ACTIVE_TASK) takes precedence.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'tnm': 'SHOULD-NOT-WIN',
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      final result = resolveDriverCurlyTokens(
        'x\u{25FC}{tnm}',
        'resolverScr',
      );
      // Should resolve to #ACTIVE_TASK value, NOT the bare 'tnm' key
      expect(result, 'x\u{25FC}TASK-ABC-123');
    });

    test('double-brace {{POS(0)}} is NOT matched by single-brace regex', () {
      final result = resolveDriverCurlyTokens(
        'val\u{25FC}{{POS(0)}}',
        'resolverScr',
      );
      // {{POS(0)}} must pass through unchanged
      expect(result, 'val\u{25FC}{{POS(0)}}');
    });

    test('double-brace {{DOC(5)}} is NOT matched by single-brace regex', () {
      final result = resolveDriverCurlyTokens(
        'val\u{25FC}{{DOC(5)}}',
        'resolverScr',
      );
      expect(result, 'val\u{25FC}{{DOC(5)}}');
    });

    test('existing callers unaffected when no bare key matches', () {
      // W2: self-seed #ACTIVE_TASK (source of {activeTaskVid}).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      // Simulate the workspace_header search pattern:
      // search:"tnm◼{activeTaskVid}" -- {activeTaskVid} is a hardcoded case,
      // not the default branch. Result should resolve from #ACTIVE_TASK.
      final result = resolveDriverCurlyTokens(
        'tnm\u{25FC}{activeTaskVid}',
        'resolverScr',
      );
      expect(result, 'tnm\u{25FC}TASK-ABC-123');
    });

    test('end-to-end: writeRouteParams + resolveDriverCurlyTokens', () {
      // W2: self-seed #ACTIVE_TASK (source of {tnm}).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      // Simulate the full P11 -> FailedDelivery flow:
      // 1. P11 button taps, dispatching failedTaskVid from {tnm}
      writeRouteParams('failedTaskVid\u{25FC}{tnm}', 'p11Scr');
      // 2. Destination page's workspace_header resolves {failedTaskVid}
      final result = resolveDriverCurlyTokens(
        'tnm\u{25FC}{failedTaskVid}',
        'failedDeliveryScr',
      );
      expect(result, 'tnm\u{25FC}TASK-ABC-123');
    });
  });
}
