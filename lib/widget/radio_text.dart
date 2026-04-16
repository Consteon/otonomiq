import 'package:flutter/material.dart';
import '../global.dart';
import '../global2.dart';
import 'package:intl/intl.dart';
import '../otq_icons.dart';

//got guidance of inheritedWidget from https://www.didierboelens.com/2018/06/widget---state---context---inheritedwidget/

// ==================================== _RadioInherited
class _RadioInherited extends InheritedWidget {
  const _RadioInherited({
    required Key super.key,
    required super.child,
    required this.data,
  });

  final RadioInheritedWidgetState data;

  @override
  bool updateShouldNotify(_RadioInherited oldWidget) {
    return true;
  }
}

//======================== RadioInheritedWidget
class RadioInheritedWidget extends StatefulWidget {
  const RadioInheritedWidget(
      {required Key key,
      required BuildContext context,
      required this.child,
      required this.radKey})
      : super(key: key);

  final Widget child;
  final Key radKey;
  //final BuildContext context;

  @override
  RadioInheritedWidgetState createState() => RadioInheritedWidgetState();

  static RadioInheritedWidgetState of(
      [BuildContext? context, bool rebuild = true]) {
    return (rebuild
            ? context?.dependOnInheritedWidgetOfExactType<_RadioInherited>()
            : context?.findAncestorWidgetOfExactType<_RadioInherited>())!
        .data;
  }
}

class RadioInheritedWidgetState extends State<RadioInheritedWidget> {
  bool refreshState = true;
  int? selected;

  int? get radioSelected => selected; // getter
  void refresh(int val) {
    // helper (setter)
    setState(() {
      refreshState = !refreshState;
      selected = val;
    });
  }

  @override
  void initState() {
    super.initState();
    selected = inputInt[widget.radKey];
  }

  @override
  Widget build(BuildContext context) {
    return _RadioInherited(
      key: UniqueKey(),
      data: this,
      child: widget.child,
    );
  }
}

