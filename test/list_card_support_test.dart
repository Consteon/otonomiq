import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/list_card_support.dart';

void main() {
  // ── parseBadgeMap ─────────────────────────────────────────────────────

  group('parseBadgeMap', () {
    test('parses full 3-segment entries', () {
      final entries = parseBadgeMap(
          'assigned\u{25FC}Menunggu\u{25FC}warn'
          '\u{2605}closed\u{25FC}Selesai\u{25FC}ok');
      expect(entries.length, 2);
      expect(entries[0].value, 'assigned');
      expect(entries[0].label, 'Menunggu');
      expect(entries[0].tier, 'warn');
      expect(entries[1].value, 'closed');
      expect(entries[1].label, 'Selesai');
      expect(entries[1].tier, 'ok');
    });

    test('neutral tier maps to info', () {
      final entries = parseBadgeMap('x\u{25FC}Label\u{25FC}neutral');
      expect(entries.length, 1);
      expect(entries[0].tier, 'info');
    });

    test('missing tier defaults to info', () {
      final entries = parseBadgeMap('x\u{25FC}Label');
      expect(entries.length, 1);
      expect(entries[0].tier, 'info');
    });

    test('empty tier segment defaults to info', () {
      final entries = parseBadgeMap('x\u{25FC}Label\u{25FC}');
      expect(entries.length, 1);
      expect(entries[0].tier, 'info');
    });

    test('missing label defaults to value', () {
      final entries = parseBadgeMap('x');
      // no ◼ in a single entry without ★ means the whole string is one "part"
      // split on ◼ gives ['x'], value='x', label defaults to 'x'
      // BUT this entry has no ◼ at all within the ★-separated part.
      // segs = ['x'], value = 'x', label = 'x' (segs.length > 1 is false)
      expect(entries.length, 1);
      expect(entries[0].value, 'x');
      expect(entries[0].label, 'x');
    });

    test('empty string returns empty list', () {
      expect(parseBadgeMap(''), isEmpty);
      expect(parseBadgeMap('  '), isEmpty);
    });

    test('empty value segment is skipped', () {
      final entries = parseBadgeMap('\u{25FC}Label\u{25FC}ok');
      expect(entries, isEmpty);
    });

    test('single entry without ★', () {
      final entries = parseBadgeMap('done\u{25FC}Done\u{25FC}ok');
      expect(entries.length, 1);
      expect(entries[0].value, 'done');
    });
  });

  // ── parseGroupLabels ──────────────────────────────────────────────────

  group('parseGroupLabels', () {
    test('parses value-Label pairs in order', () {
      final labels = parseGroupLabels(
          'assigned\u{25FC}Perlu Konfirmasi'
          '\u{2605}scheduled\u{25FC}Terjadwal'
          '\u{2605}closed\u{25FC}Selesai');
      expect(labels.length, 3);
      expect(labels[0].value, 'assigned');
      expect(labels[0].label, 'Perlu Konfirmasi');
      expect(labels[1].value, 'scheduled');
      expect(labels[1].label, 'Terjadwal');
      expect(labels[2].value, 'closed');
      expect(labels[2].label, 'Selesai');
    });

    test('no separator: value equals label', () {
      final labels = parseGroupLabels('open');
      expect(labels.length, 1);
      expect(labels[0].value, 'open');
      expect(labels[0].label, 'open');
    });

    test('empty label after separator defaults to value', () {
      final labels = parseGroupLabels('open\u{25FC}');
      expect(labels.length, 1);
      expect(labels[0].label, 'open');
    });

    test('empty value segment is skipped', () {
      final labels = parseGroupLabels('\u{25FC}Label');
      expect(labels, isEmpty);
    });

    test('empty string returns empty list', () {
      expect(parseGroupLabels(''), isEmpty);
    });

    test('preserves order across many entries', () {
      final labels = parseGroupLabels(
          'a\u{25FC}A\u{2605}b\u{25FC}B\u{2605}c\u{25FC}C');
      expect(labels.map((l) => l.value).toList(), ['a', 'b', 'c']);
    });
  });

  // ── parseStatsDefs ────────────────────────────────────────────────────

  group('parseStatsDefs', () {
    test('splits at first separator only (filter contains separator)', () {
      // "On Job◼ast◼present" -> label="On Job", filter="ast◼present"
      final defs = parseStatsDefs('On Job\u{25FC}ast\u{25FC}present');
      expect(defs.length, 1);
      expect(defs[0].label, 'On Job');
      expect(defs[0].filter, 'ast\u{25FC}present');
    });

    test('empty filter after separator = count all', () {
      final defs = parseStatsDefs('Total\u{25FC}');
      expect(defs.length, 1);
      expect(defs[0].label, 'Total');
      expect(defs[0].filter, '');
    });

    test('no separator = label only, empty filter', () {
      final defs = parseStatsDefs('Total');
      expect(defs.length, 1);
      expect(defs[0].label, 'Total');
      expect(defs[0].filter, '');
    });

    test('multiple boxes separated by star', () {
      final defs = parseStatsDefs(
          'Model\u{25FC}'
          '\u{2605}On Job\u{25FC}ast\u{25FC}present'
          '\u{2605}Selisih\u{25FC}ast\u{25FC}awaiting');
      expect(defs.length, 3);
      expect(defs[0].label, 'Model');
      expect(defs[0].filter, '');
      expect(defs[1].label, 'On Job');
      expect(defs[1].filter, 'ast\u{25FC}present');
      expect(defs[2].label, 'Selisih');
      expect(defs[2].filter, 'ast\u{25FC}awaiting');
    });

    test('empty string returns empty list', () {
      expect(parseStatsDefs(''), isEmpty);
    });

    test('empty label is skipped', () {
      final defs = parseStatsDefs('\u{25FC}ast\u{25FC}present');
      expect(defs, isEmpty);
    });
  });

  // ── computeStatsCounts ────────────────────────────────────────────────

  group('computeStatsCounts', () {
    final docs = <Map<String, dynamic>>[
      {'ast': 'present', 'name': 'Alice'},
      {'ast': 'awaiting', 'name': 'Bob'},
      {'ast': 'present', 'name': 'Carol'},
      {'ast': 'closed', 'name': 'Dave'},
    ];

    test('empty filter counts all docs', () {
      final counts =
          computeStatsCounts([const StatsDef('All', '')], docs);
      expect(counts, [4]);
    });

    test('filter counts matching docs', () {
      final counts = computeStatsCounts([
        StatsDef('Present', 'ast\u{25FC}present'),
        StatsDef('Awaiting', 'ast\u{25FC}awaiting'),
      ], docs);
      expect(counts, [2, 1]);
    });

    test('filter with no matches returns 0', () {
      final counts = computeStatsCounts(
          [StatsDef('None', 'ast\u{25FC}unknown')], docs);
      expect(counts, [0]);
    });

    test('empty docs returns all zeros', () {
      final counts = computeStatsCounts(
          [const StatsDef('All', ''), StatsDef('X', 'ast\u{25FC}present')],
          const []);
      expect(counts, [0, 0]);
    });

    test('empty defs returns empty list', () {
      expect(computeStatsCounts(const [], docs), isEmpty);
    });
  });

  // ── lookupBadge ───────────────────────────────────────────────────────

  group('lookupBadge', () {
    final entries = [
      const BadgeEntry('assigned', 'Menunggu', 'warn'),
      const BadgeEntry('closed', 'Selesai', 'info'),
    ];

    test('finds matching entry', () {
      final badge = lookupBadge(entries, 'assigned');
      expect(badge, isNotNull);
      expect(badge!.label, 'Menunggu');
      expect(badge.tier, 'warn');
    });

    test('returns null for unknown value', () {
      expect(lookupBadge(entries, 'unknown'), isNull);
    });

    test('returns null for empty value', () {
      expect(lookupBadge(entries, ''), isNull);
    });

    test('returns null for empty entries list', () {
      expect(lookupBadge(const [], 'assigned'), isNull);
    });

    test('trims value before lookup', () {
      final badge = lookupBadge(entries, '  closed  ');
      expect(badge, isNotNull);
      expect(badge!.label, 'Selesai');
    });
  });

  // ── Spec acceptance fixtures ──────────────────────────────────────────

  group('spec acceptance fixtures', () {
    test('4.2 badgeMap: 5 entries, neutral mapped to info', () {
      // assigned◼Menunggu Konfirmasi◼warn★scheduled◼Terjadwal◼neutral★
      // present◼On Job◼ok★awaiting◼Selisih — Perlu Tindak◼danger★
      // closed◼Selesai◼neutral
      final raw = 'assigned\u{25FC}Menunggu Konfirmasi\u{25FC}warn'
          '\u{2605}scheduled\u{25FC}Terjadwal\u{25FC}neutral'
          '\u{2605}present\u{25FC}On Job\u{25FC}ok'
          '\u{2605}awaiting\u{25FC}Selisih \u{2014} Perlu Tindak\u{25FC}danger'
          '\u{2605}closed\u{25FC}Selesai\u{25FC}neutral';
      final entries = parseBadgeMap(raw);
      expect(entries.length, 5);
      expect(entries[0].tier, 'warn');
      expect(entries[1].tier, 'info'); // neutral -> info
      expect(entries[2].tier, 'ok');
      expect(entries[3].tier, 'danger');
      expect(entries[3].label, 'Selisih \u{2014} Perlu Tindak');
      expect(entries[4].tier, 'info'); // neutral -> info
    });

    test('4.3 groupLabels: 5 sections in config order', () {
      final raw = 'assigned\u{25FC}Perlu Konfirmasi'
          '\u{2605}scheduled\u{25FC}Terjadwal'
          '\u{2605}present\u{25FC}Sedang Berjalan'
          '\u{2605}awaiting\u{25FC}Menunggu Brand'
          '\u{2605}closed\u{25FC}Selesai';
      final labels = parseGroupLabels(raw);
      expect(labels.length, 5);
      expect(labels[0].value, 'assigned');
      expect(labels[0].label, 'Perlu Konfirmasi');
      expect(labels[2].value, 'present');
      expect(labels[2].label, 'Sedang Berjalan');
      expect(labels[4].value, 'closed');
      expect(labels[4].label, 'Selesai');
    });

    test('4.2 stats: 3 boxes with correct filter parse + counts', () {
      final raw = 'Model\u{25FC}'
          '\u{2605}On Job\u{25FC}ast\u{25FC}present'
          '\u{2605}Selisih\u{25FC}ast\u{25FC}awaiting';
      final defs = parseStatsDefs(raw);
      expect(defs.length, 3);
      expect(defs[0].label, 'Model');
      expect(defs[0].filter, ''); // empty -> count all
      expect(defs[1].label, 'On Job');
      expect(defs[1].filter, 'ast\u{25FC}present');
      expect(defs[2].label, 'Selisih');
      expect(defs[2].filter, 'ast\u{25FC}awaiting');

      // Count verification with sample data
      final docs = <Map<String, dynamic>>[
        {'ast': 'assigned', 'mnn': 'Alice'},
        {'ast': 'present', 'mnn': 'Bob'},
        {'ast': 'awaiting', 'mnn': 'Carol'},
        {'ast': 'present', 'mnn': 'Dave'},
        {'ast': 'closed', 'mnn': 'Eve'},
      ];
      final counts = computeStatsCounts(defs, docs);
      expect(counts[0], 5); // Model: count all
      expect(counts[1], 2); // On Job: ast==present
      expect(counts[2], 1); // Selisih: ast==awaiting
    });
  });

  // ── Spec 6 checklist (pure-logic aspects) ─────────────────────────────

  group('spec 6 checklist', () {
    test('6.4: all optional fields empty -> no crash, empty results', () {
      expect(parseBadgeMap(''), isEmpty);
      expect(parseGroupLabels(''), isEmpty);
      expect(parseStatsDefs(''), isEmpty);
      expect(lookupBadge(const [], 'x'), isNull);
      expect(computeStatsCounts(const [], const []), isEmpty);
    });

    test('6.5: lookupBadge for missing value returns null (not crash)', () {
      final entries = [const BadgeEntry('a', 'A', 'ok')];
      expect(lookupBadge(entries, 'nonexistent'), isNull);
    });

    test('6.6: literal routeParams value (no curly token)', () {
      // This test documents that lookupBadge and other parsers handle
      // non-token literal values without issue. The actual routeParams
      // literal handling is tested in rbt_route_params_test.dart.
      final entries = [const BadgeEntry('literal_mode', 'Mode', 'info')];
      expect(lookupBadge(entries, 'literal_mode')?.label, 'Mode');
    });
  });

  // ── Edge cases (sparse data) ──────────────────────────────────────────

  group('sparse data edges', () {
    test('badgeMap with only value (no label, no tier)', () {
      final entries = parseBadgeMap('solo');
      expect(entries.length, 1);
      expect(entries[0].value, 'solo');
      expect(entries[0].label, 'solo'); // defaults to value
      expect(entries[0].tier, 'info'); // defaults
    });

    test('groupLabels: single entry, no star separator', () {
      final labels = parseGroupLabels('active\u{25FC}Aktif');
      expect(labels.length, 1);
      expect(labels[0].value, 'active');
      expect(labels[0].label, 'Aktif');
    });

    test('stats: multi-clause filter (field-value-AND-field-value)', () {
      // "Urgent◼priority◼high⭘status◼open" -> filter is the whole thing
      // after the FIRST ◼, which is "priority◼high⭘status◼open"
      final defs = parseStatsDefs(
          'Urgent\u{25FC}priority\u{25FC}high\u{2B58}status\u{25FC}open');
      expect(defs.length, 1);
      expect(defs[0].label, 'Urgent');
      // filter should be everything after the first ◼
      expect(defs[0].filter,
          'priority\u{25FC}high\u{2B58}status\u{25FC}open');
    });
  });
}
