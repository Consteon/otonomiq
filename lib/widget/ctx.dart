import 'package:flutter/material.dart';
import '../global.dart';
import '../global2.dart';
import '../api.dart';

class Swc extends StatefulWidget {
  const Swc({required Key key, required this.scrName, required this.component})
      : super(key: key);
  final dynamic component;
  final String scrName;

  @override
  _SwcState createState() => _SwcState();
}

class _SwcState extends State<Swc> {
  bool? cekValue = false;

  @override
  void initState() {
    final String initValue = (widget.component['currentValue'] ?? 'FALSE')
        .toString()
        .toUpperCase()
        .trim();

    if (widget.component['position'] != null) {
      txfControllerCheck(
          widget.scrName,
          widget.component['position']); // build txfController if necessary
      if (canInitializePage(widget.scrName)) {
        txfController[widget.scrName]![getPosition(
            widget.component['position'])]!
            .controller
            .text = initValue;
        txfController[widget.scrName]![getPosition(
            widget.component['position'])]!
            .finalData = emptyString;
        txfController[widget.scrName]![getPosition(
            widget.component['position'])]!
            .initialValue = initValue;
      } // end if (canInitializePage(widget.scrName))
    } // end if (widget.component['position'] != null)

    // if (widget.component['position'] != null) {
    //   if (txfController[widget.scrName]![getPosition(widget.component['position'])] == null) {
    //     txfController[widget.scrName]![getPosition(widget.component['position'])] =
    //         InputController(getPosition(widget.component['position']),
    //             TextEditingController(text: initValue), initValue, emptyString);
    //   } else {
    //     txfController[widget.scrName]![getPosition(widget.component['position'])]!
    //         .controller
    //         .text = initValue;
    //     txfController[widget.scrName]![getPosition(widget.component['position'])]!
    //         .finalData = emptyString;
    //     txfController[widget.scrName]![getPosition(widget.component['position'])]!
    //         .initialValue = initValue;
    //   } // end if (txfController[widget.scrName]![widget.component['position']] == null)
    // }
    cekValue =
        widget.component['currentValue'].toString().trim().toUpperCase() ==
            'TRUE';
    super.initState();
  }

  @override
  void dispose() {
    //txfController[widget.scrName]![widget.key!]!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget element = Container(
      child: (widget.component['variant'] ?? "").trim().toLowerCase() ==
              'checkbox'
          ? Checkbox(
              value: cekValue,
              onChanged: (bool? value) {
                setState(() => cekValue = value);
                txfController[widget.scrName]![getPosition(widget.component['position'])]!
                    .controller
                    .text = value.toString().toUpperCase();
              },
            )
          : Switch(
              value: cekValue!,
              onChanged: (bool? value) {
                setState(() => cekValue = value);
                txfController[widget.scrName]![getPosition(widget.component['position'])]!
                    .controller
                    .text = value.toString().toUpperCase();
              },
            ),
    );
    return element;
  }
}
