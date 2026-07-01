import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/picker_list.dart';
import 'package:otonomiq/widget/panel_card_support.dart'; // panelIcon

void main() {
  // Sample stock_location docs: 3 vehicles (1 inactive) + 1 client + warehouse.
  final List<Map<String, dynamic>> stock = [
    {'lv': 'V1', 'ln': 'B 1234 XY', 'ty': 'Box', 'lt': 'vehicle', 'lst': 'active'},
    {'lv': 'V2', 'ln': 'B 5678 ZZ', 'ty': 'Pickup', 'lt': 'vehicle', 'lst': 'active'},
    {'lv': 'V3', 'ln': 'D 9999 AA', 'ty': 'Van', 'lt': 'vehicle', 'lst': 'idle'},
    {'lv': 'C1', 'ln': 'Toko Maju', 'ty': '', 'lt': 'client', 'lst': 'active'},
    {'lv': 'W1', 'ln': 'Gudang A', 'ty': '', 'lt': 'warehouse', 'lst': 'active'},
  ];

  // ── filterRows (generic, no entity fallback) ────────────────────────────
  group('PickerList.filterRows', () {
    test('empty search returns ALL docs (no entity fallback)', () {
      final r = PickerList.filterRows(stock, '');
      expect(r.length, stock.length);
    });

    test('whitespace-only search returns all', () {
      expect(PickerList.filterRows(stock, '   ').length, stock.length);
    });

    test('single-clause gate "lt◼vehicle"', () {
      final r = PickerList.filterRows(stock, 'lt\u{25FC}vehicle');
      expect(r.map((d) => d['lv']), ['V1', 'V2', 'V3']);
    });

    test('AND gate "lt◼vehicle⭘lst◼active" drops the idle vehicle', () {
      final r = PickerList.filterRows(
          stock, 'lt\u{25FC}vehicle\u{2B58}lst\u{25FC}active');
      expect(r.map((d) => d['lv']), ['V1', 'V2']);
    });

    test('server-encoded gate (_25FC_ ◼ / _u2B58_ ⭘) decodes', () {
      final r = PickerList.filterRows(
          stock, 'lt_25FC_vehicle_u2B58_lst_25FC_active');
      expect(r.map((d) => d['lv']), ['V1', 'V2']);
    });

    test('gate matching nothing returns empty', () {
      expect(PickerList.filterRows(stock, 'lt\u{25FC}drone'), isEmpty);
    });

    test('client picker reuse: "lt◼client"', () {
      final r = PickerList.filterRows(stock, 'lt\u{25FC}client');
      expect(r.length, 1);
      expect(r[0]['lv'], 'C1');
    });

    test('empty source returns empty', () {
      expect(PickerList.filterRows([], 'lt\u{25FC}vehicle'), isEmpty);
    });
  });

  // ── countForRow (per-row badge) ─────────────────────────────────────────
  group('PickerList.countForRow', () {
    final List<Map<String, dynamic>> tasks = [
      {'tnm': 'T1', 'vv': 'V1', 'tst': 'assigned'},
      {'tnm': 'T2', 'vv': 'V1', 'tst': 'assigned'},
      {'tnm': 'T3', 'vv': 'V1', 'tst': 'done'},
      {'tnm': 'T4', 'vv': 'V2', 'tst': 'assigned'},
    ];

    test('counts docs matching countSearch with {lv} -> rowId', () {
      final n = PickerList.countForRow(
          tasks, 'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}assigned', 'lv', 'V1');
      expect(n, 2); // T1, T2 (T3 is done)
    });

    test('different row id yields its own count', () {
      final n = PickerList.countForRow(
          tasks, 'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}assigned', 'lv', 'V2');
      expect(n, 1);
    });

    test('row with no matching docs counts 0', () {
      final n = PickerList.countForRow(
          tasks, 'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}assigned', 'lv', 'V9');
      expect(n, 0);
    });

    test('server-encoded countSearch decodes then counts', () {
      final n = PickerList.countForRow(
          tasks, 'vv_25FC_{lv}_u2B58_tst_25FC_assigned', 'lv', 'V1');
      expect(n, 2);
    });

    test('empty countSearch -> 0 (no badge)', () {
      expect(PickerList.countForRow(tasks, '', 'lv', 'V1'), 0);
    });

    test('empty rowId -> 0 (cannot resolve token)', () {
      final n = PickerList.countForRow(
          tasks, 'vv\u{25FC}{lv}', 'lv', '');
      expect(n, 0);
    });

    test('unresolved leftover token -> 0 (guards against counting-all)', () {
      // countSearch references {warehouse} but idField token is {lv} -> leftover.
      final n = PickerList.countForRow(
          tasks, 'vv\u{25FC}{lv}\u{2B58}gl\u{25FC}{warehouse}', 'lv', 'V1');
      expect(n, 0);
    });

    test('custom idField token name is substituted', () {
      final fleets = [
        {'fid': 'F1', 'wid': 'W1'},
        {'fid': 'F2', 'wid': 'W1'},
      ];
      final n = PickerList.countForRow(
          fleets, 'wid\u{25FC}{wid}', 'wid', 'W1');
      expect(n, 2);
    });
  });

  // ── resolveCaptureToken ─────────────────────────────────────────────────
  group('PickerList.resolveCaptureToken', () {
    test('absent -> default vv', () {
      expect(PickerList.resolveCaptureToken(<String, dynamic>{}), 'vv');
    });

    test('empty/whitespace -> default vv', () {
      expect(PickerList.resolveCaptureToken({'captureToken': '  '}), 'vv');
    });

    test('explicit honored + trimmed (vehicleId)', () {
      expect(
        PickerList.resolveCaptureToken({'captureToken': ' vehicleId '}),
        'vehicleId',
      );
    });

    test('explicit honored (kl) for customer picker', () {
      expect(PickerList.resolveCaptureToken({'captureToken': 'kl'}), 'kl');
    });
  });

  // ── resolveIdField ──────────────────────────────────────────────────────
  group('PickerList.resolveIdField', () {
    test('absent -> default lv', () {
      expect(PickerList.resolveIdField(<String, dynamic>{}), 'lv');
    });

    test('empty -> default lv', () {
      expect(PickerList.resolveIdField({'idField': ''}), 'lv');
    });

    test('explicit honored + trimmed', () {
      expect(PickerList.resolveIdField({'idField': ' wid '}), 'wid');
    });
  });

  // ── countForRow for statusSearch (status pill) ─────────────────────────

  group('PickerList.countForRow statusSearch', () {
    final List<Map<String, dynamic>> taskDocs = [
      {'tnm': 'T1', 'vv': 'V1', 'tst': 'on_delivery'},
      {'tnm': 'T2', 'vv': 'V1', 'tst': 'assigned'},
      {'tnm': 'T3', 'vv': 'V2', 'tst': 'on_delivery'},
      {'tnm': 'T4', 'vv': 'V3', 'tst': 'assigned'},
    ];

    test('V1 has 1 on_delivery task -> On Route (count > 0)', () {
      final int n = PickerList.countForRow(
          taskDocs,
          'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}on_delivery',
          'lv',
          'V1');
      expect(n, 1); // T1 only (T2 is assigned)
    });

    test('V2 has 1 on_delivery task -> On Route', () {
      final int n = PickerList.countForRow(
          taskDocs,
          'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}on_delivery',
          'lv',
          'V2');
      expect(n, 1);
    });

    test('V3 has 0 on_delivery -> Available (count == 0)', () {
      final int n = PickerList.countForRow(
          taskDocs,
          'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}on_delivery',
          'lv',
          'V3');
      expect(n, 0); // V3 has assigned only, not on_delivery
    });

    test('unknown vehicle -> 0 (Available)', () {
      final int n = PickerList.countForRow(
          taskDocs,
          'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}on_delivery',
          'lv',
          'V99');
      expect(n, 0);
    });

    test('server-encoded statusSearch decodes', () {
      final int n = PickerList.countForRow(
          taskDocs,
          'vv_25FC_{lv}_u2B58_tst_25FC_on_delivery',
          'lv',
          'V1');
      expect(n, 1);
    });

    test('empty statusSearch -> 0 (no pill rendered)', () {
      expect(PickerList.countForRow(taskDocs, '', 'lv', 'V1'), 0);
    });

    test('empty task docs -> 0 (Available)', () {
      expect(
        PickerList.countForRow(
            <Map<String, dynamic>>[],
            'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}on_delivery',
            'lv',
            'V1'),
        0,
      );
    });
  });

  // ── parseHexColor ──────────────────────────────────────────────────────

  group('PickerList.parseHexColor', () {
    test('null -> null', () {
      expect(PickerList.parseHexColor(null), isNull);
    });

    test('empty string -> null', () {
      expect(PickerList.parseHexColor(''), isNull);
    });

    test('whitespace only -> null', () {
      expect(PickerList.parseHexColor('   '), isNull);
    });

    test('"0xFF2563EB" -> Color(0xFF2563EB)', () {
      expect(PickerList.parseHexColor('0xFF2563EB'), const Color(0xFF2563EB));
    });

    test('"0xff2563eb" lowercase -> Color(0xFF2563EB)', () {
      expect(PickerList.parseHexColor('0xff2563eb'), const Color(0xFF2563EB));
    });

    test('"FF2563EB" no prefix -> Color(0xFF2563EB)', () {
      expect(PickerList.parseHexColor('FF2563EB'), const Color(0xFF2563EB));
    });

    test('"2563EB" 6-char RGB -> Color(0xFF2563EB) (alpha FF prepended)', () {
      expect(PickerList.parseHexColor('2563EB'), const Color(0xFF2563EB));
    });

    test('"#2563EB" hash prefix -> Color(0xFF2563EB)', () {
      expect(PickerList.parseHexColor('#2563EB'), const Color(0xFF2563EB));
    });

    test('"#ff2563eb" hash + lowercase -> Color(0xFF2563EB)', () {
      expect(PickerList.parseHexColor('#ff2563eb'), const Color(0xFF2563EB));
    });

    test('invalid hex "xyz" -> null', () {
      expect(PickerList.parseHexColor('xyz'), isNull);
    });

    test('"0x" alone -> null (empty after stripping prefix)', () {
      expect(PickerList.parseHexColor('0x'), isNull);
    });

    test('trims whitespace before parsing', () {
      expect(PickerList.parseHexColor('  0xFF047857  '), const Color(0xFF047857));
    });

    test('"0xFF0D9488" -> Color(0xFF0D9488) (teal)', () {
      expect(PickerList.parseHexColor('0xFF0D9488'), const Color(0xFF0D9488));
    });
  });

  // ── panelIcon truck/vehicle entries ─────────────────────────────────────

  group('panelIcon truck/vehicle', () {
    test('truck resolves to local_shipping_rounded', () {
      expect(panelIcon('truck'), Icons.local_shipping_rounded);
    });

    test('vehicle resolves to local_shipping_rounded', () {
      expect(panelIcon('vehicle'), Icons.local_shipping_rounded);
    });

    test('truck is case-insensitive', () {
      expect(panelIcon('Truck'), Icons.local_shipping_rounded);
      expect(panelIcon('TRUCK'), Icons.local_shipping_rounded);
    });

    test('vehicle is case-insensitive', () {
      expect(panelIcon('Vehicle'), Icons.local_shipping_rounded);
    });

    test('unknown still falls back to dashboard_rounded', () {
      expect(panelIcon('helicopter'), Icons.dashboard_rounded);
    });

    test('existing entries unaffected', () {
      expect(panelIcon('users'), Icons.people_alt_rounded);
      expect(panelIcon('clipboard-check'), Icons.fact_check_rounded);
      expect(panelIcon('map-pin'), Icons.location_on_rounded);
      expect(panelIcon('clock'), Icons.schedule_rounded);
      expect(panelIcon('info'), Icons.info_outline_rounded);
      expect(panelIcon('alert'), Icons.warning_amber_rounded);
    });
  });

  // ── hasStatusOrBadge (entity-mode helper) ──────────────────────────────

  group('hasStatusOrBadge (entity-mode helper)', () {
    test('both null -> false', () {
      expect(hasStatusOrBadge(null, null), false);
    });

    test('statusLabel empty, badge null -> false', () {
      expect(hasStatusOrBadge('', null), false);
    });

    test('statusLabel non-empty, badge null -> true', () {
      expect(hasStatusOrBadge('Available', null), true);
    });

    test('statusLabel null, badge non-null -> true', () {
      expect(hasStatusOrBadge(null, '3 task'), true);
    });

    test('both present -> true', () {
      expect(hasStatusOrBadge('On Route', '2 task'), true);
    });
  });

  // ── selectionFromToken (per-build highlight derivation) ────────────────

  group('PickerList.selectionFromToken', () {
    test('non-empty string -> that value', () {
      expect(PickerList.selectionFromToken('V1'), 'V1');
    });

    test('string with whitespace -> trimmed value', () {
      expect(PickerList.selectionFromToken(' V1 '), 'V1');
    });

    test('empty string -> null (no highlight)', () {
      expect(PickerList.selectionFromToken(''), isNull);
    });

    test('whitespace only -> null', () {
      expect(PickerList.selectionFromToken('   '), isNull);
    });

    test('null -> null', () {
      expect(PickerList.selectionFromToken(null), isNull);
    });

    test('non-string dynamic (int) -> toString then derive', () {
      expect(PickerList.selectionFromToken(42), '42');
    });
  });
}
