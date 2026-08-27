// test/get_images_required_widget_test.dart
//
// Pump tests for the GET_IMAGES `wajib` chip (spec get-images-required §2, D6).
// The component deliberately carries NO `table` key -- that is what keeps
// Firebase out of the tree.
//
// Every test prints `errorReport: Null check operator used on a null value` at
// teardown. That comes from the widget's own dispose() ->
// GeneralGetXController.deleteAllWidget on a page that never registered a
// widget entry; it is caught inside otq_get_images_2.dart, pre-existing, and
// unrelated to this change.
//
// What CANNOT be tested here: the savesend gate itself. It lives inside the RBT
// onPressed closure (ftz_row_of_button_2.dart), which needs Firebase, TimerBloc,
// transactionStore['#THEME'] and ConnectionData to reach. Every DECISION that
// closure makes is covered by test/get_images_required_support_test.dart; the
// wiring around them is not, and that gap is stated in the plan (§7 R3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/widget/otq_get_images_2.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // globalInit() does NOT run under flutter_test.
    if (!Get.isRegistered<WidgetUpdateController>()) {
      Get.put(WidgetUpdateController());
    }
    if (!Get.isRegistered<GeneralGetXController>()) {
      Get.put(GeneralGetXController());
    }
  });

  setUp(() {
    txfController.clear();
    GeneralGetXController.to.widgetData.clear();
  });

  Map<String, dynamic> component({
    Map<String, dynamic> extra = const {},
    bool withPosition = true,
  }) =>
      <String, dynamic>{
        'type': 'GET_IMAGES',
        'margin': '0,0,0,0',
        if (withPosition) 'position': 3,
        'label': 'Foto Muka Meter',
        'text': '+◆Foto muka meter belum diambil',
        'previewSize': 120,
        'camera': 1,
        'currentValue': '',
        'max': 1,
        ...extra,
      };

  Widget subject(Map<String, dynamic> c, String scrName) => MaterialApp(
        home: Scaffold(
          body: OtqGetImages2(
            key: ValueKey('$scrName-outer'),
            wKey: ValueKey('$scrName-inner'),
            component: c,
            scrName: scrName,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      );

  // RED if: the `if (isRequired)` chip block is removed, or its condition is
  // inverted (see Task 7 M15 / M18).
  testWidgets("optional:'FALSE' renders the wajib chip", (WidgetTester t) async {
    await t.pumpWidget(subject(component(extra: {'optional': 'FALSE'}), 'scr_a'));
    await t.pump();
    expect(find.text('wajib'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // RED if: the chip's condition is inverted. This is the byte-for-byte
  // backward-compat assertion for every live page (spec §2, §9).
  testWidgets('an absent optional renders NO chip', (WidgetTester t) async {
    await t.pumpWidget(subject(component(), 'scr_b'));
    await t.pump();
    expect(find.text('wajib'), findsNothing);
  });

  testWidgets("optional:'TRUE' renders NO chip", (WidgetTester t) async {
    await t.pumpWidget(subject(component(extra: {'optional': 'TRUE'}), 'scr_c'));
    await t.pump();
    expect(find.text('wajib'), findsNothing);
  });

  // Spec §5 ships the sheet template after the renderer; a half-swept workbook
  // must look exactly like today.
  testWidgets('an unresolved [OPTIONAL] renders NO chip', (WidgetTester t) async {
    await t.pumpWidget(
        subject(component(extra: {'optional': '[OPTIONAL]'}), 'scr_d'));
    await t.pump();
    expect(find.text('wajib'), findsNothing);
  });

  // RED if: the chip is inserted in a way that displaces the label or the
  // counter, or overflows the header Row.
  testWidgets('the header label and counter survive alongside the chip',
      (WidgetTester t) async {
    await t.pumpWidget(subject(component(extra: {'optional': 'FALSE'}), 'scr_e'));
    await t.pump();
    expect(find.text('FOTO MUKA METER'), findsOneWidget); // label is uppercased
    expect(find.text('0 / 1 foto'), findsOneWidget);
    expect(find.text('wajib'), findsOneWidget);
    // text segment 1 is the DIALOG message -- it must never leak into the form.
    expect(find.text('Foto muka meter belum diambil'), findsNothing);
    expect(t.takeException(), isNull);
  });

  // The chip must not appear for a component the gate will skip (plan §3.8).
  //
  // It cannot appear anyway, for a reason that has nothing to do with this
  // change: _buildContent passes `widget.component['position']` (null here)
  // into GeneralGetXController.getWidgetItem(String, int), and null is not an
  // int -- otq_get_images_2.dart throws a TypeError before painting anything.
  // That crash is PRE-EXISTING and out of scope.
  //
  // The `findsNothing` line is the REQUIREMENT. The `isA<TypeError>()` line
  // documents why it is currently free -- if someone ever null-guards
  // _buildContent, replace that second line with
  // `expect(t.takeException(), isNull);` and leave the first line alone.
  testWidgets('a required component with NO position renders no chip',
      (WidgetTester t) async {
    await t.pumpWidget(subject(
      component(withPosition: false, extra: {'optional': 'FALSE'}),
      'scr_f',
    ));
    await t.pump();
    expect(find.text('wajib'), findsNothing);
    expect(t.takeException(), isA<TypeError>());
  });
}
