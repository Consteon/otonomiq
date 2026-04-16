import 'package:flutter/material.dart';
import '../widget/ui_component.dart';
import 'package:get/get.dart';

Future doOtqDialog(BuildContext context, String scrName, var dComponent) async {
  /*
     action widget to display dialog box. Widgets inside this dialog will update
     txfController by itself. This function can be used in widget chain

     dComponent {
       "title" : "top title",
       "children" : [{"type"":..},{}], list of widget to be displayed,
       "chain" : {next widget to be displayed},
      }

      For consistency use await showGeneralDialog() like in photo_camera
  */
  var currentWidth = MediaQuery.of(context).size.width;
  //var currentHeight = MediaQuery.of(context).size.height;
  List<Widget> dialogWidgets =
      buildPage(dComponent['children'], scrName, dialog: true, clear: false);
  return Get.dialog(AlertDialog(
    // insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 20),
    title: Text(
      dComponent['title'] ?? "",
      textAlign: TextAlign.center,
    ),
    content: SizedBox(
      width: currentWidth,
      child: ListView.builder(
        // controller: _scrollController,
        shrinkWrap: true,
        itemCount: dialogWidgets.length,
        itemBuilder: (context, position) {
          return dialogWidgets[position];
        }, // end of itemBuilder
      ),
    ),
  ));
} // end of doOtqDialog
