import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // Seed the Redux store once (mirrors rbt_route_params_test.dart pattern).
  // W2: each test re-dispatches the keys it asserts on so no test depends on
  // leftover state from a prior one.
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

  // ── resolveRowCurlyTokens (pure helper) ──────────────────────────────────

  group('resolveRowCurlyTokens', () {
    test('resolves field from row map', () {
      final result = resolveRowCurlyTokens(
        '{lv}',
        {'lv': 'VID-42', 'ln': 'Truck A'},
      );
      expect(result, 'VID-42');
    });

    test('leaves unknown token literal for session fallback', () {
      final result = resolveRowCurlyTokens(
        '{vehicleId}',
        {'lv': 'VID-42'},
      );
      expect(result, '{vehicleId}');
    });

    test('resolves row field and leaves session token', () {
      final result = resolveRowCurlyTokens(
        '{lv}\u{25FC}{today}',
        {'lv': 'VID-42'},
      );
      expect(result, 'VID-42\u{25FC}{today}');
    });

    test('empty row map returns raw unchanged', () {
      final result = resolveRowCurlyTokens('{lv}', const {});
      expect(result, '{lv}');
    });

    test('null field value leaves token literal', () {
      final result = resolveRowCurlyTokens('{lv}', {'lv': null});
      expect(result, '{lv}');
    });

    test('empty string field value leaves token literal', () {
      final result = resolveRowCurlyTokens('{lv}', {'lv': ''});
      expect(result, '{lv}');
    });

    test('whitespace-only field value leaves token literal', () {
      final result = resolveRowCurlyTokens('{lv}', {'lv': '  '});
      expect(result, '{lv}');
    });

    test('no curly tokens returns raw immediately', () {
      final result = resolveRowCurlyTokens('literal', {'lv': 'VID-42'});
      expect(result, 'literal');
    });

    test('numeric field value stringified', () {
      final result = resolveRowCurlyTokens('{qty}', {'qty': 42});
      expect(result, '42');
    });

    test('double-brace not matched', () {
      final result = resolveRowCurlyTokens(
        '{{POS(0)}}',
        {'POS(0)': 'bad'},
      );
      expect(result, '{{POS(0)}}');
    });
  });

  // ── writeRouteParamsFromRow ──────────────────────────────────────────────

  group('writeRouteParamsFromRow', () {
    test('resolves {lv} from row fields and dispatches bare key', () {
      writeRouteParamsFromRow(
        'vehicleId\u{25FC}{lv}',
        {'lv': 'VID-42', 'ln': 'Truck A'},
        'testScr',
      );
      expect(transactionStore.state.screenTx['vehicleId'], 'VID-42');
    });

    test('falls back to session token when row field missing', () {
      // {tnm} is not in row but IS a reserved token mapping to
      // #ACTIVE_TASK in resolveDriverCurlyTokens.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      writeRouteParamsFromRow(
        'taskId\u{25FC}{tnm}',
        {'lv': 'VID-42'}, // tnm not here
        'testScr',
      );
      expect(transactionStore.state.screenTx['taskId'], 'TASK-ABC-123');
    });

    test('row field wins over session token for same name', () {
      // Row has a field named 'vehicleId' -> row-context resolution runs
      // first and resolves it before resolveDriverCurlyTokens sees it.
      writeRouteParamsFromRow(
        'vid\u{25FC}{vehicleId}',
        {'vehicleId': 'ROW-VID-99'},
        'testScr',
      );
      expect(transactionStore.state.screenTx['vid'], 'ROW-VID-99');
    });

    test('literal value dispatched as-is', () {
      writeRouteParamsFromRow(
        'mode\u{25FC}edit',
        {'lv': 'VID-42'},
        'testScr',
      );
      expect(transactionStore.state.screenTx['mode'], 'edit');
    });

    test('multiple pairs: row + session + literal', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'TASK-ABC-123',
      })));
      writeRouteParamsFromRow(
        'vid\u{25FC}{lv}\u{2B58}task\u{25FC}{tnm}\u{2B58}flag\u{25FC}yes',
        {'lv': 'VID-42'},
        'testScr',
      );
      final tx = transactionStore.state.screenTx;
      expect(tx['vid'], 'VID-42');
      expect(tx['task'], 'TASK-ABC-123');
      expect(tx['flag'], 'yes');
    });

    test('null DSL is no-op', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'noopKey': 'BEFORE',
      })));
      writeRouteParamsFromRow(null, {'lv': 'VID-42'}, 'testScr');
      expect(transactionStore.state.screenTx['noopKey'], 'BEFORE');
    });

    test('empty DSL is no-op', () {
      writeRouteParamsFromRow('', {'lv': 'VID-42'}, 'testScr');
      // no crash, no dispatch
    });

    test('null row is no-op (adhoc row case)', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'adhocKey': 'BEFORE',
      })));
      writeRouteParamsFromRow(
        'adhocKey\u{25FC}{lv}',
        null,
        'testScr',
      );
      expect(transactionStore.state.screenTx['adhocKey'], 'BEFORE');
    });

    test('empty row field not dispatched (pending-safe)', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'shouldBeNull': null,
      })));
      writeRouteParamsFromRow(
        'shouldBeNull\u{25FC}{lv}',
        {'lv': ''},
        'testScr',
      );
      // lv is empty -> resolveRowCurlyTokens leaves {lv} ->
      // resolveDriverCurlyTokens has no bare 'lv' key -> still {lv} ->
      // contains '{' -> skipped.
      expect(transactionStore.state.screenTx['shouldBeNull'], isNull);
    });

    test('unresolved token not dispatched', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'unresolvedKey': null,
      })));
      writeRouteParamsFromRow(
        'unresolvedKey\u{25FC}{noSuchField}',
        {'lv': 'VID-42'},
        'testScr',
      );
      expect(transactionStore.state.screenTx['unresolvedKey'], isNull);
    });

    test('autheniumDecode handles encoded separators', () {
      // Server wire form: U+25FC as _u25FC_ and U+2B58 as _u2B58_ (the no-`u`
      // _2B58_ branch is dead in autheniumDecode, global.dart:1152).
      writeRouteParamsFromRow(
        'vehicleId_u25FC_{lv}_u2B58_mode_u25FC_view',
        {'lv': 'VID-55'},
        'testScr',
      );
      final tx = transactionStore.state.screenTx;
      expect(tx['vehicleId'], 'VID-55');
      expect(tx['mode'], 'view');
    });

    test('malformed DSL segment skipped gracefully', () {
      writeRouteParamsFromRow(
        'badpair\u{2B58}vehicleId\u{25FC}{lv}',
        {'lv': 'VID-42'},
        'testScr',
      );
      // badpair has no U+25FC -> skipped; vehicleId resolved
      expect(transactionStore.state.screenTx['vehicleId'], 'VID-42');
    });

    test('end-to-end: row dispatch + destination resolve', () {
      // Simulates StockHistory flow:
      // 1. Source page taps vehicle row, dispatches vehicleId from {lv}
      writeRouteParamsFromRow(
        'vehicleId\u{25FC}{lv}',
        {'lv': 'VID-42', 'ln': 'Truck A'},
        'stockListScr',
      );
      // 2. Destination page resolves {vehicleId} via the real
      //    filterDriverHomeDocs pipeline: resolveDriverCurlyTokens (step 2)
      //    leaves the RESERVED {vehicleId} literal when no per-screen publisher
      //    set state.vehicleId, then resolveScreenTxTokens (step 3) resolves it
      //    from the dispatched bare screenTx key.
      final String driverResolved = resolveDriverCurlyTokens(
        'vv\u{25FC}{vehicleId}',
        'stockDetailScr',
      );
      final String result = resolveScreenTxTokens(
        driverResolved,
        transactionStore.state.screenTx,
      );
      expect(result, 'vv\u{25FC}VID-42');
    });
  });
}
