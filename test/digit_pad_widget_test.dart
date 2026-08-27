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
// ★ ML KIT NEVER RUNS HERE AND CANNOT. The plugin is a MethodChannel and throws
// MissingPluginException under flutter_test, so setUp below replaces the
// top-level `digitPadOcrRead` seam with a counting fake. Two consequences worth
// stating: acceptance §11's "nol ML Kit dipanggil" becomes a countable
// assertion (`ocrCalls`), and NOTHING here is evidence that ML Kit reads a real
// meter photo — the native side of this plugin has never been compiled in this
// repo. That is device work.
//
// No restore in tearDown: `flutter test` gives every FILE its own isolate, so
// the fake cannot leak into another suite; setUp re-installs it per test, which
// is what keeps the counters from leaking BETWEEN tests in this file.
//
// ★ WHAT A GREEN RUN HERE STILL DOES NOT PROVE: the real Firestore
// subscription (subscribeToMapCollection), `search` resolution through
// filterDriverHomeDocs (no component here sets `search`, so that path is never
// entered), and the real `meter` doc's shape and field types — which are
// unratified anyway. Those stay device work (§7.3 manual flow).
import 'dart:async';

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
  const int photoSlot = 3;
  const String serialA = 'A21-4471908';
  const String photoA = '/data/user/0/app/otq_images/OTQC_a.jpg';
  const String photoB = '/data/user/0/app/otq_images/OTQC_b.jpg';
  const String seg6 =
      'Nomor seri di foto tidak cocok dengan yang tercatat ({serial}). '
      'Yakin ini meteran unit ini?';
  const String seg6Resolved =
      'Nomor seri di foto tidak cocok dengan yang tercatat (A21-4471908). '
      'Yakin ini meteran unit ini?';

  /// How many times the ML Kit seam was entered — acceptance §11's "nol ML Kit
  /// dipanggil" measured, not asserted by absence of a warning.
  int ocrCalls = 0;
  List<String> ocrPaths = <String>[];
  Map<String, String> ocrTextByPath = <String, String>{};
  bool ocrThrows = false;

  /// Holds the seam OPEN, per photo path. While a path has an entry here the
  /// fake awaits it before answering (or throwing), which is the only way to
  /// still be INSIDE the ML Kit round-trip when something else happens to the
  /// pad — and that round-trip is where r2's W4 lived.
  ///
  /// Per PATH rather than one global gate so a test can also choose which of
  /// two in-flight reads answers FIRST, which is what "an older read answers
  /// last" needs. `ocrCalls` still counts at DISPATCH, not at answer.
  Map<String, Completer<void>> ocrGates = <String, Completer<void>>{};

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
    // ★ The serial memo is static for the SAME reason (it must survive the
    // State destruction a scroll causes — r1 W2), so it leaks between tests the
    // same way: without this, the second test to pump the SAME photo + serial
    // would find _ocrKey already answered, skip the OCR entirely and assert
    // ocrCalls == 1 against a seam that never ran. Measured, not assumed —
    // eight tests in this file fail if this line is removed.
    DigitPad.clearSerialMemo(scr);
    ocrCalls = 0;
    ocrPaths = <String>[];
    ocrTextByPath = <String, String>{};
    ocrThrows = false;
    ocrGates = <String, Completer<void>>{};
    digitPadOcrRead = (String path) async {
      ocrCalls++;
      ocrPaths.add(path);
      final Completer<void>? gate = ocrGates[path];
      if (gate != null) await gate.future;
      if (ocrThrows) throw StateError('MissingPluginException (simulated)');
      return ocrTextByPath[path] ?? '';
    };
  });

  /// The `meter` doc's serial field, alongside pv/avg.
  void seedMeterDocWithSerial({num pv = 1000, num avg = 30, String msn = ''}) {
    mapTableContent[''] = <Map<String, dynamic>>[
      <String, dynamic>{'pv': pv, 'avg': avg, 'msn': msn},
    ];
  }

  /// Write the getImages slot exactly as otq_get_images_2 does: BOTH halves,
  /// each photo wrapped `aum__<path>__mua`, joined by separator[5] (◇).
  ///
  /// ★ `.controller.text` last, and that is load-bearing: assigning it is what
  /// notifies the pad's photo listener, which is the whole 0a mechanism.
  void writePhotoSlot(List<String> paths) {
    txfControllerCheck(scr, photoSlot);
    final String v = paths
        .map((String p) => '$localImagePrefix$p$localImagePostfix')
        .join(whiteDiamond);
    txfController[scr]![photoSlot]!.finalData = v;
    txfController[scr]![photoSlot]!.controller.text = v;
  }

  /// The same slot, written RAW — no `aum__` wrapping.
  ///
  /// Two real shapes reach the pad this way and neither is a local file: an
  /// EDIT page seeds the slot from `currentValue`, where a previously synced
  /// photo is a plain https Storage URL, and a cancelled camera leaves
  /// [emptyImageUrl] (`aum__--__mua`).
  void writeRawPhotoSlot(String value) {
    txfControllerCheck(scr, photoSlot);
    txfController[scr]![photoSlot]!.finalData = value;
    txfController[scr]![photoSlot]!.controller.text = value;
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
  void seedSlots({String digits = '5'}) {
    txfControllerCheck(scr, digitsSlot);
    txfController[scr]![digitsSlot]!.finalData = digits;
    txfControllerCheck(scr, pos);
    txfController[scr]![pos]!.initialValue = '';
    txfController[scr]![pos]!.finalData = '';
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
    String photoPosition = '$photoSlot',
    String serialField = '',
    String blockOnSerialMismatch = 'FALSE',
    String serialText = seg6,
    String ocrPattern = '',
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
        'blockOnBackward': blockOnBackward,
        'photoPosition': photoPosition,
        // Retired by §3.2 and read by NOBODY. Present here so the acceptance
        // line "ocrPattern masih ada di config -> diabaikan diam-diam, widget
        // tidak di-drop" is actually exercised rather than assumed.
        'ocrPattern': ocrPattern,
        'serialField': serialField,
        'blockOnSerialMismatch': blockOnSerialMismatch,
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
        ].join(d),
      };

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
  // ── meter-serial-verify ───────────────────────────────────────────────────

  // Acceptance §11 line 1. RED if: the `_serialField.isEmpty` guard leaves
  // _applySerial. This is the ONLY assertion that measures "nol ML Kit
  // dipanggil"; a "no sheet appeared" assertion would pass with the OCR running
  // on every build.
  testWidgets('serialField blank never enters the OCR seam',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'SOMETHING ELSE ENTIRELY';
    await t.pumpWidget(subject(component(serialField: '')));
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text('Angka di meter sekarang'), findsOneWidget);
  });

  // Acceptance §11 line 2. RED if: the
  // `digitPadNormalizeSerial(_wantSerial).isEmpty` guard is removed — the OCR
  // would run and (with an empty needle) the pad would fall to whatever
  // digitPadSerialSatisfied's empty case does, on every point in the fleet.
  testWidgets('a doc with an empty serial never enters the OCR seam',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: '');
    writePhotoSlot(<String>[photoA]);
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // RED if: the `paths.isEmpty` guard is removed. The call count alone would
  // NOT go red there (an empty loop calls nothing) — what goes red is the
  // sheet: without the guard `match` stays false and the pad declares a
  // mismatch on a point that has no photo at all.
  testWidgets('a serial with no photo yet is silent, not a mismatch',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★★ ONE pumpWidget PER TEST. Load-bearing, not style — do NOT merge the two
  // tests below back into one.
  //
  // subject() builds DigitPad with NO Key at a fixed position in the tree, and
  // DigitPadState has NO didUpdateWidget. Widget.canUpdate is therefore true on
  // a second pumpWidget: the element is updated IN PLACE and initState never
  // runs again. Every config field this feature adds is `late final`, read once
  // in initState through _spec — so a second pump carrying a DIFFERENT
  // component() silently keeps the FIRST pump's values, and every assertion
  // after it certifies nothing at all. No other test in this file pumps twice;
  // these two must not become the first.

  // RED if: digitPadParsePosition stops returning null for a blank string, or a
  // blank photoPosition acquires a "helpful" default. The photo IS in slot 3
  // here (the component() default) carrying text that would mismatch, so ANY
  // resolution other than "no slot at all" turns ocrCalls into 1 and raises the
  // sheet.
  testWidgets('a blank photoPosition is silent', (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'NOTHING USEFUL';
    await t.pumpWidget(
        subject(component(serialField: 'msn', photoPosition: '')));
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★ RED if: the `photoSlot == _position` nulling in initState is removed
  // (§6.4 M6).
  //
  // What this measures is the LISTENER, not the OCR call, and that is
  // deliberate: `ocrCalls` could NEVER catch this. _content writes
  // `ic.finalData = submit` for this pad's own slot on every build, BEFORE the
  // serial block reads photoRaw from it — so the pad's own slot can only ever
  // hold a digit string, digitPadPhotoPaths finds no aum__ wrapper in it, and
  // the OCR branch is unreachable through it whether the nulling is there or
  // not. A test that asserted only `ocrCalls == 0` would be green on both
  // sides, which is exactly the hole the r1 draft of this test carried.
  //
  // The probe is a REBUILD probe instead, and it works because this pad has
  // exactly three rebuild sources: the Obx on mapTableContent, the GetBuilder
  // id '$scrName-$position' (its OWN id), and its own setState. Writing another
  // slot's controller.text touches none of them — which is the whole reason the
  // photoPosition listener has to exist ('replacing the photo recomputes the
  // verdict' leans on the same fact from the opposite side).
  //
  // So: write THIS pad's own controller.text from outside, then pump. Correct
  // behaviour = no listener = no rebuild = _content never re-runs = finalData
  // keeps the '' the first build wrote. Delete the nulling and the listener
  // attaches to the pad's own controller, the write notifies it, setState
  // rebuilds, _content writes finalData = '12345' AND a spike verdict raises
  // the sheet — two independent assertions go RED.
  testWidgets('a self-referential photoPosition attaches no listener',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    await t.pumpWidget(
        subject(component(serialField: 'msn', photoPosition: '$pos')));
    await t.pumpAndSettle();
    // The first build wrote '' (a 5-hole buffer is an incomplete reading).
    expect(txfController[scr]![pos]!.finalData, '');

    // The write otq_get_images_2 would make — aimed, by THIS config, at the
    // pad's own slot. '12345' is a complete 5-box buffer, so a rebuild would be
    // unmistakable in finalData.
    txfController[scr]![pos]!.controller.text = '12345';
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    // ★ THE assertion. '' means _content did not re-run, which means nothing
    // was listening to this pad's own controller.
    expect(txfController[scr]![pos]!.finalData, '');
    expect(noPumpException(), isTrue);
  });

  // Acceptance §11 line 3. RED if: digitPadSerialSatisfied's result is
  // inverted, or the aum__ unwrapping in digitPadPhotoPaths is dropped — the
  // seam would then be handed `aum__/…__mua` instead of a real path, which the
  // `ocrPaths` assertion pins.
  testWidgets('the right meter photo shows nothing at all',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'PDAM\nA21 4471908\n039010\nBudi -6.29,106.66';
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();

    expect(ocrCalls, 1);
    expect(ocrPaths, <String>[photoA]);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // Acceptance §11 lines 4 + 11 in one. Also spec §5's sketch: the sheet rises
  // on the PHOTO alone, with the digit boxes still empty.
  // RED if: the `_wantSheetKey.isEmpty` widening in _applySheet is reverted
  // (the old `_wantSheetValue.isEmpty` re-arm would swallow this raise), or if
  // {serial} is filled from the OCR text instead of the doc.
  testWidgets('the wrong meter raises segment 6 with the RECORDED serial',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'PDAM\nA21 4471999\n041220';
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();

    expect(ocrCalls, 1);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    // ★ The RECORDED serial, never the one OCR read (which was A21 4471999).
    expect(find.text(seg6Resolved), findsOneWidget);
    // The digit boxes were never touched.
    expect(txfController[scr]![pos]!.finalData, '');
  });

  // Acceptance §11 line 11: zero hardcoded strings. RED if: any part of segment
  // 6 is baked into the widget.
  testWidgets('segment 6 comes entirely from the sheet',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      serialText: 'Seri beda: {serial}. Cek lagi.',
    )));
    await t.pumpAndSettle();

    expect(find.text('Seri beda: A21-4471908. Cek lagi.'), findsOneWidget);
    expect(find.text(seg6Resolved), findsNothing);
  });

  // §3.1 "segmen kosong = fitur itu diam".
  // RED if: the `sheetText.isEmpty` guard leaves digitPadShouldRaiseAnySheet.
  testWidgets('a blank segment 6 silences the serial verdict entirely',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    await t.pumpWidget(
        subject(component(serialField: 'msn', serialText: '')));
    await t.pumpAndSettle();

    expect(ocrCalls, 1); // the check still RAN
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // Acceptance §11 line 5, ALL THREE halves of it: the save button lives,
  // segment 13 is offered, AND "bacaan tersimpan apa adanya" — the reading the
  // officer already typed survives the mismatch untouched.
  //
  // RED if: the `_blockOnSerialMismatch &&` term is dropped from serialBlock
  // (the save button would die on a warning-only config, which is the v1 shape
  // spec §10 mandates), or if anything on the serial path writes back to the
  // pad's own slot — finalData is the value saveSend actually submits, and it
  // is born '--' here, so "the reading survived" is not self-evident and has to
  // be asserted.
  //
  // ★ The reading is SEEDED into controller.text before the pump, never typed
  // after it. _content re-establishes the buffer from controller.text on every
  // build (which is how an edit page arrives with a reading already in place),
  // and typing is not an option here: the mismatch sheet is already up by the
  // time the pad is interactive, and showModalBottomSheet's barrier absorbs
  // every tap aimed at the numpad underneath — the same trap documented on
  // 'correcting the reading restores savesend to initialIsEnabled'.
  //
  // 01100 -> submit '1100'. 1100 > pv 1000 and delta 100 <= avg 30 * 4, so the
  // numeric verdict is `sane` and the serial keeps the sheet (digitPadSerialOwnsSheet).
  testWidgets('blockOnSerialMismatch FALSE warns but never disables savesend',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    txfController[scr]![pos]!.controller.text = '01100';
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'FALSE')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    // The serial message, not the sane verdict, is what took the sheet.
    expect(find.text(seg6Resolved), findsOneWidget);
    // Segment 13 present: the officer can accept and move on.
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(find.text('Perbaiki dulu'), findsNothing);
    // ★ "bacaan tersimpan apa adanya" — the typed reading is intact in the slot
    // saveSend composes from, warning or no warning.
    expect(txfController[scr]![pos]!.finalData, '1100');
  });

  // Acceptance §11 line 6. RED if: `|| serialBlock` is dropped from EITHER
  // _scheduleGate (savesend stays alive) or verdictBlock (segment 13 comes
  // back and segment 5 disappears). Two independent mutations, both caught.
  testWidgets('blockOnSerialMismatch TRUE kills savesend and hides segment 13',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsNothing);
    // Segment 5 appears twice: the sheet's blocked foot and the card footer.
    expect(find.text('Perbaiki dulu'), findsNWidgets(2));
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
  });

  // ★★ Acceptance §11 line 8, AND the only in-harness proof of the 0a
  // mechanism. Nothing touches the pad here — the photo slot is written the way
  // otq_get_images_2 writes it, and only the LISTENER can turn that into a
  // rebuild.
  // RED (two independent mutations):
  //   * remove the photoPosition listener      -> ocrCalls stays 1, no sheet
  //   * drop photoRaw from the _ocrKey memo    -> ocrCalls stays 1, no sheet
  testWidgets('replacing the photo recomputes the verdict', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'PDAM A21 4471908 039010'; // the RIGHT meter
    ocrTextByPath[photoB] = 'PDAM A21 4471999 041220'; // a DIFFERENT meter
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();
    expect(ocrCalls, 1);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    // The officer retakes the photo. No tap on the pad, no rebuild forced.
    writePhotoSlot(<String>[photoB]);
    await t.pumpAndSettle();

    expect(ocrCalls, 2);
    expect(ocrPaths, <String>[photoA, photoB]);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.text(seg6Resolved), findsOneWidget);
  });

  // ★ Multi-photo. RED if: the per-photo loop is "improved" into one
  // concatenated string — the two halves below would then join into
  // A214471908 and a WRONG meter would read as correct. This is the single
  // most dangerous simplification in the feature.
  testWidgets('a serial straddling two photos is NOT a match',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA, photoB]);
    ocrTextByPath[photoA] = 'PDAM A21-44';
    ocrTextByPath[photoB] = '71908 SNI';
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();

    expect(ocrCalls, 2);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
  });

  // RED if: the loop stops short-circuiting, or stops scanning past photo 1.
  testWidgets('any photo containing the serial is a match',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA, photoB]);
    ocrTextByPath[photoA] = 'BLURRED';
    ocrTextByPath[photoB] = 'A21 4471908';
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();

    expect(ocrCalls, 2);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
  });

  // ★ The FAIL-OPEN branch, and it is a ratified product decision (spec §10
  // "blokir waktu OCR gagal baca apa pun" is Not Doing; product #17), NOT the
  // repo's usual fail-closed gate rule.
  // RED if: the catch in _applySerial sets _serialMatch = false instead of
  // returning — a device without the ML Kit model would then brick every
  // MeterRead page that ships blockOnSerialMismatch:"TRUE".
  testWidgets('an OCR throw is silent and never blocks, even with block TRUE',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrThrows = true;
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(ocrCalls, 1);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text('Perbaiki dulu'), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(noPumpException(), isTrue);
  });

  // ★ Precedence (spec §12 / interview decision 5). RED if:
  // digitPadSerialOwnsSheet loses its verdict terms — segment 6 would take the
  // sheet and the backward reading, the ONE thing product #21 exists for, would
  // be hidden behind a false-positive-prone serial warning.
  testWidgets('a backward reading beats the serial message for the sheet',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    // ★ SEEDED before the pump, never typed after it. The serial mismatch
    // raises its sheet on the FIRST frame — the digit boxes are still empty,
    // which is precisely spec §5's sketch — and from then on
    // showModalBottomSheet's barrier absorbs every tap aimed at the numpad
    // underneath, so a tap loop here lands on nothing at all. Same trap and
    // same workaround as the sibling test 'blockOnSerialMismatch FALSE warns
    // but never disables savesend': _content re-establishes the buffer from
    // controller.text on every build. 00900 -> submit '900' < pv 1000.
    txfController[scr]![pos]!.controller.text = '00900';
    await t.pumpWidget(subject(component(
      serialField: 'msn',
      blockOnBackward: 'TRUE',
    )));
    await t.pumpAndSettle();

    // Segment 4, not segment 6 — and TWICE, the inline card banner plus the
    // sheet, which is the count both pre-existing backward tests in this file
    // already assert.
    expect(find.text('Angka lebih kecil dari 1000'), findsNWidgets(2));
    expect(find.text(seg6Resolved), findsNothing);
    expect(find.byKey(const ValueKey<String>('digitPadSheetAccept')),
        findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
  });

  // Acceptance §11 line 10 — a retired key must be inert, not fatal.
  // RED if: anyone "implements" ocrPattern, or SduiSpec starts rejecting
  // unknown keys.
  testWidgets('a leftover ocrPattern in the config is ignored silently',
      (WidgetTester t) async {
    seedSlots();
    seedMeterDocWithSerial(msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'A21 4471908';
    await t.pumpWidget(subject(
        component(serialField: 'msn', ocrPattern: r'\d{4,9}')));
    await t.pumpAndSettle();

    expect(find.text('Angka di meter sekarang'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('digitPadBox-0')), findsOneWidget);
    expect(ocrCalls, 1);
    expect(noPumpException(), isTrue);
  });

  // ── r2: SEQUENCES ────────────────────────────────────────────────────────
  //
  // Every one of the 45 tests r1 added asserts a SINGLE state, which is exactly
  // why W1 and W2 survived a green 154. A test that pumps once and asserts one
  // condition cannot see either defect: both live in what the SECOND event does
  // to the memory the FIRST one left behind.

  // ★★ r1 W1, measured at runtime by the orchestrator as FIVE modal sheets for
  // ONE mismatch. §12 concedes a mismatch is COMMON (an unreadable photo reads
  // as one), so this is the normal path, and a sheet on every keystroke cycle
  // manufactures precisely the habit §4c rule 1 exists to prevent — the officer
  // learns to close the sheet unread, and the BACKWARD verdict goes with it.
  //
  // RED if: digitPadShouldRaiseAnySheet compares the latch WHOLE again, or its
  // serial branch goes back to an unconditional `return true`. The failure
  // lands on the assertion right after the type loop.
  testWidgets(
      'a live serial mismatch raises the sheet ONCE, however the reading '
      'changes', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();
    // Spec §5's sketch: the sheet rises on the PHOTO alone, boxes still empty.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(ocrCalls, 1);

    // Segment 13 closes the sheet and nothing else. From here the modal barrier
    // is gone and the numpad is tappable again — which is the only reason this
    // test can type at all (see the seed-before-pump note on its siblings).
    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    // 01100 -> submit '1100'. 100 over pv 1000 is well inside avg 30 * 4, so
    // the numeric verdict is `sane` and the serial keeps the sheet.
    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    // ★ RAISE #2 on r1: completing the buffer minted a new composite key.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    await tapBack(t);
    await t.pumpAndSettle();
    // ★ RAISE #3 on r1: an incomplete buffer put the key back to '|<ocr>'.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    await tapKey(t, '0');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    // Neither the photo nor the serial changed, so the verdict was computed
    // exactly once.
    expect(ocrCalls, 1);
    // The pad is alive and showing the NUMERIC verdict inline, which is the
    // whole point of keeping the serial message on the sheet only (spec §5).
    //
    // ★ There is deliberately no `digitPadVerdictRow` to assert here: that
    // compact row is only tappable for spike/backward, and the serial verdict
    // has no inline surface at all — measured, not assumed. Its consequence is
    // out of scope for this round and recorded in the walkthrough.
    expect(find.text('Masuk akal — selisih 100 m³ dari 1000'), findsOneWidget);
    expect(txfController[scr]![pos]!.finalData, '1100');
  });

  // ★ The residual the OBVIOUS two-line W1 fix would have left behind. With one
  // latch entry that keys on whichever axis raised last, a spike between two
  // serial states evicts the serial memory and backspacing re-raises the sheet
  // the officer closed two taps ago.
  //
  // Two sheets here are CORRECT — one serial, one spike. A third is the bug.
  // RED if: digitPadNextSheetLatch stops keeping the previous serial half
  // through a numeric raise.
  testWidgets('a spike sheet between two serial states does not re-open the '
      'dismissed serial sheet', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    await t.pumpWidget(subject(component(serialField: 'msn')));
    await t.pumpAndSettle();
    // Sheet #1 — the serial.
    expect(find.text(seg6Resolved), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();

    // 09999 -> submit '9999'. 8999 over pv 1000 is far past avg 30 * 4, so the
    // NUMERIC verdict takes the sheet back (digitPadSerialOwnsSheet).
    for (final String k in <String>['0', '9', '9', '9', '9']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    // Sheet #2 — the spike, NOT the serial.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.text(seg6Resolved), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();

    // The officer starts correcting the number the spike sheet told him to fix.
    await tapBack(t);
    await t.pumpAndSettle();

    // ★ THE assertion: no third sheet. The serial verdict has not changed, and
    // the photo has not changed, so there is nothing new to say.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(ocrCalls, 1);
  });

  // ★★ r1 W2. _ocrKey and _serialMatch used to be State-local while the latch
  // they feed was static — and AnyPage renders through a ListView.builder with
  // no keep-alive (any_page.dart), so scrolling the pad off screen DESTROYS the
  // State. On the way back the memo was empty, the sheet key collapsed to '',
  // _applySheet took its re-arm branch and DELETED the latch, and the dismissed
  // sheet came back as soon as the re-run OCR landed.
  //
  // Unmounting and re-pumping is that scroll: an element removed from the tree
  // is disposed, and the third pump builds a brand-new DigitPadState with
  // initState run again. `find.byType(DigitPad) findsNothing` in the middle is
  // what keeps this test from passing vacuously if the tree ever stops being
  // torn down.
  //
  // RED if: _ocrKey / _serialMatch go back to being State fields (both
  // assertions fail — the sheet returns AND the OCR runs a second time).
  testWidgets('a State re-creation neither re-raises the dismissed sheet nor '
      're-runs the OCR', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    final Map<String, dynamic> c = component(serialField: 'msn');
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(ocrCalls, 1);

    await t.tap(find.byKey(const ValueKey<String>('digitPadSheetAccept')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);

    // Scrolled away: SingleChildScrollView -> SizedBox is a runtimeType change,
    // so the subtree is unmounted rather than updated in place.
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await t.pumpAndSettle();
    expect(find.byType(DigitPad), findsNothing);

    // Scrolled back.
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    // ★ The second half of W2, and the one with a device cost: a fresh native
    // recogniser per return, plus (with blockOnSerialMismatch TRUE) savesend
    // re-enabled for the whole in-flight window.
    expect(ocrCalls, 1);
    expect(noPumpException(), isTrue);
  });

  // ── r2 W4: the memo may hold ANSWERS, never a claim ──────────────────
  //
  // r2 claimed the memo key BEFORE the await and wrote the answer after it, so
  // a pass abandoned in between left `ocrKey = K, match = null` in a STATIC map
  // and every later pass returned at `key == _ocrKey`. No sheet, no gate, no
  // log, for that photo, until a new photo or a navigation.
  //
  // The `a State re-creation ...` test above CANNOT see this: it lets the OCR
  // complete before the State is disturbed. The two below hold the seam open
  // with a Completer and destroy the State while the read is still in flight,
  // which is the real field sequence — AnyPage's ListView.builder destroys the
  // State on a scroll, and the officer scrolls in exactly the seconds after the
  // photo is taken, i.e. inside the 100-500 ms round-trip.
  //
  // RED if: the memo write moves back below `if (!mounted) return;`, or the key
  // is claimed in the memo before the await again.
  testWidgets(
      'a State destroyed MID-read still records the verdict, and the next '
      'mount raises it', (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    final Completer<void> gate = Completer<void>();
    ocrGates[photoA] = gate;
    final Map<String, dynamic> c =
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE');
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();
    // Dispatched and PENDING. There is no verdict yet, so no sheet and — the
    // §12 residual, recorded not fixed — no gate either during the window.
    expect(ocrCalls, 1);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);

    // Scrolled away DURING the round-trip.
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await t.pumpAndSettle();
    expect(find.byType(DigitPad), findsNothing);

    // ML Kit answers a State that no longer exists.
    gate.complete();
    await t.pumpAndSettle();

    // Scrolled back.
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();

    // ★ THE assertion pair. On r2 this was `findsNothing` + `isTrue`: the
    // check was dead for this photo and the officer could save the wrong meter.
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(find.text(seg6Resolved), findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    // The abandoned pass's answer was KEPT, so nothing had to be recomputed.
    expect(ocrCalls, 1);
    expect(noPumpException(), isTrue);
  });

  // ★ The other half of the same wedge, and the worse half: with the key
  // claimed before the await, ONE transient ML Kit failure (a first-call model
  // init) killed the check for that photo permanently. r1 retried on the next
  // State; the memo is left untouched by the catch so that r1 behaviour is back.
  //
  // RED if: the catch writes anything into the memo, or _dispatchedOcrKey is
  // moved into the static memo (it must die with its State).
  testWidgets(
      'a MID-read throw leaves the memo re-armable: the next mount reads again',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    ocrThrows = true;
    final Completer<void> gate = Completer<void>();
    ocrGates[photoA] = gate;
    final Map<String, dynamic> c =
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE');
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();
    expect(ocrCalls, 1);

    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await t.pumpAndSettle();
    expect(find.byType(DigitPad), findsNothing);

    // The throw lands on a State that is already gone.
    gate.complete();
    await t.pumpAndSettle();

    // The transient cause is over — a real first-call model init succeeds on
    // the retry, which is the whole reason this branch must stay re-armable.
    ocrThrows = false;
    ocrGates.remove(photoA);
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();

    // ★ A SECOND read: nothing the failed pass left behind can block it.
    expect(ocrCalls, 2);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(noPumpException(), isTrue);
  });

  // ★★ Constraint 3 of the W4 fix, measured. A throw leaves the memo
  // untouched on purpose, so nothing in the STATIC store can stop a retry —
  // only the per-State _dispatchedOcrKey can. _applySerial runs from
  // _scheduleSide's post-frame pass on EVERY build (_sidePending dedupes per
  // FRAME, not per key), so on a build with no ML Kit plugin, where every pass
  // throws, dropping that marker means one native call per keystroke.
  //
  // RED if: `if (key == _dispatchedOcrKey) return;` is dropped, or the marker
  // is cleared anywhere.
  testWidgets('a build with no ML Kit plugin reads ONCE, not once per keystroke',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrThrows = true;
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();
    expect(ocrCalls, 1);

    // 01100 over pv 1000 is `sane`, so no sheet and no modal barrier: every tap
    // below lands on the numpad, and every tap is another build.
    for (final String k in <String>['0', '1', '1', '0', '0']) {
      await tapKey(t, k);
    }
    await t.pumpAndSettle();
    await tapBack(t);
    await t.pumpAndSettle();
    await tapKey(t, '0');
    await t.pumpAndSettle();

    expect(ocrCalls, 1);
    // Fail-open still holds while it is quiet (spec §10, product #17).
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  // ★★ Constraint 5 of the W4 fix, the CROSS-State half. Recording from a dead
  // State is the fix; recording BLINDLY from one is a fresh hole. Here the
  // officer scrolls away mid-read, the photo is retaken while the pad is off
  // screen, he scrolls back and the NEW photo's mismatch lands first. Only then
  // does the OLD photo's read answer — about a photo that has left the slot,
  // and it says "match". Letting that overwrite would release a gate the
  // officer is looking at, with nothing on screen to explain it.
  //
  // RED if: `live: mounted` becomes `live: true`, or _memoRecord's !live branch
  // is dropped.
  testWidgets('a dead State never overwrites a newer verdict',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'PDAM A21 4471908 039010'; // the RIGHT meter
    ocrTextByPath[photoB] = 'WRONG UNIT'; // a DIFFERENT meter
    final Completer<void> slowA = Completer<void>();
    ocrGates[photoA] = slowA;
    final Map<String, dynamic> c =
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE');
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();
    expect(ocrCalls, 1);

    // Scrolled away mid-read; the photo is retaken while the pad is gone.
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await t.pumpAndSettle();
    writePhotoSlot(<String>[photoB]);

    // Scrolled back. The new photo is read by a NEW State and answers at once.
    await t.pumpWidget(subject(c));
    await t.pumpAndSettle();
    expect(ocrCalls, 2);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);

    // The first read finally answers, on a State that no longer exists.
    slowA.complete();
    await t.pumpAndSettle();

    // A real repaint, so this is not asserted by absence. Same channel as the
    // gate-re-assert test above: a pointer event would be eaten by the sheet's
    // modal barrier, and blockOnSerialMismatch:"TRUE" hides segment 13, so
    // there is no accept button to dismiss it with either.
    Get.find<WidgetUpdateController>().update(<String>['$scr-$pos']);
    await t.pump();
    await t.pump(); // post-frame gate

    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(find.text(seg6Resolved), findsOneWidget);
    expect(ocrCalls, 2);
  });

  // ★★ Constraint 5 again, the SAME-State half — r2 spelled this guard
  // `key != _ocrKey` and no test ever drove it. Two reads are in flight inside
  // ONE State (the officer retakes the photo with the pad on screen) and the
  // OLDER one answers LAST, about a photo that has left the slot.
  //
  // RED if: `if (key != _dispatchedOcrKey) return;` above the memo write goes.
  testWidgets('an older read answering last never overwrites the newer verdict',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'PDAM A21 4471908 039010'; // the RIGHT meter
    ocrTextByPath[photoB] = 'WRONG UNIT';
    final Completer<void> slowA = Completer<void>();
    final Completer<void> slowB = Completer<void>();
    ocrGates[photoA] = slowA;
    ocrGates[photoB] = slowB;
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();
    expect(ocrCalls, 1);

    // Retaken with the pad still on screen: the SAME State dispatches a second
    // read while the first is still out.
    writePhotoSlot(<String>[photoB]);
    await t.pumpAndSettle();
    expect(ocrCalls, 2);

    // The newer read answers FIRST.
    slowB.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);

    // ... and the older one arrives after it.
    slowA.complete();
    await t.pumpAndSettle();
    Get.find<WidgetUpdateController>().update(<String>['$scr-$pos']);
    await t.pump();
    await t.pump(); // post-frame gate

    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(find.text(seg6Resolved), findsOneWidget);
    expect(ocrCalls, 2);
  });

  // ★★★ The other way to mint an entry that cannot be re-armed, and it took a
  // mutation to find: r2 also nulled `match` while LEAVING `ocrKey` set,
  // whenever a new key arrived. Follow that with a pass that never answers —
  // here the slot is replaced by an https Storage URL, which returns at
  // `paths.isEmpty` — and the entry sits there as `key K, no answer`. Bring the
  // same photo back and `key == _ocrKey` matches something empty: no sheet, no
  // gate, for a photo that is in the slot and IS the wrong meter.
  //
  // The shipped code has no partial write at all: the previous answer is left
  // alone and replaced whole, so the verdict is still there when the photo is.
  //
  // RED if: any invalidation that writes one half of the memo without the other
  // comes back (measured — restoring r2's null-the-match block leaves every
  // other test in this file green).
  testWidgets('a photo that comes back finds its verdict still there',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(pv: 1000, avg: 30, msn: serialA);
    writePhotoSlot(<String>[photoA]);
    ocrTextByPath[photoA] = 'WRONG UNIT';
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')),
        findsOneWidget);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(ocrCalls, 1);

    // The slot is re-seeded with something ML Kit cannot open, so this pass
    // ends at paths.isEmpty with no answer of its own. The gate follows the
    // SLOT, so it releases here — correctly: nothing is known about this value.
    writeRawPhotoSlot(
        'https://firebasestorage.googleapis.com/v0/b/otq/o/OTQC_a.jpg?alt=media');
    await t.pumpAndSettle();
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
    expect(ocrCalls, 1);

    // The original photo is back.
    writePhotoSlot(<String>[photoA]);
    await t.pumpAndSettle();

    // ★ Its verdict was never destroyed, so the gate is back with it and no
    // second ML Kit call was needed.
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isFalse);
    expect(find.text(seg6Resolved), findsOneWidget);
    expect(ocrCalls, 1);
  });

  // ── r2 I1 / orchestrator O1: the paths.isEmpty guard, finally pinned ──────
  //
  // Deleting `if (paths.isEmpty) return;` left the whole widget suite GREEN on
  // r1 — the guard was completely unpinned. It is NOT an equivalent mutant:
  // `ocrKey` is built from the RAW slot string, so a slot holding something ML
  // Kit cannot open is still a non-empty key and still reaches this line.
  //
  // blockOnSerialMismatch:"TRUE" here on purpose — without the guard this shape
  // kills the save button on every edit-page load with ZERO OCR having run,
  // which is the 'gate the officer cannot clear' class this widget has been
  // burned by four times.
  // RED (both tests) if: the guard is removed.
  testWidgets('an https photo URL in the slot is silent, not a mismatch',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    // What an EDIT page seeds from currentValue: already synced, so a Storage
    // URL rather than a local path.
    writeRawPhotoSlot(
        'https://firebasestorage.googleapis.com/v0/b/otq/o/OTQC_a.jpg?alt=media');
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text(seg6Resolved), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });

  testWidgets('a cancelled camera leaves emptyImageUrl, which is silent too',
      (WidgetTester t) async {
    seedSlots();
    seedPage();
    seedMeterDocWithSerial(msn: serialA);
    // `aum__--__mua` — wrapped like a real photo, but the path inside is the
    // '--' sentinel, so digitPadPhotoPaths drops it and nothing is left.
    writeRawPhotoSlot(emptyImageUrl);
    await t.pumpWidget(subject(
        component(serialField: 'msn', blockOnSerialMismatch: 'TRUE')));
    await t.pumpAndSettle();

    expect(ocrCalls, 0);
    expect(find.byKey(const ValueKey<String>('digitPadSheetFix')), findsNothing);
    expect(find.text(seg6Resolved), findsNothing);
    expect(txfController[scr]![saveSendSlot]!.isEnabled, isTrue);
  });
}

/// No uncaught exception was recorded during the last pump.
///
/// lowerCamelCase deliberately: `non_constant_identifier_names` is in the
/// analyzer baseline and §7.1 demands ZERO new findings on touched files.
bool noPumpException() =>
    TestWidgetsFlutterBinding.instance.takeException() == null;
