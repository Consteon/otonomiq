// test/checklist_dynamic_widget_test.dart
//
// Pump tests for CHECKLIST_DYNAMIC (per-field output, round 2).
//
// ★ HOW THIS RUNS WITH ZERO FIREBASE, and what that costs.
// The component carries `vidtable` + `table`. `vidtable` short-circuits
// resolveAppVid before getTableVid (which would read the `late` global
// appCodeController), and subscribeToMapCollection swallows the null-firestoreDb
// NoSuchMethodError in its OWN try/catch (table_repository.dart:2183) -- while
// `_code` is assigned BEFORE that call, so it survives as [docCode]. Seeding
// mapTableContent[docCode] therefore drives the REAL read path: search ->
// filterDriverHomeDocs -> sort -> titles -> slot block -> render.
//
// Tests that exercise that real path: w-01, w-02, w-03, w-06, w-07, w-09..w-18.
// w-04, w-05 and w-08 deliberately do NOT (w-08 omits `table` entirely, which is
// the whole point of the Obx zero-observable check) -- a green run there proves
// nothing about the data path and is not claimed to.
//
// WHAT A GREEN RUN STILL DOES NOT PROVE: the live Firestore listener itself, the
// close button's updateEventRow config, or that positions 12..17 are actually
// free on the live page. Those stay device / sheet work (§9.5, §8).
//
// No mocking package is used or added -- mockito/mocktail are not dependencies
// of this repo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/checklist_dynamic.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  const String scr = 'CleaningFormAkhir';
  const int pos = 12; // the live component's position
  const String docVid = '20342033315492';
  const String docCode = '$docVid/84214220504259/checklist_template';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // globalInit() does not run under flutter_test: register by hand what the
    // widget touches (mirrors digit_pad_widget_test / ocr_capture_widget_test).
    if (!Get.isRegistered<WidgetUpdateController>()) {
      Get.put(WidgetUpdateController());
    }
    if (!Get.isRegistered<GeneralGetXController>()) {
      Get.put(GeneralGetXController());
    }
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    // `late` global, assigned only in globalInit. Belt and braces: `vidtable`
    // short-circuits resolveAppVid before it is ever read.
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  setUp(() {
    txfController.clear();
    mapTableContent.clear();
    // Bare screenTx key written by the scanner's routeParams in production.
    // '' is equivalent to absent: resolveDriverCurlyTokens leaves the literal
    // `{template}` for an empty bare key, and filterByMultiClause is fail-closed
    // on any value still containing '{'.
    transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction(<String, dynamic>{
      'template': '',
    })));
  });

  final String d = separator[1]; // ◆

  /// The full 4-status option string.
  final String options4 = <String>[
    '✓', 'Selesai', 'Tandai Selesai',
    '✖', 'Tidak Tersedia', 'Barang tidak ada di area ini',
    '>', 'Dilewati', 'Kembali lagi nanti',
    '!', 'Masalah', 'Jelaskan dalam laporan',
  ].join(d);

  /// text slots: 0 empty-msg (blank -> Indonesian default), 1 completed prefix,
  /// 2..4 subtitles, 5 sheet header.
  final String text6 = <String>[
    '',
    'Selesai',
    'Tidak tersedia di area ini',
    'Dilewati - Kunjungi kembali nanti',
    'Masalah - jelaskan dalam laporan.',
    'Ubah Status',
  ].join(d);

  /// [useDefaults] omits `taskField` and `sortField` entirely, so the widget
  /// falls back to checklistDefaultTaskField / checklistDefaultSortField.
  Map<String, dynamic> component({
    String search = '',
    String sortField = 'ord',
    String sortDir = 'asc',
    String taskField = 'tsk',
    int? slots,
    bool withTable = true,
    bool useDefaults = false,
    String? text,
  }) {
    final Map<String, dynamic> c = <String, dynamic>{
      'type': 'CHECKLIST_DYNAMIC',
      'position': pos,
      'currentValue': '',
      'search': search,
      'sortDir': sortDir,
      'pendingLabel': 'belum',
      'category': '',
      'borderRadius': 10,
      'margin': '0,5,0,0',
      'text': text ?? text6,
      'options': options4,
    };
    if (!useDefaults) {
      c['sortField'] = sortField;
      c['taskField'] = taskField;
    }
    if (slots != null) c['slots'] = slots;
    if (withTable) {
      c['vidtable'] = docVid;
      c['table'] = '84214220504259//checklist_template';
    }
    return c;
  }

  /// The four documents that actually exist in
  /// MobileTable/20342033315492/tables/84214220504259/checklist_template on
  /// 2026-08-21, in Firestore's default document-id-ascending order.
  List<Map<String, dynamic>> liveDocs() => <Map<String, dynamic>>[
        <String, dynamic>{
          '__docId': '4tmKu8rG1Ie6O9vEVjeV',
          'ord': 1,
          'tmp': 'Pantry',
          'tsk': 'Bersihkan sink & keran',
        },
        <String, dynamic>{
          '__docId': 'FaHaUC4AjsIdzmGJGJF2',
          'order': 2,
          'tmp': 'Restroom',
          'tsk': 'Isi ulang sabun & tisu',
        },
        <String, dynamic>{
          '__docId': 'bzJM0qsvJ7DucJDgN9hg',
          'order': 3,
          'tmp': 'Restroom',
          'tsk': 'Sapu & pel lantai',
        },
        <String, dynamic>{
          '__docId': 'f5zvzeYd2LfYmzgRRUEt',
          'order': 3,
          'tmp': 'Restroom',
          'tsk': 'Semprot pengharum',
        },
      ];

  void seedDocs(List<Map<String, dynamic>> docs) {
    mapTableContent[docCode] = docs;
  }

  /// Seed ONE slot as the dispatch chain / a previous build would leave it.
  void seedSlot(int p, String finalData) {
    txfControllerCheck(scr, p);
    txfController[scr]![p]!.initialValue = '';
    txfController[scr]![p]!.finalData = finalData;
  }

  /// Slot value, or null when the slot was never created.
  String? slotAt(int p) => txfController[scr]?[p]?.finalData;

  Widget subject(Map<String, dynamic> c) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChecklistDynamic(
              component: c,
              scrName: scr,
              lPad: 0,
              tPad: 0,
              rPad: 0,
              bPad: 0,
            ),
          ),
        ),
      );

  // ── w-01 : render + order + fan-out ──────────────────────────────────────

  // ★ THE HEADLINE CHANGE. One task per slot, in render-index order (D2).
  // RED if: the widget goes back to joining into one slot, or the sort
  // comparator stops coercing. `ord` is deliberately mixed String/int, as a
  // sheet writes it.
  testWidgets('w-01 fans N tasks out to N consecutive slots, ord-ordered',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'T10', 'ord': '10', 'tmp': 'Restroom'},
      <String, dynamic>{'tsk': 'T2', 'ord': 2, 'tmp': 'Restroom'},
      <String, dynamic>{'tsk': 'T9', 'ord': '9', 'tmp': 'Restroom'},
    ]);
    await t.pumpWidget(subject(component()));
    await t.pump();

    expect(find.text('T2'), findsOneWidget);
    expect(find.text('T9'), findsOneWidget);
    expect(find.text('T10'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chkEmpty')), findsNothing);
    // Visual order.
    expect(t.getTopLeft(find.text('T2')).dy,
        lessThan(t.getTopLeft(find.text('T9')).dy));
    expect(t.getTopLeft(find.text('T9')).dy,
        lessThan(t.getTopLeft(find.text('T10')).dy));
    // The values the server receives, ONE PER SLOT.
    expect(slotAt(12), 'T2 | belum');
    expect(slotAt(13), 'T9 | belum');
    expect(slotAt(14), 'T10 | belum');
    // Nothing beyond the block exists.
    expect(slotAt(15), isNull);
  });

  // ── w-02 .. w-03 : the {template} filter ─────────────────────────────────

  // RED if: `search` stops being applied, or is applied to the wrong field.
  testWidgets('w-02 {template} resolved from a bare screenTx key scopes rows',
      (WidgetTester t) async {
    seedSlot(pos, '');
    transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction(<String, dynamic>{
      'template': 'Restroom',
    })));
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1, 'tmp': 'Restroom'},
      <String, dynamic>{'tsk': 'Lap meja', 'ord': 1, 'tmp': 'Pantry'},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2, 'tmp': 'Restroom'},
    ]);
    await t.pumpWidget(subject(component(search: 'tmp◼{template}')));
    await t.pump();

    expect(find.text('Sapu'), findsOneWidget);
    expect(find.text('Sikat'), findsOneWidget);
    expect(find.text('Lap meja'), findsNothing);
    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Sikat | belum');
    expect(slotAt(14), isNull);
  });

  // ★ THE SECURITY PROPERTY *AND* D8 TOGETHER. An unresolved {template} must
  // show zero rows AND must not blank a block that already holds the officer's
  // ticks.
  // RED if: filterByMultiClause's fail-closed contract is bypassed, or the D8
  // guard is moved below the write (M11).
  testWidgets('w-03 an unresolved {template} shows ZERO rows and writes NOTHING',
      (WidgetTester t) async {
    // A block left by an earlier, successful build.
    seedSlot(12, 'Sapu | Selesai');
    seedSlot(13, 'Sikat | belum');
    // setUp left `template` empty -> the literal `{template}` survives token
    // resolution -> filterByMultiClause returns [].
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1, 'tmp': 'Restroom'},
      <String, dynamic>{'tsk': 'Lap meja', 'ord': 1, 'tmp': 'Pantry'},
    ]);
    await t.pumpWidget(
        subject(component(search: 'tmp◼{template}', slots: 6)));
    await t.pump();

    expect(find.text('Sapu'), findsNothing);
    expect(find.text('Lap meja'), findsNothing);
    expect(find.byKey(const ValueKey<String>('chkEmpty')), findsOneWidget);
    expect(find.text('Belum ada task untuk kategori ini.'), findsOneWidget);
    // ★ UNTOUCHED. Not '', not '--'.
    expect(slotAt(12), 'Sapu | Selesai');
    expect(slotAt(13), 'Sikat | belum');
    expect(slotAt(14), isNull);
  });

  // ── w-04 .. w-05 : the empty message ─────────────────────────────────────

  // RED if: the blank-aware wrapper on text slot 0 is dropped (M10).
  testWidgets('w-04 a blank text slot 0 falls back to the Indonesian default',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(const <Map<String, dynamic>>[]);
    await t.pumpWidget(subject(component()));
    await t.pump();
    expect(find.text('Belum ada task untuk kategori ini.'), findsOneWidget);
  });

  testWidgets('w-05 an authored text slot 0 overrides the default',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(const <Map<String, dynamic>>[]);
    await t.pumpWidget(subject(component(
      text: <String>['Kategori belum di-setup.', 'Selesai'].join(d),
    )));
    await t.pump();
    expect(find.text('Kategori belum di-setup.'), findsOneWidget);
    expect(find.text('Belum ada task untuk kategori ini.'), findsNothing);
  });

  // ── w-06 .. w-07 : taps land in the RIGHT slot ───────────────────────────

  // ★ Address rows by KEY, never by text/icon: every row renders the same
  // Icons.more_horiz, and 'Selesai' is simultaneously text slot 1, an option
  // label and a badge label.
  testWidgets('w-06 the circle toggle writes into THAT task\'s own slot only',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
    ]);
    await t.pumpWidget(subject(component()));
    await t.pump();
    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Sikat | belum');

    await t.tap(find.byKey(const ValueKey<String>('chkToggle-1')));
    await t.pump();
    expect(slotAt(12), 'Sapu | belum'); // untouched
    expect(slotAt(13), 'Sikat | Selesai');

    await t.tap(find.byKey(const ValueKey<String>('chkToggle-1')));
    await t.pump();
    expect(slotAt(13), 'Sikat | belum');
  });

  testWidgets('w-07 the status sheet writes the picked option label',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
    ]);
    await t.pumpWidget(subject(component()));
    await t.pump();

    await t.tap(find.byKey(const ValueKey<String>('chkMore-0')));
    await t.pumpAndSettle();
    expect(find.text('Ubah Status'), findsOneWidget); // text slot 5
    await t.tap(find.byKey(const ValueKey<String>('chkOpt-skipped')));
    await t.pumpAndSettle();

    expect(slotAt(12), 'Sapu | Dilewati');
    expect(slotAt(13), 'Sikat | belum');
    // The status subtitle for `skipped` comes from text slot 3.
    expect(find.text('Dilewati - Kunjungi kembali nanti'), findsOneWidget);
  });

  // ── w-08 : the Obx zero-observable guard ─────────────────────────────────

  // ★ RED if: an `if (_code.isEmpty) return ...` guard is put ABOVE the
  // mapTableContent read in _docs. With no `table` key `_code` stays '', and the
  // missing-key read is the ONLY observable this build registers -- move it
  // below a guard and Obx throws "[Get] the improper use of a GetX has been
  // detected" on every build.
  testWidgets('w-08 a table-less component renders without a GetX zero-obs error',
      (WidgetTester t) async {
    seedSlot(pos, '');
    await t.pumpWidget(subject(component(withTable: false)));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('chkEmpty')), findsOneWidget);
  });

  // ── w-09 : the '--' birth sentinel ───────────────────────────────────────

  // ★ RED if: the unconditional _writeBlock call in _content is deleted or made
  // conditional (M12). A slot still holding '--' makes saveSend fall back to
  // controller.text (api.dart:4839).
  testWidgets("w-09 the '--' birth sentinel never survives a build",
      (WidgetTester t) async {
    txfControllerCheck(scr, pos); // births finalData == emptyString
    expect(txfController[scr]![pos]!.finalData, emptyString);
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
    ]);
    await t.pumpWidget(subject(component()));
    await t.pump();
    expect(slotAt(12), 'Sapu | belum');
  });

  // ── w-10 : ListView-recycling survival ───────────────────────────────────

  // ★ THE REGRESSION THIS DESIGN EXISTS FOR. AnyPage renders elements in a
  // ListView.builder with no keep-alive (page/any_page.dart:168), so a row
  // scrolled off screen is DISPOSED and remounts with a fresh State. Re-pumping
  // a brand new widget over the same scrName/position is that remount.
  // RED if: the parse phase is dropped (M13) -- the ticks come back all pending.
  testWidgets('w-10 a remount re-hydrates ticked statuses from the block',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
    ]);
    await t.pumpWidget(subject(component()));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('chkToggle-0')));
    await t.pump();
    expect(slotAt(12), 'Sapu | Selesai');

    // Unmount, then mount a fresh State over the same block.
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await t.pump();
    await t.pumpWidget(subject(component()));
    await t.pump();

    expect(slotAt(12), 'Sapu | Selesai');
    expect(slotAt(13), 'Sikat | belum');
    // The status badge proves the RENDER re-hydrated too, not just the slot.
    expect(find.text('Selesai'), findsWidgets);
  });

  // ── w-11 : template edited mid-life, task MOVES slot ─────────────────────

  // ★ THE REASON THE PARSE PHASE MUST READ THE WHOLE BLOCK BEFORE WRITING.
  // Deleting task #2 moves task #3 from slot 14 to slot 13; the status must
  // follow the TITLE, not the slot index.
  testWidgets('w-11 a deleted task shifts its successors and statuses follow',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
      <String, dynamic>{'tsk': 'Pel', 'ord': 3},
    ]);
    await t.pumpWidget(subject(component(slots: 3)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('chkToggle-2'))); // Pel
    await t.pump();
    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Sikat | belum');
    expect(slotAt(14), 'Pel | Selesai');

    // Admin deletes 'Sikat'. 'Pel' moves from slot 14 to slot 13.
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Pel', 'ord': 3},
    ]);
    await t.pump();

    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Pel | Selesai'); // status followed the TITLE
    expect(slotAt(14), ''); // tail blanked, slots == 3
    expect(find.text('Sikat'), findsNothing);
  });

  // ── w-12 : missing position ──────────────────────────────────────────────

  // A component with no position submits nothing. Render a visible marker, never
  // a silent blank -- a broken config must not survive a whole shift unnoticed.
  testWidgets('w-12 a component with no position renders an error marker',
      (WidgetTester t) async {
    final Map<String, dynamic> c = component()..remove('position');
    await t.pumpWidget(subject(c));
    await t.pump();
    expect(find.textContaining('--CHECKLIST_DYNAMIC--'), findsOneWidget);
  });

  // ── w-13 : N < slots, the tail is blanked ────────────────────────────────

  // ★ D3. RED if: the tail branch of checklistSlotValues is deleted (M5) -- the
  // tail slots are then never written and read back null.
  testWidgets('w-13 fewer tasks than slots: the tail is blanked every build',
      (WidgetTester t) async {
    // Stale values a shrunken template left behind.
    seedSlot(14, 'TaskLama | Selesai');
    seedSlot(15, 'TaskLama2 | Masalah');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
    ]);
    await t.pumpWidget(subject(component(slots: 4)));
    await t.pump();

    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Sikat | belum');
    expect(slotAt(14), ''); // blanked, NOT 'TaskLama | Selesai'
    expect(slotAt(15), '');
    expect(slotAt(16), isNull); // still outside the block
  });

  // ── w-14 : N > slots, warning + hard block boundary ──────────────────────

  // ★ D3. Three things at once: the warning is VISIBLE, nothing outside the
  // block is written, and an excess row cannot accept a tap that would vanish.
  // RED if: the block bound in checklistSlotValues is widened (M6), the warning
  // row is dropped (M16), or the Opacity/IgnorePointer wrapper is removed (M17).
  //
  // ★★ M17 needs the STRUCTURAL assertion at the bottom of this test, and the
  // slot assertions alone do NOT provide it. Measured 2026-08-21: with the
  // wrapper deleted the tap DOES reach _apply and sets statusByTitle['Pel'],
  // but checklistSlotValues never emits more than `block` entries, so slot 14
  // is still never created and slots 12/13 are rewritten to the same values --
  // every slot assertion holds and the mutant is observationally equivalent.
  // A behavioural assertion is not available here: the widget re-parses status
  // from the block on the next build, so the bad tap SNAPS BACK to pending
  // within the same pump -- being invisible is precisely the defect. Hence a
  // structural check on the wrapper that is the actual guard.
  testWidgets('w-14 more tasks than slots: warning, no out-of-block write, inert rows',
      (WidgetTester t) async {
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
      <String, dynamic>{'tsk': 'Pel', 'ord': 3},
    ]);
    await t.pumpWidget(subject(component(slots: 2)));
    await t.pump();

    // All three tasks are VISIBLE -- the officer must see what exists.
    expect(find.text('Sapu'), findsOneWidget);
    expect(find.text('Sikat'), findsOneWidget);
    expect(find.text('Pel'), findsOneWidget);
    // The warning names the loss.
    expect(find.byKey(const ValueKey<String>('chkOverflow')), findsOneWidget);
    expect(find.textContaining('1 task terakhir'), findsOneWidget);
    // ★ NOTHING outside the block. Slot 14 was never even created.
    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Sikat | belum');
    expect(slotAt(14), isNull);
    expect(txfController[scr]!.containsKey(14), isFalse);

    // ★ The excess row cannot be ticked -- IgnorePointer swallows the tap, so
    // nothing changes anywhere. warnIfMissed:false because missing IS the point.
    await t.tap(find.byKey(const ValueKey<String>('chkToggle-2')),
        warnIfMissed: false);
    await t.pump();
    expect(slotAt(12), 'Sapu | belum');
    expect(slotAt(13), 'Sikat | belum');
    expect(slotAt(14), isNull);

    // ★★ The excess row is STRUCTURALLY inert, not merely harmless downstream.
    // This is the only assertion in the suite that distinguishes M17; see the
    // note above for why the slot assertions cannot and a behavioural one
    // cannot either. Plan §5.4: a tappable excess row writes into
    // statusByTitle, is dropped by checklistSlotValues, and snaps back to
    // pending on the next build -- the silently vanishing tap that round 1
    // already had to fix once for blank `options` labels.
    // NOTE: byType(IgnorePointer) alone is NOT usable here -- the framework puts
    // three of its own IgnorePointers above every row (all ignoring:false), so
    // the type check finds 4 and passes even when the widget's wrapper is gone.
    // The discriminating property is ignoring == true.
    Finder blockingPointerAbove(String rowKey) => find.ancestor(
          of: find.byKey(ValueKey<String>(rowKey)),
          matching: find.byWidgetPredicate(
            (Widget w) => w is IgnorePointer && w.ignoring,
          ),
        );

    expect(blockingPointerAbove('chkRow-2'), findsOneWidget); // excess: inert
    // ...and the negative case, so wrapping EVERY row would not pass either.
    expect(blockingPointerAbove('chkRow-0'), findsNothing); // in-block: live
    expect(blockingPointerAbove('chkRow-1'), findsNothing);
  });

  // ── w-15 : D8, the destructive-remount regression ────────────────────────

  // ★★★ THE REASON D8 EXISTS. A remount that precedes the Firestore snapshot
  // renders ZERO titles. Under round 1 (one slot) an unconditional write was
  // harmless; under fan-out it would blank the officer's whole block -- and the
  // block IS the re-hydration source, so the ticks would be gone for good.
  // RED if: the `titles.isEmpty` early return is moved BELOW the write (M11).
  testWidgets('w-15 an empty task list leaves an already-written block UNTOUCHED',
      (WidgetTester t) async {
    seedSlot(12, 'Sapu | Selesai');
    seedSlot(13, 'Sikat | Dilewati');
    seedSlot(14, 'Pel | Selesai');
    seedSlot(15, '');
    seedSlot(16, '');
    seedSlot(17, '');
    seedDocs(const <Map<String, dynamic>>[]); // snapshot has not landed yet

    await t.pumpWidget(subject(component(slots: 6)));
    await t.pump();

    expect(find.byKey(const ValueKey<String>('chkEmpty')), findsOneWidget);
    expect(slotAt(12), 'Sapu | Selesai');
    expect(slotAt(13), 'Sikat | Dilewati');
    expect(slotAt(14), 'Pel | Selesai');
    expect(slotAt(15), '');
    expect(slotAt(16), '');
    expect(slotAt(17), '');

    // ...and when the snapshot DOES land, the ticks re-hydrate.
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Sapu', 'ord': 1},
      <String, dynamic>{'tsk': 'Sikat', 'ord': 2},
      <String, dynamic>{'tsk': 'Pel', 'ord': 3},
    ]);
    await t.pump();
    expect(slotAt(12), 'Sapu | Selesai');
    expect(slotAt(13), 'Sikat | Dilewati');
    expect(slotAt(14), 'Pel | Selesai');
    expect(slotAt(15), '');
  });

  // ── w-16 : D5/D9 defaults ────────────────────────────────────────────────

  // ★ A BLANK sheet cell selects the DEFAULT (SduiSpec.str), so a stale default
  // silently reads a field that does not exist and the checklist renders empty.
  // RED if: checklistDefaultTaskField reverts to 'task' or
  // checklistDefaultSortField reverts to '' (M14).
  testWidgets('w-16 with taskField/sortField omitted the widget reads tsk + ord',
      (WidgetTester t) async {
    seedSlot(pos, '');
    seedDocs(<Map<String, dynamic>>[
      <String, dynamic>{'tsk': 'Kedua', 'ord': 2},
      <String, dynamic>{'tsk': 'Pertama', 'ord': 1},
    ]);
    await t.pumpWidget(subject(component(useDefaults: true, slots: 2)));
    await t.pump();

    expect(find.text('Pertama'), findsOneWidget);
    expect(find.text('Kedua'), findsOneWidget);
    expect(slotAt(12), 'Pertama | belum'); // ord respected
    expect(slotAt(13), 'Kedua | belum');
  });

  // ── w-17 : the LIVE seed, exactly as it is today ─────────────────────────

  // ★ Production data, mid-normalisation: `ord` on one doc, `order` on three,
  // two Restroom docs tied at 3. Every doc must render and get its own slot.
  // This is D2's justification as an executable fact: under an ord-driven slot
  // mapping the two value-3 docs would collide on one slot.
  testWidgets('w-17 the live half-normalised seed renders and fans out',
      (WidgetTester t) async {
    transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction(<String, dynamic>{
      'template': 'Restroom',
    })));
    seedDocs(liveDocs());
    await t.pumpWidget(subject(component(
      search: 'tmp◼{template}',
      useDefaults: true,
      slots: 6,
    )));
    await t.pump();

    expect(find.text('Bersihkan sink & keran'), findsNothing); // Pantry
    // All three Restroom tasks render, none dropped for a missing `ord`.
    expect(slotAt(12), 'Isi ulang sabun & tisu | belum');
    expect(slotAt(13), 'Sapu & pel lantai | belum');
    expect(slotAt(14), 'Semprot pengharum | belum');
    expect(slotAt(15), '');
    expect(slotAt(16), '');
    expect(slotAt(17), '');
    expect(slotAt(18), isNull);
    expect(find.byKey(const ValueKey<String>('chkOverflow')), findsNothing);
  });

  // ── w-18 : a template with ZERO seeded docs ──────────────────────────────

  // ★ Work Area / Public Area / Outdoor have NO docs in the live seed today, so
  // scanning a location mapped to one of them takes exactly this path. The empty
  // state renders and D8's zero-write guard is what fires.
  testWidgets('w-18 a template with no docs shows the empty state, writes nothing',
      (WidgetTester t) async {
    seedSlot(12, 'PRESEEDED');
    transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction(<String, dynamic>{
      'template': 'Outdoor',
    })));
    seedDocs(liveDocs());
    await t.pumpWidget(subject(component(
      search: 'tmp◼{template}',
      useDefaults: true,
      slots: 6,
    )));
    await t.pump();

    expect(find.byKey(const ValueKey<String>('chkEmpty')), findsOneWidget);
    expect(find.text('Belum ada task untuk kategori ini.'), findsOneWidget);
    expect(slotAt(12), 'PRESEEDED'); // untouched
    expect(slotAt(13), isNull);
  });
}
