import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:get/get.dart';

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
import 'choice_button_group.dart';
import 'ctx.dart';
import 'display_qr.dart';
import 'ftz_bluetooth_printer.dart';
import 'ftz_row_of_button_2.dart';
import 'goto.dart';
import 'gps_send.dart';
import 'image_upload.dart';
import 'location_detector.dart';
import 'otq_checkbox.dart';
import 'otq_dropdown_2.dart';
import 'otq_get_images_2.dart';
import 'otq_rdo_2.dart';
import 'otq_txf_2.dart';
import 'progress_bar.dart';
import 'selectable_btn.dart';
import 'tasklist.dart';
import 'time_presence.dart';

Widget buildDisplayComponent(
    dynamic component, String scrName, UserRepository userRepository,
    {bool? dialog}) {
  Widget result;
  var lPad = (systemUIComponent['Mobile']['leftPad'] ?? 0.0).toDouble();
  var tPad = (systemUIComponent['Mobile']['topPad'] ?? 0.0).toDouble();
  var rPad = (systemUIComponent['Mobile']['rightPad'] ?? 0.0).toDouble();
  var bPad = (systemUIComponent['Mobile']['bottomPad'] ?? 0.0).toDouble();
  // final txfKey = UniqueKey();
  final txfKey = ObjectKey("$scrName-${component['position']}");
  if (component['position'] != null) {
    String initValue = getInitialValue(scrName, component);
    txfControllerCheck(
        scrName, component['position']); // build txfController if necessary
    final bool isEnabled =
        (component['isEnabled']?.toString().toLowerCase() ?? 'true') != 'false';
    txfController[scrName]![getPosition(component['position'])]!.isEnabled =
        isEnabled;
    txfController[scrName]![getPosition(component['position'])]!
        .initialIsEnabled = isEnabled;
    if (scrName.toLowerCase() == 'vertikateknolokaciptareportpatrol' &&
        component['position'] == 5) {
      int d = 1;
    }
    // if (canInitializePage(scrName)) {
    txfController[scrName]![getPosition(component['position'])]!.finalData =
        initValue; // put initial value
    txfController[scrName]![getPosition(component['position'])]!.initialValue =
        initValue; // put initial value
    // }
  } else {
    if (component['type'].toLowerCase() == 'rbt') {
      final children = component['children'] ?? [];
      for (Map<String, dynamic> childComponent in children) {
        if (childComponent['position'] != null) {
          txfControllerCheck(scrName,
              childComponent['position']); // build txfController if necessary
          final bool isEnabled =
              (childComponent['isEnabled']?.toString().toLowerCase() ??
                  'true') !=
                  'false';
          txfController[scrName]![getPosition(childComponent['position'])]!
              .isEnabled = isEnabled;
          txfController[scrName]![getPosition(childComponent['position'])]!
              .initialIsEnabled = isEnabled;
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
      result = FtzAutoNumber(
        key: key,
        component: component,
        scrName: scrName,
      );
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
            bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
        height: (component['height'] ?? 0.0).toDouble(),
        padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
        child: Row(
          mainAxisAlignment: maaSwitch(component['alignment'] ?? 'start'),
          children: <Widget>[
            Expanded(
              child: displayImage(
                  imageUrl: component['url'] ?? defaultImage, cached: true),
              // child: FadeInImage.memoryNetwork(
              //     fit: BoxFit.contain,
              //     placeholder: kTransparentImage,
              //     image: component['url']),
            ),
          ],
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
            bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
        height: (component['width'] ?? 0.0).toDouble(),
        child: GridView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: (component['width'] ?? 0.0).toDouble(),
              childAspectRatio: bannerAspectRatio),
          children:
          buildBannerList(component['children'], bannerImageAspectRatio),
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
            bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
        height: ((component['width'] ?? 90.0) * component['row']).toDouble(),
        child: GridView(
          scrollDirection: Axis.vertical,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: (component['width'] ?? 90.0).toDouble()),
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
            bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
        height: ((component['width'] ?? 90.0) * component['row']).toDouble(),
        child: GridView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: (component['width'] ?? 90.0).toDouble()),
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
              bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
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
            bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
        padding: EdgeInsets.fromLTRB(lPad + (component['leftPadding'] ?? 0.0),
            tPad, rPad + (component['rightPadding'] ?? 0.0), bPad),
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
                child: Text(
                  component['label'] ?? "",
                ),
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
        final initValue =
        getInitialValue(scrName, component); // This is the display value
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
      bool isApprovalRbt = (component['children'] as List<dynamic>? ?? [])
          .any((btn) => btn is Map && btn.containsKey('actions'));
      if (isApprovalRbt) {
        final rbtComponent = component;
        final rbtScrName = scrName;
        final rbtDialog = dialog;
        final rbtLPad = lPad;
        final rbtTPad = tPad;
        final rbtRPad = rPad;
        final rbtBPad = bPad;
        final rbtKey = txfKey;
        List<String> tabs = [];
        var screenTx = transactionStore.state.screenTx;
        if (screenTx['approval_tabs'] is List) {
          tabs = (screenTx['approval_tabs'] as List)
              .map((e) => e.toString())
              .toList();
        }
        final String defaultStatus =
        tabs.isNotEmpty ? tabs[0].toUpperCase() : 'PENDING';
        result = ApproverStickyBar(
          scrName: scrName,
          builder: () => Obx(() {
            String s = ApprovalDetail.currentStatus.value;
            if (s.isNotEmpty && s != defaultStatus) {
              return const SizedBox.shrink();
            }
            return FtzRowOfButton2(
              key: rbtKey,
              component: rbtComponent,
              scrName: rbtScrName,
              dialog: rbtDialog,
              lPad: rbtLPad,
              tPad: rbtTPad,
              rPad: rbtRPad,
              bPad: rbtBPad,
            );
          }),
        );
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
                bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
            padding: EdgeInsets.fromLTRB(
                lPad + (component['leftPadding'] ?? 0.0).toDouble(),
                tPad,
                rPad + (component['rightPadding'] ?? 0.0).toDouble(),
                bPad),
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
                bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
            padding: EdgeInsets.fromLTRB(
                lPad + (component['leftPadding'] ?? 0.0).toDouble(),
                tPad,
                rPad + (component['rightPadding'] ?? 0.0).toDouble(),
                bPad),
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
                              context, component['route'], component['title']);
                        } else {
                          var state = transactionStore.state.screenTx;
                          if (state['#REFRESH']) {
                            oldSettingUpShouldBeDeleted().then((aRes) {
                              var state = transactionStore.state;
                              var lifKey = state.screenTx['#INTERFACE_KEY'];
                              readSettings(lifKey, 1).then((_) {
                                // constructAllPageElements();
                                transactionStore.dispatch(UpdateScreenTxAction(
                                    ScreenTransaction({'#REFRESH': false})));
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
                bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
            padding: EdgeInsets.fromLTRB(
                lPad + (component['leftPadding'] ?? 0.0).toDouble(),
                tPad,
                rPad + (component['rightPadding'] ?? 0.0).toDouble(),
                bPad),
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
          emptyString);
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
      result = Builder(builder: (BuildContext context) {
        return Invitation(
          key: rKey,
          scrName: scrName,
          component: component,
        );
      });
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
                bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
            padding: EdgeInsets.fromLTRB(
                lPad + (component['leftPadding'] ?? 0.0).toDouble(),
                tPad,
                rPad + (component['rightPadding'] ?? 0.0).toDouble(),
                bPad),
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
  } else if (tip == 'pdf_view') {
    // Pdf
    try {
      Key iKey = GlobalKey();
      result = Builder(
        builder: (BuildContext context) {
          return PdfViewer(
            key: iKey,
            component: component,
            scrName: scrName,
          );
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
                (component['children'][i]['fontSize'] ?? 14.0).toDouble());
        } // end switch
        iconList.add(theIcon);
      } // end for
      result = Container(
          margin: EdgeInsets.only(
              top: (component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
          height: ((component['width']) ?? 90.0).toDouble(),
          child: GridView(
            scrollDirection: Axis.horizontal,
            controller: ScrollController(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:
              ((component['width'] + 30) ?? 130.0).toDouble(),
              crossAxisSpacing: 1.0,
              // mainAxisSpacing: 1.0,
            ),
            children: iconList,
          ));
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
          txfControllerCheck(scrName,
              component['position']); // build txfController if necessary
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
  } else if (tip == 'approval') {
    try {
      result = Approval(
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
  } else if (tip == 'worker_card_detail') {
    try {
      result = WorkerCardDetail(
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
  } else if (tip == 'approval_detail') {
    try {
      result = ApprovalDetail(
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
  } else if (tip == 'comment_detail') {
    try {
      result = CommentDetail(
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
                bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
            padding: EdgeInsets.fromLTRB(
                lPad + (component['leftPadding'] ?? 0.0).toDouble(),
                tPad,
                rPad + (component['rightPadding'] ?? 0.0).toDouble(),
                bPad),
            child: const SizedBox(
              width: 0.0,
              height: 0.0,
            ), // put child here
          );
        },
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    } // end of try
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
