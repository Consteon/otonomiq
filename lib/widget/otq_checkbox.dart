import 'package:flutter/material.dart';

import '../global2.dart';

class OtqCheckbox extends StatefulWidget {
  const OtqCheckbox({
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
  final dynamic lPad;
  final dynamic tPad;
  final dynamic rPad;
  final dynamic bPad;
  @override
  _OtqCheckboxState createState() => _OtqCheckboxState();
}

class _OtqCheckboxState extends State<OtqCheckbox> {
  late bool enabled;

  @override
  void initState() {
    super.initState();
    enabled = widget.component['data'].toString().toUpperCase() == 'TRUE';
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }

  Widget childrenBuilder(var component, String scrName, bool enabled) {
    return Container(
      margin: EdgeInsets.only(
        top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
        bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble(),
      ),
      padding: EdgeInsets.fromLTRB(
        //          widget.lPad + (widget.component['leftPadding'] ?? 0.0).toDouble(),
        //          widget.tPad,
        //          widget.rPad + (widget.component['rightPadding'] ?? 0.0).toDouble(),
        //          widget.bPad),
        (widget.component['leftPadding'] ?? 0.0).toDouble(),
        0,
        (widget.component['rightPadding'] ?? 0.0).toDouble(),
        0,
      ),
      child: widget.component['orientation'] == 'ltr'
          ? Row(
              children: <Widget>[
                Checkbox(
                  value: enabled,
                  //                  checkColor: Colors.black,
                  //                  activeColor: Colors.red,
                  onChanged: (val) {
                    setState(() {
                      enabled = val!;
                    });
                    if (widget.component['position'] != null) {
                      txfController[widget.scrName]![widget.key]!
                          .controller
                          .text = val!
                          ? 'TRUE'
                          : 'FALSE';
                    }
                  },
                ),
                Flexible(
                  child: GestureDetector(
                    child: Text(
                      widget.component['text'],
                      //                style:
                      //                TextStyle(color: Color(hexToInt('FFF57F17'))),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Flexible(
                  child: GestureDetector(child: Text(widget.component['text'])),
                ),
                Checkbox(
                  value: enabled,
                  onChanged: (val) {
                    setState(() {
                      enabled = val!;
                    });
                    if (widget.component['position'] != null) {
                      txfController[widget.scrName]![widget.key]!
                          .controller
                          .text = val!
                          ? 'TRUE'
                          : 'FALSE';
                    }
                  },
                ),
              ],
            ), // put child here
    );
  }
}
