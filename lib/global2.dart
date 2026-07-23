import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../firestore_repository/table_repository.dart';
import '../model/otq_state.dart';
import 'global.dart';
import 'model/input_controller.dart';

Map<String, Map<int, InputController>> txfController = {};

class WidgetUpdateController
    extends GetxController {} // X controller for updating widgets

Map<String, String> parsePosition(String input) {
  // Define Unicode code points as constants for readability and optimization.
  const int unicodeLeftwardTriangle = 9665; //LEFT-POINTING TRIANGLE
  const int unicodeRightwardTriangle = 9655; //RIGHT-POINTING TRIANGLE
  const int unicodeBlackLeftwardTriangle = 9664; // BLACK LEFT-POINTING TRIANGLE
  const int unicodeBlackRightwardTriangle =
      9654; //BLACK RIGHT-POINTING TRIANGLE

  // 1. Convert Unicode enclosures to their ASCII equivalents internally
  String processedInput = input;

  processedInput = processedInput.replaceAll(
    String.fromCharCode(unicodeLeftwardTriangle),
    '<<',
  );
  processedInput = processedInput.replaceAll(
    String.fromCharCode(unicodeRightwardTriangle),
    '>>',
  );
  processedInput = processedInput.replaceAll(
    String.fromCharCode(unicodeBlackLeftwardTriangle),
    '[[',
  );
  processedInput = processedInput.replaceAll(
    String.fromCharCode(unicodeBlackRightwardTriangle),
    ']]',
  );

  // Define the patterns using standard ASCII characters for enclosures.
  // Using a single, non-greedy group (.+?) to capture the content.

  // 1. Table: <content>
  final tablePattern = RegExp(r'^<(.+?)>$');

  // 2. Position (<<content>>): The replacement for ◁content▷
  final positionPattern = RegExp(r'^<<(.+?)>>$');

  // 3. Left ([[content]]): The replacement for ◀content▶
  final leftPattern = RegExp(r'^\[\[(.+?)\]\]$');

  // Check for 'position' pattern (against processedInput)
  final positionMatch = positionPattern.firstMatch(processedInput);
  if (positionMatch != null) {
    // The content is always in group 1
    return {"type": "position", "val": positionMatch.group(1)!};
  }

  // Check for 'left' pattern (against processedInput)
  final leftMatch = leftPattern.firstMatch(processedInput);
  if (leftMatch != null) {
    // The content is always in group 1
    return {"type": "left", "val": leftMatch.group(1)!};
  }

  // Check for 'table' pattern (against processedInput)
  final tableMatch = tablePattern.firstMatch(processedInput);
  if (tableMatch != null) {
    // The content is always in group 1
    return {"type": "table", "val": tableMatch.group(1)!};
  }

  // Default case: 'string'
  return {
    "type": "string",
    "val": input, // The whole original string is the value
  };
} // end of parsePosition

// String getAddressFrom
String getAddressFromOtqState(OtqState state) {
  String address = '';
  if (state.thoroughfare.isNotEmpty) {
    address += '${state.thoroughfare} ';
  }
  if (state.subThoroughfare.isNotEmpty) {
    address += '${state.subThoroughfare}, ';
  }
  // if (state.subLocality.isNotEmpty) {
  //   address += '${state.subLocality}, ';
  // }
  // if (state.locality.isNotEmpty) {
  //   address += '${state.locality}, ';ƒ
  // }
  if (state.subAdministrativeArea.isNotEmpty) {
    address += '${state.subAdministrativeArea}, ';
  }
  if (state.administrativeArea.isNotEmpty) {
    address += '${state.administrativeArea}, ';
  }
  if (state.isoCountryCode.isNotEmpty) {
    address += state.isoCountryCode;
  }
  if (state.postalCode.isNotEmpty) {
    address += '${state.postalCode}, ';
  }
  return address;
}

String normalizeTableName(String input) {
  String tableName = input.toString().trim();
  final List<String> splitTableName = tableName.split('//');
  if (splitTableName.length >= 2) {
    tableName = "${splitTableName[0]}/${getDocumentName(splitTableName.last)}";
  }
  return tableName;
} // end of normalizeTableName

String getDocumentName(String? docName) {
  if (docName == null || docName.isEmpty) {
    return 'NO_NAME';
  } else {
    dynamic splitFolder = docName.split(folderSeparator);
    if (splitFolder.length < 2) {
      return splitFolder[0].replaceAll('/', '%');
    } else {
      return "${splitFolder[0]}/${splitFolder.last.replaceAll('/', '%')}";
    }
  }
} // end of getDocumentName

