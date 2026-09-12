import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/theme_tokens.dart';

void main() {
  const Color fb = Color(0xFF123456);

  group('otqColor degrades instead of throwing', () {
    tearDown(() => systemUIComponent = null);

    test('null map -> fallback', () {
      systemUIComponent = null;
      expect(otqColor('primaryColor', fb), fb);
    });

    test('empty map -> fallback', () {
      systemUIComponent = <String, dynamic>{};
      expect(otqColor('primaryColor', fb), fb);
    });

    test('not a Map at all -> fallback', () {
      systemUIComponent = 'nonsense';
      expect(otqColor('primaryColor', fb), fb);
    });

    test('theme present but key missing -> fallback', () {
      systemUIComponent = <String, dynamic>{
        theme: <String, dynamic>{'themeName': 'agenia'},
      };
      expect(otqColor('primaryColor', fb), fb);
    });

    test('int value -> colour', () {
      systemUIComponent = <String, dynamic>{
        theme: <String, dynamic>{'primaryColor': 4278939264},
      };
      expect(otqColor('primaryColor', fb), const Color(0xFF0B6E80));
    });

    test('double value -> colour (JSON decode can hand us a double)', () {
      systemUIComponent = <String, dynamic>{
        theme: <String, dynamic>{'primaryColor': 4278939264.0},
      };
      expect(otqColor('primaryColor', fb), const Color(0xFF0B6E80));
    });

    test('non-numeric value -> fallback, not a throw', () {
      systemUIComponent = <String, dynamic>{
        theme: <String, dynamic>{'primaryColor': '#0B6E80'},
      };
      expect(otqColor('primaryColor', fb), fb);
    });
  });

  group('otqOn picks the readable foreground', () {
    test('white surface -> dark text', () {
      expect(otqOn(Colors.white), OtqPalette.foreground);
    });

    test('deep teal surface -> white text', () {
      expect(otqOn(const Color(0xFF0B6E80)), Colors.white);
    });

    test('navy surface -> white text', () {
      expect(otqOn(const Color(0xFF001A72)), Colors.white);
    });

    // Regression guard for the threshold bug. A `computeLuminance() < 0.5`
    // test picks WHITE on all three of these -- 2.67:1, 2.71:1 and 3.77:1,
    // the exact white-on-brand pairing the v4 system forbids. Measuring both
    // candidates puts them on the right side.
    test('brand orange -> dark text, not white', () {
      expect(otqOn(const Color(0xFFF08118)), OtqPalette.foreground);
    });

    test('brand teal -> dark text, not white', () {
      expect(otqOn(const Color(0xFF1CACC4)), OtqPalette.foreground);
    });

    test('mid green -> dark text, not white', () {
      expect(otqOn(const Color(0xFF059669)), OtqPalette.foreground);
    });
  });

  group('otqContentInset tops up to the content edge', () {
    tearDown(() => systemUIComponent = null);

    void mobile(dynamic v) =>
        systemUIComponent = <String, dynamic>{'Mobile': v};

    test('the live sheet value (8) is topped up to 16', () {
      mobile(<String, dynamic>{'leftPad': 8, 'topPad': 4, 'rightPad': 8});
      expect(otqContentInset(), const EdgeInsets.only(left: 8, right: 8));
    });

    test('a page already at 16 gets nothing, so it never double-pads', () {
      mobile(<String, dynamic>{'leftPad': 16, 'rightPad': 16});
      expect(otqContentInset(), EdgeInsets.zero);
    });

    test('a page padded WIDER than the target is left alone, not pulled back',
        () {
      mobile(<String, dynamic>{'leftPad': 24, 'rightPad': 24});
      expect(otqContentInset(), EdgeInsets.zero);
    });

    test('sides are independent', () {
      mobile(<String, dynamic>{'leftPad': 8, 'rightPad': 0});
      expect(otqContentInset(), const EdgeInsets.only(left: 8, right: 16));
    });

    test('missing, null and non-numeric config all mean zero page padding', () {
      systemUIComponent = null;
      expect(otqContentInset(), const EdgeInsets.only(left: 16, right: 16));
      systemUIComponent = <String, dynamic>{};
      expect(otqContentInset(), const EdgeInsets.only(left: 16, right: 16));
      mobile('nonsense');
      expect(otqContentInset(), const EdgeInsets.only(left: 16, right: 16));
      mobile(<String, dynamic>{'leftPad': '8'});
      expect(otqContentInset(), const EdgeInsets.only(left: 16, right: 16));
    });

    test('the target is overridable', () {
      mobile(<String, dynamic>{'leftPad': 8, 'rightPad': 8});
      expect(otqContentInset(target: 20),
          const EdgeInsets.only(left: 12, right: 12));
    });
  });

  group('otqContrast', () {
    test('matches WCAG reference values', () {
      expect(otqContrast(Colors.white, const Color(0xFF0B6E80)),
          closeTo(5.91, 0.02));
      expect(otqContrast(OtqPalette.foreground, Colors.white),
          closeTo(15.01, 0.05));
      expect(otqContrast(const Color(0xFF4A5F66), Colors.white),
          closeTo(6.73, 0.02));
    });

    test('is symmetric and bottoms out at 1.0', () {
      expect(otqContrast(Colors.white, Colors.white), 1.0);
      expect(
        otqContrast(Colors.white, const Color(0xFF0B6E80)),
        otqContrast(const Color(0xFF0B6E80), Colors.white),
      );
    });

    // The nav's step-down rule: teal clears 4.5:1 on its own pill, the lighter
    // brand teal does not, which is why activeColor is measured rather than
    // derived by a fixed lightness lift.
    test('nav active-label guard separates the two teals', () {
      const Color pillTeal = Color(0xFFE3F0F2);
      expect(otqContrast(const Color(0xFF0B6E80), pillTeal),
          greaterThanOrEqualTo(4.5));
      expect(otqContrast(const Color(0xFF1CACC4), pillTeal), lessThan(4.5));
    });
  });
}
