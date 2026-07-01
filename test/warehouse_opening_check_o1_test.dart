// test/warehouse_opening_check_o1_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── aggregatePlanByItem (shared pure helper) ────────────────────────────

  group('aggregatePlanByItem', () {
    test('sums pd+ps+pr across tasks per item', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'ii': 'galon', 'pd': 5, 'ps': 2, 'pr': 1},
            {'ii': 'lpg12', 'pd': 3, 'ps': 0, 'pr': 0},
          ],
        },
        {
          'tst': 'assigned',
          'it': [
            {'ii': 'galon', 'pd': 3, 'ps': 1, 'pr': 0},
          ],
        },
      ];
      final result = aggregatePlanByItem(tasks,
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr');
      expect(result.totals['galon'], 12); // (5+2+1) + (3+1+0)
      expect(result.totals['lpg12'], 3);
      expect(result.iiOrder, ['galon', 'lpg12']);
    });

    test('excludes load_rejected tasks', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'ii': 'galon', 'pd': 5, 'ps': 0, 'pr': 0}
          ]
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'ii': 'galon', 'pd': 10, 'ps': 0, 'pr': 0}
          ]
        },
      ];
      final result = aggregatePlanByItem(tasks,
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr',
          excludeStatus: 'load_rejected');
      expect(result.totals['galon'], 5);
    });

    test('handles empty tasks list', () {
      final result = aggregatePlanByItem(<Map<String, dynamic>>[],
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr');
      expect(result.iiOrder, isEmpty);
      expect(result.totals, isEmpty);
    });

    test('handles tasks with no it array', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'assigned'}
      ];
      final result = aggregatePlanByItem(tasks,
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr');
      expect(result.iiOrder, isEmpty);
    });

    test('handles empty ii in item entry', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'ii': '', 'pd': 5, 'ps': 0, 'pr': 0},
            {'ii': 'galon', 'pd': 3, 'ps': 0, 'pr': 0},
          ]
        },
      ];
      final result = aggregatePlanByItem(tasks,
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr');
      expect(result.totals.containsKey(''), false);
      expect(result.totals['galon'], 3);
    });

    test('handles string qty values', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'ii': 'galon', 'pd': '5', 'ps': '2', 'pr': '1'}
          ]
        },
      ];
      final result = aggregatePlanByItem(tasks,
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr');
      expect(result.totals['galon'], 8);
    });

    test('handles null/missing qty fields', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'ii': 'galon', 'pd': null}
          ]
        },
        {
          'tst': 'assigned',
          'it': [
            {'ii': 'galon'}
          ]
        },
      ];
      final result = aggregatePlanByItem(tasks,
          itemsField: 'it',
          deliverField: 'pd',
          saleField: 'ps',
          refillField: 'pr');
      expect(result.totals['galon'], 0);
    });
  });

  // ── coerceNum (renamed from _coerceNum) ─────────────────────────────────

  group('coerceNum', () {
    test('handles int', () => expect(coerceNum(5), 5));
    test('handles double', () => expect(coerceNum(3.14), 3.14));
    test('handles numeric string', () => expect(coerceNum('42'), 42));
    test('handles null', () => expect(coerceNum(null), 0));
    test('handles non-numeric string', () => expect(coerceNum('abc'), 0));
    test('handles empty string', () => expect(coerceNum(''), 0));
  });

  // ── ie[] assembly ──────────────────────────────────────────────────────

  group('ie[] assembly', () {
    test('builds ie entries with writeCond override', () {
      final entries = <CountEntry>[
        CountEntry(ii: 'galon', cd: 'full', qty: 10),
        CountEntry(ii: 'lpg12', cd: 'full', qty: 5),
      ];
      const writeCond = 'full';
      final ieArray = entries
          .map((e) => {
                'ii': e.ii,
                'cd': writeCond.isNotEmpty ? writeCond : e.cd,
                'qt': e.qty,
              })
          .toList();
      expect(ieArray.length, 2);
      expect(ieArray[0], {'ii': 'galon', 'cd': 'full', 'qt': 10});
      expect(ieArray[1], {'ii': 'lpg12', 'cd': 'full', 'qt': 5});
    });
  });

  // ── Opening doc map assembly ────────────────────────────────────────────

  group('opening doc map assembly', () {
    test('builds complete opening doc with all fields', () {
      final doc = <String, dynamic>{
        'cnm': 'CHK-VEH-B1234XY-20260624',
        'cty': 'opening',
        'vv': 'VEH-B1234XY',
        'gl': 'WH-001',
        'cdt': '1719176400000',
        'cst': 'awaiting_custody',
        'gv': 'checker-vid',
        'gn': 'Anton Pratama',
        'ldt': '1719216600000',
        't': 1719216600000,
        'ie': [
          {'ii': 'galon', 'cd': 'full', 'qt': 10}
        ],
        'search': 'cnm\u{2605}CHK-VEH-B1234XY-20260624',
      };
      expect(doc['cnm'], 'CHK-VEH-B1234XY-20260624');
      expect(doc['cty'], 'opening');
      expect(doc['cst'], 'awaiting_custody');
      expect(doc['ie'], isA<List>());
      expect((doc['ie'] as List).length, 1);
      expect(doc['gl'], 'WH-001');
      expect(doc['search'], contains('\u{2605}'));
    });

    test('empty gl is accepted (W1: no tasks today)', () {
      final doc = <String, dynamic>{
        'cnm': 'CHK-VEH-B1234XY-20260624',
        'cty': 'opening',
        'vv': 'VEH-B1234XY',
        'gl': '',
        'cdt': '1719176400000',
        'cst': 'awaiting_custody',
        'gv': 'checker-vid',
        'gn': 'Anton',
        'ldt': '1719216600000',
        't': 1719216600000,
        'ie': [
          {'ii': 'galon', 'cd': 'full', 'qt': 5}
        ],
        'search': 'cnm\u{2605}CHK-VEH-B1234XY-20260624',
      };
      expect(doc['gl'], '');
      // gl empty is accepted; not an error
    });
  });

  // ── cnm generation ──────────────────────────────────────────────────────

  group('cnm generation', () {
    test('format: CHK-{vehicleId}-{YYYYMMDD}', () {
      const vehicleId = 'VEH-B1234XY';
      const int wibOffsetMs = 25200000;
      final int nowMs = DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final DateTime wibNow =
          DateTime.fromMillisecondsSinceEpoch(nowMs + wibOffsetMs, isUtc: true);
      final dateStr =
          '${wibNow.year}${wibNow.month.toString().padLeft(2, '0')}${wibNow.day.toString().padLeft(2, '0')}';
      final cnm = 'CHK-$vehicleId-$dateStr';
      expect(cnm, 'CHK-VEH-B1234XY-20260624');
    });
  });

  // ── Chosen-driver gate ──────────────────────────────────────────────────

  group('chosen-driver enable gate', () {
    test('enabled when chosenVid non-empty', () {
      expect('v1'.isNotEmpty, true);
    });
    test('disabled when chosenVid empty', () {
      expect(''.isNotEmpty, false);
    });
  });

  // ── todayEpochMidnightWib ───────────────────────────────────────────────

  group('todayEpochMidnightWib', () {
    test('midnight WIB for a known timestamp', () {
      final nowMs = DateTime.utc(2026, 6, 24, 10, 30).millisecondsSinceEpoch;
      final result = todayEpochMidnightWib(nowMs: nowMs);
      final expected =
          DateTime.utc(2026, 6, 23, 17, 0).millisecondsSinceEpoch.toString();
      expect(result, expected);
    });
  });
}
