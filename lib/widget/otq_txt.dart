import 'package:flutter/material.dart';
import '../api.dart';
import '../global.dart';
import 'approver_sticky_bar.dart';
import 'item_card_detail.dart';
import 'otq_formatted_text.dart';

class OtqTxt extends StatelessWidget {
  const OtqTxt({
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
  Widget build(BuildContext context) {
    String searchStr = (component['search'] ?? '').toString().trim();
    if (searchStr.isNotEmpty) {
      List<dynamic> row = ItemCardDetail.currentRow.value;
      if (row.isNotEmpty && !evaluateRbtSearch(searchStr, row)) {
        return const SizedBox.shrink();
      }
    }
    List<double> margin = marginArray(component['margin']);
    return Container(
      margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
      padding:
          EdgeInsets.fromLTRB(lPad + margin[2], tPad, rPad + margin[3], bPad),
      child: SingleChildScrollView(
        child: GestureDetector(
          child: OtqFormattedText(
            textData: component['data'],
            component: component,
          ),
          onTap: () {
            if (component['route'] != null &&
                component['route'] != rootThis.pageName) {
              if (component['route'].length >= 4 &&
                  component['route'].substring(0, 4).toLowerCase() == 'http') {
                openInWebView(context, component['route'],
                    component['title']);
              } // end if route.length
            } // end if route != null
          }, // end of onTap
        ),
      ),
    );
  } // end of build
} // end of class OtqTxt
