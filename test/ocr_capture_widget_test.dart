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
import 'package:otonomiq/global.dart' show emptyImageUrl, emptyString;
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/widget/ocr_capture.dart';
import 'package:otonomiq/widget/ocr_capture_support.dart';

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
  });

  setUp(() {
    txfController.clear();
    OcrCapture.clearAll();
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
}