List<dynamic> splitTableInput(String inp) {
  final tableSeparator = separator[1]; // black diamond
  // final fieldSeparator = forbiddenCharacter[4]; // white big circle
  // final equalSeparator = forbiddenCharacter[5]; // black square
  final fieldSeparator = separator[8]; // white big circle
  final equalSeparator = separator[2]; // black square

  List<dynamic> result = [];
  dynamic t1 = inp.split(tableSeparator);
  for (int i = 0; i < t1.length; i++) {
    List<dynamic> topComponent = [];
    dynamic t2 = t1[i].split(fieldSeparator);
    for (int j = 0; j < t2.length; j++) {
      dynamic t3 = t2[j].split(equalSeparator);
      topComponent.add(t3);
    } // end for j
    result.add(topComponent);
  } // end for i
  return result;
} // end of splitTableInput

/// Executes actions for widgets on a given screen based on the executable type.
/// The 'executable' parameter can be 'execute1', 'execute2', or 'all'.
Future<void> executeWidgets(String scrName, String executable) async {
  if (txfController[scrName] == null) {
    debugPrint("No controllers found for screen: $scrName");
    return;
  }

  final lowerCaseExecutable = executable.toLowerCase();

  if (lowerCaseExecutable != 'execute1' &&
      lowerCaseExecutable != 'execute2' &&
      lowerCaseExecutable != 'all') {
    debugPrint(
      "Invalid executable parameter: '$executable'. Must be 'execute1', 'execute2', or 'all'.",
    );
    return;
  }

  final List<Future<void>> asyncTasks = [];

  for (final controller in txfController[scrName]!.values) {
    List<List<dynamic>> executablesToRun = [];

    if ((lowerCaseExecutable == 'execute1' || lowerCaseExecutable == 'all') &&
        controller.execute1 != null) {
      executablesToRun.addAll(
        controller.execute1!
            .where((item) => item != null)
            .map((item) => item as List<dynamic>),
      );
    }
    if ((lowerCaseExecutable == 'execute2' || lowerCaseExecutable == 'all') &&
        controller.execute2 != null) {
      executablesToRun.addAll(
        controller.execute2!
            .where((item) => item != null)
            .map((item) => item as List<dynamic>),
      );
    }

    for (final item in executablesToRun) {
      // The expected format is now [widgetId, action, template]
      if (item.length < 2) continue;

      try {
        final String widgetId = item[0] as String;
        final String action = item[1] as String;

        switch (action.toLowerCase()) {
          case 'generate_number':
            if (item.length < 3) {
              debugPrint(
                "Template missing for 'generate_number' action for widget: $widgetId",
              );
              continue;
            }
            final String template = item[2] as String;
            final parts = widgetId.split('-');
            if (parts.length != 2) {
              debugPrint("Invalid widgetId format: $widgetId");
              continue;
            }
            final String scrNameFromId = parts[0];
            final int? position = int.tryParse(parts[1]);

            if (position == null) {
              debugPrint("Invalid position in widgetId: $widgetId");
              continue;
            }

            // Create an async task to perform the generation and update.
            final task = () async {
              final generatedString = await generateAutoNumber(
                template,
                scrNameFromId,
              );
              addToTxfController(position, scrNameFromId, generatedString);
              // Rebuild the specific widget using its ID.
              Get.find<WidgetUpdateController>().update([widgetId]);
            }(); // Immediately invoke and get the Future.

            asyncTasks.add(task);
            break;

          default:
            debugPrint("Unknown action: '$action' for widget: $widgetId");
        }
      } catch (e) {
        debugPrint(
          "Error executing action '${item[1]}' for widget ${item[0]}: $e",
        );
      }
    }
  }

  if (asyncTasks.isNotEmpty) {
    await Future.wait(asyncTasks);
  }
} // end of executeWidgets

/// Top-level function to generate a string based on a template.
Future<String> generateAutoNumber(String template, String scrName) async {
  return await _parseTemplate(template, scrName);
}

/// Parses the template and replaces tokens with generated values.
Future<String> _parseTemplate(String template, String scrName) async {
  final RegExp exp = RegExp(r'\{\{([^}]+)\}\}');
  final matches = exp.allMatches(template);
  final buffer = StringBuffer();
  int lastEnd = 0;

  for (final match in matches) {
    buffer.write(template.substring(lastEnd, match.start));
    final token = match.group(1) ?? '';
    final value = await _getTokenValue(token, scrName);
    buffer.write(value);
    lastEnd = match.end;
  }
  buffer.write(template.substring(lastEnd));
  return buffer.toString();
}

