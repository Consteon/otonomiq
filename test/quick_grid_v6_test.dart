import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/menu_icon_card.dart';

// Vertika v6 shortcut grid (`.quick`) — the Laporan / Formulir / Log / Terbaru
// menus. Opted into on the HGR component (`variant: "v6"`), so a screen that
// never sets it keeps the 4-column card grid it has today.
//
// v6 has TWO tile shapes and mixing them is the bug this guards: the
// attendance METHOD tile (soft-filled block, label + caption) and this
// shortcut tile (soft icon square, label underneath, nothing behind the text).

const Color _kNavy = Color(0xFF001A72);

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(primaryColor: _kNavy),
      home: Scaffold(body: child),
    );

Widget _tile({
  String variant = 'v6',
  bool quick = true,
  String label = 'Harian',
  int badge = 0,
}) =>
    menuIconCard(
      imageUrl: '',
      label: label,
      fontSize: 14,
      variant: variant,
      quick: quick,
      badgeCount: badge,
      onTap: () {},
    );

/// The icon square is the only 48x48 box the shortcut tile draws.
Finder _square() => find.byWidgetPredicate((Widget w) =>
    w is Container &&
    w.constraints?.maxWidth == 48 &&
    w.constraints?.maxHeight == 48);

void main() {
  group('shortcut tile', () {
    testWidgets('v6 + quick draws the icon square, no card',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(SizedBox(width: 72, child: _tile())));

      expect(_square(), findsOneWidget);
      expect(find.text('Harian'), findsOneWidget);
    });

    testWidgets('the label is 12/600 centred, not the classic card caption',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(SizedBox(width: 72, child: _tile())));

      final Text t = tester.widget<Text>(find.text('Harian'));
      expect(t.style?.fontSize, 12);
      expect(t.style?.fontWeight, FontWeight.w600);
      expect(t.textAlign, TextAlign.center);
      expect(t.maxLines, 2);
    });

    testWidgets('no variant keeps the classic card', (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(SizedBox(width: 72, child: _tile(variant: ''))));

      expect(_square(), findsNothing);
      expect(find.text('Harian'), findsOneWidget);
    });

    testWidgets('an unknown variant falls back to classic, never to v6',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(SizedBox(width: 72, child: _tile(variant: 'v7'))));

      expect(_square(), findsNothing);
    });

    testWidgets('v6 WITHOUT quick is the method tile, not this one',
        (WidgetTester tester) async {
      // Same variant value, different shape. Routing on `variant` alone would
      // hand the shortcut grid an attendance block tile.
      await tester.pumpWidget(_host(SizedBox(
        width: 200,
        child: menuIconCard(
          imageUrl: '',
          label: 'QR',
          fontSize: 14,
          variant: 'v6',
          opMode: 'qr-single',
        ),
      )));

      expect(_square(), findsNothing);
      expect(find.text('Pindai di pos'), findsOneWidget);
    });

    testWidgets('a badge hangs off the square', (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(SizedBox(width: 72, child: _tile(badge: 3))));

      expect(find.text('3'), findsOneWidget);
      expect(_square(), findsOneWidget);
    });

    testWidgets('a long label fits the fixed cell instead of overflowing',
        (WidgetTester tester) async {
      // The grid derives childAspectRatio from kQuickTileHeight, so the tile
      // has to live inside exactly that height at the narrowest real cell
      // (5 columns on a 360dp phone).
      await tester.pumpWidget(_host(SizedBox(
        width: 64,
        height: kQuickTileHeight,
        child: _tile(label: 'Complain Supervisor List'),
      )));

      expect(tester.takeException(), isNull);
      expect(_square(), findsOneWidget);
    });
  });
}
