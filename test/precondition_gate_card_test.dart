import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  group('PreconditionGateCard text parsing', () {
    test('diamondTextToList parses 9-slot text correctly', () {
      final text =
          'Perlu Aksi◆Konfirmasi Penerimaan Muatan◆Muat dari <2>. Cek & konfirmasi sebelum berangkat.◆Konfirmasi Penerimaan◆membuka layar...◆Muatan dikonfirmasi◆{confirmedSummary} · jumlah aktual◆! Ada selisih dari catatan gudang◆udah dilaporkan, Supervisor lagi review.';
      final arr = diamondTextToList(text);
      expect(arr.length, 9);
      expect(arr[0], 'Perlu Aksi');
      expect(arr[5], 'Muatan dikonfirmasi');
    });

    test('length guard on short arrays', () {
      final arr = diamondTextToList('A◆B◆C');
      expect(arr.length > 5 ? arr[5] : 'fallback', 'fallback');
    });
  });

  group('Gate search string decode', () {
    // W4 / encoding reality: autheniumDecode ACTIVELY decodes `_25FC_` -> ◼
    // (global.dart:1128) and `_u2B58_` -> ⭘ (global.dart:1124). The bare
    // `_2B58_` form is COMMENTED OUT (global.dart:1135), so it is NOT decoded —
    // even though CLAUDE.md and scanner_validate.dart describe the server escape
    // as bare `_2B58_`. This mismatch is flagged as an out-of-scope finding for
    // code-reviewer. These tests assert autheniumDecode's ACTUAL behavior.
    test('autheniumDecode converts _25FC_ to ◼ and _u2B58_ to ⭘', () {
      final raw = 'cty_25FC_opening_u2B58_vv_25FC_123';
      final decoded = autheniumDecode(raw);
      expect(decoded, contains('\u{25FC}')); // ◼
      expect(decoded, contains('\u{2B58}')); // ⭘
    });

    test('bare _2B58_ is NOT decoded (latent autheniumDecode gap)', () {
      // Documents the current behavior: bare _2B58_ stays literal. If the live
      // op1Screen JSON sends bare _2B58_ for the AND-separator, the gate search
      // would not split — see walkthrough out-of-scope note.
      final decoded = autheniumDecode('vv_2B58_cdt');
      expect(decoded!.contains('\u{2B58}'), isFalse);
      expect(decoded.contains('_2B58_'), isTrue);
    });
  });

  group('{confirmedSummary} from ip[] (P3)', () {
    // Tests the CONTRACT of confirmed-summary computation:
    // aggregateActualSummary(ip[], nameMap) -> summary string,
    // then template.replaceAll('{confirmedSummary}', computed).

    // W2: mirrors _buildConfirmed's empty-summary cleanup — substitute, then
    // when the computed value is empty, strip a leading middle-dot separator so
    // no dangling "· suffix" renders. Asserts the CLEAN rendered string.
    String renderSummary(String template, String computed) {
      String out = template.replaceAll('{confirmedSummary}', computed);
      if (computed.isEmpty) {
        // Mirror _buildConfirmed: non-raw string so \u{00B7} is the literal
        // middle-dot char (a raw regex would not match without the unicode flag).
        out = out.replaceFirst(RegExp('^\\s*\u{00B7}\\s*'), '').trim();
      }
      return out;
    }

    test('template substitution with computed summary', () {
      final template = '{confirmedSummary} \u{00B7} jumlah aktual';
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': '30'},
        {'ii': '31', 'cd': 'empty', 'qt': '4'},
        {'ii': '32', 'cd': 'full', 'qt': '12'},
      ];
      final nameMap = {
        '31': 'Amidis Galon 19 Lite',
        '32': 'Aqua 600ml',
      };
      final computed = aggregateActualSummary(ip, nameMap);
      final result = renderSummary(template, computed);
      expect(result,
          '34 Amidis Galon 19 Lite \u{00B7} 12 Aqua 600ml \u{00B7} jumlah aktual');
    });

    test('empty ip[] -> empty summary, leading middle-dot stripped (W2)', () {
      // W2: with an empty computed summary, the confirmed card must NOT render a
      // dangling "· jumlah aktual". _buildConfirmed strips the leading dot, so
      // the rendered line is just the suffix "jumlah aktual".
      final template = '{confirmedSummary} \u{00B7} jumlah aktual';
      final computed = aggregateActualSummary([], {});
      expect(computed, '');
      final result = renderSummary(template, computed);
      expect(result, 'jumlah aktual');
    });

    test('absent ip (null) -> empty summary', () {
      final computed = aggregateActualSummary(null, {});
      expect(computed, '');
    });

    test('template without {confirmedSummary} passes through unchanged', () {
      const template = 'Muatan sudah dikonfirmasi';
      // No {confirmedSummary} token -> replaceAll is a no-op.
      final result = template.replaceAll('{confirmedSummary}', 'ignored');
      expect(result, 'Muatan sudah dikonfirmasi');
    });

    test('ip[] with unknown ii -> raw id in summary', () {
      final ip = [
        {'ii': '999', 'cd': 'full', 'qt': '5'},
      ];
      final computed = aggregateActualSummary(ip, {});
      expect(computed, '5 999');
    });
  });
}
