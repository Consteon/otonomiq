// test/main_page_nav_route_test.dart
//
// MainPageState.navRouteAt -- bounds guard for the bottom-bar route lookup.
// Regression: handleNavTap read `systemUIComponent[mobile]['bottomBar'][i]`
// with the tap index of the bar that was PAINTED, while the global could have
// been reverted to the guest bar (1 item) in between -> RangeError on i >= 1.
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/page/main_page.dart';

void main() {
  Map<String, dynamic> sysUI(List<Map<String, dynamic>> bar) => {
        'Mobile': {'bottomBar': bar},
      };

  final List<Map<String, dynamic>> authedBar = [
    {'route': 'home'},
    {'route': 'inbox'},
    {'route': 'contact'},
    {'route': 'profile'},
  ];

  test('returns the route of the requested slot', () {
    expect(MainPageState.navRouteAt(sysUI(authedBar), 0), 'home');
    expect(MainPageState.navRouteAt(sysUI(authedBar), 3), 'profile');
  });

  test('guest bar (1 item) tapped at slot 3 returns empty, does not throw', () {
    expect(
      MainPageState.navRouteAt(
          sysUI([
            {'route': 'home'}
          ]),
          3),
      '',
    );
  });

  test('empty bar returns empty for slot 0', () {
    expect(MainPageState.navRouteAt(sysUI(const []), 0), '');
  });

  test('missing/!List bottomBar returns empty', () {
    expect(MainPageState.navRouteAt(<String, dynamic>{'Mobile': {}}, 0), '');
    expect(
      MainPageState.navRouteAt({
        'Mobile': {'bottomBar': 'not a list'}
      }, 0),
      '',
    );
    expect(MainPageState.navRouteAt(null, 0), '');
  });

  test('non-map entry or missing route key returns empty', () {
    expect(MainPageState.navRouteAt(sysUI(const []), -1), '');
    expect(
      MainPageState.navRouteAt({
        'Mobile': {
          'bottomBar': ['plain string']
        }
      }, 0),
      '',
    );
    expect(MainPageState.navRouteAt(sysUI([{}]), 0), '');
  });
}
