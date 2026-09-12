import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/location_detector.dart';

// The whole point of `variant` is that a screen which does NOT set it keeps
// the widget it already had. These tests hold both halves of that promise:
// absent/unknown -> the classic card, `v4` -> the redesign, and nothing in
// between silently opts a tenant in.
//
// initState fires _fetchLocationData(), which reaches for GPS. In a test that
// throws and the widget's own `catch (_)` puts it in the fallback-address
// state -- exactly the state we want to assert layout in, so no mocking.

/// initState calls getLocation() -> getAppGps(), which arms a 5s timer
/// (api.dart:238). Pumping past it lets that timer fire; otherwise the test
/// ends with a pending timer and fails before any assertion is reached.
const Duration _kGpsTimeout = Duration(seconds: 6);

const String _kText = 'Location◆Inside Site◆Outside Site◆Unknown◆'
    'High Accuracy◆Low Accuracy◆±◆m◆View Map◆Refresh◆Posisi tidak ditemukan';

/// Stands in for the tenant's `primaryColor`. main_page.dart paints the app
/// bar with it, so the v4 panel must paint the same colour.
const Color _kAppBarColor = Color(0xFF0B6E80);

Widget _host(Map<String, dynamic> component) => MaterialApp(
      theme: ThemeData(primaryColor: _kAppBarColor),
      home: Scaffold(
        body: LocationDetector(
          key: UniqueKey(),
          component: component,
          scrName: 'testScreen',
          single: true,
        ),
      ),
    );

Map<String, dynamic> _component({String? variant}) => <String, dynamic>{
      'type': 'LOCATION_DETECTOR',
      'borderRadius': 10,
      'showViewMap': 'TRUE',
      'showRefresh': 'TRUE',
      'text': _kText,
      if (variant != null) 'variant': variant,
    };

/// The v4 panel is the only thing that installs a [BleedPainter].
BleedPainter? _panelPainter(WidgetTester tester) {
  for (final CustomPaint p
      in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final CustomPainter? painter = p.painter;
    if (painter is BleedPainter) return painter;
  }
  return null;
}

bool _paintsV4Surface(WidgetTester tester) => _panelPainter(tester) != null;

void main() {
  group('LocationDetector variant gate', () {
    testWidgets('no variant -> classic card, with its LOCATION header',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component()));
      await tester.pump(_kGpsTimeout);

      expect(find.text('LOCATION'), findsOneWidget);
      expect(_paintsV4Surface(tester), isFalse);
    });

    testWidgets('variant v4 -> panel, header dropped',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'v4')));
      await tester.pump(_kGpsTimeout);

      // v4 leads with the status, so the small header label is gone.
      expect(find.text('LOCATION'), findsNothing);
      expect(_paintsV4Surface(tester), isTrue);
    });

    testWidgets('v4 panel paints the app bar colour, not a baked-in teal',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'v4')));
      await tester.pump(_kGpsTimeout);

      expect(_panelPainter(tester)!.color, _kAppBarColor);
    });

    testWidgets('a tenant with a different primaryColor gets THAT colour',
        (WidgetTester tester) async {
      // The whole point of reading Theme.of(context).primaryColor: the panel
      // follows whatever the tenant's theme doc says, so it can never drift
      // out of sync with the bar above it.
      const Color navy = Color(0xFF001A72);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(primaryColor: navy),
        home: Scaffold(
          body: LocationDetector(
            key: UniqueKey(),
            component: _component(variant: 'v4'),
            scrName: 'testScreen',
            single: true,
          ),
        ),
      ));
      await tester.pump(_kGpsTimeout);

      expect(_panelPainter(tester)!.color, navy);
    });

    testWidgets('variant is trimmed and case-folded, like every other widget',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: '  V4 ')));
      await tester.pump(_kGpsTimeout);

      expect(_paintsV4Surface(tester), isTrue);
    });

    testWidgets('variant v6 keeps the v4 panel — there is no v6 card design',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'v6')));
      await tester.pump(_kGpsTimeout);

      // v6 adds the redesigned MAP screen behind "View Map"; the panel itself
      // is the one v4 already shipped, so moving that cell v4 -> v6 must not
      // drop the tenant back to the classic card.
      expect(find.text('LOCATION'), findsNothing);
      expect(_paintsV4Surface(tester), isTrue);
    });

    testWidgets('an unknown variant falls back to classic, never to v4',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_component(variant: 'hero')));
      await tester.pump(_kGpsTimeout);

      expect(find.text('LOCATION'), findsOneWidget);
      expect(_paintsV4Surface(tester), isFalse);
    });

    testWidgets('both variants still render the status label from text[]',
        (WidgetTester tester) async {
      for (final String? v in <String?>[null, 'v4', 'v6']) {
        await tester.pumpWidget(_host(_component(variant: v)));
        await tester.pump(_kGpsTimeout);
        // GPS is unavailable in a test, so the widget stays on its configured
        // default status: text index 3, 'Unknown'.
        expect(find.text('Unknown'), findsOneWidget,
            reason: 'variant=$v should still label the status');
        expect(find.text('View Map'), findsOneWidget,
            reason: 'variant=$v should still offer the map action');
      }
    });
  });
}
