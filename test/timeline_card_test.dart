// TIMELINE_CARD (slug: timeline-card). Covers all eight spec section 8 cases.
//
// Layer 1 — PURE: parsers, row-slot auto-hide, day grouping and chip inference
//   are pure functions in timeline_card_support.dart and take an explicit `now`,
//   so every rule is exercised deterministically without a pump.
// Layer 2 — PUMP: the widget's wiring — which list feeds the chip, where the
//   separator lands, that `limit` cuts what is RENDERED, that `moreRoute` gates
//   the link. A pure test asserts a composition the test file itself wrote and
//   stays green against a widget that composes the same helpers differently.
//
// Real symbols only. Nothing under test is re-implemented in this file.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'; // mapTableContent
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/timeline_card.dart';
import 'package:otonomiq/widget/timeline_card_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart'; // DevToolsStore

// Framing glyphs as escapes — never paste the raw character.
const String kD = '\u{25C6}'; // ◆ config slot separator
const String kSq = '\u{25FC}'; // ◼ field separator inside an entry
const String kHollow = '\u{2B58}'; // ⭘ entry separator

const String kText = 'Riwayat Absensi${kD}Lihat semua${kD}HARI INI'
    '${kD}Belum Absen${kD}Belum ada riwayat absensi';
const String kDotMap = 'clock-in${kSq}warn${kHollow}clock-out${kSq}info';
const String kChipMap = 'clock-in${kSq}Sedang Bekerja${kSq}info'
    '${kHollow}clock-out${kSq}Sudah Clock Out${kSq}muted';

/// Local noon [daysAgo] days back — stable inside one test run.
int noon(int daysAgo, {int hour = 12}) {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day - daysAgo, hour).millisecondsSinceEpoch;
}

Map<String, dynamic> ev(int ms, String ty, String label, String place,
        {String? acc}) =>
    <String, dynamic>{
      't': ms,
      'ty': ty,
      'd': label,
      'i': place,
      if (acc != null) 'acc': acc,
    };

