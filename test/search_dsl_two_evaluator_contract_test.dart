import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/admin_home_support.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/list_card_support.dart';
import 'package:otonomiq/widget/picker_list.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

/// Pins the two-evaluator contract (spec S3-A):
///
/// - filterByMultiClause / filterByCharCodeEquality: empty value = fail-closed
///   (match nothing).
/// - evaluateGate: empty value = match-empty (doc field must be empty/blank).
///
/// This file tests the CONTRAST between the two paths. Per-function isolation
/// tests live in their own files (search_dsl_empty_token_test.dart,
/// admin_home_support_test.dart, driver_home_support_test.dart,
/// statistic_card_support_test.dart, picker_list_test.dart).
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  // ── Contract contrast: same DSL, two evaluators, opposite behavior ────

  group('two-evaluator contract: empty clause value', () {
    // The SAME clause value (empty after ◼) produces opposite results
    // depending on which evaluator runs it. This is the core contract.
    //
    // Regression signal: if filterByMultiClause were changed to match-empty,
    // the first test would start passing with a non-empty result and the
    // scope-leak prevention would be broken. If evaluateGate were changed to
    // fail-closed on empty value, the second test would start returning false
    // and every noExecutorGate/unassignedGate/invoiceGate in admin runtime
    // would break.

    final docs = <Map<String, dynamic>>[
      {'tst': 'assigned', 'vv': '', 'dv': ''},
      {'tst': 'assigned', 'vv': 'V1', 'dv': 'DRV001'},
    ];

    test('filterByMultiClause: empty value -> EMPTY result (fail-closed)', () {
      // dv◼ with empty value after ◼
      final result = filterByMultiClause(
        docs,
        'tst\u{25FC}assigned\u{2B58}dv\u{25FC}',
      );
      // Regression: if this returned non-empty, a scope leak exists.
      // The "assigned" clause alone would match both docs; the empty dv
      // clause must cause the ENTIRE query to return empty, not be dropped.
      expect(result, isEmpty);
    });

    test('evaluateGate: empty value -> MATCHES doc with empty field', () {
      // Same DSL shape: tst◼assigned⭘dv◼
      final docEmpty = docs[0]; // dv=''
      final docPopulated = docs[1]; // dv='DRV001'

      // Regression: if this returned false, admin unassignedGate would
      // stop showing unassigned vehicles entirely.
      expect(
        evaluateGate(docEmpty, 'tst\u{25FC}assigned\u{2B58}dv\u{25FC}'),
        isTrue,
        reason: 'empty dv clause must match doc whose dv is empty',
      );

      // The REJECTION direction: evaluateGate must also reject docs where
      // the field is populated. A one-sided assertion (only testing the
      // match) would pass even if evaluateGate ignored the empty clause
      // entirely and returned true for everything.
      expect(
        evaluateGate(docPopulated, 'tst\u{25FC}assigned\u{2B58}dv\u{25FC}'),
        isFalse,
        reason: 'empty dv clause must reject doc whose dv is populated',
      );
    });

    test('filterByCharCodeEquality: empty resolved value -> EMPTY (fail-closed)', () {
      // Single-clause form: dv◼ with empty value
      // screenTx is irrelevant here -- the value is already empty after
      // the ◼, no {token} to resolve.
      final result = filterByCharCodeEquality(
        docs,
        'dv\u{25FC}',
        const <String, dynamic>{},
      );
      // Regression: if this returned non-empty, same scope-leak as
      // filterByMultiClause.
      expect(result, isEmpty);
    });
  });

  // ── Token-resolver invariant: empty state leaves {token} literal ──────

  group('resolveDriverCurlyTokens: empty state leaves literal (guard-path ordering)', () {
    // Pins the guard-path ORDERING (defense-in-depth), not a leak boundary.
    // Even if a resolver returned "" instead of "{token}",
    // filterByMultiClause would still fail-closed via isTokenEmpty -- no
    // scope leak either way. But the designed invariant is that resolvers
    // leave the literal `{name}`, so the `value.contains('{')` guard fires
    // first. This test pins that ordering.
    //
    // Regression signal: if resolveDriverCurlyTokens started returning ""
    // for an empty vehicleId instead of "{vehicleId}", the fail-closed
    // guard path would shift from contains('{') to isTokenEmpty. No leak
    // either way, but the ordering change would signal a resolver regression.

    test('{vehicleId} with empty state -> literal {vehicleId}', () {
      clearDriverHomeState('contract_scr');
      // vehicleId is '' (default RxString)
      final result = resolveDriverCurlyTokens(
        'vv\u{25FC}{vehicleId}',
        'contract_scr',
      );
      expect(result, 'vv\u{25FC}{vehicleId}');
      // The resolved string still contains '{', so filterByMultiClause's
      // value.contains('{') guard fires (not isTokenEmpty).
      expect(result.contains('{'), isTrue);
    });

    test('{driverVid} with empty #has_user_login -> literal {driverVid}', () {
      // Register restore BEFORE mutating, so it runs even if an expect fails.
      addTearDown(() {
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
          '#has_user_login': '777',
        })));
      });
      // Temporarily clear #has_user_login
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#has_user_login': '',
      })));
      final result = resolveDriverCurlyTokens(
        'dv\u{25FC}{driverVid}',
        'contract_scr',
      );
      expect(result, 'dv\u{25FC}{driverVid}');
      expect(result.contains('{'), isTrue);
    });

    test('default case (bare screenTx key) with empty value -> literal', () {
      // {someArbitraryKey} not in any switch case -> falls through to
      // default, which reads screenTx[name]. Empty or absent -> literal.
      clearDriverHomeState('contract_scr2');
      final result = resolveDriverCurlyTokens(
        'f\u{25FC}{someArbitraryKey}',
        'contract_scr2',
      );
      expect(result, 'f\u{25FC}{someArbitraryKey}');
    });
  });

  group('resolveScreenTxTokens: empty screenTx value leaves literal', () {
    test('empty string value -> literal {key}', () {
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}',
        <String, dynamic>{'vehicleId': ''},
      );
      expect(result, 'vv\u{25FC}{vehicleId}');
      expect(result.contains('{'), isTrue);
    });

    test('absent key -> literal {key}', () {
      final result = resolveScreenTxTokens(
        'vv\u{25FC}{vehicleId}',
        const <String, dynamic>{},
      );
      expect(result, 'vv\u{25FC}{vehicleId}');
    });
  });

  // ── End-to-end: PickerList.filterRows with real config ────────────────

  group('PickerList.filterRows with real noExecutorGate config', () {
    // Real SDUI config: vehiclePicker search "lt◼vehicle⭘lst◼active⭘dv◼"
    // This routes through evaluateGate (match-empty semantics), NOT
    // filterByMultiClause.
    //
    // Regression signal: if filterRows were changed to use
    // filterByMultiClause instead of evaluateGate, all three assertions
    // below would flip (the unassigned vehicle would be excluded, the
    // assigned one included, and the client excluded for the wrong reason).

    final stockDocs = <Map<String, dynamic>>[
      {'lv': 'V1', 'ln': 'B 1234', 'lt': 'vehicle', 'lst': 'active', 'dv': ''},
      {'lv': 'V2', 'ln': 'B 5678', 'lt': 'vehicle', 'lst': 'active', 'dv': 'DRV001'},
      {'lv': 'V3', 'ln': 'D 9999', 'lt': 'vehicle', 'lst': 'idle', 'dv': ''},
      {'lv': 'C1', 'ln': 'Toko Maju', 'lt': 'client', 'lst': 'active', 'dv': ''},
    ];

    test('returns unassigned active vehicle, excludes assigned and non-vehicle', () {
      final result = PickerList.filterRows(
        stockDocs,
        'lt\u{25FC}vehicle\u{2B58}lst\u{25FC}active\u{2B58}dv\u{25FC}',
      );
      expect(result.length, 1);
      expect(result.first['lv'], 'V1');
    });

    test('assigned vehicle excluded by non-empty dv', () {
      final result = PickerList.filterRows(
        stockDocs,
        'lt\u{25FC}vehicle\u{2B58}lst\u{25FC}active\u{2B58}dv\u{25FC}',
      );
      // V2 has dv='DRV001' -- must be excluded by the dv◼ (empty) clause
      expect(result.any((d) => d['lv'] == 'V2'), isFalse);
    });

    test('idle vehicle excluded by lst clause, not by dv clause', () {
      final result = PickerList.filterRows(
        stockDocs,
        'lt\u{25FC}vehicle\u{2B58}lst\u{25FC}active\u{2B58}dv\u{25FC}',
      );
      // V3 has lst='idle' -- excluded by lst◼active, even though dv is empty
      expect(result.any((d) => d['lv'] == 'V3'), isFalse);
    });
  });

  // ── End-to-end: computeStatsCounts with empty filter ──────────────────

  group('computeStatsCounts with empty-filter stats def', () {
    // Real SDUI config shape: stats "Nota◼" -> StatsDef('Nota', '')
    // The empty filter short-circuits to docs.length BEFORE evaluateGate.
    //
    // Regression signal: if computeStatsCounts removed the d.filter.isEmpty
    // short-circuit and passed '' to evaluateGate, evaluateGate returns
    // false on empty gateDsl -- so the count would drop to 0.

    final docs = <Map<String, dynamic>>[
      {'ast': 'present', 'name': 'Alice'},
      {'ast': 'awaiting', 'name': 'Bob'},
      {'ast': 'present', 'name': 'Carol'},
    ];

    test('empty filter counts ALL docs (short-circuits before evaluateGate)', () {
      final counts = computeStatsCounts(
        [const StatsDef('Nota', '')],
        docs,
      );
      expect(counts, [3]);
    });

    test('non-empty filter counts only matching docs via evaluateGate', () {
      final counts = computeStatsCounts(
        [
          const StatsDef('Nota', ''),
          const StatsDef('Present', 'ast\u{25FC}present'),
        ],
        docs,
      );
      expect(counts, [3, 2]);
    });
  });

  // ── Cross-path: filterByMultiClause vs evaluateGate on same data ──────

  group('same doc set, same DSL, opposite evaluator -> opposite result', () {
    // The acid test: feed the EXACT SAME docs and the EXACT SAME DSL string
    // to both evaluators. They must disagree on the empty-value clause.

    final docs = <Map<String, dynamic>>[
      {'lt': 'vehicle', 'dv': ''},
      {'lt': 'vehicle', 'dv': 'DRV001'},
    ];
    // DSL: lt◼vehicle⭘dv◼ (dv clause has empty value)
    const dsl = 'lt\u{25FC}vehicle\u{2B58}dv\u{25FC}';

    test('filterByMultiClause -> 0 results (fail-closed)', () {
      final result = filterByMultiClause(docs, dsl);
      expect(result, isEmpty);
    });

    test('evaluateGate on doc with empty dv -> true (match-empty)', () {
      expect(evaluateGate(docs[0], dsl), isTrue);
    });

    test('evaluateGate on doc with populated dv -> false (rejects)', () {
      expect(evaluateGate(docs[1], dsl), isFalse);
    });
  });
}
