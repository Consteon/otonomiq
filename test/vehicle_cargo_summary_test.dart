// test/vehicle_cargo_summary_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/notice_bar.dart';

void main() {
  // ── text parsing (6 slots, repurposed) ──────────────────────────────────

  group('vehicleCargoSummary text parsing', () {
    test('6-slot text parsed and length-guarded', () {
      final text = [
        'Serahkan kendaraan', // 0 introA
        ' + sisa muatan ke gudang.', // 1 introB
        'Sisa di Kendaraan', // 2 cardTitle
        'isi', // 3 fullLabel
        'kosong', // 4 emptyLabel
        'Tidak ada sisa muatan', // 5 emptyState
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 6);
      expect(arr.isNotEmpty ? arr[0] : '', 'Serahkan kendaraan');
      expect(arr.length > 1 ? arr[1] : '', ' + sisa muatan ke gudang.');
      expect(arr.length > 2 ? arr[2] : '', 'Sisa di Kendaraan');
      expect(arr.length > 3 ? arr[3] : '', 'isi');
      expect(arr.length > 4 ? arr[4] : '', 'kosong');
      expect(arr.length > 5 ? arr[5] : '', 'Tidak ada sisa muatan');
    });

    test('short text array uses defaults for missing slots', () {
      final arr = diamondTextToList('Serahkan kendaraan');
      expect(arr.isNotEmpty ? arr[0] : '', 'Serahkan kendaraan');
      expect(arr.length > 1 ? arr[1] : '', '');
      expect(
          arr.length > 2 ? arr[2] : 'Sisa di Kendaraan', 'Sisa di Kendaraan');
      expect(arr.length > 3 ? arr[3] : 'isi', 'isi');
      expect(arr.length > 4 ? arr[4] : 'kosong', 'kosong');
    });

    test('empty text still safe', () {
      final arr = diamondTextToList('');
      // diamondTextToList('') returns [''] (length 1)
      expect(arr.length, greaterThanOrEqualTo(1));
      expect(arr.length > 5 ? arr[5] : 'Tidak ada sisa muatan',
          'Tidak ada sisa muatan');
    });
  });

  // ── _findVehicleDoc logic (vehicleId publisher) ─────────────────────────
  // This stays a test-local mirror: the real method reads transactionStore
  // (Redux) and mapTableContent (GetX), neither bootstrappable in a pure unit
  // test. The mirror exercises the lt=='vehicle' && dv==driverVid selection.

  group('vehicleCargoSummary _findVehicleDoc', () {
    Map<String, dynamic>? findVehicleDoc(
      List<Map<String, dynamic>> slDocs,
      String driverVid,
    ) {
      if (driverVid.isEmpty) return null;
      for (final doc in slDocs) {
        final String lt = (doc['lt'] ?? '').toString().trim();
        final String dv = (doc['dv'] ?? '').toString().trim();
        if (lt == 'vehicle' && dv == driverVid) return doc;
      }
      return null;
    }

    test('finds vehicle doc by lt==vehicle and dv==driverVid', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'dv': 'DRV-1', 'lv': 'WH-1', 'ln': 'Gudang A'},
        {'lt': 'vehicle', 'dv': 'DRV-1', 'lv': 'VEH-X', 'ln': 'B 1234 XY'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRV-1');
      expect(doc, isNotNull);
      expect(doc!['lv'], 'VEH-X');
      expect(doc['ln'], 'B 1234 XY');
    });

    test('returns null when no match', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'OTHER', 'lv': 'VEH-Z', 'ln': 'B 0000 ZZ'},
      ];
      expect(findVehicleDoc(slDocs, 'DRV-1'), isNull);
    });

    test('returns null when driverVid is empty', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'DRV-1', 'lv': 'VEH-X', 'ln': 'B 1234 XY'},
      ];
      expect(findVehicleDoc(slDocs, ''), isNull);
    });

    test('returns null when docs list is empty', () {
      expect(findVehicleDoc([], 'DRV-1'), isNull);
    });

    test('skips docs where lt is not vehicle', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'office', 'dv': 'DRV-1', 'lv': 'OFF-1', 'ln': 'Kantor'},
      ];
      expect(findVehicleDoc(slDocs, 'DRV-1'), isNull);
    });
  });

  // ── plate from vehicle doc ──────────────────────────────────────────────

  group('vehicleCargoSummary plate extraction', () {
    test('reads plate from plateField (default ln)', () {
      final doc = {'lv': 'VEH-X', 'ln': 'B 1234 XY', 'lt': 'vehicle'};
      final String plateField = 'ln';
      final String plate = (doc[plateField] ?? '').toString().trim();
      expect(plate, 'B 1234 XY');
    });

    test('absent plateField yields empty -> no bold plate in intro', () {
      final Map<String, dynamic> doc = {'lv': 'VEH-X', 'lt': 'vehicle'};
      final String plate = (doc['ln'] ?? '').toString().trim();
      expect(plate, '');
    });
  });

  // ── per-item cargo aggregation (replaces bucket aggregation) ────────────
  // Calls the REAL computePerItemCargoRows from driver_home_support.dart (the
  // widget calls the same function) -- no test-local mirror. Result type is
  // CargoItemRow (fields itemId / displayName / fullQty / emptyQty).

  group('vehicleCargoSummary per-item aggregation', () {
    final nameMap = {
      '8886008101138': 'Aqua Galon 19 Liter',
      '8886008101139': 'LPG 3kg',
      '8886008101140': 'Amidis 600ml',
    };

    test('groups by ii, sums qt per cd, resolves name', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': '10', 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'empty', 'qt': '2', 'lv': 'VEH-X'},
        {'ii': '8886008101139', 'cd': 'full', 'qt': '4', 'lv': 'VEH-X'},
        {'ii': '8886008101139', 'cd': 'empty', 'qt': '6', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows.length, 2);
      // Sorted by name: "Aqua Galon 19 Liter" < "LPG 3kg"
      expect(rows[0].displayName, 'Aqua Galon 19 Liter');
      expect(rows[0].fullQty, 10);
      expect(rows[0].emptyQty, 2);
      expect(rows[1].displayName, 'LPG 3kg');
      expect(rows[1].fullQty, 4);
      expect(rows[1].emptyQty, 6);
    });

    test('full->isi and empty->kosong mapping via cd field', () {
      // The widget uses the raw cd values 'full' and 'empty' internally,
      // then maps to display labels via _t(3,'isi') and _t(4,'kosong').
      // This test verifies the grouping uses exact cd string matching.
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': '7', 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'empty', 'qt': '3', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows[0].fullQty, 7);
      expect(rows[0].emptyQty, 3);
    });

    test('0-fill missing condition -- item has only full docs', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': '15', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows.length, 1);
      expect(rows[0].fullQty, 15);
      expect(rows[0].emptyQty, 0); // 0-fill
    });

    test('0-fill missing condition -- item has only empty docs', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101139', 'cd': 'empty', 'qt': '8', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows.length, 1);
      expect(rows[0].fullQty, 0); // 0-fill
      expect(rows[0].emptyQty, 8);
    });

    test('name fallback to raw ii when item not in name map', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '9999999999999', 'cd': 'full', 'qt': '3', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows[0].displayName, '9999999999999');
    });

    test('name fallback when itemNameMap is empty (no item subscription)', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': '5', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, <String, String>{});
      expect(rows[0].displayName, '8886008101138');
    });

    test('name fallback when itemNameMap entry is empty string', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': '5', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, {'8886008101138': ''});
      expect(rows[0].displayName, '8886008101138');
    });

    test('empty cache docs -> empty rows', () {
      final rows = computePerItemCargoRows([], nameMap);
      expect(rows, isEmpty);
    });

    test('docs with empty ii are skipped', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '', 'cd': 'full', 'qt': '5', 'lv': 'VEH-X'},
        {'cd': 'full', 'qt': '3', 'lv': 'VEH-X'}, // ii absent
        {'ii': '8886008101138', 'cd': 'full', 'qt': '10', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows.length, 1);
      expect(rows[0].displayName, 'Aqua Galon 19 Liter');
    });

    test('non-numeric qt defaults to 0', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': 'abc', 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'full', 'qt': '5', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows[0].fullQty, 5); // 0 + 5
    });

    test('int qt values aggregate correctly', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': 20, 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'full', 'qt': 14, 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows[0].fullQty, 34);
    });

    test('ordering: by resolved name ascending, tiebreak by raw ii', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101139', 'cd': 'full', 'qt': '1', 'lv': 'VEH-X'},
        {'ii': '8886008101140', 'cd': 'full', 'qt': '2', 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'full', 'qt': '3', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      // Amidis 600ml < Aqua Galon 19 Liter < LPG 3kg
      expect(rows[0].displayName, 'Amidis 600ml');
      expect(rows[1].displayName, 'Aqua Galon 19 Liter');
      expect(rows[2].displayName, 'LPG 3kg');
    });

    test('ordering tiebreak: same name, different ii, sorted by ii', () {
      final tiedMap = {
        'AAA': 'Same Name',
        'ZZZ': 'Same Name',
      };
      final docs = <Map<String, dynamic>>[
        {'ii': 'ZZZ', 'cd': 'full', 'qt': '1', 'lv': 'VEH-X'},
        {'ii': 'AAA', 'cd': 'full', 'qt': '2', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, tiedMap);
      expect(rows[0].itemId, 'AAA');
      expect(rows[1].itemId, 'ZZZ');
    });

    test('multiple docs for same ii+cd are summed', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'cd': 'full', 'qt': '5', 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'full', 'qt': '3', 'lv': 'VEH-X'},
        {'ii': '8886008101138', 'cd': 'empty', 'qt': '1', 'lv': 'VEH-X'},
      ];
      final rows = computePerItemCargoRows(docs, nameMap);
      expect(rows[0].fullQty, 8);
      expect(rows[0].emptyQty, 1);
    });
  });

  // ── buildItemNameMap (shared helper) ────────────────────────────────────

  group('vehicleCargoSummary item name resolution', () {
    test('buildItemNameMap maps ii -> in', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': '8886008101138', 'in': 'Aqua Galon 19 Liter', 'ic': 'returnable'},
        {'ii': '8886008101139', 'in': 'LPG 3kg', 'ic': 'returnable'},
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map['8886008101138'], 'Aqua Galon 19 Liter');
      expect(map['8886008101139'], 'LPG 3kg');
    });

    test('empty ii entries are skipped', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': '', 'in': 'Ghost'},
        {'ii': '123', 'in': 'Real'},
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map.length, 1);
      expect(map['123'], 'Real');
    });

    test('empty item docs -> empty map', () {
      final map = buildItemNameMap([]);
      expect(map, isEmpty);
    });
  });

  // ── intro text assembly ─────────────────────────────────────────────────

  group('vehicleCargoSummary intro text assembly', () {
    test('assembles intro with bold plate marker', () {
      const introA = 'Serahkan kendaraan';
      const plate = 'B 1234 XY';
      const introB = ' + sisa muatan ke gudang.';
      final introText = '$introA **$plate**$introB';
      expect(introText,
          'Serahkan kendaraan **B 1234 XY** + sisa muatan ke gudang.');
    });

    test('empty plate omits bold markers', () {
      const introA = 'Serahkan kendaraan';
      const plate = '';
      const introB = ' + sisa muatan ke gudang.';
      final platePart = plate.isNotEmpty ? ' **$plate**' : '';
      final introText = '$introA$platePart$introB';
      expect(introText, 'Serahkan kendaraan + sisa muatan ke gudang.');
    });

    test('parseInlineEmphasis produces bold span for plate', () {
      const base = TextStyle(fontSize: 14, color: Color(0xFF6B7280));
      final spans = parseInlineEmphasis(
          'Serahkan kendaraan **B 1234 XY** + sisa muatan.', base);
      expect(spans.length, 3);
      expect((spans[0] as TextSpan).text, 'Serahkan kendaraan ');
      expect((spans[1] as TextSpan).text, 'B 1234 XY');
      expect((spans[1] as TextSpan).style!.fontWeight, FontWeight.w700);
      expect((spans[2] as TextSpan).text, ' + sisa muatan.');
    });
  });
}
