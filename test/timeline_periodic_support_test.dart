import 'package:flutter_test/flutter_test.dart';
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
}