/// Resolves a single token to its corresponding value.
Future<String> _getTokenValue(String token, String scrName) async {
  final now = DateTime.now();
  final String deviceLocale = Platform.localeName;

  switch (token.toUpperCase()) {
    case 'YYYY':
      return now.year.toString();
    case 'YY':
      return now.year.toString().substring(2);
    case 'MR':
      return _intToRoman(now.month);
    case 'MMM':
      final String monthAbbr = DateFormat('MMM', deviceLocale).format(now);
      return '${monthAbbr[0].toUpperCase()}${monthAbbr.substring(1).toLowerCase()}';
    case 'MM':
      return now.month.toString().padLeft(2, '0');
    case 'DD':
      return now.day.toString().padLeft(2, '0');
    case 'HH':
      return now.hour.toString().padLeft(2, '0');
    case 'mm':
      return now.minute.toString().padLeft(2, '0');
    case 'ss':
      return now.second.toString().padLeft(2, '0');
  }
  if (token.toUpperCase().startsWith('RANDOM')) {
    return _generateRandom(token);
  } else if (token.toUpperCase().startsWith('COUNTER')) {
    return await _getCounterValue(token);
  } else if (token.toUpperCase().startsWith('POS')) {
    try {
      final paramsString = token.substring(
        token.indexOf('(') + 1,
        token.indexOf(')'),
      );
      final params = paramsString.split(',').map((p) => p.trim()).toList();

      if (params.isEmpty) {
        throw Exception('POS token requires a position.');
      }

      final int position = int.parse(params[0]);

      if (txfController.containsKey(scrName) &&
          txfController[scrName]!.containsKey(position)) {
        return txfController[scrName]![position]!.finalData;
      } else {
        return 'POS_NODATA';
      }
    } catch (e) {
      debugPrint('Error parsing POS token: $e');
      return 'POS_ERR';
    }
  }
  return token;
}

/// Generates a random string based on specified length and format.
String _generateRandom(String token) {
  try {
    final params = token
        .substring(token.indexOf('(') + 1, token.indexOf(')'))
        .split(',');
    final length = int.parse(params[0].trim());
    final format = params.length > 1
        ? params[1].trim().toLowerCase()
        : 'decimal';
    final random = Random.secure();

    switch (format) {
      case 'hex':
        final bytes = List<int>.generate(length, (_) => random.nextInt(256));
        return bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .substring(0, length);
      case 'base64':
        final bytes = List<int>.generate(length, (_) => random.nextInt(256));
        return base64Url.encode(bytes).substring(0, length);
      case 'string':
        const chars =
            'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        return String.fromCharCodes(
          Iterable.generate(
            length,
            (_) => chars.codeUnitAt(random.nextInt(chars.length)),
          ),
        );
      case 'decimal':
      default:
        final max = pow(10, length);
        return random.nextInt(max.toInt()).toString().padLeft(length, '0');
    }
  } catch (e) {
    debugPrint('Error parsing RANDOM token: $e');
    return 'RANDOM_ERR';
  }
}

/// Retrieves a sequential counter value.
Future<String> _getCounterValue(String token) async {
  try {
    final paramsString = token.substring(
      token.indexOf('(') + 1,
      token.indexOf(')'),
    );
    final params = paramsString.split(',').map((p) => p.trim()).toList();

    if (params.isEmpty || params[0].isEmpty) {
      throw Exception('COUNTER document name is missing.');
    }
    final String documentName = params[0];
    int? numberOfDigits;

    if (params.length > 1) {
      numberOfDigits = int.tryParse(params[1]);
    }

    final counter = await firestoreSequential(documentName);
    String counterStr = counter.toString();

    if (numberOfDigits != null && numberOfDigits > 0) {
      counterStr = counterStr.padLeft(numberOfDigits, '0');
    }

    return counterStr;
  } catch (e) {
    debugPrint('Error parsing COUNTER token: $e');
    return 'COUNTER_ERR';
  }
}

/// Converts an integer to its Roman numeral representation.
String _intToRoman(int num) {
  if (num < 1 || num > 3999) {
    return "Error";
  }
  const List<int> values = [
    1000,
    900,
    500,
    400,
    100,
    90,
    50,
    40,
    10,
    9,
    5,
    4,
    1,
  ];
  const List<String> numerals = [
    "M",
    "CM",
    "D",
    "CD",
    "C",
    "XC",
    "L",
    "XL",
    "X",
    "IX",
    "V",
    "IV",
    "I",
  ];

  StringBuffer result = StringBuffer();
  for (int i = 0; i < values.length; i++) {
    while (num >= values[i]) {
      num -= values[i];
      result.write(numerals[i]);
    }
  }
  return result.toString();
}

int getPosition(dynamic inp) {
  int retVal = (inp!.runtimeType == String) ? int.parse(inp!) : inp!;
  return retVal;
} // end of getPosition(dynamic inp)

