// test/whatsapp_invoice_phase2_test.dart
//
// whatsapp-invoice-phase2 -- spec (3) sections 6b-2.0b / 6b-2.1 / 6b-2.2 no.3.
//
// ITEM 1  TaskCreateSubmit.dispatchRouteParams   (routeParams on the submit)
// ITEM 2  resolveSearchWithRow + phoneLookupConfigured + sheet phone prefill
// ITEM 3  seedPriceFor / keepsPrice / toItMap sub / computeItTotal / tot
//
// The ITEM 2 pump group runs with ZERO Firebase: `vidtable` short-circuits
// resolveAppVid before the `late` appCodeController is read, and
// subscribeToMapCollection swallows the null-firestoreDb NoSuchMethodError in
// its own try/catch (table_repository.dart:2183) while _msgSubCode /
// _phoneSubCode are assigned BEFORE that call. Seeding mapTableContent[code]
// therefore drives the REAL read path: search -> resolveSearchWithRow ->
// filterByCharCodeEquality -> _resolvePhone -> sheet prefill.
// The `subscribeToMapCollection ... failed` lines on stdout are the harness
// working. Same pattern as test/checklist_dynamic_widget_test.dart.
//
// What a green run still does NOT prove: the live Firestore listener, the sheet
// cells the operator has to edit, or the wa.me launch itself. Those stay device
// / sheet work (see the plan's Verification section).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/task_create_submit.dart';
import 'package:otonomiq/widget/task_item_builder.dart';
import 'package:otonomiq/widget/whatsapp_send.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // globalInit() does not run under flutter_test: register by hand what the
    // widgets touch (mirrors checklist_dynamic_widget_test.dart).
    if (!Get.isRegistered<WidgetUpdateController>()) {
      Get.put(WidgetUpdateController());
    }
    if (!Get.isRegistered<GeneralGetXController>()) {
      Get.put(GeneralGetXController());
    }
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  group('ITEM 1 -- TaskCreateSubmit.dispatchRouteParams', () {
    setUp(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    String? tx(String k) => transactionStore.state.screenTx[k]?.toString();

    test('taskVid◼{tnm} resolves from the assembled task doc', () {
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{
          'routeParams': 'taskVid\u{25FC}{tnm}',
        },
        row: <String, dynamic>{'tnm': 'TASK-2026-000555', 'kl': 'C1'},
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'TASK-2026-000555');
    });

    test('server-escaped _25FC_ is decoded before parsing', () {
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{'routeParams': 'taskVid_25FC_{tnm}'},
        row: <String, dynamic>{'tnm': 'TASK-9'},
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'TASK-9');
    });

    test('two pairs both land', () {
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{
          'routeParams': 'taskVid\u{25FC}{tnm}\u{2B58}custId\u{25FC}{kl}',
        },
        row: <String, dynamic>{'tnm': 'T1', 'kl': 'C7'},
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'T1');
      expect(tx('custId'), 'C7');
    });

    test('absent routeParams dispatches NOTHING (byte-identical to today)', () {
      transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'taskVid': 'PREV'})));
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{},
        row: <String, dynamic>{'tnm': 'T2'},
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'PREV');
    });

    test('empty routeParams dispatches NOTHING', () {
      transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'taskVid': 'PREV'})));
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{'routeParams': '   '},
        row: <String, dynamic>{'tnm': 'T2'},
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'PREV');
    });

    test('STALE GUARD: a declared key the row cannot fill is BLANKED, '
        'not left at the previous task value', () {
      transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'notaNo': 'INV-OLD'})));
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{
          'routeParams': 'taskVid\u{25FC}{tnm}\u{2B58}notaNo\u{25FC}{nno}',
        },
        row: <String, dynamic>{'tnm': 'TASK-NEW'}, // no nno on a task doc
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'TASK-NEW');
      expect(tx('notaNo'), '');
    });

    test('STALE GUARD survives the server-escaped dialect '
        '(_u25FC_ / _u2B58_)', () {
      transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'notaNo': 'INV-OLD'})));
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{
          'routeParams': 'taskVid_u25FC_{tnm}_u2B58_notaNo_u25FC_{nno}',
        },
        row: <String, dynamic>{'tnm': 'TASK-NEW'},
        scrName: 'scr',
      );
      expect(tx('taskVid'), 'TASK-NEW');
      expect(tx('notaNo'), '');
    });

    test('malformed pair (no ◼) dispatches nothing for that pair', () {
      TaskCreateSubmit.dispatchRouteParams(
        component: <String, dynamic>{'routeParams': 'garbage'},
        row: <String, dynamic>{'tnm': 'T3'},
        scrName: 'scr',
      );
      expect(tx('garbage'), isNull);
    });
  });

  // ── ITEM 2 ──────────────────────────────────────────────────────────

  const String scr = 'OrderConfirm';
  const String vid = '20342033315492';
  const String taskCode = '$vid/84214220504259/task';
  const String slCode = '$vid/84214220504259/stock_location';

  setUp(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    mapTableContent.clear();
  });

  group('ITEM 2 -- resolveSearchWithRow', () {
    test('row field resolves first', () {
      expect(
        resolveSearchWithRow('lv\u{25FC}{kl}',
            <String, dynamic>{'kl': 'CUST-9'}, scr, const {}),
        'lv\u{25FC}CUST-9',
      );
    });

    test('row field WINS over a stale bare screenTx key of the same name', () {
      expect(
        resolveSearchWithRow('lv\u{25FC}{kl}',
            <String, dynamic>{'kl': 'CUST-NEW'}, scr,
            <String, dynamic>{'kl': 'CUST-STALE'}),
        'lv\u{25FC}CUST-NEW',
      );
    });

    test('row missing the field falls through to screenTx (route token)', () {
      expect(
        resolveSearchWithRow('lv\u{25FC}{customerId}',
            <String, dynamic>{'kl': 'CUST-9'}, scr,
            <String, dynamic>{'customerId': 'CUST-ROUTE'}),
        'lv\u{25FC}CUST-ROUTE',
      );
    });

    test('server-escaped _25FC_ is decoded BEFORE resolution', () {
      expect(
        resolveSearchWithRow('lv_25FC_{kl}',
            <String, dynamic>{'kl': 'CUST-9'}, scr, const {}),
        'lv\u{25FC}CUST-9',
      );
    });

    test('null row = today message chain (screenTx only)', () {
      expect(
        resolveSearchWithRow('tnm\u{25FC}{taskVid}', null, scr,
            <String, dynamic>{'taskVid': 'TASK-1'}),
        'tnm\u{25FC}TASK-1',
      );
    });

    test('empty row map behaves like null row', () {
      expect(
        resolveSearchWithRow('tnm\u{25FC}{taskVid}',
            const <String, dynamic>{}, scr,
            <String, dynamic>{'taskVid': 'TASK-1'}),
        'tnm\u{25FC}TASK-1',
      );
    });

    test('unresolvable token stays LITERAL (fail-closed downstream)', () {
      expect(
        resolveSearchWithRow('lv\u{25FC}{kl}', <String, dynamic>{'x': 'y'},
            scr, const {}),
        'lv\u{25FC}{kl}',
      );
    });

    test('CEILING: empty row field falls back to the stale bare key', () {
      // resolveRowCurlyTokens leaves a token literal when the row value is
      // empty, so step 3 can still fill it from screenTx. Pinned, not fixed.
      expect(
        resolveSearchWithRow('lv\u{25FC}{kl}', <String, dynamic>{'kl': ''},
            scr, <String, dynamic>{'kl': 'CUST-STALE'}),
        'lv\u{25FC}CUST-STALE',
      );
    });

    test('no token = unchanged', () {
      expect(
        resolveSearchWithRow('src\u{25FC}delivery', <String, dynamic>{'kl': 'C'},
            scr, const {}),
        'src\u{25FC}delivery',
      );
    });
  });

  group('ITEM 2 -- phoneLookupConfigured', () {
    test('both set -> true', () {
      expect(
        WhatsAppSend.phoneLookupConfigured(<String, dynamic>{
          'phoneTable': 'X//stock_location',
          'phoneSearch': 'lv\u{25FC}{kl}',
        }),
        isTrue,
      );
    });
    test('table only -> false', () {
      expect(
        WhatsAppSend.phoneLookupConfigured(
            <String, dynamic>{'phoneTable': 'X//stock_location'}),
        isFalse,
      );
    });
    test('search only -> false', () {
      expect(
        WhatsAppSend.phoneLookupConfigured(
            <String, dynamic>{'phoneSearch': 'lv\u{25FC}{kl}'}),
        isFalse,
      );
    });
    test('neither -> false (today configs, nol regresi)', () {
      expect(WhatsAppSend.phoneLookupConfigured(<String, dynamic>{}), isFalse);
    });
    test('whitespace-only -> false', () {
      expect(
        WhatsAppSend.phoneLookupConfigured(
            <String, dynamic>{'phoneTable': '  ', 'phoneSearch': '  '}),
        isFalse,
      );
    });
  });

  group('ITEM 2 -- sheet phone prefill', () {
    Map<String, dynamic> comp({
      String? phoneTable,
      String? phoneSearch,
      String phoneField = 'hpic',
      String phoneFallback = '',
    }) =>
        <String, dynamic>{
          'type': 'WHATSAPP_SEND',
          'vidtable': vid,
          'phoneField': phoneField,
          'phoneFallback': phoneFallback,
          'allowContactPick': 'TRUE',
          'countryCode': '62',
          'messageTable': '84214220504259//task',
          'messageSearch': 'tnm\u{25FC}{taskVid}',
          'messageTemplate': 'Halo {{kn}}',
          if (phoneTable != null) 'phoneTable': phoneTable,
          if (phoneSearch != null) 'phoneSearch': phoneSearch,
          'text': 'Kirim WA',
        };

    Widget sut(Map<String, dynamic> c) => MaterialApp(
          home: Scaffold(
            body: WhatsAppSend(
              component: c,
              scrName: scr,
              lPad: 0,
              tPad: 0,
              rPad: 0,
              bPad: 0,
            ),
          ),
        );

    void seed() {
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'taskVid': 'TASK-2026-000555'})));
      mapTableContent[taskCode] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tnm': 'TASK-2026-000555',
          'kn': 'Toko Maju',
          'kl': 'CUST-9',
        },
      ];
      mapTableContent[slCode] = <Map<String, dynamic>>[
        <String, dynamic>{'lv': 'CUST-9', 'ln': 'Toko Maju', 'hpic': '0812111'},
        <String, dynamic>{'lv': 'CUST-7', 'ln': 'Lain', 'hpic': '0899999'},
      ];
    }

    // The sheet has exactly TWO TextFields: the phone one
    // (keyboardType: TextInputType.phone) and the message one (maxLines: null,
    // no keyboardType). Addressing by keyboardType is unambiguous; index-based
    // finders would not be.
    String phoneText(WidgetTester t) {
      final TextField f = t.widget<TextField>(find.byWidgetPredicate(
          (w) => w is TextField && w.keyboardType == TextInputType.phone));
      return f.controller?.text ?? '';
    }

    testWidgets('phoneTable+phoneSearch reads hpic from the CUSTOMER doc',
        (WidgetTester t) async {
      seed();
      await t.pumpWidget(sut(comp(
        phoneTable: '84214220504259//stock_location',
        phoneSearch: 'lv\u{25FC}{kl}',
      )));
      await t.pump();
      await t.tap(find.byType(ElevatedButton));
      await t.pumpAndSettle();
      expect(phoneText(t), '0812111');
    });

    testWidgets('no phoneTable -> reads phoneField from the MAIN doc (today)',
        (WidgetTester t) async {
      seed();
      mapTableContent[taskCode] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tnm': 'TASK-2026-000555',
          'kn': 'Toko Maju',
          'kl': 'CUST-9',
          'hpic': '0800MAIN',
        },
      ];
      await t.pumpWidget(sut(comp()));
      await t.pump();
      await t.tap(find.byType(ElevatedButton));
      await t.pumpAndSettle();
      expect(phoneText(t), '0800MAIN');
    });

    testWidgets('phoneTable set but phoneSearch empty -> rule 2 (main doc)',
        (WidgetTester t) async {
      seed();
      mapTableContent[taskCode] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tnm': 'TASK-2026-000555',
          'kl': 'CUST-9',
          'hpic': '0800MAIN',
        },
      ];
      await t.pumpWidget(sut(comp(
        phoneTable: '84214220504259//stock_location',
        phoneSearch: '',
      )));
      await t.pump();
      await t.tap(find.byType(ElevatedButton));
      await t.pumpAndSettle();
      expect(phoneText(t), '0800MAIN');
    });

    testWidgets('phone lookup miss -> degrades to main doc, then fallback',
        (WidgetTester t) async {
      seed();
      mapTableContent[taskCode] = <Map<String, dynamic>>[
        <String, dynamic>{'tnm': 'TASK-2026-000555', 'kl': 'CUST-NOBODY'},
      ];
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'custPhone': '0855FALL'})));
      await t.pumpWidget(sut(comp(
        phoneTable: '84214220504259//stock_location',
        phoneSearch: 'lv\u{25FC}{kl}',
        phoneFallback: '{custPhone}',
      )));
      await t.pump();
      await t.tap(find.byType(ElevatedButton));
      await t.pumpAndSettle();
      expect(phoneText(t), '0855FALL');
    });

    testWidgets('main doc missing -> phone lookup SKIPPED (no stale number)',
        (WidgetTester t) async {
      seed();
      mapTableContent[taskCode] = <Map<String, dynamic>>[];
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'kl': 'CUST-7'})));
      await t.pumpWidget(sut(comp(
        phoneTable: '84214220504259//stock_location',
        phoneSearch: 'lv\u{25FC}{kl}',
      )));
      await t.pump();
      await t.tap(find.byType(ElevatedButton));
      await t.pumpAndSettle();
      expect(phoneText(t), '');
    });
  });

  // ── ITEM 3 ──────────────────────────────────────────────────────────

  group('ITEM 3 -- toItMap price + sub', () {
    test('deliver line carries hg and sub = pd * hg', () {
      final m = DraftItem(
              ii: 'ITM-1', itemName: 'Galon 19L', tx: 'deliver', pd: 3, pp: 2, hg: 20000)
          .toItMap();
      expect(m['hg'], 20000);
      expect(m['sub'], 60000);
      expect(m['pd'], 3);
    });

    test('sale line subtotals on ps, not pd', () {
      final m = DraftItem(
              ii: 'ITM-2', itemName: 'Air Mineral', tx: 'sale', ps: 4, pd: 9, hg: 5000)
          .toItMap();
      expect(m['hg'], 5000);
      expect(m['sub'], 20000);
    });

    test('purchase line has NO hg and NO sub', () {
      final m = DraftItem(ii: 'ITM-3', itemName: 'Galon Kosong', tx: 'purchase', pb: 5, hg: 7000)
          .toItMap();
      expect(m.containsKey('hg'), isFalse);
      expect(m.containsKey('sub'), isFalse);
    });

    test('refill line has NO hg and NO sub', () {
      final m = DraftItem(ii: 'ITM-4', itemName: 'Refill', tx: 'refill', pr: 2, hg: 6000)
          .toItMap();
      expect(m.containsKey('hg'), isFalse);
      expect(m.containsKey('sub'), isFalse);
    });

    test('deliver with hg 0 -> sub 0 (key still present)', () {
      final m = DraftItem(ii: 'ITM-5', itemName: 'X', tx: 'deliver', pd: 3).toItMap();
      expect(m['hg'], 0);
      expect(m['sub'], 0);
    });

    test('deliver with pd 0 -> sub 0', () {
      final m = DraftItem(ii: 'ITM-6', itemName: 'X', tx: 'deliver', pd: 0, pp: 4, hg: 20000).toItMap();
      expect(m['sub'], 0);
    });

    test('sub is int (Firestore Number canon)', () {
      final m = DraftItem(ii: 'i', itemName: 'n', tx: 'deliver', pd: 3, hg: 20000).toItMap();
      expect(m['sub'], isA<int>());
      expect(m['hg'], isA<int>());
    });
  });

  group('ITEM 3 -- computeItTotal', () {
    test('sums sub across mixed lines', () {
      final arr = AdminCreateTaskSupport.draftToItArray([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 3, hg: 20000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 5000),
        DraftItem(ii: 'c', itemName: 'C', tx: 'purchase', pb: 9, hg: 999),
      ]);
      expect(AdminCreateTaskSupport.computeItTotal(arr), 70000);
    });

    test('empty array -> 0', () {
      expect(AdminCreateTaskSupport.computeItTotal(const []), 0);
    });

    test('line with no sub key contributes 0', () {
      expect(
        AdminCreateTaskSupport.computeItTotal(
            <Map<String, dynamic>>[<String, dynamic>{'ii': 'x'}]),
        0,
      );
    });

    test('string sub from firestore read-back is coerced', () {
      expect(
        AdminCreateTaskSupport.computeItTotal(
            <Map<String, dynamic>>[<String, dynamic>{'sub': '1500'}]),
        1500,
      );
    });

    test('double sub from firestore read-back truncates to int', () {
      expect(
        AdminCreateTaskSupport.computeItTotal(
            <Map<String, dynamic>>[<String, dynamic>{'sub': 1500.0}]),
        1500,
      );
    });
  });

  group('ITEM 3 -- assembleTaskDoc tot', () {
    Map<String, dynamic> doc(List<DraftItem> items) =>
        AdminCreateTaskSupport.assembleTaskDoc(
          tnm: 'TASK-1',
          kl: 'C1',
          kn: 'Toko',
          al: 'Jl',
          vv: 'V1',
          gl: 'WH',
          cv: '1',
          cn: 'Admin',
          tdt: 1,
          t: 2,
          itArray: AdminCreateTaskSupport.draftToItArray(items),
          tableVid: 'TV',
        );

    test('tot equals sum of it[].sub', () {
      final d = doc([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 3, hg: 20000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 5000),
      ]);
      expect(d['tot'], 70000);
      final List<Map<String, dynamic>> it =
          (d['it'] as List).cast<Map<String, dynamic>>();
      int s = 0;
      for (final l in it) {
        s += (l['sub'] ?? 0) as int;
      }
      expect(d['tot'], s);
    });

    test('tot ALWAYS present, 0 for a pickup-only task', () {
      final d = doc([
        DraftItem(ii: 'a', itemName: 'A', tx: 'purchase', pb: 5),
      ]);
      expect(d.containsKey('tot'), isTrue);
      expect(d['tot'], 0);
    });

    test('tot is int', () {
      final d = doc([DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 1, hg: 7)]);
      expect(d['tot'], isA<int>());
    });
  });

  group('ITEM 3 -- seedPriceFor', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'ii': 'G19',
      'in': 'Galon 19L',
      'harga': 20000, // order-mode price field (_itemPriceField default)
      'hrg': 18000, // walkin/supplier price field (_priceSourceField default)
    };

    int seed(String mode, String addTx, [Map<String, dynamic>? doc]) =>
        TaskItemBuilder.seedPriceFor(
          mode: mode,
          addTx: addTx,
          itemDoc: doc ?? item,
          itemPriceField: 'harga',
          priceSourceField: 'hrg',
        );

    test('order + deliver -> priceSourceField wins over itemPriceField', () {
      // Changed by whatsapp-invoice-phase3 (spec (4) section 6b-2.2 no.3a).
      // The shared fixture carries BOTH fields; order mode now reads `hrg`
      // first and only falls back to `harga` when `hrg` yields 0.
      expect(seed('order', 'deliver'), 18000);
    });
    test('order + sale -> priceSourceField wins (same arm as deliver)', () {
      // Changed by whatsapp-invoice-phase3: order+sale routes through the same
      // order arm as order+deliver, so it was broken by the same root cause.
      expect(seed('order', 'sale'), 18000);
    });
    test('order + purchase -> 0', () {
      expect(seed('order', 'purchase'), 0);
    });
    test('order + refill -> 0', () {
      expect(seed('order', 'refill'), 0);
    });
    test('walkin + sale -> priceSourceField (unchanged)', () {
      expect(seed('walkin', 'sale'), 18000);
    });
    test('walkin + deliver -> 0 (mode guard: walkin never gets order price)',
        () {
      expect(seed('walkin', 'deliver'), 0);
    });
    test('supplier + buy -> priceSourceField (unchanged)', () {
      expect(seed('supplier', 'buy'), 18000);
    });
    test('supplier + deliver -> priceSourceField, supplier wins first', () {
      expect(seed('supplier', 'deliver'), 18000);
    });
    test('seed mode + deliver -> 0', () {
      expect(seed('seed', 'deliver'), 0);
    });
    test('missing price field -> 0 (coerceNum on null)', () {
      expect(seed('order', 'deliver', <String, dynamic>{'ii': 'X'}), 0);
    });
    test('string price from a sheet is coerced', () {
      expect(seed('order', 'deliver', <String, dynamic>{'harga': '20000'}),
          20000);
    });
    test('double price truncates to int', () {
      expect(seed('order', 'deliver', <String, dynamic>{'harga': 20000.9}),
          20000);
    });
  });

  group('ITEM 3 -- keepsPrice', () {
    test('order + deliver -> true (THE NEW BEHAVIOR)', () {
      expect(TaskItemBuilder.keepsPrice(mode: 'order', tx: 'deliver'), isTrue);
    });
    test('order + sale -> true', () {
      expect(TaskItemBuilder.keepsPrice(mode: 'order', tx: 'sale'), isTrue);
    });
    test('walkin + sale -> true', () {
      expect(TaskItemBuilder.keepsPrice(mode: 'walkin', tx: 'sale'), isTrue);
    });
    test('walkin + deliver -> false (mode guard)', () {
      expect(TaskItemBuilder.keepsPrice(mode: 'walkin', tx: 'deliver'), isFalse);
    });
    test('order + purchase -> false', () {
      expect(
          TaskItemBuilder.keepsPrice(mode: 'order', tx: 'purchase'), isFalse);
    });
    test('order + refill -> false', () {
      expect(TaskItemBuilder.keepsPrice(mode: 'order', tx: 'refill'), isFalse);
    });
  });

  // ── ITEM 4 (GATE-1 addition C) ──────────────────────────────────────
  //
  // <IFSET source='x'>…</IFSET> hides a block when the field is UNSET.
  // Born from the pickup-only task: purchase/refill lines carry no `sub`, so
  // `tot` is 0 and `*Perkiraan total: Rp 0*` would go to a real customer. One
  // template serves every task on OrderConfirm, so the operator cannot fix it
  // by dropping the cell -- that would strip the total from PRICED tasks too.
  //
  // The `-----` separator lives INSIDE the block deliberately: dropping the
  // total must drop its rule as well, or the message ends on a dangling line.

  group('ITEM 4 -- IFSET', () {
    // The exact cell the operator pastes (plan section 6.6, sheet-edit 3).
    // Raw string: the `\n` are the LITERAL two characters the sheet stores;
    // pass 1 of the renderer turns them into newlines.
    const String totalBlock =
        r"<IFSET source='tot'>--------------------\n*Perkiraan total: {{tot|idr}}*\n</IFSET>";

    test('tot set -> body kept, {{tot|idr}} rendered', () {
      expect(
        renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': 150000}),
        '--------------------\n*Perkiraan total: 150.000*\n',
      );
    });

    test('tot 0 (int) -> WHOLE block gone, separator included', () {
      expect(renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': 0}),
          '');
    });

    test("tot '0' (String -- the shape a sheet cell produces) -> block gone",
        () {
      expect(renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': '0'}),
          '');
    });

    test('tot 0.0 (double read back from Firestore) -> block gone', () {
      expect(renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': 0.0}),
          '');
    });

    test('tot absent -> block gone', () {
      expect(renderWhatsAppTemplate(totalBlock, <String, dynamic>{}), '');
    });

    test("tot '' -> block gone", () {
      expect(renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': ''}),
          '');
    });

    test(
        'non-numeric non-empty value stays SET -- the LUNAS regression '
        'coerceNum would have caused', () {
      // coerceNum('LUNAS') == 0, so a coerceNum-based "is set" test would
      // silently delete this line. num.tryParse returns null instead, which is
      // why the parse has to come BEFORE the zero test.
      expect(
        renderWhatsAppTemplate(
            r"<IFSET source='st'>Status: {{st}}</IFSET>",
            <String, dynamic>{'st': 'LUNAS'}),
        'Status: LUNAS',
      );
    });

    test('IFSET with no source= -> block gone (fail-closed on a typo)', () {
      expect(
        renderWhatsAppTemplate(
            '<IFSET>always?</IFSET>', <String, dynamic>{'tot': 5}),
        '',
      );
    });

    test('LOOP and IFSET in one template: both render, in the right order',
        () {
      expect(
        renderWhatsAppTemplate(
          r"Order:\n<LOOP source='li'>- {{item.in}} x{{item.pd}} @ {{item.hg|idr}}\n</LOOP><IFSET source='tot'>-----\n*Total: {{tot|idr}}*</IFSET>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'Galon', 'pd': 2, 'hg': 20000},
              <String, dynamic>{'in': 'Air', 'pd': 1, 'hg': 5000},
            ],
            'tot': 45000,
          },
        ),
        'Order:\n- Galon x2 @ 20.000\n- Air x1 @ 5.000\n-----\n*Total: 45.000*',
      );
    });

    test('tot 0 drops ONLY the total block -- LOOP output survives', () {
      expect(
        renderWhatsAppTemplate(
          r"<LOOP source='li'>- {{item.in}}\n</LOOP><IFSET source='tot'>-----\n*Total: {{tot|idr}}*</IFSET>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'Galon Kosong'},
            ],
            'tot': 0,
          },
        ),
        '- Galon Kosong\n',
      );
    });

    test(
        'ORDERING: the IFSET pass runs BEFORE {{field}} substitution -- a tag '
        'arriving in DATA is never executed', () {
      // Control structure comes from the TEMPLATE, never from a doc field.
      // Run the pass after substitution instead and this injected tag WOULD be
      // evaluated (tot == 0 -> the note silently disappears). <LOOP> already
      // gives the same guarantee for the same reason.
      expect(
        renderWhatsAppTemplate(
          'A {{note}} B',
          <String, dynamic>{
            'note': r"<IFSET source='tot'>LEAK</IFSET>",
            'tot': 0,
          },
        ),
        "A <IFSET source='tot'>LEAK</IFSET> B",
      );
    });
  });
}
