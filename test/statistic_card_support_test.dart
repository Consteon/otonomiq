import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';

void main() {
  group('parsePeriods', () {
    test('parses label◼ms★... into options', () {
      final p = parsePeriods(
          '24 jam◼86400000★7 hari◼604800000★30 hari◼2592000000');
      expect(p.length, 3);
      expect(p[0].label, '24 jam');
      expect(p[0].ms, 86400000);
      expect(p[2].label, '30 hari');
      expect(p[2].ms, 2592000000);
    });
    test('skips malformed entries and empty input', () {
      expect(parsePeriods(''), isEmpty);
      expect(parsePeriods('oops★7 hari◼604800000').length, 1);
      expect(parsePeriods('bad◼notanumber'), isEmpty);
    });
  });

  group('parseStatSpecs', () {
    test('parses template◆label★... into specs', () {
      final s = parseStatSpecs(
          '{totalVisits}◆Total kunjungan★{noVisitCount}◆Titik tanpa kunjungan★{typedCount}◆Lokasi diketik');
      expect(s.length, 3);
      expect(s[0].template, '{totalVisits}');
      expect(s[0].label, 'Total kunjungan');
      expect(s[2].template, '{typedCount}');
      expect(s[2].label, 'Lokasi diketik');
    });
    test('empty input → empty; missing label → empty label', () {
      expect(parseStatSpecs(''), isEmpty);
      final s = parseStatSpecs('{x}');
      expect(s.length, 1);
      expect(s[0].label, '');
    });
  });

  group('humanizeAgo', () {
    test('menit / jam / hari boundaries', () {
      expect(humanizeAgo(30000), 'Baru saja'); // 30s
      expect(humanizeAgo(30 * 60000), '30 menit lalu');
      expect(humanizeAgo(60 * 60000), '1 jam lalu'); // exactly 1h
      expect(humanizeAgo(8 * 3600000), '8 jam lalu');
      expect(humanizeAgo(23 * 3600000), '23 jam lalu');
      expect(humanizeAgo(24 * 3600000), '1 hari lalu'); // exactly 24h
      expect(humanizeAgo(30 * 3600000), '1 hari lalu');
      expect(humanizeAgo(-1), 'Baru saja');
    });
  });

  group('deriveType', () {
    test('patrol/clean substrings, else uppercase, empty→empty', () {
      expect(deriveType('report-patrol'), 'PATROLI');
      expect(deriveType('report-cleaning'), 'CLEANING');
      expect(deriveType(''), '');
      expect(deriveType('survey'), 'SURVEY');
    });
  });

  group('deriveEvidence', () {
    test('non-empty lq → Bukti kuat, empty → GPS saja', () {
      expect(deriveEvidence('QR123'), 'Bukti kuat');
      expect(deriveEvidence(''), 'GPS saja');
      expect(deriveEvidence('  '), 'GPS saja');
    });
  });

  group('eventsByLn', () {
    test('groups events by ln, skips empty ln', () {
      final g = eventsByLn([
        {'ln': 'Gudang', 't': '100'},
        {'ln': 'Gudang', 't': '200'},
        {'ln': 'Mushola', 't': '50'},
        {'t': '999'}, // no ln → skipped
      ]);
      expect(g['Gudang']!.length, 2);
      expect(g['Mushola']!.length, 1);
      expect(g.containsKey(''), isFalse);
    });
  });

  group('computePointStat', () {
    const now = 1000000000000;
    const stale = 43200000; // 12h
    final windowStart = now - 86400000; // 24h window

    test('no events → danger / Belum pernah', () {
      final r = computePointStat(const [], now, windowStart, stale);
      expect(r.ps, 'danger');
      expect(r.lastAgo, 'Belum pernah');
      expect(r.visits, 0);
      expect(r.hasEvent, isFalse);
      expect(r.type, '');
      expect(r.evidence, '');
      expect(r.lastEpoch, 0);
    });

    test('recent QR visit → ok / Bukti kuat', () {
      final r = computePointStat([
        {'ln': 'A', 't': '${now - 3600000}', 'lq': 'q', 'cn': 'Budi', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.ps, 'ok');
      expect(r.visits, 1);
      expect(r.lastAgo, '1 jam lalu');
      expect(r.lastBy, 'Budi');
      expect(r.type, 'PATROLI');
      expect(r.evidence, 'Bukti kuat');
      expect(r.hasEvent, isTrue);
    });

    test('stale visit (≥12h) → warn even with QR evidence', () {
      final r = computePointStat([
        {'ln': 'A', 't': '${now - 13 * 3600000}', 'lq': 'q', 'cn': 'Agus', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.ps, 'warn');
      expect(r.visits, 1);
      expect(r.lastAgo, '13 jam lalu');
      expect(r.evidence, 'Bukti kuat');
    });

    test('recent but GPS-only (empty lq) → warn / GPS saja', () {
      final r = computePointStat([
        {'ln': 'A', 't': '${now - 3600000}', 'lq': '', 'cn': 'Sari', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.ps, 'warn');
      expect(r.evidence, 'GPS saja');
    });

    test('events only outside window → danger, last-ever still shown', () {
      final r = computePointStat([
        {'ln': 'A', 't': '${now - 30 * 3600000}', 'lq': 'q', 'cn': 'X', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.visits, 0);
      expect(r.ps, 'danger');
      expect(r.lastAgo, '1 hari lalu');
      expect(r.hasEvent, isTrue);
    });

    test('picks latest among many and counts window', () {
      final r = computePointStat([
        {'ln': 'A', 't': '${now - 2 * 3600000}', 'lq': 'q', 'cn': 'New', 'ty': 'report-patrol'},
        {'ln': 'A', 't': '${now - 5 * 3600000}', 'lq': 'q', 'cn': 'Old', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.visits, 2);
      expect(r.lastBy, 'New');
      expect(r.lastEpoch, now - 2 * 3600000);
    });
  });

  group('computeStatsSummary', () {
    const now = 1000000000000;
    final windowStart = now - 86400000;

    test('totalVisits / noVisitCount / typedCount in window', () {
      final points = [
        {'ln': 'A'},
        {'ln': 'B'},
        {'ln': 'C'},
      ];
      final byLn = eventsByLn([
        {'ln': 'A', 't': '${now - 1000}', 'lq': 'q'},
        {'ln': 'A', 't': '${now - 2000}', 'lq': ''}, // typed
        {'ln': 'B', 't': '${now - 30 * 3600000}', 'lq': 'q'}, // outside window
        // C has no events
      ]);
      final s = computeStatsSummary(points, byLn, now, windowStart);
      expect(s.totalVisits, 2); // both A events in window; B's is out
      expect(s.noVisitCount, 2); // B (out of window) and C
      expect(s.typedCount, 1); // A's empty-lq event
    });

    test('non-map point tolerated', () {
      final s = computeStatsSummary(['oops', {'ln': 'A'}],
          eventsByLn([{'ln': 'A', 't': '${now - 1000}', 'lq': 'q'}]),
          now, windowStart);
      expect(s.totalVisits, 1);
      expect(s.noVisitCount, 0);
    });
  });

  group('resolveScreenTxTokens', () {
    test('replaces {key} from screenTx, leaves unknown literal', () {
      expect(resolveScreenTxTokens('av◼{ccVid}', {'ccVid': '83'}), 'av◼83');
      expect(resolveScreenTxTokens('av◼{ccVid}', const {}), 'av◼{ccVid}');
    });
  });

  group('filterByCharCodeEquality', () {
    final docs = [
      {'av': '83', 'an': 'A Group'},
      {'av': '99', 'an': 'B Group'},
    ];
    test('conditions form filters by av == ccVid', () {
      final r = filterByCharCodeEquality(
          docs, '[[◀av▶◼{ccVid}]]', {'ccVid': '83'});
      expect(r.length, 1);
      expect(r.first['an'], 'A Group');
    });
    test('search form filters by av == ccVid', () {
      final r = filterByCharCodeEquality(docs, 'av◼{ccVid}', {'ccVid': '99'});
      expect(r.length, 1);
      expect(r.first['an'], 'B Group');
    });
    test('empty conditions → unchanged list', () {
      expect(filterByCharCodeEquality(docs, '', const {}).length, 2);
    });
    test('unresolved token → no match (empty)', () {
      expect(filterByCharCodeEquality(docs, 'av◼{ccVid}', const {}), isEmpty);
    });
  });

  group('scopePatrolEvents', () {
    const now = 1000000000000;
    final windowStart = now - 86400000;

    test('filters by ty, av, ln non-empty, and window', () {
      final events = [
        {'ty': 'report-patrol', 'av': '83', 'ln': 'A', 't': '${now - 1000}'},
        {'ty': 'report-patrol', 'av': '83', 'ln': 'B', 't': '${now - 2000}'},
        {'ty': 'report-cleaning', 'av': '83', 'ln': 'C', 't': '${now - 1000}'}, // wrong ty
        {'ty': 'report-patrol', 'av': '99', 'ln': 'D', 't': '${now - 1000}'}, // wrong av
        {'ty': 'report-patrol', 'av': '83', 'ln': '', 't': '${now - 1000}'}, // empty ln
        {'ty': 'report-patrol', 'av': '83', 'ln': 'E', 't': '${now - 90000000}'}, // out of window
      ];
      final r = scopePatrolEvents(events, 'report-patrol', '83', windowStart);
      expect(r.length, 2);
      expect(r[0]['ln'], 'A');
      expect(r[1]['ln'], 'B');
    });

    test('empty avValue returns empty', () {
      final events = [
        {'ty': 'report-patrol', 'av': '83', 'ln': 'A', 't': '${now - 1000}'},
      ];
      expect(scopePatrolEvents(events, 'report-patrol', '', windowStart), isEmpty);
    });

    test('ty match is case-insensitive contains', () {
      final events = [
        {'ty': 'Report-Patrol', 'av': '83', 'ln': 'A', 't': '${now - 1000}'},
      ];
      final r = scopePatrolEvents(events, 'report-patrol', '83', windowStart);
      expect(r.length, 1);
    });
  });

  group('eventsByLnLower', () {
    test('groups by lowercase ln, skips empty ln', () {
      final g = eventsByLnLower([
        {'ln': 'Gudang', 't': '100'},
        {'ln': 'gudang', 't': '200'},
        {'ln': 'GUDANG', 't': '300'},
        {'ln': 'Mushola', 't': '50'},
        {'ln': '', 't': '999'},
      ]);
      expect(g['gudang']!.length, 3);
      expect(g['mushola']!.length, 1);
      expect(g.containsKey(''), isFalse);
    });

    test('preserves original event data including casing', () {
      final g = eventsByLnLower([
        {'ln': 'Gudang A', 't': '100', 'cn': 'Budi'},
      ]);
      expect(g['gudang a']!.first['ln'], 'Gudang A');
      expect(g['gudang a']!.first['cn'], 'Budi');
    });
  });

  group('groupOrphans', () {
    test('extracts orphans not in official set', () {
      final byLnLower = eventsByLnLower([
        {'ln': 'Gudang', 't': '300', 'cn': 'Budi'},
        {'ln': 'gudang', 't': '100', 'cn': 'Agus'},
        {'ln': 'Mushola', 't': '200', 'cn': 'Sari'},
        {'ln': 'Pos Depan', 't': '400', 'cn': 'Rina'},
      ]);
      final officialLower = {'gudang', 'mushola'};
      final orphans = groupOrphans(byLnLower, officialLower);
      expect(orphans.length, 1);
      expect(orphans.first.lnLower, 'pos depan');
      expect(orphans.first.ln, 'Pos Depan'); // latest event casing
      expect(orphans.first.events.length, 1);
    });

    test('collapses N events to 1 entry, picks latest casing', () {
      final byLnLower = eventsByLnLower([
        {'ln': 'gudang b', 't': '100', 'cn': 'Old'},
        {'ln': 'Gudang B', 't': '500', 'cn': 'New'},
        {'ln': 'GUDANG B', 't': '300', 'cn': 'Mid'},
      ]);
      final orphans = groupOrphans(byLnLower, <String>{});
      expect(orphans.length, 1);
      expect(orphans.first.ln, 'Gudang B'); // from t=500, the latest
      expect(orphans.first.events.length, 3);
    });

    test('trailing space makes it a different key (not fuzzy)', () {
      final byLnLower = eventsByLnLower([
        {'ln': 'Gudang', 't': '100'},
        {'ln': 'Gudang ', 't': '200'}, // trailing space
      ]);
      final officialLower = {'gudang'};
      final orphans = groupOrphans(byLnLower, officialLower);
      // "gudang " (with space) != "gudang" -> orphan
      expect(orphans.length, 1);
      expect(orphans.first.lnLower, 'gudang ');
    });

    test('empty byLnLower returns empty', () {
      expect(groupOrphans(const {}, {'a'}), isEmpty);
    });

    test('all events match official -> no orphans', () {
      final byLnLower = eventsByLnLower([
        {'ln': 'Gudang', 't': '100'},
      ]);
      final orphans = groupOrphans(byLnLower, {'gudang'});
      expect(orphans, isEmpty);
    });
  });

  group('computeStatsSummaryMerge', () {
    const now = 1000000000000;

    test('totalVisits = scoped event count, noVisit = official with 0, typedCount = orphan count', () {
      final points = [
        {'ln': 'A'},
        {'ln': 'B'},
        {'ln': 'C'},
      ];
      // Scoped events: 3 events (A has 2, orphan "D" has 1)
      final scoped = [
        {'ln': 'A', 't': '${now - 1000}'},
        {'ln': 'A', 't': '${now - 2000}'},
        {'ln': 'D', 't': '${now - 3000}'},
      ];
      final byLnLower = eventsByLnLower(scoped);
      final typedEntries = groupOrphans(
          byLnLower, {'a', 'b', 'c'});
      final s = computeStatsSummaryMerge(
        points: points,
        typedEntries: typedEntries,
        scopedEvents: scoped,
        byLnLower: byLnLower,
      );
      expect(s.totalVisits, 3); // all 3 scoped events
      expect(s.noVisitCount, 2); // B and C have 0 events
      expect(s.typedCount, 1); // orphan "D"
    });

    test('no events at all -> all points no-visit, 0 typed', () {
      final points = [{'ln': 'A'}, {'ln': 'B'}];
      final s = computeStatsSummaryMerge(
        points: points,
        typedEntries: const [],
        scopedEvents: const [],
        byLnLower: const {},
      );
      expect(s.totalVisits, 0);
      expect(s.noVisitCount, 2);
      expect(s.typedCount, 0);
    });

    test('empty ll (no official points) -> noVisit=0, all events orphan', () {
      final scoped = [
        {'ln': 'X', 't': '${now - 1000}'},
        {'ln': 'Y', 't': '${now - 2000}'},
      ];
      final byLnLower = eventsByLnLower(scoped);
      final typedEntries = groupOrphans(byLnLower, <String>{});
      final s = computeStatsSummaryMerge(
        points: const [],
        typedEntries: typedEntries,
        scopedEvents: scoped,
        byLnLower: byLnLower,
      );
      expect(s.totalVisits, 2);
      expect(s.noVisitCount, 0);
      expect(s.typedCount, 2);
    });
  });

  group('computeTypedPointStat', () {
    const now = 1000000000000;

    test('forces ps=warn and evidence=GPS saja regardless of lq', () {
      final r = computeTypedPointStat([
        {'ln': 'X', 't': '${now - 3600000}', 'lq': 'QR123', 'cn': 'Budi', 'ty': 'report-patrol'},
      ], now);
      expect(r.ps, 'warn');
      expect(r.evidence, 'GPS saja');
      expect(r.visits, 1);
      expect(r.lastBy, 'Budi');
      expect(r.hasEvent, isTrue);
    });

    test('empty events -> warn / GPS saja / 0 visits', () {
      final r = computeTypedPointStat(const [], now);
      expect(r.ps, 'warn');
      expect(r.evidence, 'GPS saja');
      expect(r.visits, 0);
      expect(r.hasEvent, isFalse);
    });

    test('picks latest event for lastBy/lastAgo', () {
      final r = computeTypedPointStat([
        {'ln': 'X', 't': '${now - 5 * 3600000}', 'cn': 'Old', 'ty': 'report-patrol'},
        {'ln': 'X', 't': '${now - 1 * 3600000}', 'cn': 'New', 'ty': 'report-patrol'},
      ], now);
      expect(r.lastBy, 'New');
      expect(r.visits, 2);
      expect(r.lastAgo, '1 jam lalu');
    });
  });

  group('parseChipSpec', () {
    test('segment with ◼ returns ChipSpec', () {
      final c = parseChipSpec('login◼<is>');
      expect(c, isNotNull);
      expect(c!.iconName, 'login');
      expect(c.valueTemplate, '<is>');
    });

    test('segment without ◼ returns null (plain text)', () {
      expect(parseChipSpec('<n>'), isNull);
      expect(parseChipSpec('Hello world'), isNull);
    });

    test('empty icon name returns null', () {
      expect(parseChipSpec('◼<is>'), isNull);
    });

    test('parts beyond index 1 are ignored (forward-compat)', () {
      final c = parseChipSpec('login◼<is>◼{tone}');
      expect(c, isNotNull);
      expect(c!.iconName, 'login');
      expect(c.valueTemplate, '<is>');
    });

    test('encoded ◼ after autheniumDecode becomes real ◼', () {
      // Simulates content that has been through autheniumDecode:
      // '_25FC_' -> '◼'. By the time parseChipSpec sees it, the ◼ is real.
      final c = parseChipSpec('logout◼<os>');
      expect(c, isNotNull);
      expect(c!.iconName, 'logout');
    });

    test('whitespace around icon and template is trimmed', () {
      final c = parseChipSpec('  login ◼ <is> ');
      expect(c, isNotNull);
      expect(c!.iconName, 'login');
      expect(c.valueTemplate, '<is>');
    });

    test('empty segment returns null', () {
      expect(parseChipSpec(''), isNull);
    });
  });

  group('formatTimeShort', () {
    test('HH:MM passes through', () {
      expect(formatTimeShort('06:58'), '06:58');
    });

    test('HH:MM:SS truncates seconds', () {
      expect(formatTimeShort('15:10:29'), '15:10');
    });

    test('datetime string extracts time', () {
      expect(formatTimeShort('10 Jun 2026 15:10:29'), '15:10');
    });

    test('single-digit hour', () {
      expect(formatTimeShort('6:58'), '6:58');
    });

    test('empty value returns em-dash placeholder', () {
      expect(formatTimeShort(''), '—');
      expect(formatTimeShort('   '), '—');
    });

    test('no time pattern returns value as-is', () {
      expect(formatTimeShort('hello'), 'hello');
      expect(formatTimeShort('42'), '42');
    });
  });

  group('chipTone', () {
    test('filled value returns ok', () {
      expect(chipTone('06:58', 'danger'), 'ok');
      expect(chipTone('15:10', 'warn'), 'ok');
    });

    test('empty value inherits card status', () {
      expect(chipTone('', 'danger'), 'danger');
      expect(chipTone('', 'warn'), 'warn');
    });

    test('em-dash placeholder inherits card status', () {
      expect(chipTone('—', 'danger'), 'danger');
      expect(chipTone('—', 'warn'), 'warn');
    });

    test('whitespace-only inherits card status', () {
      expect(chipTone('   ', 'warn'), 'warn');
    });
  });

  group('resolveBadge', () {
    test('resolves template tokens and trims', () {
      final r = resolveBadge('{statusLine}', {}, {'statusLine': 'Belum scan'});
      expect(r, 'Belum scan');
    });

    test('empty result suppresses badge', () {
      final r = resolveBadge('{statusLine}', {}, {'statusLine': ''});
      expect(r, '');
    });

    test('whitespace-only result suppresses badge', () {
      final r = resolveBadge('{statusLine}', {}, {'statusLine': '   '});
      expect(r, '');
    });

    test('empty template suppresses badge', () {
      expect(resolveBadge('', {}, {'statusLine': 'X'}), '');
      expect(resolveBadge('   ', {}, {'statusLine': 'X'}), '');
    });

    test('raw doc tokens resolve too', () {
      final r = resolveBadge('<st>', {'st': 'active'}, {});
      expect(r, 'active');
    });
  });
}
