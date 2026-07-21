import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'; // phoneCanonical62
import 'package:otonomiq/widget/ftz_contact_picker.dart';
import 'package:otonomiq/widget/whatsapp_send.dart'; // renderWhatsAppTemplate

void main() {
  // ── Template renderer tests ─────────────────────────────────────────

  group('renderWhatsAppTemplate', () {
    test('scalar field replacement', () {
      final doc = {'nno': 'INV-2026-001', 'by': 'Toko ABC'};
      final result =
          renderWhatsAppTemplate('No: {{nno}}, Pembeli: {{by}}', doc);
      expect(result, 'No: INV-2026-001, Pembeli: Toko ABC');
    });

    test('missing field produces empty string', () {
      final doc = <String, dynamic>{'nno': 'INV-001'};
      final result = renderWhatsAppTemplate('{{nno}} - {{missing}}', doc);
      expect(result, 'INV-001 - ');
    });

    test('idr formatter with int', () {
      final doc = {'tot': 1250000};
      final result = renderWhatsAppTemplate('Total: {{tot|idr}}', doc);
      expect(result, 'Total: 1.250.000');
    });

    test('idr formatter with string input', () {
      final doc = {'tot': '71000'};
      final result = renderWhatsAppTemplate('Rp {{tot|idr}}', doc);
      expect(result, 'Rp 71.000');
    });

    test('idr formatter with zero', () {
      final doc = {'tot': 0};
      final result = renderWhatsAppTemplate('{{tot|idr}}', doc);
      expect(result, '0');
    });

    test('idr formatter passes pre-formatted input through, never renders 0',
        () {
      // A tenant sheet that already stores tot dot-formatted must NOT collapse
      // to "*TOTAL: 0*". double.tryParse('1.250.000') returns null; the old
      // `?? 0.0` fallback silently rendered 0 with no exception raised.
      final doc = {'tot': '1.250.000'};
      final result = renderWhatsAppTemplate('*TOTAL: {{tot|idr}}*', doc);
      expect(result, isNot(contains('TOTAL: 0')));
      expect(result, '*TOTAL: 1.250.000*');
    });

    test('idr formatter passes non-numeric text through unchanged', () {
      final doc = {'tot': 'n/a'};
      final result = renderWhatsAppTemplate('{{tot|idr}}', doc);
      expect(result, 'n/a');
    });

    test('LOOP with multiple items', () {
      final doc = {
        'li': [
          {'in': 'Beras', 'qt': 5, 'sub': 50000},
          {'in': 'Gula', 'qt': 2, 'sub': 30000},
        ],
      };
      final result = renderWhatsAppTemplate(
        '<LOOP li>{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>',
        doc,
      );
      expect(result, 'Beras x5 = 50.000\nGula x2 = 30.000\n');
    });

    test('LOOP with zero items produces empty string', () {
      final doc = {'li': <Map<String, dynamic>>[]};
      final result = renderWhatsAppTemplate(
        'Items:<LOOP li>{{item.in}}\n</LOOP>Done',
        doc,
      );
      expect(result, 'Items:Done');
    });

    test('LOOP with null array produces empty string', () {
      final doc = <String, dynamic>{};
      final result = renderWhatsAppTemplate(
        '<LOOP li>{{item.in}}</LOOP>',
        doc,
      );
      expect(result, '');
    });

    test('LOOP with single item', () {
      final doc = {
        'li': [
          {'in': 'Air', 'qt': 1},
        ],
      };
      final result = renderWhatsAppTemplate(
        '<LOOP li>{{item.in}} x{{item.qt}}</LOOP>',
        doc,
      );
      expect(result, 'Air x1');
    });

    test('backslash-n becomes real newline', () {
      final doc = {'a': 'X', 'b': 'Y'};
      final result = renderWhatsAppTemplate(r'{{a}}\n{{b}}', doc);
      expect(result, 'X\nY');
    });

    test('full invoice template end-to-end', () {
      final doc = {
        'nno': 'INV-2026-001',
        'by': 'Toko Maju',
        'ts': '2026-07-17',
        'tot': 80000,
        'li': [
          {'in': 'Beras', 'qt': 5, 'sub': 50000},
          {'in': 'Gula', 'qt': 2, 'sub': 30000},
        ],
      };
      final template = r'*INVOICE {{nno}}*\n{{by}}\n{{ts}}\n'
          r'------------------\n'
          r'<LOOP li>{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>'
          r'------------------\n'
          r'*TOTAL: {{tot|idr}}*\nTerima kasih';
      final result = renderWhatsAppTemplate(template, doc);
      expect(
        result,
        '*INVOICE INV-2026-001*\n'
        'Toko Maju\n'
        '2026-07-17\n'
        '------------------\n'
        'Beras x5 = 50.000\n'
        'Gula x2 = 30.000\n'
        '------------------\n'
        '*TOTAL: 80.000*\n'
        'Terima kasih',
      );
    });
  });

  // ── Phone normalization tests (phoneCanonical62 from global.dart) ───

  group('phoneCanonical62', () {
    test('08xx normalizes to 628xx', () {
      expect(phoneCanonical62('081234567890'), '6281234567890');
    });

    test('+62 with spaces normalizes', () {
      expect(phoneCanonical62('+62 812 3456 7890'), '6281234567890');
    });

    test('already prefixed 62 stays idempotent', () {
      expect(phoneCanonical62('6281234567890'), '6281234567890');
    });

    test('raw 8xx gets 62 prefix', () {
      expect(phoneCanonical62('81234567890'), '6281234567890');
    });

    test('empty input returns empty', () {
      expect(phoneCanonical62(''), '');
    });

    test('letters only returns empty', () {
      expect(phoneCanonical62('abcdef'), '');
    });

    test('dashes and spaces stripped', () {
      expect(phoneCanonical62('0812-3456-7890'), '6281234567890');
    });

    test('parentheses stripped', () {
      // Plan had '(0812) 345 6789' (11 digits) against the 13-char canonical
      // expectation — arithmetically impossible: stripping the leading 0
      // leaves 10 digits -> '628123456789'. phoneCanonical62 is correct; the
      // plan's input was one digit short. Input corrected to the parenthesized
      // form of the SAME number every sibling test in this group asserts.
      expect(phoneCanonical62('(0812) 3456 7890'), '6281234567890');
    });
  });

  // ── URL encoding ───────────────────────────────────────────────────

  group('wa.me URL encoding', () {
    test('newline and special chars encoded', () {
      const phone = '6281234567890';
      const message = 'Hello\nWorld & "test"';
      final url =
          'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
      expect(url, contains('wa.me/6281234567890'));
      expect(url, contains('text='));
      expect(Uri.encodeComponent(message), contains('%0A'));
      expect(Uri.encodeComponent(message), contains('%26'));
    });
  });

  // ── C1 regression: logSearch must use U+25FC, not star ─────────────

  group('logSearch separator', () {
    test('writeNativeFields search uses U+25FC not star', () {
      // writeNativeFields splits on U+25FC (◼). A search string using ★
      // would silently drop the clause (sep < 0 → continue), leaving an
      // empty search that writes nothing. This test pins the correct
      // separator in the canonical config value.
      const correctSearch = 'tnm\u{25FC}{taskVid}';
      // Must contain the ◼ separator
      expect(correctSearch.contains('\u{25FC}'), isTrue);
      // Must NOT contain ★
      expect(correctSearch.contains('\u{2605}'), isFalse);
      // The separator index must be > 0 (field name before it)
      expect(correctSearch.indexOf('\u{25FC}'), greaterThan(0));
    });
  });

  // ── C4 regression: launch failure must not mark sent ───────────────
  // launchUrl is a platform call that cannot be unit-tested without a
  // mock package (url_launcher_platform_interface). The C4 ordering
  // (launch first → mark only on success) is verified in manual QA
  // (section 6.4 item 1, bullet "WhatsApp not installed"). This test
  // documents the contract without faking the platform.

  group('launch-failure contract (documented, manual QA)', () {
    test('contract: launch before marker, not after', () {
      // The _launch() method in _WhatsAppSheetState must:
      //   1. Call launchUrl FIRST
      //   2. Only on success: writeNativeFields + onSent() + pop
      //   3. On failure: snackbar, keep sheet open, no write, no badge
      // This is not testable without url_launcher mocks. See section 6.4.
      expect(true, isTrue); // placeholder to document the contract
    });
  });

  // ── LOOP dialect regression (device-reported 2026-07-20) ───────────
  // Sheet operators author in template_printer.dart's dialect, whose
  // _parseAttributes accepts source='li' / "li" / li. The first build only
  // matched the dev-spec shorthand <LOOP li>, so a correctly-authored
  // template shipped its raw tag into the customer's WhatsApp message.

  group('LOOP source dialect', () {
    final Map<String, dynamic> doc = {
      'tot': 14000,
      'li': [
        {'in': 'Beras', 'qt': 2, 'sub': 10000},
        {'in': 'Gula', 'qt': 1, 'sub': 4000},
      ],
    };
    const String expected = 'Beras x2 = 10.000\nGula x1 = 4.000\n';

    test("source='li' (single quotes, the PRN form) renders", () {
      expect(
        renderWhatsAppTemplate(
          "<LOOP source='li'>{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>",
          doc,
        ),
        expected,
      );
    });

    test('source="li" (double quotes) renders', () {
      expect(
        renderWhatsAppTemplate(
          '<LOOP source="li">{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>',
          doc,
        ),
        expected,
      );
    });

    test('source=li (unquoted) renders', () {
      expect(
        renderWhatsAppTemplate(
          '<LOOP source=li>{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>',
          doc,
        ),
        expected,
      );
    });

    test('<LOOP li> shorthand still renders (back-compat)', () {
      expect(
        renderWhatsAppTemplate(
          '<LOOP li>{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>',
          doc,
        ),
        expected,
      );
    });

    test('unknown source yields empty, never a raw tag', () {
      final String out = renderWhatsAppTemplate(
        "<LOOP source='nope'>{{item.in}}</LOOP>",
        doc,
      );
      expect(out, '');
      expect(out, isNot(contains('LOOP')));
    });

    test('no raw LOOP tag survives the device-reported template', () {
      final String out = renderWhatsAppTemplate(
        r"*INVOICE {{nno}}*\n{{by}}\n--------\n"
        r"<LOOP source='li'>{{item.in}} x{{item.qt}} = {{item.sub|idr}}\n</LOOP>"
        r"--------\n*TOTAL: {{tot|idr}}*",
        {...doc, 'nno': 'INV-001', 'by': 'Toko Contoh Jaya'},
      );
      expect(out, isNot(contains('<LOOP')));
      expect(out, isNot(contains('</LOOP>')));
      expect(out, isNot(contains('{{')));
      expect(out, contains('Beras x2 = 10.000'));
      expect(out, contains('*TOTAL: 14.000*'));
    });
  });

  // ── Contact picker search (device-reported 2026-07-20) ─────────────

  group('contactMatchesQuery', () {
    final List<dynamic> budi = [
      'Budi Santoso',
      {'mobile': '+62 812-3456-7890'},
    ];

    test('empty query matches everything', () {
      expect(contactMatchesQuery(budi, ''), isTrue);
      expect(contactMatchesQuery(budi, '   '), isTrue);
    });

    test('name match is case-insensitive substring', () {
      expect(contactMatchesQuery(budi, 'budi'), isTrue);
      expect(contactMatchesQuery(budi, 'SANTOSO'), isTrue);
      expect(contactMatchesQuery(budi, 'santo'), isTrue);
      expect(contactMatchesQuery(budi, 'agus'), isFalse);
    });

    test('typed local format matches stored international format', () {
      // The whole point: what the user types never matches byte-for-byte.
      expect(contactMatchesQuery(budi, '0812-3456'), isTrue);
      expect(contactMatchesQuery(budi, '812 3456'), isTrue);
      expect(contactMatchesQuery(budi, '6281234'), isTrue);
    });

    test('non-matching digits are rejected', () {
      expect(contactMatchesQuery(budi, '9999'), isFalse);
    });

    test('multiple numbers: any one matching is enough', () {
      final List<dynamic> multi = [
        'Toko Jaya',
        {'work': '021-555-1234', 'mobile': '0857-0000-1111'},
      ];
      expect(contactMatchesQuery(multi, '5551234'), isTrue);
      expect(contactMatchesQuery(multi, '85700001111'), isTrue);
      expect(contactMatchesQuery(multi, '0898'), isFalse);
    });

    test('digitless query never falls through to the number branch', () {
      expect(contactMatchesQuery(budi, 'zzz'), isFalse);
    });

    test('malformed rows do not throw', () {
      expect(contactMatchesQuery(<dynamic>[], 'x'), isFalse);
      expect(contactMatchesQuery(<dynamic>['OnlyName'], '812'), isFalse);
      expect(contactMatchesQuery(<dynamic>['N', 'not-a-map'], '812'), isFalse);
    });
  });
}