/// Adds an executable action to a specific controller's state.
/// This function associates a GlobalKey and an action string with an executable name.
void addExecutableToController(
  int position,
  String scrName,
  GlobalKey key,
  String executable, // This should be 'execute1' or 'execute2'
  String action,
) {
  // Ensure the controller for the given screen and position exists.
  txfControllerCheck(scrName, position);

  try {
    final controller = txfController[scrName]![position]!;
    final keyString = key.toString();
    final executableItem = [keyString, key, action];

    if (executable == 'execute1') {
      // If execute1 is null, initialize it as an empty list.
      controller.execute1 ??= [];
      // Add the new executable item.
      if (!controller.execute1!.any((item) => item![0] == keyString)) {
        controller.execute1!.add(executableItem);
        debugPrint(
          '|||||||| add executable $scrName.$position Number = ${keyString.substring(keyString.length - 7)}',
        );
      }
    } else if (executable == 'execute2') {
      // If execute2 is null, initialize it as an empty list.
      controller.execute2 ??= [];
      // Add the new executable item.
      // controller.execute2!.add(executableItem);
      if (!controller.execute2!.any((item) => item![0] == keyString)) {
        controller.execute2!.add(executableItem);
      }
    } else {
      // Handle the case where the executable name is invalid.
      debugPrint(
        "Invalid executable name: $executable. Use 'execute1' or 'execute2'.",
      );
    }
  } catch (e) {
    // Report any errors that occur.
    debugPrint('Error adding executable: $e');
    errorReport(e);
  }
} // end of addExecutableToController

/// Converts a string representation of a color into a Color object.
/// This function can handle color names with shades (e.g., 'red_500')
/// and multi-word color names (e.g., 'deep_orange_700').
Color stringToColor(String colorString) {
  final Map<String, MaterialColor> colorMap = {
    'red': Colors.red,
    'pink': Colors.pink,
    'purple': Colors.purple,
    'deep_purple': Colors.deepPurple,
    'indigo': Colors.indigo,
    'blue': Colors.blue,
    'light_blue': Colors.lightBlue,
    'cyan': Colors.cyan,
    'teal': Colors.teal,
    'green': Colors.green,
    'light_green': Colors.lightGreen,
    'lime': Colors.lime,
    'yellow': Colors.yellow,
    'amber': Colors.amber,
    'orange': Colors.orange,
    'deep_orange': Colors.deepOrange,
    'brown': Colors.brown,
    'grey': Colors.grey,
    'blue_grey': Colors.blueGrey,
  };

  final Map<String, Color> singleColorMap = {
    'black': Colors.black,
    'white': Colors.white,
    'transparent': Colors.transparent,
  };

  String lowerCaseColor = colorString.toLowerCase();

  // Handle single colors first (e.g., 'black', 'white')
  if (singleColorMap.containsKey(lowerCaseColor)) {
    return singleColorMap[lowerCaseColor]!;
  }

  // Handle colors with shades (e.g., 'red_500', 'deep_orange_700')
  int lastUnderscoreIndex = lowerCaseColor.lastIndexOf('_');
  if (lastUnderscoreIndex != -1) {
    String colorName = lowerCaseColor.substring(0, lastUnderscoreIndex);
    String shadeStr = lowerCaseColor.substring(lastUnderscoreIndex + 1);
    int? shade = int.tryParse(shadeStr);

    // Check if the part after the last underscore is a valid shade
    // and if the color name exists in the map.
    if (shade != null && colorMap.containsKey(colorName)) {
      return colorMap[colorName]![shade] ?? Colors.black;
    }
  }

  // Handle base colors without shades (e.g., 'red', 'deep_orange')
  if (colorMap.containsKey(lowerCaseColor)) {
    return colorMap[lowerCaseColor]!;
  }

  // Return a default color if no match is found
  return Colors.black;
} // end of stringToColor

