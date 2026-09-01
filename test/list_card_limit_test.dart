// Tests for the LIST_CARD `limit` config key (slug: list-card-limit).
//
// Two layers, because they prove different things.
//
//   1. PURE unit tests (no pump, no binding, no Firebase) for `parseLimit` and
//      `applyLimit`. The parse and the cut both live in pure helpers in
//      list_card_support.dart, so every config shape and every boundary can be
//      exercised directly and exhaustively.
//
//   2. WIDGET-PUMP tests for the widget's own wiring — WHICH list the cut is
//      applied to. That is the half a pure test structurally cannot reach: a
//      pure test asserts a composition the test file itself writes, so it stays
//      green against a widget that composes the same helpers differently. The
//      pump tests pin both binding interview decisions: D2 (header count and
//      stats keep the UNCAPPED total, so the cut must not touch
//      `serverFiltered`) and D1 (the cap is GLOBAL, applied before grouping,
//      not per section).
//
// The pump layer needs no Firebase and no globalInit — see the harness note on
// the `ListCard wiring (pump)` group at the bottom of this file.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'; // autheniumDecode (§2), mapTableContent
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart'; // stripRouteWrapper
import 'package:otonomiq/widget/list_card.dart'; // ListCard (pump layer)
import 'package:otonomiq/widget/list_card_support.dart';
import 'package:otonomiq/widget/panel_card_support.dart'; // groupByField
import 'package:redux_dev_tools/redux_dev_tools.dart'; // DevToolsStore

/// n rows already in display order (the widget sorts before the cut), each
/// carrying a stable id.
List<Map<String, dynamic>> _rows(int n) => [
      for (int i = 0; i < n; i++) <String, dynamic>{'id': 'r$i'}
    ];

