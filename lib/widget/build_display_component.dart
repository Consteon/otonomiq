import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../api.dart';
import '../crypto/auth_crypto.dart';
import '../global.dart';
import '../global2.dart';
// import 'package:share_plus/share_plus.dart';
import '../init_values.dart';
import '../login/api/user_repository.dart';
import '../login/page/login/login_widget.dart';
import '../login/page/tos_page.dart';
import '../model/ftz_scanned_code.dart';
import '../model/input_controller.dart';
import '../redux/screen_transaction.dart';
import '../widget/all_widget.dart';
import '../widget/approver_sticky_bar.dart';
import '../widget/qr_gps.dart';
import '../widget/radio_text.dart';
import '../widget/ui_component.dart';
import 'build_display_component_support.dart';
import 'choice_button_group.dart';
import 'ctx.dart';
import 'display_qr.dart';
import 'ftz_bluetooth_printer.dart';
import 'ftz_row_of_button_2.dart';
import 'goto.dart';
import 'gps_send.dart';
import 'image_upload.dart';
import 'list_statistic_card_keyed.dart';
import 'location_detector.dart';
import 'otq_checkbox.dart';
import 'otq_dropdown_2.dart';
import 'otq_get_images_2.dart';
import 'otq_rdo_2.dart';
import 'otq_txf_2.dart';
import 'progress_bar.dart';
import 'tasklist.dart';
import 'time_presence.dart';
import 'worker_card_detail_keyed.dart';

