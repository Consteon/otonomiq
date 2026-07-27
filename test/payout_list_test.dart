import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show mapTableContent;
import 'package:otonomiq/global2.dart' show txfController;
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/driver_home_support.dart' show coerceNum;
import 'package:otonomiq/widget/payout_list.dart';
import 'package:otonomiq/widget/picker_list.dart';
import 'package:otonomiq/widget/table_picker.dart';
import 'package:otonomiq/widget/task_item_builder.dart';

void main() {
  // ── textSegment ─────────────────────────────────────────────────────────────
  group('PayoutList.textSegment', () {
    test('returns value at valid index', () {
      expect(PayoutList.textSegment(['a', 'b', 'c'], 1, 'def'), 'b');
    });

    test('returns default when index out of range', () {
      expect(PayoutList.textSegment(['a'], 3, 'def'), 'def');
    });

    test('returns default for empty array at index 1+', () {
      // diamondTextToList('') returns [''], length 1 -- so index 0 gives ''
      // but index 1 should give default.
      expect(PayoutList.textSegment([''], 1, 'fallback'), 'fallback');
    });

    test('index 0 on empty-string array returns the empty string', () {
      // diamondTextToList('') -> [''], not [] -- so index 0 gives ''
      expect(PayoutList.textSegment([''], 0, 'def'), '');
    });
  });

  // ── collapseTemplate ───────────────────────────────────────────────────────
  group('PayoutList.collapseTemplate', () {
    test('replaces token with value (middle dot separator)', () {
      expect(
        PayoutList.collapseTemplate(
            '{n} dipilih \u{00B7} {total}', '{total}', 'Rp 8.000'),
        '{n} dipilih \u{00B7} Rp 8.000',
      );
    });

    test('collapses trailing middle dot when token is empty', () {
      expect(
        PayoutList.collapseTemplate(
            '{n} dipilih \u{00B7} {total}', '{total}', ''),
        '{n} dipilih',
      );
    });

    test('collapses leading middle dot when token is empty', () {
      expect(
        PayoutList.collapseTemplate(
            '{total} \u{00B7} {n} worker', '{total}', ''),
        '{n} worker',
      );
    });

    test('collapses middle double middle dot separator', () {
      expect(
        PayoutList.collapseTemplate(
            'a \u{00B7} {x} \u{00B7} b', '{x}', ''),
        'a \u{00B7} b',
      );
    });

    test('collapses trailing em dash when token is empty', () {
      expect(
        PayoutList.collapseTemplate(
            '{n} dipilih \u{2014} {total}', '{total}', ''),
        '{n} dipilih',
      );
    });

    test('collapses trailing pipe when token is empty', () {
      expect(
        PayoutList.collapseTemplate('{n} dipilih | {total}', '{total}', ''),
        '{n} dipilih',
      );
    });

    test('collapses trailing hyphen when token is empty', () {
      expect(
        PayoutList.collapseTemplate('{n} dipilih - {total}', '{total}', ''),
        '{n} dipilih',
      );
    });

    test('no separator: plain replacement', () {
      expect(
        PayoutList.collapseTemplate('{n} dipilih', '{n}', '3'),
        '3 dipilih',
      );
    });

    test('no separator, empty token: just removes the token', () {
      expect(
        PayoutList.collapseTemplate('{total} items', '{total}', ''),
        'items',
      );
    });

    // Issue fix (W1-residual): token mid-template with a SINGLE adjacent
    // separator. These are the spec's literal text[5] / text[3] strings, with
    // {n} already substituted (call order: {n} first, then collapseTemplate).
    test('spec text[5]: mid-template token + trailing single separator', () {
      // "Total belum ditransfer {total} · {n} worker", {n} -> 5.
      expect(
        PayoutList.collapseTemplate(
            'Total belum ditransfer {total} \u{00B7} 5 worker', '{total}', ''),
        'Total belum ditransfer 5 worker',
      );
    });

    test('spec text[3]: trailing token + preceding single separator', () {
      // "{n} dipilih · {total}", {n} -> 2.
      expect(
        PayoutList.collapseTemplate('2 dipilih \u{00B7} {total}', '{total}', ''),
        '2 dipilih',
      );
    });
  });

  // ── Reused static helpers (sanity, not exhaustive) ─────────────────────────
  group('Reused helper sanity', () {
    test('TablePicker.resolveValueFromDoc: empty valueField uses __docId', () {
      final doc = <String, dynamic>{'__docId': 'DOC1', 'cv': 'V1'};
      expect(TablePicker.resolveValueFromDoc(doc, ''), 'DOC1');
    });

    test('TablePicker.resolveValueFromDoc: explicit field', () {
      final doc = <String, dynamic>{'__docId': 'DOC1', 'cv': 'V1'};
      expect(TablePicker.resolveValueFromDoc(doc, 'cv'), 'V1');
    });

    test('coerceNum: Firestore Number', () {
      expect(coerceNum(3), 3);
    });

    test('coerceNum: numeric string', () {
      expect(coerceNum('5'), 5);
    });

    test('coerceNum: null', () {
      expect(coerceNum(null), 0);
    });

    test('AdminCreateTaskSupport.formatRupiah: thousands', () {
      expect(AdminCreateTaskSupport.formatRupiah(8000), 'Rp 8.000');
    });

    test('AdminCreateTaskSupport.formatRupiah: zero', () {
      expect(AdminCreateTaskSupport.formatRupiah(0), 'Rp 0');
    });

    test('PickerList.filterRows: empty search returns all docs', () {
      final docs = <Map<String, dynamic>>[
        {'__docId': 'D1', 'rd': '1'},
        {'__docId': 'D2', 'rd': '2'},
      ];
      expect(PickerList.filterRows(docs, ''), docs);
    });

    test('TaskItemBuilder.sortPickerItems: sorts asc by numeric field', () {
      final items = <Map<String, dynamic>>[
        {'cn': 'Zara', 'bt': 1},
        {'cn': 'Anna', 'bt': 3},
      ];
      TaskItemBuilder.sortPickerItems(items,
          sortField: 'bt', sortDir: 'asc', nameField: 'cn');
      // sortField is numeric via coerceNum: bt 1 < bt 3.
      expect(items[0]['cn'], 'Zara'); // bt=1, smallest -> first
      expect(items[0]['bt'], 1);
      expect(items[1]['cn'], 'Anna'); // bt=3, largest -> second
      expect(items[1]['bt'], 3);
    });
  });

  // ── clearState ─────────────────────────────────────────────────────────────
  group('PayoutList.clearState', () {
    test('removes scrName entry from selection store', () {
      // No-op on unknown scrName (no crash).
      PayoutList.clearState('nonexistent_screen');
    });

    // I6: verify clearState actually drops a real selection.
    testWidgets('clearState drops selection and rebuild shows no checked items',
        (WidgetTester tester) async {
      const String scrName = 'pl_clear_01';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Eve', 'cv': 'E1'},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '',
        'position': 30,
        'labelField': 'cn',
        'valueField': 'cv',
        'rate': '100',
        'text': 'T\u{25C6}E',
      };

      Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Select Eve.
      await tester.tap(find.text('Eve'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![30]!.finalData, 'E1');

      // Simulate route change: clearState.
      PayoutList.clearState(scrName);

      // Rebuild the widget (simulates returning to the page).
      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // The checked icon should be gone -- only unchecked boxes remain.
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });
  });

  // ── Widget pump: Obx smoke test (Prior Correction #4) ─────────────────────
  // Verifies that the widget registers >=1 Obx observable and does not throw
  // GetX "improper use" even when mapTableContent[code] is absent/null.
  group('widget pump: Obx smoke + empty state', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders empty state without GetX crash', (WidgetTester tester) async {
      const String scrName = 'pl_smoke_01';
      PayoutList.clearState(scrName);
      addTearDown(() => PayoutList.clearState(scrName));

      // Seed mapTableContent with empty key so Obx has an observable.
      // The widget subscribes via _subscribe(), but in test no Firestore is
      // available, so _code stays '' (rawTable empty). The unconditional
      // `mapTableContent[_code]` read uses '' which is safe.
      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '', // no table -> _code = '', no subscription
        'position': 18,
        'rate': '1000',
        'text': 'Belum Dibayar\u{25C6}Semua sudah ditransfer',
      };

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Core regression guard: no GetX "improper use" build exception.
      expect(tester.takeException(), isNull,
          reason: 'PayoutList must register >=1 Obx observable');

      // Empty state text renders.
      expect(find.text('Semua sudah ditransfer'), findsOneWidget);
      // Title renders.
      expect(find.text('Belum Dibayar'), findsOneWidget);
    });

    testWidgets('renders rows, computes nominal, and emits in display order',
        (WidgetTester tester) async {
      const String scrName = 'pl_smoke_02';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      // Seed mapTableContent[''] with test docs.
      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Ratna', 'hn': '@ratna', 'bt': 3, 'cv': 'V1', 'rd': '1'},
        {'__docId': 'D2', 'cn': 'Dedi K.', 'hn': '@dedi', 'bt': 5, 'cv': 'V2', 'rd': '1'},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '', // -> _code = ''
        'position': 18,
        'labelPosition': 19,
        'totalPosition': 20,
        'labelField': 'cn',
        'subField': 'hn',
        'countField': 'bt',
        'valueField': 'cv',
        'rate': '1000',
        'sortField': 'cn',
        'sortDir': 'asc',
        'selectAll': true,
        'joinSep': '|',
        'text':
            'Belum Dibayar\u{25C6}Semua sudah\u{25C6}Pilih semua ({n})\u{25C6}{n} dipilih \u{00B7} {total}\u{25C6}{c} batch siap \u{00B7} {nom}\u{25C6}Total {total} \u{00B7} {n} worker',
      };

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Rows rendered (sorted asc by cn: Dedi < Ratna).
      expect(find.text('Dedi K.'), findsOneWidget);
      expect(find.text('Ratna'), findsOneWidget);
      // Sub-labels rendered.
      expect(find.text('@dedi'), findsOneWidget);
      expect(find.text('@ratna'), findsOneWidget);
      // Select-all row rendered with count.
      expect(find.textContaining('Pilih semua (2)'), findsOneWidget);
      // No items selected initially -> no selected counter.
      expect(find.textContaining('dipilih'), findsNothing);

      // W4: verify rendered summary line (text[5]) with grand total.
      // Grand total = (3+5)*1000 = 8000.
      expect(find.textContaining('Total Rp 8.000'), findsOneWidget);
      expect(find.textContaining('2 worker'), findsOneWidget);

      // Tap first item (Dedi K. -- displayed first due to sort).
      await tester.tap(find.text('Dedi K.'));
      await tester.pumpAndSettle();

      // Verify txfController emit.
      expect(txfController[scrName]![18]!.finalData, 'V2');
      expect(txfController[scrName]![19]!.finalData, 'Dedi K.');
      expect(txfController[scrName]![20]!.finalData, '5000');

      // W4: verify rendered selected counter (text[3]).
      expect(find.textContaining('1 dipilih'), findsOneWidget);
      expect(find.textContaining('Rp 5.000'), findsWidgets);

      // Tap second item (Ratna).
      await tester.tap(find.text('Ratna'));
      await tester.pumpAndSettle();

      // Both selected: values joined with | in DISPLAY order (Dedi, Ratna).
      expect(txfController[scrName]![18]!.finalData, 'V2|V1');
      expect(txfController[scrName]![19]!.finalData, 'Dedi K.|Ratna');
      expect(txfController[scrName]![20]!.finalData, '8000');

      // W4: verify rendered selected counter updated.
      expect(find.textContaining('2 dipilih'), findsOneWidget);
    });

    // C1: emit order is always display (sorted) order, not tap order.
    testWidgets('C1: tap order differs from display order, emit is display order',
        (WidgetTester tester) async {
      const String scrName = 'pl_c1_order';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      // Sorted asc by cn: Anna < Zara. So display order = Anna, Zara.
      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Zara', 'cv': 'ZID', 'bt': 2},
        {'__docId': 'D2', 'cn': 'Anna', 'cv': 'AID', 'bt': 3},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '',
        'position': 40,
        'labelPosition': 41,
        'totalPosition': 42,
        'labelField': 'cn',
        'countField': 'bt',
        'valueField': 'cv',
        'rate': '1000',
        'sortField': 'cn',
        'sortDir': 'asc',
        'joinSep': '|',
        'text': 'T\u{25C6}E',
      };

      Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Tap Zara FIRST (second in display order), then Anna.
      await tester.tap(find.text('Zara'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anna'));
      await tester.pumpAndSettle();

      // Values and labels must be in DISPLAY order (Anna, Zara), NOT tap order.
      expect(txfController[scrName]![40]!.finalData, 'AID|ZID');
      expect(txfController[scrName]![41]!.finalData, 'Anna|Zara');
      // Total = Anna(3*1000) + Zara(2*1000) = 5000.
      expect(txfController[scrName]![42]!.finalData, '5000');
    });

    // C2: stale id excluded from all outputs when row departs.
    testWidgets('C2: departed row id excluded from all outputs',
        (WidgetTester tester) async {
      const String scrName = 'pl_c2_stale';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Alice', 'cv': 'A1', 'bt': 2},
        {'__docId': 'D2', 'cn': 'Bob', 'cv': 'B1', 'bt': 3},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '',
        'position': 50,
        'labelPosition': 51,
        'totalPosition': 52,
        'labelField': 'cn',
        'countField': 'bt',
        'valueField': 'cv',
        'rate': '1000',
        'sortField': 'cn',
        'sortDir': 'asc',
        'joinSep': '|',
        'text': 'T\u{25C6}E',
      };

      Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Select both.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![50]!.finalData, 'A1|B1');
      expect(txfController[scrName]![51]!.finalData, 'Alice|Bob');
      expect(txfController[scrName]![52]!.finalData, '5000');

      // Simulate CF resetting Bob's rd -> row departs from subscription.
      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Alice', 'cv': 'A1', 'bt': 2},
      ];

      // Pump to trigger Obx rebuild.
      await tester.pump();
      await tester.pumpAndSettle();

      // Bob's row is gone. Bob's id is stale in _selectionStore.
      // The rendered list should only show Alice.
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);

      // Tap Alice to trigger _writeToController with the stale store.
      // (Untap then re-tap to force a write cycle.)
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // Bob must be excluded from ALL outputs.
      expect(txfController[scrName]![50]!.finalData, 'A1');
      expect(txfController[scrName]![51]!.finalData, 'Alice');
      expect(txfController[scrName]![52]!.finalData, '2000');
    });

    testWidgets('non-money mode: rate empty hides nominal, totalPosition=0',
        (WidgetTester tester) async {
      const String scrName = 'pl_smoke_03';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Alice', 'bt': 3, 'cv': 'A1'},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '',
        'position': 10,
        'totalPosition': 11,
        'labelField': 'cn',
        'countField': 'bt',
        'valueField': 'cv',
        'rate': '', // non-money mode
        'text': 'Title\u{25C6}Empty\u{25C6}All ({n})\u{25C6}{n} dipilih \u{00B7} {total}\u{25C6}{c} batch \u{00B7} {nom}\u{25C6}Total {total} \u{00B7} {n} worker',
      };

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Nominal line should NOT be rendered (no "batch" text with Rp).
      expect(find.textContaining('Rp'), findsNothing);

      // Tap to select.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![10]!.finalData, 'A1');
      expect(txfController[scrName]![11]!.finalData, '0');
    });

    testWidgets('deselect-to-empty writes empty/0', (WidgetTester tester) async {
      const String scrName = 'pl_smoke_04';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Bob', 'cv': 'B1'},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '',
        'position': 5,
        'labelPosition': 6,
        'totalPosition': 7,
        'labelField': 'cn',
        'valueField': 'cv',
        'rate': '500',
        'text': 'T\u{25C6}E',
      };

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Select.
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![5]!.finalData, 'B1');

      // Deselect.
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![5]!.finalData, '');
      expect(txfController[scrName]![6]!.finalData, '');
      expect(txfController[scrName]![7]!.finalData, '0');
    });

    testWidgets('selectAll:false hides select-all row', (WidgetTester tester) async {
      const String scrName = 'pl_smoke_05';
      PayoutList.clearState(scrName);
      addTearDown(() {
        PayoutList.clearState(scrName);
        mapTableContent.remove('');
      });

      mapTableContent[''] = <Map<String, dynamic>>[
        {'__docId': 'D1', 'cn': 'Cara', 'cv': 'C1'},
      ];

      final Map<String, dynamic> component = {
        'type': 'PAYOUT_LIST',
        'table': '',
        'position': 5,
        'labelField': 'cn',
        'valueField': 'cv',
        'rate': '100',
        'selectAll': false,
        'text': 'T\u{25C6}E\u{25C6}All ({n})',
      };

      await tester.pumpWidget(wrap(PayoutList(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Select-all row should NOT render.
      expect(find.textContaining('All ('), findsNothing);
    });
  });
}
