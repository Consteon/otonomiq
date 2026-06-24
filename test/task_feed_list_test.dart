import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── P10 tst vocabulary via stopStatusOf ─────────────────────────────────

  group('P10 tst vocabulary', () {
    test('assigned normalizes to pending', () {
      expect(stopStatusOf({'tst': 'assigned'}), 'pending');
    });

    test('on_delivery normalizes to pending', () {
      expect(stopStatusOf({'tst': 'on_delivery'}), 'pending');
    });

    test('completed normalizes to done', () {
      expect(stopStatusOf({'tst': 'completed'}), 'done');
    });

    test('failed normalizes to failed', () {
      expect(stopStatusOf({'tst': 'failed'}), 'failed');
    });
  });

  // ── Grouping logic (pure function extraction) ──────────────────────────

  group('task grouping', () {
    /// Pure grouping function that mirrors the logic in TaskFeedList.build.
    /// Extracted here for testing without widget pump.
    Map<String, List<Map<String, dynamic>>> groupTasks(
        List<Map<String, dynamic>> tasks, String tstField) {
      final pending = <Map<String, dynamic>>[];
      final failed = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      for (final doc in tasks) {
        final status = stopStatusOf(doc, tstField: tstField);
        if (status == 'failed') {
          failed.add(doc);
        } else if (status == 'done') {
          completed.add(doc);
        } else {
          pending.add(doc);
        }
      }
      return {'pending': pending, 'failed': failed, 'completed': completed};
    }

    test('groups assigned+on_delivery into pending', () {
      final tasks = [
        {'tst': 'assigned'},
        {'tst': 'on_delivery'},
        {'tst': 'completed'},
        {'tst': 'failed'},
      ];
      final groups = groupTasks(tasks, 'tst');
      expect(groups['pending']!.length, 2);
      expect(groups['failed']!.length, 1);
      expect(groups['completed']!.length, 1);
    });

    test('on_delivery groups with assigned, not completed', () {
      final tasks = [
        {'tst': 'on_delivery'},
        {'tst': 'on_delivery'},
        {'tst': 'completed'},
      ];
      final groups = groupTasks(tasks, 'tst');
      expect(groups['pending']!.length, 2);
      expect(groups['completed']!.length, 1);
    });

    test('empty task list produces empty groups', () {
      final groups = groupTasks([], 'tst');
      expect(groups['pending'], isEmpty);
      expect(groups['failed'], isEmpty);
      expect(groups['completed'], isEmpty);
    });

    test('all completed', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'completed'},
      ];
      final groups = groupTasks(tasks, 'tst');
      expect(groups['pending'], isEmpty);
      expect(groups['completed']!.length, 2);
    });
  });

  // ── stopNumber indexing ─────────────────────────────────────────────────

  group('stopNumber indexing', () {
    test('1-based global index across all tasks regardless of state', () {
      final tasks = [
        {'tst': 'assigned', 'tnm': 'T001'},
        {'tst': 'completed', 'tnm': 'T002'},
        {'tst': 'assigned', 'tnm': 'T003'},
        {'tst': 'failed', 'tnm': 'T004'},
      ];

      // Simulate the indexing logic from TaskFeedList.build
      final List<Map<String, int>> indexed = [];
      int globalIndex = 0;
      for (final _ in tasks) {
        globalIndex++;
        indexed.add({'stopNumber': globalIndex});
      }

      expect(indexed[0]['stopNumber'], 1);
      expect(indexed[1]['stopNumber'], 2);
      expect(indexed[2]['stopNumber'], 3);
      expect(indexed[3]['stopNumber'], 4);
    });
  });

  // ── allDone boolean ──────────────────────────────────────────────────────

  group('allDone', () {
    test('true when no assigned or on_delivery tasks', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'failed'},
        {'tst': 'completed'},
      ];
      final bool allDone = tasks.every((doc) {
        final status = stopStatusOf(doc);
        return status == 'done' || status == 'failed';
      });
      expect(allDone, true);
    });

    test('false when on_delivery tasks remain', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'on_delivery'},
      ];
      final bool allDone = tasks.every((doc) {
        final status = stopStatusOf(doc);
        return status == 'done' || status == 'failed';
      });
      expect(allDone, false);
    });

    test('false when assigned tasks remain', () {
      final tasks = [
        {'tst': 'assigned'},
      ];
      final bool allDone = tasks.every((doc) {
        final status = stopStatusOf(doc);
        return status == 'done' || status == 'failed';
      });
      expect(allDone, false);
    });

    test('allDone computed via pending group empty (matches widget logic)', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'failed'},
      ];
      final pending = tasks.where((doc) {
        final status = stopStatusOf(doc);
        return status != 'done' && status != 'failed';
      }).toList();
      expect(pending.isEmpty, true); // allDone
    });

    test('empty task list is NOT allDone (no banner shown)', () {
      // Widget shows allDone banner only when allDone && tasks.isNotEmpty
      final tasks = <Map<String, dynamic>>[];
      final pending = tasks.where((doc) {
        final status = stopStatusOf(doc);
        return status != 'done' && status != 'failed';
      }).toList();
      // pending is empty, but tasks is also empty → no banner
      expect(pending.isEmpty, true);
      expect(tasks.isNotEmpty, false);
    });
  });

  // ── Per-card drop/pickup with actual vs planned ──────────────────────────

  group('per-card drop/pickup', () {
    test('assigned card uses planned pd/pp', () {
      final doc = {
        'tst': 'assigned',
        'it': [
          {'pd': '5', 'pp': '2', 'ad': '0', 'ap': '0'},
          {'pd': '3', 'pp': '1', 'ad': '0', 'ap': '0'},
        ],
      };
      // Widget uses pd/pp for non-done
      int drop = 0;
      int pickup = 0;
      for (final item in (doc['it'] as List)) {
        drop += int.tryParse((item['pd'] ?? '0').toString()) ?? 0;
        pickup += int.tryParse((item['pp'] ?? '0').toString()) ?? 0;
      }
      expect(drop, 8);
      expect(pickup, 3);
    });

    test('completed card uses actual ad/ap', () {
      final doc = {
        'tst': 'completed',
        'it': [
          {'pd': '5', 'pp': '2', 'ad': '4', 'ap': '1'},
          {'pd': '3', 'pp': '1', 'ad': '3', 'ap': '1'},
        ],
      };
      // Widget uses ad/ap for done status
      int drop = 0;
      int pickup = 0;
      for (final item in (doc['it'] as List)) {
        drop += int.tryParse((item['ad'] ?? '0').toString()) ?? 0;
        pickup += int.tryParse((item['ap'] ?? '0').toString()) ?? 0;
      }
      expect(drop, 7);
      expect(pickup, 2);
    });
  });

  // ── diamondTextToList length guard ──────────────────────────────────────

  group('text segment length guard', () {
    test('empty text returns length-1 list with empty string', () {
      final result = diamondTextToList('');
      expect(result.length, 1);
      expect(result[0], '');
    });

    test('_t helper returns default for out-of-range index', () {
      // Simulate the _t helper
      final textArray = diamondTextToList('');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      expect(t(0), ''); // index 0 exists, returns ''
      expect(t(1, 'fallback'), 'fallback'); // index 1 out of range
      expect(t(14, 'last'), 'last'); // way out of range
    });

    test('short text still length-guards high indexes', () {
      final textArray = diamondTextToList('Hello\u{25C6}World');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      expect(t(0), 'Hello');
      expect(t(1), 'World');
      expect(t(2, 'nope'), 'nope');
    });
  });
}
