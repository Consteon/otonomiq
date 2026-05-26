import 'package:flutter/material.dart';

import 'do_otq_bottom_sheet.dart';
import 'do_otq_dialog.dart';

Future doChain(BuildContext context, String scrName, var cComponent) async {
  String type = cComponent['type'].toString().toLowerCase();
  if (type == 'do_dialog' || type == 'dodialog') {
    return doOtqDialog(context, scrName, cComponent);
  } else if (type == 'do_bottom_sheet' || type == 'dobottomsheet') {
    return doOtqBottomSheet(context, scrName, cComponent);
  }
} // end of doChain
