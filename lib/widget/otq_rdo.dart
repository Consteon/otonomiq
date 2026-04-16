import 'package:flutter/material.dart' hide RadioGroup;
import 'package:group_radio_button/group_radio_button.dart';
import '../global.dart';
import '../global2.dart';
import '../otq_icons.dart';
import '../api.dart';
import 'otq_formatted_text.dart';
// https://pub.dev/packages/grouped_buttons#-example-tab-

class OtqRdo extends StatefulWidget {
  const OtqRdo({
    required Key key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  }) : super(key: key);
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  _OtqRdoState createState() => _OtqRdoState();
}

class _OtqRdoState extends State<OtqRdo>
    with AutomaticKeepAliveClientMixin<OtqRdo> {
  String? _picked;
  List<double> margin = [];
  List<String> menu = [];
  Axis axis = Axis.vertical;
  MainAxisAlignment align = MainAxisAlignment.start;

  @override
  initState() {
    super.initState();
    _picked = widget.component['currentValue'];

    if (widget.component['position'] != null) {
      txfControllerCheck(
          widget.scrName, widget.component['position']); // build txfController if necessary
      if (canInitializePage(widget.scrName)) {
        txfController[widget.scrName]![widget.component['position']]!.finalData =
            _picked ?? "";
        txfController[widget.scrName]![widget.component['position']]!
            .initialValue = _picked ?? "";
      } // end if (canInitializePage(widget.scrName))
    } // end if (widget.component['position'] != null)

    // if (widget.component['position'] != null &&
    //     txfController[widget.scrName]![widget.component['position']] == null) {
    //   txfController[widget.scrName]![widget.component['position']] =
    //       InputController(
    //           widget.component['position'],
    //           TextEditingController(),
    //           widget.component['currentValue'] ?? "",
    //           widget.component['currentValue'] ?? emptyString);
    // } else {
    //   txfController[widget.scrName]![widget.component['position']]!.finalData =
    //       _picked ?? "";
    //   txfController[widget.scrName]![widget.component['position']]!
    //       .initialValue = _picked ?? "";
    // } // end if (txfController[scrName]![_component['position']] == null)
    margin = marginArray(widget.component['margin']);
    menu = List<String>.from(widget.component['menu'] ?? ['--']);
    axis = (widget.component['buttonLayout'] ?? 'vertical')
                .toString()
                .toLowerCase() ==
            'horizontal'
        ? Axis.horizontal
        : Axis.vertical;
    align = mainAlignmentConst(widget.component['alignment']);
  } // end of initState()

  @override
  Widget build(BuildContext context) {
    super.build(context); // needed by AutomaticKeepAliveClientMixin
    try {
      var component = widget.component;
      List<String> menu = List<String>.from(widget.component['menu'] ?? ['--']);

      return Container(
        margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
        padding: EdgeInsets.fromLTRB(widget.lPad + margin[2], widget.tPad,
            widget.rPad + margin[3], widget.bPad),
        child: Column(
          children: <Widget>[
            (widget.component['labelPosition'] ?? 'right')
                        .toString()
                        .toLowerCase() ==
                    'left'
                ? Row(
                    mainAxisAlignment: align,
                    children: <Widget>[
                      OtqFormattedText(
                        textData: widget.component['label'] ?? "",
                        component: widget.component,
                      ),
                      (component['icon'].toString().isNotEmpty)
                          ? Icon(otqIcons[component['icon'].toString()])
                          : Container(),
                    ],
                  )
                : Row(
                    mainAxisAlignment: align,
                    children: <Widget>[
                      (component['icon'].toString().isNotEmpty)
                          ? Icon(otqIcons[component['icon'].toString()])
                          : Container(),
                      (component['icon'].toString().isNotEmpty)
                          ? Container(
                              width: (component['icon'].toString().isNotEmpty)
                                  ? 16
                                  : 0,
                            )
                          : Container(),
                      OtqFormattedText(
                        textData: widget.component['label'] ?? "",
                        component: widget.component,
                      ),
                    ],
                  ),
            RadioGroup<String>.builder(
              groupValue: _picked ?? "",
              direction: axis,
              horizontalAlignment:
                  mainAlignmentConst(widget.component['alignment']),
              onChanged: (value) => setState(() {
                _picked = value;
                if (widget.component['position'] != null) {
                  txfControllerCheck(
                      widget.scrName, widget.component['position']);
                  txfController[widget.scrName]![widget.component['position']]!
                      .finalData = _picked ?? "";
                } // end if (widget.component['position'] != null)
              }),
              items: menu,
              itemBuilder: (item) => RadioButtonBuilder(
                item,
                textPosition:
                    ((axis == Axis.vertical) && align == MainAxisAlignment.end)
                        ? RadioButtonTextPosition.left
                        : RadioButtonTextPosition.right,
              ),
            ),
          ],
        ),
      );
    } catch (err) {
      return Text("--Radio Button (RDO)-- [ $err]");
    }
  } // end of build

  @override
  bool get wantKeepAlive => true;
} // end of class _OtqRdoState
