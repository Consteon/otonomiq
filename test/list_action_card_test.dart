import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/list_action_card.dart';
import 'package:otonomiq/global.dart'; // transactionStore
import 'package:otonomiq/redux/screen_transaction.dart'; // ScreenTransaction, UpdateScreenTxAction
import 'package:otonomiq/redux/screen_transaction_reducers.dart'; // transactionReducer, initTransactionStore
import 'package:redux_dev_tools/redux_dev_tools.dart'; // DevToolsStore

void main() {
  // Seed the Redux store so any resolveActionTokensOrAbort ABORT test whose
  // token is absent from the row doc can reach resolveDriverCurlyTokens, which
  // reads transactionStore.state (null in a bare test -> NoSuchMethodError).
  // Unknown tokens like {ck}/{a}/{b} are still not session tokens, so the probe
  // returns them literal and the ABORT assertions hold. Pattern:
  // rbt_route_params_test:25. The session-token group below re-seeds via its
  // own setUp/tearDown.
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#VID': 'V123',
      '#NAME': 'Test User',
    })));
  });

  // ── parseActionMeta ──────────────────────────────────────────────────────

  group('parseActionMeta', () {
    test('parses 2-action happy path with posisiNote', () {
      final metas = parseActionMeta(
          'ok\u{25FC}reward-approve'
          '\u{25C6}danger\u{25FC}reward-reject\u{25FC}5');
      expect(metas.length, 2);
      expect(metas[0].tone, 'ok');
      expect(metas[0].flag, 'reward-approve');
      expect(metas[0].notePosition, isNull);
      expect(metas[1].tone, 'danger');
      expect(metas[1].flag, 'reward-reject');
      expect(metas[1].notePosition, 5);
    });

    test('single action without posisiNote', () {
      final metas = parseActionMeta('warn\u{25FC}some-flag');
      expect(metas.length, 1);
      expect(metas[0].tone, 'warn');
      expect(metas[0].flag, 'some-flag');
      expect(metas[0].notePosition, isNull);
    });

    test('empty string returns empty list', () {
      expect(parseActionMeta(''), isEmpty);
      expect(parseActionMeta('  '), isEmpty);
    });

    test('unknown tone normalizes to neutral', () {
      final metas = parseActionMeta('banana\u{25FC}flag');
      expect(metas.length, 1);
      expect(metas[0].tone, 'neutral');
    });

    test('missing flag yields empty string', () {
      final metas = parseActionMeta('ok');
      expect(metas.length, 1);
      expect(metas[0].tone, 'ok');
      expect(metas[0].flag, '');
      expect(metas[0].notePosition, isNull);
    });

    test('trailing diamond does not produce extra entry', () {
      final metas = parseActionMeta('ok\u{25FC}f1\u{25C6}');
      expect(metas.length, 1);
    });

    test('posisiNote non-numeric is ignored (null)', () {
      final metas = parseActionMeta('ok\u{25FC}flag\u{25FC}abc');
      expect(metas.length, 1);
      expect(metas[0].notePosition, isNull);
    });
  });

  // ── parseListActionFields ─────────────────────────────────────────────────

  group('parseListActionFields', () {
    test('parses 6-segment happy path', () {
      final f = parseListActionFields(
          '<cn>\u{25C6}<pl>\u{25C6}i\u{25C6}<ts>\u{25C6}fl\u{25C6}'
          'sample\u{25FC}Sampel\u{25FC}neutral');
      expect(f.titleTpl, '<cn>');
      expect(f.subtitleTpl, '<pl>');
      expect(f.imageField, 'i');
      expect(f.metaTpl, '<ts>');
      expect(f.badgeField, 'fl');
      expect(f.rawBadgeMap, 'sample\u{25FC}Sampel\u{25FC}neutral');
    });

    test('short fields array fills defaults', () {
      final f = parseListActionFields('<cn>\u{25C6}<pl>');
      expect(f.titleTpl, '<cn>');
      expect(f.subtitleTpl, '<pl>');
      expect(f.imageField, '');
      expect(f.metaTpl, '');
      expect(f.badgeField, '');
      expect(f.rawBadgeMap, '');
    });

    test('empty string returns all-empty fields', () {
      final f = parseListActionFields('');
      // diamondTextToList('') returns [''], so seg[0] = ''
      expect(f.titleTpl, '');
      expect(f.subtitleTpl, '');
      expect(f.imageField, '');
    });
  });

  // ── resolveActionTokensOrAbort ────────────────────────────────────────────

  group('resolveActionTokensOrAbort (row-doc tokens)', () {
    const String testScreen = 'testScreen';

    test('resolves all tokens from row doc', () {
      const dsl = 'table//coll\u{2B58}search\u{25FC}ck\u{2605}{ck}\u{2B58}st\u{25FC}approved';
      final doc = <String, dynamic>{'ck': 'abc-123'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, isNotNull);
      expect(result!.contains('{'), isFalse);
      expect(result.contains('abc-123'), isTrue);
    });

    test('returns null when token field is absent in doc and unknown to session resolver', () {
      const dsl = 'table//coll\u{2B58}search\u{25FC}ck\u{2605}{ck}';
      final doc = <String, dynamic>{'cn': 'Dedi'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      // 'ck' is not a known session token, so it ABORTs.
      expect(result, isNull);
    });

    test('returns null when token field is empty string in doc and unknown to session', () {
      const dsl = 'table//coll\u{2B58}search\u{25FC}ck\u{2605}{ck}';
      final doc = <String, dynamic>{'ck': ''};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, isNull);
    });

    test('DSL without tokens passes through unchanged', () {
      const dsl = 'table//coll\u{2B58}st\u{25FC}approved';
      final doc = <String, dynamic>{'ck': 'abc'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, dsl);
    });

    test('multiple tokens all resolved', () {
      const dsl = '{a}-{b}';
      final doc = <String, dynamic>{'a': 'X', 'b': 'Y'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, 'X-Y');
    });

    test('one resolved one absent returns null (ABORT)', () {
      const dsl = '{a}-{b}';
      final doc = <String, dynamic>{'a': 'X'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      // 'b' is not a known session token -> ABORT
      expect(result, isNull);
    });

    test('numeric value resolved as string', () {
      const dsl = 'v={n}';
      final doc = <String, dynamic>{'n': 42};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, 'v=42');
    });

    test('row doc value takes precedence over session token', () {
      // If the row doc has a field named 'userVid', it resolves from doc,
      // never hitting the session resolver.
      const dsl = 'cv\u{25FC}{userVid}';
      final doc = <String, dynamic>{'userVid': 'DOC_VALUE'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, 'cv\u{25FC}DOC_VALUE');
    });
  });

  group('resolveActionTokensOrAbort (session-token pass-through)', () {
    // Seed the Redux store so resolveDriverCurlyTokens can resolve {userVid}.
    // Pattern: test/rbt_route_params_test.dart:25-34.
    const String testScreen = 'testScreen';

    setUp(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': 'V123',
        '#NAME': 'Test User',
      })));
    });

    tearDown(() {
      // Reset store so seeded values do not leak to sibling groups.
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    test('known session token is left literal for saveSend to resolve', () {
      // {userVid} maps to #VID in resolveDriverCurlyTokens. With #VID seeded
      // to 'V123', the probe returns 'V123' (differs from '{userVid}'), so the
      // token is recognised and left literal -- NOT resolved to 'V123' here.
      const dsl = 'cv\u{25FC}{userVid}';
      final doc = <String, dynamic>{};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, 'cv\u{25FC}{userVid}'); // literal, NOT 'cv◼V123'
    });

    test('session token with empty backing value still ABORTs', () {
      // Seed #VID to empty -> resolveDriverCurlyTokens returns '{userVid}'
      // unchanged -> probe matches -> ABORT.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': '',
      })));
      const dsl = 'cv\u{25FC}{userVid}';
      final doc = <String, dynamic>{};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, isNull);
    });

    test('mixed row-doc and session tokens both resolve correctly', () {
      // {ck} from doc, {userVid} left literal (session token).
      const dsl = 'search\u{25FC}ck\u{2605}{ck}\u{2B58}cv\u{25FC}{userVid}';
      final doc = <String, dynamic>{'ck': 'abc-123'};
      final result = resolveActionTokensOrAbort(dsl, doc, testScreen);
      expect(result, isNotNull);
      // {ck} resolved, {userVid} left literal.
      expect(result!.contains('abc-123'), isTrue);
      expect(result.contains('{userVid}'), isTrue);
      expect(result.contains('V123'), isFalse);
    });
  });

  // ── parseSortConfig ───────────────────────────────────────────────────────

  group('parseSortConfig', () {
    test('parses field and asc direction', () {
      final s = parseSortConfig('t\u{25FC}asc');
      expect(s.field, 't');
      expect(s.descending, isFalse);
    });

    test('parses desc direction', () {
      final s = parseSortConfig('amount\u{25FC}desc');
      expect(s.field, 'amount');
      expect(s.descending, isTrue);
    });

    test('no separator yields field only, default asc', () {
      final s = parseSortConfig('t');
      expect(s.field, 't');
      expect(s.descending, isFalse);
    });

    test('empty string yields empty field', () {
      final s = parseSortConfig('');
      expect(s.field, '');
      expect(s.descending, isFalse);
    });
  });

  // ── collectButtonWrites ────────────────────────────────────────────────────

  group('collectButtonWrites', () {
    test('collects 4 ops per button from component map', () {
      final component = <String, dynamic>{
        'updateEventRow1': 'uer1_val',
        'addToEvent1': 'ate1_val',
        'addToTable1': '',
        'updateTableRow1': '',
        'updateEventRow2': 'uer2_val',
        'addToEvent2': 'ate2_val',
        'addToTable2': 'att2_val',
        'updateTableRow2': 'utr2_val',
      };
      String decode(String key) => (component[key] ?? '').toString().trim();
      final result = collectButtonWrites(decode);

      expect(result.length, 2);
      // Button 1
      expect(result[0][0], 'uer1_val'); // updateEventRow
      expect(result[0][1], 'ate1_val'); // addToEvent
      expect(result[0][2], '');         // addToTable
      expect(result[0][3], '');         // updateTableRow
      // Button 2
      expect(result[1][0], 'uer2_val');
      expect(result[1][1], 'ate2_val');
      expect(result[1][2], 'att2_val');
      expect(result[1][3], 'utr2_val');
    });

    test('missing keys yield empty strings', () {
      final component = <String, dynamic>{};
      String decode(String key) => (component[key] ?? '').toString().trim();
      final result = collectButtonWrites(decode);

      expect(result.length, 2);
      expect(result[0].every((s) => s.isEmpty), isTrue);
      expect(result[1].every((s) => s.isEmpty), isTrue);
    });

    test('only button 2 populated', () {
      final component = <String, dynamic>{
        'updateEventRow2': 'reject_dsl',
      };
      String decode(String key) => (component[key] ?? '').toString().trim();
      final result = collectButtonWrites(decode);

      expect(result[0].every((s) => s.isEmpty), isTrue);
      expect(result[1][0], 'reject_dsl');
      expect(result[1][1], '');
      expect(result[1][2], '');
      expect(result[1][3], '');
    });

    test('whitespace-only value collapses to empty string', () {
      final component = <String, dynamic>{
        'updateEventRow1': '   ',
        'addToEvent1': ' \t ',
      };
      // Simulate _cfg (autheniumDecode returns the string as-is for plain
      // whitespace, no escapes to decode). collectButtonWrites owns the trim.
      String decode(String key) => (component[key] ?? '').toString();
      final result = collectButtonWrites(decode);

      expect(result[0][0], '');
      expect(result[0][1], '');
      expect(buttonHasWrites(result, 0), isFalse);
    });
  });

  // ── buttonHasWrites ────────────────────────────────────────────────────────

  group('buttonHasWrites', () {
    test('returns true when at least one op is non-empty', () {
      final writes = [
        ['', 'ate1', '', ''],
        ['', '', '', ''],
      ];
      expect(buttonHasWrites(writes, 0), isTrue);
      expect(buttonHasWrites(writes, 1), isFalse);
    });

    test('returns false for out-of-range index', () {
      final writes = [
        ['uer1', '', '', ''],
      ];
      expect(buttonHasWrites(writes, 2), isFalse);
      expect(buttonHasWrites(writes, -1), isFalse);
    });

    test('returns false when all ops empty', () {
      final writes = [
        ['', '', '', ''],
        ['', '', '', ''],
      ];
      expect(buttonHasWrites(writes, 0), isFalse);
    });

    test('all 4 ops populated', () {
      final writes = [
        ['a', 'b', 'c', 'd'],
      ];
      expect(buttonHasWrites(writes, 0), isTrue);
    });
  });

  // ── writeOpKeys ────────────────────────────────────────────────────────────

  group('writeOpKeys', () {
    test('has exactly 4 entries in canonical order', () {
      expect(writeOpKeys.length, 4);
      expect(writeOpKeys[0], 'updateEventRow');
      expect(writeOpKeys[1], 'addToEvent');
      expect(writeOpKeys[2], 'addToTable');
      expect(writeOpKeys[3], 'updateTableRow');
    });
  });

  // ── buildSaveSendComponent ─────────────────────────────────────────────────

  group('buildSaveSendComponent', () {
    test('sets bare op keys from resolved writes and strips numbered keys', () {
      final component = <String, dynamic>{
        'type': 'LIST_ACTION_CARD',
        'updateEventRow1': 'uer1_raw',
        'addToEvent1': 'ate1_raw',
        'updateEventRow2': 'uer2_raw',
        'addToEvent2': 'ate2_raw',
        'route': 'someDetailRoute',
        'delay': '5',
        'vidtable': '20342033315492',
      };
      final resolvedWrites = ['uer1_resolved', 'ate1_resolved', '', ''];
      final result = buildSaveSendComponent(component, resolvedWrites, 'my-flag');

      // Bare keys set from resolved writes.
      expect(result['updateEventRow'], 'uer1_resolved');
      expect(result['addToEvent'], 'ate1_resolved');
      // Empty resolved writes are NOT set as keys.
      expect(result.containsKey('addToTable'), isFalse);
      expect(result.containsKey('updateTableRow'), isFalse);
      // All 8 numbered keys removed.
      expect(result.containsKey('updateEventRow1'), isFalse);
      expect(result.containsKey('addToEvent1'), isFalse);
      expect(result.containsKey('updateEventRow2'), isFalse);
      expect(result.containsKey('addToEvent2'), isFalse);
      expect(result.containsKey('addToTable1'), isFalse);
      expect(result.containsKey('addToTable2'), isFalse);
      expect(result.containsKey('updateTableRow1'), isFalse);
      expect(result.containsKey('updateTableRow2'), isFalse);
      // flag set.
      expect(result['flag'], 'my-flag');
      // C1: route and delay stripped.
      expect(result.containsKey('route'), isFalse);
      expect(result.containsKey('delay'), isFalse);
      // Non-action keys preserved.
      expect(result['type'], 'LIST_ACTION_CARD');
      expect(result['vidtable'], '20342033315492');
    });

    test('does not leak other button ops when only one button fires', () {
      final component = <String, dynamic>{
        'updateEventRow1': 'uer1_raw',
        'updateEventRow2': 'uer2_raw',
        'addToEvent2': 'ate2_raw',
      };
      // Button 1 fires: only updateEventRow resolved.
      final resolvedWrites = ['uer1_resolved', '', '', ''];
      final result = buildSaveSendComponent(component, resolvedWrites, 'f1');

      expect(result['updateEventRow'], 'uer1_resolved');
      // Button 2's ops must NOT be present.
      expect(result.containsKey('updateEventRow2'), isFalse);
      expect(result.containsKey('addToEvent2'), isFalse);
      expect(result.containsKey('addToEvent'), isFalse);
    });

    test('route and delay absent in source does not crash', () {
      final component = <String, dynamic>{'type': 'LIST_ACTION_CARD'};
      final resolvedWrites = ['uer', '', '', ''];
      final result = buildSaveSendComponent(component, resolvedWrites, 'f');
      // No crash; route/delay simply not present.
      expect(result.containsKey('route'), isFalse);
      expect(result.containsKey('delay'), isFalse);
    });
  });
}
