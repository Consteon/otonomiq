import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart' hide RadioGroup;
import 'package:flutter/material.dart' hide RadioGroup;
// import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
// import 'package:fluttercontactpicker/fluttercontactpicker.dart';
import 'package:group_radio_button/group_radio_button.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api.dart';
import '../bloc_timer/timer_bloc.dart';
import '../bloc_timer/timer_event.dart';
// import '../part/android_part/ftz_mobile_scanner.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../init_values.dart';
import '../main_bloc/main_bloc.dart';
import '../main_bloc/main_event.dart';
import '../model/general_get_controller.dart';
import '../otq_icons.dart';
import '../redux/screen_transaction.dart';
import 'ftz_array_search.dart';
import 'ftz_contact_picker.dart';
import 'otq_txf.dart';

// import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
// import 'package:barcode_scan2/barcode_scan2.dart';

// child method call
// https://stackoverflow.com/questions/48481590/how-to-set-update-state-of-statefulwidget-from-other-statefulwidget-in-flutter
// credit card format idea : https://appvesto.medium.com/flutter-formatting-textfield-with-textinputformatter-c73ee2167514
// more of credit card data input including logos
// https://medium.com/flutter-community/validating-and-formatting-payment-card-text-fields-in-flutter-bebe12bc9c60
// https://github.com/wilburt/Payment-Card-Validation/tree/master/assets/images
// multi formatter :
// https://pub.dev/packages/flutter_multi_formatter/example

String sttCompose(String base, String words, int maxLength) {
  // Compose one speech session onto the text present before it started.
  // maxLength <= 0 means unlimited (LengthLimitingTextInputFormatter does not
  // apply to programmatic controller.text writes, so truncate here).
  String t = base.isEmpty ? words : '$base $words';
  if (maxLength > 0 && t.length > maxLength) {
    t = t.substring(0, maxLength);
  }
  return t;
} // end of sttCompose

