import 'package:flutter/material.dart';

import '../global.dart';
import '../redux/screen_transaction.dart';

void buildTheme(dynamic themeJSON) {
  dynamic appTheme = themeJSON ??
      {
        "themeName": "agenia",
        "bottomAppBarColor": 4293454582,
        "primaryColor": 4278196850
      };
  appTheme = null;
  ThemeData myTheme = ThemeData(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) =>
            systemUIComponent[theme]['buttonColor'] == null
                ? Colors.grey[400]!
                : Color(systemUIComponent[theme]['buttonColor'])),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) =>
            systemUIComponent[theme]['buttonText'] == null
                ? Colors.black87
                : Color(systemUIComponent[theme]['buttonText'])),
        shape: WidgetStateProperty.resolveWith<OutlinedBorder>((_) {
          return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  systemUIComponent[theme]['buttonRadius'] ?? 4));
        }),
        elevation: WidgetStateProperty.all(
            0.0 + 0.0 + (appTheme?['elevation'] ?? 4)),
        // side: MaterialStateProperty.resolveWith<BorderSide>(
        //         (states) => BorderSide(color: borderColor ?? Colors.black)),
        // textStyle: MaterialStateProperty.resolveWith<TextStyle>(
        //     (states) => TextStyle(color: Colors.red)),
      ),
    ),
  );
  transactionStore
      .dispatch(UpdateScreenTxAction(ScreenTransaction({'#THEME': myTheme})));
} // end of buildTheme
