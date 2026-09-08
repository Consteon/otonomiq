// test/digit_pad_widget_test.dart
//
// Pump tests for DIGIT_PAD.
//
// The component in these tests carries NO `table` key on purpose:
// parseTablePath('') yields an empty docId, so _subscribe returns before
// resolveAppVid and subscribeToMapCollection is never reached. That is what
// keeps Firebase uninitialised.
//
// It does NOT make the verdict untestable, and an earlier version of this
// header wrongly implied it did — which is how the submit gate ended up with no
// test that disabled anything. With no `table` key `_code` keeps its init value
// '', and _docs() reads mapTableContent[''] — a plain global RxMap needing no
// Firebase. Seeding it drives comparator -> verdict -> banner -> submit gate
// end to end. The gate tests below do exactly that.
//
// ★ THERE IS NO OCR IN THIS WIDGET ANY MORE. digit-pad-deltamax-serial
// (2026-09-04) deleted the ML Kit path, the async seam and the static verdict
// memo: the serial check is a synchronous string compare against a form slot.
// So there is no `digitPadOcrRead` seam to install, no call counter, and no
// memo to clear between tests — only DigitPad.clearSheetRaised remains.
//
// `photoPosition` and `ocrPattern` are still present in every component() below
// on purpose: spec §6 leaves both columns in the shared sheet template, and
// every test in this file therefore doubles as proof that they are inert.
//
// ★ WHAT A GREEN RUN HERE STILL DOES NOT PROVE: the real Firestore
// subscription (subscribeToMapCollection), `search` resolution through
// filterDriverHomeDocs (no component here sets `search`, so that path is never
// entered), and the real `meter` doc's shape and field types — which are
// unratified anyway. Those stay device work (§7.3 manual flow).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/digit_pad.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  const String scr = 'MeterRead';
  const int pos = 7;
  const int digitsSlot = 9;
  const int saveSendSlot = 22;
  // mapTableContent key built by _subscribe for [tableComponent]:
  // '<appVid>/<tableDocId>/<subColl>'.
  const String docVid = '4242';
  const String docCode = '$docVid/meter/content';
  const int serialSlot = 16;
  /// As stamped on the meter and recorded on the doc.
  const String serialA = 'B21-4471902';
  const String seg6 =
      'Nomor seri di foto tidak cocok dengan yang tercatat ({serial}). '
      'Yakin ini meteran unit ini?';
  const String seg6Resolved =
      'Nomor seri di foto tidak cocok dengan yang tercatat (B21-4471902). '
      'Yakin ini meteran unit ini?';
  const String seg15 =
      'Pemakaian {delta} m³ — melewati batas {deltaMax} m³. Cek lagi angkanya.';
  const String seg16 = 'Nomor serinya belum difoto — foto dulu nomor serinya '
      'sebelum simpan, biar yakin ini meteran unit yang benar.';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // globalInit() does not run under flutter_test: register what the widget
    // touches by hand (mirrors ocr_capture_widget_test / task_create_submit_test).
    if (!Get.isRegistered<WidgetUpdateController>()) {
      Get.put(WidgetUpdateController());
    }
    // ocrWriteToPosition (the output-slot writer this widget reuses) reads
    // GeneralGetXController.to. Mirrors ocr_capture_widget_test's setUpAll.
    if (!Get.isRegistered<GeneralGetXController>()) {
      Get.put(GeneralGetXController());
    }
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    // `late` global, assigned only in globalInit. Belt and braces: the table-less
    // component below already short-circuits before resolveAppVid reads it.
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  setUp(() {
    txfController.clear();
    screenUIComponent = <String, dynamic>{};
    // _code is '' for a table-less component, so every test shares the
    // mapTableContent[''] slot. Without this a seeded comparator would leak
    // into the tests that assert "no verdict".
    mapTableContent.clear();
    // The sheet-raise latch is a static per-screen map; without this a test
    // that raised the sheet for '9999' would silently suppress the raise in the
    // next test that types the same value.
    DigitPad.clearSheetRaised(scr);
  });

  /// The `meter` doc's serial field, alongside pv/avg.
  void seedMeterDocWithSerial({num pv = 1000, num avg = 30, String msn = ''}) {
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{'pv': pv, 'avg': avg, 'msn': msn},
    ];
  }

  /// Write the serial slot exactly as its two real writers do — BOTH halves.
  ///
  /// ocrWriteToPosition (OCR_CAPTURE `ocrTargets:"16"`) and otq_txf_2's
  /// onChanged (a human edit) each set finalData and controller.text.
  /// `.controller.text` LAST here, and that is load-bearing: assigning it is
  /// what notifies the pad's listener, which is the whole reactivity mechanism.
  void writeSerialSlot(String v) {
    txfControllerCheck(scr, serialSlot);
    txfController[scr]![serialSlot]!.finalData = v;
    txfController[scr]![serialSlot]!.controller.text = v;
  }

  /// A `meter` doc with no `avg` at all — the shape of EVERY point with fewer
  /// than two readings, and the hole `deltaMax` exists to close. The one live
  /// doc in Firestore has exactly this shape.
  void seedMeterDocNoAvg({num pv = 1000, dynamic dmx}) {
    // [dmx] = the PER-POINT ceiling in m³ (meter-block-alias-dmx §3).
    // `dynamic`, mirroring `component()`'s `dynamic deltaMax`, because
    // Firestore flips numeric fields between num and String per tenant. OMITTED
    // when null, so "the doc has no dmx" stays distinguishable from "the doc
    // has dmx: 0" — those are two different tests below.
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{'pv': pv, if (dmx != null) 'dmx': dmx},
    ];
  }

  /// A dgm:2 (Lodge) point: 4 black + 2 red, so 10^red is 100 and every raw
  /// stand is a hundredth of its m³ value.
  /// [avg] is OMITTED unless asked for: the one live `meter` doc has no `avg`
  /// field, which is the shape `deltaMax` exists to cover.
  void seedLodgeDoc({num pv = 12600, num? avg, dynamic dmx}) {
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{
        'pv': pv,
        'dgh': 4,
        'dgm': 2,
        if (avg != null) 'avg': avg,
        // Same omit-when-null rule as seedMeterDocNoAvg. This is the only
        // seeder whose pow10 is not 1, so it is the only one that can see the
        // m³ basis of the dmx comparison.
        if (dmx != null) 'dmx': dmx,
      },
    ];
  }

  /// The `meter` doc the verdict compares against, reachable with zero Firebase:
  /// a table-less component leaves _code == '', and _docs() reads
  /// mapTableContent[_code].
  void seedMeterDoc({num pv = 1000, num avg = 30}) {
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{'pv': pv, 'avg': avg},
    ];
  }

  /// The digit-count source slot, plus the DIGIT_PAD slot itself.
  ///
  /// ★ The SERIAL slot is minted here too, empty, because that is what the live
  /// page does: buildPage (ui_component.dart) calls buildDisplayComponent — and
  /// therefore txfControllerCheck — for EVERY component before Flutter mounts
  /// any of them, so slot 16's InputController exists before the pad's first
  /// build even though the TXF sits after the pad in `children`. Without it
  /// _ensureSerialWatch finds nothing to attach to, and a test that then writes
  /// the slot would be measuring the harness rather than the widget.
  void seedSlots({String digits = '5'}) {
    txfControllerCheck(scr, digitsSlot);
    txfController[scr]![digitsSlot]!.finalData = digits;
    txfControllerCheck(scr, pos);
    txfController[scr]![pos]!.initialValue = '';
    txfController[scr]![pos]!.finalData = '';
    txfControllerCheck(scr, serialSlot);
  }

  /// A page whose only RBT child is a savesend button at [saveSendSlot].
  void seedPage() {
    screenUIComponent[scr] = <String, dynamic>{
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'rbt',
          'children': <dynamic>[
            <String, dynamic>{'position': 21, 'action': 'route'},
            <String, dynamic>{'position': saveSendSlot, 'action': 'savesend'},
          ],
        },
      ],
    };
    txfControllerCheck(scr, 21);
    txfController[scr]![21]!.initialIsEnabled = true;
    txfController[scr]![21]!.isEnabled = true;
    txfControllerCheck(scr, saveSendSlot);
    txfController[scr]![saveSendSlot]!.initialIsEnabled = true;
    txfController[scr]![saveSendSlot]!.isEnabled = true;
  }

  final String d = separator[1]; // ◆

  Map<String, dynamic> component({
    String digitsPosition = '9',
    String digitsRedPosition = '',
    String digitsSourcePosition = '',
    String digitsField = '',
    String digitsRedField = '',
    String digitsMode = 'auto',
    String digitsOptions = '',
    String digitsRedOptions = '',
    String blockOnBackward = 'FALSE',
    String isEnabled = 'TRUE',
    String serialSourcePosition = '$serialSlot',
    String serialField = '',
    String blockOnSerialMismatch = 'FALSE',
    String serialText = seg6,
    String missingSerialText = seg16,
    // dynamic: the live sheet sends `"deltaMax":100` as a JSON NUMBER, and a
    // test must be able to pass that shape, not only a string.
    dynamic deltaMax = '',
  }) =>
      <String, dynamic>{
        'type': 'DIGIT_PAD',
        'position': pos,
        // NO 'table' key: that is what keeps Firebase out of the tree.
        'digitsField': digitsField,
        'digitsRedField': digitsRedField,
        'digitsPosition': digitsPosition,
        'digitsRedPosition': digitsRedPosition,
        'digitsSourcePosition': digitsSourcePosition,
        'digitsMode': digitsMode,
        'digitsOptions': digitsOptions,
        'digitsRedOptions': digitsRedOptions,
        'compareField': 'pv',
        'avgField': 'avg',
        'spikeMultiplier': 4,
        'deltaMax': deltaMax,
        'blockOnBackward': blockOnBackward,
        'serialSourcePosition': serialSourcePosition,
        'serialField': serialField,
        'blockOnSerialMismatch': blockOnSerialMismatch,
        // ★ RETIRED 2026-09-04 and read by NOBODY. Unconditional (not behind a
        // parameter) because spec §6 leaves both columns in the shared sheet
        // template: every test in this file therefore exercises their
        // inertness, and one named test below says so out loud.
        'photoPosition': '3',
        'ocrPattern': r'\d{4,9}',
        'currentValue': '',
        'isEnabled': isEnabled,
        'text': <String>[
          /* 0 */ 'Angka di meter sekarang',
          /* 1 */ 'Salin kotak hitam saja',
          /* 2 */ 'Masuk akal — selisih {delta} m³ dari {prev}',
          /* 3 */ 'Lonjakan jauh — {delta} m³',
          /* 4 */ 'Angka lebih kecil dari {prev}',
          /* 5 */ 'Perbaiki dulu',
          /* 6 */ serialText,
          /* 7 */ 'Kurang {n} angka',
          /* 8 */ 'Berapa kotak hitam?',
          /* 9 */ 'Berapa kotak merah?',
          /* 10 */ 'beda?',
          /* 11 */ 'Cocokkan dengan meternya',
          /* 12 */ 'Perbaiki angkanya',
          /* 13 */ 'Angkanya memang segitu',
          /* 14 */ 'Kalau kamu yakin, disimpan apa adanya',
          /* 15 */ seg15,
          /* 16 */ missingSerialText,
        ].join(d),
      };

  Map<String, dynamic> lodgeComponent({dynamic deltaMax = 100}) => component(
        digitsField: 'dgh',
        digitsRedField: 'dgm',
        digitsRedPosition: '13',
        deltaMax: deltaMax,
      );

  /// A component wired to a REAL doc source, still with zero Firebase.
  ///
  /// Measured, not assumed: `vidtable` short-circuits resolveAppVid before
  /// getTableVid, and subscribeToMapCollection swallows the null-`firestoreDb`
  /// NoSuchMethodError in its OWN try/catch (table_repository.dart:2183) — and
  /// `_code` is assigned BEFORE that call, so it survives as [docCode]. That is
  /// what lets these tests tell "no snapshot yet" apart from "no doc source at
  /// all"; every other test in this file pumps a table-less component, where
  /// `_code` is '' and the two states are indistinguishable.
  Map<String, dynamic> tableComponent({String digitsField = 'dg'}) =>
      Map<String, dynamic>.from(
          component(digitsPosition: '', digitsField: digitsField))
        ..['table'] = 'meter'
        ..['vidtable'] = docVid;

  Future<void> tapChip(WidgetTester t, String id) async {
    await t.tap(find.byKey(ValueKey<String>('digitPadOpt$id')));
    await t.pump();
  }

  Widget subject(Map<String, dynamic> c) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DigitPad(
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

  // ★ Address the numpad by KEY, never by text.
  //
  // A filled digit box and a numpad key are both
  // `Container > ... > Text('0')`, and _boxes is added to the Column BEFORE
  // _numpad — so `find.widgetWithText(Container, '0').first` resolves to the
  // BOX as soon as that digit is on screen. Typing 0,0,9,8,7 would then have the
  // second '0' tap box 0 (moving the cursor) instead of entering a digit, and
  // the buffer would end up '987__'. ValueKeys make the target unambiguous.
  Future<void> tapKey(WidgetTester t, String label) async {
    await t.tap(find.byKey(ValueKey<String>('digitPadKey-$label')));
    await t.pump();
  }

  /// The backspace key is icon-only — it has no Text at all, so it is
  /// unreachable by any text-based finder.
  Future<void> tapBack(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey<String>('digitPadKey-back')));
    await t.pump();
  }

  Future<void> tapBox(WidgetTester t, int i) async {
    await t.tap(find.byKey(ValueKey<String>('digitPadBox-$i')));
    await t.pump();
  }

  // RED if: the label stops coming from text[0], or the ◆-slot order shifts.
  testWidgets('renders title and hint from text slots 0 and 1',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    expect(find.text('Angka di meter sekarang'), findsOneWidget);
    expect(find.text('Salin kotak hitam saja'), findsOneWidget);
  });

  // ★ The structural guarantee for spec §11: no text-entry widget exists, so the
  // system keyboard CANNOT appear and there is no path to a comma/dot/minus.
  // RED if: anyone replaces the boxes with a TextField "for convenience".
  testWidgets('there is no text-entry widget anywhere in the tree',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('digits fill left to right; finalData stays empty until complete',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '1', '2']) {
      await tapKey(t, k);
    }
    expect(txfController[scr]![pos]!.controller.text, '012__');
    // Spec §5: a half-filled set of boxes is NOT a number.
    expect(txfController[scr]![pos]!.finalData, '');
    // text[7] with {n} resolved.
    expect(find.text('Kurang 2 angka'), findsOneWidget);
  });

  // RED if: the leading-zero strip in digitPadSubmitValue is removed.
  testWidgets('a complete buffer submits the leading-zero-stripped value',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '8', '7']) {
      await tapKey(t, k);
    }
    expect(txfController[scr]![pos]!.controller.text, '00987'); // display
    expect(txfController[scr]![pos]!.finalData, '987'); // storage
    expect(find.text('Kurang 0 angka'), findsNothing);
  });

  // Spec §11: "Ketik angka ke-6 -> tidak ada yang terjadi".
  testWidgets('a 6th digit changes nothing', (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '8', '7']) {
      await tapKey(t, k);
    }
    await tapKey(t, '3');
    expect(txfController[scr]![pos]!.controller.text, '00987');
    expect(txfController[scr]![pos]!.finalData, '987');
  });

  // ★ RED if: the unconditional `ic.finalData = submit;` line in _content is
  // removed. Without it a freshly created slot keeps the '--' birth value, and
  // saveSend's record composer falls back to controller.text — submitting the
  // raw hole-buffer as the meter reading.
  testWidgets("the '--' birth sentinel never survives a build",
      (WidgetTester t) async {
    txfControllerCheck(scr, digitsSlot);
    txfController[scr]![digitsSlot]!.finalData = '5';
    txfControllerCheck(scr, pos); // finalData == emptyString ('--')
    expect(txfController[scr]![pos]!.finalData, emptyString);
    await t.pumpWidget(subject(component()));
    await t.pump();
    expect(txfController[scr]![pos]!.finalData, '');
  });

  // Spec §7.2 / §12 — neither count source resolves and nothing is pickable.
  //
  // rev f: before this patch the branch returned `const SizedBox.shrink()` —
  // the officer saw a blank gap with no title, no boxes and NO ERROR, and a
  // broken config survived a whole trip unnoticed. This test used to be named
  // "...renders nothing and does not crash" and asserted only title-absent +
  // no-crash — both stay true whether the widget renders the rev-f marker OR
  // nothing at all, so the name and the assertions were blind to the exact
  // regression rev f exists to prevent (and would stay green if the whole
  // marker block were deleted again). Retargeted to pin what rev f adds.
  //
  // ★ RED if: the marker Text is deleted (reverts to SizedBox.shrink()); if
  // `${widget.component['type']}` is replaced by a fixed string (the type
  // prefix stops being real interpolation); or if `ic.finalData = '';` is
  // removed — the '--' birth sentinel would then survive this branch, and
  // saveSend's record composer falls back to controller.text (see "the '--'
  // birth sentinel never survives a build" above for why that matters).
  testWidgets(
      'no resolvable digit count and no picker renders the config-error '
      'marker, not nothing, and clears finalData',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos); // finalData born '--' (emptyString)
    expect(txfController[scr]![pos]!.finalData, emptyString);
    await t.pumpWidget(subject(component(digitsPosition: '', digitsField: '')));
    await t.pump();
    expect(find.text('Angka di meter sekarang'), findsNothing);
    expect(
      find.text('--DIGIT_PAD-- Error: no digit count '
          '(digitsField/doc empty, and no pickable '
          'digitsOptions + digitsPosition)'),
      findsOneWidget,
    );
    // '' , NOT '--': the sentinel must not survive into a submitted record.
    expect(txfController[scr]![pos]!.finalData, '');
    expect(noPumpException(), isTrue);
  });

  // Spec §7.6 / product #17 — a broken config (no resolvable count, no
  // picker) is a config bug, not a backward reading, and must never lock the
  // officer out of the page. Same early-return branch as the marker test
  // above, exercising `_scheduleGate(false)` specifically.
  //
  // ★ The savesend slot is seeded DISABLED before pumpWidget, deliberately —
  // seedPage() alone leaves it enabled, and a slot that starts and stays
  // enabled would pass this assertion even if `_scheduleGate(false)` were
  // deleted outright: with no call at all, nothing re-visits the slot, so an
  // already-true value just sits there and the mutation goes unnoticed (the
  // exact "asserts the initial state didn't change" trap). Pre-disabling
  // means a GREEN result only happens if the gate actively LIFTS it.
  //
  // ★ RED if: `_scheduleGate(false)` becomes `_scheduleGate(true)`, or the
  // call is removed.
  testWidgets('no resolvable digit count and no picker never gates the page',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    txfController[scr]![saveSendSlot]!.isEnabled = false;
    await t.pumpWidget(subject(component(digitsPosition: '', digitsField: '')));
    await t.pump();
    await t.pump(); // let the post-frame gate run
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    // Control: a non-savesend sibling (action:'route') was never touched.
    expect(txfController[scr]![21]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ── W1 (code-review r1): the rev-f marker must not fire during the
  // Firestore load window ────────────────────────────────────────────────────
  //
  // subscribeToMapCollection assigns mapTableContent[_code] ONLY inside its
  // snapshot listener (table_repository.dart:2180), so on the widget's PRIMARY
  // config shape — `table` + `digitsField`, count from the doc, no
  // `digitsOptions` fallback — every build before the first snapshot has
  // black == null and a hidden picker. Rev f as first written painted
  // "Error: no digit count" there: on every cold entry, and permanently while
  // offline, on config that is perfectly correct. Spec (5).md:186 calls a
  // not-yet-existing meter doc correct behaviour, not an error.
  //
  // The guard is a 3-term AND; the four tests below give each term its own
  // fixture, so no term can be deleted and stay green:
  //   !mapTableContent.containsKey(_code) -> T1 (absent) / T2 (present, empty)
  //   _code.isNotEmpty                    -> T4 (no doc source at all)
  //   _digitsField.isNotEmpty             -> T3 (table, but no field to read)

  // T1. ★ RED if the whole `if (… !mapTableContent.containsKey(_code))
  // return SizedBox.shrink()` block is deleted (the marker comes back on a
  // healthy config), or if either write above it is moved INSIDE the marker
  // path — finalData would keep its '--' birth sentinel and the gate would
  // never lift.
  testWidgets(
      'a configured doc that has not arrived yet renders nothing, not the '
      'error marker, and still clears finalData and lifts the gate',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos); // finalData born '--' (emptyString)
    seedPage();
    // Pre-DISABLED, deliberately: seedPage() leaves it enabled, and a slot that
    // starts and stays enabled would pass even if _scheduleGate(false) were
    // deleted. Green here means the gate actively LIFTED it.
    txfController[scr]![saveSendSlot]!.isEnabled = false;
    // No mapTableContent[docCode] seeded: the snapshot has not landed.
    expect(mapTableContent.containsKey(docCode), isFalse);

    await t.pumpWidget(subject(tableComponent()));
    await t.pump();
    await t.pump(); // let the post-frame gate run

    expect(
      find.textContaining('Error: no digit count'),
      findsNothing,
      reason: 'loading is not a broken cell (spec (5).md:186)',
    );
    // Nothing at all is painted — not the marker AND not a half-built pad.
    expect(find.text('Angka di meter sekarang'), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsNothing);
    // Both writes still happened on this exit.
    expect(txfController[scr]![pos]!.finalData, '');
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // T2. The discriminator itself. A snapshot that ARRIVED and carried no doc is
  // real broken config (or a real empty collection) and must stay loud.
  //
  // ★ RED if `!mapTableContent.containsKey(_code)` is weakened to
  // `docs.isEmpty` — the two states are identical under docs.isEmpty, so the
  // marker would be suppressed here too, forever. Also RED if the awaiting
  // guard is made unconditional.
  testWidgets(
      'a snapshot that landed with no doc still shows the error marker',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    // The key EXISTS with an empty list: subscribeToMapCollection has answered.
    mapTableContent[docCode] = <Map<String, dynamic>>[];

    await t.pumpWidget(subject(tableComponent()));
    await t.pump();

    expect(
      find.text('--DIGIT_PAD-- Error: no digit count '
          '(digitsField/doc empty, and no pickable '
          'digitsOptions + digitsPosition)'),
      findsOneWidget,
    );
    expect(txfController[scr]![pos]!.finalData, '');
    expect(noPumpException(), isTrue);
  });

  // T3. A config naming a `table` but no `digitsField` has nothing to read from
  // the doc, so no snapshot can ever resolve its count — waiting on one would
  // hide the bug until the doc landed, and forever offline.
  //
  // ★ RED if `_digitsField.isNotEmpty` is dropped from the guard.
  testWidgets(
      'a table with no digitsField shows the marker immediately, without '
      'waiting for a snapshot', (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    expect(mapTableContent.containsKey(docCode), isFalse);

    await t.pumpWidget(subject(tableComponent(digitsField: '')));
    await t.pump();

    expect(find.textContaining('Error: no digit count'), findsOneWidget);
    expect(txfController[scr]![pos]!.finalData, '');
    expect(noPumpException(), isTrue);
  });

  // T4. A `digitsField` with no `table` never subscribes, so its key never
  // appears in mapTableContent — without the `_code.isNotEmpty` term that reads
  // as "still loading" and the pad stays blank for the whole trip, which is the
  // exact silent-config-bug regression rev f exists to prevent.
  //
  // ★ RED if `_code.isNotEmpty` is dropped from the guard.
  testWidgets(
      'a digitsField with no table shows the marker, never a loading blank',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);

    // Table-less: _code stays '', and mapTableContent.containsKey('') is false.
    await t.pumpWidget(
        subject(component(digitsPosition: '', digitsField: 'dg')));
    await t.pump();

    expect(find.textContaining('Error: no digit count'), findsOneWidget);
    expect(txfController[scr]![pos]!.finalData, '');
    expect(noPumpException(), isTrue);
  });

  // ★ REPLACES rev b's "re-fits from the right" test, which asserted the exact
  // OPPOSITE of what spec rev d §2.2 rule 4 now requires ("Ganti pilihan =
  // kosongkan isian ... bukan dipotong dari kanan"). The scenario it drove — a
  // sibling widget writing digitsPosition — is also forbidden config now: the
  // three slots are widget-OWNED outputs.
  //
  // RED if: _pickBlack stops calling _clearBuffer, or clears by truncation.
  testWidgets('changing the picked count EMPTIES the buffer, never truncates',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component(
      digitsMode: 'editable',
      digitsOptions: '3◆5',
    )));
    await t.pump();
    for (final String k in <String>['1', '2', '3', '4', '5']) {
      await tapKey(t, k);
    }
    expect(txfController[scr]![pos]!.finalData, '12345');

    await t.tap(find.byKey(const ValueKey<String>('digitPadPickerLink')));
    await t.pump();
    await tapChip(t, 'Black-3');
    await t.pump();

    // ★ '' , NOT a hole string. _content deliberately never writes the
    // normalised buffer back to controller.text (assigning .text notifies
    // listeners, which mid-frame is a setState-during-build) — only _apply does,
    // on a tap. Every rev-b assertion that reads a hole string ('012__',
    // '123__') follows a tapKey for exactly that reason; there is no tap here.
    //
    // Truncation would have left '12345' sitting in controller.text and '123'
    // in finalData. §2.2 rule 4: a truncated number still looks like a valid
    // number, which is the failure being prevented.
    expect(txfController[scr]![pos]!.controller.text, '');
    expect(txfController[scr]![pos]!.finalData, '');
    expect(txfController[scr]![digitsSlot]!.finalData, '3');
    // The RENDER did follow the pick: exactly 3 boxes, so the empty buffer is a
    // cleared pad and not a pad that stopped drawing.
    expect(find.byKey(const ValueKey<String>('digitPadBox-2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-3')), findsNothing);
  });

  // Spec §7.6 / product #17 — with no comparator there is no verdict, so the
  // savesend button must stay ALIVE even with blockOnBackward TRUE.
  testWidgets('no verdict means no gate, even when blockOnBackward is TRUE',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '8', '7']) {
      await tapKey(t, k);
    }
    await t.pump(); // let the post-frame gate run
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(txfController[scr]![21]!.isEnabled, isTrue);
  });

  // RED if: digitPadPressBackspace stops clearing the box BEFORE the cursor
  // (e.g. clears the box AT the cursor instead). Real branching logic, and the
  // only key with no Text — it is reachable at all only because of its ValueKey.
  testWidgets('backspace clears the last digit and walks back',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['1', '2', '3']) {
      await tapKey(t, k);
    }
    expect(txfController[scr]![pos]!.controller.text, '123__');

    await tapBack(t);
    expect(txfController[scr]![pos]!.controller.text, '12___');
    await tapBack(t);
    expect(txfController[scr]![pos]!.controller.text, '1____');

    // Re-typing after a backspace resumes at the cleared box, not at the end.
    await tapKey(t, '9');
    expect(txfController[scr]![pos]!.controller.text, '19___');
  });

  // RED if: tapping a box stops moving the cursor. Guards the overwrite path —
  // and proves the box ValueKeys address boxes, not keys.
  testWidgets('tapping a box moves the cursor there and typing overwrites',
      (WidgetTester t) async {
    seedSlots();
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['1', '2', '3', '4', '5']) {
      await tapKey(t, k);
    }
    expect(txfController[scr]![pos]!.finalData, '12345');

    await tapBox(t, 1);
    await tapKey(t, '9');
    expect(txfController[scr]![pos]!.controller.text, '19345');
    expect(txfController[scr]![pos]!.finalData, '19345');
  });

  testWidgets('isEnabled FALSE makes every key inert', (WidgetTester t) async {
    seedSlots();
    // ★ BEFORE pumpWidget, not after. txfControllerCheck births the slot with
    // isEnabled = true (input_controller.dart named default), and writing the
    // flag after the first build marks NOTHING dirty — GetBuilder rebuilds only
    // on WidgetUpdateController.update(), the inner Obx only on an observable
    // change, so a bare t.pump() repaints neither and the already-painted tree
    // keeps its live onTap. _content reads ic.isEnabled on every build, so a
    // pre-seeded false is picked up on the FIRST paint.
    // (buildDisplayComponent normally seeds this from component['isEnabled'];
    // the pump bypasses that block entirely.)
    txfController[scr]![pos]!.isEnabled = false;
    await t.pumpWidget(subject(component(isEnabled: 'FALSE')));
    await t.pump();
    await tapKey(t, '7');
    expect(txfController[scr]![pos]!.controller.text, isNot(contains('7')));
    expect(txfController[scr]![pos]!.finalData, '');
  });

  // ── the submit gate, driven end to end (spec §7.6, product #21) ───────────
  //
  // These are the only tests that ever DISABLE anything. The earlier gate test
  // above asserts isEnabled stays true on seeds that were already true, so it
  // would pass against an empty _applyGate; these cannot.

  // ★ RED if: _applyGate stops writing ic.isEnabled = false on a block.
  // This is the ONLY blocking path in the whole system.
  testWidgets('a backward reading with blockOnBackward TRUE disables savesend',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    // 900 < pv 1000 -> backward.
    for (final String k in <String>['0', '0', '9', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pump(); // let the post-frame gate run

    expect(txfController[scr]![pos]!.finalData, '900');
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    // A non-savesend sibling (action:'route') must never be touched.
    expect(txfController[scr]![21]!.isEnabled, isTrue);
    // text[4] verdict banner and text[5] blocked footer, tokens resolved.
    //
    // ★ TWO of each since rev e (§4c): a backward verdict raises the bottom
    // sheet, which renders the SAME verdict copy and the SAME blocked footer as
    // the card. The count alone would be a weaker assertion than rev b's — it
    // does not say WHERE the second copy is, so a regression that painted the
    // banner twice inside the card would still pass. The sheet assertion below
    // is what pins it: one copy is the card's compact row, the other is the
    // sheet. The compact row is not redundant — §4c makes it what SURVIVES the
    // sheet being dismissed, which is why both must exist at once.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.text('Angka lebih kecil dari 1000'), findsNWidgets(2));
    expect(find.text('Perbaiki dulu'), findsNWidgets(2));
  });

  // ★ RED if: the re-enable branch stops restoring initialIsEnabled, or the gate
  // latches once blocked (the W1 class of bug — a memo on the applied state).
  testWidgets('correcting the reading restores savesend to initialIsEnabled',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pump();
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);

    // ★ rev e: the backward verdict raised the bottom sheet, and its modal
    // barrier absorbs every pointer event aimed at the pad underneath — the box
    // tap below would silently no-op (the hit test lands on RenderAbsorbPointer)
    // and the correction would never happen. Dismiss through the BARRIER, not
    // through either sheet button: segment 12 ("Perbaiki angkanya") clears the
    // buffer this test needs to edit, and segment 13 is deliberately absent
    // here because blockOnBackward:"TRUE" + backward engages the gate (§4c
    // rule 5). showModalBottomSheet is isDismissible by default.
    //
    // This is a coverage GAIN, not a workaround: the test now walks acceptance
    // §11's "Perbaiki angka → tombol hidup lagi" end to end — dismiss the
    // sheet, correct the reading, watch the gate lift.
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    // Correct 00900 -> 01100. 1100 > pv, and delta 100 <= avg 30 * 4 = 120,
    // so the verdict is sane rather than a spike.
    await tapBox(t, 1);
    await tapKey(t, '1');
    await tapKey(t, '1');
    await t.pump();

    expect(txfController[scr]![pos]!.finalData, '1100');
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(txfController[scr]![21]!.isEnabled, isTrue);
    expect(find.text('Perbaiki dulu'), findsNothing);
    // ★ RED if: the sane branch renders any segment other than text(2), or
    // resolves {delta}/{prev} wrongly. r3 W-2: spike and backward were pinned
    // to their segments by literals, sane was not — swapping text(2) for
    // text(3) left all 60 tests green.
    expect(find.text('Masuk akal — selisih 100 m³ dari 1000'), findsOneWidget);
  });

  // ★ RED if: digitPadShouldBlock is widened to block on any non-sane verdict.
  // The pure function covers the rule; this covers the WIRING from verdict to
  // gate. Spec §10: leaks are real and must be reported, never blocked.
  testWidgets('a spike warns but never disables savesend',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    // 9999 - 1000 = 8999 > 30 * 4 -> spike.
    for (final String k in <String>['0', '9', '9', '9', '9']) {
      await tapKey(t, k);
    }
    await t.pump();

    expect(txfController[scr]![pos]!.finalData, '9999');
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    // text[3] spike banner with {delta} resolved.
    //
    // ★ TWO since rev e (§4c): a spike raises the bottom sheet, which renders
    // the same verdict copy as the card's compact row. The sheet assertion is
    // what makes the count meaningful — without it, a regression that painted
    // the banner twice inside the card would also read 2. The compact row stays
    // by design: §4c makes it what survives the sheet being dismissed.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.text('Lonjakan jauh — 8999 m³'), findsNWidgets(2));
    // Still absent, and that is the point of this test: a spike NEVER blocks,
    // so verdictBlock is false and neither the card footer nor the sheet's
    // blocked-foot renders. If this ever finds a widget, it is a real bug.
    expect(find.text('Perbaiki dulu'), findsNothing);
  });

  // ★ RED if: _scheduleGate regains a memo of the state it already applied
  // (e.g. `if (_gateApplied == block) return;`).
  //
  // isEnabled has several writers. buildDisplayComponent's `rbt` else-branch
  // rewrites every positioned RBT child's isEnabled straight from config, with
  // no isFieldUntouched-style guard, and constructAllPageElements runs it for
  // every screen on any server UI push. A form page is not repainted by
  // rePaintScreen (home-only), so DigitPadState survives that reset. A widget
  // that remembered "I already blocked" would never re-assert and the backward
  // reading would submit. The external write below is that reset.
  testWidgets('the gate re-asserts after an external writer re-enables savesend',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pump();
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);

    // Simulate the server UI push re-seeding the flag from config, exactly as
    // build_display_component's rbt else-branch does.
    txfController[scr]![saveSendSlot]!.isEnabled = true;

    // Any repaint of the pad must re-assert the gate. This is the REAL channel:
    // clearData's tail calls WidgetUpdateController.update(...) and the pad's
    // GetBuilder subscribes to exactly this id. A pointer event would be
    // absorbed by the verdict sheet's modal barrier, and tapping the barrier
    // would test the sheet rather than the gate.
    //
    // The verdict is unchanged (still backward), which is precisely the case a
    // memo on the applied state would swallow — see mutation row 20.
    Get.find<WidgetUpdateController>().update(<String>['$scr-$pos']);
    await t.pump();
    await t.pump(); // post-frame gate

    expect(txfController[scr]![pos]!.finalData, '900'); // verdict unchanged
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
  });

  // Product #17 / spec §7.5: a backward reading with the switch OFF is stored
  // and flagged, never blocked. The officer always wins.
  testWidgets('a backward reading with blockOnBackward FALSE still submits',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'FALSE')));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pump();

    expect(txfController[scr]![pos]!.finalData, '900');
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    // The banner still warns; only the gate is off.
    //
    // ★ TWO since rev e (§4c): the sheet rises for a backward verdict whatever
    // blockOnBackward says — the switch governs the SUBMIT GATE, not the sheet.
    // The sheet assertion below is what pins where the second copy lives; a
    // bare count of 2 would also pass if the card painted the banner twice.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.text('Angka lebih kecil dari 1000'), findsNWidgets(2));
    // Still absent: blockOnBackward is FALSE, so verdictBlock is false and
    // neither the card footer nor the sheet's blocked-foot renders. Segment 13
    // IS offered here, which is the officer-always-wins path. A hit on this
    // line would be a real bug, not a count to adjust.
    expect(find.text('Perbaiki dulu'), findsNothing);
  });

  // ── rev c: the red group (spec §2.1) ──────────────────────────────────────

  /// A `meter` doc carrying digit config, reachable with zero Firebase.
  void seedMeterConfig({num pv = 1000, num avg = 30, int dgh = 4, int dgm = 1}) {
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{'pv': pv, 'avg': avg, 'dgh': dgh, 'dgm': dgm},
    ];
  }

  // ★ RED if: the comma is dropped, the red group is not rendered, or
  // digitPadSubmitValue is "helpfully" divided by 10^red.
  // Spec §11: dgh:4 + dgm:1 -> 4 dark + comma + 1 red; typing 00115 submits 115.
  testWidgets('4 black + 1 red renders a comma and submits the raw integer',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig();
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
    )));
    await t.pump();

    expect(find.byKey(const ValueKey<String>('digitPadBox-4')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-5')), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadComma')), findsOneWidget);

    for (final String k in <String>['0', '0', '1', '1', '5']) {
      await tapKey(t, k);
    }
    expect(txfController[scr]![pos]!.controller.text, '00115');
    // The WHOLE integer, raw. The division to 11,5 m³ is display only (§2.1).
    expect(txfController[scr]![pos]!.finalData, '115');
  });

  // RED if: hasComma stops keying on red > 0. A comma with nothing after it
  // invents an m³ boundary the meter face does not have.
  testWidgets('dgm 0 renders no comma and no red box', (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig(dgh: 5, dgm: 0);
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
    )));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('digitPadComma')), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadBox-4')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-5')), findsNothing);
  });

  // ── rev d: the picker (spec §2.2) ─────────────────────────────────────────

  // Spec §11: digitsMode auto + config -> no picker, no link.
  testWidgets('auto mode with config shows neither picker nor link',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig(dgh: 5, dgm: 0);
    await t.pumpWidget(subject(component(
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsMode: 'auto',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('digitPadPickerLink')),
        findsNothing);
    expect(find.text('Berapa kotak hitam?'), findsNothing);
  });

  // Spec §11: digitsMode editable + config -> link present; tapping opens it.
  // RED if: the link and the picker are wired to two different widgets.
  testWidgets('editable mode with config shows the link, which opens the picker',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig(dgh: 5, dgm: 0);
    await t.pumpWidget(subject(component(
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsMode: 'editable',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    expect(find.text('Berapa kotak hitam?'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('digitPadPickerLink')));
    await t.pump();
    expect(find.text('Berapa kotak hitam?'), findsOneWidget);
    expect(find.text('Cocokkan dengan meternya'), findsOneWidget);
  });

  // ★ RED if: the forced-picker term is dropped from digitPadBlockSubmit, or
  // the picker renders boxes before a pick. Spec §11: "Doc tidak punya dgh ->
  // pemilih muncul sendiri, kotak digit belum ada, tombol simpan mati".
  testWidgets('no config forces the picker, kills submit, and no boxes appear',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsSourcePosition: '14',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    await t.pump(); // post-frame gate

    expect(find.text('Berapa kotak hitam?'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    // ★ The '--' sentinel must not survive even on the picker-only path.
    expect(txfController[scr]![pos]!.finalData, '');
  });

  // ★ RED if: _writeSlot / _applyOutputs stop writing, or _markPickedByField is
  // removed. Spec §11: "Setelah memilih 5+2 -> digitsPosition 5,
  // digitsRedPosition 2, digitsSourcePosition field".
  //
  // ★ ALSO red if _pickBlack stops latching _pickerOpen: the black pick
  // resolves the count, which flips the picker from `forced` to `hidden`, and
  // the Red-2 chip below would no longer exist to tap. This is the one test
  // that proves the red row stays reachable after the first pick.
  testWidgets('picking writes all three output slots with source `field`',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsSourcePosition: '14',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    await tapChip(t, 'Black-5');
    await t.pump();
    await tapChip(t, 'Red-2');
    await t.pump();
    await t.pump(); // post-frame outputs + gate

    expect(txfController[scr]![9]!.finalData, '5');
    expect(txfController[scr]![13]!.finalData, '2');
    expect(txfController[scr]![14]!.finalData, 'field');
    // Boxes now exist: 5 black + 2 red.
    expect(find.byKey(const ValueKey<String>('digitPadBox-6')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-7')), findsNothing);
    // And the page is submittable again.
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ RED if: _applyOutputs writes only on the picker path. Spec §11: "Config
  // datang dari doc, petugas tidak menyentuh apa pun -> tiga slot itu TETAP
  // terkirim, digitsSourcePosition = config". Without this the CF has nothing
  // to persist and the picker returns every month.
  testWidgets('a doc-sourced count still fills all three slots, source `config`',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig(dgh: 4, dgm: 1);
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsSourcePosition: '14',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    await t.pump(); // post-frame outputs

    expect(txfController[scr]![9]!.finalData, '4');
    expect(txfController[scr]![13]!.finalData, '1');
    expect(txfController[scr]![14]!.finalData, 'config');
  });

  // ★ RED if: digitPadResolveSource's latch is removed. On build 2 the count
  // comes from the SLOT, so fromDoc is false — an unlatched resolver would flip
  // every point to `field` and the office would review all of them.
  testWidgets('the `config` provenance survives later rebuilds',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig(dgh: 4, dgm: 1);
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsSourcePosition: '14',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    await t.pump();
    expect(txfController[scr]![14]!.finalData, 'config');

    // Any interaction -> another build, now resolving from the slot.
    await tapKey(t, '9');
    await t.pump();
    await t.pump();
    expect(txfController[scr]![14]!.finalData, 'config');
  });

  // ★ RED if: _markPickedByField is dropped, or the picker tap routes through
  // the latch. In editable mode the slot already holds `config`; without the
  // direct write the office never sees the one row it must review.
  testWidgets('an editable-mode override flips the provenance to `field`',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedMeterConfig(dgh: 4, dgm: 1);
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsRedPosition: '13',
      digitsSourcePosition: '14',
      digitsField: 'dgh',
      digitsRedField: 'dgm',
      digitsMode: 'editable',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    await t.pump();
    expect(txfController[scr]![14]!.finalData, 'config');

    await t.tap(find.byKey(const ValueKey<String>('digitPadPickerLink')));
    await t.pump();
    await tapChip(t, 'Black-6');
    await t.pump();
    await t.pump();

    expect(txfController[scr]![9]!.finalData, '6');
    expect(txfController[scr]![14]!.finalData, 'field');
  });

  // ★ RED if: digitPadPickerState stops short-circuiting on hasOptions.
  // Interview decision 5 / product #17: one bad config cell must never lock the
  // officer out of the page. This is rev b's exact behaviour, preserved.
  //
  // ★ digitsPosition is deliberately VALID ('9') here even though nothing is
  // picked. This test must isolate the `!hasOptions` term: with a blank
  // digitsPosition the surviving `!canPersist` term would return `hidden` on its
  // own and the test would stay GREEN under its own mutation. The canPersist
  // half has its own test below (`options with no digitsPosition: silent, and
  // submit stays alive`) plus mutation 17.
  testWidgets('nothing pickable and no config: silent, and submit stays alive',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsField: '',
      digitsOptions: '',
      digitsRedOptions: '',
    )));
    await t.pump();
    await t.pump();

    expect(find.text('Angka di meter sekarang'), findsNothing);
    expect(find.text('Berapa kotak hitam?'), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ★★ RED if: the `canPersist` term is dropped from digitPadPickerState or
  // from its call site in _content.
  //
  // Options WITH nowhere to store the pick is the worst configuration of all:
  // the picker would render, the gate would engage, and every chip tap would be
  // swallowed by _writeSlot's null-position guard — so `black` stays null, the
  // gate re-asserts on every build (§2.6 removed the memo on purpose), and the
  // officer is locked out of the page with no escape. This is the same product
  // #17 rule as the no-options case, reached by a different bad cell.
  // ── field repro — spec §12, rev 2026-08-20f ───────────────────────────────
  //
  // Config lama aimed `digitsPosition` at a SELECTABLE_BTN slot on the same
  // page. The officer picked 5 and NOTHING appeared: no title, no boxes, no
  // error, so the broken config survived a whole field trip.
  //
  // Two facts make the cross-widget read unfixable from config:
  //   1. selectable_btn writes finalData (selectable_btn.dart:167) and signals
  //      no repaint at all, while this widget's GetBuilder is keyed to its OWN
  //      '$scrName-$position' id (digit_pad.dart:463). The pick can never reach
  //      a rebuild.
  //   2. The first (and only) build sees an empty slot, so `black` is null.
  //
  // What IS fixable is the silence — a config this broken must say so.
  testWidgets(
      'field repro: foreign digitsPosition slot renders a marker, '
      'and a late pick still never lands', (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    txfControllerCheck(scr, digitsSlot); // the SELECTABLE_BTN's slot, empty
    await t.pumpWidget(subject(component(
      digitsPosition: '9',
      digitsField: 'dgh', // and the doc carries no config either
    )));
    await t.pump();
    await t.pump(); // post-frame gate

    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsNothing);
    expect(find.textContaining('--DIGIT_PAD--'), findsOneWidget);

    // The officer taps 5 on the other widget. It lands in the slot...
    txfController[scr]![digitsSlot]!.finalData = '5';
    await t.pump();
    // ...and changes nothing, because nothing repainted this widget.
    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsNothing);
    expect(find.textContaining('--DIGIT_PAD--'), findsOneWidget);
    // Still no gate: the officer keeps the page (product #17).
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  testWidgets('options with no digitsPosition: silent, and submit stays alive',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    await t.pumpWidget(subject(component(
      digitsPosition: '',
      digitsField: 'dgh',
      digitsOptions: '4◆5◆6',
      digitsRedOptions: '0◆1◆2',
    )));
    await t.pump();
    await t.pump(); // post-frame gate

    expect(find.text('Berapa kotak hitam?'), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ── rev e: the bottom sheet (spec §4c) ────────────────────────────────────

  // ★ RED if: the sane branch is allowed to raise the sheet. §4c rule 1 — a
  // sheet on every unit trains officers to close it unread, and the backward
  // verdict goes with it. Interview decision 2 pins the inline banner.
  testWidgets('a sane verdict shows the inline banner and NO sheet',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 100 m³ dari 1000'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadVerdictRow')),
        findsNothing);
  });

  // ★ RED if: the auto-raise is removed. Spec §11: "Selisih > avg x 4 -> sheet
  // naik sendiri dengan segmen 3, tombol simpan tetap hidup".
  testWidgets('a spike raises the sheet unprompted and never blocks submit',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    for (final String k in <String>['0', '9', '9', '9', '9']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsOneWidget);
    expect(find.text('Kalau kamu yakin, disimpan apa adanya'), findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ RED if: the compact row loses its tap, or the raise latch swallows a
  // manual re-open. Spec §11: "Sheet ditutup -> baris ringkas tetap ada dan
  // bisa ditap; statusnya tidak hilang".
  testWidgets('dismissing leaves a tappable row that re-opens the sheet',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '9', '9', '9', '9']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    // Segment 13 stores the reading AS TYPED and closes. Nothing else.
    expect(txfController[scr]![pos]!.finalData, '9999');
    // The compact row survives.
    expect(find.byKey(const ValueKey<String>('digitPadVerdictRow')),
        findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('digitPadVerdictRow')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
  });

  // ★ RED if: digitPadShouldRaiseSheet drops the alreadyRaisedFor comparison.
  // §4c rule 3 — a dismissed sheet must not come back on the next rebuild.
  testWidgets('a dismissed sheet does not re-raise on rebuild',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '9', '9', '9', '9']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();

    // Tapping the caret box is a no-op on the buffer but forces a rebuild.
    await tapBox(t, 4);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★ RED if: segment 12 stops clearing the buffer, or the latch is not
  // re-armed on an empty value. Both halves matter: the clear is §4c rule 4,
  // the re-arm is what lets the NEXT complete value raise again.
  testWidgets('segment 12 clears the buffer and re-arms the raise',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component()));
    await t.pump();
    for (final String k in <String>['0', '9', '9', '9', '9']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetFix')));
    await t.pumpAndSettle();
    // ★ '' , NOT '_____': _content never writes the normalised buffer back to
    // controller.text (only _apply does, on a tap), and no tap follows here.
    expect(txfController[scr]![pos]!.controller.text, '');
    expect(txfController[scr]![pos]!.finalData, '');
    // The pad still RENDERS 5 empty boxes — the count is untouched, only the
    // typed digits are gone.
    expect(find.byKey(const ValueKey<String>('digitPadBox-4')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-5')), findsNothing);

    // A fresh complete spike raises again.
    for (final String k in <String>['0', '9', '9', '9', '8']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
  });

  // ★ RED if: the segment-13 suppression is keyed on blockOnBackward alone
  // instead of on the engaged gate. Spec §11: "blockOnBackward TRUE + vonis
  // mundur -> tombol segmen 13 tidak ada, yang muncul pesan segmen 5".
  testWidgets('a blocked backward reading hides segment 13 and shows segment 5',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    await t.pumpWidget(subject(component(blockOnBackward: 'TRUE')));
    await t.pump();
    for (final String k in <String>['0', '0', '9', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsNothing);
    // Segment 5 appears twice: in the sheet and as the card footer.
    expect(find.text('Perbaiki dulu'), findsNWidgets(2));
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
  });

  // ── a disabled pad never gates (code-review r1 W1 + route 2) ──────────────
  //
  // NOTE both tests below seed ic.isEnabled = false BEFORE pumpWidget, for the
  // reason spelled out on 'isEnabled FALSE makes every key inert': the pump
  // bypasses buildDisplayComponent, which is what normally copies
  // component['isEnabled'] into the slot. Passing isEnabled:'FALSE' in the
  // component alone would leave the pad LIVE and neither test would prove
  // anything. The component flag is passed too, so the config shape is honest.

  // ★ RED if: the `&& enabled` term is dropped from _scheduleGate.
  // ROUTE 1 (introduced by rev d): isEnabled:"FALSE" + digitsOptions set + no
  // resolvable count => picker `forced` => block. Both chip rows are inert
  // under !enabled, so the pick that would clear the gate can never be made,
  // and §2.6's deliberate lack of a memo re-asserts it on every build. The
  // officer is locked out of the whole page — photos, GPS and all.
  testWidgets('a disabled pad never gates on an unfillable picker',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    txfController[scr]![pos]!.isEnabled = false;
    seedPage();
    await t.pumpWidget(subject(component(
      isEnabled: 'FALSE',
      digitsPosition: '9',
      digitsOptions: '4◆5◆6',
      digitsField: 'dgh',
    )));
    await t.pump();
    await t.pump(); // post-frame gate

    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ★ RED if: the `&& enabled` term is dropped from _scheduleGate.
  // ROUTE 2 (pre-existing since rev b, NOT found by the reviewer): a complete
  // BACKWARD reading already sitting in the buffer (seeded from currentValue /
  // initialValue in production) + blockOnBackward:"TRUE" => verdictBlock. Every
  // digit key, the backspace and every box are inert under !enabled, so the
  // officer cannot correct the very number that is blocking him. This is the
  // route that can fire on MeterSurvey, the one page whose entire reason for
  // existing is that block.
  testWidgets('a disabled pad never gates on a backward reading it cannot correct',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 30);
    // 900 < pv 1000 -> backward, and the buffer is already complete.
    txfController[scr]![pos]!.controller.text = '00900';
    txfController[scr]![pos]!.isEnabled = false;
    await t.pumpWidget(subject(component(
      isEnabled: 'FALSE',
      blockOnBackward: 'TRUE',
    )));
    await t.pump();
    await t.pump(); // post-frame gate

    // The reading is still CAPTURED — it is stored, just not blocking.
    expect(txfController[scr]![pos]!.finalData, '900');
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);

    // ★ The verdict-block UI must be off too, not just the gate — `verdictBlock`
    // carries `&& enabled` at its definition. Measured, not assumed: the sheet
    // DOES still rise here (a read-only pad should still surface "this reading
    // looks wrong"), so the assertions below pin the two things that change.
    //
    // 1. Segment 5 is absent EVERYWHERE. Before the fix it rendered twice — the
    //    card footer AND the sheet's blocked-foot — demanding a correction from
    //    an officer whose every key and box is inert.
    expect(find.text('Perbaiki dulu'), findsNothing);
    // 2. The sheet rose, and with the block disengaged it offers segment 13,
    //    which is the officer's only exit besides the barrier. Before the fix
    //    this button was suppressed: a modal with no way out, on top of a save
    //    button that was alive anyway.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsOneWidget);
  });
  // ── deltaMax: the ABSOLUTE ceiling (digit-pad-deltamax-serial §3) ─────────

  // ★★ Acceptance §11 line 3, and the CONTROL for the pair below it. On its
  // own this test would still pass with the entire deltaMax feature deleted —
  // it only has force NEXT TO its twin, which changes nothing but the cell.
  // RED if: the `deltaMax > 0` guard is dropped (an absent cell is 0, so every
  // reading would flag).
  testWidgets('a blank deltaMax leaves the verdict exactly as it was',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    // avg 100 * spikeMultiplier 4 = 400, so delta 150 is comfortably sane
    // under the RELATIVE rule alone.
    seedMeterDoc(pv: 1000, avg: 100);
    await t.pumpWidget(subject(component()));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '1', '5', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 150 m³ dari 1000'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★★ The twin. ONE cell different — and it arrives as a JSON NUMBER, the
  // production shape (§2.1), not a string.
  // RED if: _deltaMax is never parsed, or the deltaMax branch never runs.
  // Also pins interview decision 3's documented residual: this point HAS an
  // avg, so it reads segment 3 even though only the deltaMax branch tripped.
  testWidgets('deltaMax 100 turns the same reading into a spike',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDoc(pv: 1000, avg: 100);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '1', '5', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    // Banner + sheet.
    expect(find.text('Lonjakan jauh — 150 m³'), findsNWidgets(2));
    // A spike NEVER blocks (spec §10: leaks are real and must be reported).
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★★ Acceptance §11 line 1 — the new-point hole, closed. RED if: segment 15
  // is not selected when avg is absent (segment 3 would render a literal
  // `{avg}` at the officer), or if `{deltaMax}` never reaches the token map.
  testWidgets('an avg-less point trips deltaMax and reads segment 15',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '1', '5', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(
      find.text('Pemakaian 150 m³ — melewati batas 100 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
    expect(find.text('Lonjakan jauh — 150 m³'), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ── the m³ basis on a dgm:2 point ────────────────────────────────────────
  //
  // ★★ These four are the ONLY tests in either suite that can see the m³
  // conversion. Every other component here resolves red = 0, where 10^red is 1
  // and digitPadCubic returns its argument untouched.

  // ★ Acceptance §11 line 2. RED if: the delta is compared raw — 5000 > 100
  // would flag a perfectly ordinary month. The `dari 126` in the expected
  // string is the second half of the mutation: {prev} must be m³ too.
  testWidgets('a dgm 2 point compares in m³, not in raw stand units',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    // 4 black + 2 red = 6 boxes.
    expect(find.byKey(const ValueKey<String>('digitPadBox-5')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadComma')), findsOneWidget);

    // raw 17600 - 12600 = 5000 -> 50 m³, well under deltaMax 100.
    for (final String k in <String>['0', '1', '7', '6', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 50 m³ dari 126'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    // The RAW integer is still what gets submitted — the division is for the
    // verdict and the copy, never for storage (§2.1).
    expect(txfController[scr]![pos]!.finalData, '17600');
  });

  // ★★ ISSUE-1 (plan audit W1) — the UNCONVERTED `avg`, pinned.
  //
  // `avg` is deliberately left in the doc's own unit while value and prev are
  // divided by 10^red, because it is authored in m³/month already: the same
  // page's DETAIL_CARD renders it `Rata-rata` + `<avg>` + ` m³/bln`. That
  // premise is UNMEASURED — the one live `meter` doc has no `avg` field at all,
  // so nothing was read from data. Owner check owed before the first dgm > 0
  // point goes live; until then this test pins today's treatment so a change to
  // that line is deliberate rather than drift.
  //
  // ★ RED if: `avg` is passed through digitPadCubic like value and prev
  // (mutation M6). The spike threshold would collapse from 30 * 4 = 120 m³ to
  // 0.3 * 4 = 1.2 m³ and this ordinary 50 m³ month would read as a spike.
  testWidgets('a dgm 2 point measures the avg branch against an UNCONVERTED avg',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600, avg: 30);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    // raw 17600 - 12600 = 5000 -> 50 m³: under avg 30 * 4 = 120 m³ and under
    // deltaMax 100. An ordinary month, and it must stay one.
    for (final String k in <String>['0', '1', '7', '6', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 50 m³ dari 126'), findsOneWidget);
    expect(find.text('Lonjakan jauh — 50 m³'), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★ The boundary. raw +10000 is EXACTLY 100 m³, and the threshold is strict
  // `>` ("melewati batas"), so this is sane. RED if: the branch uses `>=`.
  testWidgets('exactly at deltaMax is still sane', (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '2', '2', '6', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 100 m³ dari 126'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★★ The SAME boundary on a prev whose quotient is NOT exact — the shape
  // both older boundary tests miss. They pick prev = 12600 (126.0) and prev =
  // 1000 at pow10 1, where the two quotients happen to be exactly
  // representable and any implementation agrees. 2802/100 is not: it is the
  // binary64 nearest 28.02, and so is 12802/100, so subtracting the two
  // quotients yields 100.00000000000001 — a false spike at exactly the ceiling
  // on 1.64% of raw prev values, measured. Dividing the raw DIFFERENCE once
  // gives exactly 100.0.
  //
  // ★ RED if: the delta reaching the deltaMax comparison OR the delta reaching
  // the {delta} token is a difference of two separately-divided quotients. This
  // test was confirmed RED against the pre-fix code (it rendered segment 15
  // with 'Pemakaian 100.00000000000001 m³'), so both halves of the assertion
  // below are live, not decorative.
  testWidgets('at deltaMax with an INEXACT prev quotient it is still sane',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 2802);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    // raw 12802 - 2802 = 10000 -> EXACTLY 100 m³, and the threshold is strict.
    for (final String k in <String>['0', '1', '2', '8', '0', '2']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    // Segment 2, with {delta} rendering the same number the verdict used.
    expect(
        find.text('Masuk akal — selisih 100 m³ dari 28.02'), findsOneWidget);
    // Not segment 15, and not the float artefact that the old arithmetic put
    // into it.
    expect(find.textContaining('melewati batas'), findsNothing);
    expect(find.textContaining('100.00000000000001'), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★ One m³ past it trips, and with no avg on the doc it reads segment 15
  // with BOTH tokens resolved.
  testWidgets('one m³ past deltaMax raises segment 15',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '2', '2', '7', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(
      find.text('Pemakaian 101 m³ — melewati batas 100 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
  });

  // RED if: the conversion is applied to only ONE side of the comparison.
  testWidgets('backward survives the m³ conversion unchanged',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    // raw 10000 -> 100 m³ < 126 m³.
    for (final String k in <String>['0', '1', '0', '0', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Angka lebih kecil dari 126'), findsNWidgets(2));
  });

  // ── dmx: the PER-POINT ceiling (meter-block-alias-dmx §4a) ────────────────
  //
  // ONE rule: the effective ceiling is `doc.dmx` when present and > 0,
  // otherwise the config `deltaMax`. Everything else about the deltaMax branch
  // — the m³ basis, the avg-less segment-15 path, the strict `>` — is
  // unchanged, and the tests above still pin all of it.
  //
  // Matched PAIRS, the same discipline as the deltaMax group above: identical
  // seed and identical keystrokes, exactly one thing different. Every doc here
  // is avg-less, which is both the shape of every brand-new point and the shape
  // that routes a spike to segment 15 — the only segment carrying {deltaMax}.

  // ★★ Acceptance §11 C1, first half. The config says 100, the POINT says 15,
  // and 16 m³ is over the point's ceiling but nowhere near the config's.
  //
  // ★ RED if: the verdict call still passes `_deltaMax` (16 <= 100 would read
  // sane and nothing would render), or the token map still renders `_deltaMax`
  // (the sentence would say "batas 100").
  testWidgets('doc dmx 15 overrides a config deltaMax of 100',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000, dmx: 15);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    // 5 boxes, pow10 1: 1016 - 1000 = 16 m³.
    for (final String k in <String>['0', '1', '0', '1', '6']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    // Banner + sheet, and the sentence names the POINT's ceiling.
    expect(
      find.text('Pemakaian 16 m³ — melewati batas 15 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
    expect(find.textContaining('Masuk akal'), findsNothing);
    // A spike NEVER blocks (spec §10). `dmx` moves the threshold, not the
    // doctrine — this is the pin that says so.
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★★ Acceptance §11 C1, the sane half. Identical seed, identical component,
  // ONE keystroke different: 14 m³ is under the point's 15. Without this twin
  // the test above would pass just as well against a mutant that flagged
  // EVERYTHING.
  testWidgets('doc dmx 15 leaves 14 m³ sane', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000, dmx: 15);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '0', '1', '4']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 14 m³ dari 1000'), findsOneWidget);
    expect(find.textContaining('melewati batas'), findsNothing);
  });

  // ★★ Acceptance §11 C1, second half — the TOKEN, isolated. Same scenario as
  // the pair's first half; the ASSERTIONS are what differ, and they are the
  // only ones in either suite aimed squarely at the token map.
  //
  // The first expect is load-bearing, not decoration: without it a mutant that
  // never trips at all would satisfy the second one VACUOUSLY.
  //
  // ★ RED if: the token map still renders `_deltaMax` (second expect finds 2),
  // or the verdict call still passes `_deltaMax` (first expect finds 0).
  testWidgets('the segment-15 message names the POINT ceiling, not the config',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000, dmx: 15);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '0', '1', '6']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.textContaining('melewati batas'), findsNWidgets(2));
    expect(find.textContaining('melewati batas 100'), findsNothing);
    expect(find.textContaining('melewati batas 15 m³'), findsNWidgets(2));
  });

  // ★★ Acceptance §11 line 2 — zero regression — and the CONTROL that makes
  // the pair above attributable: identical seed and identical keystrokes to
  // 'doc dmx 15 overrides a config deltaMax of 100', with exactly ONE map entry
  // removed. 16 m³ is comfortably under the config's 100, so it stays sane.
  //
  // ⚠ This test is a CONTROL and is NOT mutation-sensitive by construction. It
  // asserts the ABSENCE of a change, and every plausible mutation of the
  // `: _deltaMax` fallback either RAISES the effective ceiling or switches it
  // off — neither can turn a sane 16 m³ into a spike. The config path itself
  // stays pinned by 'deltaMax 100 turns the same reading into a spike' and
  // 'an avg-less point trips deltaMax and reads segment 15' above; the plan's
  // mutation table (Verification M3) names the run that demonstrates that split
  // rather than pretending this test catches it.
  testWidgets('a doc with no dmx leaves the config deltaMax governing',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '0', '1', '6']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 16 m³ dari 1000'), findsOneWidget);
    expect(find.textContaining('melewati batas'), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ Acceptance §11 line 3 — `dmx` is compared in m³, AFTER the ÷10^dgm,
  // exactly like the config ceiling: at pow10 100 the point's 15 bounds the
  // 14 m³ month, never the raw 1400 stand units.
  //
  // ⚠ HONEST ABOUT ITS OWN POWER, because the plan audit measured it: this
  // pump asserts a SANE outcome and reads green before this round, after it,
  // and under every mutation in the plan's table. It is DOCUMENTATION of the
  // basis, not a detector of it. The m³ basis is structurally guaranteed
  // rather than mutation-pinned — the ÷10^dgm lives entirely inside
  // digitPadDelta / digitPadVerdict (lib/widget/digit_pad_support.dart), which
  // this round does not touch, and `deltaMaxEff` is handed to the very same
  // `deltaMax` parameter `_deltaMax` was handed to, so no edit in this round
  // can produce a raw comparison. The DETECTOR for the per-point ceiling on a
  // dgm:2 point is its twin immediately below.
  //
  // NOTE the harness difference from the tests above: NO seedSlots() here, for
  // the same reason the existing m³ tests omit it — seeding slot 9 with '5'
  // would latch 5 black boxes and the doc's `dgh: 4` would never be read.
  testWidgets('a dgm 2 point compares dmx in m³, not in raw stand units',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600, dmx: 15);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    // 4 black + 2 red = 6 boxes, pow10 100.
    // raw 14000 - 12600 = 1400 -> 14 m³, under the point's 15.
    for (final String k in <String>['0', '1', '4', '0', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text('Masuk akal — selisih 14 m³ dari 126'), findsOneWidget);
    expect(find.textContaining('melewati batas'), findsNothing);
  });

  // ★★ THE TWIN, added by the plan audit (I-W4), and the only new test that
  // exercises the per-point ceiling on a `pow10 != 1` point at all. Identical
  // seed and identical keystrokes to the pump above; ONE thing different — the
  // point's ceiling is 13, so the same 14 m³ month is now over it, while the
  // config's 100 is nowhere near either number.
  //
  // raw 14000 - 12600 = 1400 -> 14 m³. The asserted sentence pins BOTH halves
  // at once: the BASIS (a raw comparison of 1400 against 13 would spike here
  // too, but it would also spike against the config's 100, and the surviving
  // sane sibling above forbids that reading) and the SOURCE (only the point's
  // 13 can put "batas 13" in the sentence — the config cannot).
  //
  // ★ RED if: the verdict call still passes `_deltaMax` (14 <= 100 reads sane
  // and nothing renders), or the token map still renders `_deltaMax` (the
  // sentence would say "batas 100").
  testWidgets('a dgm 2 point trips dmx 13 on 14 m³, not on the raw 1400',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    seedPage();
    seedLodgeDoc(pv: 12600, dmx: 13);
    await t.pumpWidget(subject(lodgeComponent()));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '4', '0', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(
      find.text('Pemakaian 14 m³ — melewati batas 13 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
    // The config ceiling never reaches the sentence.
    expect(find.textContaining('melewati batas 100'), findsNothing);
  });

  // ★★ `dmx: 0` means "no ceiling on this point", never "a ceiling of zero":
  // the config falls back in. Spec §3 spells `0/absent` out as one case.
  //
  // A NEGATIVE dmx and an UNPARSEABLE one route through the same two clauses —
  // `docDmx != null` (already unit-pinned for null / '' / '--' / 'null' /
  // 'abc' by the digitPadNum group at test/digit_pad_support_test.dart:43-53)
  // and `docDmx > 0` (this test) — so they deliberately get no separate pump.
  // Three near-identical pumps would exercise one branch three times.
  //
  // ★ RED if: the guard is `>= 0`, or the `> 0` term is dropped, or
  // `deltaMaxEff` is seeded with 0 instead of `_deltaMax`. Each makes the
  // effective ceiling 0, digitPadVerdict's own `deltaMax > 0` switches the
  // absolute branch off, and this 150 m³ month reads sane.
  testWidgets('a doc dmx of 0 falls back to the config deltaMax',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000, dmx: 0);
    await t.pumpWidget(subject(component(deltaMax: 100)));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '1', '5', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(
      find.text('Pemakaian 150 m³ — melewati batas 100 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
  });

  // ★★ The sharpest pin on the TOKEN plumbing. With no `deltaMax` cell at all
  // `_deltaMax` is 0, so a token map that still read it would omit the entry
  // entirely and the pending-safe dialect would print a LITERAL `{deltaMax}` at
  // the officer — while a verdict call that still read it would not trip at
  // all. The doc arms the ceiling on its own.
  //
  // ★ RED if: EITHER site still reads `_deltaMax`.
  testWidgets('doc dmx arms the ceiling with no config deltaMax at all',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocNoAvg(pv: 1000, dmx: 15);
    // component() ships deltaMax: '' — the unconfigured cell.
    await t.pumpWidget(subject(component()));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '0', '1', '6']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(
      find.text('Pemakaian 16 m³ — melewati batas 15 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
    expect(find.textContaining('{deltaMax}'), findsNothing);
  });

  // ★ Acceptance §11 line 4 — zero hardcoded strings. `deltaMaxField` is an
  // operator-facing INTERFACE: a builder may rename the doc field, and a typo
  // in the Dart spelling of the key would fail SILENTLY (an unknown component
  // key is ignored — no crash, no log, no analyzer finding). This test spells
  // the key out loud so a rename goes RED instead of quiet.
  //
  // The decoy `dmx: 999` on the same doc is what makes it airtight: if the
  // 'dmx' default silently won, the ceiling would be 999 and 16 m³ would read
  // sane.
  //
  // ★ RED if: 'dmx' is hardcoded at the read site, or the config key is read
  // under any name other than 'deltaMaxField'.
  testWidgets('deltaMaxField renames the doc field the ceiling is read from',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{'pv': 1000, 'maxm3': 15, 'dmx': 999},
    ];
    final Map<String, dynamic> c = component(deltaMax: 100)
      ..['deltaMaxField'] = 'maxm3';
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '0', '1', '6']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(
      find.text('Pemakaian 16 m³ — melewati batas 15 m³. Cek lagi angkanya.'),
      findsNWidgets(2),
    );
  });

  // ── the serial identity check, sourced from a form slot ──────────────────

  // ★ Acceptance §11 line 6 — the owner's second sentence, and the doctrine
  // this widget refuses to break: never train officers to dismiss a signal.
  // RED if: a blank recorded serial stops short-circuiting to `off`.
  testWidgets('a blank msn means zero checks, zero warnings and zero gate',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: '');
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text(seg16), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // RED if: serialField stops gating the whole feature.
  testWidgets('a blank serialField is totally silent', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(subject(
        component(serialField: '', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ THE MeterSurvey shape (D562: serialField:"", serialSourcePosition:"").
  // RED if: digitPadParsePosition stops returning null for a blank string, or
  // a blank serialSourcePosition acquires a "helpful" default.
  testWidgets('a blank serialSourcePosition is totally silent',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      serialSourcePosition: '',
      blockOnSerialMismatch: 'TRUE',
    )));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ RED if: the `serialSlot == _position` nulling in initState is removed.
  // Without it the pad reads its OWN slot — which holds the digit buffer, is
  // empty on the first build, and would therefore report MISSING and kill the
  // save button on every page the officer has not typed into yet. It would
  // also attach a listener to its own controller: a self-setState loop.
  testWidgets('a self-referential serialSourcePosition is refused',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      serialSourcePosition: '$pos',
      blockOnSerialMismatch: 'TRUE',
    )));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ★★ The config decay this round's W1 named. serialSourcePosition names a
  // slot NO component on the page owns — a typo, or a TXF later deleted from
  // the sheet. _slotValue returns '' for that exactly as it does for "the
  // officer has not typed yet", so read undiscriminated it is `missing` ->
  // serialBlock -> a page with no control anywhere that can clear it. The
  // retired photoPosition:"3" decayed this way and failed OPEN; this must too.
  //
  // The controller is the discriminator: minting is EAGER (buildPage calls
  // buildDisplayComponent, hence txfControllerCheck, for every positioned
  // component before it returns) while mounting is LAZY, so a null controller
  // means nobody owns the slot.
  //
  // ★ RED if: the null-controller case falls back to '' and is read as
  // `missing`. THE OTHER DIRECTION is pinned by
  // `msn filled + an empty slot blocks with segment 16`, which is this same
  // config with serialSourcePosition left on slot 16 — it asserts the gate
  // DOES engage, so "silent" here cannot be a broken lookup.
  testWidgets('a serialSourcePosition no component owns is OFF, not a gate',
      (WidgetTester t) async {
    seedSlots(); // mints 9, 7 and 16 — never 19.
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      serialSourcePosition: '19',
      blockOnSerialMismatch: 'TRUE',
    )));
    await t.pumpAndSettle();
    // The premise, asserted rather than assumed.
    expect(txfController[scr]![19], isNull);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);

    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    // Totally silent: not the sheet, not the message, not the gate.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text(seg16), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ★★ The sibling shape: the slot EXISTS but ships isEnabled:"FALSE". The
  // officer cannot retype a serial in a field he cannot focus, so a gate
  // raised on it could never be cleared by the one action that clears it -
  // the same doctrine as the pad's own `&& enabled`, applied to the SOURCE
  // slot. Fail OPEN, but NOT silent: there is something real to warn about
  // here (a recorded serial and an empty capture), so the sheet still says so.
  //
  // ★ RED if: `serialSourceEnabled` is dropped from serialBlock (the save
  // button dies with no way back), or if the disabled slot is instead treated
  // like the absent one (the warning disappears too).
  testWidgets('a DISABLED serial source slot warns but never gates',
      (WidgetTester t) async {
    seedSlots();
    txfController[scr]![serialSlot]!.isEnabled = false;
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);

    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    // WARNED — segment 16 is on screen ...
    expect(find.text(seg16), findsOneWidget);
    // ... but NOT gated, and the acknowledge button is available because the
    // sheet is not blocking.
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(txfController[scr]![pos]!.finalData, '1100');
  });

  // ★ Acceptance §11 line 4, first half — normalisation on BOTH sides.
  // RED if: digitPadNormalizeSerial stops being applied to the slot value.
  testWidgets('a matching serial is silent, punctuation and case aside',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA); // 'B21-4471902'
    writeSerialSlot('b21 4471902');
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ Acceptance §11 line 4, second half. The sheet rises on the FIELD alone,
  // with the digit boxes still empty (spec §5's sketch).
  // RED if: the mismatch state stops keying the sheet, or {serial} is filled
  // from the slot instead of the doc.
  testWidgets('a wrong serial raises segment 6 with the RECORDED serial',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writeSerialSlot('X99-1234567');
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.text(seg6Resolved), findsOneWidget);
    // blockOnSerialMismatch TRUE -> no "memang segitu" for a serial. The only
    // ways out are correcting the field or the page's own "Tidak bisa dibaca"
    // chain, which digitPadSaveSendPositions structurally cannot gate.
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(txfController[scr]![pos]!.finalData, '');
  });

  // RED if: the `_blockOnSerialMismatch &&` term is dropped from serialBlock.
  testWidgets('blockOnSerialMismatch FALSE warns but never disables savesend',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writeSerialSlot('X99-1234567');
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'FALSE')));
    await t.pumpAndSettle();

    expect(find.text(seg6Resolved), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsOneWidget);
    expect(find.text('Perbaiki dulu'), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★★ Acceptance §11 line 5. Skipping the capture is NOT an escape hatch.
  // RED if: the `missing` state stops producing a key, or segment 16 is not
  // selected for it (segment 6's "tidak cocok" would be a lie).
  testWidgets('msn filled + an empty slot blocks with segment 16',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();
    // The gate is on from the first build; the SHEET waits for a reading.
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    // 01100 -> '1100'; 100 over pv 1000 is inside avg 30 * 4, so the NUMERIC
    // verdict is `sane` and the locking serial problem owns the sheet.
    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.text(seg16), findsOneWidget);
    expect(find.text(seg6Resolved), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    // The reading itself is captured, exactly as typed.
    expect(txfController[scr]![pos]!.finalData, '1100');
  });

  // ★★ RED if: digitPadSerialKey stops gating the MISSING half on
  // readingComplete. An empty slot is the birth state of EVERY meter, so this
  // is the difference between "one sheet when it matters" and "a modal on 100%
  // of page entries", which is §4c rule 1's exact failure mode.
  testWidgets('the missing-serial sheet does NOT greet the officer on entry',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text(seg16), findsNothing);
    // The gate is NOT deferred — an incomplete reading submits '' anyway.
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
  });

  // ★★ Acceptance §11 line 7 — the point that killed the photoPosition path.
  // Nothing touches the pad here: the slot is written the way its real writers
  // write it, and ONLY the listener can turn that into a rebuild.
  // RED if: the serial-slot listener is removed, or _ensureSerialWatch stops
  // being called from the post-frame pass. (The pass is also what survives
  // buildPage(clear:true) re-minting txfController[scrName] — a one-shot
  // attach in initState would hold a stale controller after a page rebuild.)
  testWidgets('a serial written AFTER the first build lifts the gate',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);

    writeSerialSlot(serialA);
    await t.pumpAndSettle();

    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★★★ THE anti-keystroke test, and the reason digitPadSerialKey is keyed on
  // the STATE. The serial slot is an ordinary TXF: its controller notifies this
  // pad on EVERY character and otq_txf_2's onChanged writes finalData per
  // character. A value-keyed latch would mint a new key per keystroke and, the
  // sheet being MODAL, force the officer to dismiss a bottom sheet between
  // every two characters — r1's W1 defect through a different door.
  //
  // TWO sheets are correct here (one `missing`, one `mismatch`). A third is the
  // bug. RED if: the key carries the read value.
  testWidgets('editing a wrong serial raises the sheet ONCE, not per keystroke',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    // FALSE so segment 13 exists and the modal can be dismissed between steps;
    // with TRUE the barrier would swallow the taps.
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'FALSE')));
    await t.pumpAndSettle();

    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    // Sheet #1 — MISSING, now that the reading is complete.
    expect(find.text(seg16), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();

    // The officer starts typing. 'B' is 1 char, so the < 4 rule demands exact
    // equality and this is a MISMATCH — new state, one new sheet.
    writeSerialSlot('B');
    await t.pumpAndSettle();
    expect(find.text(seg6Resolved), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();

    // ★ Two more characters. Still MISMATCH, still the same key: NO new sheet.
    for (final String v in <String>['B2', 'B21']) {
      writeSerialSlot(v);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
          findsNothing,
          reason: 'typing "$v" must not raise a third sheet');
    }

    // 'B214' is 4 chars, so substring matching applies and it matches.
    writeSerialSlot('B214');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    // The reading survived every one of those rebuilds untouched.
    expect(txfController[scr]![pos]!.finalData, '1100');
  });

  // ★★ Interview decision 10. RED if: the serialBlocking short circuit is
  // dropped from digitPadSerialOwnsSheet — the SPIKE would take the sheet,
  // segment 13 would be suppressed by the serial gate, and the officer would
  // be told to fix a number that cannot lift his block.
  testWidgets('a LOCKING serial problem owns the sheet even over a spike',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writeSerialSlot('X99-1234567');
    // ★ SEEDED before the pump, never typed after it: the serial sheet is
    // already up on the first frame and showModalBottomSheet's barrier absorbs
    // every tap aimed at the numpad underneath. _content re-establishes the
    // buffer from controller.text on every build, which is also how an edit
    // page arrives with a reading already in place.
    // 09999 -> '9999'; 8999 over pv 1000 is far past avg 30 * 4.
    txfController[scr]![pos]!.controller.text = '09999';
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    // The SHEET carries the serial message...
    expect(find.text(seg6Resolved), findsOneWidget);
    // ...and the CARD still carries the numeric one. findsOneWidget, not two:
    // the banner is on screen, the sheet is not showing it. Nothing is hidden.
    expect(find.text('Lonjakan jauh — 8999 m³'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
  });

  // ★ The other side of the same rule: when nothing is locking, the numeric
  // verdict keeps the sheet exactly as it did before this round.
  // RED if: serialBlocking is ORed in without the blocking condition.
  testWidgets('a NON-locking serial problem yields the sheet to the numbers',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writeSerialSlot('X99-1234567');
    txfController[scr]![pos]!.controller.text = '09999';
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'FALSE')));
    await t.pumpAndSettle();

    expect(find.text('Lonjakan jauh — 8999 m³'), findsNWidgets(2));
    expect(find.text(seg6Resolved), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★ Same doctrine as the two disabled-pad tests above: a gate the officer
  // cannot clear is a brick. On a disabled pad he can neither retype the serial
  // nor correct anything, and §2.6's lack of a gate memo makes the block
  // permanent — taking the page's photos, GPS and every other field with it.
  // RED if: the `&& enabled` term leaves serialBlock.
  testWidgets('a disabled pad never gates on a serial problem',
      (WidgetTester t) async {
    txfControllerCheck(scr, pos);
    txfController[scr]![pos]!.isEnabled = false;
    seedSlots();
    txfController[scr]![pos]!.isEnabled = false;
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writeSerialSlot('X99-1234567');
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      blockOnSerialMismatch: 'TRUE',
      isEnabled: 'FALSE',
    )));
    await t.pumpAndSettle();

    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(find.text('Perbaiki dulu'), findsNothing);
    expect(noPumpException(), isTrue);
  });

  // §3.1 "segmen kosong = fitur itu diam" — MeterSurvey's 15-segment `text`
  // reaches segment 16 out of range, and SduiSpec.text is a length guard.
  // RED if: either segment acquires a hardcoded fallback.
  testWidgets('a blank segment 16 silences the missing-serial message',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      missingSerialText: '',
      blockOnSerialMismatch: 'FALSE',
    )));
    await t.pumpAndSettle();
    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // Acceptance §11 line 10 — a retired key must be inert, not fatal. Both
  // photoPosition and ocrPattern are present in EVERY component() here.
  // RED if: anyone "implements" either, or SduiSpec starts rejecting unknown
  // keys.
  testWidgets('leftover photoPosition and ocrPattern are ignored silently',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writeSerialSlot(serialA);
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.text('Angka di meter sekarang'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ★ §2.4's live shape: BOTH savesend children ship without a `position`, so
  // digitPadSaveSendPositions returns [] and every block is a silent no-op.
  // This pins that the widget does not crash and does not write anything; the
  // devPrint itself is kDebugMode-only and has no seam, so it is deliberately
  // NOT asserted here (see the mutation list).
  testWidgets('a positionless savesend page is a no-op, never a crash',
      (WidgetTester t) async {
    seedSlots();
    screenUIComponent[scr] = <String, dynamic>{
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'rbt',
          'children': <dynamic>[
            <String, dynamic>{'action': 'savesend', 'text': 'Simpan & lanjut'},
          ],
        },
      ],
    };
    seedMeterDocWithSerial(msn: serialA);
    writeSerialSlot('X99-1234567');
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.text(seg6Resolved), findsOneWidget);
    expect(noPumpException(), isTrue);
  });
}

/// No uncaught exception was recorded during the last pump.
///
/// lowerCamelCase deliberately: `non_constant_identifier_names` is in the
/// analyzer baseline and §7.1 demands ZERO new findings on touched files.
bool noPumpException() =>
    TestWidgetsFlutterBinding.instance.takeException() == null;