/// --- MODIFIED: Converts a string name to a Material IconData object with an expanded list. ---
IconData stringToIconData(String? iconName) {
  // A map of common Material Design icon names to their IconData.
  final Map<String, IconData> iconMap = {
    // --- ADDED: Field Operations Icons ---
    'local_shipping': Icons.local_shipping,
    'inventory': Icons.inventory,
    'inventory_2': Icons.inventory_2,
    'warehouse': Icons.warehouse,
    'move_down': Icons.move_down,
    'conveyor_belt': Icons.conveyor_belt,
    'forklift': Icons.forklift,
    'pallet': Icons.pallet,
    'group': Icons.group,
    'people': Icons.people,
    'badge': Icons.badge,
    'handshake': Icons.handshake,
    'hub': Icons.hub,
    'attach_money': Icons.attach_money,
    'monetization_on': Icons.monetization_on,
    'payments': Icons.payments,
    'price_check': Icons.price_check,
    'receipt_long': Icons.receipt_long,

    // Actions
    'account_balance': Icons.account_balance,
    'account_balance_wallet': Icons.account_balance_wallet,
    'account_box': Icons.account_box,
    'account_circle': Icons.account_circle,
    'add_shopping_cart': Icons.add_shopping_cart,
    'alarm': Icons.alarm,
    'alarm_add': Icons.alarm_add,
    'alarm_off': Icons.alarm_off,
    'alarm_on': Icons.alarm_on,
    'all_out': Icons.all_out,
    'announcement': Icons.announcement,
    'aspect_ratio': Icons.aspect_ratio,
    'assessment': Icons.assessment,
    'assignment': Icons.assignment,
    'assignment_ind': Icons.assignment_ind,
    'assignment_late': Icons.assignment_late,
    'assignment_return': Icons.assignment_return,
    'assignment_returned': Icons.assignment_returned,
    'assignment_turned_in': Icons.assignment_turned_in,
    'autorenew': Icons.autorenew,
    'backup': Icons.backup,
    'book': Icons.book,
    'bookmark': Icons.bookmark,
    'bookmark_border': Icons.bookmark_border,
    'bug_report': Icons.bug_report,
    'build': Icons.build,
    'cached': Icons.cached,
    'calendar_today': Icons.calendar_today,
    'calendar_view_day': Icons.calendar_view_day,
    'camera_alt': Icons.camera_alt,
    'camera_enhance': Icons.camera_enhance,
    'card_giftcard': Icons.card_giftcard,
    'card_membership': Icons.card_membership,
    'card_travel': Icons.card_travel,
    'change_history': Icons.change_history,
    'check_circle': Icons.check_circle,
    'check_circle_outline': Icons.check_circle_outline,
    'chrome_reader_mode': Icons.chrome_reader_mode,
    'class': Icons.class_,
    'code': Icons.code,
    'compare_arrows': Icons.compare_arrows,
    'copyright': Icons.copyright,
    'credit_card': Icons.credit_card,
    'dashboard': Icons.dashboard,
    'date_range': Icons.date_range,
    'delete': Icons.delete,
    'delete_forever': Icons.delete_forever,
    'delete_outline': Icons.delete_outline,
    'description': Icons.description,
    'dns': Icons.dns,
    'done': Icons.done,
    'done_all': Icons.done_all,
    'done_outline': Icons.done_outline,
    'donut_large': Icons.donut_large,
    'donut_small': Icons.donut_small,
    'drag_indicator': Icons.drag_indicator,
    'edit_note': Icons.edit_note,
    'eject': Icons.eject,
    'euro_symbol': Icons.euro_symbol,
    'event': Icons.event,
    'event_seat': Icons.event_seat,
    'exit_to_app': Icons.exit_to_app,
    'explore': Icons.explore,
    'extension': Icons.extension,
    'face': Icons.face,
    'favorite': Icons.favorite,
    'favorite_border': Icons.favorite_border,
    'feedback': Icons.feedback,
    'find_in_page': Icons.find_in_page,
    'find_replace': Icons.find_replace,
    'fingerprint': Icons.fingerprint,
    'flight_land': Icons.flight_land,
    'flight_takeoff': Icons.flight_takeoff,
    'flip_to_back': Icons.flip_to_back,
    'flip_to_front': Icons.flip_to_front,
    'g_translate': Icons.g_translate,
    'gavel': Icons.gavel,
    'get_app': Icons.get_app,
    'gif': Icons.gif,
    'grade': Icons.grade,
    'group_work': Icons.group_work,
    'help': Icons.help,
    'help_outline': Icons.help_outline,
    'highlight_off': Icons.highlight_off,
    'history': Icons.history,
    'home': Icons.home,
    'hourglass_empty': Icons.hourglass_empty,
    'hourglass_full': Icons.hourglass_full,
    'http': Icons.http,
    'https': Icons.https,
    'important_devices': Icons.important_devices,
    'info': Icons.info,
    'info_outline': Icons.info_outline,
    'input': Icons.input,
    'invert_colors': Icons.invert_colors,
    'label': Icons.label,
    'label_important': Icons.label_important,
    'label_outline': Icons.label_outline,
    'language': Icons.language,
    'launch': Icons.launch,
    'lightbulb_outline': Icons.lightbulb_outline,
    'line_style': Icons.line_style,
    'line_weight': Icons.line_weight,
    'list': Icons.list,
    'lock': Icons.lock,
    'lock_open': Icons.lock_open,
    'lock_outline': Icons.lock_outline,
    'login': Icons.login,
    'logout': Icons.logout,
    'loyalty': Icons.loyalty,
    'markunread_mailbox': Icons.markunread_mailbox,
    'motorcycle': Icons.motorcycle,
    'note_add': Icons.note_add,
    'opacity': Icons.opacity,
    'open_in_browser': Icons.open_in_browser,
    'open_in_new': Icons.open_in_new,
    'open_with': Icons.open_with,
    'pageview': Icons.pageview,
    'pan_tool': Icons.pan_tool,
    'payment': Icons.payment,
    'perm_camera_mic': Icons.perm_camera_mic,
    'perm_contact_calendar': Icons.perm_contact_calendar,
    'perm_data_setting': Icons.perm_data_setting,
    'perm_device_information': Icons.perm_device_information,
    'perm_identity': Icons.perm_identity,
    'perm_media': Icons.perm_media,
    'perm_phone_msg': Icons.perm_phone_msg,
    'perm_scan_wifi': Icons.perm_scan_wifi,
    'pets': Icons.pets,
    'picture_in_picture': Icons.picture_in_picture,
    'picture_in_picture_alt': Icons.picture_in_picture_alt,
    'play_for_work': Icons.play_for_work,
    'polymer': Icons.polymer,
    'power_settings_new': Icons.power_settings_new,
    'pregnant_woman': Icons.pregnant_woman,
    'print': Icons.print,
    'query_builder': Icons.query_builder,
    'receipt': Icons.receipt,
    'record_voice_over': Icons.record_voice_over,
    'redeem': Icons.redeem,
    'remove_shopping_cart': Icons.remove_shopping_cart,
    'reorder': Icons.reorder,
    'report_problem': Icons.report_problem,
    'restore': Icons.restore,
    'restore_from_trash': Icons.restore_from_trash,
    'restore_page': Icons.restore_page,
    'room': Icons.room,
    'rounded_corner': Icons.rounded_corner,
    'rowing': Icons.rowing,
    'schedule': Icons.schedule,
    'search': Icons.search,
    'settings': Icons.settings,
    'settings_applications': Icons.settings_applications,
    'settings_backup_restore': Icons.settings_backup_restore,
    'settings_bluetooth': Icons.settings_bluetooth,
    'settings_brightness': Icons.settings_brightness,
    'settings_cell': Icons.settings_cell,
    'settings_ethernet': Icons.settings_ethernet,
    'settings_input_antenna': Icons.settings_input_antenna,
    'settings_input_component': Icons.settings_input_component,
    'settings_input_composite': Icons.settings_input_composite,
    'settings_input_hdmi': Icons.settings_input_hdmi,
    'settings_input_svideo': Icons.settings_input_svideo,
    'settings_overscan': Icons.settings_overscan,
    'settings_phone': Icons.settings_phone,
    'settings_power': Icons.settings_power,
    'settings_remote': Icons.settings_remote,
    'settings_voice': Icons.settings_voice,
    'shop': Icons.shop,
    'shop_two': Icons.shop_two,
    'shopping_basket': Icons.shopping_basket,
    'shopping_cart': Icons.shopping_cart,
    'speaker_notes': Icons.speaker_notes,
    'speaker_notes_off': Icons.speaker_notes_off,
    'spellcheck': Icons.spellcheck,
    'star': Icons.star,
    'star_border': Icons.star_border,
    'star_half': Icons.star_half,
    'stars': Icons.stars,
    'store': Icons.store,
    'subject': Icons.subject,
    'supervised_user_circle': Icons.supervised_user_circle,
    'supervisor_account': Icons.supervisor_account,
    'swap_horiz': Icons.swap_horiz,
    'swap_horizontal_circle': Icons.swap_horizontal_circle,
    'swap_vert': Icons.swap_vert,
    'swap_vertical_circle': Icons.swap_vertical_circle,
    'sync_alt': Icons.sync_alt,
    'system_update_alt': Icons.system_update_alt,
    'tab': Icons.tab,
    'tab_unselected': Icons.tab_unselected,
    'text_rotate_up': Icons.text_rotate_up,
    'text_rotate_vertical': Icons.text_rotate_vertical,
    'text_rotation_angledown': Icons.text_rotation_angledown,
    'text_rotation_angleup': Icons.text_rotation_angleup,
    'text_rotation_down': Icons.text_rotation_down,
    'text_rotation_none': Icons.text_rotation_none,
    'theaters': Icons.theaters,
    'thumb_down': Icons.thumb_down,
    'thumb_up': Icons.thumb_up,
    'thumbs_up_down': Icons.thumbs_up_down,
    'timeline': Icons.timeline,
    'toc': Icons.toc,
    'today': Icons.today,
    'toll': Icons.toll,
    'touch_app': Icons.touch_app,
    'track_changes': Icons.track_changes,
    'translate': Icons.translate,
    'trending_down': Icons.trending_down,
    'trending_flat': Icons.trending_flat,
    'trending_up': Icons.trending_up,
    'turned_in': Icons.turned_in,
    'turned_in_not': Icons.turned_in_not,
    'update': Icons.update,
    'verified_user': Icons.verified_user,
    'view_agenda': Icons.view_agenda,
    'view_array': Icons.view_array,
    'view_carousel': Icons.view_carousel,
    'view_column': Icons.view_column,
    'view_day': Icons.view_day,
    'view_headline': Icons.view_headline,
    'view_list': Icons.view_list,
    'view_module': Icons.view_module,
    'view_quilt': Icons.view_quilt,
    'view_stream': Icons.view_stream,
    'view_week': Icons.view_week,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
    'voice_over_off': Icons.voice_over_off,
    'watch_later': Icons.watch_later,
    'work': Icons.work,
    'work_off': Icons.work_off,
    'work_outline': Icons.work_outline,
    'youtube_searched_for': Icons.youtube_searched_for,
    'zoom_in': Icons.zoom_in,
    'zoom_out': Icons.zoom_out,
    'zoom_out_map': Icons.zoom_out_map,

    // Communication
    'add_call': Icons.add_call,
    'alternate_email': Icons.alternate_email,
    'business': Icons.business,
    'call': Icons.call,
    'call_end': Icons.call_end,
    'call_made': Icons.call_made,
    'call_merge': Icons.call_merge,
    'call_missed': Icons.call_missed,
    'call_missed_outgoing': Icons.call_missed_outgoing,
    'call_received': Icons.call_received,
    'call_split': Icons.call_split,
    'cancel_presentation': Icons.cancel_presentation,
    'chat': Icons.chat,
    'chat_bubble': Icons.chat_bubble,
    'chat_bubble_outline': Icons.chat_bubble_outline,
    'clear_all': Icons.clear_all,
    'comment': Icons.comment,
    'contact_mail': Icons.contact_mail,
    'contact_phone': Icons.contact_phone,
    'contacts': Icons.contacts,
    'desktop_access_disabled': Icons.desktop_access_disabled,
    'dialer_sip': Icons.dialer_sip,
    'dialpad': Icons.dialpad,
    'domain_disabled': Icons.domain_disabled,
    'duo': Icons.duo,
    'email': Icons.email,
    'forum': Icons.forum,
    'import_contacts': Icons.import_contacts,
    'import_export': Icons.import_export,
    'invert_colors_off': Icons.invert_colors_off,
    'list_alt': Icons.list_alt,
    'live_help': Icons.live_help,
    'location_off': Icons.location_off,
    'location_on': Icons.location_on,
    'mail_outline': Icons.mail_outline,
    'message': Icons.message,
    'mobile_screen_share': Icons.mobile_screen_share,
    'no_sim': Icons.no_sim,
    'pause_presentation': Icons.pause_presentation,
    'person_add': Icons.person_add,
    'phone': Icons.phone,
    'phonelink_erase': Icons.phonelink_erase,
    'phonelink_lock': Icons.phonelink_lock,
    'phonelink_ring': Icons.phonelink_ring,
    'phonelink_setup': Icons.phonelink_setup,
    'portable_wifi_off': Icons.portable_wifi_off,
    'present_to_all': Icons.present_to_all,
    'ring_volume': Icons.ring_volume,
    'rss_feed': Icons.rss_feed,
    'screen_share': Icons.screen_share,
    'share': Icons.share,
    'sentiment_satisfied_alt': Icons.sentiment_satisfied_alt,
    'speaker_phone': Icons.speaker_phone,
    'stay_current_landscape': Icons.stay_current_landscape,
    'stay_current_portrait': Icons.stay_current_portrait,
    'stay_primary_landscape': Icons.stay_primary_landscape,
    'stay_primary_portrait': Icons.stay_primary_portrait,
    'stop_screen_share': Icons.stop_screen_share,
    'swap_calls': Icons.swap_calls,
    'textsms': Icons.textsms,
    'unsubscribe': Icons.unsubscribe,
    'voicemail': Icons.voicemail,
    'vpn_key': Icons.vpn_key,

    // Navigation
    'apps': Icons.apps,
    'arrow_back': Icons.arrow_back,
    'arrow_back_ios': Icons.arrow_back_ios,
    'arrow_downward': Icons.arrow_downward,
    'arrow_drop_down': Icons.arrow_drop_down,
    'arrow_drop_down_circle': Icons.arrow_drop_down_circle,
    'arrow_drop_up': Icons.arrow_drop_up,
    'arrow_forward': Icons.arrow_forward,
    'arrow_forward_ios': Icons.arrow_forward_ios,
    'arrow_left': Icons.arrow_left,
    'arrow_right': Icons.arrow_right,
    'arrow_upward': Icons.arrow_upward,
    'cancel': Icons.cancel,
    'check': Icons.check,
    'chevron_left': Icons.chevron_left,
    'chevron_right': Icons.chevron_right,
    'close': Icons.close,
    'expand_less': Icons.expand_less,
    'expand_more': Icons.expand_more,
    'first_page': Icons.first_page,
    'fullscreen': Icons.fullscreen,
    'fullscreen_exit': Icons.fullscreen_exit,
    'last_page': Icons.last_page,
    'menu': Icons.menu,
    'more_horiz': Icons.more_horiz,
    'more_vert': Icons.more_vert,
    'refresh': Icons.refresh,
    'subdirectory_arrow_left': Icons.subdirectory_arrow_left,
    'subdirectory_arrow_right': Icons.subdirectory_arrow_right,
    'unfold_less': Icons.unfold_less,
    'unfold_more': Icons.unfold_more,

    // Content
    'add': Icons.add,
    'add_box': Icons.add_box,
    'add_circle': Icons.add_circle,
    'add_circle_outline': Icons.add_circle_outline,
    'archive': Icons.archive,
    'backspace': Icons.backspace,
    'ballot': Icons.ballot,
    'block': Icons.block,
    'clear': Icons.clear,
    'content_copy': Icons.content_copy,
    'content_cut': Icons.content_cut,
    'content_paste': Icons.content_paste,
    'create': Icons.create,
    'delete_sweep': Icons.delete_sweep,
    'drafts': Icons.drafts,
    'filter_list': Icons.filter_list,
    'flag': Icons.flag,
    'font_download': Icons.font_download,
    'forward': Icons.forward,
    'gesture': Icons.gesture,
    'inbox': Icons.inbox,
    'link': Icons.link,
    'link_off': Icons.link_off,
    'low_priority': Icons.low_priority,
    'mail': Icons.mail,
    'move_to_inbox': Icons.move_to_inbox,
    'next_week': Icons.next_week,
    'outlined_flag': Icons.outlined_flag,
    'policy': Icons.policy,
    'redo': Icons.redo,
    'remove': Icons.remove,
    'remove_circle': Icons.remove_circle,
    'remove_circle_outline': Icons.remove_circle_outline,
    'reply': Icons.reply,
    'reply_all': Icons.reply_all,
    'report': Icons.report,
    'report_off': Icons.report_off,
    'save': Icons.save,
    'save_alt': Icons.save_alt,
    'select_all': Icons.select_all,
    'send': Icons.send,
    'sort': Icons.sort,
    'text_format': Icons.text_format,
    'unarchive': Icons.unarchive,
    'undo': Icons.undo,
    'waves': Icons.waves,
    'weekend': Icons.weekend,

    // Scanner Specific
    'qr_code': Icons.qr_code,
    'qr_code_scanner': Icons.qr_code_scanner,
    'barcode_reader': Icons.barcode_reader,
    'camera': Icons.camera,
    'flash_on': Icons.flash_on,
    'flash_off': Icons.flash_off,
    'flip_camera_ios': Icons.flip_camera_ios,
  };

  // Return the icon if found, otherwise return a default help icon.
  return iconMap[iconName?.toLowerCase()] ?? Icons.help_outline;
} // end of stringToIconData

