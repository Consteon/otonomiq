import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/theme_tokens.dart';
import 'package:otonomiq/widget/tab_sections.dart';

// Vertika v6 tabbed sections (`TAB`). One component owns the Laporan /
// Formulir / Log / Terbaru groups; `mode` decides whether they stack on the
// page, collapse behind a "Lainnya" link, or switch under a tab bar.
//
// Two contracts are load-bearing here and both are guarded below:
//   - every narrowing of `mode` fails OPEN to `inline`, so a typo'd route or a
//     misspelt flag can never hide sections behind a dead link;
//   - `variant` gates the LOOK only, so a screen with no v6 variant still
//     renders a working TAB.

const Color _kNavy = Color(0xFF001A72);

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(primaryColor: _kNavy),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

List<TabSection> _four() => <TabSection>[
      const TabSection('Laporan', <Widget>[Text('isi-laporan')]),
      const TabSection('Formulir', <Widget>[Text('isi-formulir')]),
      const TabSection('Log', <Widget>[Text('isi-log')]),
      const TabSection('Terbaru', <Widget>[Text('isi-terbaru')]),
    ];

Widget _tabs({
  String mode = '',
  bool v6 = true,
  String route = '',
  String link = '',
  String scrName = 'home',
  List<TabSection>? sections,
}) =>
    TabSections(
      scrName: scrName,
      sections: sections ?? _four(),
      mode: mode,
      v6: v6,
      link: link,
      route: route,
    );

