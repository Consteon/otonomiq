// Smoke test for the test harness itself.
//
// The previous default counter-stub asserted against a `MyApp` it never pumped
// (the pumpWidget call was commented out), so it failed and made `flutter test`
// exit non-zero — turning every other (passing) test in the suite red.
//
// `MyApp` cannot be pumped in a plain unit test because its bootstrap requires
// Firebase. This minimal test just verifies the widget-test harness works; real
// widget coverage of app screens should use a fake/mocked bootstrap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('widget test harness renders a basic widget', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('otonomiq'))),
    );

    expect(find.text('otonomiq'), findsOneWidget);
  });
}
