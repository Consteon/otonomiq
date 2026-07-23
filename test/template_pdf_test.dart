import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otonomiq/template_pdf.dart';

void main() {
  // ── interpolate tests ───────────────────────────────────────────────

  group('TemplatePdf.interpolate', () {
    late TemplatePdf tp;

    setUp(() {
      tp = TemplatePdf(
          template: '', pageFormat: PdfPageFormat.a6, tables: {});
    });

    test('scalar field replacement', () {
      final ctx = <String, dynamic>{'ln': 'Pos Utara', 'sn': 'Site A'};
      expect(tp.interpolate('{{ln}} - {{sn}}', ctx), 'Pos Utara - Site A');
    });

    test('missing field produces empty string', () {
      final ctx = <String, dynamic>{'ln': 'Pos'};
      expect(tp.interpolate('{{ln}} {{missing}}', ctx), 'Pos ');
    });

    test('nested map traversal (item.field)', () {
      final ctx = <String, dynamic>{
        'item': {'in': 'Beras', 'qt': 5},
      };
      expect(tp.interpolate('{{item.in}} x{{item.qt}}', ctx), 'Beras x5');
    });

    test('idr formatter with int', () {
      final ctx = <String, dynamic>{'tot': 1250000};
      expect(tp.interpolate('{{tot|idr}}', ctx), '1.250.000');
    });

    test('idr formatter with string input', () {
      final ctx = <String, dynamic>{'tot': '71000'};
      expect(tp.interpolate('Rp {{tot|idr}}', ctx), 'Rp 71.000');
    });

    test('idr formatter with zero', () {
      final ctx = <String, dynamic>{'tot': 0};
      expect(tp.interpolate('{{tot|idr}}', ctx), '0');
    });

    test('idr formatter passes non-numeric text through unchanged', () {
      final ctx = <String, dynamic>{'tot': 'n/a'};
      expect(tp.interpolate('{{tot|idr}}', ctx), 'n/a');
    });

    test('idr formatter passes pre-formatted input through unchanged', () {
      // Divergence from ESC/POS renderer: pre-formatted '1.250.000' is NOT
      // collapsed to '0'. See class doc for rationale.
      final ctx = <String, dynamic>{'tot': '1.250.000'};
      expect(tp.interpolate('{{tot|idr}}', ctx), '1.250.000');
    });

    test('usd formatter', () {
      final ctx = <String, dynamic>{'price': 1234567};
      expect(tp.interpolate('{{price|usd}}', ctx), '1,234,567.00');
    });

    test('default formatter with empty value', () {
      final ctx = <String, dynamic>{'by': ''};
      expect(tp.interpolate('{{by|default:Umum}}', ctx), 'Umum');
    });

    test('default formatter with non-empty value', () {
      final ctx = <String, dynamic>{'by': 'Toko ABC'};
      expect(tp.interpolate('{{by|default:Umum}}', ctx), 'Toko ABC');
    });

    test('list count accessor', () {
      final ctx = <String, dynamic>{
        'li': [
          {'in': 'A'},
          {'in': 'B'},
          {'in': 'C'},
        ],
      };
      expect(tp.interpolate('{{li.count}} items', ctx), '3 items');
    });

    test('table array access (1-based row, 0-based col)', () {
      final ctx = <String, dynamic>{
        'data': [
          ['Alice', '30'],
          ['Bob', '25'],
        ],
      };
      expect(tp.interpolate('{{data[1][0]}}', ctx), 'Alice');
      expect(tp.interpolate('{{data[2][1]}}', ctx), '25');
    });

    test('hyphenated field on a Map item resolves (Divergence 2, W1)', () {
      // The `-` sends this down interpolate's expression branch. With a Map
      // item, _replaceItemPlaceholders used to throw a _TypeError before the
      // documented _resolveByPath fallback could run.
      final ctx = <String, dynamic>{
        'item': {'item-name': 'Beras'},
      };
      expect(tp.interpolate('{{item.item-name}}', ctx), 'Beras');
    });

    test('arithmetic over a Map item degrades to empty, never throws', () {
      final ctx = <String, dynamic>{
        'item': {'qt': 2, 'hg': 5000},
      };
      expect(tp.interpolate('{{item.qt * item.hg}}', ctx), '');
    });

    test('item[N] placeholders still work for positional List items', () {
      // The W1 guard must not regress the List path it was written for.
      final ctx = <String, dynamic>{
        'item': [10, 3],
      };
      expect(tp.interpolate('{{item[0] * item[1]}}', ctx), '30');
    });

    test('out of bounds table access returns empty', () {
      final ctx = <String, dynamic>{
        'data': [
          ['Alice'],
        ],
      };
      expect(tp.interpolate('{{data[5][0]}}', ctx), '');
    });
  });

  // ── parseAttributes tests ──────────────────────────────────────────

  group('TemplatePdf.parseAttributes', () {
    late TemplatePdf tp;

    setUp(() {
      tp = TemplatePdf(
          template: '', pageFormat: PdfPageFormat.a6, tables: {});
    });

    test('single-quoted attributes', () {
      final attrs = tp.parseAttributes("align='center' bold='true'");
      expect(attrs['align'], 'center');
      expect(attrs['bold'], 'true');
    });

    test('double-quoted attributes', () {
      final attrs = tp.parseAttributes('data="hello world" size="8"');
      expect(attrs['data'], 'hello world');
      expect(attrs['size'], '8');
    });

    test('bare attributes (no quotes)', () {
      final attrs = tp.parseAttributes('size=6 align=right');
      expect(attrs['size'], '6');
      expect(attrs['align'], 'right');
    });

    test('mixed quoting styles', () {
      final attrs =
          tp.parseAttributes("align='center' data=\"test\" size=4");
      expect(attrs['align'], 'center');
      expect(attrs['data'], 'test');
      expect(attrs['size'], '4');
    });

    test('empty string returns empty map', () {
      expect(tp.parseAttributes(''), isEmpty);
    });
  });

  // ── resolveAndSanitizeFileName tests ───────────────────────────────

  group('resolveAndSanitizeFileName', () {
    test('resolves {{field}} tokens', () {
      final ctx = <String, dynamic>{'ln': 'Pos Utara'};
      expect(
        resolveAndSanitizeFileName('titik-{{ln}}.pdf', ctx),
        'titik-Pos Utara.pdf',
      );
    });

    test('removes illegal filename chars', () {
      final ctx = <String, dynamic>{'ln': 'A<B>C:D'};
      expect(
        resolveAndSanitizeFileName('{{ln}}.pdf', ctx),
        'ABCD.pdf',
      );
    });

    test('collapses whitespace', () {
      final ctx = <String, dynamic>{'ln': 'A   B'};
      expect(
        resolveAndSanitizeFileName('{{ln}}.pdf', ctx),
        'A B.pdf',
      );
    });

    test('appends .pdf if missing', () {
      final ctx = <String, dynamic>{'ln': 'report'};
      expect(
        resolveAndSanitizeFileName('{{ln}}', ctx),
        'report.pdf',
      );
    });

    test('preserves .pdf if already present', () {
      final ctx = <String, dynamic>{'ln': 'test'};
      expect(
        resolveAndSanitizeFileName('{{ln}}.pdf', ctx),
        'test.pdf',
      );
    });

    test('returns share.pdf for empty result', () {
      final ctx = <String, dynamic>{};
      expect(
        resolveAndSanitizeFileName('{{missing}}', ctx),
        'share.pdf',
      );
    });

    test('handles missing field gracefully', () {
      final ctx = <String, dynamic>{'ln': 'OK'};
      expect(
        resolveAndSanitizeFileName('{{ln}}-{{missing}}.pdf', ctx),
        'OK-.pdf',
      );
    });

    test('strips control characters', () {
      final ctx = <String, dynamic>{'ln': 'A\x00B\x1FC'};
      expect(
        resolveAndSanitizeFileName('{{ln}}.pdf', ctx),
        'ABC.pdf',
      );
    });

    test('strips curly braces from unresolved dot-path tokens', () {
      final ctx = <String, dynamic>{};
      final result = resolveAndSanitizeFileName('{{item.in}}.pdf', ctx);
      expect(result, isNot(contains('{')));
      expect(result, isNot(contains('}')));
    });

    test('unresolved dot-path token does not leak its NAME into the name', () {
      // Regression: the token pattern used to be \w+, so '{{item.in}}' never
      // matched, and brace-stripping left the bare text behind -> 'N-item.in.pdf'.
      final ctx = <String, dynamic>{};
      expect(resolveAndSanitizeFileName('N-{{item.in}}.pdf', ctx), 'N-.pdf');
      expect(
        resolveAndSanitizeFileName('{{item.in}}.pdf', ctx),
        isNot(contains('item')),
      );
    });

    test('name that resolves away entirely falls back to share.pdf', () {
      // '{{item.in}}.pdf' -> '.pdf' would be a nameless hidden file.
      expect(
        resolveAndSanitizeFileName('{{item.in}}.pdf', <String, dynamic>{}),
        'share.pdf',
      );
    });
  });

  // ── PDF generation tests ───────────────────────────────────────────

  group('TemplatePdf.generateBytes', () {
    test('simple text template produces valid PDF', () async {
      final tp = TemplatePdf(
        template: '<TEXT align="center" bold="true">Hello World</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      // PDF files start with %PDF
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, startsWith('%PDF'));
    });

    test('QR code template produces valid PDF', () async {
      final tp = TemplatePdf(
        template:
            "<QRCODE data='https://example.com' align='center' size='8'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, startsWith('%PDF'));
    });

    test('CUT tag is silently ignored', () async {
      final tp = TemplatePdf(
        template: '<TEXT>Before</TEXT>;<CUT>;<TEXT>After</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      // Should not throw
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('unknown tag is silently ignored', () async {
      final tp = TemplatePdf(
        template: '<TEXT>Before</TEXT>;<BANANA size=5>;<TEXT>After</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('LOOP with list of maps', () async {
      final tp = TemplatePdf(
        template:
            "<LOOP source='li'><TEXT>{{item.in}} x{{item.qt}}</TEXT></LOOP>",
        pageFormat: PdfPageFormat.a6,
        tables: {
          'li': [
            {'in': 'Beras', 'qt': 5},
            {'in': 'Gula', 'qt': 2},
          ],
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('multi-line LOOP (;-separated) renders each item', () async {
      // The single-line form is what the other LOOP tests exercise; real
      // templates use this ;-separated form, which routes through
      // _processMultiLineLoop instead of _processSingleLineLoop.
      final tp = TemplatePdf(
        template: "<TEXT>Header</TEXT>"
            ";<LOOP source='li'>"
            ";<TEXT>{{item.in}} x{{item.qt}}</TEXT>"
            ";</LOOP>"
            ";<TEXT>Footer</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {
          'li': [
            {'in': 'Beras', 'qt': 5},
            {'in': 'Gula', 'qt': 2},
          ],
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    // Map-field arithmetic renders EMPTY -- it does not compute. Neither
    // renderer has ever supported it: _replaceItemPlaceholders only substitutes
    // positional `item[N]`, so over a Map there is nothing to substitute, the
    // expression evaluator then fails on the bare field names, and the
    // divergence-2 fallback resolves `item.qt * item.hg` as a path, which
    // misses. Asserted explicitly because the earlier version of this test was
    // named "does not throw", called this "the canonical invoice line-total
    // construct", and checked only isNotEmpty + %PDF -- passing while the
    // outcome it named was wrong. That is the same shape as the zero-page bug
    // below. Use the positional form for a real line total (next test).
    test('Map loop item arithmetic renders empty, and does not throw',
        () async {
      final tp = TemplatePdf(
        template:
            "<LOOP source='li'><TEXT>{{item.qt * item.hg}}</TEXT></LOOP>",
        pageFormat: PdfPageFormat.a6,
        tables: {
          'li': [
            {'in': 'Beras', 'qt': 2, 'hg': 5000},
          ],
        },
      );

      // The actual outcome: empty, NOT 10000.
      expect(
        tp.interpolate('{{item.qt * item.hg}}', {
          'item': {'in': 'Beras', 'qt': 2, 'hg': 5000},
        }),
        '',
      );

      // W1 regression guard: _replaceItemPlaceholders used to cast
      // context['item'] to List<dynamic>? while the LOOP walkers deliberately
      // put a Map there. That call sits OUTSIDE interpolate's try/catch, so the
      // _TypeError escaped and killed the whole render.
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('positional loop item arithmetic DOES compute a line total', () {
      // The form that actually works, for contrast with the Map case above.
      final tp = TemplatePdf(
          template: '', pageFormat: PdfPageFormat.a6, tables: {});
      expect(
        tp.interpolate('{{item[1] * item[2]}}', {
          'item': ['Beras', 2, 5000],
        }),
        '10000',
      );
    });

    // ── Empty-output guard ───────────────────────────────────────────
    // These four used to assert `expect(bytes, isNotEmpty)` and PASS, while
    // pw.MultiPage silently allocated ZERO pages: a 427-byte file whose page
    // tree is `<</Type/Pages/Kids[]/Count 0>>`, which no viewer opens.
    // `bytes.isNotEmpty` is TRUE for that file, so byte length can never be
    // the guard. generateBytes() now throws instead of producing a shareable
    // broken artifact.

    test('LOOP with missing source throws instead of emitting a pageless PDF',
        () async {
      final tp = TemplatePdf(
        template:
            "<LOOP source='missing'><TEXT>{{item.in}}</TEXT></LOOP>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      expect(tp.generateBytes(), throwsStateError);
    });

    test('LOOP with null source throws instead of emitting a pageless PDF',
        () async {
      final tp = TemplatePdf(
        template: "<LOOP source='li'><TEXT>{{item.in}}</TEXT></LOOP>",
        pageFormat: PdfPageFormat.a6,
        tables: {'li': null},
      );
      expect(tp.generateBytes(), throwsStateError);
    });

    test('LOOP over an EMPTY list throws (nota with zero line items)',
        () async {
      // The realistic C1 trigger: an invoice/nota whose cart is empty.
      final tp = TemplatePdf(
        template: "<LOOP source='li'><TEXT>{{item.in}}</TEXT></LOOP>",
        pageFormat: PdfPageFormat.a6,
        tables: {'li': []},
      );
      expect(tp.generateBytes(), throwsStateError);
    });

    test('template of only unknown tags throws', () async {
      final tp = TemplatePdf(
        template: '<BANANA size=5>;<CUT>;;;',
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      expect(tp.generateBytes(), throwsStateError);
    });

    test('GROUP_BY is silently skipped', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT>Header</TEXT>;<GROUP_BY source='data' column='0'>;<TEXT>inside</TEXT>;</GROUP_BY>;<TEXT>Footer</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('A4 vs A6 both produce valid PDFs (smoke test)', () async {
      // ponytail: smoke test only -- real page-size verification is device
      // manual test #4. Byte length is an indirect proxy; the two formats
      // produce structurally different /MediaBox entries.
      const tpl = "<TEXT align='center' bold='true' height='2'>Test</TEXT>";
      final a6 = await TemplatePdf(
              template: tpl, pageFormat: PdfPageFormat.a6, tables: {})
          .generateBytes();
      final a4 = await TemplatePdf(
              template: tpl, pageFormat: PdfPageFormat.a4, tables: {})
          .generateBytes();
      expect(String.fromCharCodes(a6.sublist(0, 5)), startsWith('%PDF'));
      expect(String.fromCharCodes(a4.sublist(0, 5)), startsWith('%PDF'));
      // Different page formats produce different PDF structures
      expect(a6.length != a4.length, isTrue);
    });

    test('HR renders without error', () async {
      final tp = TemplatePdf(
        template: '<TEXT>Above</TEXT>;<HR>;<TEXT>Below</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('FEED renders spacing without error', () async {
      final tp = TemplatePdf(
        template: "<TEXT>Top</TEXT>;<FEED lines='3'>;<TEXT>Bottom</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('ROW with COL renders without error', () async {
      final tp = TemplatePdf(
        template:
            "<ROW><COL width='6'>Left</COL><COL width='6'>Right</COL></ROW>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('full P3 QR card template end-to-end', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT align='center' bold='true' height='2'>{{ln}}</TEXT>"
            ";<QRCODE data='{{lu}}' align='center' size='8'/>"
            ";<TEXT align='center'>{{sn}}</TEXT>"
            ";<TEXT align='center'>powered by autsorz</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {
          'ln': 'Pos Gerbang Timur',
          'lu': 'https://autsorz.com/qr/2abc123',
          'sn': 'Site Utama',
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, startsWith('%PDF'));
    });

    test('non-Latin-1 glyphs do not throw', () async {
      // pdf's default Helvetica is Latin-1 only. Typographic quotes and
      // en-dashes are plausible in sheet-sourced Firestore docs. This test
      // verifies the renderer does not throw; legibility is verified on
      // device (manual test #8). If this test fails, either sanitize to
      // ASCII before rendering or embed a TTF font.
      final tp = TemplatePdf(
        template: "<TEXT>{{ln}}</TEXT>;<TEXT>{{desc}}</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {
          'ln': "Pos’s Gate – East",
          'desc': 'Café entrée',
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, startsWith('%PDF'));
    });
  });

  // ── Iteration 2: alignment, color, border, IMAGE, QRCODE-empty ────

  group('Gap 1: TEXT alignment', () {
    test('_buildText wraps in SizedBox for full-width alignment', () {
      final tp = TemplatePdf(
          template: "<TEXT align='center'>Hello</TEXT>",
          pageFormat: PdfPageFormat.a6,
          tables: {});
      final widgets = tp.processBlock(0, 0, {});
      expect(widgets.length, 1);
      // _buildText now returns SizedBox(width: infinity, child: Text(...))
      expect(widgets.first, isA<pw.SizedBox>());
    });

    test('centered TEXT produces valid PDF', () async {
      final tp = TemplatePdf(
        template: "<TEXT align='center' bold='true'>Centered Title</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });
  });

  group('Gap 2: TEXT color', () {
    test('color attribute resolved via colorResolver', () async {
      bool resolverCalled = false;
      final tp = TemplatePdf(
        template: "<TEXT color='blue'>Blue text</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        colorResolver: (name) {
          resolverCalled = true;
          expect(name, 'blue');
          return PdfColors.blue;
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(resolverCalled, isTrue);
    });

    test('absent color defaults to black (no resolver call)', () async {
      bool resolverCalled = false;
      final tp = TemplatePdf(
        template: '<TEXT>No color</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        colorResolver: (_) {
          resolverCalled = true;
          return PdfColors.red;
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(resolverCalled, isFalse);
    });

    test('color without resolver defaults to black (no throw)', () async {
      final tp = TemplatePdf(
        template: "<TEXT color='blue'>Blue without resolver</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        // colorResolver intentionally null
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });
  });

  group('Gap 3: border', () {
    test('borderColor renders page border without error', () async {
      final tp = TemplatePdf(
        template: "<TEXT>With border</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        borderColor: PdfColors.blue,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('null borderColor produces PDF without border (no regression)', () async {
      final tp = TemplatePdf(
        template: '<TEXT>No border</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        // borderColor intentionally null
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });
  });

  group('Gap 4: IMAGE tag', () {
    // Minimal valid 1x1 white PNG for testing (base64-decoded)
    final testPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4'
      '//8/AAX+Av4zEpUUAAAAAElFTkSuQmCC',
    );

    test('IMAGE with assetLoader renders valid PDF', () async {
      final tp = TemplatePdf(
        template: "<IMAGE asset='logo' align='center' height=16/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        assetLoader: (key) async => key == 'logo' ? testPng : null,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('IMAGE with missing asset skips silently', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT>Header</TEXT>;<IMAGE asset='missing' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        assetLoader: (key) async => null,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('IMAGE without assetLoader skips silently', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT>Header</TEXT>;<IMAGE asset='logo' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        // assetLoader intentionally null
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('IMAGE inside ROW/COL renders valid PDF', () async {
      final tp = TemplatePdf(
        template: "<ROW align='center'>"
            "<COL width=6 align='right'>powered by </COL>"
            "<COL width=6 align='left'><IMAGE asset='logo' height=16/></COL>"
            '</ROW>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        assetLoader: (key) async => key == 'logo' ? testPng : null,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('IMAGE with asset load error skips silently', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT>Header</TEXT>;<IMAGE asset='bad' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        assetLoader: (key) async => throw Exception('disk error'),
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });
  });

  group('Gap 5: QRCODE empty data', () {
    test('QRCODE with empty data throws StateError', () async {
      final tp = TemplatePdf(
        template: "<QRCODE data='' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      expect(tp.generateBytes(), throwsStateError);
    });

    test('QRCODE with unresolved field throws StateError', () async {
      final tp = TemplatePdf(
        template: "<QRCODE data='{{missing}}' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      expect(tp.generateBytes(), throwsStateError);
    });

    test('QRCODE with non-empty data still works', () async {
      final tp = TemplatePdf(
        template:
            "<QRCODE data='https://example.com' align='center' size='8'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });
  });

  group('Iteration 2: full template end-to-end', () {
    final testPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4'
      '//8/AAX+Av4zEpUUAAAAAElFTkSuQmCC',
    );

    test('P3 sticker template with all iter-2 features', () async {
      final tp = TemplatePdf(
        template: "<TEXT align='center' bold='true' color='blue'>{{ln}}</TEXT>"
            ";<FEED/>"
            ";<QRCODE data='{{lu}}' align='center'/>"
            ";<FEED/>"
            ";<ROW align='center'>"
            "<COL width=6 align='right'>powered by </COL>"
            "<COL width=6 align='left'><IMAGE asset='autsorz_logo' height=16/></COL>"
            '</ROW>',
        pageFormat: PdfPageFormat.a6,
        tables: {
          'ln': 'Pos Gerbang Timur',
          'lu': 'https://autsorz.com/qr/2abc123',
        },
        colorResolver: (name) => PdfColors.blue,
        borderColor: PdfColors.blue,
        assetLoader: (key) async =>
            key == 'autsorz_logo' ? testPng : null,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });
  });

  // ── Iteration 3: hex color, borderWidth, grid ──────────────────────

  group('Iter 3A: hex color in colorResolver', () {
    test('colorResolver receives hex string and produces valid PDF', () async {
      String? receivedColor;
      final tp = TemplatePdf(
        template: "<TEXT color='#1FA0A6'>Hex color text</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        colorResolver: (name) {
          receivedColor = name;
          // Mirrors the widget's _resolvePdfColor hex path
          if (name.startsWith('#')) return PdfColor.fromHex(name);
          return PdfColors.black;
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
      expect(receivedColor, '#1FA0A6');
    });

    test('named color still works alongside hex', () async {
      String? receivedColor;
      final tp = TemplatePdf(
        template: "<TEXT color='blue'>Named color text</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        colorResolver: (name) {
          receivedColor = name;
          return PdfColors.blue;
        },
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(receivedColor, 'blue');
    });

    test('PdfColor.fromHex handles #RRGGBB correctly', () {
      final color = PdfColor.fromHex('#1FA0A6');
      // R=0x1F/255, G=0xA0/255, B=0xA6/255
      expect(color.red, closeTo(0x1F / 255, 0.01));
      expect(color.green, closeTo(0xA0 / 255, 0.01));
      expect(color.blue, closeTo(0xA6 / 255, 0.01));
    });

    test('hex border color renders page border', () async {
      final tp = TemplatePdf(
        template: '<TEXT>Hex border</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        borderColor: PdfColor.fromHex('#1FA0A6'),
        borderWidth: 10.0,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });
  });

  group('Iter 3B: borderWidth param', () {
    test('borderWidth replaces hardcoded const', () async {
      final tp = TemplatePdf(
        template: '<TEXT>Custom border width</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        borderColor: PdfColors.blue,
        borderWidth: 12.0,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('borderWidth defaults to 8.0 (backward compatible)', () async {
      final tp = TemplatePdf(
        template: '<TEXT>Default width</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        borderColor: PdfColors.blue,
        // borderWidth not specified -> uses default 8.0
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });

    test('large borderWidth does not obscure content', () async {
      // margin >= borderWidth + 4, so content shifts inward.
      final tp = TemplatePdf(
        template: "<TEXT align='center'>Wide border</TEXT>",
        pageFormat: PdfPageFormat.a6,
        tables: {},
        borderColor: PdfColors.red,
        borderWidth: 30.0,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('borderWidth without borderColor produces no border (no crash)',
        () async {
      final tp = TemplatePdf(
        template: '<TEXT>No border but width set</TEXT>',
        pageFormat: PdfPageFormat.a6,
        tables: {},
        // borderColor intentionally null
        borderWidth: 15.0,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
    });
  });

  group('Iter 3C: grid mode', () {
    test('generateGridBytes 2x2 produces valid PDF', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT align='center' bold='true'>{{ln}}</TEXT>"
            ";<QRCODE data='{{lu}}' align='center'/>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'Pos A', 'lu': 'https://example.com/a'},
          {'ln': 'Pos B', 'lu': 'https://example.com/b'},
          {'ln': 'Pos C', 'lu': 'https://example.com/c'},
        ],
        gridCols: 2,
        gridRows: 2,
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('generateGridBytes 4x4 produces valid PDF', () async {
      final items = List<Map<String, dynamic>>.generate(
        16,
        (i) => {'ln': 'Pos $i', 'lu': 'https://example.com/$i'},
      );
      final tp = TemplatePdf(
        template:
            "<TEXT align='center'>{{ln}}</TEXT>"
            ";<QRCODE data='{{lu}}' align='center'/>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
      );
      final bytes = await tp.generateGridBytes(
        items: items,
        gridCols: 4,
        gridRows: 4,
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('grid pagination: >KxB items produce multi-page PDF', () async {
      final items = List<Map<String, dynamic>>.generate(
        5,
        (i) => {'ln': 'Item $i', 'lu': 'https://example.com/$i'},
      );
      final tp = TemplatePdf(
        template:
            "<TEXT>{{ln}}</TEXT>;<QRCODE data='{{lu}}'/>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
      );
      // 5 items in 2x2 grid = 2 pages (4 + 1)
      final bytes = await tp.generateGridBytes(
        items: items,
        gridCols: 2,
        gridRows: 2,
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('grid with 1 item fills one cell, rest empty', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT>{{ln}}</TEXT>;<QRCODE data='{{lu}}'/>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'Solo', 'lu': 'https://example.com/solo'},
        ],
        gridCols: 4,
        gridRows: 4,
      );
      expect(bytes, isNotEmpty);
    });

    test('grid with borderColor renders per-card borders', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT>{{ln}}</TEXT>;<QRCODE data='{{lu}}'/>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
        borderColor: PdfColors.teal,
        borderWidth: 10.0,
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'A', 'lu': 'https://a.com'},
          {'ln': 'B', 'lu': 'https://b.com'},
        ],
        gridCols: 2,
        gridRows: 2,
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('grid with IMAGE pre-loads assets once across all cards', () async {
      final testPng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4'
        '//8/AAX+Av4zEpUUAAAAAElFTkSuQmCC',
      );
      int loadCount = 0;
      final tp = TemplatePdf(
        template:
            "<TEXT>{{ln}}</TEXT>;<IMAGE asset='logo'/>"
            ";<QRCODE data='{{lu}}'/>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
        assetLoader: (key) async {
          loadCount++;
          return key == 'logo' ? testPng : null;
        },
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'A', 'lu': 'https://a.com'},
          {'ln': 'B', 'lu': 'https://b.com'},
          {'ln': 'C', 'lu': 'https://c.com'},
        ],
        gridCols: 2,
        gridRows: 2,
      );
      expect(bytes, isNotEmpty);
      expect(loadCount, 1); // asset loaded ONCE, reused per card
    });

    test('empty items throws StateError', () async {
      final tp = TemplatePdf(
        template: '<TEXT>{{ln}}</TEXT>',
        pageFormat: PdfPageFormat.a4,
        tables: const {},
      );
      expect(
        tp.generateGridBytes(
            items: const [], gridCols: 2, gridRows: 2),
        throwsStateError,
      );
    });

    test('single-mode generateBytes unchanged (regression)', () async {
      final tp = TemplatePdf(
        template:
            "<TEXT align='center' bold='true'>{{ln}}</TEXT>"
            ";<QRCODE data='{{lu}}' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: {
          'ln': 'Regression Test',
          'lu': 'https://example.com/regress',
        },
        borderColor: PdfColors.blue,
        borderWidth: 10.0,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('grid A6 with small cells renders (QR warning path)', () async {
      // A6 4x4 -> tiny cells (~26x37mm). QR < 25mm likely.
      // This verifies the renderer does NOT throw on small cells.
      final tp = TemplatePdf(
        template:
            "<TEXT>{{ln}}</TEXT>;<QRCODE data='{{lu}}'/>",
        pageFormat: PdfPageFormat.a6,
        tables: const {},
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'A', 'lu': 'https://a.com'},
          {'ln': 'B', 'lu': 'https://b.com'},
        ],
        gridCols: 4,
        gridRows: 4,
      );
      // Renders successfully despite small cells -- WARN is at widget level.
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    // ── W1 (code-review r4): a zero-height grid card must never corrupt the
    // PDF. pw.FittedBox asserts height>0 (debug) / yields a NaN transform ->
    // blank-corrupt PDF silently shared (release). Both guards keep it valid.

    test('grid card with NO widgets is padded, not corrupt (W1)', () async {
      // "<CUT/>" is silently ignored -> processBlock yields zero widgets.
      final tp = TemplatePdf(
        template: '<CUT/>',
        pageFormat: PdfPageFormat.a4,
        tables: const {},
        borderColor: PdfColor.fromHex('#1FA0A6'),
        borderWidth: 8.0,
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'A'},
          {'ln': 'B'},
        ],
        gridCols: 2,
        gridRows: 2,
      );
      // Empty cards padded; render succeeds instead of asserting / NaN-corrupt.
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('grid card of all-empty <TEXT> (zero height) renders, not corrupt (W1)',
        () async {
      // Non-empty widget list, but its only widget resolves to zero height.
      // The minHeight floor keeps FittedBox dividing by a height > 0.
      final tp = TemplatePdf(
        template: "<TEXT align='center'>{{missing}}</TEXT>",
        pageFormat: PdfPageFormat.a4,
        tables: const {},
      );
      final bytes = await tp.generateGridBytes(
        items: [
          {'ln': 'A'},
          {'ln': 'B'},
          {'ln': 'C'},
        ],
        gridCols: 2,
        gridRows: 2,
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });
  });

  // ── <IMAGE url='...'> network source (footer branding image) ────────
  // The renderer stays IO-free: a `url` key is passed to assetLoader exactly
  // like an `asset` key; the widget's loader fetches http(s). `url` wins over
  // `asset` when both are present.
  group('IMAGE url (network source)', () {
    final testPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4'
      '//8/AAX+Av4zEpUUAAAAAElFTkSuQmCC',
    );

    test('IMAGE url attr resolves via assetLoader with the URL key', () async {
      String? receivedKey;
      final tp = TemplatePdf(
        template:
            "<IMAGE url='https://example.com/powered-by.png' align='center' width='120'/>",
        pageFormat: PdfPageFormat.a6,
        tables: const {},
        assetLoader: (key) async {
          receivedKey = key;
          return key.startsWith('http') ? testPng : null;
        },
      );
      final bytes = await tp.generateBytes();
      expect(receivedKey, 'https://example.com/powered-by.png');
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('IMAGE url takes precedence over asset when both present', () async {
      final keys = <String>[];
      final tp = TemplatePdf(
        template:
            "<IMAGE url='https://example.com/a.png' asset='autsorz_logo' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: const {},
        assetLoader: (key) async {
          keys.add(key);
          return testPng;
        },
      );
      await tp.generateBytes();
      expect(keys, contains('https://example.com/a.png'));
      expect(keys, isNot(contains('autsorz_logo')));
    });

    test('IMAGE url inside COL renders (single-image footer use case)',
        () async {
      final tp = TemplatePdf(
        template: "<ROW align='center'><COL width=1 align='center'>"
            "<IMAGE url='https://example.com/powered-by.png' width='120'/>"
            "</COL></ROW>",
        pageFormat: PdfPageFormat.a6,
        tables: const {},
        assetLoader: (key) async =>
            key.startsWith('http') ? testPng : null,
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });

    test('IMAGE url offline (loader returns null) skips silently', () async {
      final tp = TemplatePdf(
        template: "<TEXT>Header</TEXT>"
            ";<IMAGE url='https://example.com/x.png' align='center'/>",
        pageFormat: PdfPageFormat.a6,
        tables: const {},
        assetLoader: (key) async => null, // simulates offline / non-200
      );
      final bytes = await tp.generateBytes();
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), startsWith('%PDF'));
    });
  });
}
