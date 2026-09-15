import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show diamondTextToList;
import 'package:otonomiq/widget/timeline_periodic_support.dart';

void main() {
  group('relativeTimestamp', () {
    final now = DateTime(2026, 6, 4, 15, 0).millisecondsSinceEpoch;
    test('same calendar day → "HH:mm hari ini"', () {
      final t = DateTime(2026, 6, 4, 13, 42).millisecondsSinceEpoch;
      expect(relativeTimestamp(t, now), '13:42 hari ini');
    });
    test('yesterday → "Kemarin HH:mm"', () {
      final t = DateTime(2026, 6, 3, 14, 55).millisecondsSinceEpoch;
      expect(relativeTimestamp(t, now), 'Kemarin 14:55');
    });
    test('older → "N hari lalu"', () {
      final t = DateTime(2026, 6, 2, 9, 10).millisecondsSinceEpoch;
      expect(relativeTimestamp(t, now), '2 hari lalu');
    });
  });

  group('deriveMethod', () {
    test('QR vs typed, always + foto, isQr flag', () {
      expect(deriveMethod('q1').label, 'Scan QR + foto');
      expect(deriveMethod('q1').isQr, isTrue);
      expect(deriveMethod('').label, 'Lokasi diketik + foto');
      expect(deriveMethod('').isQr, isFalse);
      expect(deriveMethod('   ').label, 'Lokasi diketik + foto');
    });
  });

  group('gapLabel', () {
    const gapMs = 43200000; // 12h
    const t = 1000000000000;
    test('below threshold → empty', () {
      expect(gapLabel(t, t - 6 * 3600000, gapMs), '');
    });
    test('always jam (hours), even for large gaps', () {
      expect(gapLabel(t, t - 23 * 3600000, gapMs), 'Jeda 23 jam');
      expect(gapLabel(t, t - 30 * 3600000, gapMs), 'Jeda 30 jam');
      expect(gapLabel(t, t - 50 * 3600000, gapMs), 'Jeda 50 jam');
    });
    test('exactly at threshold → shown', () {
      expect(gapLabel(t, t - 12 * 3600000, gapMs), 'Jeda 12 jam');
    });
  });

  group('resolveAngleTokens', () {
    test('<key> from screenTx, unknown left literal', () {
      expect(resolveAngleTokens('ln◼<point>', {'point': 'Genset'}), 'ln◼Genset');
      expect(resolveAngleTokens('ln◼<point>', const {}), 'ln◼<point>');
    });
  });

  group('filterEventsByConditions', () {
    final events = [
      {'ln': 'Genset', 'ty': 'report-patrol', 'cn': 'Agus'},
      {'ln': 'Genset', 'ty': 'report-incident', 'cn': 'Budi'}, // ty mismatch
      {'ln': 'Mushola', 'ty': 'report-patrol', 'cn': 'Sari'}, // ln mismatch
    ];
    test('AND match on ln + ty with <point> resolved', () {
      final r = filterEventsByConditions(
          events, '[[◀ln▶◼<point>◀ty▶◼report-patrol]]', {'point': 'Genset'});
      expect(r.length, 1);
      expect(r.first['cn'], 'Agus');
    });
    test('unresolved <point> → no match', () {
      expect(
          filterEventsByConditions(
              events, '[[◀ln▶◼<point>◀ty▶◼report-patrol]]', const {}),
          isEmpty);
    });
    test('empty conditions → unchanged list', () {
      expect(filterEventsByConditions(events, '', const {}).length, 3);
    });
    test('white-triangle field marker (◁sv▷) also matches, AND-combined', () {
      final evs = [
        {'ln': 'Genset', 'sv': '83', 'cn': 'Agus'},
        {'ln': 'Genset', 'sv': '99', 'cn': 'Budi'},
      ];
      final r = filterEventsByConditions(
          evs, '[[◀ln▶◼<point>◁sv▷◼<site>]]', {'point': 'Genset', 'site': '83'});
      expect(r.length, 1);
      expect(r.first['cn'], 'Agus');
    });
  });

  group('resolveStatusColor', () {
    test('statusField present, known status ok -> green', () {
      final c = resolveStatusColor('lv', {'lv': 'ok'}, '');
      expect(c, const Color(0xFF16A34A));
    });
    test('statusField present, known status warn -> amber', () {
      final c = resolveStatusColor('lv', {'lv': 'WARN'}, '');
      expect(c, const Color(0xFFD97706));
    });
    test('statusField present, known status danger -> red', () {
      final c = resolveStatusColor('lv', {'lv': 'danger'}, '');
      expect(c, const Color(0xFFDC2626));
    });
    test('statusField present, unknown value -> neutral gray', () {
      final c = resolveStatusColor('lv', {'lv': 'pending'}, '');
      expect(c, const Color(0xFF6B7280));
    });
    test('statusField present, empty value -> neutral gray', () {
      final c = resolveStatusColor('lv', {'lv': ''}, '');
      expect(c, const Color(0xFF6B7280));
    });
    test('statusField present, missing field -> neutral gray', () {
      final c = resolveStatusColor('lv', <String, dynamic>{}, '');
      expect(c, const Color(0xFF6B7280));
    });
    test('statusField null, strong evidence -> ok green', () {
      final c = resolveStatusColor(null, <String, dynamic>{}, 'Bukti kuat');
      expect(c, const Color(0xFF16A34A));
    });
    test('statusField null, weak evidence -> warn amber', () {
      final c = resolveStatusColor(null, <String, dynamic>{}, 'GPS saja');
      expect(c, const Color(0xFFD97706));
    });
  });

  group('resolveStatusBgColor', () {
    test('statusField present, known status ok -> green bg', () {
      final c = resolveStatusBgColor('lv', {'lv': 'ok'}, '');
      expect(c, const Color(0xFFDCFCE7));
    });
    test('statusField present, unknown value -> neutral gray bg', () {
      final c = resolveStatusBgColor('lv', {'lv': 'archived'}, '');
      expect(c, const Color(0xFFF3F4F6));
    });
    test('statusField null, strong evidence -> ok green bg', () {
      final c = resolveStatusBgColor(null, <String, dynamic>{}, 'Bukti kuat');
      expect(c, const Color(0xFFDCFCE7));
    });
    test('statusField null, weak evidence -> warn amber bg', () {
      final c = resolveStatusBgColor(null, <String, dynamic>{}, 'GPS saja');
      expect(c, const Color(0xFFFEF3C7));
    });
  });

  group('badgeContainsEvidence', () {
    test('template with {evidence} -> true', () {
      expect(badgeContainsEvidence('{evidence}'), isTrue);
    });
    test('template with mixed tokens including {evidence} -> true', () {
      expect(badgeContainsEvidence('<lv> {evidence}'), isTrue);
    });
    test('template without {evidence} -> false', () {
      expect(badgeContainsEvidence('<lv>'), isFalse);
    });
    test('empty template -> false', () {
      expect(badgeContainsEvidence(''), isFalse);
    });
    test('literal text only -> false', () {
      expect(badgeContainsEvidence('Approved'), isFalse);
    });
  });

  group('textContainsMethod', () {
    test('template with {method} -> true', () {
      expect(textContainsMethod('<ts>◆oleh <cn>◆{method}◆<d>'), isTrue);
    });
    test('template without {method} -> false', () {
      expect(textContainsMethod('<ts>◆oleh <cn>◆<act>◆<d>'), isFalse);
    });
    test('empty template -> false', () {
      expect(textContainsMethod(''), isFalse);
    });
  });

  // ── empty-segment blanking (meter-renderer-fixes, fix B) ─────────────────
  group('resolveHidingEmptySegments', () {
    const Map<String, String> computed = <String, String>{
      'method': 'Scan QR + foto',
      'evidence': 'Bukti kuat',
    };
    // The live kokpit row template, verbatim from the dev spec.
    const String tpl = '<ts>◆<pvo> → <sd> (+<du> m³)◆oleh <cn>◆<d>';

    /// What _buildEntry does: resolve, then split. Asserting on THIS list is
    /// asserting on what the four fixed slots receive.
    List<String> render(String t, Map<String, dynamic> doc) =>
        diamondTextToList(resolveHidingEmptySegments(t, doc, computed));

    test('a recheck event blanks segment 1 IN PLACE, slot 3 does not shift', () {
      final List<String> r = render(tpl, <String, dynamic>{
        'ts': '15:45 hari ini',
        'cn': 'Dewi (kantor)',
        'd': 'Angka meragukan — foto buram',
      });
      expect(r.length, 4);
      expect(r[0], '15:45 hari ini');
      expect(r[1], '');
      expect(r[2], 'oleh Dewi (kantor)');
      expect(r[3], 'Angka meragukan — foto buram');
    });

    test('a full reading row renders every segment unchanged', () {
      final List<String> r = render(tpl, <String, dynamic>{
        'ts': '15:38 hari ini',
        'pvo': '4581',
        'sd': '4615',
        'du': '34',
        'cn': 'Surya',
        'd': 'lancar',
      });
      expect(r, <String>[
        '15:38 hari ini',
        '4581 → 4615 (+34 m³)',
        'oleh Surya',
        'lancar',
      ]);
    });

    test('a segment with NO token is kept verbatim, punctuation and all', () {
      expect(render('<a>◆ → ', <String, dynamic>{'a': ''})[1], ' → ');
      expect(render('<a>◆Selesai', <String, dynamic>{'a': ''})[1], 'Selesai');
    });

    test('one non-empty token keeps the whole segment', () {
      expect(
        render('<a>◆<b> → <c>', <String, dynamic>{'a': 'x', 'b': '4581'})[1],
        '4581 → ',
      );
    });

    test('{method} and {evidence} are never empty, so they never blank', () {
      expect(render('<a>◆{method}', <String, dynamic>{'a': 'x'})[1],
          'Scan QR + foto');
      expect(render('<a>◆<b> {evidence}', <String, dynamic>{'a': 'x'})[1],
          ' Bukti kuat');
    });

    test('a {key} absent from computed is literal text, not a token', () {
      expect(render('<a>◆{visitCount}', <String, dynamic>{'a': 'x'})[1],
          '{visitCount}');
    });

    test('a whitespace-only doc value counts as empty', () {
      expect(render('<a>◆(<b>)', <String, dynamic>{'a': 'x', 'b': '   '})[1],
          '');
    });

    test('a doc value carrying ◆ still expands into extra slots', () {
      final List<String> r =
          render('<a>◆z', <String, dynamic>{'a': 'p◆q'});
      expect(r, <String>['p', 'q', 'z']);
    });

    test('the _u25C6_ escaped separator is a real segment boundary', () {
      // Both halves resolve -> identical to a raw ◆.
      expect(render('<a>_u25C6_<b>', <String, dynamic>{'a': 'A', 'b': 'B'}),
          <String>['A', 'B']);
      // ...and it must BLANK the same way a raw ◆ does. A plain
      // `template.split(blackDiamond)` SURVIVES the line above (the call site's
      // diamondTextToList re-splits the escape anyway) and fails only here.
      expect(render('<a>_u25C6_<b> → <c>', <String, dynamic>{'a': 'A'}),
          <String>['A', '']);
    });

    // ★ This test documents a KNOWN DIVERGENCE from the pre-helper output. It
    // is NOT a guarantee and NOT the desired rendering -- it is here so the
    // next edit to this helper cannot move the behaviour silently.
    //
    // Trigger: the template MIXES a real ◆ with a literal _u25C6_ *and* a
    // resolved value carries a `"`. The quote makes diamondTextToList's
    // jsonDecode throw into its `catch` fallback, a plain `input.split('◆')`
    // that does NOT honour _u25C6_ -- while this helper has already turned that
    // escape into a real separator. Old output: 4 segments, the note at at(3).
    // Now: 5, the note at index 4, which _buildEntry never renders.
    //
    // Left as is on purpose: matching the old output would mean copying
    // diamondTextToList's own internal inconsistency into this helper, and the
    // root -- one quote in one value re-segmenting the string for EVERY caller
    // of diamondTextToList -- is a pre-existing, app-wide bug.
    test('a MIXED-separator template with a quoted value is a KNOWN divergence',
        () {
      const String mixed = '<ts>◆<pvo>_u25C6_<sd>◆oleh <cn>◆<d>';
      final Map<String, dynamic> doc = <String, dynamic>{
        'ts': '15:38',
        'pvo': '4581',
        'sd': '4615',
        'cn': 'Surya',
        'd': 'meter "A-36" rusak',
      };
      expect(render(mixed, doc), <String>[
        '15:38',
        '4581',
        '4615',
        'oleh Surya',
        'meter "A-36" rusak',
      ]);
      // The trigger is the QUOTE, not the mixing: without it jsonDecode
      // succeeds, that path honours _u25C6_ too, and the old code produced
      // these same 5 segments.
      expect(
          render(mixed, <String, dynamic>{...doc, 'd': 'meter A-36 rusak'}),
          <String>['15:38', '4581', '4615', 'oleh Surya', 'meter A-36 rusak']);
      // A UNIFORMLY escaped template under the same trigger is an IMPROVEMENT:
      // the old code collapsed this whole row into ONE garbage segment carrying
      // the literal escapes. Do not "restore" that.
      expect(render('<ts>_u25C6_<pvo> - <sd>_u25C6_oleh <cn>_u25C6_<d>', doc),
          <String>['15:38', '4581 - 4615', 'oleh Surya', 'meter "A-36" rusak']);
      // CONTROL -- the shape the server actually ships: a pure-◆ template with
      // the same quoted value is untouched, 4 segments, note still at at(3).
      expect(render('<ts>◆<pvo> - <sd>◆oleh <cn>◆<d>', doc),
          <String>['15:38', '4581 - 4615', 'oleh Surya', 'meter "A-36" rusak']);
    });

    test("the '--' sentinel and the empty template behave as before", () {
      expect(render('--', const <String, dynamic>{}), isEmpty);
      expect(render('', const <String, dynamic>{}), <String>['']);
    });

    test('a 1-segment template with one empty token blanks to one empty slot',
        () {
      expect(render('<a>', const <String, dynamic>{}), <String>['']);
    });

    test('non-String doc values stringify, they do not blank', () {
      expect(render('<a>◆<b>', <String, dynamic>{'a': 'x', 'b': 0})[1], '0');
      expect(
          render('<a>◆<b>', <String, dynamic>{'a': 'x', 'b': false})[1],
          'false');
    });
  });
}
