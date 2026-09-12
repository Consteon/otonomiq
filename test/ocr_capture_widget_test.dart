// test/ocr_capture_widget_test.dart
//
// Pump tests for OCR_CAPTURE. The component deliberately carries NO `table` key
// -- that is what keeps Firebase out of the tree.
//
// What CANNOT be tested here: the camera, ML Kit, the tap screen's real photo,
// and the upload. Nothing in this file says anything about the native side.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:otonomiq/global.dart'
    show
        appCodeController,
        emptyImageUrl,
        emptyString,
        mapTableContent,
        transactionStore;
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/ocr_capture.dart';
import 'package:otonomiq/widget/ocr_capture_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // globalInit() (global.dart:656, :922) does NOT run under flutter_test.
    if (!Get.isRegistered<WidgetUpdateController>()) {
      Get.put(WidgetUpdateController());
    }
    if (!Get.isRegistered<GeneralGetXController>()) {
      Get.put(GeneralGetXController());
    }
    // filterDriverHomeDocs reads transactionStore.state.screenTx; the global is
    // `dynamic` (global.dart:530) and stays null outside globalInit, so the
    // search path would NoSuchMethod without this.
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    // `late` global (global.dart:496). Belt and braces: every compare fixture
    // below sets `vidtable`, which short-circuits resolveAppVid before it
    // reaches getTableVid.
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  setUp(() {
    txfController.clear();
    OcrCapture.clearAll();
    // A plain global RxMap: seeded rows leak between tests otherwise, and a
    // stale row under the DECOY key would silently answer a later compare.
    //
    // No `screenUIComponent` reset here (r1 I4): nothing in this file reads it,
    // and its ONE production consumer on this path -- ocrSiblingComponent
    // (ocr_capture_support.dart) -- returns null from its own try/catch when the
    // `dynamic` global is still the boot-time null.
    mapTableContent.clear();
  });

  tearDown(() {
    mapTableContent.clear();
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Map<String, dynamic> component({
    String variant = 'auto',
    String isEnabled = 'TRUE',
    int position = 4,
    String currentValue = '',
    String metaTargets = '',
    String text =
        'Foto Meteran◆Pas-in angka◆Ketuk angkanya◆Gak kebaca◆dari foto◆Stand Meter',
  }) =>
      <String, dynamic>{
        'type': 'ocr_capture',
        'variant': variant,
        'position': position,
        'ocrTargets': '7',
        'ocrPattern': r'\d{4,6}',
        'ocrType': 'number',
        'metaTargets': metaTargets,
        'guide': '4:1',
        'previewSize': 120,
        'currentValue': currentValue,
        'isEnabled': isEnabled,
        'text': text,
      };

  Widget subject(Map<String, dynamic> c, String scrName) => wrap(OcrCapture(
        component: c,
        scrName: scrName,
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      ));

  // RED if: the label stops coming from text[0], or the slot order shifts.
  testWidgets('empty state renders text[0] as the label', (WidgetTester t) async {
    await t.pumpWidget(subject(component(), 'scr_a'));
    await t.pump();
    expect(find.text('Foto Meteran'), findsOneWidget);
    // text[1] is the CAMERA hint -- it must NOT leak into the form.
    expect(find.text('Pas-in angka'), findsNothing);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
  });

  // RED if: the label row stops being skipped when text[0] is blank -- a blank
  // slot must render NOTHING, never a hardcoded Indonesian default.
  testWidgets('a blank text[0] renders no label row', (WidgetTester t) async {
    await t.pumpWidget(subject(
      component(text: '◆cam◆tap◆fail◆badge◆chip'),
      'scr_b',
    ));
    await t.pump();
    expect(find.byIcon(Icons.document_scanner_outlined), findsNothing);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
  });

  // RED if: isEnabled / run:"N:disable" stops disabling the capture affordance.
  testWidgets('isEnabled FALSE disables the capture zone', (WidgetTester t) async {
    await t.pumpWidget(subject(component(isEnabled: 'FALSE'), 'scr_c'));
    await t.pump();
    // buildDisplayComponent seeds isEnabled; a bare pump does not, so set it the
    // way the dispatcher would (build_display_component.dart:70-73).
    txfControllerCheck('scr_c', 4);
    txfController['scr_c']![4]!.isEnabled = false;
    await t.pumpWidget(subject(component(isEnabled: 'FALSE'), 'scr_c'));
    await t.pump();
    final GestureDetector g = t.widget<GestureDetector>(
      find.ancestor(
        of: find.byIcon(Icons.add_a_photo_outlined),
        matching: find.byType(GestureDetector),
      ).first,
    );
    expect(g.onTap, isNull);
  });

  // RED if: the failure banner stops reading text[3], or stops being gated on
  // the entry's `failed` flag.
  testWidgets('the failure message comes from text[3]', (WidgetTester t) async {
    const String scrName = 'scr_d';
    OcrCapture.entryOf(scrName, 4)
      ..photoUrl = 'aum__x__mua'
      ..failed = true;
    await t.pumpWidget(subject(component(), scrName));
    await t.pump();
    expect(find.text('Gak kebaca'), findsOneWidget);
  });

  // ★★★ RED if: OcrCapture.resetRev is dropped, or the Obx read is moved out of
  // build. THIS is the regression the previous round shipped: a clearData
  // WITHOUT navigation wipes the store while the stale crop stays painted and
  // tappable, writing the previous capture's values into record slots.
  testWidgets('clearAll() repaints back to the empty state',
      (WidgetTester t) async {
    const String scrName = 'scr_e';
    OcrCapture.entryOf(scrName, 4)
      ..photoUrl = 'aum__x__mua'
      ..written[7] = '12345';
    await t.pumpWidget(subject(component(), scrName));
    await t.pump();
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget); // filled zone
    expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);

    OcrCapture.clearAll(); // what ScreenSession.navReset calls
    await t.pump();

    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
  });

  // RED if: the value chips stop rendering the text[4] badge prefix, or stop
  // pairing the chip label (text[5+]) with the written value.
  testWidgets('a written target renders the badge chip', (WidgetTester t) async {
    const String scrName = 'scr_f';
    OcrCapture.entryOf(scrName, 4)
      ..photoUrl = 'aum__x__mua'
      ..written[7] = '12345';
    await t.pumpWidget(subject(component(), scrName));
    await t.pump();
    expect(find.text('dari foto · Stand Meter: 12345'), findsOneWidget);
  });

  // RED if: the '"null"' seed normalisation is removed from build() -- an
  // untouched field would submit the four-character string `null`.
  testWidgets('the literal "null" seed is normalised on every build',
      (WidgetTester t) async {
    const String scrName = 'scr_g';
    txfControllerCheck(scrName, 4);
    txfController[scrName]![4]!.finalData = 'null';
    txfController[scrName]![4]!.initialValue = 'null';
    await t.pumpWidget(subject(component(), scrName));
    await t.pump();
    expect(txfController[scrName]![4]!.finalData, '');
    expect(txfController[scrName]![4]!.initialValue, '');
  });

  // ★ W-1. RED if _attachEditWatch moves back inside the success `else`:
  // capture 1 arms the edit-watch with baseline '12345'; capture 2 (a RETAKE)
  // reads NOTHING and writes `manual`; the agent then types the reading by
  // hand. The stale listener must be gone, or that retype flips the spec-13
  // accuracy column from `manual` to `ocr_edit` -- reporting an OCR correction
  // for a capture where ML Kit returned nothing.
  testWidgets('a failed retake disarms the previous capture edit-watch',
      (WidgetTester t) async {
    const String scrName = 'scr_i';
    await t.pumpWidget(subject(component(metaTargets: '9,10'), scrName));
    await t.pump();
    final OcrCaptureState s =
        t.state<OcrCaptureState>(find.byType(OcrCapture));

    // capture 1 succeeds: position 7 <- 12345, src <- 'ocr', watch armed.
    s.applyCaptureResult(4, <int, OcrFill>{
      7: (
        display: '12345',
        finalData: '12345',
        raw: '12345',
        box: const <double>[0, 0, 10, 10],
      ),
    }, '12345');
    expect(txfController[scrName]![9]!.finalData, 'ocr');

    // capture 2 is a RETAKE that reads nothing: src <- 'manual'.
    s.applyCaptureResult(4, <int, OcrFill>{}, 'noise noise');
    expect(txfController[scrName]![9]!.finalData, 'manual');

    // the agent types the reading by hand into the OCR target.
    txfController[scrName]![7]!.controller.text = '54321';

    expect(txfController[scrName]![9]!.finalData, 'manual');
  });

  // ★ W-3. RED if hasPhoto goes back to reading the store alone: clearAll()
  // wipes the store on ANY clearData while clearData restores the slot from
  // initialValue, so the widget painted "+ add photo" over a slot that still
  // held -- and would still submit -- the photo URL, with no × to clear it.
  testWidgets('a wiped store still renders the filled zone from the slot',
      (WidgetTester t) async {
    const String scrName = 'scr_j';
    await t.pumpWidget(
        subject(component(currentValue: 'aum__x__mua'), scrName));
    await t.pump();
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

    OcrCapture.clearAll(); // what clearData -> ScreenSession.navReset calls
    await t.pump();

    // the record slot is untouched by clearAll -- it still submits the URL.
    expect(txfController[scrName]![4]!.finalData, 'aum__x__mua');
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
  });

  // ★ W-6. RED if either "no image" sentinel starts reading as a photo URL.
  // emptyImageUrl ('aum__--__mua') is what prepareImageAsLocal makes of a '--'
  // path and what a stored record carries for "no image"; accepting it as a
  // seed (initState) or as a slot value (_content) paints a filled zone with a
  // × over a photo that does not exist.
  testWidgets('the emptyImageUrl sentinel renders the empty zone, not a photo',
      (WidgetTester t) async {
    const String scrName = 'scr_m';
    await t.pumpWidget(
        subject(component(currentValue: emptyImageUrl), scrName));
    await t.pump();
    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
    // the seed was rejected, so it never reached the store either.
    expect(OcrCapture.peek(scrName, 4)?.photoUrl ?? '', '');
  });

  // ★ C-1. RED if the cancel guard goes back to `rawPath.isEmpty` alone.
  //
  // The path handed in below is emptyString ('--'), NOT '': that is what
  // acquireCamera returns on EVERY cancel exit (photo_camera.dart:742 seeds
  // [emptyString], :762 returns it, and only the accept button at :697 writes a
  // real path), and '--'.isEmpty is FALSE. A test that passed '' would stay
  // green under the broken guard and prove nothing.
  //
  // ★ WHICH assertions below actually discriminate -- read this before deleting
  // any of them as "a rendering detail". Under the reverted guard the step right
  // after it, getTemporaryDirectory(), is a platform channel that under
  // flutter_test NEVER ANSWERS (its reply can only be processed on the real
  // event loop, which the test binding's fake async never reaches). So it HANGS
  // rather than throwing: the catch does NOT run, `failed` is never set and the
  // text[3] banner never paints.
  //
  // What that leaves: `_busy` is set true at ocr_capture.dart:472 -- BEFORE the
  // guard -- and cleared only in the finally (:635), which the hang never
  // reaches. So `_busy` stays true and the spinner (:820, :872) renders forever.
  //
  //   DISCRIMINATING  -> the CircularProgressIndicator and add_a_photo_outlined
  //                      assertions. These two, and only these two, go RED when
  //                      the guard is reverted.
  //   INERT under the mutation -> `failed`, the 'Gak kebaca' banner, and the
  //                      three finalData assertions. They document the on-device
  //                      damage; they do not detect it here.
  //
  // On a device the damage IS the inert set -- _setMeta('manual', ...) overwrites
  // the previous capture's spec-13 provenance and emptyImageUrl lands in the
  // record slot. Keep them for that, but never at the cost of the two above.
  testWidgets('a cancelled camera ("--") never enters the OCR pipeline',
      (WidgetTester t) async {
    const String scrName = 'scr_k';
    await t.pumpWidget(subject(component(metaTargets: '9,10'), scrName));
    await t.pump();
    final OcrCaptureState s =
        t.state<OcrCaptureState>(find.byType(OcrCapture));

    // capture 1 read something: src <- 'ocr', target 7 <- 12345.
    s.applyCaptureResult(4, <int, OcrFill>{
      7: (
        display: '12345',
        finalData: '12345',
        raw: '12345',
        box: const <double>[0, 0, 10, 10],
      ),
    }, '12345');
    expect(txfController[scrName]![9]!.finalData, 'ocr');

    // The agent reopens the camera and backs out of it. NOT awaited on purpose:
    // once past the guard the next step is a platform channel that never
    // answers under flutter_test, so awaiting would time the suite out (10 min)
    // instead of failing it. The guarded path suspends on microtasks only, so
    // one pump completes it.
    unawaited(s.captureForTest(emptyString));
    await t.pump();

    // Idle again -- the capture RETURNED. Past the guard it would still be
    // spinning on a file that does not exist.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    expect(OcrCapture.peek(scrName, 4)!.failed, isFalse);
    expect(find.text('Gak kebaca'), findsNothing); // no failure banner
    // provenance, the OCR value and this widget's own photo slot: untouched.
    // '--' is what txfControllerCheck seeds (global2.dart:1018) -- an empty
    // slot, never emptyImageUrl.
    expect(txfController[scrName]![9]!.finalData, 'ocr');
    expect(txfController[scrName]![7]!.finalData, '12345');
    expect(txfController[scrName]![4]!.finalData, emptyString);
  });

  // ★ W-7, the companion to the failed-retake test above: that one proves the
  // watch is GONE after a failed retake, this one proves it was ever THERE.
  // RED if _attachEditWatch is deleted, no-op'd, or stops firing -- without it
  // `ocr_edit` is unreachable and the spec-13 accuracy column silently records
  // every corrected read as a clean one.
  testWidgets('a hand edit after a successful capture flips src to ocr_edit',
      (WidgetTester t) async {
    const String scrName = 'scr_l';
    await t.pumpWidget(subject(component(metaTargets: '9,10'), scrName));
    await t.pump();
    final OcrCaptureState s =
        t.state<OcrCaptureState>(find.byType(OcrCapture));

    s.applyCaptureResult(4, <int, OcrFill>{
      7: (
        display: '12345',
        finalData: '12345',
        raw: '12345',
        box: const <double>[0, 0, 10, 10],
      ),
    }, '12345');
    expect(txfController[scrName]![9]!.finalData, 'ocr');

    // the agent corrects the machine read by hand. TextEditingController is a
    // ValueNotifier, so the watch fires synchronously on assignment.
    txfController[scrName]![7]!.controller.text = '54321';

    expect(txfController[scrName]![9]!.finalData, 'ocr_edit');
  });

  // RED if: a missing position starts throwing instead of rendering the
  // standard dispatch error text.
  testWidgets('a missing position renders the error text, never throws',
      (WidgetTester t) async {
    final Map<String, dynamic> c = component()..remove('position');
    await t.pumpWidget(subject(c, 'scr_h'));
    await t.pump();
    expect(find.textContaining('position missing'), findsOneWidget);
  });

  // ── serial compare against a reference doc (ocr-serial-instant-check) ─────
  //
  // Every test below drives the SAME funnel production uses --
  // applyCaptureResult -- and asserts on RENDERED output, never by restating a
  // production expression.
  //
  // ★ WHAT A GREEN RUN HERE DOES NOT PROVE: the real Firestore subscription
  // (subscribeToMapCollection cannot reach a null firestoreDb here -- it
  // swallows the NoSuchMethodError in its own try/catch), and that `search` is
  // read RAW rather than through SduiSpec.str. Both spellings resolve the same
  // fixture, because autheniumDecode on an already-decoded string is a no-op;
  // no fixture can separate them. That one stays a code-review point.
  //
  // ★ FINDER AMBIGUITY, stated so nobody assumes uniqueness: `Icons.check` and
  // `Icons.check_circle` BOTH already exist further down ocr_capture.dart, in
  // the tap-picker dialog (_pickFromTaps' AlertDialog -- its per-candidate rows
  // and its confirm action). `findsOneWidget` on Icons.check below is exact only
  // because no fixture in this file opens that dialog: every test drives
  // applyCaptureResult directly, which is the `auto` funnel. A future test that
  // pumps the tap screen must scope its finder.
  group('serial compare', () {
    const String docVid = 'V';
    const String docCode = 'V/D/meter';
    const String serialA = 'B21-4471902';
    const String msgOne =
        'Seri di foto ({value}) tidak cocok dengan yang tercatat ({expected})';
    const String hintOne = 'Foto ulang / periksa unitnya';
    // 8 segments: 0..4 as always, 5 = the single chip label, 6 = mismatch
    // message, 7 = retake hint (text[5 + n] / text[6 + n] with n = 1).
    const String textOne = 'Foto Meteran◆Pas-in angka◆Ketuk angkanya◆'
        'Gak kebaca◆dari foto◆Stand Meter◆$msgOne◆$hintOne';
    // 9 segments for TWO targets: 5 and 6 are chip labels, so the message and
    // the hint move to 7 and 8. Nothing renumbers.
    const String textTwo = 'Foto Meteran◆Pas-in angka◆Ketuk angkanya◆'
        'Gak kebaca◆dari foto◆Stand Meter◆Kode◆$msgOne◆$hintOne';

    Map<String, dynamic> cmp({
      String compareField = 'msn',
      String blockOnMismatch = 'FALSE',
      String ocrTargets = '7',
      String table = 'D//meter',
      String search = '',
      String text = textOne,
    }) =>
        <String, dynamic>{
          'type': 'ocr_capture',
          'variant': 'auto',
          'position': 4,
          'ocrTargets': ocrTargets,
          'ocrType': 'text',
          'metaTargets': '',
          'previewSize': 120,
          'isEnabled': 'TRUE',
          'text': text,
          if (compareField.isNotEmpty) 'compareField': compareField,
          if (blockOnMismatch.isNotEmpty) 'blockOnMismatch': blockOnMismatch,
          if (table.isNotEmpty) 'table': table,
          if (table.isNotEmpty) 'vidtable': docVid,
          if (search.isNotEmpty) 'search': search,
        };

    /// The reference doc AND a decoy under the bare key ''. The decoy is not
    /// decoration: if _code ever collapses to the bare key the compare would
    /// read DECOY0000 and every ok-path assertion below flips.
    void seedDoc(String msn) {
      mapTableContent[''] = <Map<String, dynamic>>[
        <String, dynamic>{'msn': 'DECOY0000'},
      ];
      mapTableContent[docCode] = <Map<String, dynamic>>[
        <String, dynamic>{'msn': msn},
      ];
    }

    OcrFill fill(String v) =>
        (display: v, finalData: v, raw: v, box: const <double>[0, 0, 10, 10]);

    /// Mint the sibling slots buildDisplayComponent mints EAGERLY on a real
    /// page (txfControllerCheck runs for every positioned component before any
    /// widget is constructed -- digit_pad.dart documents the same invariant).
    /// Without it the compared slot does not exist at the first post-frame and
    /// the compare watch has nothing to attach to.
    void mintSlots(String scr, List<int> slots) {
      for (final int p in slots) {
        txfControllerCheck(scr, p);
      }
    }

    /// The repaint production gets from _capture's `finally` setState. The
    /// applyCaptureResult seam skips that method, so issue the same
    /// WidgetUpdateController id update ocrWriteToPosition uses. Kept explicit
    /// so these tests do not silently depend on the compare watch -- that one
    /// has its own test.
    Future<void> repaint(WidgetTester t, String scr) async {
      Get.find<WidgetUpdateController>().update(<String>['$scr-4']);
      await t.pump();
    }

    // RED if: compareField is read WITH an SduiSpec default (it can then never
    // be blank), or the banner stops being gated on the mismatch state.
    // Measured: `_spec.str('compareField', 'msn')` turns this test RED.
    //
    // The doc is present and mismatching and both message segments are
    // present -- compare is simply not configured. That is what makes this a
    // detector instead of a "nothing changed" control.
    testWidgets('compare off: value written, nothing new rendered',
        (WidgetTester t) async {
      const String scr = 'cmp_off';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      await t.pumpWidget(
          subject(cmp(compareField: '', blockOnMismatch: ''), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      expect(txfController[scr]![7]!.finalData, '99999');
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.textContaining('tidak cocok'), findsNothing);
      expect(find.text(hintOne), findsNothing);
    });

    // RED if: blockOnMismatch stops being read (a FALSE config that withholds
    // anyway), or the {value}/{expected} fill breaks.
    // Measured: dropping `_blockOnMismatch &&` from the withhold condition
    // turns this test RED.
    testWidgets('a mismatch warns and, with FALSE, still writes',
        (WidgetTester t) async {
      const String scr = 'cmp_false';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      expect(txfController[scr]![7]!.finalData, '99999');
      expect(
        find.text(
            'Seri di foto (99999) tidak cocok dengan yang tercatat ($serialA)'),
        findsOneWidget,
      );
      expect(find.text(hintOne), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    // RED if: _code drops the appVid or collapses to the bare key -- the decoy
    // row then answers the compare and this reads as a mismatch.
    // Measured: `_code = ''` plus removing the _docs early return turns this
    // test RED. Also RED if the ok tick is dropped, or if digitPadSerialMatch
    // stops being the rule (B21-4471902 vs B214471902 agree only under its
    // A-Z0-9 normalisation).
    testWidgets('an agreeing serial ticks the chip and shows no banner',
        (WidgetTester t) async {
      const String scr = 'cmp_ok';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('B214471902')}, 'x');
      await repaint(t, scr);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('dari foto · Stand Meter: B214471902'), findsOneWidget);
    });

    // RED if: the withhold stops being scoped to the compared target (slot 8
    // would be empty), if the parked read is dropped ({value} then stays
    // literal), or if the message index stops tracking the target count
    // (hardcoding text[6] reads the chip label "Kode" here).
    // Measured: all three mutations turn THIS test RED.
    testWidgets('blockOnMismatch TRUE withholds ONLY the compared target',
        (WidgetTester t) async {
      const String scr = 'cmp_block';
      mintSlots(scr, <int>[7, 8]);
      seedDoc(serialA);
      await t.pumpWidget(subject(
          cmp(blockOnMismatch: 'TRUE', ocrTargets: '7,8', text: textTwo), scr));
      await t.pump();
      t.state<OcrCaptureState>(find.byType(OcrCapture)).applyCaptureResult(
          4, <int, OcrFill>{7: fill('99999'), 8: fill('XYZ')}, 'raw');
      await repaint(t, scr);
      expect(txfController[scr]![7]!.finalData, '');
      expect(txfController[scr]![8]!.finalData, 'XYZ');
      expect(
        find.text(
            'Seri di foto (99999) tidak cocok dengan yang tercatat ($serialA)'),
        findsOneWidget,
      );
      expect(find.text('dari foto · Kode: XYZ'), findsOneWidget);
      // No chip for the withheld target: nothing was written for it.
      expect(find.textContaining('Stand Meter'), findsNothing);
    });

    // ── W-3 (code-review r1): the gate MUST be clearable ─────────────────────
    //
    // The load-bearing invariant of the whole withhold: after a block, the
    // officer's typing lands and STICKS. Nothing else in this file types while
    // blockOnMismatch is TRUE -- cmp_block never types, cmp_fix types but runs
    // with FALSE -- so the classic regression (re-applying the withhold on every
    // rebuild) survived both and the entire suite with them.
    //
    // RED if: the withhold is re-applied anywhere outside applyCaptureResult.
    // Measured with the mutant the review names -- _content clearing the
    // compared slot whenever _blockOnMismatch and the PARKED read still mismatch.
    // Measured outcome, stated exactly: cmp_block and cmp_fix (every pre-r2
    // fixture) stay GREEN, and three die -- this one plus cmp_mute and cmp_locked,
    // which assert the same "the value survives" half from their own angles.
    // This is the only fixture that reaches it by TYPING.
    testWidgets('a withheld gate clears when the officer types the recorded '
        'serial', (WidgetTester t) async {
      const String scr = 'cmp_unblock';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      await t.pumpWidget(subject(cmp(blockOnMismatch: 'TRUE'), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      // Withheld, and the parked read is what the banner names.
      expect(txfController[scr]![7]!.finalData, '');
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // otq_txf_2's onChanged order: finalData first, then the controller -- the
      // controller write is what notifies the compare watch.
      txfController[scr]![7]!.finalData = serialA;
      txfController[scr]![7]!.controller.text = serialA;
      await t.pump();

      // The officer always wins: the correction sticks and the gate is gone.
      expect(txfController[scr]![7]!.finalData, serialA);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    // RED if: the compare watch is never scheduled/attached (nothing else
    // rebuilds this widget when a sibling slot changes), or the ok tick stops
    // being tied to the value the PHOTO produced.
    // Measured: deleting the _scheduleCompareWatch() call, and separately
    // dropping the controller.text-vs-written clause from the tick, each turn
    // this test RED.
    testWidgets('a manual correction clears the warning live',
        (WidgetTester t) async {
      const String scr = 'cmp_fix';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Exactly what otq_txf_2's onChanged does: finalData first, then the
      // controller -- assigning the controller is what notifies our watch.
      txfController[scr]![7]!.finalData = serialA;
      txfController[scr]![7]!.controller.text = serialA;
      await t.pump();

      expect(find.byIcon(Icons.error_outline), findsNothing);
      // The tick belongs to the PHOTO's value; the officer's own correction
      // earns no "dari foto" tick, so the card just goes quiet.
      expect(find.byIcon(Icons.check), findsNothing);
    });

    // ★ The strongest test in this group. RED if the verdict is LATCHED
    // anywhere instead of derived every build.
    // Measured: memoising the recorded serial at capture time turns this test
    // RED (along with four others).
    testWidgets('a doc that lands AFTER the photo still warns',
        (WidgetTester t) async {
      const String scr = 'cmp_late';
      mintSlots(scr, <int>[7]);
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      // D3 fail-open: no snapshot yet -> write the value, warn about nothing,
      // block nothing.
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(txfController[scr]![7]!.finalData, '99999');

      seedDoc(serialA); // the snapshot lands; no second capture
      await t.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    // RED if: `missing` starts warning here (D4). digitPad owns that state.
    // Measured: widening cmpMismatch to "not off and not ok" turns this RED.
    testWidgets('a capture that read nothing shows text[3] and no banner',
        (WidgetTester t) async {
      const String scr = 'cmp_missing';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{}, 'noise');
      await repaint(t, scr);
      expect(find.text('Gak kebaca'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    // RED if: the literal "null" seed getInitialValue writes into an unauthored
    // slot is treated as a serial -- the card would greet the officer with a
    // mismatch on a page nobody has touched.
    // Measured: widening cmpMismatch to "not off and not ok" turns this RED
    // too, which is the same defect from the other side.
    testWidgets('the literal "null" slot seed never becomes a serial',
        (WidgetTester t) async {
      const String scr = 'cmp_null';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      txfController[scr]![7]!.finalData = 'null';
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.textContaining('tidak cocok'), findsNothing);
    });

    // RED if: `search` stops filtering, or the doc is taken off the raw list.
    // The MATCHING row is deliberately SECOND, so an unfiltered docs.first
    // answers ZZZ99999 and this reads as a mismatch.
    testWidgets('search picks the unit doc, not docs.first',
        (WidgetTester t) async {
      const String scr = 'cmp_search';
      mintSlots(scr, <int>[7]);
      mapTableContent[docCode] = <Map<String, dynamic>>[
        <String, dynamic>{'lk': 'A2', 'msn': 'ZZZ99999'},
        <String, dynamic>{'lk': 'A1', 'msn': serialA},
      ];
      await t.pumpWidget(subject(cmp(search: 'lk◼A1'), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('B214471902')}, 'x');
      await repaint(t, scr);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    // ── W2 (plan-review r1) + W-1 (code-review r1) ───────────────────────────
    //
    // Two shapes of "the reference doc carries nothing a serial can be made of",
    // one fixture, because they leave _recordedSerial at DIFFERENT statements.
    // An absent doc exits at `if (docs.isEmpty) return '';` (spec §11 "Unit
    // tanpa `msn`"); a row WITHOUT the field exits at the `?? ''`; a row whose
    // field holds the four-character STRING "null" -- getInitialValue's seed for
    // an absent value, which has reached Firestore through a form slot before --
    // walks past both and is stopped only by digitPadNormalizeSeed.
    //
    // RED if: digitPadNormalizeSeed is dropped from _recordedSerial. Phase 2
    // then compares against "NULL" (letters survive digitPadNormalizeSerial
    // intact, which is the whole reason the seed normaliser exists), the state
    // becomes `mismatch`, and the card warns about a meter that simply has no
    // serial on file. Measured.
    //
    // Phase 1's own killer is now a PAIR, and that is disclosed on purpose: with
    // the seed normalisation in place the `?? ''` is belt-and-braces --
    // (null).toString() is the literal "null", which the normaliser also strips
    // -- so dropping the `?? ''` alone no longer turns this red (measured). Both
    // guards stay: two cheap guards on a Firestore-typed read is the repo idiom,
    // and phase 1 still pins that a fieldless row is silent under whatever
    // spelling replaces them.
    testWidgets('a compared field with no usable serial stays silent',
        (WidgetTester t) async {
      const String scr = 'cmp_nofield';
      mintSlots(scr, <int>[7]);
      // Present, findable, and no `msn` anywhere on it.
      mapTableContent[docCode] = <Map<String, dynamic>>[
        <String, dynamic>{'lk': 'A1'},
      ];
      await t.pumpWidget(subject(cmp(), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      // Fail-open, ratified: the value lands, nothing is withheld, nothing warns.
      expect(txfController[scr]![7]!.finalData, '99999');
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.textContaining('tidak cocok'), findsNothing);
      expect(find.text('dari foto · Stand Meter: 99999'), findsOneWidget);

      // Phase 2: the field EXISTS and holds the string "null". Repainted the
      // same way cmp_late is -- the RxMap read inside the Obx, no second
      // capture.
      mapTableContent[docCode] = <Map<String, dynamic>>[
        <String, dynamic>{'lk': 'A1', 'msn': 'null'},
      ];
      await t.pump();
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.textContaining('tidak cocok'), findsNothing);
      expect(txfController[scr]![7]!.finalData, '99999');
    });

    // ── W3 (plan-review r1): the lean tenant sheet, §6.5.4 as a machine check ─
    //
    // `text` stops at index 5, so BOTH new segments are off the end of the
    // ◆-list while the verdict itself is a genuine mismatch. Conventions rule 3:
    // a fixed index on a diamond list is length-guarded or it throws on exactly
    // the tenants whose sheet is short.
    //
    // RED if: the _cmpVoiced term is dropped from showCmp -- an empty red
    // container with an icon and no words then renders. (That term replaced the
    // inline `cmpMessage/cmpHint` clause in r2: the withhold needs the identical
    // gate, and two copies of it could drift apart -- code-review-r1 C-1.) RED (as a THROW, not a mismatch) if _spec.text() is
    // ever swapped for a raw diamondTextToList()[5 + n]. Measured below.
    testWidgets('a lean text row renders no banner and does not throw',
        (WidgetTester t) async {
      const String scr = 'cmp_lean';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      // Six segments: 0..4 as always plus the single chip label. No text[6],
      // no text[7].
      await t.pumpWidget(subject(
          cmp(
              text: 'Foto Meteran◆Pas-in angka◆Ketuk angkanya◆'
                  'Gak kebaca◆dari foto◆Stand Meter'),
          scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      // Explicit: a RangeError off the short ◆-list would surface here.
      expect(t.takeException(), isNull);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      // The capture itself is untouched by the missing segments.
      expect(txfController[scr]![7]!.finalData, '99999');
      expect(find.text('dari foto · Stand Meter: 99999'), findsOneWidget);
    });

    // ── C-1 (code-review r1): a block with no voice does not block ────────────
    //
    // cmp_lean above is the same lean ◆-row with blockOnMismatch FALSE. THIS one
    // sets it TRUE, which is the whole finding: withholding here empties the
    // officer's serial field with no banner (showCmp false), no chip (the
    // withheld target never enters entry.written) and no text[3] (that line
    // needs entry.failed, and a fill DID exist) -- captured data discarded in
    // total silence, with no reason and no instruction. Blank segments mean this
    // line is OFF, exactly as they do for every other text slot.
    //
    // RED if: the _cmpVoiced term is dropped from the withhold -- finalData goes
    // back to ''. Measured.
    testWidgets('blockOnMismatch TRUE with no message segments still writes',
        (WidgetTester t) async {
      const String scr = 'cmp_mute';
      mintSlots(scr, <int>[7]);
      seedDoc(serialA);
      // Six segments: 0..4 plus the single chip label. No text[6], no text[7].
      await t.pumpWidget(subject(
          cmp(
              blockOnMismatch: 'TRUE',
              text: 'Foto Meteran◆Pas-in angka◆Ketuk angkanya◆'
                  'Gak kebaca◆dari foto◆Stand Meter'),
          scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      // The value survives: a silent block is the one outcome that is worse than
      // no block at all.
      expect(txfController[scr]![7]!.finalData, '99999');
      expect(find.byIcon(Icons.error_outline), findsNothing);
      // The chip is the officer's only evidence the number landed.
      expect(find.text('dari foto · Stand Meter: 99999'), findsOneWidget);
    });

    // ── W-2 (code-review r1): warn, but never brick ───────────────────────────
    //
    // isEnabled:"FALSE" on the compared target plus blockOnMismatch TRUE was an
    // unfillable field: the ONE action that clears the gate is typing into a slot
    // the officer cannot type into. digitPad's ratified serialSourceEnabled
    // doctrine applies here -- the verdict still WARNS, only the block is
    // withheld.
    //
    // ★ The flag is seeded on the SLOT, never on the component: pumpWidget skips
    // buildDisplayComponent, which is what copies isEnabled:"FALSE" into the
    // slot, and txfControllerCheck mints it `true`. A fixture that sets only the
    // component key would leave the slot live and guard nothing.
    //
    // RED if: the cmpTargetEnabled term is dropped from the withhold --
    // finalData goes back to ''. Measured.
    testWidgets('a disabled compared target warns but is never withheld',
        (WidgetTester t) async {
      const String scr = 'cmp_locked';
      mintSlots(scr, <int>[7]);
      txfController[scr]![7]!.isEnabled = false;
      seedDoc(serialA);
      await t.pumpWidget(subject(cmp(blockOnMismatch: 'TRUE'), scr));
      await t.pump();
      t
          .state<OcrCaptureState>(find.byType(OcrCapture))
          .applyCaptureResult(4, <int, OcrFill>{7: fill('99999')}, '99999');
      await repaint(t, scr);
      // Written, because withholding it here would be permanent.
      expect(txfController[scr]![7]!.finalData, '99999');
      // And the officer is still told -- just not blocked.
      expect(
        find.text(
            'Seri di foto (99999) tidak cocok dengan yang tercatat ($serialA)'),
        findsOneWidget,
      );
      expect(find.text(hintOne), findsOneWidget);
    });
  });
}
