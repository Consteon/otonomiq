import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Upcoming task filter ────────────────────────────────────────────────
  //
  // Mirrors the filter in AdminUpcomingTaskList.build() Obx:
  //   for (final t in allTasks) {
  //     if (tst != 'assigned') continue;
  //     if (tdt != todayStr) continue;
  //     upcoming.add(t);
  //   }

  List<Map<String, dynamic>> filterUpcoming(
    List<Map<String, dynamic>> tasks,
    String schedField,
    String todayStr,
  ) {
    final List<Map<String, dynamic>> result = [];
    for (final t in tasks) {
      final String tst = (t['tst'] ?? '').toString().trim();
      if (tst != 'assigned') continue;
      final String tdt = (t[schedField] ?? '').toString().trim();
      if (tdt != todayStr) continue;
      result.add(t);
    }
    return result;
  }

  group('Upcoming task filter', () {
    const String today = '1782604800000';

    test('empty input -> empty result', () {
      expect(filterUpcoming([], 'tdt', today), isEmpty);
    });

    test('only assigned + today tasks pass', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'assigned', 'tdt': today, 'kn': 'A'},
        {'tst': 'on_delivery', 'tdt': today, 'kn': 'B'},
        {'tst': 'assigned', 'tdt': '9999', 'kn': 'C'},
        {'tst': 'assigned', 'tdt': today, 'kn': 'D'},
      ];
      final result = filterUpcoming(tasks, 'tdt', today);
      expect(result.length, 2);
      expect(result[0]['kn'], 'A');
      expect(result[1]['kn'], 'D');
    });

    test('completed and failed tasks filtered out', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'completed', 'tdt': today},
        {'tst': 'failed', 'tdt': today},
      ];
      expect(filterUpcoming(tasks, 'tdt', today), isEmpty);
    });

    test('config-driven schedField', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'assigned', 'myDate': today, 'tdt': '0000'},
      ];
      final result = filterUpcoming(tasks, 'myDate', today);
      expect(result.length, 1);
    });

    test('all non-matching -> empty (triggers emptyText path)', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'completed', 'tdt': today},
        {'tst': 'assigned', 'tdt': '0000'},
      ];
      expect(filterUpcoming(tasks, 'tdt', today), isEmpty);
    });

    test('missing tst field -> filtered out', () {
      final tasks = <Map<String, dynamic>>[
        {'tdt': today, 'kn': 'No status'},
      ];
      expect(filterUpcoming(tasks, 'tdt', today), isEmpty);
    });

    test('missing schedField -> filtered out', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'assigned', 'kn': 'No date'},
      ];
      expect(filterUpcoming(tasks, 'tdt', today), isEmpty);
    });
  });

  // ── emptyText config default ────────────────────────────────────────────
  //
  // Mirrors _parseConfig: cfgStr('emptyText', 'Tidak ada order...')

  group('emptyText config resolution', () {
    String resolveEmptyText(Map<String, dynamic>? component) {
      final String v =
          (component?['emptyText'] ?? '').toString().trim();
      return v.isNotEmpty ? v : 'Tidak ada order terjadwal hari ini';
    }

    test('absent key -> default', () {
      expect(resolveEmptyText({}),
          'Tidak ada order terjadwal hari ini');
    });

    test('null component -> default', () {
      expect(resolveEmptyText(null),
          'Tidak ada order terjadwal hari ini');
    });

    test('custom emptyText', () {
      expect(
        resolveEmptyText({'emptyText': 'No tasks'}),
        'No tasks',
      );
    });

    test('empty string -> default', () {
      expect(resolveEmptyText({'emptyText': ''}),
          'Tidak ada order terjadwal hari ini');
    });

    test('whitespace-only -> default', () {
      expect(resolveEmptyText({'emptyText': '   '}),
          'Tidak ada order terjadwal hari ini');
    });
  });
}
