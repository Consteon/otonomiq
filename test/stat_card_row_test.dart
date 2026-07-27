import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/stat_card_row.dart';

void main() {
  // ── parseStatCardDefs ─────────────────────────────────────────────────

  group('parseStatCardDefs', () {
    test('parses 3-card happy path', () {
      final defs = parseStatCardDefs(
          'Approved\u{25FC}ap\u{25FC}ok'
          '\u{2605}Batch siap\u{25FC}bt\u{25FC}accent'
          '\u{2605}Menunggu\u{25FC}pnd\u{25FC}muted');
      expect(defs.length, 3);
      expect(defs[0].label, 'Approved');
      expect(defs[0].field, 'ap');
      expect(defs[0].tone, 'ok');
      expect(defs[1].label, 'Batch siap');
      expect(defs[1].field, 'bt');
      expect(defs[1].tone, 'accent');
      expect(defs[2].label, 'Menunggu');
      expect(defs[2].field, 'pnd');
      expect(defs[2].tone, 'muted');
    });

    test('missing tone segment defaults to muted', () {
      final defs = parseStatCardDefs('Label\u{25FC}fld');
      expect(defs.length, 1);
      expect(defs[0].tone, 'muted');
    });

    test('missing field segment yields empty field', () {
      final defs = parseStatCardDefs('Label');
      expect(defs.length, 1);
      expect(defs[0].label, 'Label');
      expect(defs[0].field, '');
      expect(defs[0].tone, 'muted');
    });

    test('empty cards string returns empty list', () {
      expect(parseStatCardDefs(''), isEmpty);
      expect(parseStatCardDefs('  '), isEmpty);
    });

    test('trailing ★ does not produce extra entry', () {
      final defs = parseStatCardDefs('A\u{25FC}a\u{25FC}ok\u{2605}');
      expect(defs.length, 1);
    });

    test('empty label entry is skipped', () {
      final defs = parseStatCardDefs('\u{25FC}fld\u{25FC}ok');
      expect(defs, isEmpty);
    });

    test('empty tone segment defaults to muted', () {
      final defs = parseStatCardDefs('Label\u{25FC}fld\u{25FC}');
      expect(defs.length, 1);
      expect(defs[0].tone, 'muted');
    });

    test('4-card parse (dynamic add via sheet)', () {
      final defs = parseStatCardDefs(
          'A\u{25FC}a\u{25FC}ok'
          '\u{2605}B\u{25FC}b\u{25FC}warn'
          '\u{2605}C\u{25FC}c\u{25FC}danger'
          '\u{2605}D\u{25FC}d\u{25FC}accent');
      expect(defs.length, 4);
      expect(defs[3].label, 'D');
      expect(defs[3].tone, 'accent');
    });

    test('◼ in label shifts field and tone by one segment (intentional)', () {
      // CONFIG RULE: a label must not contain ◼. `Batch◼siap◼bt◼ok` is parsed
      // positionally, so 'Batch' becomes the label, 'siap' shifts into field,
      // and 'bt' shifts into tone. 'bt' is not a known tone, so W4 normalizes
      // it to 'muted'. This pins the shift as intentional, not a silent bug.
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      final defs = parseStatCardDefs('Batch\u{25FC}siap\u{25FC}bt\u{25FC}ok');
      debugPrint = originalDebugPrint;
      expect(defs.length, 1);
      expect(defs[0].label, 'Batch');
      expect(defs[0].field, 'siap');
      expect(defs[0].tone, 'muted');
    });

    test('unknown tone is normalized to muted by parser', () {
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      final defs = parseStatCardDefs('Label\u{25FC}fld\u{25FC}xyzzy');
      debugPrint = originalDebugPrint;
      expect(defs.length, 1);
      expect(defs[0].tone, 'muted');
    });
  });

  // ── statCardFgColor / statCardBgColor ─────────────────────────────────

  group('tone color resolution', () {
    test('known tones resolve to distinct colors', () {
      expect(statCardFgColor('ok'), const Color(0xFF16A34A));
      expect(statCardFgColor('warn'), const Color(0xFFD97706));
      expect(statCardFgColor('danger'), const Color(0xFFDC2626));
      expect(statCardFgColor('accent'), const Color(0xFF2563EB));
      expect(statCardFgColor('muted'), const Color(0xFF6B7280));
    });

    test('unknown tone falls back to muted', () {
      // Colour resolvers keep a silent default fallback (unknown tones are
      // already normalized upstream in parseStatCardDefs).
      expect(statCardFgColor('typo'), const Color(0xFF6B7280));
      expect(statCardBgColor('typo'), const Color(0xFFF3F4F6));
    });

    test('known bg tones resolve correctly', () {
      expect(statCardBgColor('ok'), const Color(0xFFDCFCE7));
      expect(statCardBgColor('warn'), const Color(0xFFFEF3C7));
      expect(statCardBgColor('danger'), const Color(0xFFFEE2E2));
      expect(statCardBgColor('accent'), const Color(0xFFDBEAFE));
      expect(statCardBgColor('muted'), const Color(0xFFF3F4F6));
    });
  });

  // ── resolveStatValue ──────────────────────────────────────────────────

  group('resolveStatValue', () {
    test('field present in doc returns its string value', () {
      final doc = <String, dynamic>{'ap': 17, 'bt': '1', 'pnd': 3};
      expect(resolveStatValue(doc, 'ap'), '17');
      expect(resolveStatValue(doc, 'bt'), '1');
      expect(resolveStatValue(doc, 'pnd'), '3');
    });

    test('field absent in doc returns 0', () {
      final doc = <String, dynamic>{'ap': 17};
      expect(resolveStatValue(doc, 'bt'), '0');
    });

    test('field null in doc returns 0', () {
      final doc = <String, dynamic>{'ap': null};
      expect(resolveStatValue(doc, 'ap'), '0');
    });

    test('empty field name returns 0', () {
      final doc = <String, dynamic>{'ap': 17};
      expect(resolveStatValue(doc, ''), '0');
    });

    test('non-numeric string value is returned as-is', () {
      final doc = <String, dynamic>{'status': 'aktif'};
      expect(resolveStatValue(doc, 'status'), 'aktif');
    });
  });
}
