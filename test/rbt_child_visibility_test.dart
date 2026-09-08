import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/approver_sticky_bar.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/item_card_detail.dart';
import 'package:otonomiq/widget/rbt_visibility.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#has_user_login': '777',
      '#VID': '87544551624342',
      'nm': 'ASG-001',
    })));
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  const Map<String, dynamic> waitingDoc = {
    'nm': 'ASG-001',
    'st': 'waiting',
    'ty': 'assign-extra-work'
  };
  const Map<String, dynamic> acceptedDoc = {
    'nm': 'ASG-001',
    'st': 'accepted',
    'ty': 'assign-extra-work'
  };

  group('rbtChildVisible — empty search always visible', () {
    test('empty, no doc, no row', () {
      expect(rbtChildVisible('', 'scr', row: const [], contextDoc: null),
          isTrue);
    });
    test('whitespace, no doc', () {
      expect(rbtChildVisible('   ', 'scr', row: const [], contextDoc: null),
          isTrue);
    });
    test('empty, doc present but mismatching', () {
      expect(
          rbtChildVisible('', 'scr', row: const [], contextDoc: acceptedDoc),
          isTrue);
    });
  });

  group('rbtChildVisible — keyed (live shapes)', () {
    test('st◼waiting + waiting doc -> visible', () {
      expect(
          rbtChildVisible('st\u{25FC}waiting', 'scr',
              row: const [], contextDoc: waitingDoc),
          isTrue);
    });
    test('st◼waiting + accepted doc -> hidden', () {
      expect(
          rbtChildVisible('st\u{25FC}waiting', 'scr',
              row: const [], contextDoc: acceptedDoc),
          isFalse);
    });
    test('st◼pending + no context doc -> hidden (fail-closed)', () {
      expect(
          rbtChildVisible('st\u{25FC}pending', 'scr',
              row: const [], contextDoc: null),
          isFalse);
    });
    test('positional row present does NOT rescue a keyed miss', () {
      expect(
          rbtChildVisible('st\u{25FC}waiting', 'scr',
              row: const ['a', 'b', 'waiting'], contextDoc: acceptedDoc),
          isFalse);
    });
    test('server-escaped _25FC_ decodes', () {
      expect(
          rbtChildVisible('st_25FC_waiting', 'scr',
              row: const [], contextDoc: waitingDoc),
          isTrue);
    });
    test('keyed is CASE-SENSITIVE (eq string fallback)', () {
      expect(
          rbtChildVisible('st\u{25FC}WAITING', 'scr',
              row: const [], contextDoc: waitingDoc),
          isFalse);
    });
    test('keyed eq() is type-tolerant (num doc vs string clause)', () {
      // 3.0 (not 3): filterByMultiClause stringifies the doc side, so a doc
      // value of 3 would pass on eq()'s plain string fallback and never reach
      // the numeric branch. "3.0" != "3" as strings, so this fixture can only
      // pass numerically.
      expect(
          rbtChildVisible('lv\u{25FC}3', 'scr',
              row: const [], contextDoc: const {'lv': 3.0}),
          isTrue);
    });
    test('unresolved {token} -> fail-closed', () {
      expect(
          rbtChildVisible('st\u{25FC}{noSuchKey}', 'scr',
              row: const [], contextDoc: waitingDoc),
          isFalse);
    });
  });

  group('rbtChildVisible — multi-clause AND', () {
    test('both clauses match -> visible', () {
      expect(
          rbtChildVisible(
              'st\u{25FC}waiting\u{2B58}ty\u{25FC}assign-extra-work', 'scr',
              row: const [], contextDoc: waitingDoc),
          isTrue);
    });
    test('one clause fails -> hidden', () {
      expect(
          rbtChildVisible(
              'st\u{25FC}waiting\u{2B58}ty\u{25FC}other', 'scr',
              row: const [], contextDoc: waitingDoc),
          isFalse);
    });
    test('server-escaped _u2B58_ AND separator decodes', () {
      expect(
          rbtChildVisible(
              'st_25FC_waiting_u2B58_ty_25FC_assign-extra-work', 'scr',
              row: const [], contextDoc: waitingDoc),
          isTrue);
    });
  });

  group('rbtChildVisible — positional (45 live sticky children)', () {
    const List<dynamic> row = ['id1', 'x', 'MENUNGGU', 'more'];
    test('2◼MENUNGGU matches row[2]', () {
      expect(
          rbtChildVisible('2\u{25FC}MENUNGGU', 'scr',
              row: row, contextDoc: null),
          isTrue);
    });
    test('2◼SELESAI does not match row[2]', () {
      expect(
          rbtChildVisible('2\u{25FC}SELESAI', 'scr',
              row: row, contextDoc: null),
          isFalse);
    });
    test('positional is CASE-INSENSITIVE (legacy uppercase both sides)', () {
      expect(
          rbtChildVisible('2\u{25FC}menunggu', 'scr',
              row: row, contextDoc: null),
          isTrue);
    });
    test('empty row -> hidden (idx >= row.length)', () {
      expect(
          rbtChildVisible('2\u{25FC}MENUNGGU', 'scr',
              row: const [], contextDoc: null),
          isFalse);
    });
    test('out-of-range index -> hidden, no RangeError', () {
      expect(
          rbtChildVisible('9\u{25FC}MENUNGGU', 'scr',
              row: row, contextDoc: null),
          isFalse);
    });
    test('positional does NOT consult the context doc', () {
      expect(
          rbtChildVisible('2\u{25FC}MENUNGGU', 'scr',
              row: row, contextDoc: acceptedDoc),
          isTrue);
    });
    test('eq() type tolerance on positional', () {
      // 5.0 (not 5): evaluateRbtSearch stringifies row[idx] too, so a plain 5
      // would pass on the string fallback. "5.0" vs "5" forces the numeric
      // branch.
      expect(
          rbtChildVisible('1\u{25FC}5', 'scr',
              row: const ['a', 5.0], contextDoc: null),
          isTrue);
    });
    test('multi positional AND', () {
      expect(
          rbtChildVisible('0\u{25FC}id1\u{2B58}2\u{25FC}MENUNGGU', 'scr',
              row: row, contextDoc: null),
          isTrue);
    });
  });

  group('rbtChildVisible — mixed positional + keyed = AND', () {
    const List<dynamic> row = ['id1', 'x', 'MENUNGGU'];
    test('both sides match -> visible', () {
      expect(
          rbtChildVisible('2\u{25FC}MENUNGGU\u{2B58}st\u{25FC}waiting', 'scr',
              row: row, contextDoc: waitingDoc),
          isTrue);
    });
    test('positional fails -> hidden without consulting doc', () {
      expect(
          rbtChildVisible('2\u{25FC}SELESAI\u{2B58}st\u{25FC}waiting', 'scr',
              row: row, contextDoc: waitingDoc),
          isFalse);
    });
    test('keyed fails -> hidden', () {
      expect(
          rbtChildVisible('2\u{25FC}MENUNGGU\u{2B58}st\u{25FC}waiting', 'scr',
              row: row, contextDoc: acceptedDoc),
          isFalse);
    });
  });

  group('rbtChildVisible — malformed clauses', () {
    test('no ◼ at all -> visible (evaluateRbtSearch parity)', () {
      expect(rbtChildVisible('sticky', 'scr', row: const [], contextDoc: null),
          isTrue);
      expect(evaluateRbtSearch('sticky', const []), isTrue);
    });
    test('empty clause key -> hidden (guard; filterByMultiClause SKIPS it)',
        () {
      // Without the explicit empty-key guard this is VISIBLE: filterByMultiClause
      // does `if (field.isEmpty) continue`, ends with pairs.isEmpty and returns
      // `docs` unchanged -> non-empty -> visible. evaluateRbtSearch fails closed
      // on the same string, so the guard preserves today's sticky behaviour.
      expect(evaluateRbtSearch('\u{25FC}waiting', const ['a', 'b']), isFalse);
      expect(
          rbtChildVisible('\u{25FC}waiting', 'scr',
              row: const [], contextDoc: waitingDoc),
          isFalse);
      // The raw evaluator this branch delegates to is fail-OPEN here — proof
      // the guard is load-bearing, not decorative.
      expect(
          filterDriverHomeDocs(
              <Map<String, dynamic>>[waitingDoc], '\u{25FC}waiting', 'scr'),
          isNotEmpty);
    });
    test('clause value empty -> hidden (filterByMultiClause fail-closed)', () {
      expect(
          rbtChildVisible('st\u{25FC}', 'scr',
              row: const [], contextDoc: waitingDoc),
          isFalse);
    });
  });

  group('resolveRbtDocSource', () {
    setUp(() {
      screenUIComponent = <String, dynamic>{};
    });

    test('first DETAIL_CARD in page order wins', () {
      screenUIComponent['scrA'] = {
        'children': [
          {'type': 'WORKSPACE_HEADER'},
          {
            'type': 'DETAIL_CARD',
            'vidtable': '20342033315492',
            'table': '84214220504259//assignment',
            'search': 'nm\u{25FC}{nm}',
          },
          {
            'type': 'DETAIL_CARD',
            'vidtable': '999',
            'table': '888//other',
            'search': 'x\u{25FC}1',
          },
        ]
      };
      final src = resolveRbtDocSource('scrA');
      expect(src.code, '20342033315492/84214220504259/assignment');
      expect(src.rawSearch, 'nm\u{25FC}{nm}');
    });

    test('lowercase type key also matches', () {
      screenUIComponent['scrB'] = {
        'children': [
          {
            'type': 'detail_card',
            'vidtable': '1',
            'table': '2//t',
            'search': ''
          }
        ]
      };
      expect(resolveRbtDocSource('scrB').code, '1/2/t');
    });

    test('table without // defaults subColl to content', () {
      screenUIComponent['scrC'] = {
        'children': [
          {'type': 'DETAIL_CARD', 'vidtable': '1', 'table': '2'}
        ]
      };
      expect(resolveRbtDocSource('scrC').code, '1/2/content');
    });

    test('DETAIL_CARD with empty table is skipped, next one wins', () {
      screenUIComponent['scrD'] = {
        'children': [
          {'type': 'DETAIL_CARD', 'vidtable': '1', 'table': ''},
          {'type': 'DETAIL_CARD', 'vidtable': '9', 'table': '8//s'},
        ]
      };
      expect(resolveRbtDocSource('scrD').code, '9/8/s');
    });

    test('page with no DETAIL_CARD -> empty source', () {
      screenUIComponent['scrE'] = {
        'children': [
          {'type': 'ITEM_CARD_DETAIL'},
          {'type': 'RBT'}
        ]
      };
      expect(resolveRbtDocSource('scrE').code, '');
      expect(resolveRbtDocSource('scrE').isEmpty, isTrue);
    });

    test('unknown screen -> empty source', () {
      expect(resolveRbtDocSource('nope').code, '');
    });

    test('null screenUIComponent -> empty source, no throw', () {
      screenUIComponent = null;
      expect(resolveRbtDocSource('scrA').code, '');
    });
  });

  group('anyRbtChildConditional', () {
    test('no search anywhere -> false', () {
      expect(
          anyRbtChildConditional([
            {'text': 'Ok'},
            {'text': 'Batal', 'search': '  '}
          ]),
          isFalse);
    });
    test('one search -> true', () {
      expect(
          anyRbtChildConditional([
            {'text': 'Ok'},
            {'text': 'Sanggupi', 'search': 'st\u{25FC}waiting'}
          ]),
          isTrue);
    });
    test('empty children -> false', () {
      expect(anyRbtChildConditional(const []), isFalse);
    });
  });

  group('visibleRbtChildren end-to-end', () {
    const String code = '20342033315492/84214220504259/assignment';

    setUp(() {
      screenUIComponent = <String, dynamic>{
        'assignDetail': {
          'children': [
            {
              'type': 'DETAIL_CARD',
              'vidtable': '20342033315492',
              'table': '84214220504259//assignment',
              'search': 'nm\u{25FC}{nm}',
            },
          ]
        },
        'noCardScreen': {
          'children': [
            {'type': 'TIMELINE_CARD'}
          ]
        },
      };
      mapTableContent.remove(code);
      ItemCardDetail.currentRow.value = const [];
    });

    final List<dynamic> children = [
      {'text': '✓ Sanggupi', 'search': 'st\u{25FC}waiting'},
      {'text': 'Kembali'},
    ];

    test('doc waiting -> both children visible', () {
      mapTableContent[code] = [
        {'nm': 'ASG-001', 'st': 'waiting'},
        {'nm': 'ASG-002', 'st': 'waiting'},
      ];
      final v = visibleRbtChildren(children, 'assignDetail');
      expect(v.length, 2);
      expect(v.first['text'], '✓ Sanggupi');
    });

    test('doc accepted -> only the unconditional child survives', () {
      mapTableContent[code] = [
        {'nm': 'ASG-001', 'st': 'accepted'},
      ];
      final v = visibleRbtChildren(children, 'assignDetail');
      expect(v.length, 1);
      expect(v.first['text'], 'Kembali');
    });

    test('snapshot not arrived -> conditional hidden, plain child kept', () {
      final v = visibleRbtChildren(children, 'assignDetail');
      expect(v.length, 1);
      expect(v.first['text'], 'Kembali');
    });

    test('DETAIL_CARD search matches no doc -> conditional hidden', () {
      mapTableContent[code] = [
        {'nm': 'OTHER', 'st': 'waiting'},
      ];
      final v = visibleRbtChildren(children, 'assignDetail');
      expect(v.length, 1);
    });

    test('DETAIL_CARD with an empty search -> the FIRST doc is the context doc',
        () {
      // Mirrors DetailCard._findDoc: a blank card search makes
      // filterDriverHomeDocs return the collection unchanged, so `.first`
      // decides. Doc 0 is accepted and doc 1 is waiting -- "any matching doc"
      // would keep the button; "the doc the card is showing" hides it.
      screenUIComponent['blankSearchScreen'] = {
        'children': [
          {
            'type': 'DETAIL_CARD',
            'vidtable': '111',
            'table': '222//t',
            'search': '',
          },
        ]
      };
      mapTableContent['111/222/t'] = [
        {'nm': 'ASG-001', 'st': 'accepted'},
        {'nm': 'ASG-002', 'st': 'waiting'},
      ];
      final v = visibleRbtChildren(children, 'blankSearchScreen');
      expect(v.length, 1);
      expect(v.first['text'], 'Kembali');

      // Same screen, docs swapped: doc 0 is now waiting -> visible. Without
      // this half the test would also pass if resolveRbtDocSource had failed
      // and returned no source at all (fail-closed hides for the wrong
      // reason). Proves the code resolved AND that doc 0 decided it.
      mapTableContent['111/222/t'] = [
        {'nm': 'ASG-002', 'st': 'waiting'},
        {'nm': 'ASG-001', 'st': 'accepted'},
      ];
      expect(visibleRbtChildren(children, 'blankSearchScreen').length, 2);
    });

    test('page with no DETAIL_CARD -> conditional hidden', () {
      mapTableContent[code] = [
        {'nm': 'ASG-001', 'st': 'waiting'},
      ];
      final v = visibleRbtChildren(children, 'noCardScreen');
      expect(v.length, 1);
      expect(v.first['text'], 'Kembali');
    });

    test('every child hidden -> empty list', () {
      mapTableContent[code] = [
        {'nm': 'ASG-001', 'st': 'accepted'},
      ];
      final v = visibleRbtChildren([
        {'text': 'A', 'search': 'st\u{25FC}waiting'},
        {'text': 'B', 'search': 'st\u{25FC}pending'},
      ], 'assignDetail');
      expect(v, isEmpty);
    });

    test('positional child uses ItemCardDetail.currentRow, not the doc', () {
      ItemCardDetail.currentRow.value = ['id', 'x', 'MENUNGGU'];
      final v = visibleRbtChildren([
        {'text': 'P', 'search': '2\u{25FC}MENUNGGU'},
      ], 'noCardScreen');
      expect(v.length, 1);
    });

    test('returns a List<dynamic> (assignable to component children)', () {
      final v = visibleRbtChildren(children, 'assignDetail');
      expect(v, isA<List<dynamic>>());
    });

    test('outer sticky vs inline is irrelevant — same children, same result',
        () {
      mapTableContent[code] = [
        {'nm': 'ASG-001', 'st': 'accepted'},
      ];
      final inlineComponent = {'search': '', 'children': children};
      final stickyComponent = {'search': 'sticky', 'children': children};
      final a = visibleRbtChildren(
          inlineComponent['children'] as List<dynamic>, 'assignDetail');
      final b = visibleRbtChildren(
          stickyComponent['children'] as List<dynamic>, 'assignDetail');
      expect(a.length, b.length);
      expect(a.length, 1);
    });
  });
}
