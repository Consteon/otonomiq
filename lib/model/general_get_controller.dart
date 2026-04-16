import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import '../global2.dart';

class WidgetItem {
  WidgetItem({
    required this.counter,
    required this.widgetList,
    required this.stringList,
    this.controller,
  });
  int counter;
  dynamic controller;
  List<Widget> widgetList;
  List<String> stringList;
} // end of WidgetItem

class GeneralGetXController extends GetxController {
  /*
  * This is a singleton class. This means that there is only one instance of this class.
  * This class is used to store widget-specific updater data.
  * use GeneralGetXController.to.updateWidget(pageName,position) to update specific widget
  */
  static GeneralGetXController get to => Get.find();
  Map<String, Map<int, WidgetItem>> widgetData =
      {}; // Map to store widget-specific data

  void increaseCounter(String pageName, int position) {
    widgetData[pageName]![position]?.counter =
        ((widgetData[pageName]![position]?.counter ?? 0) > 999999999)
            ? 0
            : widgetData[pageName]![position]!.counter + 1;
  } // end of increaseCounter

  String getWidgetId(String pageName, int position) {
    return '$pageName.${position.toString()}';
  } // end of getWidgetData

  void checkWidgetData(String pageName, int position) {
    if (widgetData[pageName] == null) {
      registerPage(pageName);
    }
    if (widgetData[pageName]![position] == null) {
      widgetData[pageName]![position] =
          WidgetItem(counter: 0, widgetList: [], stringList: []);
    } // end of if (widgetData[widgetId] == null)
  } // end of checkWidgetData

  void putController(String pageName, int position, dynamic newController) {
    checkWidgetData(pageName, position);
    widgetData[pageName]![position]?.controller = newController;
  } // end of putController

  dynamic getController(String pageName, int position) {
    if (widgetData[pageName] == null) {
      return null;
    }
    if (widgetData[pageName]![position] == null) {
      return null;
    }
    return widgetData[pageName]![position]?.controller;
  } // end of getController

  WidgetItem? getWidgetItem(String pageName, int position) {
    if (widgetData[pageName] == null) {
      return null;
    }
    if (widgetData[pageName]![position] == null) {
      return null;
    }
    return widgetData[pageName]![position];
  } // end of getWidgetData

  List<Widget> getWidgetList(String pageName, int position) {
    if (widgetData[pageName] == null) {
      return [];
    }
    if (widgetData[pageName]![position] == null) {
      return [];
    }
    return widgetData[pageName]![position]?.widgetList ?? [];
  } // end of getWidgetList

  List<String> getStringList(String pageName, int position) {
    if (widgetData[pageName] == null) {
      return [];
    }
    if (widgetData[pageName]![position] == null) {
      return [];
    }
    return widgetData[pageName]![position]?.stringList ?? [];
  } // end of getStringList

  Map<int, WidgetItem>? getPageData(String pageName) {
    if (widgetData[pageName] == null) {
      return {};
    }
    return widgetData[pageName];
  } // end of getPageData

  void registerPage(String pageName) {
    widgetData[pageName] = {};
  } // end of registerWidget

  void registerWidget(String pageName, int position) {
    if (widgetData[pageName] == null) {
      registerPage(pageName);
    }
    widgetData[pageName]![position] =
        WidgetItem(counter: 0, widgetList: [], stringList: []);
  } // end of updateWidget

  void updateWidget(String pageName, int position) {
    checkWidgetData(pageName, position);
    increaseCounter(pageName, position);
    update([
      getWidgetId(pageName, position)
    ]); // Notify listeners with the widgetId
  } // end of updateWidget

  void addWidget(
      String pageName, int position, Widget newWidget, String newString) {
    checkWidgetData(pageName, position);
    widgetData[pageName]![position]?.widgetList.add(newWidget);
    widgetData[pageName]![position]?.stringList.add(newString);
    increaseCounter(pageName, position);
    update([
      getWidgetId(pageName, position)
    ]); // Notify listeners with the widgetId
  } //end of addWidget

  void deleteWidgetAt(String pageName, int positionInPage, int imagePosition) {
    bool isEnabled = txfController[pageName]![positionInPage]?.isEnabled ?? true;
    if (!isEnabled) {
      return;
    }
    if (widgetData[pageName] != null &&
        widgetData[pageName]![positionInPage] != null) {
      widgetData[pageName]![positionInPage]?.widgetList.removeAt(imagePosition);
      widgetData[pageName]![positionInPage]?.stringList.removeAt(imagePosition);
    } // end of if (widgetData[pageName] == null)
    increaseCounter(pageName, positionInPage);
    update([
      getWidgetId(pageName, positionInPage)
    ]); // Notify listeners with the widgetId
  } // end of deleteWidgetAt

  void deleteAllWidget(String pageName, int positionInPage) {
    if (widgetData[pageName] != null &&
        widgetData[pageName]![positionInPage] != null) {
      widgetData[pageName]![positionInPage]?.widgetList.length = 0;
      widgetData[pageName]![positionInPage]?.stringList.length = 0;
    } // end of if (widgetData[pageName] == null)
    increaseCounter(pageName, positionInPage);
    update([
      getWidgetId(pageName, positionInPage)
    ]); // Notify listeners with the widgetId
  } //end of deleteWidgetAt

  void redraw(
      String pageName, int position) {
    checkWidgetData(pageName, position);
    // widgetData[pageName]![position]?.widgetList.add(newWidget);
    // widgetData[pageName]![position]?.stringList.add(newString);
    // increaseCounter(pageName, position);
    update([
      getWidgetId(pageName, position)
    ]); // Notify listeners with the widgetId
  } // end of refresh
} // end of GeneralGetXController