void main() {
  // ── parseLimit ────────────────────────────────────────────────────────

  group('parseLimit', () {
    test('absent key (null) is unlimited', () {
      // Catches: the back-compat path breaking — every already-deployed
      // LIST_CARD has no `limit` key and must keep rendering every row.
      expect(parseLimit(null), 0);
    });

    test('plain int is taken as-is', () {
      // Catches: "limit":5 (the spec's written form) not being honoured.
      expect(parseLimit(5), 5);
      expect(parseLimit(1), 1);
      expect(parseLimit(999), 999);
    });

    test('quoted string number parses', () {
      // Catches: a sheet that delivers "5" instead of 5 silently going
      // unlimited. Sheet-sourced JSON is inconsistent about quoting.
      expect(parseLimit('5'), 5);
      expect(parseLimit(' 5 '), 5);
    });

    test('unquoted double (jsonDecode 5.0) truncates to int', () {
      // Catches: the `is num` branch being dropped, which would send a
      // double straight to int.tryParse and yield 0 = unlimited.
      expect(parseLimit(5.0), 5);
      expect(parseLimit(5.9), 5);
    });

    test('zero is unlimited', () {
      // Catches: 0 being treated as "show nothing" instead of "no cap"
      // (spec §1: `0` = current behavior).
      expect(parseLimit(0), 0);
      expect(parseLimit('0'), 0);
    });

    test('negative is unlimited, never a negative take()', () {
      // Catches: a negative reaching Iterable.take(), which throws
      // RangeError — a per-tenant crash from one bad sheet cell.
      expect(parseLimit(-1), 0);
      expect(parseLimit(-3), 0);
      expect(parseLimit('-3'), 0);
      expect(parseLimit(-2.5), 0);
    });

    test('empty / sentinel / junk / bool are unlimited', () {
      // Catches: any non-number config value being coerced into a cap.
      // '--' is the sheet's empty-cell sentinel.
      expect(parseLimit(''), 0);
      expect(parseLimit('   '), 0);
      expect(parseLimit('--'), 0);
      expect(parseLimit('abc'), 0);
      expect(parseLimit(true), 0);
      expect(parseLimit(<String>[]), 0);
    });

    test('quoted double string "5.0" is unlimited (documented edge)', () {
      // Catches: this documented behaviour drifting silently. int.tryParse
      // rejects "5.0"; per spec §1 unparseable = no cap. If this ever needs
      // to be 5, change parseLimit AND docs/widgets/list_card.md together.
      expect(parseLimit('5.0'), 0);
    });
  });

  // ── applyLimit ────────────────────────────────────────────────────────

  group('applyLimit', () {
    test('limit 0 returns the SAME list instance (zero-alloc back-compat)', () {
      // Catches: the no-limit path starting to copy the list. Identity is the
      // strongest possible statement of "byte-identical to today".
      final rows = _rows(3);
      expect(identical(applyLimit(rows, 0), rows), isTrue);
    });

    test('negative limit returns the SAME list instance', () {
      final rows = _rows(3);
      expect(identical(applyLimit(rows, -4), rows), isTrue);
    });

    test('limit larger than the row count returns everything', () {
      // Catches: an off-by-one or an unnecessary copy when N > rows.
      final rows = _rows(3);
      expect(applyLimit(rows, 10).length, 3);
      expect(identical(applyLimit(rows, 10), rows), isTrue);
    });

    test('limit exactly equal to the row count returns everything', () {
      final rows = _rows(5);
      expect(applyLimit(rows, 5).length, 5);
      expect(identical(applyLimit(rows, 5), rows), isTrue);
    });

    test('limit smaller than the row count keeps the FIRST N, in order', () {
      // Catches: taking from the wrong end. _getServerFiltered() sorts before
      // returning, so "first N" is exactly "top N" (spec §1: cut after sort).
      final rows = _rows(10);
      final cut = applyLimit(rows, 3);
      expect(cut.length, 3);
      expect(cut.map((r) => r['id']).toList(), ['r0', 'r1', 'r2']);
    });

    test('limit 1 keeps exactly the top row', () {
      final rows = _rows(10);
      expect(applyLimit(rows, 1).map((r) => r['id']).toList(), ['r0']);
    });

    test('does not mutate the source list', () {
      // Catches: an in-place removeRange-style implementation, which would
      // corrupt serverFiltered and therefore the header count and stats.
      final rows = _rows(10);
      applyLimit(rows, 3);
      expect(rows.length, 10);
    });

    test('empty input stays empty at any limit', () {
      final rows = <Map<String, dynamic>>[];
      expect(applyLimit(rows, 5), isEmpty);
      expect(applyLimit(rows, 0), isEmpty);
    });
  });

  // ── grouped mode: the cap is GLOBAL, not per-group (interview D1) ──────
  //
  // These assert the COMPOSITION the widget performs in build():
  //   applyLimit(...)  ->  _buildGrouped(displayed)  ->  groupByField(docs, …)
  // What IS proved here is that this order yields a global cap and that the
  // obvious per-group mutant fails. That the WIDGET composes them in this
  // order is pinned separately, by the `ListCard wiring (pump)` group below.

  group('limit x grouped mode (global cap)', () {
    // 6 rows in display order: 3x group 'a', then 3x group 'b'.
    List<Map<String, dynamic>> sixRows() => <Map<String, dynamic>>[
          {'id': 'a1', 'g': 'a'},
          {'id': 'a2', 'g': 'a'},
          {'id': 'a3', 'g': 'a'},
          {'id': 'b1', 'g': 'b'},
          {'id': 'b2', 'g': 'b'},
          {'id': 'b3', 'g': 'b'},
        ];

    test('cap inside the first group: the second group is NOT rendered', () {
      // Catches: a per-group cap (which would render both 'a' and 'b').
      final grouped = groupByField(applyLimit(sixRows(), 2), 'g');
      expect(grouped.keys.toList(), ['a']);
      expect(grouped['a']!.length, 2);
      expect(grouped.values.fold<int>(0, (s, v) => s + v.length), 2);
    });

    test('cap straddling the boundary splits 3 + 1, not 4 + 4', () {
      // Catches: the per-group mutant most directly — a per-group cap of 4
      // would give a:3 / b:3 (6 total), a global cap gives a:3 / b:1 (4).
      final grouped = groupByField(applyLimit(sixRows(), 4), 'g');
      expect(grouped['a']!.length, 3);
      expect(grouped['b']!.length, 1);
      expect(grouped.values.fold<int>(0, (s, v) => s + v.length), 4);
    });

    test('no limit renders every group in full', () {
      final grouped = groupByField(applyLimit(sixRows(), 0), 'g');
      expect(grouped['a']!.length, 3);
      expect(grouped['b']!.length, 3);
      expect(grouped.values.fold<int>(0, (s, v) => s + v.length), 6);
    });
  });

  // ── §2: route:"" is already non-tappable (confirm-only, zero code) ─────

  group('route:"" chain (spec §2 — confirmation, no code change)', () {
    test('the _cfg-equivalent expression maps "" to "" (=> onTap: null)', () {
      // Mirrors _initConfig()'s
      //   _routeStr = stripRouteWrapper(_cfg('route').trim());
      // with _cfg inlined as `autheniumDecode(raw) ?? raw`.
      // An empty _routeStr makes `tappable` false in _buildCard, which passes
      // `onTap: null` to the InkWell — no ripple, no navigation.
      // Catches: an autheniumDecode or stripRouteWrapper change that gives an
      // empty `route` a non-empty value, silently making these rows tappable.
      // (stripRouteWrapper('') alone is also covered in
      // test/custody_reveal_test.dart; this asserts the composition.)
      const String raw = '';
      expect(stripRouteWrapper((autheniumDecode(raw) ?? raw).trim()), '');
    });
  });

  // ── ListCard wiring: WHICH list gets cut (widget pump) ─────────────────
  //
  // The pure groups above prove what applyLimit DOES. These two prove where
  // the widget CALLS it — the half no pure test can reach, because a pure test
  // asserts a composition it wrote itself and therefore survives a widget that
  // composes the same helpers differently.
  //
  // Harness (no Firebase, no globalInit) — the recipe documented in
  // test/driver_stop_card_maps_test.dart:
  //   * `table` is OMITTED, so _subscribe() returns at its
  //     `if (rawTable.isEmpty) return;` guard and subscribeToMapCollection --
  //     hence firestoreDb -- is never reached.
  //   * `vidtable` IS set. _subscribe() calls resolveAppVid BEFORE that guard,
  //     and resolveAppVid falls through to getTableVid, which reads the `late`
  //     global appCodeController and throws LateInitializationError outside
  //     globalInit. A non-empty `vidtable` short-circuits it at its first
  //     branch. With no `table` there is no subscription for it to scope.
  //   * _code therefore stays '', so _getServerFiltered() reads
  //     mapTableContent[''] -- seeded per test, removed in tearDown so the
  //     rows do not leak into the rest of the suite.
  //   * _gateCode and _statusCode also default to '' and alias the same seeded
  //     rows. Benign here: `gateTable` is absent so _gateIntended is false and
  //     _applySlotGate passes through untouched, and `statusSearch` is absent
  //     so there is no status pill and no tap lock.
  //   * transactionStore is null in a bare test, and _applySlotGate reads it
  //     through sessionVidForLog() on EVERY build -- so it is built in
  //     setUpAll or the first pump throws NoSuchMethodError on null.
  //   * `route` is absent, so cards are non-tappable and nothing navigates.

  group('ListCard wiring (pump)', () {
    setUpAll(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    tearDown(() => mapTableContent.remove(''));

    // text: seg0 title, seg1 subtitle (empty -> not rendered), seg2 count
    // label. Segment 2 must exist or _buildHeader renders no count at all and
    // the D2 assertions would be vacuous.
    const String kText = 'Riwayat\u{25C6}\u{25C6}catatan';

    Widget wrap(Map<String, dynamic> component, String scrName) => MaterialApp(
          home: Scaffold(
            body: ListCard(
              component: component,
              scrName: scrName,
              lPad: 0,
              tPad: 0,
              rPad: 0,
              bPad: 0,
            ),
          ),
        );

    testWidgets(
        'D2: limit cuts the DISPLAY list only -- header count and stats keep '
        'the uncapped total', (WidgetTester tester) async {
      // Catches: moving the cut onto serverFiltered, e.g.
      //   final serverFiltered = applyLimit(_getServerFiltered(), _limit);
      // That mutant still renders exactly `limit` cards, so a card-count
      // assertion alone would stay green -- it is the header count ('6
      // catatan' becomes '2 catatan') and the stats box ('6' becomes '2') that
      // kill it. Both are asserted below, positively AND negatively.
      mapTableContent[''] = <Map<String, dynamic>>[
        for (int i = 1; i <= 6; i++) <String, dynamic>{'nm': 'BARIS-0$i'},
      ];

      final Map<String, dynamic> component = <String, dynamic>{
        'type': 'LIST_CARD',
        'vidtable': '20342033315492',
        // 'table' omitted on purpose -- see the harness note above.
        'text': kText,
        'title': '<nm>',
        // No mark after the label => empty filter => counts every doc it is
        // handed. That makes the box a direct readout of what
        // computeStatsCounts was given.
        'stats': 'Total',
        'limit': 2,
      };

      await tester.pumpWidget(wrap(component, 'lcl_pump_d2'));
      await tester.pumpAndSettle();

      // Fixture sanity first: without this the assertions below could all be
      // green on a card list that rendered nothing at all.
      expect(find.text('BARIS-01'), findsOneWidget);
      expect(find.text('BARIS-02'), findsOneWidget);

      // The cut itself: rows 3..6 are gone.
      expect(find.text('BARIS-03'), findsNothing);
      expect(find.text('BARIS-04'), findsNothing);
      expect(find.text('BARIS-05'), findsNothing);
      expect(find.text('BARIS-06'), findsNothing);

      // D2, half one -- the header count is the UNCAPPED total.
      expect(find.text('6 catatan'), findsOneWidget);
      expect(find.text('2 catatan'), findsNothing);

      // D2, half two -- the stats strip is the UNCAPPED total too.
      expect(find.text('6'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    // Header action ("Lihat Semua"). Three separate pumps ON PURPOSE: pumping
    // a second ListCard of the same type into the same tester REUSES the
    // element, so initState -- and therefore _initConfig -- never re-runs and
    // the second config is silently ignored. A single test with three
    // pumpWidget calls passes for the wrong reason.
    Map<String, dynamic> moreComp(String text, String moreRoute) =>
        <String, dynamic>{
          'type': 'LIST_CARD',
          'vidtable': '20342033315492',
          'text': text,
          'title': '<nm>',
          'moreRoute': moreRoute,
        };

    // Exactly the shape live op1Screen rows 185/190 deploy today: 5 segments,
    // stopping at emptyText.
    const String kDeployedText =
        'Riwayat Absensi\u{25C6}\u{25C6}\u{25C6}Cari\u{25C6}Belum ada riwayat absensi';
    const String kWithMore = '$kDeployedText\u{25C6}Lihat Semua';

    void seedOneRow() => mapTableContent[''] = <Map<String, dynamic>>[
          <String, dynamic>{'nm': 'BARIS-01'},
        ];

    testWidgets('header action: absent on every already-deployed config',
        (WidgetTester tester) async {
      // Catches: the button leaking into the ~dozen LIST_CARDs already live.
      // Their `text` stops at segment 4, so _txt(5) is '' and showMore is
      // false. This is the zero-regression assertion for this feature.
      seedOneRow();
      await tester.pumpWidget(wrap(moreComp(kDeployedText, ''), 'lcl_more_a'));
      await tester.pumpAndSettle();
      expect(find.text('Riwayat Absensi'), findsOneWidget); // fixture sanity
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('header action: label without moreRoute renders no button',
        (WidgetTester tester) async {
      // Catches: dropping the `&& _moreRoute.isNotEmpty` half of the guard,
      // which would ship a button whose tap goes nowhere.
      seedOneRow();
      await tester.pumpWidget(wrap(moreComp(kWithMore, ''), 'lcl_more_b'));
      await tester.pumpAndSettle();
      expect(find.text('Riwayat Absensi'), findsOneWidget); // fixture sanity
      expect(find.text('Lihat Semua'), findsNothing);
    });

    testWidgets('header action: with both set it renders IN the title row',
        (WidgetTester tester) async {
      // Catches: the button rendering somewhere other than the title row --
      // the whole ask was "satu row dengan teks Riwayat Absensi". A plain
      // findsOneWidget would stay green if it were moved below the header.
      seedOneRow();
      await tester.pumpWidget(wrap(
          moreComp(kWithMore, 'vertikaTeknoLokaciptaRiwayatAbsensi'),
          'lcl_more_c'));
      await tester.pumpAndSettle();

      expect(find.text('Lihat Semua'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                  of: find.text('Riwayat Absensi'), matching: find.byType(Row))
              .first,
          matching: find.text('Lihat Semua'),
        ),
        findsOneWidget,
      );

      // Catches: an unresolvable route throwing instead of no-op'ing.
      // routeExist() is false here -- no linkElement is registered in a test.
      await tester.tap(find.text('Lihat Semua'));
      await tester.pumpAndSettle();
      expect(find.text('Lihat Semua'), findsOneWidget);
    });

    testWidgets(
        'fit-content: a capped list sizes to its rows, not to 79% of the '
        'screen, and its ListView does not scroll',
        (WidgetTester tester) async {
      // Catches: the fixed 0.79 viewport surviving on a capped list (dead
      // space under a 3-row teaser) and the inner ListView keeping its own
      // scroll (the page's SingleChildScrollView already scrolls).
      mapTableContent[''] = <Map<String, dynamic>>[
        for (int i = 1; i <= 3; i++) <String, dynamic>{'nm': 'BARIS-0$i'},
      ];
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'LIST_CARD',
        'vidtable': '20342033315492',
        'text': kDeployedText,
        'title': '<nm>',
        'limit': 3,
      }, 'lcl_fit'));
      await tester.pumpAndSettle();

      expect(find.text('BARIS-03'), findsOneWidget); // fixture sanity

      final double screenH = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final double cardH = tester.getSize(find.byType(ListCard)).height;
      expect(cardH, lessThan(screenH * 0.79),
          reason: 'capped list still claims the fixed viewport height');

      final ListView list = tester.widget<ListView>(find.byType(ListView));
      expect(list.shrinkWrap, isTrue);
      expect(list.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets(
        'fit-content: an UNCAPPED list keeps the 0.79 viewport and scrolls',
        (WidgetTester tester) async {
      // Catches: the zero-regression half -- every deployed LIST_CARD has no
      // `limit`, so it must keep the house-convention viewport and its own
      // scroll. Flipping the default would change every live list screen.
      mapTableContent[''] = <Map<String, dynamic>>[
        for (int i = 1; i <= 3; i++) <String, dynamic>{'nm': 'BARIS-0$i'},
      ];
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'LIST_CARD',
        'vidtable': '20342033315492',
        'text': kDeployedText,
        'title': '<nm>',
      }, 'lcl_nofit'));
      await tester.pumpAndSettle();

      final double screenH = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final double cardH = tester.getSize(find.byType(ListCard)).height;
      expect((cardH - screenH * 0.79).abs(), lessThan(1.0),
          reason: 'uncapped list lost the fixed 0.79 viewport');

      final ListView list = tester.widget<ListView>(find.byType(ListView));
      expect(list.shrinkWrap, isFalse);
      // NOT `isNull`: a primary ListView resolves a null `physics` to
      // AlwaysScrollableScrollPhysics. What matters is that it still scrolls.
      expect(list.physics, isNot(isA<NeverScrollableScrollPhysics>()));
    });

    testWidgets(
        'D1: the cap is GLOBAL -- a group left with no rows renders nothing, '
        'header included', (WidgetTester tester) async {
      // Catches: a per-group cap, i.e. moving the cut inside _buildGrouped
      //   for (final doc in applyLimit(grouped[key]!, _limit))
      // which would render BOTH sections (2 rows each) instead of only the
      // first. `groupLabels` lists both values on purpose: _buildGrouped seeds
      // orderedKeys from _groupLabels FIRST, so 'b' is in the render list
      // either way -- what suppresses it is the `isNotEmpty` guard, and that
      // guard only fires if the cut happened BEFORE grouping.
      mapTableContent[''] = <Map<String, dynamic>>[
        <String, dynamic>{'nm': 'ALPHA-1', 'g': 'a'},
        <String, dynamic>{'nm': 'ALPHA-2', 'g': 'a'},
        <String, dynamic>{'nm': 'ALPHA-3', 'g': 'a'},
        <String, dynamic>{'nm': 'BETA-1', 'g': 'b'},
        <String, dynamic>{'nm': 'BETA-2', 'g': 'b'},
        <String, dynamic>{'nm': 'BETA-3', 'g': 'b'},
      ];

      final Map<String, dynamic> component = <String, dynamic>{
        'type': 'LIST_CARD',
        'vidtable': '20342033315492',
        // 'table' omitted on purpose -- see the harness note above.
        'text': kText,
        'title': '<nm>',
        'groupBy': 'g',
        'groupLabels':
            'a\u{25FC}Kelompok Alpha\u{2605}b\u{25FC}Kelompok Beta',
        'limit': 2,
      };

      await tester.pumpWidget(wrap(component, 'lcl_pump_d1'));
      await tester.pumpAndSettle();

      // Fixture sanity: the first section really rendered.
      expect(find.text('KELOMPOK ALPHA'), findsOneWidget);
      expect(find.text('ALPHA-1'), findsOneWidget);
      expect(find.text('ALPHA-2'), findsOneWidget);

      // Global cap: the 3rd row of the FIRST group is already outside it.
      expect(find.text('ALPHA-3'), findsNothing);

      // D1 -- the second group is absent ENTIRELY, header included.
      expect(find.text('KELOMPOK BETA'), findsNothing);
      expect(find.text('BETA-1'), findsNothing);
      expect(find.text('BETA-2'), findsNothing);
      expect(find.text('BETA-3'), findsNothing);

      // The section count reflects the CUT list (2), while the top header
      // still reports the uncapped total (6) -- D1 and D2 in one frame.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('6 catatan'), findsOneWidget);
    });
  });
}