class OtqTxf2 extends StatefulWidget {
  /*
    Full blown txf widget
  */
  const OtqTxf2({
    required Key key,
    required this.scrName,
    required this.component,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
    this.cnt,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;
  final TextEditingController? cnt; //external controller, used by parent widget
  // null indicate that this is a stand-alone widget
  @override
  OtqTxf2State createState() => OtqTxf2State();
}

class OtqTxf2State extends State<OtqTxf2>
    with AutomaticKeepAliveClientMixin<OtqTxf2> {
  // with AutomaticKeepAliveClientMixin<TxfFull> will keep this widget when scroll
  var selectedDate = DateTime.now();
  late TextEditingController myController;
  TextEditingController searchController = TextEditingController();
  bool touch = true;
  bool obscure = false;
  // int startPosition = 0;
  String errorCode = emptyString; // emptyString = no Error
  String? lastValue;
  List<double> margin = [];
  List<dynamic> style = [];
  List<String> radioOption = []; // menu of ratio button
  Axis radioAxis = Axis.vertical; // axis of ratio button
  MainAxisAlignment radioAlignment =
      MainAxisAlignment.start; // alignment of radio button
  String? _picked; // picked item in radio button
  int maxLength =
      -1; // maximum length of input text (from component['maxlength']
  late bool editable;
  List<TextInputFormatter> tiFormatter = [];
  dynamic formatArray = [];

  // for currency, 0 = symbol (default = ""= no symbol)
  // 1 = thousands separator (default ",")
  // 2 = length of mantissa (default = 0)
  List<dynamic> textArray = [];
  String labelStr = '';
  String hintStr = '';
  String cancelStr = '';
  String searchDisplayType = '', searchContent = '', searchContentBase = '';

  // RxList<dynamic> localTable =
  //     [].obs; // Full array type of table for text search
  // RxList<dynamic> pickTable = [].obs; // searched localTable
  List<dynamic> localTable = []; // Full array type of table for text search
  List<dynamic> pickTable = []; // searched localTable
  bool tableSearchFound = false;
  Position? gpsPosition; // current position
  String qrType = 'G'; // default qr type = Generic
  Map<String, String> errString = {};

  // Speech-to-text (enabled per component via 'stt': true). One platform
  // recognizer exists per app, so the instance is static; _sttOwner routes the
  // static status/error callbacks to whichever field is listening now.
  static final SpeechToText _stt = SpeechToText();
  static bool _sttReady = false;
  static OtqTxf2State? _sttOwner;
  bool sttEnabled = false;
  bool _sttListening = false;
  String _sttBase = ''; // field text captured when the session started

  String formatNumber(dynamic format, num? value) {
    // format = [symbol, language, mantissa]
    late String result;
    try {
      num factor = pow(10, format[2]);
      num value2 = ((value ?? 0) * factor).round() / factor;
      String template = "#,##0";
      if (format[2] > 0) {
        template += ".${"0" * format[2]}";
      } // end if (format[2] > 0)
      result = format[0] == ""
          ? ""
          : "${format[0]} ${NumberFormat(template, format[1]).format(value2)}";
    } catch (e) {
      result = "";
    } // end try num factor
    return result;
  } // end of formatNumber

  DateTime _string2DT(String? inp, bool utc) {
    /*
      inp = millisecond from epoch or millisecond from beginning of day
    */
    var now = DateTime.now();
    DateTime returnValue = now;
    bool isDate = false;
    int n = now.hour * 3600000 + now.minute * 60000 + now.second * 1000;
    int init;
    try {
      init = (inp == null || inp == "") ? n : int.parse(inp);
      isDate = init >= 86400000 ? true : false;
    } catch (_) {
      init = n;
    }
    if (utc) {
      init += DateTime.now().timeZoneOffset.inMilliseconds;
    }
    if (isDate) {
      returnValue = DateTime.fromMillisecondsSinceEpoch(init);
    } else {
      int hour = (init / 3600000).floor();
      int minute = ((init % 3600000) / 60000).floor();
      int sec = ((init % 1000) / 1000).round();
      returnValue = DateTime(now.year, now.month, now.day, hour, minute, sec);
    } // end if (isDate)
    return returnValue;
  } // end of String2DT

  List<dynamic> getTotalValueFormatted() {
    // result = [dynamic data to be stored / totalValue (if any), String? formatted totalValue or original)
    String? cData =
        autheniumDecode(widget.component['currentValue'] ?? '') ?? '';
    late List<dynamic> result;

    try {
      if (cData.toString().substring(0, 1) == separator[3]) {
        // test for star
        List<String> currentArray = cData.split(separator[3]);
        num subTotal = 0;
        bool sum = currentArray[1].toString().trim() == "+";
        bool multiply = currentArray[1].toString().trim() == "*";
        for (var i = 2; i < currentArray.length; i++) {
          late num newValue;
          try {
            int newPosition = int.parse(currentArray[i]);
            newValue = num.parse(
              txfController[widget.scrName]![newPosition]!.finalData,
            );
          } catch (e) {
            newValue = 0;
          }
          if (sum) {
            subTotal += newValue;
          } else if (multiply) {
            subTotal = subTotal * newValue;
          } // end if sum
        } // end for currentArray
        if (formatArray.length <= 0) {
          formatArray = getCurrencyFormat(widget.component['format']);
        }
        result = [subTotal.toString(), formatNumber(formatArray, subTotal)];
      } else {
        result = [numericCleanUp(formatArray, cData), cData];
      } // end if "_u2605_"
    } catch (e) {
      result = [cData, cData]; // default
    }
    return result;
  } // end of getTotalValueFormatted

  @override
  void initState() {
    super.initState();
    GeneralGetXController.to.registerWidget(
      widget.scrName,
      widget.component['position'],
    );
    int currentTableVid = getTableVid(widget.component['com']);
    // final String com =
    //     (widget.component['com'] ?? '').toString().trim().toLowerCase();
    // if ((com.isNotEmpty)) {
    //   switch (com) {
    //     case 'con': // consteon
    //       currentTableVid = consteonVid;
    //       break;
    //   } // end switch
    //   currentTableVid = consteonVid;
    // }
    // if ((widget.component['qr'] ?? errorString) == 'aqr') {
    //   // ToDo delete this after new app for consteon
    //   currentTableVid = consteonVid;
    // }
    // if (widget.component['start'] is int) {
    //   startPosition = widget.component['start'] ?? 0;
    // }
    // if (widget.scrName.toLowerCase() == 'vertikateknolokaciptaapproveleave' &&
    //     widget.component['position'] == 16) {
    //   int dd = 1;
    // }
    String tableCode =
        autheniumDecode(normalizeTableName(widget.component['table'] ?? '')) ??
        '';
    if (tableCode.isNotEmpty) {
      String indexTableString = '';
      try {
        if (widget.component['filter'] != null) {
          List<String> parts =
              (autheniumDecode(widget.component['filter']) ?? '').split(
                separator[8],
              ); // white hollow circle
          indexTableString = parts[0];
        }
      } catch (e) {
        // do nothing}
      }
      subscribeToTable(
        tableCode,
        currentTableVid,
        indexTableString: indexTableString,
        indexTableType: 'K',
      ).then((_) {
        localTable = tableToArray(
          transactionStore.state.screenTx['#TABLE$tableCode'],
          tableCode,
          widget.component['sort'],
        );
        int dd = 1;
        // setState(() {
        //   pickTable = List.from(localTable).obs;
        // });
      });
      // todo unsubscribe at dispose if desirable (will be need to load again)
    } // end if (widget.component['table'] != null)
    if (widget.component['refTableNegative'] != null &&
        widget.component['refTableNegative'].toString().trim() != '') {
      subscribeToTable(
        widget.component['refTableNegative'],
        currentTableVid,
      ).then((_) {
        localTable = tableToArray(
          transactionStore
              .state
              .screenTx['#TABLE${widget.component['refTableNegative'].toString().trim()}'],
          widget.component['refTableNegative'],
          'asc',
        );
        // setState(() {
        //   pickTable = List.from(localTable).obs;
        // });
      });
      // todo unsubscribe at dispose if desirable (will be need to load again)
    } // end if (widget.component['table'] != null)
    if (widget.component['qr'] == null ||
        widget.component['qr'].toString().trim().isEmpty) {
      qrType = 'G';
    } else if (widget.component['qr'].toString().trim().toLowerCase() ==
        'uqr') {
      qrType = 'U';
    } else if (widget.component['qr'].toString().trim().toLowerCase() ==
        'lqr') {
      getLocation().then((pos) {
        gpsPosition = pos;
      });
      qrType = 'L';
    } else if (widget.component['qr'].toString().trim().toLowerCase() ==
        'aqr') {
      getLocation().then((pos) {
        gpsPosition = pos;
      });
      qrType = 'A';
    }
    editable = true;
    selectedDate = DateTime.now();
    if (widget.cnt != null) {
      // If an external controller is passed via 'cnt', use it.
      // This maintains parent-to-child control as the highest priority.
      myController = widget.cnt!;
    } else {
      // Otherwise, look up the controller from the global txfController map.
      // This assumes the parent has already created it.
      txfControllerCheck(widget.scrName, widget.component['position']);
      myController =
          txfController[widget.scrName]![widget.component['position']]!
              .controller;
    }
    // myController = (widget.cnt == null) ? TextEditingController() : widget.cnt!;
    // : myController = widget.cnt!;
    GeneralGetXController.to.putController(
      widget.scrName,
      widget.component['position'],
      myController,
    );
    // GeneralGetXController.to.putController(
    //     widget.scrName, widget.component['position'], (widget.cnt == null)
    //     ? TextEditingController()
    //     : widget.cnt!);
    // TextEditingController theController = GeneralGetXController.to
    //     .getController(widget.scrName, widget.component['position']);
    maxLength = widget.component['maxLength'] ?? -1;
    if (maxLength <= 0) {
      maxLength = -1;
    }
    sttEnabled =
        widget.component['stt'].toString().trim().toLowerCase() == 'true';
    if (widget.component['format'] != null) {
      formatArray = getCurrencyFormat(widget.component['format']);
    } // end if (widget.component['format'] != null)
    String variant = widget.component['variant'].toString().toLowerCase();
    if (variant == 'creditcardnumber') {
      //formatArray = getCurrencyFormat(widget.component['format']);
      tiFormatter.add(
        MaskedInputFormatter(
          "#### #### #### ####",
          allowedCharMatcher: RegExp(r'[0-9]+'),
        ),
      );
    } else if (variant == 'money') {
      if (formatArray.length <= 0) {
        // for money formatArray is mandatory
        formatArray = getCurrencyFormat(widget.component['format']);
      }
      tiFormatter.add(
        CurrencyInputFormatter(
          leadingSymbol: formatArray[0],
          thousandSeparator: formatArray[1] == "."
              ? ThousandSeparator.Period
              : ThousandSeparator.Comma,
          mantissaLength: formatArray[2],
          useSymbolPadding: formatArray[0].toString().isNotEmpty ? true : false,
        ),
      );
    } else if (variant == 'creditcardexpire') {
      tiFormatter.add(CreditCardExpirationDateFormatter());
    } else if (variant == 'static') {
      editable = false;
    } else if (variant == 'searchtable') {
      editable = false;
    } else {
      tiFormatter.add(LengthLimitingTextInputFormatter(maxLength));
    } // end if variant (tiFormatter)

    try {
      List<dynamic> valueArray = getTotalValueFormatted();
      if (widget.component['position'] != null) {
        switch (widget.component['variant']) {
          case 'searchTable':
            myController.text = widget.component['currentValue'] == null
                ? ''
                : widget.component['currentValue'].toString();
            break;

          case 'time':
            String fm =
                widget.component['format'] == null ||
                    widget.component['format'] == ""
                ? "H:mm"
                : widget.component['format'];
            myController.text =
                widget.component['currentValue'] == null ||
                    widget.component['currentValue'] == ""
                ? emptyString
                : DateFormat(fm).format(
                    _string2DT(
                      widget.component['currentValue'],
                      string2Bool(widget.component['utc']),
                    ),
                  );
            selectedDate = _string2DT(
              widget.component['currentValue'],
              string2Bool(widget.component['utc']),
            );
            break;

          case 'date':
            String fm =
                widget.component['format'] == null ||
                    widget.component['format'] == ""
                ? "d-MMM-yyyy"
                : widget.component['format'];
            myController.text =
                widget.component['currentValue'] == null ||
                    widget.component['currentValue'] == ""
                ? emptyString
                : DateFormat(
                    fm,
                  ).format(_string2DT(widget.component['currentValue'], false));
            if (widget.component['currentValue'] == null ||
                widget.component['currentValue'] == '') {
              selectedDate = _string2DT(
                DateTime.now().millisecondsSinceEpoch.toString(),
                string2Bool(widget.component['utc']),
              );
            } else {
              selectedDate = _string2DT(
                widget.component['currentValue'],
                false,
              );
            } // end if (widget.component['currentValue'] == null
            selectedDate = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
            ); // trim hourly data
            break;

          case 'dateTime':
            String fm =
                widget.component['format'] == null ||
                    widget.component['format'] == ""
                ? "d-MMM-yyyy H:mm"
                : widget.component['format'];
            myController.text =
                widget.component['currentValue'] == null ||
                    widget.component['currentValue'] == ""
                ? emptyString
                : DateFormat(fm).format(
                    _string2DT(
                      widget.component['currentValue'],
                      string2Bool(widget.component['utc']),
                    ),
                  );
            if (widget.component['currentValue'] == null ||
                widget.component['currentValue'] == '') {
              selectedDate = _string2DT(
                DateTime.now().millisecondsSinceEpoch.toString(),
                string2Bool(widget.component['utc']),
              );
            } else {
              selectedDate = _string2DT(
                widget.component['currentValue'],
                string2Bool(widget.component['utc']),
              );
            }
            break;

          case 'static':
            myController.text =
                (widget.component['line'] == null ||
                    widget.component['line'] <= 1)
                ? (valueArray[1]).replaceAll("\n", " ")
                : valueArray[1];
            break;

          case 'creditCardExpire':
            myController.text = valueArray[1];
            valueArray[0] = exp2Epoch(widget.component['currentValue']);
            break;

          default:
            myController.text =
                (widget.component['line'] == null ||
                    widget.component['line'] <= 1)
                ? (valueArray[1]).replaceAll("\n", " ")
                : valueArray[1];
        }

        if (widget.component['position'] != null) {
          txfControllerCheck(
            widget.scrName,
            widget.component['position'],
          ); // build txfController if necessary
          if (canInitializePage(widget.scrName)) {
            txfController[widget.scrName]![widget.component['position']]!
                    .finalData =
                valueArray[0];
            txfController[widget.scrName]![widget.component['position']]!
                    .initialValue =
                myController.text;
          } // end if (canInitializePage(widget.scrName))
        } // end if (widget.component['position'] != null)

        // txfControllerCheck(widget.scrName, widget.component['position']);
        // txfController[widget.scrName]![widget.component['position']]!
        //     .finalData = valueArray[0];
        // txfController[widget.scrName]![widget.component['position']]!
        //     .initialValue = myController.text;
        lastValue = myController.text;
        // if (widget.component['tableContentReference'] != null &&
        //     widget.component['tableContentReference'] > 0) {
        //   txfControllerCheck(
        //       widget.scrName, widget.component['tableContentReference']);
        //   if (canInitializePage(widget.scrName)) {
        //     txfController[widget.scrName]![
        //             widget.component['tableContentReference']]!
        //         .finalData = '';
        //   } // end if (canInitializePage(widget.scrName))
        // } // end if (widget.component['tableContentReference'] > 0)
        if (widget.component['locationNamePosition'] != null &&
            widget.component['locationNamePosition'] > 0) {
          txfControllerCheck(
            widget.scrName,
            widget.component['locationNamePosition'],
          );
          if (canInitializePage(widget.scrName)) {
            txfController[widget.scrName]![widget
                        .component['locationNamePosition']]!
                    .finalData =
                '';
          } // end if (canInitializePage(widget.scrName))
        } // end if (widget.component['tableContentReference'] > 0)
      } else {
        //myController = TextEditingController();
        errorCode = textList["NoPosition"]; // No position error
      } // end if component['position'] != null
    } catch (controllerE) {
      errorCode =
          textList["TXFInitError"]; // No position error // error while initializing controller
    } // end of try controller
    margin = marginArray(widget.component['margin']);
    style = styleArray(widget.component['style']);
    radioOption = List<String>.from(
      (widget.component['radio'] == null ||
              widget.component['radio'].length <= 0)
          ? [emptyString]
          : widget.component['radio'],
    ); // for radio button
    radioAxis =
        (widget.component['buttonLayout'] ?? 'vertical')
                .toString()
                .toLowerCase() ==
            'horizontal'
        ? Axis.horizontal
        : Axis.vertical; // for radio button
    radioAlignment = mainAlignmentConst(
      widget.component['alignment'],
    ); // for radio button
    textArray = (widget.component['text'] == null)
        ? []
        : diamondTextToList(widget.component['text']);
    labelStr = textArray.isNotEmpty
        ? textArray[0]
        : (widget.component['label'] ?? 'Label');
    hintStr = textArray.length > 1
        ? textArray[1]
        : (widget.component['hint'] ?? 'Hint');
    // labelStr = widget.component['label'] ??
    //     (textArray.isNotEmpty ? textArray[0] : 'Label');
    hintStr =
        widget.component['hint'] ??
        (textArray.length > 1 ? textArray[1] : 'Hint');
    cancelStr = textArray.length > 2 ? textArray[2] : 'Cancel';
    const noObject = {"searchDisplayType": "none", "content": ""};
    dynamic tempObj = noObject;
    if (textArray.length > 6) {
      // content string
      // content of search card
      try {
        tempObj = textArray[6] == '' ? noObject : json.decode(textArray[6]);
      } catch (e) {
        tempObj = noObject;
      } // end try
    } // end if (textArray.length > 6)
    if (textArray.length > 10) {
      // error messages
      errString['03'] = textArray[7];
      errString['05'] = textArray[8];
      errString['04'] = textArray[9];
      errString['98'] = textArray[10];
      errString['99'] = textArray[11];
    } // end if (textArray.length > 10)
    searchDisplayType = tempObj['searchDisplayType'];
    searchContent = tempObj['content'] ?? '';
    searchContentBase = searchContent;
  } // end of initState

  void _sttStopped() {
    // Reached from the mic button, plugin status ('done'/'notListening') and
    // error callbacks — the last two can fire after this state is disposed.
    if (mounted && _sttListening) {
      setState(() {
        _sttListening = false;
      });
    } else {
      _sttListening = false;
    }
  } // end of _sttStopped

  Future<void> _sttToggle() async {
    if (_sttListening) {
      await _stt.stop();
      _sttStopped();
      return;
    }
    if (!_sttReady) {
      // Also triggers the mic / speech-recognition permission prompts.
      _sttReady = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _sttOwner?._sttStopped();
          }
        },
        onError: (_) => _sttOwner?._sttStopped(),
      );
    }
    if (!_sttReady) {
      devPrint('stt initialize failed (permission or no speech service)');
      return;
    }
    if (_sttOwner != null && _sttOwner != this && _sttOwner!._sttListening) {
      await _stt.stop(); // steal the shared recognizer from another field
      _sttOwner!._sttStopped();
    }
    _sttOwner = this;
    _sttBase = myController.text.trim();
    setState(() {
      _sttListening = true;
    });
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: (widget.component['sttLocale'] ?? 'id_ID').toString(),
        partialResults: true,
      ),
      onResult: (result) {
        String t = sttCompose(_sttBase, result.recognizedWords, maxLength);
        // Programmatic .text writes do not fire onChanged — mirror its
        // default branch by hand (same as the QR/scan handlers do).
        myController.text = t;
        txfControllerCheck(widget.scrName, widget.component['position']);
        txfController[widget.scrName]![widget.component['position']]!
            .finalData = numericCleanUp(
          formatArray,
          t,
        );
      },
    );
  } // end of _sttToggle

  @override
  Future<void> dispose() async {
    super.dispose();
    if (_sttOwner == this) {
      _stt.stop();
      _sttOwner = null;
    }
    GeneralGetXController.to.putController(
      widget.scrName,
      widget.component['position'],
      null,
    );
    // myController.dispose();
    searchController.dispose();
    localTable.clear();
    pickTable.clear();
    margin.clear();
    style.clear();
    radioOption.clear();
    formatArray.clear();
    textArray.clear();
    // txfController[widget.scrName]!.remove(widget.component['position']);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<WidgetUpdateController>(
      id: "${widget.scrName}-${widget.component['position']}",
      builder: (_) {
        super.build(context); // needed by AutomaticKeepAliveClientMixin

        // MODIFIED: Get the isEnabled state from the controller
        // txfControllerCheck(widget.scrName,
        //     widget.component['position']); // Make sure controller exists
        final inputCtrl =
            txfController[widget.scrName]![widget.component['position']]!;
        final bool isEnabled = inputCtrl.isEnabled;
        debugPrint(
          "********* build txf ${widget.scrName} - ${widget.component['position']} = $isEnabled",
        );
        Widget result;
        var component = widget.component;
        String scrName = widget.scrName;
        final txfKey = widget.key;

        void saveData(String scrName, String locString) {
          TimerBloc timerBloc = transactionStore.state.screenTx['#TIMER_BLOC'];
          var route = widget.component['route'] ?? widget.scrName;
          rootThis.setState(() {
            rootThis.wait = true;
          });
          timerBloc.add(
            const Start(duration: 5),
          ); //  get timerBloc from transactionStore
          transactionStore.dispatch(
            UpdateScreenTxAction(
              ScreenTransaction({
                '#NEXTROUTE': route,
                '#TIMER_CONTEXT': context,
                '#TIMER_DURATION': widget.component['delay'] ?? 5,
              }),
            ),
          ); // set state #NEXTROUTE route that will b_scrNamee displayed after waitScreen
          saveSend(null, scrName, widget.component, locString, defaultVid());
        } // end of saveData

        Future<void> scan1() async {
          String barcodeScanRes = "";
          // Platform messages may fail, so use a try/catch PlatformException.
          try {
            if (barcodeScanRes != "") {
              setState(() {
                myController.text = barcodeScanRes;
              });
              vibrate(duration: 150);
            }
          } on PlatformException {
            barcodeScanRes = textList["ScanFailed"];
          }
        } // end of _scan1

        Future<void> scan2() async {
          String barcodeScanRes = "";
          // Platform messages may fail, so we use a try/catch PlatformException.
          try {
            if (barcodeScanRes != "") {
              setState(() {
                myController.text = barcodeScanRes;
              });
              vibrate(duration: 150);
              // int beepNow = await pool.play(scannerBeep);
              saveData(scrName, separator[1] * 15);
            }
          } on PlatformException {
            barcodeScanRes = textList["ScanFailed"];
          }
        } // end of _scan2

        chooseDate(
          BuildContext context,
          String initialDateString,
          dynamic component,
        ) {
          late dynamic modal, frm;
          bool isDate = true;
          if (widget.component['variant'] == 'date') {
            modal = CupertinoDatePickerMode.date;
            frm =
                widget.component['format'] == null ||
                    widget.component['format'] == ""
                ? "d-MMM-yyyy"
                : widget.component['format'];
          } else {
            isDate = false;
            modal = CupertinoDatePickerMode.dateAndTime;
            frm =
                widget.component['format'] == null ||
                    widget.component['format'] == ""
                ? "d-MMM-yyyy H:mm"
                : widget.component['format'];
          } // end if (widget.component['variant'] == 'date')
          myController.text = DateFormat(frm).format(selectedDate);
          if (isDate) {
            txfControllerCheck(widget.scrName, widget.component['position']);
            txfController[scrName]![widget.component['position']]!.finalData =
                DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                    )
                    .add(
                      Duration(minutes: selectedDate.timeZoneOffset.inMinutes),
                    )
                    .millisecondsSinceEpoch
                    .toString();
          } else {
            txfControllerCheck(widget.scrName, widget.component['position']);
            txfController[scrName]![widget.component['position']]!.finalData =
                string2Bool(widget.component['utc'])
                ? (selectedDate.toUtc().millisecondsSinceEpoch).toString()
                : (selectedDate
                          .add(
                            Duration(
                              minutes: selectedDate.timeZoneOffset.inMinutes,
                            ),
                          )
                          .millisecondsSinceEpoch)
                      .toString();
          } // end if (isDate)
          showCupertinoModalPopup(
            context: context,
            builder: (BuildContext builder) {
              DateTime startDate = widget.component['startDate'] == null
                  ? DateTime(minYear)
                  : DateTime.fromMillisecondsSinceEpoch(
                      widget.component['startDate'],
                    );
              DateTime endDate = widget.component['endDate'] == null
                  ? DateTime.now().add(Duration(days: maxPlusYear * 365))
                  : DateTime.fromMillisecondsSinceEpoch(
                      widget.component['endDate'],
                    );
              if (startDate.isAfter(selectedDate)) {
                startDate = selectedDate;
              } // end if (startDate.isAfter(initialDate))
              return Container(
                height: MediaQuery.of(context).copyWith().size.height * 0.25,
                //color: Theme.of(context).textTheme.bodyText1!.backgroundColor,
                color: Colors.white,
                child: CupertinoDatePicker(
                  mode: modal,
                  dateOrder: DatePickerDateOrder.dmy,
                  onDateTimeChanged: (value) {
                    if (value != selectedDate) {
                      setState(() {
                        selectedDate = value;
                        myController.text = DateFormat(
                          frm,
                        ).format(selectedDate);
                      }); // end of setState
                      if (isDate) {
                        txfControllerCheck(
                          widget.scrName,
                          widget.component['position'],
                        );
                        txfController[scrName]![widget.component['position']]!
                                .finalData =
                            DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                )
                                .add(
                                  Duration(
                                    minutes:
                                        selectedDate.timeZoneOffset.inMinutes,
                                  ),
                                )
                                .millisecondsSinceEpoch
                                .toString();
                      } else {
                        txfControllerCheck(
                          widget.scrName,
                          widget.component['position'],
                        );
                        txfController[scrName]![widget.component['position']]!
                            .finalData = string2Bool(widget.component['utc'])
                            ? (selectedDate.toUtc().millisecondsSinceEpoch)
                                  .toString()
                            : (selectedDate
                                      .add(
                                        Duration(
                                          minutes: selectedDate
                                              .timeZoneOffset
                                              .inMinutes,
                                        ),
                                      )
                                      .millisecondsSinceEpoch)
                                  .toString();
                      } // end if (isDate)
                    } // end if value != selectedDate
                  },
                  // end of onDateTimeChanged
                  initialDateTime: selectedDate,
                  minimumDate: startDate,
                  maximumDate: endDate,
                ),
              );
            },
          );
        } // end of _chooseDate

        chooseTime(BuildContext context, dynamic component) {
          txfControllerCheck(widget.scrName, widget.component['position']);
          txfController[scrName]![widget.component['position']]!.finalData =
              timeOfDayToGSheet(
                TimeOfDay(hour: selectedDate.hour, minute: selectedDate.minute),
                string2Bool(widget.component['utc']),
              );
          showCupertinoModalPopup(
            context: context,
            builder: (BuildContext builder) {
              return Container(
                height: MediaQuery.of(context).copyWith().size.height * 0.25,
                //color: Theme.of(context).textTheme.bodyText1!.backgroundColor,
                color: Colors.white,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  onDateTimeChanged: (value) {
                    if (value != selectedDate) {
                      setState(() {
                        selectedDate = value;
                        myController.text = DateFormat(
                          widget.component['format'] == null ||
                                  widget.component['format'] == ""
                              ? "k:mm"
                              : widget.component['format'],
                        ).format(selectedDate);
                      }); // end of setState
                      // txfControllerCheck(
                      //     widget.scrName, widget.component['position']);
                      txfController[scrName]![widget.component['position']]!
                          .finalData = timeOfDayToGSheet(
                        TimeOfDay(
                          hour: selectedDate.hour,
                          minute: selectedDate.minute,
                        ),
                        string2Bool(widget.component['utc']),
                      );
                    } // end if value != selectedDate
                  }, // end of onDateTimeChanged
                  initialDateTime: selectedDate,
                ),
              );
            },
          );
        } // end of _chooseTime

        Future chooseContact(BuildContext context) async {
          // final PhoneContact result =
          //     await FlutterContactPicker.pickPhoneContact();
          // todo make a contact picker here
          myController.text =
              await chooseContactAndGetPhoneNumber(widget.component['label']) ??
              '';
          txfControllerCheck(widget.scrName, widget.component['position']);
          txfController[scrName]![component['position']]!.finalData =
              myController.text;
        } // end of _chooseContact

        Future chooseFromTable(dynamic component, dynamic tableArray) async {
          // localTable = tableToArray(
          //     transactionStore.state.screenTx['#TABLE${widget.component['table']}'],
          //     widget.component['table'],
          //     widget.component['sort']);
          String tableCode =
              autheniumDecode(normalizeTableName(widget.component['table'])) ??
              '';
          localTable = deepCopy2(tableContent[tableCode] ?? []);
          double contentHeight =
              ((MediaQuery.of(context).size.height) * 0.7).round() * 1.0;
          return Get.dialog(
            AlertDialog(
              content: SizedBox(
                width: double.maxFinite,
                height: contentHeight, // Specify the height explicitly
                // child: FtzStaticArraySearch(
                child: FtzArraySearch(
                  localTable: localTable,
                  resultController: myController,
                  component: widget.component,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(cancelStr),
                  onPressed: () {
                    Get.back(result: false);
                  },
                ),
              ],
            ),
          ); // end Get.dialog
        } // end of chooseFromTable

        String getSearchContent(String contentSource, String? searchKey) {
          String res = contentSource;
          String tableCode =
              autheniumDecode(normalizeTableName(widget.component['table'])) ??
              '';
          if (searchKey != null &&
              transactionStore.state.screenTx['#TABLE$tableCode'][searchKey] !=
                  null) {
            // The most concise and readable version for creating a copy of the list.
            // final elementArray = transactionStore.state
            //     .screenTx['#TABLE$tableCode'][searchKey] as List<dynamic>;
            late List<dynamic> elementArray;
            if (tableType[tableCode] == 'A') {
              elementArray = [0];
            } else {
              elementArray = [];
            }
            elementArray.addAll(
              transactionStore.state.screenTx['#TABLE$tableCode'][searchKey],
            );
            res = replaceMarker(
              contentSource,
              elementArray,
              widget.component['indexStart'] ?? 0,
              true,
            );
          }
          return res;
        } // end of getSearchContent

        void txfOnTap() {
          int indexFactor = (2 - (widget.component['indexStart'] ?? 0)).round();
          switch (component['variant'].toString().toLowerCase()) {
            case 'tablesearch':
              List<String> refArray = [];
              int mainRef = 0;
              String? tableContentReference;
              if (widget.component['tableContentReference'] != null &&
                  widget.component['tableContentReference'] != '') {
                tableContentReference = autheniumDecode(
                  widget.component['tableContentReference'].toString(),
                );
                refArray = tableContentReference!.split(blackDiamond);
                mainRef = int.tryParse(refArray[0]) ?? 0;
              } // end if (widget.component['tableContentReference'] != null)
              chooseFromTable(component, localTable).then((result) {
                List<List<int>> resultArray = refArray.sublist(1).expand((
                  part,
                ) {
                  List<String> subParts = part.split(':');
                  if (subParts.length == 2) {
                    int? num1 = int.tryParse(subParts[0]);
                    int? num2 = int.tryParse(subParts[1]);
                    if (num1 != null && num2 != null) {
                      return [
                        [num1, num2],
                      ];
                    }
                  } // end if (subParts.length == 2)
                  // If the format is wrong or parsing fails, return an empty list
                  // to effectively exclude this part from the final result.
                  return <List<int>>[];
                }).toList(); // Convert the result to a List.
                String tableCode =
                    autheniumDecode(
                      normalizeTableName(widget.component['table']),
                    ) ??
                    '';
                tableSearchFound =
                    (transactionStore
                        .state
                        .screenTx['#TABLE$tableCode'][myController.text] !=
                    null);
                final searchKey = myController.text;
                List<dynamic> elementArray = [searchKey];
                // indexFactor++; // need to advance one more for search key

                // --- START: MODIFICATION ---
                // A list to hold the unique IDs of widgets that need to be updated.
                List<String> idsToUpdate = [];

                if (tableContentReference != null &&
                    tableContentReference != '' &&
                    tableSearchFound) {
                  // get the content from reference table
                  String tableCode =
                      autheniumDecode(
                        normalizeTableName(widget.component['table']),
                      ) ??
                      '';
                  elementArray.addAll(
                    transactionStore
                        .state
                        .screenTx['#TABLE$tableCode'][searchKey],
                  );
                  if (tableType[tableCode] == 'A') {
                    // for array table
                    indexFactor--;
                  }

                  for (List<int> element in resultArray) {
                    if (element.length == 2) {
                      int position = element[0];
                      int index = element[1] + indexFactor;
                      try {
                        if (position >= 0) {
                          txfControllerCheck(widget.scrName, position);
                          txfController[widget.scrName]![position]!
                              .controller
                              .text = elementArray[index]
                              .toString();
                          txfController[widget.scrName]![position]!.finalData =
                              elementArray[index].toString();
                          idsToUpdate.add(
                            GeneralGetXController.to.getWidgetId(
                              widget.scrName,
                              position,
                            ),
                          );
                          devPrint('$position:$index updated.');
                        }
                      } catch (eElement) {
                        // Error handling for safety
                        txfControllerCheck(widget.scrName, position);
                        final errorContent =
                            'Error in $position:$index. in tableContentReference';
                        txfController[widget.scrName]![position]!
                                .controller
                                .text =
                            errorContent;
                        devPrint(errorContent);
                      } // End of try-catch
                    } // end if (element.length == 2
                  } // end for (List<int> element in resultArray
                } // end if (tableContentReference != null

                // After updating all controllers, explicitly notify GetBuilder
                // for all target widgets to force a UI refresh.
                if (idsToUpdate.isNotEmpty) {
                  GeneralGetXController.to.update(idsToUpdate);
                }
                // --- END: MODIFICATION ---
                if (mounted) {
                  // Update the state for THIS widget (W1)
                  setState(() {
                    searchContent = getSearchContent(
                      searchContentBase,
                      myController.text,
                    );
                    String contentResult = atiCode;
                    if (tableSearchFound) {
                      txfController[widget.scrName]![widget
                                  .component['position']]!
                              .finalData =
                          myController.text;
                      var content = transactionStore
                          .state
                          .screenTx['#TABLE$tableCode'][myController.text];
                      for (dynamic e in content) {
                        if (contentResult != atiCode) {
                          contentResult += separator[6];
                        }
                        try {
                          contentResult += e.toString();
                        } catch (err) {
                          // do nothing
                        }
                      }
                    } else {
                      try {
                        contentResult +=
                            separator[6] *
                            getNumberOfField(tableHeader[tableCode]);
                      } catch (e) {
                        contentResult += separator[6];
                      }
                    }
                    if (mainRef > 0) {
                      txfControllerCheck(widget.scrName, mainRef);
                      txfController[widget.scrName]![mainRef]!.finalData =
                          contentResult;
                    }
                  }); // End of setState for W1
                } // End of if(mounted)
              });
              break;

            case 'time':
              chooseTime(context, component);
              break;

            case 'date':
              chooseDate(context, myController.text, component);
              break;

            case 'datetime':
              chooseDate(context, myController.text, component);
              break;

            case 'barcode1': // should barcode1
              scan1();
              break;

            case 'barcode2':
              scan2();
              break;

            case 'barcode3':
              scan1();
              break;
          } // end switch (component['variant'].toString().toLowerCase())
        } // end of txfOnTap

        try {
          late Widget element;
          TextInputType kbType = TextInputType.text;
          String variant = (component['variant'] ?? emptyString)
              .toString()
              .toLowerCase();
          if (variant == 'date' || variant == 'datetime' || variant == 'time') {
            kbType = TextInputType.none;
          } else if (variant == 'numeric' ||
              variant == 'creditcardnumber' ||
              variant == 'creditcardexpire' ||
              variant == 'money') {
            // kbType = TextInputType.number;
            kbType = TextInputType.numberWithOptions(decimal: true);
          } else if (variant == 'contact') {
            kbType = TextInputType.number;
          } else if (variant == 'pin') {
            kbType = TextInputType.number;
            obscure = true;
          } else if (variant == 'password') {
            kbType = TextInputType.text;
            obscure = true;
          } else {
            kbType = TextInputType.text;
          }

          Widget radioSelection = radioOption[0] == emptyString
              ? Container()
              : RadioGroup<String>.builder(
                  groupValue: _picked ?? "",
                  direction: radioAxis,
                  horizontalAlignment: mainAlignmentConst(
                    widget.component['alignment'],
                  ),
                  onChanged: isEnabled
                      ? (value) => setState(() {
                          setState(() {
                            _picked = value;
                            txfController[widget.scrName]![widget
                                        .component['position']]!
                                    .controller
                                    .text =
                                _picked ?? "";
                            myController.text = value ?? "";
                          });
                          txfControllerCheck(
                            widget.scrName,
                            widget.component['position'],
                          );
                          txfController[widget.scrName]![widget
                                      .component['position']]!
                                  .finalData =
                              _picked ?? "";
                        })
                      : null,
                  items: radioOption,
                  itemBuilder: (item) => RadioButtonBuilder(
                    item,
                    textPosition:
                        ((radioAxis == Axis.vertical) &&
                            radioAlignment == MainAxisAlignment.end)
                        ? RadioButtonTextPosition.left
                        : RadioButtonTextPosition.right,
                  ),
                );
          result = Builder(
            builder: (BuildContext context) {
              Widget txf;
              String cValueString = (widget.component['currentValue'] ?? "")
                  .toString();
              if (widget.component['variant'] == 'static' &&
                  cValueString.length >= 7 &&
                  cValueString.substring(0, 7) == "_u2605_") {
                // if static and subtotal type (star in currentValue)
                List<dynamic> valueArray = getTotalValueFormatted();
                myController.text =
                    (widget.component['line'] == null ||
                        widget.component['line'] <= 1)
                    ? (valueArray[1]).replaceAll("\n", " ")
                    : valueArray[1];
                txfControllerCheck(
                  widget.scrName,
                  widget.component['position'],
                );
                txfController[widget.scrName]![widget.component['position']]!
                        .finalData =
                    valueArray[0];
              } // end if (widget.component['variant']== 'static')
              try {
                txf = Column(
                  children: <Widget>[
                    (widget.component['fieldPosition'] ?? 'bottom')
                                .toString()
                                .toLowerCase() ==
                            'top'
                        ? Container()
                        : radioSelection,
                    TextFormField(
                      key: txfKey,
                      controller: myController,
                      keyboardType:
                          (component['line'] == null || component['line'] <= 1)
                          ? kbType
                          : TextInputType.multiline,
                      obscureText: obscure,
                      enabled:
                          editable &&
                          isEnabled, // MODIFIED: Combine editable with isEnabled
                      inputFormatters: tiFormatter,
                      onTap: txfOnTap,
                      onChanged: (value) async {
                        txfControllerCheck(
                          widget.scrName,
                          widget.component['position'],
                        );
                        String variant = (widget.component['variant'] ?? '')
                            .toString()
                            .trim()
                            .toLowerCase();
                        if (variant == 'creditcardexpire') {
                          txfController[widget.scrName]![widget
                                  .component['position']]!
                              .finalData = exp2Epoch(
                            value,
                          ).toString();
                        } else if (variant == 'qrscan') {
                          // Manual typing = no QR scanned → keep lq (this field's
                          // own position) EMPTY; only the location NAME goes to
                          // locationNamePosition (ln). A real scan sets this
                          // position = qrResult via the scan handler, which does
                          // not fire onChanged, so scans are unaffected.
                          txfController[widget.scrName]![widget
                                      .component['position']]!
                                  .finalData =
                              '';
                          if (widget.component['locationNamePosition'] !=
                                  null &&
                              widget.component['locationNamePosition']
                                      .toString()
                                      .trim() !=
                                  '') {
                            txfControllerCheck(
                              widget.scrName,
                              widget.component['locationNamePosition'],
                            );
                            txfController[widget.scrName]![widget
                                    .component['locationNamePosition']]!
                                .finalData = value
                                .toString();
                          } // end if (widget.component['locationNamePosition'] != null
                        } else if (variant == 'static') {
                          // do nothing
                        } else {
                          txfController[widget.scrName]![widget
                                  .component['position']]!
                              .finalData = numericCleanUp(
                            formatArray,
                            myController.text,
                          );
                          if (variant == 'tablesearch') {
                            setState(() {
                              String tableCode =
                                  autheniumDecode(
                                    normalizeTableName(
                                      widget.component['table'],
                                    ),
                                  ) ??
                                  '';
                              if (transactionStore
                                      .state
                                      .screenTx['#TABLE$tableCode'][value] !=
                                  null) {
                                searchContent = getSearchContent(
                                  searchContentBase,
                                  value,
                                );
                                tableSearchFound = true;
                              } else {
                                tableSearchFound = false;
                              }
                            });
                          } // end if (widget.component['variant'] == 'tableSearch')
                        }
                      },
                      //end of onChanged
                      minLines:
                          (component['line'] == null || component['line'] <= 1)
                          ? 1
                          : component['line'],
                      maxLines:
                          (component['line'] == null || component['line'] <= 1)
                          ? 1
                          : component['line'],
                      decoration: InputDecoration(
                        // prefixIcon: component['icon'].toString().isNotEmpty
                        //     ? Padding(
                        //         padding: const EdgeInsets.only(left: 8),
                        //         child: Icon(
                        //           otqIcons[component['icon'].toString()],
                        //           color: const Color(0xFF93C5FD),
                        //         ),
                        //       )
                        //     : null,
                        hintText: hintStr,
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(
                          16,
                          widget.tPad.clamp(10.0, 16.0),
                          8,
                          widget.bPad.clamp(10.0, 16.0),
                        ),
                      ),
                      style: TextStyle(
                        color: Color.fromARGB(255, 88, 91, 97),
                        backgroundColor:
                            (component['background'] ?? 'default') != 'default'
                            ? Color(int.parse(component['background']))
                            : Theme.of(
                                context,
                              ).textTheme.bodyLarge!.backgroundColor,
                        fontWeight: style[0],
                        fontStyle: style[1],
                        decoration: style[2],
                        fontSize: 0.0 + (component['size'] ?? 13.0).toDouble(),
                      ),
                    ),
                    (widget.component['fieldPosition'] ?? 'bottom')
                                .toString()
                                .toLowerCase() ==
                            'bottom'
                        ? Container()
                        : radioSelection,
                  ],
                );
              } catch (eTxf) {
                txf = Text("-- TXF -- $scrName, $txfKey : ${eTxf.toString()}");
              }
              bool showTitle =
                  (component['label'] != null &&
                      component['label'].toString().trim().isNotEmpty) ||
                  (textArray.isNotEmpty &&
                      textArray[0].toString().trim().isNotEmpty);
              String iconKey = (component['icon'] ?? '').toString().trim();
              bool hasIcon = iconKey.isNotEmpty && (otqIcons[iconKey] != null);
              Container pillWrap(Widget child) => Container(
                margin: (showTitle || hasIcon)
                    ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
                    : EdgeInsets.only(
                        top: margin[0],
                        bottom: margin[1],
                        left: widget.lPad + margin[2],
                        right: widget.rPad + margin[3],
                      ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                    width: 1.2,
                  ),
                  boxShadow: (showTitle || hasIcon)
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: child,
              );
              bool errorHappened = false;
              switch (component['variant'].toString().toLowerCase()) {
                case 'contact':
                  element = pillWrap(
                    Row(
                      children: <Widget>[
                        Expanded(child: txf),
                        IconButton(
                          icon: Icon(
                            otqIcons[component['buttonIcon'] ?? 'contact_page'],
                            size: 8.0 + (component['size'] ?? 16.0),
                          ),
                          tooltip: 'Contact',
                          onPressed: isEnabled
                              ? () => chooseContact(context)
                              : null,
                        ),
                      ],
                    ),
                  );
                  break;

                case 'tablesearch':
                  element = Row(
                    children: <Widget>[
                      Expanded(child: txf),
                      IconButton(
                        icon: Icon(
                          otqIcons[component['buttonIcon'] ?? 'flare'],
                          size: 8.0 + (component['size'] ?? 16.0),
                        ),
                        tooltip: 'Scan',
                        onPressed: isEnabled
                            ? () async {
                                // MODIFIED
                                if (!await dataOk(context)) {
                                  setState(() {
                                    myController.text = lastValue ?? "";
                                  });
                                } else {
                                  if (txfController[scrName] != null &&
                                      txfController[scrName]![component['position']] !=
                                          null) {
                                    lastValue = myController.text;
                                  }
                                  actionLock('tableSearch otq_txf');
                                  String? rawQRText = await takeQR(
                                    context,
                                    textArray.length > 3
                                        ? textArray[3]
                                        : 'Scan QR',
                                    scrName,
                                    component,
                                    'txt',
                                  );
                                  if (rawQRText != null &&
                                      rawQRText != emptyString &&
                                      rawQRText != 'null') {
                                    String qrResult = (await getQRContent(
                                      qrType,
                                      rawQRText,
                                      gpsPosition,
                                      component['table'],
                                      component['refTableNegative'],
                                      [],
                                    )).toString();
                                    String errorMessage = '';
                                    if (qrResult.substring(0, 6) ==
                                        textList["ErrorPrefix"]) {
                                      errorHappened = true;
                                      switch (qrResult.substring(6, 8)) {
                                        case '01': //out of range
                                          errorMessage = textArray.length > 9
                                              ? textArray[9]
                                              : textList['GPSOutOfRange'];
                                          break;

                                        case '02': // no qr result
                                          errorMessage = textArray.length > 11
                                              ? textArray[11]
                                              : textList["QRError"];
                                          break;

                                        case '05': //user not in list
                                          errorMessage = textArray.length > 8
                                              ? textArray[8]
                                              : textList['QRNotListed2'];
                                          break;

                                        case '98': //qr not recognized
                                          errorMessage = textArray.length > 10
                                              ? textArray[10]
                                              : textList['QRError'];
                                          break;

                                        default:
                                          errorMessage =
                                              textList['GeneralError'];
                                      } // end switch (qrResult.substring(6, 8))
                                      // qrResult += ' $errorMessage';
                                      qrResult = errorMessage;
                                    } // end if (qrResult.substring(0,6)
                                    setState(() {
                                      dynamic refTable = {};
                                      bool table = false;
                                      String tableCode =
                                          autheniumDecode(
                                            normalizeTableName(
                                              widget.component['table'],
                                            ),
                                          ) ??
                                          '';
                                      if (tableCode.toString().isEmpty) {
                                        if (qrType == 'L') {
                                          refTable = transactionStore
                                              .state
                                              .screenTx['#LQR_LIST'];
                                        }
                                        table = false;
                                      } else {
                                        refTable = transactionStore
                                            .state
                                            .screenTx['#TABLE$tableCode'];
                                        table = true;
                                      }
                                      if (qrType == 'L') {
                                        if (errorHappened) {
                                          myController.text = qrResult;
                                        } else {
                                          myController.text =
                                              (table
                                                      ? refTable[qrResult][2]
                                                      : refTable[qrResult][0])
                                                  .toString(); // location name
                                        } // end if (qrResult.substring(0, 6)
                                      } else if (qrType == 'U') {
                                        myController.text = qrResult; // vid
                                      } else {
                                        myController.text = qrResult;
                                      } // end if (widget.component['qr'] == 'lqr')
                                      txfController[widget
                                                  .scrName]![component['position']]!
                                              .finalData =
                                          qrResult;
                                      if (refTable[qrResult] != null) {
                                        searchContent = getSearchContent(
                                          searchContentBase,
                                          qrResult,
                                        );
                                        tableSearchFound = true;
                                        if (!errorHappened) {
                                          List<String> refArray = [];
                                          int mainRef = 0;
                                          String? tableContentReference;
                                          if (component['tableContentReference'] !=
                                                  null &&
                                              component['tableContentReference'] !=
                                                  '') {
                                            tableContentReference = autheniumDecode(
                                              widget
                                                  .component['tableContentReference']
                                                  .toString(),
                                            );
                                            refArray = tableContentReference!
                                                .split(blackDiamond);
                                            mainRef =
                                                int.tryParse(refArray[0]) ?? 0;
                                            var content = refTable[qrResult];
                                            // String contentResult = '';
                                            String contentResult = atiCode;
                                            for (dynamic e in content) {
                                              if (contentResult != atiCode) {
                                                contentResult += separator[6];
                                              } // end if (contentResult != '')
                                              try {
                                                contentResult += e.toString();
                                              } catch (err) {
                                                // do nothing
                                              }
                                            } // end for (dynamic e in content)
                                            if (mainRef > 0) {
                                              txfControllerCheck(
                                                widget.scrName,
                                                mainRef,
                                              );
                                              txfController[widget
                                                          .scrName]![mainRef]!
                                                      .finalData =
                                                  contentResult;
                                            }
                                            List<dynamic> elementArray = [
                                              qrResult,
                                            ];
                                            elementArray.addAll(
                                              transactionStore
                                                  .state
                                                  .screenTx['#TABLE$tableCode'][qrResult],
                                            );
                                            List<List<int>>
                                            resultArray = refArray.sublist(1).expand((
                                              part,
                                            ) {
                                              // Each part is split by ':'
                                              List<String> subParts = part
                                                  .split(':');
                                              // Ensure the part has exactly two components after splitting.
                                              if (subParts.length == 2) {
                                                // Try to parse both components into integers.
                                                int? num1 = int.tryParse(
                                                  subParts[0],
                                                );
                                                int? num2 = int.tryParse(
                                                  subParts[1],
                                                );
                                                // If both parsing attempts are successful, return the pair
                                                // wrapped in a list for the expand method.
                                                if (num1 != null &&
                                                    num2 != null) {
                                                  return [
                                                    [num1, num2],
                                                  ];
                                                }
                                              } // end if (subParts.length == 2)
                                              // If the format is wrong or parsing fails, return an empty list
                                              // to effectively exclude this part from the final result.
                                              return <List<int>>[];
                                            }).toList(); // Convert the result to a List.
                                            for (List<int> element
                                                in resultArray) {
                                              if (element.length == 2) {
                                                int position = element[0];
                                                int index = element[1];
                                                List<String> idsToUpdate = [];
                                                try {
                                                  if (position >= 0) {
                                                    txfControllerCheck(
                                                      widget.scrName,
                                                      position,
                                                    );
                                                    // Update the controller's text for the target widget (e.g., W2, W3)
                                                    txfController[widget
                                                            .scrName]![position]!
                                                        .controller
                                                        .text = elementArray[index]
                                                        .toString();
                                                    // Update the final data as well
                                                    txfController[widget
                                                                .scrName]![position]!
                                                            .finalData =
                                                        elementArray[index]
                                                            .toString();

                                                    // Add the target widget's ID to our notification list.
                                                    idsToUpdate.add(
                                                      GeneralGetXController.to
                                                          .getWidgetId(
                                                            widget.scrName,
                                                            position,
                                                          ),
                                                    );

                                                    devPrint(
                                                      '$position:$index updated.',
                                                    );
                                                  }
                                                } catch (eElement) {
                                                  // Error handling for safety
                                                  txfControllerCheck(
                                                    widget.scrName,
                                                    position,
                                                  );
                                                  final errorContent =
                                                      'Error in $position:$index. in tableContentReference';
                                                  txfController[widget
                                                              .scrName]![position]!
                                                          .controller
                                                          .text =
                                                      errorContent;
                                                  devPrint(errorContent);
                                                } // End of try-catch
                                                if (idsToUpdate.isNotEmpty) {
                                                  GeneralGetXController.to
                                                      .update(idsToUpdate);
                                                }
                                              } // end if (element.length == 2
                                            } // end for (List<int> element in resultArray
                                          } // end if (component['tableContentReference'] != null
                                        } // end if (!errorHappend)
                                      } else {
                                        tableSearchFound = false;
                                      } // end if (transactionStore.state.screenTx
                                    });
                                  } // end if (rawQRText != null && rawQRText != emptyString
                                  setDataOK(
                                    '2',
                                  ); // reload pages and display green status.
                                } // end if !transactionStore.state.screenTx['#DATA_OK']
                              }
                            : null,
                      ),
                    ],
                  );
                  element = pillWrap(element);
                  if (searchDisplayType == 'text1') {
                    element = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        element,
                        !tableSearchFound
                            ? Container()
                            : Container(
                                margin: (showTitle || hasIcon)
                                    ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
                                    : EdgeInsets.only(
                                        top: margin[0],
                                        bottom: margin[1],
                                      ),
                                padding: (showTitle || hasIcon)
                                    ? const EdgeInsets.fromLTRB(4, 8, 4, 8)
                                    : EdgeInsets.fromLTRB(
                                        widget.lPad + margin[2],
                                        widget.tPad,
                                        widget.rPad + margin[3],
                                        widget.bPad,
                                      ),
                                child: Text(
                                  searchContent,
                                  softWrap: true,
                                  style: TextStyle(
                                    color:
                                        (component['color'] ?? 'default') !=
                                            'default'
                                        ? Color(int.parse(component['color']))
                                        : Theme.of(
                                            context,
                                          ).textTheme.bodyLarge!.color,
                                    backgroundColor:
                                        (component['background'] ??
                                                'default') !=
                                            'default'
                                        ? Color(
                                            int.parse(component['background']),
                                          )
                                        : Theme.of(context)
                                              .textTheme
                                              .bodyLarge!
                                              .backgroundColor,
                                    fontWeight: style[0],
                                    fontStyle: style[1],
                                    decoration: style[2],
                                    fontSize:
                                        0.0 +
                                        (int.parse(
                                          (component['size'] ?? 16).toString(),
                                        )),
                                  ),
                                ),
                              ),
                      ],
                    );
                  } // end if (searchDisplayType == 'text1')
                  break;

                case 'barcode1': // should barcode1
                  {
                    element = pillWrap(
                      Row(
                        children: <Widget>[
                          Expanded(child: txf),
                          IconButton(
                            icon: const Icon(Icons.flare),
                            tooltip: 'Scan',
                            onPressed: isEnabled ? () => scan1() : null,
                          ),
                        ],
                      ),
                    );
                  }
                  break;

                case 'qrscan':
                  {
                    element = Row(
                      children: <Widget>[
                        Expanded(child: txf),
                        IconButton(
                          icon: Icon(
                            otqIcons[component['buttonIcon'] ?? 'flare'],
                            size: 8.0 + (component['size'] ?? 16.0),
                          ),
                          tooltip: 'Scan',
                          onPressed: isEnabled
                              ? () async {
                                  // MODIFIED
                                  if (!await dataOk(context)) {
                                    setState(() {
                                      myController.text = lastValue ?? "";
                                    });
                                  } else {
                                    if (txfController[scrName] != null &&
                                        txfController[scrName]![component['position']] !=
                                            null) {
                                      lastValue = myController.text;
                                    }
                                    final bool fakeGpsAllowed =
                                        (component['fakeGpsAllowed']
                                                ?.toString()
                                                .toLowerCase() ??
                                            'true') !=
                                        'false';
                                    if (!fakeGpsAllowed &&
                                        (gpsPosition?.isMocked ?? false)) {
                                      if (context.mounted) {
                                        await showDialog(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return AlertDialog(
                                              title: Text(
                                                textArray.length > 12
                                                    ? textArray[12]
                                                    : 'Lokasi tidak valid',
                                              ),
                                              content: Text(
                                                textArray.length > 13
                                                    ? textArray[13]
                                                    : 'Nonaktifkan Fake GPS',
                                              ),
                                              actions: [
                                                TextButton(
                                                  child: const Text('OK'),
                                                  onPressed: () =>
                                                      Navigator.of(ctx).pop(),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      }
                                      return;
                                    }
                                    final bool outPositionAllowed =
                                        (component['outPositionAllowed']
                                                ?.toString()
                                                .toUpperCase() ??
                                            'TRUE') !=
                                        'FALSE';
                                    bool outBlocked = false;
                                    if (!outPositionAllowed) {
                                      final dynamic lqrList = transactionStore
                                          .state
                                          .screenTx['#LQR_LIST'];
                                      final bool hasLqrList =
                                          lqrList != null &&
                                          lqrList is Map &&
                                          lqrList.isNotEmpty;
                                      if (hasLqrList) {
                                        try {
                                          final double gpsAccuracy =
                                              gpsPosition!.accuracy;
                                          bool insideAny = false;
                                          double minDistance = double.infinity;
                                          double matchZone2 = 0;
                                          for (final entry in lqrList.values) {
                                            final List data = entry as List;
                                            final double targetLat =
                                                (data[1] as num).toDouble();
                                            final double targetLng =
                                                (data[2] as num).toDouble();
                                            final double tolerance =
                                                (data[3] as num).toDouble();
                                            final double zone2 =
                                                tolerance + gpsAccuracy * 2;
                                            final double distance =
                                                Geolocator.distanceBetween(
                                                  targetLat,
                                                  targetLng,
                                                  gpsPosition!.latitude,
                                                  gpsPosition!.longitude,
                                                );
                                            if (distance < minDistance) {
                                              minDistance = distance;
                                              matchZone2 = zone2;
                                            }
                                            if (distance <= zone2) {
                                              insideAny = true;
                                              break;
                                            }
                                          }
                                          debugPrint(
                                            '[qrScan/otq_txf_2] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                                          );
                                          if (!insideAny) {
                                            outBlocked = true;
                                            if (context.mounted) {
                                              await Get.dialog(
                                                AlertDialog(
                                                  title: Text(
                                                    textArray.length > 14
                                                        ? textArray[14]
                                                        : 'Diluar Area Absensi',
                                                  ),
                                                  content: Text(
                                                    textArray.length > 15
                                                        ? textArray[15]
                                                        : 'Silahkan menuju lokasi yang ditentukan',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      child: const Text('OK'),
                                                      onPressed: () =>
                                                          Get.back(),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          }
                                        } catch (eLoc) {
                                          debugPrint(
                                            '[qrScan/otq_txf_2] parse error: $eLoc — bypass pengecekan',
                                          );
                                        }
                                      } else {
                                        if (!internetConnected()) {
                                          debugPrint(
                                            '[qrScan/otq_txf_2] offline & #LQR_LIST kosong/null — block absensi',
                                          );
                                          outBlocked = true;
                                          if (context.mounted) {
                                            await Get.dialog(
                                              AlertDialog(
                                                title: Text(
                                                  textArray.length > 14
                                                      ? textArray[14]
                                                      : 'Diluar Area Absensi',
                                                ),
                                                content: Text(
                                                  textArray.length > 15
                                                      ? textArray[15]
                                                      : 'Silahkan menuju lokasi yang ditentukan',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text('OK'),
                                                    onPressed: () => Get.back(),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        } else {
                                          debugPrint(
                                            '[qrScan/otq_txf_2] online & #LQR_LIST kosong/null — bypass pengecekan',
                                          );
                                        }
                                      }
                                    }
                                    if (outBlocked) return;
                                    actionLock('qrScan otq_txf');
                                    String? rawQRText = await takeQR(
                                      context,
                                      textArray.length > 3
                                          ? textArray[3]
                                          : 'Scan QR',
                                      scrName,
                                      component,
                                      'txt',
                                    );
                                    if (rawQRText != null &&
                                        rawQRText != emptyString &&
                                        rawQRText != 'null') {
                                      String qrResult = (await getQRContent(
                                        qrType,
                                        rawQRText,
                                        gpsPosition,
                                        component['table'],
                                        component['refTableNegative'],
                                        component['cluster'],
                                      )).toString();
                                      if (qrResult.substring(0, 6) !=
                                          textList["ErrorPrefix"]) {
                                        Map<String, dynamic> refTable = {};
                                        if (component['table'] == null ||
                                            component['table']
                                                .toString()
                                                .trim()
                                                .isEmpty) {
                                          if (qrType == 'L') {
                                            refTable = transactionStore
                                                .state
                                                .screenTx['#LQR_LIST'];
                                          }
                                        } else {
                                          refTable = transactionStore
                                              .state
                                              .screenTx['#TABLE${component['table']}'];
                                        } // end if (component['table'] == null)
                                        // refTable ??= {};
                                        setState(() {
                                          if (refTable[qrResult] != null) {
                                            myController.text =
                                                refTable[qrResult][0]
                                                    .toString();
                                            txfController[widget
                                                        .scrName]![component['position']]!
                                                    .finalData =
                                                qrResult;
                                            if (component['locationNamePosition'] !=
                                                    null &&
                                                component['locationNamePosition']
                                                    .toString()
                                                    .trim()
                                                    .isNotEmpty) {
                                              try {
                                                txfControllerCheck(
                                                  widget.scrName,
                                                  widget
                                                      .component['locationNamePosition'],
                                                );
                                                txfController[widget
                                                            .scrName]![component['locationNamePosition']]!
                                                        .finalData =
                                                    refTable[qrResult][0]
                                                        .toString();
                                              } catch (e) {
                                                // do nothing
                                                devPrint(e);
                                              } // end try
                                            } // end if (component['locationNamePosition']
                                          } else {
                                            txfController[widget
                                                        .scrName]![component['position']]!
                                                    .finalData =
                                                '';
                                            if (qrType == 'L') {
                                              myController.text =
                                                  textList["QRError"]; // location not defined #Error02
                                            } else if (qrType == 'U') {
                                              myController.text =
                                                  textList['QRNotListed2']; // location not defined #Error05
                                            } else {
                                              myController.text = qrResult;
                                              txfController[widget
                                                          .scrName]![component['position']]!
                                                      .finalData =
                                                  qrResult;
                                              if (component['locationNamePosition'] !=
                                                      null &&
                                                  component['locationNamePosition']
                                                      .toString()
                                                      .trim()
                                                      .isNotEmpty) {
                                                try {
                                                  txfControllerCheck(
                                                    widget.scrName,
                                                    widget
                                                        .component['locationNamePosition'],
                                                  );
                                                  txfController[widget
                                                              .scrName]![component['locationNamePosition']]!
                                                          .finalData =
                                                      qrResult;
                                                  // textList['QRNotListed2'];
                                                } catch (e) {
                                                  // do nothing
                                                } // end try
                                              } // end if (component['locationNamePosition']
                                            } // end if (qrType == 'L')
                                          } // end if (refTable[qrResult] != null)
                                        });
                                      } else {
                                        txfController[widget
                                                    .scrName]![component['position']]!
                                                .finalData =
                                            '';
                                        switch (qrResult.substring(6, 8)) {
                                          case '01': //out of range
                                            myController.text =
                                                textArray.length > 14
                                                ? textArray[14]
                                                : textList['GPSOutOfRange'];
                                            break;

                                          case '02': // no qr result
                                            myController.text =
                                                textArray.length > 11
                                                ? textArray[11]
                                                : textList["QRError"];
                                            break;

                                          case '05': //user not in list
                                            myController.text =
                                                textArray.length > 8
                                                ? textArray[8]
                                                : textList['QRNotListed2'];
                                            break;

                                          case '98': //qr not recognized
                                            myController.text =
                                                textArray.length > 10
                                                ? textArray[10]
                                                : textList['QRError'];
                                            break;

                                          default:
                                            myController.text =
                                                textList['GeneralError'];
                                        } // end switch (q
                                      } // end if (qrResult.substring(0,6) != '#Error')
                                    }
                                    setDataOK(
                                      '2',
                                    ); // reload pages and display green status.
                                  } // end if !transactionStore.state.screenTx['#DATA_OK']
                                }
                              : null,
                        ),
                      ],
                    );
                    element = pillWrap(element);
                  }
                  break;

                case 'qrAttend1': // barcode4 => scanner
                  {
                    BlocProvider.of<MainBloc>(context).add(
                      QrAttend1Scan(
                        front: component['front'] ?? false,
                        flash: component['flash'] ?? false,
                        size: component['size'] ?? 300,
                        fSize: component['dataFont'] ?? 16,
                        exitSize: component['exitFont'] ?? 16,
                        exitRoute: component['route'] ?? home,
                        //                      crypto: 'attend1',
                        crypto: 'raw',
                        exitString: component['exitText'] ?? 'Exit',
                        position: component['position'] ?? 1,
                        screenName: scrName,
                      ),
                    );
                  }
                  break;
                default:
                  {
                    element = pillWrap(
                      !(sttEnabled && editable)
                          ? txf
                          : Row(
                              children: <Widget>[
                                Expanded(child: txf),
                                IconButton(
                                  icon: Icon(
                                    _sttListening ? Icons.mic : Icons.mic_none,
                                    size: 8.0 + (component['size'] ?? 16.0),
                                    color: _sttListening ? Colors.red : null,
                                  ),
                                  tooltip: 'Suara',
                                  onPressed: isEnabled ? _sttToggle : null,
                                ),
                              ],
                            ),
                    );
                  }
              } // end switch (component['variant'].toString().toLowerCase())

              if (showTitle || hasIcon) {
                element = Container(
                  margin: EdgeInsets.only(
                    top: margin[0],
                    bottom: margin[1],
                    left: widget.lPad + margin[2],
                    right: widget.rPad + margin[3],
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            if (hasIcon) ...[
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  otqIcons[iconKey],
                                  size: 14,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              labelStr.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      element,
                    ],
                  ),
                );
              }
              return element;
            }, // end of builder
          );
        } catch (e) {
          result = Text('--TXF-- (otq_txt): $e');
        }
        return result;
      },
    );
  } // end of build

  @override
  bool get wantKeepAlive => true;
} // end of class _TxfFullState