//================================== RadioBtn
class RadioBtn extends StatefulWidget {
  const RadioBtn({
    required Key key,
    required this.scrName,
    required this.component,
    required this.txtKey,
    required this.radKey,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final Key txtKey;
  final Key radKey;

  @override
  _RadioBtnState createState() => _RadioBtnState();
}

class _RadioBtnState extends State<RadioBtn> {
  late int radioValue;
  bool touch = true;

  @override
  void initState() {
    super.initState();
    radioValue = inputInt[widget.radKey]!;
    touch = true;
  }

  @override
  Widget build(BuildContext context) {
    final RadioInheritedWidgetState rState = RadioInheritedWidget.of(context);
    Widget result;
    List<Widget> radioWidget = <Widget>[];
    var component = widget.component;
    String scrName = widget.scrName;
    Key radioKey = widget.radKey;
    Key txtKey = widget.txtKey;

    try {
      if (inputInt[widget.radKey] != rState.radioSelected) {
        inputInt[widget.radKey] = rState.radioSelected!;
        setState(() {
          radioValue = rState.radioSelected!;
          touch = !touch;
        });
      }
      var radio = component['children'];
      for (var idx = 0; idx < radio.length; idx++) {
        radioWidget.add(Row(
          key: UniqueKey(),
          children: <Widget>[
            Radio(
              value: idx,
              groupValue: radioValue,
              onChanged: (int? i) {
                inputInt[radioKey] = i!;
                setState(() {
                  touch = !touch;
                  radioValue = i;
                });
                if (component['position'] != null) {
                  txfController[scrName]![component['position']]!
                      .controller
                      .text = radio[i];
                } // end if (component['position']!=null)
                rState.refresh(i); // refresh data in inherited parent
              },
            ),
            Text(radio[idx],
                style: TextStyle(
                  fontSize: 0.0 + (component['size'] ?? 16.0),
                )),
          ],
        ));
      }
      result = Builder(
        builder: ((context) {
          return Column(
//            key: widget.radKey,
            children: radioWidget,
          );
        }),
      );
    } catch (_) {
      result = const Text('--Radio Button--');
    }

    return result;
  }
}

//========================================= RTxf
class RTxf extends StatefulWidget {
  const RTxf({required Key key, required this.scrName, required this.component})
      : super(key: key);
  final String scrName;
  final dynamic component;

  @override
  _RTxfState createState() => _RTxfState();
}

class _RTxfState extends State<RTxf> {
  @override
  Widget build(BuildContext context) {
    final RadioInheritedWidgetState rState =
        RadioInheritedWidget.of(context, false);
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
      if (widget.component['position'] != null) {
        txfControllerCheck(widget.scrName, widget.component['position']);
        txfController[scrName]![widget.component['position']]!.controller.text =
            DateFormat(shortDateFormat).format(result);
      }
      rState.refresh(-1); // refresh Radio button, set selected to none
    } // end of function _chooseDate

    try {
//      inputTxt[_txfKey] = component['currentValue'];
//      txfController[scrName][_txfKey] = InputController(
//          component['position'],
//          TextEditingController(text: inputTxt[_txfKey]),
//          component['currentValue'] ?? '');
      Widget element;
      dynamic kbType;
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
            controller: txfController[scrName]![widget.component['position']]!
                .controller,
            decoration: InputDecoration(
              icon: (component['icon'] ?? 0) > 0
                  ? Icon(otqIcons[component['icon'].toString()])
                  : null,
              hintText: component['hint'] ?? ' ',
              labelText: component['label'] ?? ' ',
            ),
            style: TextStyle(
              color: (component['color'] ?? 'default') != 'default'
                  ? Color(int.parse(component['color']))
                  : Theme.of(context).textTheme.bodyLarge!.color,
              backgroundColor:
                  (component['background'] ?? 'default') != 'default'
                      ? Color(int.parse(component['background']))
                      : Theme.of(context).textTheme.bodyLarge!.backgroundColor,
              fontWeight: (component['bold'] ?? 'FALSE') == 'TRUE'
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: (component['italic'] ?? 'FALSE') == 'TRUE'
                  ? FontStyle.italic
                  : FontStyle.normal,
              decoration: (component['underline'] ?? 'FALSE') == 'TRUE'
                  ? TextDecoration.underline
                  : TextDecoration.none,
              fontSize: 0.0 + (component['size'] ?? 16.0),
            ),
            obscureText: (component['variant'] ?? 'generic') == 'password'
                ? true
                : false,
            onFieldSubmitted: (String value) {
              inputTxt[txfKey!] = value;
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
                    context,
                    txfController[scrName]![widget.component['position']]!
                        .controller
                        .text);
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

//================================== RadioText
class RadioText extends StatefulWidget {
  const RadioText({
    required Key key,
    required this.scrName,
    required this.component,
    required this.txtKey,
    required this.radKey,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final Key txtKey;
  final Key radKey;
  @override
  _RadioTextState createState() => _RadioTextState();
}

class _RadioTextState extends State<RadioText> {
  @override
  Widget build(BuildContext context) {
    Widget result;
    var component = widget.component;
    String scrName = widget.scrName;

    try {
      Widget rdWidget = RadioBtn(
        key: widget.radKey,
        scrName: scrName,
        component: component,
        txtKey: widget.txtKey,
        radKey: widget.radKey,
      );
      Widget txfWidget = RTxf(
        key: widget.txtKey,
        scrName: scrName,
        component: component,
      );
      result = RadioInheritedWidget(
        key: UniqueKey(),
        context: context,
        radKey: widget.radKey,
        child: Column(
          children: <Widget>[
            rdWidget,
            txfWidget,
          ],
        ),
      );
    } catch (_) {
      result = const Text('--RTF--');
    }
    return result;
  }
}
