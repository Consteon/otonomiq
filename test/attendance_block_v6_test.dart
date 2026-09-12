import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/theme_tokens.dart';
import 'package:otonomiq/widget/menu_icon_card.dart';

// Vertika v6 "Absen Masuk" / "Absen Pulang" block.
//
// The block is opted into on the HORIZONTAL_ICON container (variant: "v6");
// without it the branch keeps drawing the 4-column card grid it always has,
// which the Checker block on the same screen and every other menu still use.
//
// The dispatch branch itself needs the whole SDUI stack to run, so what is
// tested here is where the decisions actually live: the shape rule, the
// opMode mappings, the palette, and the block's own layout.

const Color _kNavy = Color(0xFF001A72); // the tenant primary in production
const Color _kLightTeal = Color(0xFF1CACC4); // 2.71:1 on white

Widget _host(Widget child, {Color primary = _kNavy}) => MaterialApp(
      theme: ThemeData(primaryColor: primary),
      home: Scaffold(body: child),
    );

/// Prebuilt tiles: the block takes them ready-made, so layout can be asserted
/// without dragging AttendQrGpsSelfie and its GPS/camera stack into the test.
List<Widget> _tiles(int n) => List<Widget>.generate(
      n,
      (int i) => SizedBox(key: ValueKey<String>('t$i'), height: 64),
    );

Widget _block({
  int tiles = 3,
  String title = 'Absen Masuk',
  String meta = 'Terakhir 11:38',
  String tone = 'in',
}) =>
    Builder(
      builder: (BuildContext context) => attendanceBlockV6(
        context: context,
        title: title,
        meta: meta,
        tone: tone,
        emptyText: 'Belum ada metode absensi aktif. Hubungi admin.',
        tiles: _tiles(tiles),
      ),
    );

double _dy(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey<String>(key))).dy;

