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
}
