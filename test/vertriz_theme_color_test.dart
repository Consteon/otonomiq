import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/page/vertriz_app.dart';

// themeColor (page/vertriz_app.dart) reads a colour out of the server-driven
// theme map for the ROOT MaterialApp. Anything thrown from VertrizApp.build
// renders a blank app, so every one of these states must degrade, never throw.
//
// It replaced two unguarded reads:
//   Color(systemUIComponent[theme]['primaryColor'].toInt())
//   Color(systemUIComponent[theme]['bottomAppBarColor'].toInt())
// and three half-guarded ones that checked for null but then passed the raw
// dynamic to Color(x) with no .toInt().

const Color sentinel = Color(0xFFDEADBE);

void main() {
  setUp(() {
    theme = 'ThemeAgenia';
    systemUIComponent = {
      'ThemeAgenia': {'primaryColor': 4278196850},
    };
  });

  group('themeColor', () {
    test('reads an int straight through', () {
      expect(themeColor('primaryColor', sentinel), const Color(4278196850));
    });

    test('systemUIComponent null -> fallback, no NoSuchMethodError', () {
      // global.dart:490 declares `dynamic systemUIComponent;` with no
      // initializer, so this is its state before any settings load.
      systemUIComponent = null;
      expect(themeColor('primaryColor', sentinel), sentinel);
    });

    test('systemUIComponent {} -> fallback', () {
      // What the init/reset routine leaves behind (global.dart:849) until the
      // settings refetch lands. `{}['ThemeAgenia']` is null.
      systemUIComponent = {};
      expect(themeColor('primaryColor', sentinel), sentinel);
    });

    test('theme key present but colour key missing -> fallback', () {
      // A tenant sheet that simply omits the entry.
      systemUIComponent = {
        'ThemeAgenia': {'somethingElse': 1},
      };
      expect(themeColor('primaryColor', sentinel), sentinel);
    });

    test('double value is accepted, not a TypeError', () {
      // JSON numbers can decode as double. The old null-guarded reads did
      // Color(x) with no .toInt() and blew up on exactly this.
      systemUIComponent = {
        'ThemeAgenia': {'buttonColor': 4278196850.0},
      };
      expect(themeColor('buttonColor', sentinel), const Color(4278196850));
    });

    test('non-numeric value -> fallback', () {
      systemUIComponent = {
        'ThemeAgenia': {'primaryColor': '#0064B2'},
      };
      expect(themeColor('primaryColor', sentinel), sentinel);
    });

    test('systemUIComponent not a Map at all -> fallback', () {
      // The try/catch, not the null-aware operators, is what saves this one.
      systemUIComponent = 'garbage';
      expect(themeColor('primaryColor', sentinel), sentinel);
    });

    test('theme names a missing entry -> fallback', () {
      theme = 'ThemeThatDoesNotExist';
      expect(themeColor('primaryColor', sentinel), sentinel);
    });

    test('explicit null colour value -> fallback', () {
      systemUIComponent = {
        'ThemeAgenia': {'primaryColor': null},
      };
      expect(themeColor('primaryColor', sentinel), sentinel);
    });
  });
}
