import 'package:flutter/material.dart';
import '../global.dart';
import '../global2.dart';
import 'package:intl/intl.dart';
import '../otq_icons.dart';

import '../api.dart';

class TxfPlain extends StatefulWidget {
  const TxfPlain({required Key key, required this.scrName, required this.component})
      : super(key: key);
  final String scrName;
  final dynamic component;

  @override
  _TxfPlainState createState() => _TxfPlainState();
}

class _TxfPlainState extends State<TxfPlain> {
  int radioValue = -1;
  bool touch = true;

  @override
  Widget build(BuildContext context) {
    Widget result;
    var component = widget.component;
    String scrName = widget.scrName;
    final txfKey = widget.key;
    double lPad = (systemUIComponent['Mobile']['leftPad'] ?? 0.0).toDouble();
    double tPad = (systemUIComponent['Mobile']['topPad'] ?? 0.0).toDouble();
    double rPad = (systemUIComponent['Mobile']['rightPad'] ?? 0.0).toDouble();
    double bPad = (systemUIComponent['Mobile']['bottomPad'] ?? 0.0).toDouble();

    DateTime? convertToDate(String input) {
      try {
        var d = DateFormat(shortDateFormat).parseStrict(input);
        return d;
      } catch (e) {
        return null;
      }
    } // end of function convertToDate

    Future chooseDate(BuildContext context, String initialDateString) async {
      var now = DateTime.now();
      var initialDate = convertToDate(initialDateString) ?? now;
      initialDate = (initialDate.year >= minYear ? initialDate : now);

      var result = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(minYear),
        lastDate: DateTime(DateTime.now().year + maxPlusYear),
      );

      if (result == null) return;
      txfController[scrName]![getPosition(component['position'])]!.controller.text =
          DateFormat(shortDateFormat).format(result);
    } // end of function _chooseDate

    try {
      inputTxt[txfKey!] = component['currentValue']??"";

      if (component['position'] != null) {
        txfControllerCheck(
            scrName, component['position']); // build txfController if necessary
        if (canInitializePage(scrName)) {
          txfController[scrName]![component['position']]!.controller.text =
              component['currentValue'] ?? "";
          txfController[scrName]![component['position']]!.finalData =
              emptyString;
          txfController[scrName]![component['position']]!.initialValue =
              component['currentValue'] ?? "";
        } // end if (canInitializePage(widget.scrName))
      } // end if (widget.component['position'] != null)

      // if (txfController[scrName]![component['position']] == null) {
      //   txfController[scrName]![component['position']] = InputController(
      //       component['position'],
      //       TextEditingController(text: component['currentValue']??""),
      //       component['currentValue'] ?? '',
      //       emptyString);
      // } else {
      //   txfController[scrName]![component['position']]!.controller.text =
      //       component['currentValue'] ?? "";
      //   txfController[scrName]![component['position']]!.finalData =
      //       emptyString;
      //   txfController[scrName]![component['position']]!.initialValue =
      //       component['currentValue'] ?? "";
      // } // end if (txfController[scrName]![component['position']] == null)
      Widget element;
      TextInputType kbType;
      switch (component['variant']) {
        case 'date':
          {
            kbType = TextInputType.datetime;
          }
          break;
        case 'numeric':
          {
            kbType = TextInputType.number;
          }
          break;
        default:
          {
            kbType = TextInputType.text;
          }
      }

      Widget txf = Builder(
        builder: (context) {
          return TextFormField(
            keyboardType: kbType,
            key: txfKey,
            controller: txfController[scrName]![component['position']]!.controller,
            decoration: InputDecoration(
              icon: (component['icon'] ?? 0) > 0
                  ? Icon(
                      otqIcons[component['icon'].toString()],
                    )
                  : null,
              hintText: component['hint'] ?? ' ',
              labelText: component['label'] ?? ' ',
            ),
            style: TextStyle(
              color: (component['color'] ?? 'default') != 'default'
                  ? Color(int.parse(component['color']))
                  : Theme.of(context).textTheme.bodyMedium!.color,
              backgroundColor:
                  (component['background'] ?? 'default') != 'default'
                      ? Color(int.parse(component['background']))
                      : Theme.of(context).textTheme.bodyMedium!.backgroundColor,
              fontWeight: (component['bold'] ?? 'FALSE') == 'TRUE'
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: (component['italic'] ?? 'FALSE') == 'TRUE'
                  ? FontStyle.italic
                  : FontStyle.normal,
              decoration: (component['underline'] ?? 'FALSE') == 'TRUE'
                  ? TextDecoration.underline
                  : TextDecoration.none,
              fontSize: 0.0 + component['size'],
            ),
            obscureText: (component['variant'] ?? 'generic') == 'password'
                ? true
                : false,
            onFieldSubmitted: (String value) {
              inputTxt[txfKey] = value;
            },
          ); // end of txf
        },
      );

      switch (component['variant']) {
        case 'date':
          {
            element = GestureDetector(
              onTap: (() {
                chooseDate(
                    context, txfController[scrName]![component['position']]!.controller.text);
              }),
              child: AbsorbPointer(
                child: txf,
              ),
            );
          }
          break;
        default:
          {
            element = txf;
          }
      }

      result = Container(
        margin: EdgeInsets.only(
            top: (component['beforeSpacing'] ?? 0.0).toDouble(),
            bottom: (component['afterSpacing'] ?? 0.0).toDouble()),
        padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
        child: element,
      );
    } catch (_) {
      result = const Text('--TXF--');
    }

    return result;
  }
}
