import '../global.dart';
import '../global2.dart';
import 'package:flutter/material.dart';
import 'otq_formatted_text.dart';

class OtqSwitch extends StatefulWidget {
  const OtqSwitch({
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
  _OtqSwitchState createState() => _OtqSwitchState();
}

class _OtqSwitchState extends State<OtqSwitch>
    with AutomaticKeepAliveClientMixin<OtqSwitch> {
  bool enabled = false;
  late Widget sw;
  List<double> margin = [];

  @override
  void initState() {
    super.initState();
    enabled = (widget.component['currentValue'] ?? 'false')
            .toString()
            .toLowerCase() ==
        'true';

    // if (txfController[widget.scrName]![widget.component['position']] == null) {
    //   txfController[widget.scrName]![widget.component['position']] =
    //       InputController(
    //           widget.component['position'] ?? "",
    //           TextEditingController(),
    //           widget.component['currentValue'] ?? "",
    //           widget.component['currentValue'] ?? emptyString);
    // } else {
    //   txfController[widget.scrName]![widget.component['position']]!.finalData =
    //       enabled ? "TRUE" : "FALSE";
    //   txfController[widget.scrName]![widget.component['position']]!
    //       .initialValue = enabled ? "TRUE" : "FALSE";
    // } // end if (txfController[scrName]![_component['position']] == null)
    margin = marginArray(widget.component['margin']);
  } // end of initState

  @override
  Widget build(BuildContext context) {
    super.build(context); // needed by AutomaticKeepAliveClientMixin
    String variant =
        (widget.component['variant'] ?? 's').toString().toLowerCase();
    if (variant == 'checkbox') {
      sw = Checkbox(
        value: enabled,
        onChanged: (val) {
          setState(() {
            enabled = val ?? false;
          });
          if (widget.component['position'] != null) {
            txfController[widget.scrName]![widget.component['position']]!
                .finalData = enabled ? 'TRUE' : 'FALSE';
          }
        },
      ); // end of Checkbox
    } else {
      sw = Switch(
        value: enabled,
        onChanged: (val) {
          setState(() {
            enabled = val;
          });
          if (widget.component['position'] != null) {
            txfControllerCheck(widget.scrName, widget.component['position']);
            txfController[widget.scrName]![widget.component['position']]!
                .finalData = enabled ? 'TRUE' : 'FALSE';
          }
        },
      ); // end of Switch
    } // end if variant
    return Container(
      margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
      padding: EdgeInsets.fromLTRB(widget.lPad + margin[2], widget.tPad,
          widget.rPad + margin[3], widget.bPad),
      child: (widget.component['labelPosition'] ?? "left")
                  .toString()
                  .toLowerCase() ==
              'right'
          ? Row(
              mainAxisAlignment: mainAlignmentConst(widget.component['alignment']),
              children: <Widget>[
                sw,
                OtqFormattedText(
                  textData: widget.component['label'] ?? "",
                  component: widget.component,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: mainAlignmentConst(widget.component['alignment']),
              children: <Widget>[
                OtqFormattedText(
                  textData: widget.component['label'] ?? "",
                  component: widget.component,
                ),
                sw,
              ],
            ), // put child here
    );
  } // end of build

  @override
  bool get wantKeepAlive => true;
} // end of class _OtqSwitchState
