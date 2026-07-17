import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── listActiveWarehouses ─────────────────────────────────────────────────

  group('listActiveWarehouses', () {
    test('empty list -> empty result', () {
      expect(listActiveWarehouses(const <Map<String, dynamic>>[]), isEmpty);
    });

    test('no warehouse docs -> empty result', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'lst': 'active', 'lv': 'VEH-1', 'ln': 'B1'},
        {'lt': 'client', 'lst': 'active', 'lv': 'C-1', 'ln': 'Honda'},
      ];
      expect(listActiveWarehouses(docs), isEmpty);
    });

    test('warehouse with lst!=active is skipped', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'inactive', 'lv': 'WH-OLD', 'ln': 'Old'},
      ];
      expect(listActiveWarehouses(docs), isEmpty);
    });

    test('warehouse with empty lv is skipped', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'active', 'lv': '', 'ln': 'No-ID'},
      ];
      expect(listActiveWarehouses(docs), isEmpty);
    });

    test('warehouse with missing lst field is skipped (empty != active)', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lv': 'WH-1', 'ln': 'Missing Status'},
      ];
      expect(listActiveWarehouses(docs), isEmpty);
    });

    test('exactly 1 active warehouse -> single-element list', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'lst': 'active', 'lv': 'VEH-1', 'ln': 'B1'},
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-JKT-01', 'ln': 'Gudang Jakarta'},
        {'lt': 'warehouse', 'lst': 'inactive', 'lv': 'WH-OLD', 'ln': 'Old'},
      ];
      final result = listActiveWarehouses(docs);
      expect(result.length, 1);
      expect(result.first, {'lv': 'WH-JKT-01', 'ln': 'Gudang Jakarta'});
    });

    test('>1 active warehouses -> returns all', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-A', 'ln': 'Gudang A'},
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-B', 'ln': 'Gudang B'},
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-C', 'ln': 'Gudang C'},
      ];
      final result = listActiveWarehouses(docs);
      expect(result.length, 3);
      expect(result[0], {'lv': 'WH-A', 'ln': 'Gudang A'});
      expect(result[1], {'lv': 'WH-B', 'ln': 'Gudang B'});
      expect(result[2], {'lv': 'WH-C', 'ln': 'Gudang C'});
    });

    test('empty ln is preserved (not skipped)', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-X', 'ln': ''},
      ];
      final result = listActiveWarehouses(docs);
      expect(result.length, 1);
      expect(result.first, {'lv': 'WH-X', 'ln': ''});
    });

    test('dynamic field values are .toString().trim() safe', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'active', 'lv': 123, 'ln': 456},
      ];
      final result = listActiveWarehouses(docs);
      expect(result.length, 1);
      expect(result.first, {'lv': '123', 'ln': '456'});
    });

    test('null field values treated as empty', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'active', 'lv': null, 'ln': null},
      ];
      // lv is empty after null -> '' -> skipped
      expect(listActiveWarehouses(docs), isEmpty);
    });

    test('whitespace-only fields are trimmed', () {
      final docs = <Map<String, dynamic>>[
        {'lt': ' warehouse ', 'lst': ' active ', 'lv': '  WH-TRIM  ', 'ln': '  Trimmed  '},
      ];
      final result = listActiveWarehouses(docs);
      expect(result.length, 1);
      expect(result.first, {'lv': 'WH-TRIM', 'ln': 'Trimmed'});
    });

    test('custom field names', () {
      final docs = <Map<String, dynamic>>[
        {'type': 'gudang', 'status': 'aktif', 'id': 'G-1', 'name': 'Gudang 1'},
      ];
      final result = listActiveWarehouses(
        docs,
        typeField: 'type',
        typeValue: 'gudang',
        statusField: 'status',
        statusValue: 'aktif',
        idField: 'id',
        nameField: 'name',
      );
      expect(result.length, 1);
      expect(result.first, {'lv': 'G-1', 'ln': 'Gudang 1'});
    });

    test('mixed: only active warehouses with non-empty lv survive', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-OK', 'ln': 'Good'},
        {'lt': 'warehouse', 'lst': 'inactive', 'lv': 'WH-OLD', 'ln': 'Old'},
        {'lt': 'vehicle', 'lst': 'active', 'lv': 'VEH-1', 'ln': 'Van'},
        {'lt': 'warehouse', 'lst': 'active', 'lv': '', 'ln': 'Empty ID'},
        {'lt': 'warehouse', 'lst': 'active', 'lv': 'WH-2', 'ln': 'Second'},
      ];
      final result = listActiveWarehouses(docs);
      expect(result.length, 2);
      expect(result[0]['lv'], 'WH-OK');
      expect(result[1]['lv'], 'WH-2');
    });
  });
}
