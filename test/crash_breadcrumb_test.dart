import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

/// The whole point of the guard in [crashBreadcrumb] is that a breadcrumb can
/// never turn a navigation into a crash. `reloadPage` calls it on EVERY route
/// change, including ones that run before `Firebase.initializeApp` (startup
/// page load, notification cold-start) and before `transactionStore` exists.
///
/// This test runs with neither: no Firebase app, `transactionStore` still null.
/// `FirebaseCrashlytics.instance` throws synchronously in that state, so an
/// unguarded body would fail here — which is exactly the regression to catch.
void main() {
  test('crashBreadcrumb swallows a missing Firebase app', () {
    expect(() => crashBreadcrumb('driver_home'), returnsNormally);
  });

  test('crashBreadcrumb swallows an empty screen name', () {
    expect(() => crashBreadcrumb(''), returnsNormally);
  });
}
