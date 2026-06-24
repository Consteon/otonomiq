// test/custody_stepper_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/custody_stepper.dart';

void main() {
  // -- clampStepperValue (pure function) -----------------------------------

  group('clampStepperValue', () {
    test('value above min is unchanged', () {
      expect(clampStepperValue(5, 0), 5);
    });

    test('value at min is unchanged', () {
      expect(clampStepperValue(0, 0), 0);
    });

    test('value below min is clamped to min', () {
      expect(clampStepperValue(-1, 0), 0);
    });

    test('works with non-zero min', () {
      expect(clampStepperValue(2, 3), 3);
      expect(clampStepperValue(5, 3), 5);
    });

    test('negative min', () {
      expect(clampStepperValue(-5, -3), -3);
      expect(clampStepperValue(-2, -3), -2);
    });
  });

  // -- Widget: decrement disabled at min -----------------------------------

  group('CustodyStepper widget', () {
    testWidgets('decrement button disabled when value == min', (tester) async {
      bool decremented = false;
      bool incremented = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustodyStepper(
              value: 0,
              min: 0,
              onDecrement: () => decremented = true,
              onIncrement: () => incremented = true,
            ),
          ),
        ),
      );

      // Find the two Icons -- remove (decrement) and add (increment).
      final removeFinder = find.byIcon(Icons.remove);
      final addFinder = find.byIcon(Icons.add);
      expect(removeFinder, findsOneWidget);
      expect(addFinder, findsOneWidget);

      // Tap decrement: should NOT fire (value == min).
      await tester.tap(removeFinder);
      await tester.pump();
      expect(decremented, false);

      // Tap increment: SHOULD fire.
      await tester.tap(addFinder);
      await tester.pump();
      expect(incremented, true);
    });

    testWidgets('both buttons disabled when enabled: false', (tester) async {
      bool decremented = false;
      bool incremented = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustodyStepper(
              value: 5,
              min: 0,
              enabled: false,
              onDecrement: () => decremented = true,
              onIncrement: () => incremented = true,
            ),
          ),
        ),
      );

      // Tap decrement: should NOT fire (disabled).
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(decremented, false);

      // Tap increment: should NOT fire (disabled).
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(incremented, false);
    });

    testWidgets('decrement fires when value > min and enabled', (tester) async {
      bool decremented = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustodyStepper(
              value: 3,
              min: 0,
              onDecrement: () => decremented = true,
              onIncrement: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(decremented, true);
    });
  });
}
