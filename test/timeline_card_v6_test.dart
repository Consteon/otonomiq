// TIMELINE_CARD `variant: "v6"` — the Vertika v6 log list (`.li`).
//
// Opted in per component, so the two "Riwayat" cards already on home keep the
// card they render today. Two contracts carry the weight here:
//   - v6 draws a chip on EVERY row via `rowChip`, NOT the single summary chip
//     `inferChip` derives from the newest row. Applied per row, inferChip's
//     today-only rule would blank the chip on every historical line — the ones
//     a log exists to show.
//   - the meta icons come from config (`metaIcons`), never from Dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'; // mapTableContent
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/theme_tokens.dart';
import 'package:otonomiq/widget/timeline_card.dart';
import 'package:otonomiq/widget/timeline_card_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

const String kD = '\u{25C6}'; // ◆
const String kSq = '\u{25FC}'; // ◼
const String kHollow = '\u{2B58}'; // ⭘

const String kText = 'Log${kD}Lihat semua${kD}Hari ini'
    '${kD}Belum Absen${kD}Belum ada riwayat';
const String kDotMap = 'clock-in${kSq}warn${kHollow}clock-out${kSq}info';
const String kChipMap = 'clock-in${kSq}Sedang Bekerja${kSq}info'
    '${kHollow}clock-out${kSq}Sudah Clock Out${kSq}muted';

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

/// The classic card's white surface. v6 draws no surface at all.
Finder cardSurface() => find.byWidgetPredicate((Widget w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).color == Colors.white);

