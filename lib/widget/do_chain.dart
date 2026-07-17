import 'package:flutter/material.dart';

import 'do_otq_bottom_sheet.dart';
import 'do_otq_dialog.dart';

Future doChain(BuildContext context, String scrName, var cComponent) async {
  // cComponent is the caller's server-JSON `chain`; may be null (button with no
  // chain). Deref of null throws NoSuchMethodError []('type'). Chokepoint guard
  // for all callers — null chain = nothing to do.
  if (cComponent == null) return;
  String type = cComponent['type'].toString().toLowerCase();
  if (type == 'do_dialog' || type == 'dodialog') {
    return doOtqDialog(context, scrName, cComponent);
  } else if (type == 'do_bottom_sheet' || type == 'dobottomsheet') {
    return doOtqBottomSheet(context, scrName, cComponent);
  }
} // end of doChain
