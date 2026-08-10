import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/token_resolver.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  // ── <KEY> grammar: TokenResolver.screenTxMarkers ──────────────────────

  group('screenTxMarkers', () {
    test('absent key leaves literal <foo>', () {
      // Use a unique key name to avoid cross-test bleed (screenTx is
      // session-long merged state, never cleared).
      expect(
        TokenResolver.screenTxMarkers('hello <tr_absent_1> world'),
        'hello <tr_absent_1> world',
      );
    });

    test('key present with empty string resolves to empty', () {
      // THE dialect pin: <KEY> treats '' as a valid resolution, unlike {token}
      // which leaves the literal when the value is empty (pending-safe).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'tr_empty_2': '',
      })));
      expect(
        TokenResolver.screenTxMarkers('before<tr_empty_2>after'),
        'beforeafter',
      );
    });

    test('normal key resolves', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'tr_normal_3': 'HELLO',
      })));
      expect(
        TokenResolver.screenTxMarkers('x<tr_normal_3>y'),
        'xHELLOy',
      );
    });

    test('snake_case key resolves (regex accepts underscore)', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'my_snake_key_4': 'SNAKE',
      })));
      expect(
        TokenResolver.screenTxMarkers('<my_snake_key_4>'),
        'SNAKE',
      );
    });

    test('non-string value (int) is stringified', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'tr_int_5': 42,
      })));
      expect(
        TokenResolver.screenTxMarkers('<tr_int_5>'),
        '42',
      );
    });

    test('multiple markers in one string', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'tr_a6': 'AA',
        'tr_b6': 'BB',
      })));
      expect(
        TokenResolver.screenTxMarkers('<tr_a6>-<tr_b6>'),
        'AA-BB',
      );
    });

    test('no markers returns identical string', () {
      const plain = 'no angle brackets here';
      expect(TokenResolver.screenTxMarkers(plain), plain);
    });
  });

  // ── {token} grammar: TokenResolver.curly ──────────────────────────────

  group('curly', () {
    test('reserved token {userVid} resolves from screenTx #VID', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': 'V-999',
      })));
      expect(
        TokenResolver.curly('{userVid}', 'trCurlyScr'),
        'V-999',
      );
    });

    test('empty value leaves token literal (pending-safe)', () {
      // Contrast with <KEY> which resolves '' to ''. This is the opposite
      // dialect: {token} leaves the literal when the resolved value is empty,
      // so filterByMultiClause's value.contains('{') guard detects unresolved
      // state and returns empty (pending-safe / fail-closed).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': '',
      })));
      expect(
        TokenResolver.curly('{userVid}', 'trCurlyScr2'),
        '{userVid}',
      );
    });

    test('unknown token with bare screenTx key present resolves', () {
      // The default case in resolveDriverCurlyTokens resolves unknown tokens
      // from bare screenTx keys (the routeParams fallback).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'myCustomParam7': 'CUSTOM_VAL',
      })));
      expect(
        TokenResolver.curly('{myCustomParam7}', 'trCurlyScr3'),
        'CUSTOM_VAL',
      );
    });

    test('unknown token with nothing in screenTx leaves literal', () {
      expect(
        TokenResolver.curly('{tr_totally_absent_8}', 'trCurlyScr4'),
        '{tr_totally_absent_8}',
      );
    });

    test('no-brace fast path returns identical string', () {
      const plain = 'no braces here';
      expect(TokenResolver.curly(plain, 'trCurlyScr5'), plain);
    });
  });

  // ── Composition-order pin ─────────────────────────────────────────────

  group('composition order', () {
    test('curly then screenTxMarkers resolves both grammars', () {
      // Simulates the canonical order: curly → (replacePlaceholders skipped
      // here, no ref) → screenTxMarkers. A string containing both {token}
      // and <KEY> is resolved in two passes, matching the api.dart saveSend
      // eventString pipeline.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': 'V-123',
        'APPROVAL_STATUS_9': 'approved',
      })));

      const input = '{userVid}◼<APPROVAL_STATUS_9>';
      // Pass 1: curly resolves {userVid} → 'V-123'
      final afterCurly = TokenResolver.curly(input, 'trCompScr');
      expect(afterCurly, 'V-123◼<APPROVAL_STATUS_9>');
      // Pass 2: screenTxMarkers resolves <APPROVAL_STATUS_9> → 'approved'
      final afterMarkers = TokenResolver.screenTxMarkers(afterCurly);
      expect(afterMarkers, 'V-123◼approved');
    });
  });
}
