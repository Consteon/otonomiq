// test/screen_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/screen_session.dart';

void main() {
  setUp(() {
    ScreenSession.resetForTest();
  });

  group('ensure', () {
    test('registers a new entry', () {
      bool called = false;
      ScreenSession.ensure('test.store', (scrName) => called = true);
      ScreenSession.navReset('anyScreen');
      expect(called, true);
    });

    test('is idempotent -- second call is ignored', () {
      int callCount = 0;
      ScreenSession.ensure('test.store', (scrName) => callCount++);
      ScreenSession.ensure('test.store', (scrName) => callCount += 100);
      ScreenSession.navReset('s');
      expect(callCount, 1); // first clearOne, not the second
    });

    test('asserts when nav:all without clearAllFn', () {
      expect(
        () => ScreenSession.ensure('bad', (_) {},
            nav: NavPolicy.all, clearAllFn: null),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('navReset', () {
    test('fires screen-policy entries with scrName', () {
      String? received;
      ScreenSession.ensure('a', (s) => received = s);
      ScreenSession.navReset('myScreen');
      expect(received, 'myScreen');
    });

    test('fires all-policy entries via clearAllFn', () {
      bool allCalled = false;
      ScreenSession.ensure('a', (_) {},
          nav: NavPolicy.all, clearAllFn: () => allCalled = true);
      ScreenSession.navReset('anyScreen');
      expect(allCalled, true);
    });

    test('skips none-policy entries', () {
      bool called = false;
      ScreenSession.ensure('a', (_) => called = true, nav: NavPolicy.none);
      ScreenSession.navReset('s');
      expect(called, false);
    });

    test('skips persistent entries', () {
      bool called = false;
      ScreenSession.ensure('a', (_) => called = true, persistent: true);
      ScreenSession.navReset('s');
      expect(called, false);
    });

    test('unknown scrName does not throw', () {
      // No entries registered at all
      expect(() => ScreenSession.navReset('unknown'), returnsNormally);
    });

    test('one throwing entry does not block the rest', () {
      bool secondCalled = false;
      ScreenSession.ensure('a', (_) => throw Exception('boom'));
      ScreenSession.ensure('b', (_) => secondCalled = true);
      ScreenSession.navReset('s');
      expect(secondCalled, true);
    });

    test('tolerates ensure() called during iteration', () {
      // clearOne of 'a' triggers ensure('late') mid-iteration
      ScreenSession.ensure('a', (_) {
        ScreenSession.ensure('late', (_) {});
      });
      // Must not throw ConcurrentModificationError
      expect(() => ScreenSession.navReset('s'), returnsNormally);
    });
  });

  group('pageBuild', () {
    test('fires screen-rebuild entries', () {
      String? received;
      ScreenSession.ensure('a', (s) => received = s);
      ScreenSession.pageBuild('myScreen');
      expect(received, 'myScreen');
    });

    test('skips none-rebuild entries', () {
      bool called = false;
      ScreenSession.ensure('a', (_) => called = true,
          rebuild: RebuildPolicy.none);
      ScreenSession.pageBuild('s');
      expect(called, false);
    });

    test('skips persistent entries', () {
      bool called = false;
      ScreenSession.ensure('a', (_) => called = true, persistent: true);
      ScreenSession.pageBuild('s');
      expect(called, false);
    });

    test('one throwing entry does not block the rest', () {
      bool secondCalled = false;
      ScreenSession.ensure('a', (_) => throw Exception('boom'));
      ScreenSession.ensure('b', (_) => secondCalled = true);
      ScreenSession.pageBuild('s');
      expect(secondCalled, true);
    });

    test('tolerates ensure() called during iteration', () {
      ScreenSession.ensure('a', (_) {
        ScreenSession.ensure('late', (_) {});
      });
      expect(() => ScreenSession.pageBuild('s'), returnsNormally);
    });
  });

  group('registrySnapshot', () {
    test('returns all registered entries with their policies', () {
      ScreenSession.ensure('x', (_) {}, nav: NavPolicy.all,
          clearAllFn: () {}, rebuild: RebuildPolicy.screen);
      ScreenSession.ensure('y', (_) {}, nav: NavPolicy.none,
          rebuild: RebuildPolicy.none, persistent: true);
      final snap = ScreenSession.registrySnapshot;
      expect(snap.length, 2);
      expect(snap['x']!.nav, NavPolicy.all);
      expect(snap['x']!.rebuild, RebuildPolicy.screen);
      expect(snap['x']!.persistent, false);
      expect(snap['y']!.nav, NavPolicy.none);
      expect(snap['y']!.rebuild, RebuildPolicy.none);
      expect(snap['y']!.persistent, true);
    });
  });

  group('map factory', () {
    test('returns a per-scrName map cleared by navReset', () {
      final store = ScreenSession.map<String, int>('test.map');
      store.putIfAbsent('scr1', () => <String, int>{});
      store['scr1']!['key'] = 42;

      ScreenSession.navReset('scr1');
      expect(store.containsKey('scr1'), false);
    });

    test('onEvict callback fires with removed map', () {
      Map<String, int>? evicted;
      final store = ScreenSession.map<String, int>('test.map',
          onEvict: (_, m) => evicted = m);
      store['s'] = {'a': 1};
      ScreenSession.navReset('s');
      expect(evicted, {'a': 1});
    });
  });
}
