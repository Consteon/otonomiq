// test/vehicle_custody_header_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // ── vehicleCustodyHeader text parsing ───────────────────────────────────

  group('vehicleCustodyHeader text parsing', () {
    test('4-slot text parsed and length-guarded', () {
      final text = [
        'Penerimaan Muatan', // 0
        'Dimuat oleh', // 1
        'Waktu loading', // 2
        'Custody event', // 3
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 4);
      expect(arr.isNotEmpty ? arr[0] : '', 'Penerimaan Muatan');
      expect(arr.length > 1 ? arr[1] : '', 'Dimuat oleh');
      expect(arr.length > 2 ? arr[2] : '', 'Waktu loading');
      expect(arr.length > 3 ? arr[3] : '', 'Custody event');
    });

    test('short text array uses defaults', () {
      final arr = diamondTextToList('Title');
      expect(arr.isNotEmpty ? arr[0] : 'def', 'Title');
      expect(arr.length > 1 ? arr[1] : 'Dimuat oleh', 'Dimuat oleh');
      expect(arr.length > 3 ? arr[3] : 'Custody event', 'Custody event');
    });
  });

  // ── Field extraction from vehicle_check doc ─────────────────────────────

  group('vehicleCustodyHeader field extraction', () {
    // Simulate the widget's field read logic
    String fieldOf(Map<String, dynamic>? doc, String field) =>
        (doc?[field] ?? '').toString().trim();

    test('reads cnm, gn, ldt from vehicle_check doc', () {
      final doc = {
        'cnm': 'CHK-VEH-B1234XY-20260615-OPEN',
        'gn': 'Anton Pratama',
        'ldt': '1718420280000',
        'cty': 'opening',
        'vv': 'VEH-B1234XY',
      };
      expect(fieldOf(doc, 'cnm'), 'CHK-VEH-B1234XY-20260615-OPEN');
      expect(fieldOf(doc, 'gn'), 'Anton Pratama');
      expect(fieldOf(doc, 'ldt'), '1718420280000');
    });

    test('absent gn/ldt yield empty -> widget shows dash', () {
      final doc = {
        'cnm': 'CHK-VEH-B1234XY-20260615-OPEN',
        'cty': 'opening',
      };
      // gn and ldt are FUTURE fields, absent in current data
      final gn = fieldOf(doc, 'gn');
      final ldt = fieldOf(doc, 'ldt');
      expect(gn, '');
      expect(ldt, '');
      // Widget logic: gn.isEmpty ? '\u{2014}' : gn
      expect(gn.isEmpty ? '\u{2014}' : gn, '\u{2014}');
      expect(ldt.isEmpty ? '\u{2014}' : ldt, '\u{2014}');
    });

    test('reads ln (plate) from stock_location doc', () {
      final doc = {'lv': 'VEH-B1234XY', 'ln': 'B-1234-XY', 'lt': 'vehicle'};
      expect(fieldOf(doc, 'ln'), 'B-1234-XY');
    });

    test('null doc returns empty for all fields', () {
      expect(fieldOf(null, 'cnm'), '');
      expect(fieldOf(null, 'ln'), '');
    });
  });

  // ── _findVehicleDoc logic (vehicleId publisher) ────────────────────────

  group('vehicleCustodyHeader _findVehicleDoc (vehicleId publisher)', () {
    /// Simulate _findVehicleDoc: iterates stock_location docs for
    /// lt=='vehicle' && dv==driverVid. Returns the full doc.
    /// This mirrors route_progress_header._findVehicleDoc (rph:124-138).
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
        {'lt': 'warehouse', 'dv': 'DRIVER-001', 'lv': 'WH-1', 'ln': 'Gudang A'},
        {'lt': 'vehicle', 'dv': 'DRIVER-002', 'lv': 'VEH-Y', 'ln': 'B-9999-ZZ'},
        {'lt': 'vehicle', 'dv': 'DRIVER-001', 'lv': 'VEH-X', 'ln': 'B-1234-XY'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRIVER-001');
      expect(doc, isNotNull);
      expect(doc!['lv'], 'VEH-X');
      expect(doc['ln'], 'B-1234-XY');
    });

    test('lv from found doc is the value downstream searches receive', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'DRV-A', 'lv': 'VEH-A', 'ln': 'B-1 A'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRV-A');
      // The derived vehicleId is doc['lv'], which gets published
      // into getDriverHomeState(scrName).vehicleId.value
      final String derivedVehicleId =
          (doc?['lv'] ?? '').toString().trim();
      expect(derivedVehicleId, 'VEH-A');
    });

    test('returns null when no doc matches driverVid', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'OTHER', 'lv': 'VEH-Z', 'ln': 'B-0000-ZZ'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRIVER-001');
      expect(doc, isNull);
    });

    test('returns null when driverVid is empty', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'DRIVER-001', 'lv': 'VEH-X', 'ln': 'B-1234-XY'},
      ];
      final doc = findVehicleDoc(slDocs, '');
      expect(doc, isNull);
    });

    test('returns null when docs list is empty', () {
      final doc = findVehicleDoc([], 'DRIVER-001');
      expect(doc, isNull);
    });

    test('skips docs where lt is not vehicle', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'dv': 'DRIVER-001', 'lv': 'WH-1', 'ln': 'Gudang'},
        {'lt': 'office', 'dv': 'DRIVER-001', 'lv': 'OFF-1', 'ln': 'Kantor'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRIVER-001');
      expect(doc, isNull);
    });

    test('returns first matching doc when multiple vehicles match', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'DRV-A', 'lv': 'VEH-1', 'ln': 'First'},
        {'lt': 'vehicle', 'dv': 'DRV-A', 'lv': 'VEH-2', 'ln': 'Second'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRV-A');
      expect(doc!['lv'], 'VEH-1');
    });
  });
}