/// A row's bottom hairline. The last row draws none.
int rowDividers(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((Container c) {
      final Decoration? d = c.decoration;
      if (d is! BoxDecoration) return false;
      return d.border is Border &&
          (d.border as Border).bottom.color == OtqPalette.v6Border;
    })
    .length;

void main() {
  group('rowChip', () {
    final List<ChipEntry> map = parseChipMap(kChipMap);

    test('looks up the row own value, with no entry-order or date rule', () {
      // Entry 1 is a TERMINAL state: inferChip would only show it for a row
      // dated today. A log row must carry its own label whatever its date.
      final TimelineChip? c =
          rowChip(ev(noon(9), 'clock-out', 'X', 'Y'), 'ty', map);
      expect(c?.label, 'Sudah Clock Out');
      expect(c?.tier, 'muted');
    });

    test('entry 0 resolves the same way', () {
      expect(rowChip(ev(noon(0), 'clock-in', 'X', 'Y'), 'ty', map)?.label,
          'Sedang Bekerja');
    });

    test('null — never an empty-condition label — when there is no chip', () {
      expect(rowChip(ev(noon(0), 'clock-in', 'X', 'Y'), '', map), isNull);
      expect(rowChip(ev(noon(0), 'clock-in', 'X', 'Y'), 'ty', const []), isNull);
      expect(rowChip(ev(noon(0), 'unknown', 'X', 'Y'), 'ty', map), isNull);
      expect(rowChip(<String, dynamic>{}, 'ty', map), isNull);
    });
  });

  group('TimelineCard v6 (pump)', () {
    setUpAll(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    tearDown(() => mapTableContent.remove(''));

    Map<String, dynamic> comp({
      String variant = 'v6',
      String moreRoute = '',
      String metaIcons = '',
      String text = kText,
      Object? limit,
    }) =>
        <String, dynamic>{
          'type': 'TIMELINE_CARD',
          'vidtable': '20342033315492',
          // `table` omitted: no table => no subscription => no Firebase.
          'row': '<t>$kD<d>$kD<i>${kD}GPS ±<acc> m',
          'dotMap': kDotMap,
          'chipField': 'ty',
          'chipMap': kChipMap,
          'groupByDay': 'TRUE',
          'sortField': 't',
          'sortDir': 'desc',
          'text': text,
          'moreRoute': moreRoute,
          if (variant.isNotEmpty) 'variant': variant,
          if (metaIcons.isNotEmpty) 'metaIcons': metaIcons,
          if (limit != null) 'limit': limit,
        };

    Widget wrap(Map<String, dynamic> component, String scrName) => MaterialApp(
          theme: ThemeData(primaryColor: const Color(0xFF001A72)),
          home: Scaffold(
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

    void twoDays() {
      mapTableContent[''] = <Map<String, dynamic>>[
        ev(noon(0, hour: 11), 'clock-in', 'Absen Masuk', 'BSD Tech', acc: '52'),
        ev(noon(1, hour: 17), 'clock-out', 'Absen Pulang', 'BSD Tech',
            acc: '9'),
      ];
    }

    testWidgets('v6 drops the card surface; classic keeps it',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_surface'));
      await tester.pumpAndSettle();
      expect(cardSurface(), findsNothing);
    });

    testWidgets('an absent variant still renders the classic card',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(variant: ''), 'cl_surface'));
      await tester.pumpAndSettle();
      expect(cardSurface(), findsWidgets);
    });

    testWidgets('an unrecognised variant renders the classic card',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(variant: 'v7'), 'cl_v7'));
      await tester.pumpAndSettle();
      expect(cardSurface(), findsWidgets);
    });

    // ★ The reason rowChip exists. Under inferChip the yesterday row — a
    // TERMINAL chipMap entry on a non-today date — resolves to the empty
    // condition and its label never renders.
    testWidgets('v6 chips EVERY row, including a terminal state dated earlier',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_chips'));
      await tester.pumpAndSettle();

      expect(find.text('Sedang Bekerja'), findsOneWidget);
      expect(find.text('Sudah Clock Out'), findsOneWidget);
    });

    testWidgets('classic still draws exactly one summary chip',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(variant: ''), 'cl_chips'));
      await tester.pumpAndSettle();

      expect(find.text('Sedang Bekerja'), findsOneWidget);
      expect(find.text('Sudah Clock Out'), findsNothing);
    });

    testWidgets('rows keep their day headings and both slots of meta',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_rows'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hari ini'), findsOneWidget);
      expect(find.text('Absen Masuk'), findsOneWidget);
      expect(find.text('Absen Pulang'), findsOneWidget);
      // Meta is one Text.rich per row, so the slots are not separate Texts.
      expect(find.textContaining('BSD Tech'), findsNWidgets(2));
      expect(find.textContaining('GPS ±52 m'), findsOneWidget);
    });

    testWidgets('the time column is a 44 dp gutter', (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_gutter'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((Widget w) => w is SizedBox && w.width == 44),
        findsNWidgets(2),
      );
    });

    testWidgets('only the LAST row omits its hairline',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_rule'));
      await tester.pumpAndSettle();

      expect(rowDividers(tester), 1); // 2 rows, 1 divider
    });

    testWidgets('metaIcons draws the named icon, and nothing when blank',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(
          wrap(comp(metaIcons: 'location_on${kD}qr_code'), 'v6_icons'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
      expect(find.byIcon(Icons.qr_code), findsNWidgets(2));
      // stringToIconData answers help_outline for anything it does not know, so
      // a blank name must be SKIPPED rather than passed through.
      expect(find.byIcon(Icons.help_outline), findsNothing);
    });

    testWidgets('one icon named, the other slot left bare',
        (WidgetTester tester) async {
      twoDays();
      await tester
          .pumpWidget(wrap(comp(metaIcons: 'location_on'), 'v6_one_icon'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
      expect(find.byType(Icon), findsNWidgets(2)); // nothing on slot 3
    });

    // Documented, not fixed: every stringToIconData caller in this repo shows
    // the same "?" for a name the map does not carry. A visible mark is how a
    // builder finds their typo; silently dropping it would hide the mistake.
    testWidgets('an unknown icon name renders the shared help_outline mark',
        (WidgetTester tester) async {
      twoDays();
      await tester
          .pumpWidget(wrap(comp(metaIcons: 'notAnIcon'), 'v6_bad_icon'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
    });

    testWidgets('no metaIcons means no icons at all',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_noicons'));
      await tester.pumpAndSettle();

      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('the head shows the see-all link only with a moreRoute',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(), 'v6_nolink'));
      await tester.pumpAndSettle();

      expect(find.text('Log'), findsOneWidget);
      expect(find.text('Lihat semua'), findsNothing);
    });

    testWidgets('a moreRoute brings the link back',
        (WidgetTester tester) async {
      twoDays();
      await tester.pumpWidget(wrap(comp(moreRoute: 'anyRoute'), 'v6_link'));
      await tester.pumpAndSettle();

      expect(find.text('Lihat semua'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('limit cuts what is rendered', (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[
        for (int i = 0; i < 5; i++)
          ev(noon(0, hour: 8 + i), 'clock-in', 'Baris $i', 'BSD'),
      ];
      await tester.pumpWidget(wrap(comp(limit: 3), 'v6_limit'));
      await tester.pumpAndSettle();

      expect(find.text('Baris 4'), findsOneWidget); // newest first
      expect(find.text('Baris 1'), findsNothing);
      expect(rowDividers(tester), 2); // 3 rows, 2 dividers
    });

    testWidgets('the empty state is the config label, not a Dart string',
        (WidgetTester tester) async {
      mapTableContent[''] = <Map<String, dynamic>>[];
      await tester.pumpWidget(wrap(comp(), 'v6_empty'));
      await tester.pumpAndSettle();

      expect(find.text('Belum ada riwayat'), findsOneWidget);
      expect(rowDividers(tester), 0);
    });
  });
}