/// Converts a comma-separated string to EdgeInsets.
EdgeInsets stringToEdgeInsets(String? marginString) {
  const EdgeInsets defaultMargin = EdgeInsets.only(bottom: 24.0);
  if (marginString == null || marginString.isEmpty) {
    return defaultMargin;
  }
  final parts = marginString.split(',');
  if (parts.length == 4) {
    try {
      final double top = double.parse(parts[0].trim());
      final double bottom = double.parse(parts[1].trim());
      final double left = double.parse(parts[2].trim());
      final double right = double.parse(parts[3].trim());
      return EdgeInsets.fromLTRB(left, top, right, bottom);
    } catch (e) {
      return defaultMargin;
    }
  }
  return defaultMargin;
} // end of stringToEdgeInsets

void txfControllerCheck(String scrName, dynamic pos) {
  // check existence of txfController[widget.scrName]
  // check existence of txfController[widget.scrName][widget.component['position']]
  // create data if needed.
  int position = getPosition(pos);
  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  } // end if (txfController[scrName] == null)
  if (txfController[scrName]![position] == null) {
    txfController[scrName]![position] = InputController(
      position,
      TextEditingController(text: ""),
      "",
      emptyString,
    );
  } // end if (txfController[scrName]![position] == null)
} // end of txfControllerCheck

