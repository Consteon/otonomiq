import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/admin_home_support.dart';
import 'package:otonomiq/widget/signal_list_support.dart';

/// Pure-parser tests for SIGNAL_LIST (`lib/widget/signal_list_support.dart`).
///
/// Deliberately NO `testWidgets` pump: a widget test of SignalList would need
/// Firebase (subscribeToMapCollection) and would mostly prove that a code path
/// was never reached. Every test below fails if the logic it covers is mutated.
void main() {
  // Real separators pulled from global.dart, so a separator change breaks a
  // test instead of silently breaking production.
  final String diamond = separator[1]; // ◆ U+25C6
  final String square = separator[2]; // ◼ U+25FC
  final String star = separator[3]; // ★ U+2605

  // ── signalTextSegment — the 1-based ◆ accessor ─────────────────────────

  group('signalTextSegment', () {
    final List<String> full = <String>[
      '<cn>',
      '<ct>',
      '<ds> hari belum order',
      'biasa tiap <cd> hari',
      'Follow up',
      'Semua pelanggan dalam ritme — aman',
      'Cari nama',
      'Radar Reorder',
    ];

    test('spec segment N maps to array index N-1 (off-by-one guard)', () {
      expect(signalTextSegment(full, 1), '<cn>');
      expect(signalTextSegment(full, 2), '<ct>');
      expect(signalTextSegment(full, 3), '<ds> hari belum order');
      expect(signalTextSegment(full, 4), 'biasa tiap <cd> hari');
      expect(signalTextSegment(full, 5), 'Follow up');
      expect(signalTextSegment(full, 6), 'Semua pelanggan dalam ritme — aman');
      expect(signalTextSegment(full, 7), 'Cari nama');
      expect(signalTextSegment(full, 8), 'Radar Reorder');
    });

    test('short array: configured segments hit, missing segments return empty',
        () {
      final List<String> short = <String>['<cn>', '<ct>', 'metric'];
      expect(signalTextSegment(short, 1), '<cn>');
      expect(signalTextSegment(short, 3), 'metric');
      expect(signalTextSegment(short, 4), '');
      expect(signalTextSegment(short, 8), '');
    });

    test('out-of-range never throws RangeError (lean tenant sheet)', () {
      final List<String> oneSegment = <String>['only'];
      expect(() => signalTextSegment(oneSegment, 8), returnsNormally);
      expect(signalTextSegment(oneSegment, 8), '');
    });

    test('empty list returns empty for every segment', () {
      expect(signalTextSegment(const <String>[], 1), '');
      expect(signalTextSegment(const <String>[], 8), '');
    });

    test("diamondTextToList('') yields [''] — segment 1 hits it, 2..8 fall back",
        () {
      // NOT []: global.dart:1793 short-circuits only on the '--' sentinel,
      // so '' falls through to jsonDecode('[""]').
      final List<String> segs = diamondTextToList('');
      expect(segs.length, 1);
      expect(segs.first, '');
      expect(signalTextSegment(segs, 1), '');
      expect(signalTextSegment(segs, 8), '');
    });

    test('segment 0 and negative segments return empty, never throw', () {
      expect(signalTextSegment(full, 0), '');
      expect(signalTextSegment(full, -3), '');
    });

    test('segment 9 (future extension) on an 8-segment array returns empty',
        () {
      expect(signalTextSegment(full, 9), '');
    });
  });

  // ── parseSignalStatusMap ───────────────────────────────────────────────

  group('parseSignalStatusMap', () {
    test('parses full 3-field entries and preserves order', () {
      final List<SignalStatusEntry> e = parseSignalStatusMap(
          'dormant${square}Lama menghilang${square}warn'
          '${star}overdue${square}Telat order${square}warn');
      expect(e.length, 2);
      expect(e[0].value, 'dormant');
      expect(e[0].label, 'Lama menghilang');
      expect(e[0].tone, 'warn');
      expect(e[1].value, 'overdue');
      expect(e[1].label, 'Telat order');
      expect(e[1].tone, 'warn');
    });

    test('missing tone field defaults to neutral', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('x${square}Label');
      expect(e.length, 1);
      expect(e[0].tone, 'neutral');
    });

    test('empty tone field defaults to neutral', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('x${square}Label$square');
      expect(e.length, 1);
      expect(e[0].tone, 'neutral');
    });

    test('missing label falls back to the value', () {
      final List<SignalStatusEntry> e = parseSignalStatusMap('x');
      expect(e.length, 1);
      expect(e[0].value, 'x');
      expect(e[0].label, 'x');
      expect(e[0].tone, 'neutral');
    });

    test('empty label field falls back to the value', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('x$square${square}warn');
      expect(e.length, 1);
      expect(e[0].label, 'x');
      expect(e[0].tone, 'warn');
    });

    test('entry with an empty value is skipped', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('${square}Label${square}warn${star}ok${square}OK');
      expect(e.length, 1);
      expect(e[0].value, 'ok');
    });

    test('blank entries between stars are skipped', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('a${square}A$star$star${star}b${square}B');
      expect(e.length, 2);
      expect(e[0].value, 'a');
      expect(e[1].value, 'b');
    });

    test('a 4th field is ignored, not fatal', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('a${square}A${square}warn${square}junk');
      expect(e.length, 1);
      expect(e[0].tone, 'warn');
    });

    test('empty and whitespace input yield an empty list', () {
      expect(parseSignalStatusMap(''), isEmpty);
      expect(parseSignalStatusMap('   '), isEmpty);
    });

    test('surrounding whitespace is trimmed off every field', () {
      final List<SignalStatusEntry> e =
          parseSignalStatusMap('  a  $square  A  $square  warn  ');
      expect(e[0].value, 'a');
      expect(e[0].label, 'A');
      expect(e[0].tone, 'warn');
    });
  });

  // ── lookupSignalStatus ─────────────────────────────────────────────────

  group('lookupSignalStatus', () {
    final List<SignalStatusEntry> entries = parseSignalStatusMap(
        'dormant${square}Lama${square}warn${star}overdue${square}Telat${square}warn');

    test('known value returns its entry', () {
      expect(lookupSignalStatus(entries, 'overdue')?.label, 'Telat');
    });

    test('unknown value returns null (widget then hides the pill)', () {
      expect(lookupSignalStatus(entries, 'overdue_x'), isNull);
    });

    test('empty value returns null', () {
      expect(lookupSignalStatus(entries, ''), isNull);
      expect(lookupSignalStatus(entries, '   '), isNull);
    });

    test('empty entry list returns null', () {
      expect(lookupSignalStatus(const <SignalStatusEntry>[], 'overdue'), isNull);
    });
  });

  // ── resolveSignalTone — THE DOCTRINE GUARD ─────────────────────────────

  group('resolveSignalTone', () {
    test('★ DOCTRINE: danger is forced to warn (amber, never red)', () {
      expect(resolveSignalTone('danger'), 'warn');
    });

    test('★ DOCTRINE: danger is forced regardless of case or padding', () {
      expect(resolveSignalTone('DANGER'), 'warn');
      expect(resolveSignalTone('  Danger  '), 'warn');
    });

    test('known tones pass through, case-insensitively', () {
      expect(resolveSignalTone('warn'), 'warn');
      expect(resolveSignalTone('WARN'), 'warn');
      expect(resolveSignalTone('ok'), 'ok');
      expect(resolveSignalTone('accent'), 'accent');
      expect(resolveSignalTone('neutral'), 'neutral');
    });

    test('unknown and empty tones fall back to neutral', () {
      expect(resolveSignalTone('purple'), 'neutral');
      expect(resolveSignalTone(''), 'neutral');
      expect(resolveSignalTone('   '), 'neutral');
    });
  });

  // ── signalToneColors — THE PALETTE TRAP ────────────────────────────────

  group('signalToneColors', () {
    test('★ TRAP: tone warn uses the AMBER danger* tokens, not the VIOLET warn*',
        () {
      final SignalToneColors c = signalToneColors('warn');
      expect(c.accent, AdminTierColors.dangerBorder); // #F59E0B amber
      expect(c.pillBg, AdminTierColors.dangerBadgeBg); // #FEF3C7
      expect(c.pillText, AdminTierColors.dangerBadgeText); // #B45309
      expect(c.cardTint, AdminTierColors.dangerBg); // #FFF7E6
      // The violet trap, asserted explicitly so a "fix" to the same-named
      // token fails here instead of shipping a violet badge.
      expect(c.pillText, isNot(AdminTierColors.warnBadgeText)); // #7C3AED
      expect(c.pillBg, isNot(AdminTierColors.warnBadgeBg)); // #EDE9FE
    });

    test('★ DOCTRINE: tone danger resolves byte-identically to tone warn', () {
      final SignalToneColors d = signalToneColors('danger');
      final SignalToneColors w = signalToneColors('warn');
      expect(d.accent, w.accent);
      expect(d.pillBg, w.pillBg);
      expect(d.pillText, w.pillText);
      expect(d.cardTint, w.cardTint);
    });

    test('★ DOCTRINE: no tone can ever produce a red', () {
      const List<Color> reds = <Color>[
        Color(0xFFDC2626),
        Color(0xFFEF4444),
        Color(0xFFFEE2E2),
        Color(0xFFB91C1C),
      ];
      for (final String tone in <String>[
        'warn',
        'ok',
        'accent',
        'neutral',
        'danger',
        'DANGER',
        'nonsense',
        '',
      ]) {
        final SignalToneColors c = signalToneColors(tone);
        for (final Color red in reds) {
          expect(c.accent, isNot(red), reason: 'accent for "$tone"');
          expect(c.pillBg, isNot(red), reason: 'pillBg for "$tone"');
          expect(c.pillText, isNot(red), reason: 'pillText for "$tone"');
          expect(c.cardTint, isNot(red), reason: 'cardTint for "$tone"');
        }
        expect(c.accent, isNot(Colors.red), reason: 'accent for "$tone"');
        expect(c.pillText, isNot(Colors.red), reason: 'pillText for "$tone"');
      }
    });

    test('tone ok uses okActionGreen for TEXT (AA), not okBadgeText', () {
      final SignalToneColors c = signalToneColors('ok');
      expect(c.pillText, AdminTierColors.okActionGreen); // #15803D ≈5.0:1
      expect(c.pillText, isNot(AdminTierColors.okBadgeText)); // #16A34A ≈3.2:1
      expect(c.pillBg, AdminTierColors.okBadgeBg);
      expect(c.cardTint, Colors.white);
    });

    test('tone accent uses the blue action palette', () {
      final SignalToneColors c = signalToneColors('accent');
      expect(c.accent, AdminTierColors.okAction);
      expect(c.pillBg, AdminTierColors.iconTileBg);
      expect(c.pillText, AdminTierColors.okAction);
      expect(c.cardTint, Colors.white);
    });

    test('unknown tone falls back to the neutral row', () {
      final SignalToneColors u = signalToneColors('chartreuse');
      final SignalToneColors n = signalToneColors('neutral');
      expect(u.accent, n.accent);
      expect(u.pillBg, n.pillBg);
      expect(u.pillText, n.pillText);
      expect(u.cardTint, n.cardTint);
      expect(n.accent, AdminTierColors.mutedText);
      expect(n.pillBg, AdminTierColors.normalBadgeBg);
      expect(n.pillText, AdminTierColors.normalBadgeText);
      expect(n.cardTint, Colors.white);
    });
  });

  // ── parseSignalGaps — tolerant, shape UNVERIFIED ───────────────────────

  group('parseSignalGaps', () {
    test('List of num passes through', () {
      expect(parseSignalGaps(<num>[7, 6, 8, 7]), <num>[7, 6, 8, 7]);
    });

    test('List of String is coerced', () {
      expect(parseSignalGaps(<String>['7', '6', '8']), <num>[7, 6, 8]);
    });

    test('List of dynamic mixes int/double/String', () {
      expect(parseSignalGaps(<dynamic>[7, '6', 8.5]), <num>[7, 6, 8.5]);
    });

    test('non-numeric list elements are DROPPED, never defaulted to 0', () {
      expect(parseSignalGaps(<dynamic>['7', 'abc', '8']), <num>[7, 8]);
      expect(parseSignalGaps(<dynamic>['7', null, '8']), <num>[7, 8]);
    });

    test('★ VERIFIED SHAPE: List of Map yields the first numeric value each',
        () {
      // Live Firestore (otq-01, 2026-08-06): the tenant's only array field,
      // task.it, is an array of maps. If the reorder_cache CF follows house
      // style, this is the shape `gaps` arrives in.
      expect(
          parseSignalGaps(<dynamic>[
            <String, dynamic>{'d': 7},
            <String, dynamic>{'d': 6},
            <String, dynamic>{'d': 8},
          ]),
          <num>[7, 6, 8]);
    });

    test('List of Map: any key name works, and string-numbers are read', () {
      expect(
          parseSignalGaps(<dynamic>[
            <String, dynamic>{'gap': '7'},
            <String, dynamic>{'days': 6},
          ]),
          <num>[7, 6]);
    });

    test('List of Map: non-numeric leading fields are skipped, not fatal', () {
      // Mirrors task.it, where string fields precede the numbers.
      expect(
          parseSignalGaps(<dynamic>[
            <String, dynamic>{'tx': 'deliver', 'ad': 2},
            <String, dynamic>{'tx': 'pickup', 'ad': 5},
          ]),
          <num>[2, 5]);
    });

    test('List of Map with no numeric value at all is dropped, never throws',
        () {
      expect(
          () => parseSignalGaps(<dynamic>[
                <String, dynamic>{'tx': 'deliver'}
              ]),
          returnsNormally);
      expect(
          parseSignalGaps(<dynamic>[
            <String, dynamic>{'tx': 'deliver'},
            <String, dynamic>{'d': 7},
          ]),
          <num>[7]);
    });

    test('◆-joined String', () {
      expect(parseSignalGaps('7${diamond}6${diamond}8'), <num>[7, 6, 8]);
    });

    test('comma-joined String', () {
      expect(parseSignalGaps('7,6,8'), <num>[7, 6, 8]);
      expect(parseSignalGaps('7, 6, 8'), <num>[7, 6, 8]);
    });

    test('JSON-ish bracketed String', () {
      expect(parseSignalGaps('[7,6,8]'), <num>[7, 6, 8]);
      expect(parseSignalGaps('["7","6","8"]'), <num>[7, 6, 8]);
    });

    test('bare scalar in either form', () {
      expect(parseSignalGaps('7'), <num>[7]);
      expect(parseSignalGaps(7), <num>[7]);
    });

    test('null, empty, whitespace and the -- sentinel yield an empty list', () {
      expect(parseSignalGaps(null), isEmpty);
      expect(parseSignalGaps(''), isEmpty);
      expect(parseSignalGaps('   '), isEmpty);
      expect(parseSignalGaps('--'), isEmpty);
      expect(parseSignalGaps(<dynamic>[]), isEmpty);
    });

    test('fully garbage input yields an empty list, never throws', () {
      expect(() => parseSignalGaps('abc'), returnsNormally);
      expect(parseSignalGaps('abc'), isEmpty);
      expect(parseSignalGaps(<String, dynamic>{'a': 1}), isEmpty);
    });
  });

  // ── formatSignalGapValue ───────────────────────────────────────────────

  group('formatSignalGapValue', () {
    test('ints print bare', () {
      expect(formatSignalGapValue(7), '7');
      expect(formatSignalGapValue(24), '24');
    });

    test('whole doubles print as ints, not 7.0', () {
      expect(formatSignalGapValue(7.0), '7');
    });

    test('genuine fractions keep one decimal', () {
      expect(formatSignalGapValue(7.5), '7.5');
      expect(formatSignalGapValue(7.46), '7.5');
    });
  });

  // ── parseSignalSort ────────────────────────────────────────────────────

  group('parseSignalSort', () {
    test('field◼desc', () {
      final SignalSortSpec s = parseSignalSort('ds${square}desc');
      expect(s.field, 'ds');
      expect(s.desc, isTrue);
      expect(s.isEmpty, isFalse);
    });

    test('field◼asc', () {
      final SignalSortSpec s = parseSignalSort('ds${square}asc');
      expect(s.field, 'ds');
      expect(s.desc, isFalse);
    });

    test('direction is case-insensitive', () {
      expect(parseSignalSort('ds${square}DESC').desc, isTrue);
    });

    test('bare field defaults to ascending', () {
      final SignalSortSpec s = parseSignalSort('ds');
      expect(s.field, 'ds');
      expect(s.desc, isFalse);
    });

    test('unknown direction defaults to ascending', () {
      expect(parseSignalSort('ds${square}sideways').desc, isFalse);
    });

    test('empty input is isEmpty (no sort)', () {
      expect(parseSignalSort('').isEmpty, isTrue);
      expect(parseSignalSort('   ').isEmpty, isTrue);
      expect(parseSignalSort('${square}desc').isEmpty, isTrue);
    });
  });

  // ── Dev spec §4 acceptance: two configs, ZERO code difference ──────────

  group('dev spec §4 acceptance — generic proof', () {
    test('config A (Reorder galon) resolves all 8 text segments', () {
      const String text = '<cn>◆<ct>◆<ds> hari belum order◆biasa tiap <cd> hari'
          '◆Follow up◆Semua pelanggan dalam ritme — aman◆Cari nama◆Radar Reorder';
      final List<String> segs = diamondTextToList(text);
      expect(segs.length, 8);
      expect(signalTextSegment(segs, 1), '<cn>');
      expect(signalTextSegment(segs, 2), '<ct>');
      expect(signalTextSegment(segs, 3), '<ds> hari belum order');
      expect(signalTextSegment(segs, 4), 'biasa tiap <cd> hari');
      expect(signalTextSegment(segs, 5), 'Follow up');
      expect(signalTextSegment(segs, 6), 'Semua pelanggan dalam ritme — aman');
      expect(signalTextSegment(segs, 7), 'Cari nama');
      expect(signalTextSegment(segs, 8), 'Radar Reorder');
    });

    test('config A statusMap: 2 entries, both amber warn', () {
      final List<SignalStatusEntry> e = parseSignalStatusMap(
          'dormant${square}Lama menghilang${square}warn'
          '${star}overdue${square}Telat order${square}warn');
      expect(e.length, 2);
      for (final SignalStatusEntry entry in e) {
        expect(resolveSignalTone(entry.tone), 'warn');
        expect(signalToneColors(entry.tone).accent,
            AdminTierColors.dangerBorder); // amber
      }
    });

    test('config A sort + timeline config', () {
      expect(parseSignalSort('ds${square}desc').field, 'ds');
      expect(parseSignalSort('ds${square}desc').desc, isTrue);
      expect(parseSignalGaps(<num>[7, 6, 8, 7]), <num>[7, 6, 8, 7]);
    });

    test('config B (Service AC) resolves all 8 text segments — same code', () {
      const String text = '<al>◆<cn> · <mk>◆Servis lewat <od> hari'
          '◆servis tiap <cad> bln◆Jadwalkan◆Semua unit terawat◆Cari unit'
          '◆Aset Perlu Servis';
      final List<String> segs = diamondTextToList(text);
      expect(segs.length, 8);
      expect(signalTextSegment(segs, 1), '<al>');
      expect(signalTextSegment(segs, 2), '<cn> · <mk>');
      expect(signalTextSegment(segs, 3), 'Servis lewat <od> hari');
      expect(signalTextSegment(segs, 4), 'servis tiap <cad> bln');
      expect(signalTextSegment(segs, 5), 'Jadwalkan');
      expect(signalTextSegment(segs, 6), 'Semua unit terawat');
      expect(signalTextSegment(segs, 7), 'Cari unit');
      expect(signalTextSegment(segs, 8), 'Aset Perlu Servis');
    });

    test('config B statusMap parses; empty gaps/marker means no timeline', () {
      final List<SignalStatusEntry> e = parseSignalStatusMap(
          'jadwal${square}Jadwal servis${square}warn'
          '${star}perhatian${square}Perlu perhatian${square}warn');
      expect(e.length, 2);
      expect(e[0].label, 'Jadwal servis');
      // gapsField:"" and markerField:"" -> nothing to parse -> timeline off.
      expect(parseSignalGaps(null), isEmpty);
      expect(parseSignalGaps(''), isEmpty);
    });
  });

  // ── computeSignalDaysSince (REV2) ─────────────────────────────────────

  group('computeSignalDaysSince', () {
    // Fixed nowMs for deterministic tests: 2026-08-06T00:00:00.000Z
    final int nowMs = DateTime.utc(2026, 8, 6).millisecondsSinceEpoch;

    test('valid int epoch returns days since', () {
      final int lo = nowMs - (24 * 86400000);
      expect(computeSignalDaysSince(lo, nowMs), 24);
    });

    test('string epoch is coerced (CF typing inconsistency)', () {
      final int lo = nowMs - (7 * 86400000);
      expect(computeSignalDaysSince(lo.toString(), nowMs), 7);
    });

    test('double epoch is handled', () {
      final double lo = (nowMs - (3 * 86400000)).toDouble();
      expect(computeSignalDaysSince(lo, nowMs), 3);
    });

    test('same-day epoch returns 0', () {
      expect(computeSignalDaysSince(nowMs, nowMs), 0);
    });

    test('null returns -1 (skip)', () {
      expect(computeSignalDaysSince(null, nowMs), -1);
    });

    test('empty string returns -1', () {
      expect(computeSignalDaysSince('', nowMs), -1);
    });

    test('zero returns -1 (bogus epoch)', () {
      expect(computeSignalDaysSince(0, nowMs), -1);
    });

    test('negative returns -1', () {
      expect(computeSignalDaysSince(-100, nowMs), -1);
    });

    test('non-numeric string returns -1', () {
      expect(computeSignalDaysSince('abc', nowMs), -1);
    });
  });

  // ── computeSignalCadenceDays (REV2) ───────────────────────────────────

  group('computeSignalCadenceDays', () {
    test('int cadence in hari returns as-is', () {
      expect(computeSignalCadenceDays(7, 'hari'), 7);
    });

    test('string cadence is coerced (CF typing)', () {
      expect(computeSignalCadenceDays('14', 'hari'), 14);
    });

    test('bulan multiplies by 30', () {
      expect(computeSignalCadenceDays(2, 'bulan'), 60);
    });

    test('empty unit defaults to hari (no multiplication)', () {
      // The renderer defaults empty cadenceUnit to hari before calling.
      expect(computeSignalCadenceDays(7, ''), 7);
    });

    test('null returns -1 (skip)', () {
      expect(computeSignalCadenceDays(null, 'hari'), -1);
    });

    test('empty string returns -1', () {
      expect(computeSignalCadenceDays('', 'hari'), -1);
    });

    test('zero returns -1 (broken cadence)', () {
      expect(computeSignalCadenceDays(0, 'hari'), -1);
    });

    test('negative returns -1', () {
      expect(computeSignalCadenceDays(-5, 'hari'), -1);
    });

    test('non-numeric returns -1', () {
      expect(computeSignalCadenceDays('abc', 'hari'), -1);
    });
  });

  // ── computeSignalTier (REV2) ──────────────────────────────────────────

  group('computeSignalTier', () {
    // cadDays=10, attFraction=0.8, dormantMult=3.0
    // fresh: ds<=8, approaching: 8<ds<=10, overdue: 10<ds<=30, dormant: ds>30

    test('fresh: ds at boundary (ds == cadDays * attFraction)', () {
      expect(computeSignalTier(8, 10, 0.8, 3.0), 'fresh');
    });

    test('fresh: ds = 0 (just ordered)', () {
      expect(computeSignalTier(0, 10, 0.8, 3.0), 'fresh');
    });

    test('approaching: ds just above fresh boundary', () {
      expect(computeSignalTier(9, 10, 0.8, 3.0), 'approaching');
    });

    test('approaching: ds at cadDays boundary', () {
      expect(computeSignalTier(10, 10, 0.8, 3.0), 'approaching');
    });

    test('overdue: ds just above cadDays', () {
      expect(computeSignalTier(11, 10, 0.8, 3.0), 'overdue');
    });

    test('overdue: ds at dormant boundary (ds == cadDays * dormantMult)', () {
      expect(computeSignalTier(30, 10, 0.8, 3.0), 'overdue');
    });

    test('dormant: ds above dormant boundary', () {
      expect(computeSignalTier(31, 10, 0.8, 3.0), 'dormant');
    });

    test('bulan cadence with custom thresholds', () {
      // cadDays=60 (2 bulan), attFraction=0.5, dormantMult=2.0
      // fresh: ds<=30, approaching: 30<ds<=60, overdue: 60<ds<=120, dormant: ds>120
      expect(computeSignalTier(30, 60, 0.5, 2.0), 'fresh');
      expect(computeSignalTier(31, 60, 0.5, 2.0), 'approaching');
      expect(computeSignalTier(60, 60, 0.5, 2.0), 'approaching');
      expect(computeSignalTier(61, 60, 0.5, 2.0), 'overdue');
      expect(computeSignalTier(120, 60, 0.5, 2.0), 'overdue');
      expect(computeSignalTier(121, 60, 0.5, 2.0), 'dormant');
    });
  });

  // ── REV2 acceptance — aging config end-to-end ─────────────────────────

  group('REV2 acceptance — aging compute', () {
    test('config A (Reorder galon) aging pipeline', () {
      // lo = 24 days ago, cad = 7 (hari), defaults
      final int nowMs = DateTime.utc(2026, 8, 6).millisecondsSinceEpoch;
      final int lo = nowMs - (24 * 86400000);
      final int ds = computeSignalDaysSince(lo, nowMs);
      expect(ds, 24);
      final num cadDays = computeSignalCadenceDays(7, 'hari');
      expect(cadDays, 7);
      final String st = computeSignalTier(ds, cadDays, 0.8, 3.0);
      // 24 > 7*3.0=21 -> dormant
      expect(st, 'dormant');
    });

    test('config B (Service AC) bulan cadence', () {
      final int nowMs = DateTime.utc(2026, 8, 6).millisecondsSinceEpoch;
      final int lo = nowMs - (45 * 86400000);
      final int ds = computeSignalDaysSince(lo, nowMs);
      expect(ds, 45);
      // cadence = 2 bulan = 60 days
      final num cadDays = computeSignalCadenceDays(2, 'bulan');
      expect(cadDays, 60);
      final String st = computeSignalTier(ds, cadDays, 0.8, 3.0);
      // 45 <= 60*0.8=48 -> fresh
      expect(st, 'fresh');
    });

    test('statusMap visibility filter hides fresh tier', () {
      // Only overdue and dormant in statusMap -> fresh/approaching hidden
      final List<SignalStatusEntry> entries = parseSignalStatusMap(
          'overdue${square}Telat order${square}warn'
          '${star}dormant${square}Lama menghilang${square}warn');
      expect(lookupSignalStatus(entries, 'fresh'), isNull);
      expect(lookupSignalStatus(entries, 'approaching'), isNull);
      expect(lookupSignalStatus(entries, 'overdue')?.label, 'Telat order');
      expect(lookupSignalStatus(entries, 'dormant')?.label, 'Lama menghilang');
    });
  });
}