void main() {
  // ── Layer 1: pure ────────────────────────────────────────────────────

  group('parseDotMap', () {
    test('parses value◼tier entries split on ⭘', () {
      final Map<String, String> m = parseDotMap(kDotMap);
      expect(m['clock-in'], 'warn');
      expect(m['clock-out'], 'info');
      expect(m.length, 2);
    });

    test('empty / sentinel input yields an empty map', () {
      expect(parseDotMap(''), isEmpty);
      expect(parseDotMap('   '), isEmpty);
    });

    test('an entry with no ◼ is SKIPPED, never given a colour', () {
      // Fail-closed: a malformed entry means "no opinion", not "green".
      final Map<String, String> m =
          parseDotMap('broken${kHollow}clock-out${kSq}info');
      expect(m.containsKey('broken'), isFalse);
      expect(m['clock-out'], 'info');
    });

    test('tier is lower-cased and a third ◼ segment is ignored', () {
      expect(parseDotMap('a${kSq}WARN${kSq}junk')['a'], 'warn');
    });
  });

  group('parseChipMap', () {
    test('parses value◼Label◼tier and PRESERVES order', () {
      final List<ChipEntry> e = parseChipMap(kChipMap);
      expect(e.length, 2);
      expect(e[0].value, 'clock-in');
      expect(e[0].label, 'Sedang Bekerja');
      expect(e[0].tier, 'info');
      expect(e[1].value, 'clock-out');
      expect(e[1].label, 'Sudah Clock Out');
      expect(e[1].tier, 'muted');
    });

    test('missing tier defaults to info; missing label falls back to value', () {
      final List<ChipEntry> e = parseChipMap('mulai${kSq}Dalam Perjalanan'
          '${kHollow}selesai');
      expect(e[0].tier, 'info');
      expect(e[1].label, 'selesai');
      expect(e[1].tier, 'info');
    });

    test('empty input yields an empty list', () {
      expect(parseChipMap(''), isEmpty);
    });
  });

  group('timeFieldOf', () {
    test('takes the first <field> token of slot 0', () {
      expect(timeFieldOf(<String>['<t>', '<d>', '<i>', 'GPS ±<acc> m']), 't');
    });

    test('a slot 0 with several tokens takes the FIRST', () {
      expect(timeFieldOf(<String>['<t> <et>', '<d>']), 't');
    });

    test('no token / no row yields empty, never a throw', () {
      expect(timeFieldOf(<String>['13:05', '<d>']), '');
      expect(timeFieldOf(const <String>[]), '');
    });
  });

  group('docEpochMs', () {
    test('accepts int and String epochs (Firestore hands back both)', () {
      expect(docEpochMs(<String, dynamic>{'t': 1756600000000}, 't'),
          1756600000000);
      expect(docEpochMs(<String, dynamic>{'t': '1756600000000'}, 't'),
          1756600000000);
    });

    test('missing key, unparseable value or blank field yields 0', () {
      expect(docEpochMs(<String, dynamic>{}, 't'), 0);
      expect(docEpochMs(<String, dynamic>{'t': 'abc'}, 't'), 0);
      expect(docEpochMs(<String, dynamic>{'t': 1}, ''), 0);
    });
  });

  group('resolveRowSlot — spec section 3 auto-hide', () {
    const List<String> slots = <String>[
      '<t>',
      '<d>',
      '<i>, <lq>, <ln>',
      'GPS ±<acc> m',
    ];

    test('case 6: a doc without `acc` renders NOTHING for the GPS slot', () {
      // Catches: substituting a blank token, which would ship "GPS ± m".
      expect(resolveRowSlot(slots, 3, ev(noon(0), 'clock-in', 'CLOCK IN', 'BSD')),
          '');
    });

    test('a doc WITH `acc` renders the whole literal line', () {
      expect(
        resolveRowSlot(
            slots, 3, ev(noon(0), 'clock-in', 'CLOCK IN', 'BSD', acc: '8')),
        'GPS ±8 m',
      );
    });

    test('ANY empty token blanks the whole slot, not just that token', () {
      // slot 2 has three tokens; only <i> is present.
      expect(
        resolveRowSlot(slots, 2, <String, dynamic>{'i': 'Sampora'}),
        '',
      );
      expect(
        resolveRowSlot(slots, 2, <String, dynamic>{
          'i': 'Sampora',
          'lq': 'Cisauk',
          'ln': 'Banten',
        }),
        'Sampora, Cisauk, Banten',
      );
    });

    test('an out-of-range slot index yields empty, never a RangeError', () {
      // Convention 3: a lean tenant `row` with only 2 slots must not crash.
      expect(resolveRowSlot(<String>['<t>', '<d>'], 3, <String, dynamic>{}), '');
    });

    test('integer 0 counts as PRESENT', () {
      expect(
        resolveRowSlot(<String>['<t>', 'n=<n>'], 1, <String, dynamic>{'n': 0}),
        'n=0',
      );
    });
  });

  group('day grouping', () {
    test('dayKeyOf is zero-padded and empty for a non-positive epoch', () {
      expect(dayKeyOf(0), '');
      expect(dayKeyOf(-5), '');
      expect(dayKeyOf(DateTime(2026, 8, 3, 9).millisecondsSinceEpoch),
          '2026-08-03');
    });

    test('formatDayLabel is UPPERCASE and empty for a non-positive epoch', () {
      expect(formatDayLabel(0), '');
      final String s =
          formatDayLabel(DateTime(2026, 8, 30, 9).millisecondsSinceEpoch);
      expect(s, s.toUpperCase());
      expect(s, contains('30'));
      expect(s, contains('2026'));
    });

    test('isTodayEpoch compares the LOCAL calendar day', () {
      final DateTime now = DateTime(2026, 8, 31, 6);
      expect(isTodayEpoch(DateTime(2026, 8, 31, 23, 59).millisecondsSinceEpoch,
          now), isTrue);
      expect(isTodayEpoch(DateTime(2026, 8, 30, 22).millisecondsSinceEpoch, now),
          isFalse);
      expect(isTodayEpoch(0, now), isFalse);
    });

    test('case 1: three events on one day form ONE group with the prefix', () {
      final DateTime now = DateTime(2026, 8, 31, 18);
      final List<TimelineDayGroup> g = groupDocsByDay(
        <Map<String, dynamic>>[
          ev(DateTime(2026, 8, 31, 17).millisecondsSinceEpoch, 'clock-out', 'A',
              'x'),
          ev(DateTime(2026, 8, 31, 12).millisecondsSinceEpoch, 'clock-in', 'B',
              'x'),
          ev(DateTime(2026, 8, 31, 8).millisecondsSinceEpoch, 'clock-in', 'C',
              'x'),
        ],
        't',
        'HARI INI',
        now,
      );
      expect(g.length, 1);
      expect(g[0].docs.length, 3);
      expect(g[0].label, startsWith('HARI INI \u{00B7} '));
      expect(g[0].label, contains('31'));
    });

    test('case 2: events crossing midnight produce TWO groups, the older '
        'labelled with a plain date', () {
      final DateTime now = DateTime(2026, 8, 31, 18);
      final List<TimelineDayGroup> g = groupDocsByDay(
        <Map<String, dynamic>>[
          ev(DateTime(2026, 8, 31, 8).millisecondsSinceEpoch, 'clock-in', 'A',
              'x'),
          ev(DateTime(2026, 8, 30, 22).millisecondsSinceEpoch, 'clock-out', 'B',
              'x'),
        ],
        't',
        'HARI INI',
        now,
      );
      expect(g.length, 2);
      expect(g[0].label, contains('HARI INI'));
      expect(g[1].label, isNot(contains('HARI INI')));
      expect(g[1].label, contains('30'));
    });

    test('a blank today prefix leaves the plain date', () {
      final DateTime now = DateTime(2026, 8, 31, 18);
      final List<TimelineDayGroup> g = groupDocsByDay(
        <Map<String, dynamic>>[
          ev(DateTime(2026, 8, 31, 8).millisecondsSinceEpoch, 'clock-in', 'A',
              'x'),
        ],
        't',
        '',
        now,
      );
      expect(g[0].label, isNot(contains('\u{00B7}')));
      expect(g[0].label, contains('31'));
    });

    test('epoch 0 rows form a headerless group (no separator is emitted)', () {
      final List<TimelineDayGroup> g = groupDocsByDay(
        <Map<String, dynamic>>[<String, dynamic>{'d': 'no time'}],
        't',
        'HARI INI',
        DateTime(2026, 8, 31),
      );
      expect(g.length, 1);
      expect(g[0].label, '');
    });
  });

  group('inferChip — spec section 4', () {
    final List<ChipEntry> map = parseChipMap(kChipMap);
    final DateTime now = DateTime(2026, 8, 31, 6);

    TimelineChip run(List<Map<String, dynamic>> docs) => inferChip(
          sortedDocs: docs,
          chipField: 'ty',
          chipMap: map,
          timeField: 't',
          emptyLabel: 'Belum Absen',
          now: now,
        );

    test('case 3: clock-in at 22:00 YESTERDAY still reads "Sedang Bekerja"', () {
      // The night-shift rule. Catches: adding a date condition to entry 0.
      final TimelineChip c = run(<Map<String, dynamic>>[
        ev(DateTime(2026, 8, 30, 22).millisecondsSinceEpoch, 'clock-in', 'A',
            'x'),
      ]);
      expect(c.label, 'Sedang Bekerja');
      expect(c.tier, 'info');
    });

    test('case 4: clock-out yesterday, nothing today -> "Belum Absen"', () {
      // Catches: dropping the today-condition on the terminal entries.
      final TimelineChip c = run(<Map<String, dynamic>>[
        ev(DateTime(2026, 8, 30, 17).millisecondsSinceEpoch, 'clock-out', 'A',
            'x'),
      ]);
      expect(c.label, 'Belum Absen');
      expect(c.tier, 'muted');
    });

    test('clock-out TODAY -> "Sudah Clock Out"', () {
      final TimelineChip c = run(<Map<String, dynamic>>[
        ev(DateTime(2026, 8, 31, 5).millisecondsSinceEpoch, 'clock-out', 'A',
            'x'),
      ]);
      expect(c.label, 'Sudah Clock Out');
      expect(c.tier, 'muted');
    });

    test('case 5: zero events -> "Belum Absen"', () {
      expect(run(const <Map<String, dynamic>>[]).label, 'Belum Absen');
    });

    test('only the TOP row decides', () {
      final TimelineChip c = run(<Map<String, dynamic>>[
        ev(DateTime(2026, 8, 31, 5).millisecondsSinceEpoch, 'clock-in', 'A',
            'x'),
        ev(DateTime(2026, 8, 30, 17).millisecondsSinceEpoch, 'clock-out', 'B',
            'x'),
      ]);
      expect(c.label, 'Sedang Bekerja');
    });

    test('an unmapped value, a blank chipField and an empty chipMap all fall '
        'through to the empty label', () {
      expect(
        run(<Map<String, dynamic>>[
          ev(DateTime(2026, 8, 31, 5).millisecondsSinceEpoch, 'break', 'A', 'x'),
        ]).label,
        'Belum Absen',
      );
      expect(
        inferChip(
          sortedDocs: <Map<String, dynamic>>[
            ev(DateTime(2026, 8, 31, 5).millisecondsSinceEpoch, 'clock-in', 'A',
                'x'),
          ],
          chipField: '',
          chipMap: map,
          timeField: 't',
          emptyLabel: 'Belum Absen',
          now: now,
        ).label,
        'Belum Absen',
      );
      expect(
        inferChip(
          sortedDocs: <Map<String, dynamic>>[
            ev(DateTime(2026, 8, 31, 5).millisecondsSinceEpoch, 'clock-in', 'A',
                'x'),
          ],
          chipField: 'ty',
          chipMap: const <ChipEntry>[],
          timeField: 't',
          emptyLabel: 'Belum Absen',
          now: now,
        ).label,
        'Belum Absen',
      );
    });

    test('the rule is GENERIC over chipMap values, not tied to clock-in/out',
        () {
      // Catches: hardcoding the literal 'clock-out' as the today-gated value.
      final List<ChipEntry> trip = parseChipMap(
          'mulai${kSq}Dalam Perjalanan${kSq}info'
          '${kHollow}selesai${kSq}Selesai${kSq}ok');
      TimelineChip go(List<Map<String, dynamic>> d) => inferChip(
            sortedDocs: d,
            chipField: 'ty',
            chipMap: trip,
            timeField: 't',
            emptyLabel: 'Belum Jalan',
            now: now,
          );
      expect(
        go(<Map<String, dynamic>>[
          ev(DateTime(2026, 8, 30, 22).millisecondsSinceEpoch, 'mulai', 'A',
              'x'),
        ]).label,
        'Dalam Perjalanan', // entry 0 -> no date condition
      );
      expect(
        go(<Map<String, dynamic>>[
          ev(DateTime(2026, 8, 30, 22).millisecondsSinceEpoch, 'selesai', 'A',
              'x'),
        ]).label,
        'Belum Jalan', // terminal entry, not today
      );
    });
  });

  // ── Layer 2: pump ────────────────────────────────────────────────────

  group('TimelineCard wiring (pump)', () {
    setUpAll(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    tearDown(() => mapTableContent.remove(''));

    Map<String, dynamic> comp({
      Object? limit,
      String moreRoute = '',
      String groupByDay = 'TRUE',
      String text = kText,
    }) =>
        <String, dynamic>{
          'type': 'TIMELINE_CARD',
          'vidtable': '20342033315492',
          // `table` omitted on purpose — see the harness note in this file's
          // header: no table => no subscription => no Firebase.
          'row': '<t>$kD<d>$kD<i>${kD}GPS ±<acc> m',
          'dotMap': kDotMap,
          'chipField': 'ty',
          'chipMap': kChipMap,
          'groupByDay': groupByDay,
          'sortField': 't',
          'sortDir': 'desc',
          'text': text,
          'moreRoute': moreRoute,
          if (limit != null) 'limit': limit,
        };

    Widget wrap(Map<String, dynamic> component, String scrName) => MaterialApp(
          home: Scaffold(
            // SingleChildScrollView mirrors main_page.dart, so a tall fixture
            // cannot raise a RenderFlex overflow. The widget still uses a plain
            // Column, so every row is INFLATED and findsNothing is sound.
            body: SingleChildScrollView(
              child: TimelineCard(
                component: component,
                scrName: scrName,
                lPad: 0,
                tPad: 0,
                rPad: 0,
                bPad: 0,
              ),
            ),
          ),
        );

    testWidgets('case 1: three events today -> ONE day group, chip from the top '
        'row', (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD', acc: '8'),
        ev(noon(0, hour: 12), 'clock-out', 'ISTIRAHAT', 'BSD', acc: '9'),
        ev(noon(0, hour: 17), 'clock-in', 'MASUK LAGI', 'BSD', acc: '7'),
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case1'));
      await tester.pumpAndSettle();

      // Fixture sanity first — otherwise every assertion below could be green
      // on a card that rendered nothing at all.
      expect(find.text('17:00'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);

      // Exactly one day separator, and it carries the config prefix.
      expect(find.byKey(const ValueKey<String>('tlcard-day-0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('tlcard-day-1')), findsNothing);
      expect(find.textContaining('HARI INI'), findsOneWidget);

      // Chip comes from the NEWEST row (17:00, clock-in).
      expect(find.text('Sedang Bekerja'), findsOneWidget);
      expect(find.text('Belum Absen'), findsNothing);
    });

    testWidgets('case 2: events crossing midnight -> a SECOND day separator',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD', acc: '8'),
        ev(noon(1, hour: 22), 'clock-out', 'CLOCK OUT', 'BSD', acc: '9'),
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case2'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('tlcard-day-0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('tlcard-day-1')), findsOneWidget);
      expect(find.textContaining('HARI INI'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
    });

    testWidgets('groupByDay FALSE -> a flat timeline with NO separators',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD'),
        ev(noon(1, hour: 22), 'clock-out', 'CLOCK OUT', 'BSD'),
      ];
      await tester
          .pumpWidget(wrap(comp(groupByDay: 'FALSE'), 'tlc_flat'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('tlcard-day-0')), findsNothing);
      expect(find.textContaining('HARI INI'), findsNothing);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
    });

    testWidgets('case 3: clock-in last night -> chip "Sedang Bekerja"',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(1, hour: 22), 'clock-in', 'CLOCK IN', 'BSD'),
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case3'));
      await tester.pumpAndSettle();
      expect(find.text('Sedang Bekerja'), findsOneWidget);
      expect(find.text('Belum Absen'), findsNothing);
    });

    testWidgets('case 4: clock-out yesterday -> chip "Belum Absen"',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(1, hour: 17), 'clock-out', 'CLOCK OUT', 'BSD'),
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case4'));
      await tester.pumpAndSettle();
      expect(find.text('Belum Absen'), findsOneWidget);
      expect(find.text('Sudah Clock Out'), findsNothing);
    });

    testWidgets('case 5: zero events -> empty state + "Belum Absen" chip',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[];
      await tester.pumpWidget(wrap(comp(), 'tlc_case5'));
      await tester.pumpAndSettle();
      expect(find.text('Belum ada riwayat absensi'), findsOneWidget);
      expect(find.text('Belum Absen'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('tlcard-day-0')), findsNothing);
    });

    testWidgets('case 6: a doc without `acc` renders no GPS line and no empty '
        'placeholder', (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 12), 'clock-in', 'CLOCK IN', 'BSD', acc: '8'),
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN LAMA', 'BSD'), // no acc
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case6'));
      await tester.pumpAndSettle();

      // Census: with `acc` present the line IS findable, so the findsNothing
      // below cannot pass for the wrong reason.
      expect(find.text('GPS ±8 m'), findsOneWidget);
      // The doc without `acc` contributes NO GPS text at all.
      expect(find.textContaining('GPS ±'), findsOneWidget);
      expect(find.text('GPS ± m'), findsNothing);
      // and the row itself still rendered
      expect(find.text('CLOCK IN LAMA'), findsOneWidget);
    });

    // ── cases 7 and 8: ONE pumpWidget per testWidgets, ON PURPOSE ─────────
    //
    // Widget.canUpdate compares runtimeType and key ONLY. Every pump here
    // builds the same MaterialApp > Scaffold > SingleChildScrollView >
    // TimelineCard, and wrap() passes NO key, so a second pumpWidget in the
    // same tester REUSES the Element: initState -- and therefore _initConfig
    // -- never re-runs, and the second config is silently ignored. `_limit`
    // would stay 3 and `_moreRoute` would stay ''. A single test with two or
    // three pumpWidget calls FAILS on its positive assertions and passes its
    // findsNothing assertions for the WRONG reason.
    //
    // Same rule, same reasoning, as test/list_card_limit_test.dart:329-333,
    // which splits its own moreRoute scenario into lcl_more_a/b/c.

    List<Map<String, dynamic>> fiveRows() => <Map<String, dynamic>>[
          for (int h = 8; h <= 12; h++)
            ev(noon(0, hour: h), 'clock-in', 'BARIS-$h', 'BSD'),
        ];

    testWidgets('case 7a: limit 3 caps the RENDERED rows',
        (WidgetTester tester) async {
      mapTableContent[''] = fiveRows();
      await tester.pumpWidget(wrap(comp(limit: 3), 'tlc_case7a'));
      await tester.pumpAndSettle();
      // Census first: the three survivors must actually be on screen, or the
      // two findsNothing below would be green on a card that rendered nothing
      // at all. sortDir desc => 12, 11, 10 survive; 9 and 8 are cut.
      expect(find.text('BARIS-12'), findsOneWidget);
      expect(find.text('BARIS-11'), findsOneWidget);
      expect(find.text('BARIS-10'), findsOneWidget);
      expect(find.text('BARIS-9'), findsNothing);
      expect(find.text('BARIS-8'), findsNothing);
    });

    testWidgets('case 7b: limit 0 renders every row',
        (WidgetTester tester) async {
      // The other half of spec case 7, in its OWN testWidgets — see the note
      // above. Catches: a widget that ignores `limit` entirely, against which
      // 7a's findsNothing assertions alone would be no evidence.
      mapTableContent[''] = fiveRows();
      await tester.pumpWidget(wrap(comp(limit: 0), 'tlc_case7b'));
      await tester.pumpAndSettle();
      expect(find.text('BARIS-12'), findsOneWidget);
      expect(find.text('BARIS-9'), findsOneWidget);
      expect(find.text('BARIS-8'), findsOneWidget);
    });

    testWidgets('case 8a: a label with NO moreRoute renders no link',
        (WidgetTester tester) async {
      // Segment 1 of `text` IS 'Lihat semua', but moreRoute is '' -> no link.
      // Catches: dropping the `&& _moreRoute.isNotEmpty` half of the guard,
      // which would ship a link whose tap goes nowhere.
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD'),
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case8a'));
      await tester.pumpAndSettle();
      expect(find.text('Riwayat Absensi'), findsOneWidget); // fixture sanity
      expect(find.text('Lihat semua'), findsNothing);
    });

    testWidgets('case 8b: a moreRoute with NO label renders no link',
        (WidgetTester tester) async {
      // Catches: dropping the `moreLabel.isNotEmpty` half, which would ship an
      // invisible / empty-labelled TextButton.
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD'),
      ];
      await tester.pumpWidget(wrap(
        comp(
          moreRoute: 'someRoute',
          // segment 1 (the link label) is EMPTY in this `text`.
          text: 'Riwayat Absensi$kD$kD'
              'HARI INI${kD}Belum Absen${kD}Belum ada riwayat',
        ),
        'tlc_case8b',
      ));
      await tester.pumpAndSettle();
      expect(find.text('Riwayat Absensi'), findsOneWidget); // fixture sanity
      expect(find.text('Lihat semua'), findsNothing);
    });

    testWidgets('case 8c: label + moreRoute renders the link',
        (WidgetTester tester) async {
      // The positive half. Without it, 8a and 8b would both stay green on a
      // widget that never renders a link under any config.
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD'),
      ];
      await tester
          .pumpWidget(wrap(comp(moreRoute: 'someRoute'), 'tlc_case8c'));
      await tester.pumpAndSettle();
      expect(find.text('Lihat semua'), findsOneWidget);
    });

    // ── redesign: the chip has ONE home, and it moves ─────────────────────
    //
    // The chip is drawn on the first day separator when one exists, and in the
    // header otherwise. Both halves are asserted because either alone would
    // stay green on a widget that always picks the same spot — and a widget
    // that drew it in BOTH would make every `findsOneWidget` above fail.

    testWidgets('case 9a: grouped -> the chip rides the FIRST day separator',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD'),
        ev(noon(1, hour: 22), 'clock-out', 'CLOCK OUT', 'BSD'),
      ];
      await tester.pumpWidget(wrap(comp(), 'tlc_case9a'));
      await tester.pumpAndSettle();

      expect(find.text('Sedang Bekerja'), findsOneWidget); // exactly one home
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('tlcard-day-0')),
          matching: find.text('Sedang Bekerja'),
        ),
        findsOneWidget,
      );
      // ...and NOT on the second separator.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('tlcard-day-1')),
          matching: find.text('Sedang Bekerja'),
        ),
        findsNothing,
      );
    });

    testWidgets('case 9b: groupByDay FALSE -> the chip falls back to the header',
        (WidgetTester tester) async {
      // One pumpWidget per testWidgets: Widget.canUpdate would reuse the
      // Element and silently ignore this second config. See the note above 7a.
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 8), 'clock-in', 'CLOCK IN', 'BSD'),
      ];
      await tester.pumpWidget(wrap(comp(groupByDay: 'FALSE'), 'tlc_case9b'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('tlcard-day-0')), findsNothing);
      expect(find.text('Sedang Bekerja'), findsOneWidget);
    });
  });
}
