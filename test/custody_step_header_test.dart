// test/custody_step_header_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // ── custodyStepHeader text parsing ─────────────────────────────────────

  group('custodyStepHeader text parsing', () {
    test('2-slot text parsed and length-guarded', () {
      final text = [
        'KONFIRMASI PENERIMAAN', // 0 -- title
        'STEP 1/2',              // 1 -- step badge
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 2);
      expect(arr.isNotEmpty ? arr[0] : '', 'KONFIRMASI PENERIMAAN');
      expect(arr.length > 1 ? arr[1] : '', 'STEP 1/2');
    });

    test('short text array uses defaults', () {
      final arr = diamondTextToList('Title Only');
      expect(arr.isNotEmpty ? arr[0] : 'def', 'Title Only');
      expect(arr.length > 1 ? arr[1] : 'STEP', 'STEP');
    });

    test('empty text yields length-1 array (auto-memory gotcha)', () {
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.length > 1 ? arr[1] : 'STEP 1/2', 'STEP 1/2');
    });
  });

  // ── vehicleId derivation (mirrors vehicle_custody_header_test) ────────

  group('custodyStepHeader vehicleId publisher', () {
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
        {'lt': 'vehicle', 'dv': 'DRV-1', 'lv': 'VEH-X', 'ln': 'B-1234-XY'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRV-1');
      expect(doc, isNotNull);
      expect(doc!['lv'], 'VEH-X');
      expect(doc['ln'], 'B-1234-XY');
    });

    test('lv from found doc is published as vehicleId', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'DRV-A', 'lv': 'VEH-A', 'ln': 'B-1 A'},
      ];
      final doc = findVehicleDoc(slDocs, 'DRV-A');
      final String derivedVehicleId =
          (doc?['lv'] ?? '').toString().trim();
      expect(derivedVehicleId, 'VEH-A');
    });

    test('returns null when no doc matches', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'OTHER', 'lv': 'VEH-Z'},
      ];
      expect(findVehicleDoc(slDocs, 'DRV-1'), isNull);
    });

    test('returns null when driverVid is empty', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'vehicle', 'dv': 'DRV-1', 'lv': 'VEH-X'},
      ];
      expect(findVehicleDoc(slDocs, ''), isNull);
    });

    test('returns null when docs list is empty', () {
      expect(findVehicleDoc([], 'DRV-1'), isNull);
    });

    test('skips non-vehicle docs', () {
      final slDocs = <Map<String, dynamic>>[
        {'lt': 'warehouse', 'dv': 'DRV-1', 'lv': 'WH-1'},
        {'lt': 'client', 'dv': 'DRV-1', 'lv': 'CL-1'},
      ];
      expect(findVehicleDoc(slDocs, 'DRV-1'), isNull);
    });
  });

  // ── Plate display ─────────────────────────────────────────────────────

  group('custodyStepHeader plate display', () {
    test('reads plateField (ln) from vehicle doc', () {
      final doc = {'lv': 'VEH-X', 'ln': 'B-1234-XY', 'lt': 'vehicle'};
      expect((doc['ln'] ?? '').toString().trim(), 'B-1234-XY');
    });

    test('absent plate yields empty (widget shows dash)', () {
      final doc = <String, dynamic>{'lv': 'VEH-X', 'lt': 'vehicle'};
      final plate = (doc['ln'] ?? '').toString().trim();
      expect(plate, '');
    });
  });
}