/// The active tab indicator: the only 3 dp bar the tab row draws.
Iterable<Color?> _indicatorColors(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((Container c) => c.constraints?.maxHeight == 3)
    .map((Container c) => (c.decoration as BoxDecoration?)?.color);

void main() {
  setUp(() {
    TabSections.activeTab.clear();
    screenUIComponent = <String, dynamic>{
      'menuPage': <String, dynamic>{'children': <dynamic>[]},
    };
  });

  group('groupTabSections', () {
    test('groups by tab index, ascending, and pairs each with its label', () {
      final List<TabSection> out = groupTabSections(
        <MapEntry<int, Widget>>[
          const MapEntry<int, Widget>(1, Text('b1')),
          const MapEntry<int, Widget>(0, Text('a1')),
          const MapEntry<int, Widget>(1, Text('b2')),
          const MapEntry<int, Widget>(0, Text('a2')),
        ],
        <String>['A', 'B'],
      );

      expect(out.map((TabSection s) => s.label), <String>['A', 'B']);
      expect(out[0].children.length, 2);
      expect(out[1].children.length, 2);
      // Order WITHIN a group is document order, not the order indexes appeared.
      expect((out[0].children[0] as Text).data, 'a1');
      expect((out[0].children[1] as Text).data, 'a2');
    });

    test('sparse indexes keep their own labels, not their rank', () {
      final List<TabSection> out = groupTabSections(
        <MapEntry<int, Widget>>[
          const MapEntry<int, Widget>(2, Text('c')),
          const MapEntry<int, Widget>(0, Text('a')),
        ],
        <String>['A', 'B', 'C'],
      );

      expect(out.map((TabSection s) => s.label), <String>['A', 'C']);
    });

    test('a group past the end of the labels still renders, unlabelled', () {
      final List<TabSection> out = groupTabSections(
        <MapEntry<int, Widget>>[const MapEntry<int, Widget>(7, Text('x'))],
        <String>['A'],
      );

      expect(out.single.label, '');
      expect(out.single.children.length, 1);
    });
  });

  group('tabChildren', () {
    test('no source: the component own children, counted once', () {
      final Map<String, dynamic> c = <String, dynamic>{
        'children': <dynamic>['a', 'b'],
      };
      expect(tabChildren(c, c), <dynamic>['a', 'b']);
    });

    // ★ The regression this exists to prevent. Replacing instead of appending
    // drops a block that was authored, with no error and nothing on screen.
    test('with a source: borrowed FIRST, then the component own', () {
      final Map<String, dynamic> host = <String, dynamic>{
        'children': <dynamic>['grid0', 'grid1'],
      };
      final Map<String, dynamic> c = <String, dynamic>{
        'source': 'home',
        'children': <dynamic>['log'],
      };
      expect(tabChildren(c, host), <dynamic>['grid0', 'grid1', 'log']);
    });

    test('a source with no local children borrows only', () {
      final Map<String, dynamic> host = <String, dynamic>{
        'children': <dynamic>['grid0'],
      };
      expect(tabChildren(<String, dynamic>{'source': 'home'}, host),
          <dynamic>['grid0']);
    });

    test('missing or non-list children yield an empty list, never a throw', () {
      expect(tabChildren(<String, dynamic>{}, <String, dynamic>{}), isEmpty);
      expect(
          tabChildren(<String, dynamic>{'children': 'oops'},
              <String, dynamic>{'children': 7}),
          isEmpty);
      expect(tabChildren(null, null), isEmpty);
    });
  });

  group('findTabComponent', () {
    test('returns the TAB component of the named screen', () {
      screenUIComponent['home'] = <String, dynamic>{
        'children': <dynamic>[
          <String, dynamic>{'type': 'TXT'},
          <String, dynamic>{'type': 'tab', 'data': 'A◆B'},
        ],
      };

      expect(findTabComponent('home')?['data'], 'A◆B');
    });

    test('null for a screen with no TAB, and for an unknown screen', () {
      screenUIComponent['home'] = <String, dynamic>{
        'children': <dynamic>[
          <String, dynamic>{'type': 'HGR'}
        ],
      };

      expect(findTabComponent('home'), isNull);
      expect(findTabComponent('nope'), isNull);
    });

    test('survives screenUIComponent being null', () {
      screenUIComponent = null;
      expect(findTabComponent('home'), isNull);
    });
  });

  group('mode inline', () {
    testWidgets('absent mode stacks every section under its own heading',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs()));

      for (final String s in <String>['Laporan', 'Formulir', 'Log', 'Terbaru']) {
        expect(find.text(s), findsOneWidget);
      }
      for (final String s in <String>[
        'isi-laporan',
        'isi-formulir',
        'isi-log',
        'isi-terbaru'
      ]) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('an unrecognised mode falls back to inline, hiding nothing',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tabs')));

      expect(find.text('isi-terbaru'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('empty sections render nothing at all',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(sections: <TabSection>[])));

      expect(find.byType(Text), findsNothing);
    });
  });

  group('mode link', () {
    testWidgets('shows only the first section plus the link',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(_tabs(mode: 'link', route: 'menuPage')));

      expect(find.text('Laporan'), findsOneWidget);
      expect(find.text('isi-laporan'), findsOneWidget);
      expect(find.text('Lainnya'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      for (final String s in <String>[
        'isi-formulir',
        'isi-log',
        'isi-terbaru'
      ]) {
        expect(find.text(s), findsNothing);
      }
    });

    testWidgets('a custom link label replaces the default',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(_tabs(mode: 'link', route: 'menuPage', link: 'Semua menu')));

      expect(find.text('Semua menu'), findsOneWidget);
      expect(find.text('Lainnya'), findsNothing);
    });

    // ★ The failure this exists to prevent: a route nobody declared would
    // otherwise leave three quarters of the menu behind a dead tap.
    testWidgets('an undeclared route fails OPEN to inline',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'link', route: 'typoPage')));

      expect(find.text('isi-terbaru'), findsOneWidget);
      expect(find.text('Lainnya'), findsNothing);
    });

    testWidgets('a blank route fails OPEN to inline',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'link')));

      expect(find.text('isi-terbaru'), findsOneWidget);
      expect(find.text('Lainnya'), findsNothing);
    });

    testWidgets('one section alone is never collapsed behind a link',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(
        mode: 'link',
        route: 'menuPage',
        sections: <TabSection>[_four().first],
      )));

      expect(find.text('isi-laporan'), findsOneWidget);
      expect(find.text('Lainnya'), findsNothing);
    });

    testWidgets('tapping a link whose page is unbuilt does not navigate',
        (WidgetTester tester) async {
      linkElement.remove('menuPage');
      await tester.pumpWidget(_host(_tabs(mode: 'link', route: 'menuPage')));

      await tester.tap(find.text('Lainnya'));
      await tester.pump();

      expect(routeStack.get(), isNot('menuPage'));
    });
  });

  group('mode tab', () {
    testWidgets('shows every label but only the active section',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab')));

      for (final String s in <String>['Laporan', 'Formulir', 'Log', 'Terbaru']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('isi-laporan'), findsOneWidget);
      expect(find.text('isi-log'), findsNothing);
    });

    testWidgets('tapping a tab swaps the section', (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab')));

      await tester.tap(find.text('Log'));
      await tester.pump();

      expect(find.text('isi-log'), findsOneWidget);
      expect(find.text('isi-laporan'), findsNothing);
    });

    testWidgets('the selection survives a full rebuild of the widget tree',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab')));
      await tester.tap(find.text('Terbaru'));
      await tester.pump();

      // any_page re-runs buildPage on every redux dispatch, so the widget is a
      // brand new instance. A selection kept in State would reset here.
      await tester.pumpWidget(_host(_tabs(mode: 'tab')));

      expect(find.text('isi-terbaru'), findsOneWidget);
    });

    testWidgets('the selection is per screen', (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab', scrName: 'a')));
      await tester.tap(find.text('Log'));
      await tester.pump();

      await tester.pumpWidget(_host(_tabs(mode: 'tab', scrName: 'b')));

      expect(find.text('isi-laporan'), findsOneWidget);
    });

    testWidgets('a single section renders inline, with no tab bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(
        mode: 'tab',
        sections: <TabSection>[_four().first],
      )));

      expect(find.text('isi-laporan'), findsOneWidget);
      expect(_indicatorColors(tester), isEmpty);
    });
  });

  group('variant gates the look, not the structure', () {
    testWidgets('v6 marks the active tab in accent orange',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab')));

      expect(_indicatorColors(tester),
          contains(OtqPalette.v6AccentStrong));
      expect(_indicatorColors(tester), isNot(contains(_kNavy)));
    });

    testWidgets('without the variant the indicator stays on brand',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab', v6: false)));

      expect(_indicatorColors(tester), contains(_kNavy));
      expect(_indicatorColors(tester),
          isNot(contains(OtqPalette.v6AccentStrong)));
    });

    testWidgets('without the variant the sections still work',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs(mode: 'tab', v6: false)));

      await tester.tap(find.text('Log'));
      await tester.pump();

      expect(find.text('isi-log'), findsOneWidget);
    });

    testWidgets('headings are 16/600 with v6 and the classic 18 without',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_tabs()));
      TextStyle head() => tester.widget<Text>(find.text('Laporan')).style!;
      expect(head().fontSize, 16);
      expect(head().fontWeight, FontWeight.w600);

      await tester.pumpWidget(_host(_tabs(v6: false)));
      expect(head().fontSize, 18);
      expect(head().fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('v6 draws the section rule, classic does not',
        (WidgetTester tester) async {
      int rules() => tester
          .widgetList<Container>(find.byType(Container))
          .where((Container c) =>
              c.constraints?.maxHeight == 1 &&
              c.color == OtqPalette.v6Border)
          .length;

      await tester.pumpWidget(_host(_tabs()));
      expect(rules(), 4);

      await tester.pumpWidget(_host(_tabs(v6: false)));
      expect(rules(), 0);
    });
  });
}
