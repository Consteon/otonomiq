import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../global.dart';
import 'approver_sticky_bar.dart';
import 'driver_home_support.dart';
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
    // DriverHome (P4) state-aware label hook.
    //
    // W2 / JSON CONTRACT: this swap ONLY activates when the component carries a
    // `stateSwitch` field (e.g. the op1Screen DriverHome label, row 1010, must
    // be `"stateSwitch":"HARI INI"`). Without that field the check below
    // short-circuits and OtqTxt behaves exactly as before — zero impact on the
    // thousands of other TXT components that lack it. When present, the label
    // shows `component['data']` (pending text, e.g. "SEBELUM BERANGKAT") and
    // swaps to `stateSwitch` once DriverHomeState.confirmed flips true.
    final String switchText = (component['stateSwitch'] ?? '')
        .toString()
        .trim();
    if (switchText.isNotEmpty) {
      // Obx so the label rebuilds when DriverHomeState.confirmed changes.
      return Obx(() => _buildContent(context, switchText));
    }
    return _buildContent(context, '');
  } // end of build

  Widget _buildContent(BuildContext context, String switchText) {
    // Determine display text: if switchText is set and state is confirmed,
    // show switchText; otherwise show component['data'].
    String displayData = (component['data'] ?? '').toString();
    if (switchText.isNotEmpty) {
      final DriverHomeState? state = driverHomeStates[scrName];
      if (state != null && state.confirmed.value) {
        displayData = switchText;
      }
    }

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
      padding: EdgeInsets.fromLTRB(
        lPad + margin[2],
        tPad,
        rPad + margin[3],
        bPad,
      ),
      child: SingleChildScrollView(
        child: GestureDetector(
          child: OtqFormattedText(textData: displayData, component: component),
          onTap: () {
            if (component['route'] != null &&
                component['route'] != rootThis.pageName) {
              if (component['route'].length >= 4 &&
                  component['route'].substring(0, 4).toLowerCase() == 'http') {
                openInWebView(context, component['route'], component['title']);
              } // end if route.length
            } // end if route != null
          }, // end of onTap
        ),
      ),
    );
  } // end of _buildContent
} // end of class OtqTxt
