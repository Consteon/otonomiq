import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/theme_tokens.dart';
import 'package:otonomiq/widget/time_presence.dart';

// The whole point of `variant` is that a screen which does NOT set it keeps
// the widget it already had. These tests hold both halves of that promise:
// absent/unknown -> the classic 3-tile card, `v4` -> the timeline module, and
// nothing in between silently opts a tenant in.
//
// No `lastAction` is configured in any fixture, so the widget runs its v1
// shape: zero Firestore query, no Obx, no transactionStore needed.
//
// Two live things must be torn down or the test ends with "a Timer is still
// pending" / an active ticker: _LiveCounter's 1s Timer.periodic (armed only
// when check-in has a value) and the v4 live node's repeating pulse. Pumping
// an empty tree disposes the widget, which cancels both -- that is what
// [_teardown] is for. pumpAndSettle can never be used here: a repeating
// animation never settles.

const String _kDiamond = '◆';

/// Stands in for the tenant's `primaryColor` — deep enough to read on white.
const Color _kNavy = Color(0xFF001A72); // 15.1:1

/// A brand teal that does NOT read on white (2.71:1). The accent must step
/// down to the foreground rather than ship unreadable text.
const Color _kLightTeal = Color(0xFF1CACC4);

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 8 ◆-segments, dev-spec §3 order.
String _text({String checkIn = '', String lastAction = ''}) => <String>[
      'Absensi hari ini',
      'Absen Masuk',
      'Durasi',
      'Aksi terakhir',
      '--:--',
      checkIn, // slot 5
      lastAction, // slot 6
      '', // slot 7 checkout
    ].join(_kDiamond);

Map<String, dynamic> _component({
  String? variant,
  String checkIn = '',
  String lastAction = '',
}) =>
    <String, dynamic>{
      'type': 'TIME_PRESENCE',
      'borderRadius': 12,
      'text': _text(checkIn: checkIn, lastAction: lastAction),
      if (variant != null) 'variant': variant,
    };

Widget _host(Map<String, dynamic> component, {Color primary = _kNavy}) =>
    MaterialApp(
      theme: ThemeData(primaryColor: primary),
      home: Scaffold(
        body: TimePresence(
          key: UniqueKey(),
          component: component,
          scrName: 'testScreen',
          single: true,
        ),
      ),
    );

/// The dashed connector is installed by the v4 track and nothing else.
bool _isV4(WidgetTester tester) => _dashCount(tester) > 0;

/// How many of the two connectors are still the dashed "belum" track.
int _dashCount(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((CustomPaint p) => p.painter is DashConnectorPainter)
    .length;

/// Disposes the widget so its Timer and ticker do not outlive the test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('TimePresence variant gate', () {
    testWidgets('no variant -> classic card, with its clock header icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component()));

      expect(find.byIcon(Icons.access_time_outlined), findsOneWidget);
      expect(_isV4(tester), isFalse);
      await _teardown(tester);
    });

    testWidgets('variant v4 -> timeline module, header icon dropped',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'v4')));

      expect(find.byIcon(Icons.access_time_outlined), findsNothing);
      expect(_isV4(tester), isTrue);
      await _teardown(tester);
    });

    testWidgets('variant is trimmed and case-folded, like every other widget',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: '  V4 ')));

      expect(_isV4(tester), isTrue);
      await _teardown(tester);
    });

    testWidgets('an unknown variant falls back to classic, never to v4',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'hero')));

      expect(find.byIcon(Icons.access_time_outlined), findsOneWidget);
      expect(_isV4(tester), isFalse);
      await _teardown(tester);
    });

    testWidgets('both variants render the same labels and values from text[]',
        (WidgetTester tester) async {
      for (final String? v in <String?>[null, 'v4']) {
        await tester.pumpWidget(_host(_component(variant: v)));

        expect(find.text('Absensi hari ini'), findsOneWidget, reason: 'v=$v');
        expect(find.text('Absen Masuk'), findsOneWidget, reason: 'v=$v');
        expect(find.text('Durasi'), findsOneWidget, reason: 'v=$v');
        expect(find.text('Aksi terakhir'), findsOneWidget, reason: 'v=$v');
        // No check-in, no last action: all three columns show the no-data slot.
        expect(find.text('--:--'), findsNWidgets(3), reason: 'v=$v');
        await _teardown(tester);
      }
    });
  });

  group('TimePresence v4 node states', () {
    testWidgets('nothing recorded -> no completed node', (tester) async {
      await tester.pumpWidget(_host(_component(variant: 'v4')));

      expect(find.byIcon(Icons.check), findsNothing);
      await _teardown(tester);
    });

    testWidgets('a check-in marks its node done and starts the live node',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        _component(variant: 'v4', checkIn: _hhmm(DateTime.now())),
      ));

      expect(find.byIcon(Icons.check), findsOneWidget);
      // Elapsed is under a minute, so the counter reads zero and is tinted.
      expect(find.text('00:00'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('a segment goes solid only once both its ends are reached',
        (WidgetTester tester) async {
      // Keying the line on one end alone dashes the segment BETWEEN two
      // reached nodes — what the first device build did.
      final String now = _hhmm(DateTime.now());

      await tester.pumpWidget(_host(_component(variant: 'v4')));
      expect(_dashCount(tester), 2, reason: 'nothing recorded');
      await _teardown(tester);

      await tester.pumpWidget(
          _host(_component(variant: 'v4', checkIn: now)));
      expect(_dashCount(tester), 1, reason: 'checked in, no action yet');
      await _teardown(tester);

      await tester.pumpWidget(_host(
          _component(variant: 'v4', checkIn: now, lastAction: now)));
      expect(_dashCount(tester), 0, reason: 'every step reached');
      await _teardown(tester);
    });

    testWidgets('the classic card never paints a timeline node',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        _component(checkIn: _hhmm(DateTime.now())),
      ));

      expect(find.byIcon(Icons.check), findsNothing);
      await _teardown(tester);
    });
  });

  group('TimePresence v4 accent is measured, not assumed', () {
    testWidgets('a readable primaryColor tints the running counter',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        _component(variant: 'v4', checkIn: _hhmm(DateTime.now())),
        primary: _kNavy,
      ));

      expect(_colorOf(tester, '00:00'), _kNavy);
      await _teardown(tester);
    });

    testWidgets('a light brand colour steps down to the foreground',
        (WidgetTester tester) async {
      // #1CACC4 is 2.71:1 on white. Shipping it as text would be exactly the
      // failure otqOn exists to prevent.
      await tester.pumpWidget(_host(
        _component(variant: 'v4', checkIn: _hhmm(DateTime.now())),
        primary: _kLightTeal,
      ));

      expect(_colorOf(tester, '00:00'), OtqPalette.foreground);
      await _teardown(tester);
    });

    testWidgets('a placeholder column is muted, never the disabled grey',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'v4')));

      // The mockup's --color-disabled-fg (#93A6AC) is 2.53:1 and fails at any
      // size; mutedFg is 6.73:1. All three columns are placeholders here.
      expect(
        tester
            .widgetList<Text>(find.text('--:--'))
            .map((Text t) => t.style?.color)
            .toSet(),
        <Color>{OtqPalette.mutedFg},
      );
      await _teardown(tester);
    });
  });
}