void main() {
  group('grid shape follows the method count', () {
    test('three is the only vertical layout', () {
      expect(attendRowShape(1), isTrue);
      expect(attendRowShape(2), isTrue);
      expect(attendRowShape(3), isFalse);
      expect(attendRowShape(4), isTrue);
      expect(attendRowShape(5), isTrue);
      expect(attendRowShape(0), isTrue);
    });

    testWidgets('three tiles share one row', (WidgetTester tester) async {
      await tester.pumpWidget(_host(_block(tiles: 3)));

      expect(_dy(tester, 't0'), _dy(tester, 't1'));
      expect(_dy(tester, 't1'), _dy(tester, 't2'));
    });

    testWidgets('four tiles go 2x2, not one squeezed row',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_block(tiles: 4)));

      expect(_dy(tester, 't0'), _dy(tester, 't1'));
      expect(_dy(tester, 't2'), greaterThan(_dy(tester, 't0')));
      expect(_dy(tester, 't2'), _dy(tester, 't3'));
    });

    testWidgets('two tiles stay on one row', (WidgetTester tester) async {
      await tester.pumpWidget(_host(_block(tiles: 2)));

      expect(_dy(tester, 't0'), _dy(tester, 't1'));
    });

    testWidgets('five tiles keep wrapping in pairs',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_block(tiles: 5)));

      expect(_dy(tester, 't2'), greaterThan(_dy(tester, 't0')));
      expect(_dy(tester, 't4'), greaterThan(_dy(tester, 't2')));
    });

    testWidgets('no method configured -> the block still appears, and says so',
        (WidgetTester tester) async {
      // Silence would look identical to "loading". A misconfigured block names
      // who to ask instead.
      await tester.pumpWidget(_host(_block(tiles: 0)));

      expect(find.text('Belum ada metode absensi aktif. Hubungi admin.'),
          findsOneWidget);
      expect(find.text('Absen Masuk'), findsOneWidget);
    });
  });

  group('block head', () {
    testWidgets('title and meta both render', (WidgetTester tester) async {
      await tester.pumpWidget(_host(_block()));

      expect(find.text('Absen Masuk'), findsOneWidget);
      expect(find.text('Terakhir 11:38'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
    });

    testWidgets('the meta is pinned to the right edge, not left mid-row',
        (WidgetTester tester) async {
      // An Expanded title beside a Flexible meta splits the free space 50/50
      // BEFORE either child is measured, which parks the meta in the middle
      // with a gap after it. Regression guard for exactly that.
      await tester.pumpWidget(_host(
        SizedBox(width: 400, child: _block()),
      ));

      final double blockRight = tester.getTopRight(find.byType(Row).first).dx;
      expect(tester.getTopRight(find.text('Terakhir 11:38')).dx, blockRight);
    });

    testWidgets('a long meta wraps instead of starving the title',
        (WidgetTester tester) async {
      // A non-flexible child is measured with UNBOUNDED width, so the cap is
      // what keeps a long string from pushing the title to zero.
      await tester.pumpWidget(_host(SizedBox(
        width: 400,
        child: _block(meta: 'Terakhir kemarin 17:04 di pos gerbang utama'),
      )));

      expect(tester.getSize(find.text('Absen Masuk')).width, greaterThan(100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the pulang block points the other way',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _host(_block(title: 'Absen Pulang', tone: 'out')));

      expect(find.byIcon(Icons.logout), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);
    });

    testWidgets('an empty title drops the head entirely, not a blank row',
        (WidgetTester tester) async {
      // diamondTextToList('') yields [''], so a block with no `text` arrives
      // here as an empty title rather than a missing one.
      await tester.pumpWidget(_host(_block(title: '', meta: '')));

      expect(find.byIcon(Icons.login), findsNothing);
    });
  });

  group('AttendPalette', () {
    late BuildContext ctx;

    Future<void> capture(WidgetTester tester, Color primary) async {
      await tester.pumpWidget(_host(
        Builder(builder: (BuildContext c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
        primary: primary,
      ));
    }

    testWidgets('masuk follows the tenant primary', (WidgetTester tester) async {
      await capture(tester, _kNavy);

      expect(AttendPalette.of(ctx, 'in').ink, _kNavy);
    });

    testWidgets('a light tenant primary steps down instead of shipping 2:1',
        (WidgetTester tester) async {
      // #1CACC4 on its own 12% tint is nowhere near 4.5:1 — exactly the
      // pairing the v6 palette forbids outright.
      await capture(tester, _kLightTeal);

      expect(AttendPalette.of(ctx, 'in').ink, OtqPalette.foreground);
    });

    testWidgets('the masuk tint matches v6 primary-soft, not an alpha blend',
        (WidgetTester tester) async {
      // Blending navy at 12% over white lands on #E0E4EE -- visibly greyer
      // than the #E3E8F8 / #C1CCEC the system specifies. Lifting lightness in
      // HSL reproduces both to within one step while staying tenant-derived.
      await capture(tester, _kNavy);

      expect(AttendPalette.of(ctx, 'in').fill, const Color(0xFFE3E8F7));
      expect(AttendPalette.of(ctx, 'in').pressed, const Color(0xFFC0CAED));
    });

    testWidgets('pulang is design-system orange, never the tenant colour',
        (WidgetTester tester) async {
      await capture(tester, _kNavy);

      expect(AttendPalette.of(ctx, 'out').ink, OtqPalette.v6AccentText);
      expect(AttendPalette.of(ctx, 'out').fill, OtqPalette.v6AccentSoft);
    });

    testWidgets('disabled wins over the tone, in both blocks',
        (WidgetTester tester) async {
      // v6: "Keadaan nonaktif diputuskan sebelum keluarga warna."
      await capture(tester, _kNavy);

      for (final String tone in <String>['in', 'out']) {
        final AttendPalette p = AttendPalette.of(ctx, tone, enabled: false);
        expect(p.fill, OtqPalette.v6Muted, reason: tone);
        expect(p.ink, OtqPalette.v6DisabledFg, reason: tone);
      }
    });
  });

  group('section rule', () {
    Finder rule() => find.byWidgetPredicate((Widget w) =>
        w is Container && w.color == OtqPalette.v6Border);

    testWidgets('the block draws its own 1 dp separator',
        (WidgetTester tester) async {
      // v6 separates the flat home sections with a rule rather than boxing
      // each one in a card; drawing it here keeps the screen JSON free of a
      // divider component.
      await tester.pumpWidget(_host(_block()));

      expect(rule(), findsOneWidget);
      expect(tester.getSize(rule()).height, 1.0);
    });

    testWidgets('it can be turned off', (WidgetTester tester) async {
      await tester.pumpWidget(_host(Builder(
        builder: (BuildContext context) => attendanceBlockV6(
          context: context,
          title: 'Absen Masuk',
          meta: '',
          tone: 'in',
          emptyText: '',
          tiles: _tiles(2),
          rule: false,
        ),
      )));

      expect(rule(), findsNothing);
    });
  });

  group('live block meta', () {
    // The label is the whole decision; the widget around it only wires a
    // ledger subscription to it. Pure, so no Firestore is needed here.
    final DateTime now = DateTime(2026, 9, 9, 12, 2);
    int at(int day, int h, int m) =>
        DateTime(2026, 9, day, h, m).millisecondsSinceEpoch;

    String label(int? ms) => attendMetaLabel(
          epochMs: ms,
          now: now,
          prefix: 'Terakhir',
          yesterday: 'kemarin',
          none: 'Belum ada',
          format: 'HH:mm',
        );

    test('today shows the clock alone', () {
      expect(label(at(9, 11, 38)), 'Terakhir 11:38');
    });

    test('yesterday says so, rather than reading as today', () {
      expect(label(at(8, 17, 4)), 'Terakhir kemarin 17:04');
    });

    test('older than yesterday keeps the date', () {
      // "kemarin 17:04" would be a lie and a bare clock time is ambiguous.
      expect(label(at(3, 17, 4)), 'Terakhir 3 Sep 17:04');
    });

    test('nothing recorded says so, and never prints an empty prefix', () {
      expect(label(null), 'Belum ada');
    });

    test('an empty prefix does not leave leading whitespace', () {
      expect(
        attendMetaLabel(
          epochMs: at(9, 11, 38),
          now: now,
          prefix: '',
          yesterday: 'kemarin',
          none: 'Belum ada',
          format: 'HH:mm',
        ),
        '11:38',
      );
    });

    test('the format comes from lastAction position 4', () {
      expect(
        attendMetaLabel(
          epochMs: at(9, 11, 38),
          now: now,
          prefix: 'Terakhir',
          yesterday: 'kemarin',
          none: 'Belum ada',
          format: 'HH.mm',
        ),
        'Terakhir 11.38',
      );
    });
  });

  group('opMode captions', () {
    // The ICON is never derived from opMode -- it is the tenant's own PNG from
    // the sheet, like every other menu tile in this app. Only the caption has
    // a default.
    test('captions say what happens next, not what the label already says', () {
      expect(attendSubtitleFor('qr-single'), 'Pindai di pos');
      expect(attendSubtitleFor('selfie'), 'Foto wajah');
      expect(attendSubtitleFor('qr-selfie'), 'Pindai, lalu foto');
      expect(attendSubtitleFor('unknown'), '');
    });

    test('the sheet wins whenever it actually says something', () {
      expect(attendSubtitle('Akurasi ±52m', 'gps-single'), 'Akurasi ±52m');
      expect(attendSubtitle('  Pindai di gerbang  ', 'qr-single'),
          'Pindai di gerbang');
    });

    test('blank, whitespace and the -- sentinel all mean "use the default"',
        () {
      // A cleared cell must not ship a tile with a blank second line, and the
      // sheet's own empty sentinel must not print literally under the label.
      for (final String raw in <String>['', '   ', '--']) {
        expect(attendSubtitle(raw, 'qr-single'), 'Pindai di pos',
            reason: 'raw=${raw.isEmpty ? '(empty)' : raw}');
      }
    });

    test('an unmapped opMode with no sheet caption leaves the label bare', () {
      expect(attendSubtitle('', 'something-new'), '');
    });
  });

  group('menuIconCard variant gate', () {
    testWidgets('v6 draws the method tile', (WidgetTester tester) async {
      await tester.pumpWidget(_host(menuIconCard(
        imageUrl: '',
        label: 'QR',
        fontSize: 14,
        variant: 'v6',
        opMode: 'qr-single',
      )));

      expect(find.text('Pindai di pos'), findsOneWidget);
      expect(find.text('QR'), findsOneWidget);
    });

    testWidgets('a sheet subtitle overrides the default',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(menuIconCard(
        imageUrl: '',
        label: 'GPS',
        fontSize: 14,
        variant: 'v6',
        opMode: 'gps-single',
        subtitle: 'Akurasi ±52m',
      )));

      expect(find.text('Akurasi ±52m'), findsOneWidget);
      expect(find.text('Pakai lokasi'), findsNothing);
    });

    testWidgets('no variant keeps the classic card', (WidgetTester tester) async {
      await tester.pumpWidget(_host(menuIconCard(
        imageUrl: '',
        label: 'QR',
        fontSize: 14,
        opMode: 'qr-single',
      )));

      expect(find.text('Pindai di pos'), findsNothing);
      expect(find.text('QR'), findsOneWidget);
    });

    testWidgets('an unknown variant falls back to classic, never to v6',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(menuIconCard(
        imageUrl: '',
        label: 'QR',
        fontSize: 14,
        variant: 'v7',
        opMode: 'qr-single',
      )));

      expect(find.text('Pindai di pos'), findsNothing);
    });
  });
}
