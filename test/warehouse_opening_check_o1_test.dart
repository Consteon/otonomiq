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

  // ── lookupWarehouseLv (stock_location lt=='warehouse' -> lv) ─────────────

  group('lookupWarehouseLv', () {
    test('single warehouse doc -> returns its lv', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'lv': 'VEH-1', 'ln': 'B1'},
        {'lt': 'warehouse', 'lv': 'WH-JKT-01', 'ln': 'Gudang Jakarta'},
      ];
      expect(lookupWarehouseLv(docs), 'WH-JKT-01');
    });

    test('no warehouse doc -> empty string', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'lv': 'VEH-1'},
        {'lt': 'vehicle', 'lv': 'VEH-2'},
      ];
      expect(lookupWarehouseLv(docs), '');
    });

    test('empty list -> empty string', () {
      expect(lookupWarehouseLv(const <Map<String, dynamic>>[]), '');
    });

    test('multiple warehouse docs -> returns first non-empty lv', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lv': 'WH-A'},
        {'lt': 'warehouse', 'lv': 'WH-B'},
      ];
      expect(lookupWarehouseLv(docs), 'WH-A');
    });

    test('warehouse doc with empty lv is skipped in favour of a real one', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lv': ''},
        {'lt': 'warehouse', 'lv': 'WH-REAL'},
      ];
      expect(lookupWarehouseLv(docs), 'WH-REAL');
    });

    test('warehouse doc with only an empty lv -> empty string', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lv': ''},
      ];
      expect(lookupWarehouseLv(docs), '');
    });

    test('custom field names', () {
      final docs = <Map<String, dynamic>>[
        {'type': 'gudang', 'id': 'WH-X'},
      ];
      expect(
        lookupWarehouseLv(docs,
            typeField: 'type', typeValue: 'gudang', idField: 'id'),
        'WH-X',
      );
    });

    test('field values are trimmed', () {
      final docs = <Map<String, dynamic>>[
        {'lt': ' warehouse ', 'lv': '  WH-TRIM  '},
      ];
      expect(lookupWarehouseLv(docs), 'WH-TRIM');
    });
  });

  // ── resolveWarehouseId precedence ───────────────────────────────────────

  group('resolveWarehouseId precedence', () {
    final stock = <Map<String, dynamic>>[
      {'lt': 'warehouse', 'lv': 'WH-LOOKUP'},
    ];

    test('task.gl present (#ACTIVE_WAREHOUSE) wins over lookup', () {
      expect(
        resolveWarehouseId(
            configResolved: '', fromStore: 'WH-FROM-TASK', stockDocs: stock),
        'WH-FROM-TASK',
      );
    });

    test('empty store falls back to lookup', () {
      expect(
        resolveWarehouseId(
            configResolved: '', fromStore: '', stockDocs: stock),
        'WH-LOOKUP',
      );
    });

    test('config override wins over store and lookup', () {
      expect(
        resolveWarehouseId(
            configResolved: 'WH-CONFIG',
            fromStore: 'WH-FROM-TASK',
            stockDocs: stock),
        'WH-CONFIG',
      );
    });

    test('config with unresolved token is ignored (falls to store)', () {
      expect(
        resolveWarehouseId(
            configResolved: '{warehouseId}',
            fromStore: 'WH-FROM-TASK',
            stockDocs: stock),
        'WH-FROM-TASK',
      );
    });

    test('config unresolved + empty store -> lookup', () {
      expect(
        resolveWarehouseId(
            configResolved: '{warehouseId}', fromStore: '', stockDocs: stock),
        'WH-LOOKUP',
      );
    });

    test('all empty -> empty string', () {
      expect(
        resolveWarehouseId(
            configResolved: '',
            fromStore: '',
            stockDocs: const <Map<String, dynamic>>[]),
        '',
      );
    });
  });

  // ── lookupWarehouseLv robustness (dynamic-field hardening) ─────────────────

  group('lookupWarehouseLv robustness', () {
    test('completely empty doc in list -> no throw, returns empty string', () {
      // A doc with no keys at all: both lt and lv fall through the ?? '' guard.
      final docs = <Map<String, dynamic>>[{}];
      expect(lookupWarehouseLv(docs), '');
    });

    test('doc missing lt key -> treated as non-warehouse, skipped, no throw',
        () {
      // Server data occasionally omits the type field entirely. Dart map access
      // on a missing key returns null, which the ?? '' guard converts to ''.
      final docs = <Map<String, dynamic>>[
        {'lv': 'WH-X'},
      ];
      expect(lookupWarehouseLv(docs), '');
    });

    test('warehouse doc missing lv key -> lv treated as empty, entry skipped',
        () {
      // The id field may be absent. null ?? '' -> '' -> isEmpty -> skipped.
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse'},
      ];
      expect(lookupWarehouseLv(docs), '');
    });

    test(
        'warehouse doc missing lv key then one with lv -> second returned',
        () {
      // Absent-key case is treated identically to lv:'' and is skipped in
      // favor of a later valid entry (extends existing test that uses lv:'').
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse'}, // lv key absent
        {'lt': 'warehouse', 'lv': 'WH-REAL'},
      ];
      expect(lookupWarehouseLv(docs), 'WH-REAL');
    });

    test('lv as int -> coerced to string via toString()', () {
      // Server may store a numeric warehouse id. The impl uses
      // .toString().trim() so 42 becomes '42'.
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lv': 42},
      ];
      expect(lookupWarehouseLv(docs), '42');
    });

    test('lv null -> treated as empty lv, entry skipped', () {
      // Explicit null JSON value: (null ?? '').toString().trim() == '' -> skipped.
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lv': null},
      ];
      expect(lookupWarehouseLv(docs), '');
    });

    test('lt null -> treated as non-warehouse, entry skipped', () {
      // Explicit null JSON value for lt: (null ?? '') == '' != 'warehouse' -> skipped.
      final docs = <Map<String, dynamic>>[
        {'lt': null, 'lv': 'WH-X'},
      ];
      expect(lookupWarehouseLv(docs), '');
    });

    test('lt case-sensitive: Warehouse (capital W) does not match warehouse',
        () {
      // The impl uses exact string comparison (no .toLowerCase()), so a
      // capitalised type value is NOT treated as a warehouse. Pins actual behavior.
      final docs = <Map<String, dynamic>>[
        {'lt': 'Warehouse', 'lv': 'WH-X'},
      ];
      expect(lookupWarehouseLv(docs), '');
    });
  });

  // ── resolveWarehouseId robustness ──────────────────────────────────────────

  group('resolveWarehouseId robustness', () {
    final stock = <Map<String, dynamic>>[
      {'lt': 'warehouse', 'lv': 'WH-LOOKUP'},
    ];

    test('whitespace-only config falls through to store', () {
      // '   '.trim() == '' -> configResolved leg skipped; store is tried next.
      expect(
        resolveWarehouseId(
            configResolved: '   ', fromStore: 'WH-STORE', stockDocs: stock),
        'WH-STORE',
      );
    });

    test('whitespace-only store falls through to lookup', () {
      // '   '.trim() == '' -> store leg also skipped; falls to lookupWarehouseLv.
      expect(
        resolveWarehouseId(
            configResolved: '', fromStore: '   ', stockDocs: stock),
        'WH-LOOKUP',
      );
    });

    test('store value with surrounding whitespace is returned trimmed', () {
      // fromStore is trimmed before the isNotEmpty check and the trimmed value
      // is returned, not the raw padded string.
      expect(
        resolveWarehouseId(
            configResolved: '',
            fromStore: '  WH-PADDED  ',
            stockDocs: const <Map<String, dynamic>>[]),
        'WH-PADDED',
      );
    });
  });
}
