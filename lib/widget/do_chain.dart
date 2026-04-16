import 'package:flutter/material.dart';

import 'do_otq_dialog.dart';

Future doChain(BuildContext context, String scrName, var cComponent) async {
  String type = cComponent['type'].toString().toLowerCase();
  if (type == 'do_dialog' || type == 'dodialog') {
    return doOtqDialog(context, scrName, cComponent);
  } // end switch type

  int d1 = 1;
} // end of doChain
