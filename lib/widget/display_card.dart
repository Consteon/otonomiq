import 'dart:math';
import 'package:flutter/material.dart';
import '../widget/ui_component.dart';
import '../global.dart';

class DisplayCard extends StatefulWidget {
  const DisplayCard({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  State<DisplayCard> createState() => _DisplayCardState();
}

class _DisplayCardState extends State<DisplayCard> {
  late List<double> margin;
  late List<Widget> dialogWidgets;
  bool hasChain = false;

  @override
  void initState() {
    super.initState();
    margin = marginArray(widget.component['margin']);
    dialogWidgets =
        buildColumnPage(widget.component['children'], widget.scrName, dialog: true);
    hasChain = widget.component['chain'] != null;
  }

  @override
  Widget build(BuildContext context) {
    List<double> margin = marginArray(widget.component['margin']);
    return Container(
      margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
      padding: EdgeInsets.fromLTRB(max(0, widget.lPad + margin[2] - 3),
          widget.tPad, max(0, widget.rPad + margin[3] - 3), widget.bPad),
      // child: GestureDetector(
      child: Card(
        // child: ListView.builder(
        //   // controller: _scrollController,
        //   shrinkWrap: true,
        //   itemCount: dialogWidgets.length,
        //   itemBuilder: (context, position) {
        //     return dialogWidgets[position];
        //   }, // end of itemBuilder
        // ),
        child: Column(
          // crossAxisAlignment: CrossAxisAlignment.start,
          children: dialogWidgets,
        ),
      ),
      // onTap: () async {
      //   if (widget.component['route'] != null &&
      //       widget.component['route'] != rootThis.pageName) {
      //     if (widget.component['route'].length >= 4 &&
      //         widget.component['route'].substring(0, 4).toLowerCase() ==
      //             'http') {
      //       openInWebView(context, widget.component['route'],
      //           widget.component['title']);
      //     } // end if route.length
      //   } // end if route != null
      //   if (hasChain) {
      //     await doChain(context, widget.scrName, widget.component['chain']);
      //   }
      // }, // end of onTap
      // ),
    );
  }
}
