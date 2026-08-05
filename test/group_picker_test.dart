import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'
    show mapTableContent, transactionStore, autheniumDecode;
import 'package:otonomiq/global2.dart' show txfController;
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart'
    show resolveDriverCurlyTokens;
import 'package:otonomiq/widget/group_picker.dart';
import 'package:otonomiq/widget/picker_list.dart'; // PickerList.filterRows reuse
import 'package:otonomiq/widget/table_picker.dart'; // TablePicker.resolveValueFromDoc reuse
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // -- parseStaticOptions -----------------------------------------------------
  group('GroupPicker.parseStaticOptions', () {
    const String ps = '\u{25C6}'; // pairSep (black diamond)
    const String is_ = '\u{2B58}'; // itemSep (heavy large circle)

    test('standard 3-pair options', () {
      final opts = 'Product Group${ps}83674161979544'
          '${is_}Kantor Pusat${ps}32639062303108'
          '${is_}Cabang${ps}99887766554433';
      final r = GroupPicker.parseStaticOptions(opts, ps, is_);
      expect(r.length, 3);
      expect(r[0], {'name': 'Product Group', 'id': '83674161979544'});
      expect(r[1], {'name': 'Kantor Pusat', 'id': '32639062303108'});
      expect(r[2], {'name': 'Cabang', 'id': '99887766554433'});
    });

    test('single pair', () {
      final r = GroupPicker.parseStaticOptions(
          'Alice${ps}ID1', ps, is_);
      expect(r.length, 1);
      expect(r[0], {'name': 'Alice', 'id': 'ID1'});
    });

    test('empty string returns empty list', () {
      expect(GroupPicker.parseStaticOptions('', ps, is_), isEmpty);
    });

    test('blank/whitespace returns empty list', () {
      expect(GroupPicker.parseStaticOptions('   ', ps, is_), isEmpty);
    });

    test('no separator in item: name = id', () {
      final r = GroupPicker.parseStaticOptions('JustAValue', ps, is_);
      expect(r.length, 1);
      expect(r[0], {'name': 'JustAValue', 'id': 'JustAValue'});
    });

    test('empty name uses id', () {
      final r = GroupPicker.parseStaticOptions('${ps}ID1', ps, is_);
      expect(r.length, 1);
      expect(r[0]['name'], 'ID1');
      expect(r[0]['id'], 'ID1');
    });

    test('empty id uses name', () {
      final r = GroupPicker.parseStaticOptions('Alice$ps', ps, is_);
      expect(r.length, 1);
      expect(r[0]['name'], 'Alice');
      expect(r[0]['id'], 'Alice');
    });

    test('trailing itemSep does not produce empty entry', () {
      final r = GroupPicker.parseStaticOptions(
          'A${ps}1${is_}B${ps}2$is_', ps, is_);
      expect(r.length, 2);
    });

    test('mixed: some items with separator, some without', () {
      final r = GroupPicker.parseStaticOptions(
          'Alice${ps}ID1${is_}Orphan${is_}Bob${ps}ID2', ps, is_);
      expect(r.length, 3);
      expect(r[0], {'name': 'Alice', 'id': 'ID1'});
      expect(r[1], {'name': 'Orphan', 'id': 'Orphan'});
      expect(r[2], {'name': 'Bob', 'id': 'ID2'});
    });

    // Regression: the src:doc bug. The top-level pairSep/itemSep config arrives
    // server-escaped, but the Firestore doc field carries REAL ◆/⭘. Before the
    // fix the escaped separator never matched -> the whole field became ONE
    // option. Both escape forms (_u25C6_ and bare _25C6_) must normalize.
    test('escaped _u-form separators split a real-char doc field', () {
      final field = 'Imaglo CS${ps}78813680177365'
          '${is_}Edu FM${ps}35339332499941'
          '${is_}Functional test${ps}41999999104694';
      final r = GroupPicker.parseStaticOptions(field, '_u25C6_', '_u2B58_');
      expect(r.length, 3);
      expect(r[0], {'name': 'Imaglo CS', 'id': '78813680177365'});
      expect(r[1], {'name': 'Edu FM', 'id': '35339332499941'});
      expect(r[2], {'name': 'Functional test', 'id': '41999999104694'});
    });

    test('escaped bare-form separators split a real-char doc field', () {
      final field = 'Product Group${ps}83674161979544'
          '${is_}Kantor Pusat${ps}32639062303108';
      final r = GroupPicker.parseStaticOptions(field, '_25C6_', '_2B58_');
      expect(r.length, 2);
      expect(r[0], {'name': 'Product Group', 'id': '83674161979544'});
      expect(r[1], {'name': 'Kantor Pusat', 'id': '32639062303108'});
    });
  });

  // -- encodeSelection --------------------------------------------------------
  group('GroupPicker.encodeSelection', () {
    const String sep = '\u{25C6}';

    test('single mode returns bare string', () {
      expect(
        GroupPicker.encodeSelection(['V1'], sep, isSingle: true),
        'V1',
      );
    });

    test('single mode with empty list returns empty string', () {
      expect(
        GroupPicker.encodeSelection([], sep, isSingle: true),
        '',
      );
    });

    test('multi mode joins with sep', () {
      expect(
        GroupPicker.encodeSelection(['V1', 'V2', 'V3'], sep, isSingle: false),
        'V1${sep}V2${sep}V3',
      );
    });

    test('multi mode single item: no trailing sep', () {
      expect(
        GroupPicker.encodeSelection(['V1'], sep, isSingle: false),
        'V1',
      );
    });

    test('multi mode empty list returns empty string', () {
      expect(
        GroupPicker.encodeSelection([], sep, isSingle: false),
        '',
      );
    });

    test('multi mode does NOT use jsonEncode (no brackets/quotes)', () {
      final result =
          GroupPicker.encodeSelection(['A', 'B'], sep, isSingle: false);
      expect(result.contains('['), false);
      expect(result.contains('"'), false);
    });
  });

  // -- clientSearchStatic -----------------------------------------------------
  group('GroupPicker.clientSearchStatic', () {
    final options = [
      {'name': 'Product Group', 'id': '111'},
      {'name': 'Kantor Pusat', 'id': '222'},
      {'name': 'Cabang Bandung', 'id': '333'},
    ];

    test('empty query returns all', () {
      expect(GroupPicker.clientSearchStatic(options, '').length, 3);
    });

    test('matches case-insensitive', () {
      final r = GroupPicker.clientSearchStatic(options, 'kantor');
      expect(r.length, 1);
      expect(r[0]['name'], 'Kantor Pusat');
    });

    test('partial match works', () {
      final r = GroupPicker.clientSearchStatic(options, 'an');
      // 'Kantor' has 'an', 'Bandung' has 'an'
      expect(r.length, 2);
    });

    test('no match returns empty', () {
      expect(GroupPicker.clientSearchStatic(options, 'zzz'), isEmpty);
    });

    test('whitespace-only query returns all', () {
      expect(GroupPicker.clientSearchStatic(options, '   ').length, 3);
    });
  });

  // -- textSegment (length-guard) ---------------------------------------------
  group('GroupPicker.textSegment', () {
    test('full 5-segment array returns each segment', () {
      final arr = ['Cari', 'Kosong', 'Pilih', 'Batal', '{n} dipilih'];
      expect(GroupPicker.textSegment(arr, 0, 'def'), 'Cari');
      expect(GroupPicker.textSegment(arr, 4, 'def'), '{n} dipilih');
    });

    test('short array returns default for out-of-range index', () {
      final arr = ['Cari', 'Kosong'];
      expect(GroupPicker.textSegment(arr, 0, 'def'), 'Cari');
      expect(GroupPicker.textSegment(arr, 1, 'def'), 'Kosong');
      expect(GroupPicker.textSegment(arr, 2, 'fallback'), 'fallback');
      expect(GroupPicker.textSegment(arr, 4, 'x'), 'x');
    });

    test('empty array returns default for all indexes', () {
      expect(GroupPicker.textSegment([], 0, 'fb'), 'fb');
    });

    test('diamondTextToList empty gotcha: [""] length 1, index 0 returns ""', () {
      // diamondTextToList('') returns [''] not [] -- verify the guard
      // handles this correctly: arr.length > 0 is true, arr[0] is ''
      expect(GroupPicker.textSegment([''], 0, 'default'), '');
      expect(GroupPicker.textSegment([''], 1, 'default'), 'default');
    });
  });

  // -- key/label emit (integration of encode) ---------------------------------
  group('key/label emit', () {
    const String sep = '\u{25C6}';

    test('key is always bare string (group key)', () {
      // Key is not encoded -- it is a bare string from the group config
      // This test documents the contract
      const String groupKey = 'cc';
      expect(groupKey, 'cc');
    });

    test('multi label join uses same sep as value', () {
      final labels = ['Product Group', 'Kantor Pusat'];
      final encoded =
          GroupPicker.encodeSelection(labels, sep, isSingle: false);
      expect(encoded, 'Product Group${sep}Kantor Pusat');
    });

    test('single label is bare string', () {
      final encoded =
          GroupPicker.encodeSelection(['Product Group'], sep, isSingle: true);
      expect(encoded, 'Product Group');
    });
  });

  // -- per-group selection isolation (via static stores) ----------------------
  group('per-group selection isolation (static store contract)', () {
    // These tests exercise the static store structure that the widget uses.
    // They prove that selections in one group don't leak to another.

    test('separate group keys maintain independent sets', () {
      final Map<String, Set<String>> store = {};
      store.putIfAbsent('cc', () => {}).add('V1');
      store.putIfAbsent('cc', () => {}).add('V2');
      store.putIfAbsent('site', () => {}).add('S1');

      expect(store['cc'], {'V1', 'V2'});
      expect(store['site'], {'S1'});
      // Removing from cc does not affect site
      store['cc']!.remove('V1');
      expect(store['cc'], {'V2'});
      expect(store['site'], {'S1'});
    });

    test('clearing one group does not affect another', () {
      final Map<String, Set<String>> store = {
        'cc': {'V1', 'V2'},
        'site': {'S1'},
      };
      store['cc']!.clear();
      expect(store['cc'], isEmpty);
      expect(store['site'], {'S1'});
    });
  });

  // -- server-encoded search DSL (table-src reuse via PickerList) -------------
  group('PickerList.filterRows reuse for table-src groups', () {
    final rows = [
      {'n': 'Alice', 'sv': 'SITE1', 'ps': 'driver'},
      {'n': 'Bob', 'sv': 'SITE1', 'ps': 'crew'},
      {'n': 'Carol', 'sv': 'SITE2', 'ps': 'driver'},
    ];

    test('single-clause encoded search filters', () {
      final r = PickerList.filterRows(rows, 'ps_25FC_driver');
      expect(r.map((d) => d['n']).toList(), ['Alice', 'Carol']);
    });

    test('AND-gate encoded search narrows', () {
      final r = PickerList.filterRows(
          rows, 'ps_25FC_driver_u2B58_sv_25FC_SITE1');
      expect(r.length, 1);
      expect(r.single['n'], 'Alice');
    });

    test('empty search returns all (no entity fallback)', () {
      expect(PickerList.filterRows(rows, '').length, 3);
    });
  });

  // -- TablePicker.resolveValueFromDoc reuse for table-src groups -------------
  group('TablePicker.resolveValueFromDoc reuse', () {
    test('empty valueField returns __docId', () {
      final doc = {'__docId': 'DOC1', 'n': 'Alice', 'vid': 'V1'};
      expect(TablePicker.resolveValueFromDoc(doc, ''), 'DOC1');
    });

    test('explicit valueField returns that field', () {
      final doc = {'__docId': 'DOC1', 'n': 'Alice', 'vid': 'V1'};
      expect(TablePicker.resolveValueFromDoc(doc, 'vid'), 'V1');
    });

    test('missing field returns empty string (no crash)', () {
      final doc = {'__docId': 'DOC1', 'n': 'Alice'};
      expect(TablePicker.resolveValueFromDoc(doc, 'vid'), '');
    });
  });

  // -- Widget pump: single-mode output ----------------------------------------
  // Verifies radio semantics (only one item selected at a time) and that the
  // emitted finalData is a bare id string (no pairSep, no join).
  group('single-mode widget pump: radio semantics + bare id emit', () {
    const String ps = '\u{25C6}'; // pairSep (◆)
    const String is_ = '\u{2B58}'; // itemSep (⭘)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('tapping second item deselects first; finalData is bare id',
        (WidgetTester tester) async {
      const String scrName = 'gp_single_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'single',
        'selector': 'segmented',
        'valuePosition': 20,
        'keyPosition': 21,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'static',
            'options': 'Alpha${ps}A001${is_}Beta${ps}B002',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![20]!.finalData, 'A001');

      // Tap second item — single mode must clear first selection
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(
        txfController[scrName]![20]!.finalData,
        'B002',
        reason: 'single mode: last-tapped item wins (radio semantics)',
      );
      expect(
        txfController[scrName]![20]!.finalData.contains(ps),
        isFalse,
        reason: 'single mode emits bare id, no pairSep join',
      );
    });

    testWidgets('keyPosition finalData equals active group key',
        (WidgetTester tester) async {
      const String scrName = 'gp_single_02';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'single',
        'selector': 'segmented',
        'valuePosition': 22,
        'keyPosition': 23,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'static',
            'options': 'Alpha${ps}A001${is_}Beta${ps}B002',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(
        txfController[scrName]![23]!.finalData,
        'cc',
        reason: 'keyPosition always holds the active group key (bare string)',
      );
    });
  });

  // -- Widget pump: multi-mode + reset-on-tab-switch (R4) ----------------------
  // R4 REVERSES per-group preservation: leaving a tab RESETS that tab's
  // selection, so only the currently-active tab ever holds a selection. Also
  // verifies multi-mode output is the configured pairSep join (not jsonEncode).
  group('multi-mode widget pump: reset-on-tab-switch (R4) + pairSep join', () {
    const String is_ = '\u{2B58}'; // itemSep (⭘)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets(
        'R4: leaving a tab resets it; active-group value uses pairSep join',
        (WidgetTester tester) async {
      const String scrName = 'gp_multi_01';
      // Non-◆ pairSep so the join assertion is unambiguous and independent of
      // the ◆→SPACE downstream stringCleanUp note (we test the widget's join).
      const String customPs = ',';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': customPs,
        'valuePosition': 24,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1${customPs}PA1${is_}Item2${customPs}PA2',
          },
          {
            'key': 'grpB',
            'label': 'Group B',
            'src': 'static',
            'options': 'Item3${customPs}PB1${is_}Item4${customPs}PB2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Select 2 items in Group A (default active group)
      await tester.tap(find.text('Item1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![24]!.finalData, 'PA1,PA2',
          reason: 'multi output uses configured pairSep ","');

      // Switch to Group B -- leaving A RESETS A. Group B was never touched, so
      // the emitted (active-group-only) value is empty.
      await tester.tap(find.text('Group B'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![24]!.finalData, '',
          reason: 'R4: group B never touched -> empty output');

      // Switch back to Group A -- A was reset when we left it.
      await tester.tap(find.text('Group A'));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.check_box),
        findsNothing,
        reason: 'R4: leaving A reset it; no checked items remain',
      );
      expect(
        txfController[scrName]![24]!.finalData,
        '',
        reason: 'R4: group A selection was reset on tab switch',
      );
    });

    testWidgets('R4: leaving a tab resets its selection (multi, cc/site)',
        (WidgetTester tester) async {
      const String scrName = 'gp_r4_reset_01';
      const String customPs = ',';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': customPs,
        'valuePosition': 38,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'static',
            'options': 'Item1${customPs}PA1${is_}Item2${customPs}PA2',
          },
          {
            'key': 'site',
            'label': 'Site',
            'src': 'static',
            'options': 'Item3${customPs}PB1${is_}Item4${customPs}PB2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Check 2 items in cc (the active group).
      await tester.tap(find.text('Item1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![38]!.finalData, 'PA1,PA2');

      // Switch to site -> leaving cc clears cc's selection + labels. The
      // emitted value now reflects the active group (site), which is empty.
      await tester.tap(find.text('Site'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![38]!.finalData, '',
          reason: 'R4: finalData reflects active group site (empty)');

      // Return to cc -> proves cc's store was cleared: no checks, empty output.
      await tester.tap(find.text('Cost Center'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box), findsNothing,
          reason: 'R4: cc selection was reset when leaving cc');
      expect(txfController[scrName]![38]!.finalData, '',
          reason: 'R4: cc store for that pos+key is empty after reset');
    });
  });

  // -- Widget pump: revisit resets the picker -----------------------------------
  // Leaving the page and coming back must show group 0 with nothing selected,
  // and must do it on the FIRST painted frame -- clearData runs post-frame, so
  // a reset scoped to the entering screen would flash the old state for a frame.
  // clearAll wipes on the nav AWAY, while the page is off-screen.
  group('revisit resets picker', () {
    const String is_ = '\u{2B58}'; // itemSep (⭘)
    const String ps = ',';
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    Map<String, dynamic> componentFor(int valuePosition) => {
          'type': 'group_picker',
          'mode': 'multi',
          'selector': 'segmented',
          'pairSep': ps,
          'valuePosition': valuePosition,
          'groups': [
            {
              'key': 'cc',
              'label': 'Cost Center',
              'src': 'static',
              'options': 'Item1${ps}PA1${is_}Item2${ps}PA2',
            },
            {
              'key': 'site',
              'label': 'Site',
              'src': 'static',
              'options': 'Item3${ps}PB1${is_}Item4${ps}PB2',
            },
          ],
        };

    /// Switch to the second group ('Site') and tick 'Item3'.
    Future<void> selectInSecondGroup(WidgetTester tester) async {
      await tester.tap(find.text('Site'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item3'));
      await tester.pumpAndSettle();
    }

    void expectResetToFirstGroup() {
      expect(find.byIcon(Icons.check_box), findsNothing,
          reason: 'revisit must start with nothing selected');
      expect(find.text('Item1'), findsOneWidget,
          reason: 'revisit must land on the FIRST group (cc), not Site');
      expect(find.text('Item3'), findsNothing,
          reason: 'Site items must not be the active list on revisit');
    }

    testWidgets('away-then-back is clean on the FIRST frame (no glitch)',
        (WidgetTester tester) async {
      const String scrName = 'gp_revisit_01';
      GroupPicker.clearAll();
      addTearDown(GroupPicker.clearAll);

      Widget picker() => GroupPicker(
            component: componentFor(41),
            scrName: scrName,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          );

      // Visit 1: pick something in the second group.
      await tester.pumpWidget(wrap(picker()));
      await tester.pumpAndSettle();
      await selectInSecondGroup(tester);
      expect(txfController[scrName]![41]!.finalData, 'PB1');
      expect(find.byIcon(Icons.check_box), findsOneWidget);

      // Navigate AWAY to another screen: reloadPage(other) schedules
      // clearData(other) -> clearAll, which wipes this screen while it is
      // off-screen. Unmount first, exactly as the page swap does.
      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pumpAndSettle();
      GroupPicker.clearAll();

      // Visit 2. ONE pump = the first painted frame. It must already be clean;
      // pumpAndSettle here would hide a one-frame flash, which is the bug.
      await tester.pumpWidget(wrap(picker()));
      await tester.pump();
      expectResetToFirstGroup();
    });

    testWidgets('same-page clearData (submit/reset) repaints a mounted picker',
        (WidgetTester tester) async {
      const String scrName = 'gp_revisit_02';
      GroupPicker.clearAll();
      addTearDown(GroupPicker.clearAll);

      await tester.pumpWidget(wrap(GroupPicker(
        component: componentFor(42),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      await selectInSecondGroup(tester);
      expect(txfController[scrName]![42]!.finalData, 'PB1');
      expect(find.byIcon(Icons.check_box), findsOneWidget);

      // saveSend after a submit calls clearData on the CURRENT screen, with the
      // picker still mounted. No remount happens, so the resetRev bump inside
      // clearAll is the only thing that can repaint it.
      GroupPicker.clearAll();
      await tester.pumpAndSettle();
      expectResetToFirstGroup();
    });
  });

  // -- Widget pump: degrade paths (no crash) ----------------------------------
  // selector:dropdown → degrades to segmented (deferred feature, not a real dropdown).
  // display:sheet → GroupPicker ignores it; always renders inline.
  group('degrade paths: selector:dropdown and display:sheet', () {
    const String ps = '\u{25C6}'; // pairSep (◆)
    const String is_ = '\u{2B58}'; // itemSep (⭘)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('selector:dropdown degrades to segmented tabs, no crash',
        (WidgetTester tester) async {
      const String scrName = 'gp_degrade_drop_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'dropdown', // not 'none' → falls through to segmented logic
        'valuePosition': 25,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Tab One',
            'src': 'static',
            'options': 'Alpha${ps}A001',
          },
          {
            'key': 'grpB',
            'label': 'Tab Two',
            'src': 'static',
            'options': 'Beta${ps}B001',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Degrades to segmented: group labels are visible in the tab row
      expect(find.text('Tab One'), findsOneWidget);
      expect(find.text('Tab Two'), findsOneWidget);
      // Item list renders for the active group
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('display:sheet is ignored; renders inline without crash',
        (WidgetTester tester) async {
      const String scrName = 'gp_degrade_sheet_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'single',
        'display': 'sheet', // GroupPicker reads no 'display' field; always inline
        'valuePosition': 26,
        'groups': [
          {
            'key': 'grpA',
            'label': 'My Group',
            'src': 'static',
            'options': 'Alpha${ps}A001${is_}Beta${ps}B002',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Items render inline regardless of display:sheet
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });
  });

  // -- Widget pump: empty group options ---------------------------------------
  // Sparse diamond array edge case: one group has empty options string.
  // parseStaticOptions('', ...) returns [] → rows.isEmpty → empty-text renders.
  group('empty group options: shows empty-text, no crash', () {
    const String ps = '\u{25C6}'; // pairSep (◆)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('switching to empty-options group shows default empty-text',
        (WidgetTester tester) async {
      const String scrName = 'gp_empty_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 27,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Has Items',
            'src': 'static',
            'options': 'Alpha${ps}A001',
          },
          {
            'key': 'grpB',
            'label': 'Empty Group',
            'src': 'static',
            'options': '', // empty → parseStaticOptions returns []
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to the empty group tab
      await tester.tap(find.text('Empty Group'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // rows.isEmpty path → _t(1, 'Data tidak ditemukan') renders
      expect(find.text('Data tidak ditemukan'), findsOneWidget);
    });
  });

  // -- Widget pump: selector:none + single group (tablePicker-replacement) ----
  // The segmented tab toggle is hidden; plain item list renders.
  // Group labels only appear in _buildSelector, so their absence confirms
  // the toggle was not built.
  group('selector:none + single group: no segmented tab row', () {
    const String ps = '\u{25C6}'; // pairSep (◆)
    const String is_ = '\u{2B58}'; // itemSep (⭘)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('selector:none hides tab toggle; plain item list renders',
        (WidgetTester tester) async {
      const String scrName = 'gp_no_sel_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'single',
        'selector': 'none', // explicitly hide the segmented toggle
        'valuePosition': 28,
        'groups': [
          {
            'key': 'grpA',
            'label': 'My Group', // label only rendered inside _buildSelector
            'src': 'static',
            'options': 'Alpha${ps}A001${is_}Beta${ps}B002',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Group label only appears in _buildSelector → absent when selector hidden
      expect(find.text('My Group'), findsNothing,
          reason: 'selector:none: no segmented tab row rendered');
      // Item list still renders
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });
  });

  // -- Widget pump: short text array (length-guard in build pipeline) ----------
  // Malformed / sparse segment edge case: text field has only 1 ◆-segment.
  // diamondTextToList('Cari') returns ['Cari'] (length 1). Index 1 (empty-text)
  // is out of range → textSegment must fall back to default, no RangeError.
  group('short text array: length-guard fallback in widget build', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets(
        '1-segment text array: empty-text falls back to default, no RangeError',
        (WidgetTester tester) async {
      const String scrName = 'gp_short_txt_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      // 'Cari' contains no ◆ → diamondTextToList returns ['Cari'] (length 1).
      // _t(1, 'Data tidak ditemukan') uses index 1 which is out of range →
      // textSegment length-guard returns the default string, not a RangeError.
      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'single',
        'selector': 'segmented',
        'text': 'Cari', // 1 segment only: indexes 1-4 must all fall back
        'valuePosition': 29,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group',
            'src': 'static',
            'options': '', // empty options → triggers empty-text render path
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'short text array must not RangeError');
      // _t(1, 'Data tidak ditemukan') falls back to default (array length == 1)
      expect(find.text('Data tidak ditemukan'), findsOneWidget);
    });
  });

  // -- REGRESSION (C1): all-static widget pump --------------------------------
  // build() wraps everything in Obx. Before the fix the ONLY observable read was
  // gated behind `if (g.isTable && subscriptionCode.isNotEmpty)`, so an
  // all-static picker (the PRIMARY broadcast case: cc/site/vid) registered ZERO
  // observables and get 4.7.3 threw "improper use of a GetX has been detected"
  // during build -> the dispatch try/catch had already returned, so the subtree
  // became an ErrorWidget. This pumps the exact case the helper-only tests miss.
  group('all-static GroupPicker widget pump (Obx regression)', () {
    const String ps = '\u{25C6}'; // pairSep default
    const String is_ = '\u{2B58}'; // itemSep default

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders without throwing (registers >=1 Obx observable)',
        (WidgetTester tester) async {
      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 5,
        'keyPosition': 6,
        'labelPosition': 7,
        'title': 'Pilih Target',
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'static',
            'options': 'Product Group${ps}83674161979544'
                '${is_}Kantor Pusat${ps}32639062303108',
          },
          {
            'key': 'site',
            'label': 'Site',
            'src': 'static',
            'options': 'Jakarta${ps}111${is_}Bandung${ps}222',
          },
          {
            'key': 'vid',
            'label': 'Vehicle',
            'src': 'static',
            'options': 'Truck A${ps}V1${is_}Truck B${ps}V2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: 'groupPickerSmokeTest',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Core regression guard: no GetX "improper use" (or any) build exception.
      expect(tester.takeException(), isNull,
          reason: 'all-static GroupPicker must register >=1 Obx observable');
      // Segmented selector renders each group label -> the real picker subtree
      // built (not an ErrorWidget replacing it).
      expect(find.text('Cost Center'), findsOneWidget);
      expect(find.text('Site'), findsOneWidget);
    });
  });

  // -- Widget pump: select-all (R2 enhancement) -------------------------------
  // Opt-in `selectAll:true` renders a select-all-VISIBLE control above the item
  // tiles (multi mode only). Verifies gate (absent/false/single = no row),
  // select/deselect-all, search-scoped visibility, 3-state icon, and R4
  // reset-on-tab-switch. Uses a non-◆ pairSep (",") where finalData is asserted
  // so the join is unambiguous (independent of the downstream ◆->SPACE note).
  group('select-all (R2): opt-in check-all-visible', () {
    const String ps = '\u{25C6}'; // pairSep (◆)
    const String is_ = '\u{2B58}'; // itemSep (⭘)
    const String customPs = ','; // non-◆ pairSep for unambiguous join asserts

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    Map<String, dynamic> singleGroup(int vPos, String options,
            {bool selectAll = false, String mode = 'multi', String? pairSep}) =>
        {
          'type': 'group_picker',
          'mode': mode,
          'selector': 'segmented',
          if (selectAll) 'selectAll': true,
          if (pairSep != null) 'pairSep': pairSep,
          'valuePosition': vPos,
          'groups': [
            {
              'key': 'grpA',
              'label': 'Group A',
              'src': 'static',
              'options': options,
            },
          ],
        };

    testWidgets('selectAll absent (multi): no select-all row',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_absent_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      await tester.pumpWidget(wrap(GroupPicker(
        component: singleGroup(30, 'Item1${customPs}PA1${is_}Item2${customPs}PA2',
            pairSep: customPs),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Pilih semua'), findsNothing,
          reason: 'selectAll absent => no select-all row (default OFF)');
    });

    testWidgets('selectAll:false (multi): no select-all row',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_false_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component =
          singleGroup(31, 'Item1${ps}PA1${is_}Item2${ps}PA2');
      component['selectAll'] = false;

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Pilih semua'), findsNothing,
          reason: 'selectAll:false => no select-all row');
    });

    testWidgets('single mode + selectAll:true: no select-all row (no-op)',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_single_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      await tester.pumpWidget(wrap(GroupPicker(
        component: singleGroup(32, 'Item1${ps}PA1${is_}Item2${ps}PA2',
            selectAll: true, mode: 'single'),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Pilih semua'), findsNothing,
          reason: 'select-all is multi-only; never rendered in single mode');
    });

    testWidgets('multi, no search: tap select-all selects all visible ids',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_all_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      await tester.pumpWidget(wrap(GroupPicker(
        component: singleGroup(
            33,
            'Item1${customPs}PA1${is_}Item2${customPs}PA2'
                '${is_}Item3${customPs}PA3',
            selectAll: true,
            pairSep: customPs),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pilih semua'));
      await tester.pumpAndSettle();

      expect(
        txfController[scrName]![33]!.finalData,
        'PA1,PA2,PA3',
        reason: 'select-all adds every visible id, joined by configured pairSep',
      );
    });

    testWidgets('active search filter: select-all acts on visible rows only',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_search_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      await tester.pumpWidget(wrap(GroupPicker(
        component: singleGroup(
            34,
            'Apple${customPs}idA${is_}Apricot${customPs}idB'
                '${is_}Banana${customPs}idC',
            selectAll: true,
            pairSep: customPs),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Filter to the two "Ap*" rows; Banana(idC) is no longer visible.
      await tester.enterText(find.byType(TextField), 'Ap');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pilih semua'));
      await tester.pumpAndSettle();

      final String finalData = txfController[scrName]![34]!.finalData;
      expect(finalData, 'idA,idB',
          reason: 'only the search-visible ids are selected');
      expect(finalData.contains('idC'), isFalse,
          reason: 'the filtered-out id must NOT be selected');
    });

    testWidgets('tap select-all twice (all selected) deselects all',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_toggle_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      await tester.pumpWidget(wrap(GroupPicker(
        component: singleGroup(35, 'Item1${customPs}PA1${is_}Item2${customPs}PA2',
            selectAll: true, pairSep: customPs),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pilih semua'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![35]!.finalData, 'PA1,PA2');

      // All visible already selected -> second tap deselects all.
      await tester.tap(find.text('Pilih semua'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![35]!.finalData, '',
          reason: 'second tap when all-selected => deselect-all-visible');
    });

    testWidgets('3-state icon: partial=indeterminate, full=check_box',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_icon_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      await tester.pumpWidget(wrap(GroupPicker(
        component: singleGroup(36, 'Item1${ps}P1${is_}Item2${ps}P2',
            selectAll: true),
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // None selected -> blank (indeterminate icon is unique to select-all row).
      expect(find.byIcon(Icons.indeterminate_check_box), findsNothing);

      // Select ONE item -> select-all shows indeterminate.
      await tester.tap(find.text('Item1'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.indeterminate_check_box), findsOneWidget,
          reason: 'some-but-not-all visible selected => indeterminate');

      // Select the OTHER item -> select-all flips to check_box.
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.indeterminate_check_box), findsNothing);
      expect(find.byIcon(Icons.check_box), findsNWidgets(3),
          reason: 'all visible selected: 2 item tiles + select-all all checked');
    });

    testWidgets('R4: select-all in A is reset on leave; B stays untouched',
        (WidgetTester tester) async {
      const String scrName = 'gp_sa_iso_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'selectAll': true,
        'pairSep': customPs,
        'valuePosition': 37,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1${customPs}PA1${is_}Item2${customPs}PA2',
          },
          {
            'key': 'grpB',
            'label': 'Group B',
            'src': 'static',
            'options': 'Item3${customPs}PB1${is_}Item4${customPs}PB2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // Select-all in the default active group A.
      await tester.tap(find.text('Pilih semua'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![37]!.finalData, 'PA1,PA2');

      // Switch to B: leaving A RESETS A. B was never touched -> empty.
      await tester.tap(find.text('Group B'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![37]!.finalData, '',
          reason: 'group B untouched -> empty (select-all in A never leaked)');

      // Switch back to A: A was reset when we left it (R4) -> now empty.
      await tester.tap(find.text('Group A'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![37]!.finalData, '',
          reason: 'R4: select-all selection in A was reset on tab switch');
    });
  });

  // -- Widget pump: joinSep output separator (R3 enhancement) ------------------
  // OUTPUT-only `joinSep` joins the multi-mode value/label lists, decoupled from
  // `pairSep` (which still parses the ◆-delimited static options). Lets the
  // emitted bcc use a stringCleanUp-surviving char while options stay readable.
  // Verifies: joinSep join (value + label), absent/empty fallback to pairSep,
  // single-mode bare (no join), and select-all join (ties R2 + R3).
  group('joinSep (R3): output join separator', () {
    const String ps = '\u{25C6}'; // pairSep (◆)
    const String is_ = '\u{2B58}'; // itemSep (⭘)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('joinSep:"|" + pairSep:"◆": multi value & label joined by "|"',
        (WidgetTester tester) async {
      const String scrName = 'gp_js_pipe_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': ps, // ◆ parses the static options below
        'joinSep': '|', // | joins the emitted output (survives stringCleanUp)
        'valuePosition': 40,
        'labelPosition': 41,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1${ps}id1${is_}Item2${ps}id2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Options parsed via ◆; OUTPUT joined by | (not ◆). Insertion order in the
      // LinkedHashSet: Item1 then Item2.
      await tester.tap(find.text('Item1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![40]!.finalData, 'id1|id2',
          reason: 'multi value joined by joinSep "|", not pairSep "◆"');
      expect(txfController[scrName]![40]!.finalData.contains(ps), isFalse,
          reason: 'pairSep ◆ must NOT appear in the joined output');
      expect(txfController[scrName]![41]!.finalData, 'Item1|Item2',
          reason: 'multi label also joined by joinSep "|"');
    });

    testWidgets('joinSep absent: multi output falls back to pairSep',
        (WidgetTester tester) async {
      const String scrName = 'gp_js_absent_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': ';', // no joinSep key → join must fall back to this
        'valuePosition': 42,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1;X1${is_}Item2;X2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![42]!.finalData, 'X1;X2',
          reason: 'joinSep absent => multi join uses pairSep ";" (backward-compat)');
    });

    testWidgets('joinSep:"" (empty): falls back to pairSep',
        (WidgetTester tester) async {
      const String scrName = 'gp_js_empty_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': ';',
        'joinSep': '', // empty → getter falls back to pairSep
        'valuePosition': 43,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1;X1${is_}Item2;X2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![43]!.finalData, 'X1;X2',
          reason: 'empty joinSep => fall back to pairSep ";"');
    });

    testWidgets('single mode + joinSep:"|": finalData is bare id (no join)',
        (WidgetTester tester) async {
      const String scrName = 'gp_js_single_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'single',
        'selector': 'segmented',
        'joinSep': '|', // irrelevant in single mode (no join)
        'valuePosition': 44,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Alpha${ps}A001${is_}Beta${ps}B002',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![44]!.finalData, 'B002',
          reason: 'single mode: bare id, joinSep does not apply');
      expect(txfController[scrName]![44]!.finalData.contains('|'), isFalse,
          reason: 'no joinSep separator in single-mode output');
    });

    testWidgets('select-all + joinSep:"|": all-selected value joined by "|"',
        (WidgetTester tester) async {
      const String scrName = 'gp_js_sa_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'selectAll': true,
        'pairSep': ps, // ◆ parses options
        'joinSep': '|', // | joins the emitted output
        'valuePosition': 45,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1${ps}a${is_}Item2${ps}b${is_}Item3${ps}c',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pilih semua'));
      await tester.pumpAndSettle();

      expect(txfController[scrName]![45]!.finalData, 'a|b|c',
          reason: 'select-all output joined by joinSep "|" (ties R2 + R3)');
      expect(txfController[scrName]![45]!.finalData.contains(ps), isFalse,
          reason: 'pairSep ◆ must not appear in the select-all output');
    });
  });

  // -- Widget pump: bounded-scroll item list (R5 enhancement) ------------------
  // The person-tile list gets its own height-capped, internally-scrollable box
  // (ConstrainedBox > SingleChildScrollView > Column(min)) so a long list does
  // not push the page's send button far down. Fixed (outside the scroll):
  // title/hint/selector/search/select-all/count. Verifies: many rows => internal
  // scroll present + selection still works; maxListHeight override respected;
  // few rows still render + tappable (shrink-wrap path).
  group('bounded-scroll item list (R5)', () {
    const String is_ = '\u{2B58}'; // itemSep (⭘)
    const String customPs = ','; // non-◆ pairSep for unambiguous finalData

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('many rows: item-list scroll present; selection still works',
        (WidgetTester tester) async {
      const String scrName = 'gp_r5_many_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final String opts =
          List.generate(30, (i) => 'Person$i${customPs}p$i').join(is_);
      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': customPs,
        'valuePosition': 46,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': opts,
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The item list has its own internal scroll view.
      expect(find.byType(SingleChildScrollView), findsWidgets);

      // First tile is at the top of the capped box -> visible + tappable; the
      // scroll wrapper must not break selection.
      await tester.tap(find.text('Person0'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![46]!.finalData, 'p0',
          reason: 'wrapping the list in a scroll box must not break selection');
      expect(tester.takeException(), isNull);
    });

    testWidgets('maxListHeight override caps the item-list ConstrainedBox',
        (WidgetTester tester) async {
      const String scrName = 'gp_r5_maxh_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final String opts =
          List.generate(10, (i) => 'P$i${customPs}v$i').join(is_);
      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': customPs,
        'maxListHeight': 200,
        'valuePosition': 47,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': opts,
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The item-list ConstrainedBox is the only one with maxHeight == 200
      // (the responsive default would be screenHeight*0.4 == 240 in this window).
      final Finder listBox = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxHeight == 200,
      );
      expect(listBox, findsOneWidget);
      final ConstrainedBox box = tester.widget<ConstrainedBox>(listBox);
      expect(box.constraints.maxHeight, 200,
          reason: 'maxListHeight config overrides the responsive default');
    });

    testWidgets('few rows: both items render + tappable (shrink-wrap path)',
        (WidgetTester tester) async {
      const String scrName = 'gp_r5_few_01';
      GroupPicker.clearState(scrName);
      addTearDown(() => GroupPicker.clearState(scrName));

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'pairSep': customPs,
        'valuePosition': 48,
        'groups': [
          {
            'key': 'grpA',
            'label': 'Group A',
            'src': 'static',
            'options': 'Item1${customPs}v1${is_}Item2${customPs}v2',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Item1'), findsOneWidget);
      expect(find.text('Item2'), findsOneWidget);

      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![48]!.finalData, 'v2');
      expect(tester.takeException(), isNull);
    });
  });

  // -- _resolveSearch composition: autheniumDecode + resolveDriverCurlyTokens --

  group('_resolveSearch composition (token resolution)', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // resolveDriverCurlyTokens reads transactionStore.state.screenTx.
      // The global is null in a bare test; seed it with a known #VID.
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': '85924392055168',
      })));
    });

    test('{userVid} in encoded search resolves to #VID value', () {
      final String raw = 'gk_25FC_broadcast_{userVid}';
      final String decoded = autheniumDecode(raw) ?? raw;
      final String resolved = resolveDriverCurlyTokens(decoded, 'test_scr');
      expect(resolved, 'gk\u{25FC}broadcast_85924392055168');
    });

    test('search without token: resolveDriverCurlyTokens is no-op', () {
      final String raw = 'gk_25FC_broadcast_85924392055168';
      final String decoded = autheniumDecode(raw) ?? raw;
      final String resolved = resolveDriverCurlyTokens(decoded, 'test_scr');
      expect(resolved, 'gk\u{25FC}broadcast_85924392055168');
    });

    test('#VID empty: {userVid} stays literal (pending-safe degradation)', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': '',
      })));
      final String raw = 'gk_25FC_broadcast_{userVid}';
      final String decoded = autheniumDecode(raw) ?? raw;
      final String resolved = resolveDriverCurlyTokens(decoded, 'test_scr');
      expect(resolved, contains('{userVid}'),
          reason: 'unresolved token stays literal, not blank');
      // Restore for subsequent tests.
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#VID': '85924392055168',
      })));
    });
  });

  // -- src:doc widget pump tests ----------------------------------------------

  group('src:doc group picker (doc-source mode)', () {
    const String ps = '\u{25C6}'; // pairSep (◆)
    const String is_ = '\u{2B58}'; // itemSep (⭘)

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('src:doc renders options from doc field + Obx regression (C1)',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_01';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      // Seed mapTableContent with a mock doc. vidtable/table are empty in the
      // component so subscribeToMapCollection is never called (no Firebase
      // needed in test); code resolves to ''.
      mapTableContent[''] = [
        <String, dynamic>{
          'gk': 'broadcast_123',
          'cc':
              'Product Group${ps}83674161979544${is_}Kantor Pusat${ps}32639062303108',
        },
      ];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 30,
        'keyPosition': 31,
        'pairSep': ps,
        'itemSep': is_,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'cc',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      // C1 regression: no GetX "improper use" build exception.
      expect(tester.takeException(), isNull,
          reason: 'src:doc GroupPicker must register >=1 Obx observable');
      // Options from the doc field are displayed by name.
      expect(find.text('Product Group'), findsOneWidget);
      expect(find.text('Kantor Pusat'), findsOneWidget);

      // Tap selects; emit verifies id (not name) in finalData.
      await tester.tap(find.text('Product Group'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![30]!.finalData, '83674161979544');
      expect(txfController[scrName]![31]!.finalData, 'cc');
    });

    testWidgets('src:doc no matching doc -> empty list + emptyText',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_empty';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      // Doc exists but search does NOT match (gk mismatch).
      mapTableContent[''] = [
        <String, dynamic>{
          'gk': 'broadcast_OTHER',
          'cc': 'Alpha${ps}A1',
        },
      ];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 32,
        'pairSep': ps,
        'itemSep': is_,
        'text': 'Cari\u{25C6}Tidak ada data',
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'cc',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Tidak ada data'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('src:doc field missing in doc -> empty list',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_nofield';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      // Doc matches search, but the target field ('cc') does not exist.
      mapTableContent[''] = [
        <String, dynamic>{
          'gk': 'broadcast_123',
          // no 'cc' key
        },
      ];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 33,
        'pairSep': ps,
        'itemSep': is_,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'cc',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Data tidak ditemukan'), findsOneWidget);
    });

    testWidgets('src:doc field empty string -> empty list',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_emptyfield';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      // Doc matches, field exists but is empty.
      mapTableContent[''] = [
        <String, dynamic>{
          'gk': 'broadcast_123',
          'cc': '',
        },
      ];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 34,
        'pairSep': ps,
        'itemSep': is_,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'cc',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Data tidak ditemukan'), findsOneWidget);
    });

    // W1 guard: a src:"doc" group whose `field` is absent/typo'd must NOT fall
    // through to the table branch (which would render the raw grant doc and let
    // a tap emit its Firestore __docId into the broadcast bcc).
    testWidgets('src:doc with `field` omitted -> empty list, no doc-id rows',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_nofieldcfg';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      mapTableContent[''] = [
        <String, dynamic>{
          '__docId': 'GRANTDOC123',
          'gk': 'broadcast_123',
          'cc': 'Alpha${ps}A1',
        },
      ];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 36,
        'pairSep': ps,
        'itemSep': is_,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            // no 'field' key -- misconfigured
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Data tidak ditemukan'), findsOneWidget);
      expect(find.text('GRANTDOC123'), findsNothing,
          reason: 'must not degrade into table rendering of the grant doc');
    });

    testWidgets('3 doc groups same table: all tabs render from one subscription',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_3tab';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      // One doc, three fields. All groups use code='' (empty table/vidtable),
      // so all share mapTableContent[''].
      mapTableContent[''] = [
        <String, dynamic>{
          'gk': 'broadcast_123',
          'cc': 'Alpha${ps}A1${is_}Beta${ps}B2',
          'site': 'Jakarta${ps}J1${is_}Bandung${ps}B1',
          'vid': 'Alice${ps}V1${is_}Bob${ps}V2${is_}Charlie${ps}V3',
        },
      ];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 40,
        'keyPosition': 41,
        'pairSep': ps,
        'itemSep': is_,
        'joinSep': '|',
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'cc',
          },
          {
            'key': 'site',
            'label': 'Site',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'site',
          },
          {
            'key': 'vid',
            'label': 'Orang',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'vid',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Tab 0 (Cost Center) active by default.
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      // Switch to tab 1 (Site).
      await tester.tap(find.text('Site'));
      await tester.pumpAndSettle();
      expect(find.text('Jakarta'), findsOneWidget);
      expect(find.text('Bandung'), findsOneWidget);

      // Switch to tab 2 (Orang).
      await tester.tap(find.text('Orang'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);

      // Select Charlie on Orang tab -> emit verifies id + key.
      await tester.tap(find.text('Charlie'));
      await tester.pumpAndSettle();
      expect(txfController[scrName]![40]!.finalData, 'V3');
      expect(txfController[scrName]![41]!.finalData, 'vid');

      // Multi-select Bob -> joinSep-joined ids.
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      // Order: Charlie was first, then Bob. Set iteration order = insertion.
      expect(txfController[scrName]![40]!.finalData, 'V3|V2');
    });

    testWidgets('mapTableContent empty (no docs at all) -> empty list',
        (WidgetTester tester) async {
      const String scrName = 'gp_doc_nodocs';
      GroupPicker.clearState(scrName);
      addTearDown(() {
        GroupPicker.clearState(scrName);
        mapTableContent.remove('');
      });

      // No docs in mapTableContent at all.
      mapTableContent[''] = <Map<String, dynamic>>[];

      final Map<String, dynamic> component = {
        'type': 'group_picker',
        'mode': 'multi',
        'selector': 'segmented',
        'valuePosition': 35,
        'pairSep': ps,
        'itemSep': is_,
        'groups': [
          {
            'key': 'cc',
            'label': 'Cost Center',
            'src': 'doc',
            'vidtable': '',
            'table': '',
            'search': 'gk\u{25FC}broadcast_123',
            'field': 'cc',
          },
        ],
      };

      await tester.pumpWidget(wrap(GroupPicker(
        component: component,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Data tidak ditemukan'), findsOneWidget);
    });
  });
}
