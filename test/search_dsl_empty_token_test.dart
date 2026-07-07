import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/dsl_eq.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#has_user_login': '777',
      '#REF_TIME_START': DateTime.now().millisecondsSinceEpoch,
      '#DEVICE_TIME_START': DateTime.now().millisecondsSinceEpoch,
    })));
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  // ── isTokenEmpty ─────────────────────────────────────────────────────────

  group('isTokenEmpty', () {
    test('null is empty', () {
      expect(isTokenEmpty(null), isTrue);
    });

    test('empty string is empty', () {
      expect(isTokenEmpty(''), isTrue);
    });

    test('whitespace-only is empty', () {
      expect(isTokenEmpty('   '), isTrue);
      expect(isTokenEmpty('\t'), isTrue);
      expect(isTokenEmpty('\n'), isTrue);
    });

    test('non-empty string is NOT empty', () {
      expect(isTokenEmpty('F621a02a983500'), isFalse);
      expect(isTokenEmpty('123'), isFalse);
      expect(isTokenEmpty('a'), isFalse);
    });

    test('{literal} token is NOT empty (contains chars)', () {
      expect(isTokenEmpty('{vehicleId}'), isFalse);
    });
  });

  // ── resolveScreenTxTokens empty-value guard ──────────────────────────────

  group('resolveScreenTxTokens empty-value guard', () {
    test('null screenTx value leaves {key} literal', () {
      final screenTx = <String, dynamic>{'other': 'val'};
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}\u{2B58}tdt\u{25FC}{today}',
        screenTx,
      );
      expect(result.contains('{vehicleId}'), isTrue);
    });

    test('empty string screenTx value leaves {key} literal (fail-closed)', () {
      // THIS IS THE CRUX: "" must NOT resolve the token
      final screenTx = <String, dynamic>{'vehicleId': ''};
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}',
        screenTx,
      );
      expect(result, 'vv\u{25FC}{vehicleId}');
      expect(result.contains('{vehicleId}'), isTrue);
    });

    test('whitespace-only screenTx value leaves {key} literal', () {
      final screenTx = <String, dynamic>{'vehicleId': '   '};
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}',
        screenTx,
      );
      expect(result, 'vv\u{25FC}{vehicleId}');
    });

    test('non-empty screenTx value resolves normally', () {
      final screenTx = <String, dynamic>{'vehicleId': 'F621a02a983500'};
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}',
        screenTx,
      );
      expect(result, 'vv\u{25FC}F621a02a983500');
    });

    test('multiple tokens: empty one stays literal, non-empty resolves', () {
      final screenTx = <String, dynamic>{
        'vehicleId': '',
        'today': '1751475600000',
      };
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}\u{2B58}tdt\u{25FC}{today}',
        screenTx,
      );
      expect(result.contains('{vehicleId}'), isTrue);
      expect(result.contains('1751475600000'), isTrue);
    });
  });

  // ── filterByMultiClause fail-closed on empty token ───────────────────────

  group('filterByMultiClause empty-token fail-closed', () {
    final docs = <Map<String, dynamic>>[
      {'vv': 'F621a02a983500', 'tdt': '1751475600000', 'tst': 'assigned'},
      {'vv': 'OTHER', 'tdt': '1751475600000', 'tst': 'assigned'},
    ];

    test('empty string value -> zero matches (fail-closed)', () {
      // vv◼<empty>⭘tdt◼1751475600000 -- empty vv must NOT drop the clause
      final result = filterByMultiClause(
        docs,
        'vv\u{25FC}\u{2B58}tdt\u{25FC}1751475600000',
      );
      expect(result, isEmpty);
    });

    test('unresolved {token} -> zero matches (fail-closed)', () {
      final result = filterByMultiClause(
        docs,
        'vv\u{25FC}{vehicleId}\u{2B58}tdt\u{25FC}1751475600000',
      );
      expect(result, isEmpty);
    });

    test('non-empty value -> normal filter', () {
      final result = filterByMultiClause(
        docs,
        'vv\u{25FC}F621a02a983500\u{2B58}tdt\u{25FC}1751475600000',
      );
      expect(result.length, 1);
      expect(result.first['vv'], 'F621a02a983500');
    });

    test('multi-clause where one clause empty -> zero (not partial filter)', () {
      // The critical case: if the empty clause were DROPPED, we would get 2
      // results (both docs match tdt). Instead we must get 0.
      final result = filterByMultiClause(
        docs,
        'vv\u{25FC}\u{2B58}tdt\u{25FC}1751475600000',
      );
      expect(result, isEmpty,
          reason: 'empty vv clause must fail-closed, not be dropped');
    });

    test('single clause with empty value -> zero matches', () {
      // lv◼<empty> from INVENTORY_BUCKET_CARD
      final inventoryDocs = <Map<String, dynamic>>[
        {'lv': 'F621a02a983500', 'cd': 'full', 'qt': 10},
      ];
      final result = filterByMultiClause(inventoryDocs, 'lv\u{25FC}');
      expect(result, isEmpty);
    });

    test('whitespace-only value -> zero matches', () {
      final result = filterByMultiClause(
        docs,
        'vv\u{25FC}   \u{2B58}tdt\u{25FC}1751475600000',
      );
      expect(result, isEmpty);
    });
  });

  // ── End-to-end: filterDriverHomeDocs with empty vehicleId ────────────────

  group('filterDriverHomeDocs end-to-end empty vehicleId', () {
    final docs = <Map<String, dynamic>>[
      {'vv': 'F621a02a983500', 'tdt': todayEpochMidnightWib()},
      {'vv': 'OTHER', 'tdt': todayEpochMidnightWib()},
    ];

    test('empty vehicleId -> zero matches (not all-today leak)', () {
      clearDriverHomeState('leak_scr');
      // vehicleId is '' (default) -- simulates unassigned driver
      final result = filterDriverHomeDocs(
        docs,
        'vv_25FC_{vehicleId}_u2B58_tdt_25FC_{today}',
        'leak_scr',
      );
      expect(result, isEmpty,
          reason: 'unassigned driver must not see any stops');
    });

    test('assigned vehicleId -> normal filter', () {
      clearDriverHomeState('leak_scr2');
      getDriverHomeState('leak_scr2').vehicleId.value = 'F621a02a983500';
      final result = filterDriverHomeDocs(
        docs,
        'vv_25FC_{vehicleId}_u2B58_tdt_25FC_{today}',
        'leak_scr2',
      );
      expect(result.length, 1);
      expect(result.first['vv'], 'F621a02a983500');
    });

    test('single-clause lv◼{vehicleId} empty -> zero matches', () {
      clearDriverHomeState('leak_scr3');
      final inventoryDocs = <Map<String, dynamic>>[
        {'lv': 'F621a02a983500', 'cd': 'full', 'qt': 10},
      ];
      final result = filterDriverHomeDocs(
        inventoryDocs,
        'lv_25FC_{vehicleId}',
        'leak_scr3',
      );
      expect(result, isEmpty);
    });
  });
}