Widget buildDisplayComponent(
  dynamic component,
  String scrName,
  UserRepository userRepository, {
  bool? dialog,
}) {
  Widget result;
  var lPad = (systemUIComponent['Mobile']['leftPad'] ?? 0.0).toDouble();
  var tPad = (systemUIComponent['Mobile']['topPad'] ?? 0.0).toDouble();
  var rPad = (systemUIComponent['Mobile']['rightPad'] ?? 0.0).toDouble();
  var bPad = (systemUIComponent['Mobile']['bottomPad'] ?? 0.0).toDouble();
  if (component['position'] != null && component['position'] is String) {
    component['position'] = getPosition(component['position']);
  }
  // final txfKey = UniqueKey();
  final txfKey = ObjectKey("$scrName-${component['position']}");
  if (component['position'] != null) {
    final int posKey = getPosition(component['position']);
    final String initValue = getInitialValue(scrName, component);
    // Capture the controller BEFORE txfControllerCheck so a first-ever build
    // (existing == null) is distinguishable from a rebuild of a field the user
    // may already have edited.
    final InputController? existing = txfController[scrName]?[posKey];
    txfControllerCheck(
      scrName,
      component['position'],
    ); // build txfController if necessary
    final InputController ctrl = txfController[scrName]![posKey]!;
    final bool isEnabled =
        (component['isEnabled']?.toString().toLowerCase() ?? 'true') != 'false';
    ctrl.isEnabled = isEnabled;
    ctrl.initialIsEnabled = isEnabled;
    // Field-loss fix (patrol report, 2026-07): this seed block used to run
    // unconditionally on EVERY buildDisplayComponent call. The Firestore proxy
    // listener (main_page.dart ~1277 -> constructAllPageElements -> buildPage)
    // rebuilds every screen on any server UI push, so an unconditional reset
    // wiped in-progress operator input mid-session. Only re-seed finalData when
    // the field is untouched (new, still equal to its seeded initialValue, or
    // holding only the uninitialised '--' sentinel); preserve a value the user
    // or a widget action has already written. initialValue is always refreshed
    // so route-change reset (clearData -> finalData = initialValue) and legit
    // server display-refresh keep working. Do NOT restore the raw
    // canInitializePage guard: it is false for every non-home page and would
    // block first-time seeding of every form field.
    if (isFieldUntouched(
      existing != null,
      existing?.finalData ?? emptyString,
      existing?.initialValue ?? '',
    )) {
      ctrl.finalData = initValue; // put initial value
    }
    ctrl.initialValue = initValue; // put initial value
  } else {
    if (component['type'].toLowerCase() == 'rbt') {
      final children = component['children'] ?? [];
      for (var childComponent in children) {
        if (childComponent['position'] != null) {
          txfControllerCheck(
            scrName,
            childComponent['position'],
          ); // build txfController if necessary
          final bool isEnabled =
              (childComponent['isEnabled']?.toString().toLowerCase() ??
                  'true') !=
              'false';
          txfController[scrName]![getPosition(childComponent['position'])]!
                  .isEnabled =
              isEnabled;
          txfController[scrName]![getPosition(childComponent['position'])]!
                  .initialIsEnabled =
              isEnabled;
        }
      }
    }
  } // end if (_component['position'] != null)

  String tip = component['type'].toString().toLowerCase();
  if (tip == 'display_images' || tip == 'displayimages') {
    // print widget
    // any changes in init value please update init_value.dart
    try {
      // txfController[scrName]![getPosition(component['position'])]!.stateObject =
      //     OtqGetImagesStateObject();
      final key = txfKey;
      result = FtzDisplayImages(
        key: key,
        component: component,
        scrName: scrName,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'number') {
    // print widget
    // any changes in init value please update init_value.dart
    try {
      // txfController[scrName]![getPosition(component['position'])]!.stateObject =
      //     OtqGetImagesStateObject();
      final key = GlobalKey<FtzAutoNumberState>();
      result = FtzAutoNumber(key: key, component: component, scrName: scrName);
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'prn') {
    // print widget
    // any changes in init value please update init_value.dart
    try {
      // txfController[scrName]![getPosition(component['position'])]!.stateObject =
      //     OtqGetImagesStateObject();
      result = FtzBluetoothPrinter(
        key: txfKey,
        component: component,
        scrName: scrName,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'multiscanqr') {
    // any changes in init value please update init_value.dart
    try {
      // txfController[scrName]![getPosition(component['position'])]!.stateObject =
      //     OtqGetImagesStateObject();
      // if (component['position'] != null) {
      //   txfControllerCheck(scrName, component['position']);
      // }
      final position = getPosition(component['position']);
      txfControllerCheck(scrName, position);
      final controller = txfController[scrName]![position]!;

      // Initialize state object if it doesn't exist. This preserves it across rebuilds.
      if (controller.stateObject == null) {
        final initialList = <ScannedCode>[]; // Start empty
        controller.stateObject = initialList;
        controller.initialStateObject =
            initialList; // Store initial state for clearing
      }

      result = MultiScanWidget(
        key: txfKey,
        component: component,
        scrName: scrName,
        onScanCompleted: (finalCodes) {
          // setState(() {
          //   _warehouseScanResults = finalCodes;
          // });
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'get_images' || tip == 'getimages') {
    // any changes in init value please update init_value.dart
    try {
      // txfController[scrName]![getPosition(component['position'])]!.stateObject =
      //     OtqGetImagesStateObject();
      result = OtqGetImages2(
        key: txfKey,
        wKey: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
        // myImages: txfController[scrName]![getPosition(component['position'])]!
        //     .stateObject,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'displaylist') {
    if (component['position'] != null) {
      final int position = getPosition(component['position']);
      txfControllerCheck(scrName, position); // Ensure controller exists
      if (canInitializePage(scrName)) {
        final String initialTable = component['table'] ?? '';
        txfController[scrName]![position]!.finalData = initialTable;
        txfController[scrName]![position]!.initialValue = initialTable;
      }
    } // end if (_component['position'] != null)
    result = DisplayList(
      key: txfKey,
      scrName: scrName,
      component: component,
      lPad: lPad,
      tPad: tPad,
      rPad: rPad,
      bPad: bPad,
    );
  } else if (tip == 'displaycard') {
    result = DisplayCard(
      key: txfKey,
      scrName: scrName,
      component: component,
      lPad: lPad,
      tPad: tPad,
      rPad: rPad,
      bPad: bPad,
    );
  } else if (tip == 'img') {
    try {
      result = Container(
        margin: EdgeInsets.only(
          top: (component['beforeSpacing'] ?? 0.0).toDouble(),
          bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
        ),
        height: (component['height'] ?? 0.0).toDouble(),
        padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
        // Always centered: the old Row honored component['alignment'] but its
        // Expanded child filled the row anyway, so alignment was inert and
        // off-center logos came from oversized image canvases. contain+Center
        // makes centering deterministic regardless of JSON or image size.
        child: Center(
          child: displayImage(
            imageUrl: component['url'] ?? defaultImage,
            cached: true,
            fit: BoxFit.contain,
          ),
        ),
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'bnr') {
    try {
      var bannerImageAspectRatio = (component['aspectRatio'] ?? 1.0).toDouble();
      var bannerAspectRatio = 1.08 / bannerImageAspectRatio;
      result = Container(
        margin: EdgeInsets.only(
          top: (component['beforeSpacing'] ?? 0.0).toDouble(),
          bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
        ),
        height: (component['width'] ?? 0.0).toDouble(),
        child: GridView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: (component['width'] ?? 0.0).toDouble(),
            childAspectRatio: bannerAspectRatio,
          ),
          children: buildBannerList(
            component['children'],
            bannerImageAspectRatio,
          ),
        ),
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'vgr') {
    try {
      double fontSize = (component['fontSize'] ?? 14.0).toDouble();
      result = Container(
        margin: EdgeInsets.only(
          top: (component['beforeSpacing'] ?? 0.0).toDouble(),
          bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
        ),
        height: ((component['width'] ?? 90.0) * component['row']).toDouble(),
        child: GridView(
          scrollDirection: Axis.vertical,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: (component['width'] ?? 90.0).toDouble(),
          ),
          children: buildGridList(component['children'], fontSize),
        ),
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'hgr') {
    try {
      double fontSize = (component['fontSize'] ?? 14.0).toDouble();
      result = Container(
        margin: EdgeInsets.only(
          top: (component['beforeSpacing'] ?? 0.0).toDouble(),
          bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
        ),
        height: ((component['width'] ?? 90.0) * component['row']).toDouble(),
        child: GridView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: (component['width'] ?? 90.0).toDouble(),
          ),
          children: buildGridList(component['children'], fontSize),
        ),
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'txf') {
    String variant = (component['variant'] ?? '').toString().toLowerCase();
    if (variant == 'commentbox') {
      result = const SizedBox.shrink();
    } else {
      result = OtqTxf2(
        key: txfKey,
        scrName: scrName,
        component: component,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    }
  } else if (tip == 'html') {
    //Html display
    try {
      if (component['data'] == null) {
        result = Text('--${component['type']}-- Error: no data');
      } else {
        result = Container(
          margin: EdgeInsets.only(
            top: (component['beforeSpacing'] ?? 0.0).toDouble(),
            bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
          ),
          padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
          child: HtmlWidget(component['data']),
          // child: const Text(
          //     'html widget temporary disabled, due to flutter_widget_from_html incompatibility with ios18'),
        );
      } // end if(component['data'] == null)
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'txt') {
    // Text display
    try {
      result = OtqTxt(
        key: txfKey,
        scrName: scrName,
        component: component,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'ctx') {
    // Switch/Checkbox with text
    try {
      final ctxKey = GlobalKey();
      result = Container(
        margin: EdgeInsets.only(
          top: (component['beforeSpacing'] ?? 0.0).toDouble(),
          bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
        ),
        padding: EdgeInsets.fromLTRB(
          lPad + (component['leftPadding'] ?? 0.0),
          tPad,
          rPad + (component['rightPadding'] ?? 0.0),
          bPad,
        ),
        child: component['left'].toString().trim().toLowerCase() == 'true'
            ? Row(
                children: <Widget>[
                  GestureDetector(
                    child: Swc(
                      key: ctxKey,
                      scrName: scrName,
                      component: component,
                    ),
                  ),
                  Container(width: 8),
                  Flexible(
                    child: GestureDetector(
                      child: Text(component['label'] ?? ""),
                    ),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  Flexible(
                    child: GestureDetector(
                      child: Text(component['label'] ?? ""),
                    ),
                  ),
                  Container(width: 8),
                  GestureDetector(
                    child: Swc(
                      key: ctxKey,
                      scrName: scrName,
                      component: component,
                    ),
                  ),
                ],
              ),
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'drd') {
    //case 'DRD': // Dropdown
    try {
      // Logic to correctly set the initial finalData in the controller
      if (component['position'] != null) {
        final position = getPosition(component['position']);
        final initValue = getInitialValue(
          scrName,
          component,
        ); // This is the display value
        String finalDataValue = initValue; // Default to display value

        // Replicate logic from OtqDropdown to find the actual data value
        final menuItems = component['menu'] ?? component['option'];
        final dataItems = component['data'];
        if (menuItems != null &&
            dataItems != null &&
            menuItems.length == dataItems.length) {
          final dataMap = Map.fromIterables(menuItems, dataItems);
          finalDataValue = dataMap[initValue] ?? initValue;
        }

        // Ensure the controller is set up correctly
        txfControllerCheck(scrName, position);
        final controller = txfController[scrName]![position]!;

        // Only set the controller's values during the initial page build
        if (canInitializePage(scrName)) {
          controller.finalData = finalDataValue; // The actual data value
          controller.initialValue = initValue; // The display value for the UI
        }
      } // end if (_component['position'] != null)
      result = OtqDropdown2(
        key: txfKey,
        scrName: scrName,
        component: component,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'rbt') {
    // Row of button
    try {
      bool isApprovalRbt = (component['children'] as List<dynamic>? ?? []).any(
        (btn) => btn is Map && btn.containsKey('actions'),
      );
      bool hasSearch =
          (component['search'] ?? '').toString().trim().toLowerCase() ==
          'sticky';
      if (isApprovalRbt || hasSearch) {
        List<String> tabs = [];
        String? defaultStatus;
        if (isApprovalRbt) {
          var screenTx = transactionStore.state.screenTx;
          if (screenTx['approval_tabs'] is List) {
            tabs = (screenTx['approval_tabs'] as List)
                .map((e) => e.toString())
                .toList();
          }
          defaultStatus = tabs.isNotEmpty ? tabs[0].toUpperCase() : 'PENDING';
        }
        ApproverStickyBar.register(
          scrName: scrName,
          component: component,
          type: isApprovalRbt ? 'approval' : 'incident',
          defaultStatus: defaultStatus,
          widgetKey: txfKey,
          dialog: dialog ?? false,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
        debugPrint(
          '[StickyRBT] register scrName="$scrName" '
          'type=${isApprovalRbt ? "approval" : "incident"} '
          'activeBarScreen="${ApproverStickyBar.activeBarScreen.value}"',
        );
        if (ApproverStickyBar.hasCommentInput(scrName)) {
          result = StickyBarSlot(scrName: scrName);
        } else {
          result = const SizedBox.shrink();
        }
      } else {
        result = FtzRowOfButton2(
          key: txfKey,
          component: component,
          scrName: scrName,
          dialog: dialog,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
      // result = Container(
      //   margin: EdgeInsets.only(
      //       top: (component['beforeSpacing'] ?? 0.0).toDouble(),
      //       bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
      //   padding: EdgeInsets.fromLTRB(
      //       lPad + (component['leftPadding'] ?? 0.0).toDouble(),
      //       tPad,
      //       rPad + (component['rightPadding'] ?? 0.0).toDouble(),
      //       bPad),
      //   child: BlocBuilder<TimerBloc, TimerState>(
      //     builder: (context, state) => ButtonBar(
      //       // alignment: MainAxisAlignment.spaceEvenly,
      //       alignment: mainAlignmentConst(component['alignment']),
      //       // (_component['alignment'] ?? 'spaceEvenly') == 'spaceEvenly'
      //       //     ? MainAxisAlignment.spaceEvenly
      //       //     : MainAxisAlignment.spaceEvenly,
      //       children: buildButtonList(
      //         context,
      //         component['children'],
      //         scrName,
      //         dialog: dialog,
      //       ),
      //     ),
      //   ),
      // );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'signup') {
    // Sign up & login
    try {
      linkPage['tos'] = const TosPage();
      result = Builder(
        builder: (BuildContext context) {
          return Container(
            margin: EdgeInsets.only(
              top: (component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
            ),
            padding: EdgeInsets.fromLTRB(
              lPad + (component['leftPadding'] ?? 0.0).toDouble(),
              tPad,
              rPad + (component['rightPadding'] ?? 0.0).toDouble(),
              bPad,
            ),
            child: LoginWidget(
              userRepository: userRepository,
              tosText: component['text1'],
              tosRoute: component['tosRoute'] ?? '_Legal',
              nextRoute: component['route'] ?? '_Invitation',
              parentContext: context,
              component: component,
            ),
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'vmenu') {
    // new component placeholder
    try {
      result = Builder(
        builder: (BuildContext context) {
          return Container(
            margin: EdgeInsets.only(
              top: (component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
            ),
            padding: EdgeInsets.fromLTRB(
              lPad + (component['leftPadding'] ?? 0.0).toDouble(),
              tPad,
              rPad + (component['rightPadding'] ?? 0.0).toDouble(),
              bPad,
            ),
            child: Column(
              children: <Widget>[
                Card(
                  child: ListTile(
                    title: Text(component['title']),
                    onTap: () {
                      if (component['route'] != null) {
                        if (component['route'].length >= 4 &&
                            component['route'].substring(0, 4).toLowerCase() ==
                                'http') {
                          openInWebView(
                            context,
                            component['route'],
                            component['title'],
                          );
                        } else {
                          var state = transactionStore.state.screenTx;
                          if (state['#REFRESH']) {
                            oldSettingUpShouldBeDeleted().then((aRes) {
                              var state = transactionStore.state;
                              var lifKey = state.screenTx['#INTERFACE_KEY'];
                              readSettings(lifKey, 1).then((_) {
                                // constructAllPageElements();
                                transactionStore.dispatch(
                                  UpdateScreenTxAction(
                                    ScreenTransaction({'#REFRESH': false}),
                                  ),
                                );
                                routeStack.push(component['route']);
                                gotoRoute(component['route']);
                                // String newRoute = component['route'];
                                // List<Widget> newElementList =
                                //     reloadPage(newRoute);
                                // rootThis.setState(() {
                                //   rootThis.pageName = newRoute;
                                //   rootThis.pageElements = newElementList;
                                //   rootThis.wait = false;
                                // });
                              });
                            });
                          } else {
                            routeStack.push(component['route']);
                            gotoRoute(component['route']);
                            // String newRoute = component['route'];
                            // List<Widget> newElementList = reloadPage(newRoute);
                            // rootThis.setState(() {
                            //   rootThis.pageName = newRoute;
                            //   rootThis.pageElements = newElementList;
                            //   rootThis.wait = false;
                            // });
                          }
                        }
                      }
                    },
                  ),
                ),
                const Divider(),
              ],
            ),
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'qr') {
    // barcode & qr placeholder
    try {
      String qrData = component['data'] ?? '-';
      switch (component['variant'] ?? 'plain') {
        case 'attend1':
          {
            qrData = crQRAttend1Enc(qrData);
          }
          break;
      }
      result = Builder(
        builder: (BuildContext context) {
          return Container(
            margin: EdgeInsets.only(
              top: (component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
            ),
            padding: EdgeInsets.fromLTRB(
              lPad + (component['leftPadding'] ?? 0.0).toDouble(),
              tPad,
              rPad + (component['rightPadding'] ?? 0.0).toDouble(),
              bPad,
            ),
            alignment: const Alignment(0.0, 0.0),
            child: DisplayQR(data: (qrData), size: (component['size'] ?? 200)),
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'rtf') {
    // Radio Button Text Field
    Key rKey = UniqueKey();
    Key tKey = UniqueKey();
    inputInt[rKey] = -1;
    inputTxt[tKey] = component['currentValue'];

    if (txfController[scrName]![component['position']] == null) {
      txfController[scrName]![component['position']] = InputController(
        component['position'],
        TextEditingController(text: inputTxt[tKey]),
        component['currentValue'] ?? '',
        emptyString,
      );
    } else {
      txfController[scrName]![component['position']]!.controller.text =
          component['currentValue'] ?? "";
      txfController[scrName]![component['position']]!.finalData = emptyString;
      txfController[scrName]![component['position']]!.initialValue =
          component['currentValue'] ?? "";
    } // end if (txfController[scrName]![_component['position']] == null)
    result = RadioText(
      key: tKey,
      scrName: scrName,
      component: component,
      txtKey: tKey,
      radKey: rKey,
    );
  } else if (tip == 'rdo' || tip == 'rad') {
    // rad = deprecated
    // radio button
    result = OtqRdo2(
      key: txfKey,
      scrName: scrName,
      component: component,
      lPad: lPad,
      tPad: tPad,
      rPad: rPad,
      bPad: bPad,
    );
  } else if (tip == 'invitation') {
    try {
      Key rKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return Invitation(key: rKey, scrName: scrName, component: component);
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'img_upload') {
    // choose file pick from gallery or camera then save to storage bucket
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return Container(
            margin: EdgeInsets.only(
              top: (component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
            ),
            padding: EdgeInsets.fromLTRB(
              lPad + (component['leftPadding'] ?? 0.0).toDouble(),
              tPad,
              rPad + (component['rightPadding'] ?? 0.0).toDouble(),
              bPad,
            ),
            child: ImageUpload(
              key: iKey,
              component:
                  component, // imageType, folder, filename, route, position
              scrName: scrName,
            ),
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'qr_gps') {
    // scan QR & detect location
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return QrGps(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'checker') {
    // scan user qr with verification in table and photo
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return FtzChecker(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'time_presence') {
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return TimePresence(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'location_detector') {
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return LocationDetector(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'progress_bar') {
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return ProgressBar(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
            lPad: lPad,
            rPad: rPad,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'tasklist') {
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return Tasklist(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
            lPad: lPad,
            rPad: rPad,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'choice_button_group') {
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return ChoiceButtonGroup(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            lPad: lPad,
            tPad: tPad,
            rPad: rPad,
            bPad: bPad,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'selectable_btn') {
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return SelectableBtn(
            key: iKey,
            component: component,
            scrName: scrName,
            lPad: lPad,
            tPad: tPad,
            rPad: rPad,
            bPad: bPad,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'location') {
    // Location QR with location verification and selfie
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return AttendQrGpsSelfie(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'doc_viewer' || tip == 'docviewer') {
    // Inline PDF viewer
    try {
      result = Builder(
        builder: (BuildContext context) {
          return DocViewer(key: txfKey, component: component, scrName: scrName);
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'doc_download' || tip == 'docdownload') {
    // Download button — fetch URL to device, present share sheet.
    try {
      result = Builder(
        builder: (BuildContext context) {
          return DocDownload(
            key: txfKey,
            component: component,
            scrName: scrName,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'pdf_view') {
    // Pdf
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return PdfViewer(key: iKey, component: component, scrName: scrName);
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'gps_send') {
    // GPS location send
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return GpsSend(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'horizontal_icon') {
    try {
      List<Widget> iconList = [];
      int childrenNum = component['children'].length ?? 0;
      for (int i = 0; i < childrenNum; i++) {
        late Widget theIcon;
        var iconDefinition = component['children'][i];
        Key iconKey = GlobalKey();
        switch (iconDefinition['type'].toString().toLowerCase()) {
          case 'checker':
            theIcon = FtzChecker(
              key: iconKey,
              component: component['children'][i],
              scrName: scrName,
              single: true,
            );
            break;

          case 'share':
            // disabled because of share_plus incompatibility with ios18
            // Share.share(component['children'][i]['message'] ?? '--',
            //     subject: component['children'][i]['subject'] ?? '');
            // if (routeExist(component['children'][i]['route'])) {
            //   String pageToGo = component['children'][i]['route'] ?? scrName;
            //   routeStack.push(pageToGo);
            //   gotoRoute(pageToGo);
            // }
            break;

          case 'location':
            theIcon = AttendQrGpsSelfie(
              key: iconKey,
              component: component['children'][i],
              scrName: scrName,
              single: false,
            );
            break;

          case 'gps_send':
            theIcon = GpsSend(
              key: iconKey,
              component: component['children'][i],
              scrName: scrName,
              single: false,
            );
            break;

          case 'pdf_view':
            theIcon = PdfViewer(
              key: iconKey,
              component: component['children'][i],
              scrName: scrName,
            );
            break;

          case 'goto':
            theIcon = Goto(
              key: iconKey,
              component: component['children'][i],
              scrName: scrName,
              single: false,
            );
            break;

          default:
            theIcon = disabledIcon(
              component['children'][i]['url'],
              component['children'][i]['text'],
              (component['children'][i]['fontSize'] ?? 14.0).toDouble(),
            );
        } // end switch
        iconList.add(theIcon);
      } // end for
      result = Container(
        margin: EdgeInsets.only(
          top: (component['beforeSpacing'] ?? 0.0).toDouble(),
          bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
        ),
        height: ((component['width']) ?? 90.0).toDouble(),
        child: GridView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: ((component['width'] + 30) ?? 130.0).toDouble(),
            crossAxisSpacing: 1.0,
            // mainAxisSpacing: 1.0,
          ),
          children: iconList,
        ),
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'goto') {
    // Goto widget
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return Goto(
            key: iKey,
            component:
                component, // imageType, folder, filename, route, position
            scrName: scrName,
            single: true,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'checkbox') {
    // deprecated
    // checkbox widget
    try {
      Key iKey = GlobalKey();
      inputTxt[iKey] = component['data'] ?? "FALSE";
      if (component['position'] != null) {
        //= true => _component['variant'] = 'newPin'

        if (component['position'] != null) {
          txfControllerCheck(
            scrName,
            component['position'],
          ); // build txfController if necessary
          if (canInitializePage(scrName)) {
            txfController[scrName]![component['position']]!.controller.text =
                component['data'] ?? "FALSE";
            txfController[scrName]![component['position']]!.finalData =
                emptyString;
            txfController[scrName]![component['position']]!.initialValue =
                (component['data'] ?? "FALSE").toString().toUpperCase();
          }
        } // end if (_component['position'] != null)

        // if (txfController[scrName]![component['position']] == null) {
        //   txfController[scrName]![component['position']] = InputController(
        //       component['position'],
        //       TextEditingController(text: inputTxt[iKey]),
        //       component['data'].toString().toUpperCase(),
        //       emptyString);
        // } else {
        //   txfController[scrName]![component['position']]!.controller.text =
        //       component['data'] ?? "FALSE";
        //   txfController[scrName]![component['position']]!.finalData =
        //       emptyString;
        //   txfController[scrName]![component['position']]!.initialValue =
        //       (component['data'] ?? "FALSE").toString().toUpperCase();
        // } // end if (txfController[scrName]![_component['position']] == null)
      }
      result = Builder(
        builder: (BuildContext context) {
          return OtqCheckbox(
            key: iKey,
            component: component,
            scrName: scrName,
            lPad: lPad,
            tPad: tPad,
            rPad: rPad,
            bPad: bPad,
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'switch') {
    // checkbox widget
    try {
      result = OtqSwitch(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'list_item_card') {
    try {
      result = ListItemCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'list_card') {
    try {
      result = ListCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'detail_card') {
    try {
      result = DetailCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'stat_card_row') {
    try {
      result = StatCardRow(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'list_action_card') {
    try {
      // Seed txfController for note positions referenced in actionMeta so
      // saveSend finds them when resolving ◁N▷.
      final String rawActionMeta = (component['actionMeta'] ?? '')
          .toString()
          .trim();
      if (rawActionMeta.isNotEmpty) {
        final String decoded = autheniumDecode(rawActionMeta) ?? rawActionMeta;
        for (final part in decoded.split('\u{25C6}')) {
          final List<String> segs = part.trim().split('\u{25FC}');
          if (segs.length > 2) {
            final int? notePos = int.tryParse(segs[2].trim());
            if (notePos != null) {
              txfControllerCheck(scrName, notePos);
            }
          }
        }
      }
      result = ListActionCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'list_multiple_panel_card') {
    try {
      result = ListMultiplePanelCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'list_statistic_card') {
    try {
      final String lscVariant = (component['variant'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (lscVariant == 'keyed') {
        result = ListStatisticCardKeyed(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else {
        result = ListStatisticCard(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'worker_card_detail') {
    try {
      final String wcdVariant = (component['variant'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (wcdVariant == 'keyed') {
        result = WorkerCardDetailKeyed(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else {
        result = WorkerCardDetail(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'item_card_detail') {
    try {
      result = ItemCardDetail(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'timeline') {
    try {
      final String tlVariant = (component['variant'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (tlVariant == 'periodic') {
        result = TimelinePeriodic(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else if (tlVariant == 'ledger') {
        result = TimelineLedger(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else {
        result = Timeline(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'stepper') {
    try {
      result = StepperWidget(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'new') {
    // new component placeholder
    try {
      result = Builder(
        builder: (BuildContext context) {
          return Container(
            margin: EdgeInsets.only(
              top: (component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (component['afterSpacing'] ?? 0.0).toDouble(),
            ),
            padding: EdgeInsets.fromLTRB(
              lPad + (component['leftPadding'] ?? 0.0).toDouble(),
              tPad,
              rPad + (component['rightPadding'] ?? 0.0).toDouble(),
              bPad,
            ),
            child: const SizedBox(width: 0.0, height: 0.0), // put child here
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
  } else if (tip == 'notice_bar') {
    try {
      result = NoticeBar(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'scanner') {
    try {
      result = Scanner(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'nfc_reader') {
    try {
      result = NfcReader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'route_progress_header') {
    try {
      result = RouteProgressHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'precondition_gate_card') {
    try {
      result = PreconditionGateCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'inventory_bucket_card') {
    try {
      result = InventoryBucketCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'driver_stop_card') {
    try {
      result = DriverStopCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'nav_action_card') {
    try {
      result = NavActionCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'vehicle_custody_header') {
    try {
      result = VehicleCustodyHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'task_manifest_list') {
    try {
      result = TaskManifestList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'circulation_summary') {
    try {
      result = CirculationSummary(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_step_header') {
    try {
      result = CustodyStepHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_count_list') {
    try {
      result = CustodyCountList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_count_submit') {
    try {
      result = CustodyCountSubmit(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_reveal') {
    try {
      result = CustodyReveal(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_confirmed_list') {
    try {
      result = CustodyConfirmedList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_discrepancy_list') {
    try {
      result = CustodyDiscrepancyList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'custody_event_submit') {
    try {
      result = CustodyEventSubmit(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'closing_context_rail') {
    try {
      result = ClosingContextRail(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'route_feed_header') {
    try {
      result = RouteFeedHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'task_feed_list') {
    try {
      result = TaskFeedList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'workspace_header') {
    try {
      result = WorkspaceHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'item_execution_list' || tip == 'itemexecutionlist') {
    try {
      result = ItemExecutionList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'item_execution_submit' || tip == 'itemexecutionsubmit') {
    try {
      result = ItemExecutionSubmit(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'signature_pad') {
    try {
      result = SignaturePad(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'evidence_row' || tip == 'evidencerow') {
    try {
      result = EvidenceRow(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'return_header') {
    try {
      result = ReturnHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'vehicle_cargo_summary') {
    try {
      result = VehicleCargoSummary(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'vehicle_feed_header') {
    try {
      result = VehicleFeedHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'vehicle_feed_list') {
    try {
      result = VehicleFeedList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'adminactivetriplist') {
    try {
      result = AdminActiveTripList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'adminupcomingtasklist') {
    try {
      result = AdminUpcomingTaskList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'adminoutstandinglist') {
    try {
      result = AdminOutstandingList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'admin_coordination_header') {
    try {
      result = AdminCoordinationHeader(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'coordination_signal_list') {
    try {
      result = CoordinationSignalList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'signal_list') {
    try {
      result = SignalList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'executor_designate_card') {
    try {
      result = ExecutorDesignateCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'taskitembuilder' || tip == 'task_item_builder') {
    try {
      result = TaskItemBuilder(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'task_draft_summary') {
    try {
      result = TaskDraftSummary(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'task_draft_info') {
    try {
      result = TaskDraftInfo(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'task_create_submit') {
    try {
      result = TaskCreateSubmit(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'nota_create_submit') {
    try {
      result = NotaCreateSubmit(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'task_create_success') {
    try {
      result = TaskCreateSuccess(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'picker_list' ||
      tip == 'pickerlist' ||
      tip == 'vehicle_picker' ||
      tip == 'vehiclepicker') {
    try {
      result = PickerList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'table_picker') {
    try {
      // Both form positions are required. Guard here (not in the widget):
      // getPosition(null) throws inside TablePicker.initState, which runs AFTER
      // this dispatch returns, so this try/catch would NOT contain it and the
      // whole page would white-screen. Degrade to an inline marker instead.
      if (component['position'] == null || component['labelPosition'] == null) {
        result = Text('--${component['type']}-- missing position');
      } else {
        // Seed txfController slots for both positions so saveSend finds them.
        final int pos = getPosition(component['position']);
        txfControllerCheck(scrName, pos);
        final int lPos = getPosition(component['labelPosition']);
        txfControllerCheck(scrName, lPos);
        result = TablePicker(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'group_picker') {
    try {
      // valuePosition is required. Guard here (not in the widget):
      // getPosition(null) throws inside initState, which runs AFTER this
      // dispatch returns, so this try/catch would NOT contain it and the
      // whole page would white-screen. Degrade to an inline marker instead.
      if (component['valuePosition'] == null) {
        result = Text('--${component['type']}-- missing valuePosition');
      } else {
        // Seed txfController slots so saveSend finds them.
        final int vPos = getPosition(component['valuePosition']);
        txfControllerCheck(scrName, vPos);
        if (component['keyPosition'] != null) {
          txfControllerCheck(scrName, getPosition(component['keyPosition']));
        }
        if (component['labelPosition'] != null) {
          txfControllerCheck(scrName, getPosition(component['labelPosition']));
        }
        final gpKey = ObjectKey('$scrName-gp-$vPos');
        result = GroupPicker(
          key: gpKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'running_task_list') {
    try {
      result = AdminActiveTripList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'upcoming_task_list') {
    try {
      result = AdminUpcomingTaskList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'outstanding_panel') {
    try {
      result = AdminOutstandingList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'customer_outstanding_list') {
    try {
      result = CustomerOutstandingList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'asset_stock_list') {
    try {
      result = AssetStockList(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'receipt_doc') {
    try {
      result = ReceiptDoc(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'whatsapp_send') {
    try {
      result = WhatsAppSend(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'map_point_picker') {
    try {
      result = MapPointPicker(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'payout_list') {
    try {
      // position is required. Guard here (not in the widget):
      // getPosition(null) throws inside initState, which runs AFTER this
      // dispatch returns, so this try/catch would NOT contain it and the
      // whole page would white-screen. Degrade to an inline marker instead.
      if (component['position'] == null) {
        result = Text('--${component['type']}-- missing position');
      } else {
        // Seed txfController slots so saveSend finds them.
        final int pos = getPosition(component['position']);
        txfControllerCheck(scrName, pos);
        if (component['labelPosition'] != null) {
          txfControllerCheck(scrName, getPosition(component['labelPosition']));
        }
        if (component['totalPosition'] != null) {
          txfControllerCheck(scrName, getPosition(component['totalPosition']));
        }
        result = PayoutList(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else {
    result = Text("--${component['type']}-- Wrong widget name.");
  }

  // case 'pin': // checkbox widget
  //   {
  //     try {
  //       Key iKey = GlobalKey();
  //       inputTxt[iKey] = _component['data'];
  //       if (_component['position'] != null) {
  //         txfController[scrName][iKey] = InputController(
  //             _component['position'],
  //             TextEditingController(text: inputTxt[iKey]),
  //             _component['data'].toString().toUpperCase() ?? '');
  //       }
  //       result = Builder(
  //         builder: (BuildContext context) {
  //           return OtqPin();
  //         },
  //       );
  //     } catch (_) {
  //       result = Container(
  //         child: Text('--pin--'),
  //       );
  //     }
  //   }
  //   break; // end of case pin

  return result;
} // end of buildDisplayComponent