/// A function to put output of a widget to the TxfController.
void addToTxfController(
  int? position,
  String scrName,
  String content, {
  Map<String, dynamic>? table,
  dynamic stateObject,
}) {
  // If position is null, default it to 0.
  int finalPosition = position ?? 0;

  // Check if a valid position is provided.
  if (position == null || finalPosition <= 0) {
    debugPrint('>>>>>>>>>>> No position defined');
  } else {
    // Print the position, content, and table for debugging purposes.
    debugPrint(
      '>>>>>>>>>>> Position: $finalPosition, Content: $content, Table: $table',
    );
    try {
      txfControllerCheck(scrName, position);
      txfController[scrName]![position]!.controller.text = content;
      txfController[scrName]![position]!.finalData = content;
      // Assign the new table parameter to the controller's table property
      txfController[scrName]![position]!.table = table;
      if (stateObject != null) {
        txfController[scrName]![position]!.stateObject = stateObject;
      }
    } catch (e) {
      errorReport(e);
    }
  }
} // end of addToTxfController

/// An asynchronous function to handle writing the scanned data to specified tables.
Future<void> writeToTable(String tableNames, List<String> scannedCodes) async {
  if (tableNames.isEmpty || scannedCodes.isEmpty) {
    return;
  }
  final List<String> tables = diamondTextToList(tableNames);
  for (final table in tables) {
    // Hint for the programmer:
    // This is where you would implement the logic to write the `scannedCodes`
    // list to the specified `table`.
    // For example: await database.insert(table, {'codes': scannedCodes});
    debugPrint('Writing to table: $table');
  }
} // end of writeToTable
