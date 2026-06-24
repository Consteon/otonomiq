import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  group('RouteProgressHeader text parsing (8-slot)', () {
    test('diamondTextToList parses 8-slot text correctly', () {
      final text =
          'Rute Hari Ini\u{25C6}stop\u{25C6}gagal\u{25C6}Drop\u{25C6}Pickup\u{25C6}kendaraan ditugaskan\u{25C6}Keluar\u{25C6}Belum ditugaskan kendaraan';
      final arr = diamondTextToList(text);
      expect(arr.length, 8);
      expect(arr[0], 'Rute Hari Ini');
      expect(arr[5], 'kendaraan ditugaskan');
      expect(arr[6], 'Keluar');
      expect(arr[7], 'Belum ditugaskan kendaraan');
    });

    test('short text array handled with length guard', () {
      final arr = diamondTextToList('Only\u{25C6}Two');
      expect(arr.length, 2);
      // Length-guard pattern: arr.length > N ? arr[N] : def
      expect(arr.length > 5 ? arr[5] : 'default', 'default');
      expect(arr.length > 6 ? arr[6] : 'default', 'default');
      expect(arr.length > 7 ? arr[7] : 'default', 'default');
      expect(arr.isNotEmpty ? arr[0] : '', 'Only');
    });

    test('empty text produces single empty-string element', () {
      // diamondTextToList('') returns [''] (length 1), NOT [].
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.first, '');
    });
  });

  group('Header data-bound name/plate selection', () {
    test('name from workforce doc nameField (default n)', () {
      final driverDoc = {'n': 'Budi Santoso', 'VID': '777'};
      const String nameField = 'n'; // component['nameField'] ?? 'n'
      final String driverName =
          (driverDoc[nameField] ?? '').toString().trim();
      expect(driverName, 'Budi Santoso');
    });

    test('name from custom nameField', () {
      final driverDoc = {'full_name': 'Andi Wijaya', 'n': 'Andi'};
      const String nameField = 'full_name';
      final String driverName =
          (driverDoc[nameField] ?? '').toString().trim();
      expect(driverName, 'Andi Wijaya');
    });

    test('absent nameField in doc -> empty string', () {
      final driverDoc = {'VID': '777'}; // no 'n' field
      const String nameField = 'n';
      final String driverName =
          (driverDoc[nameField] ?? '').toString().trim();
      expect(driverName, '');
    });

    test('null driverDoc -> empty name', () {
      final Map<String, dynamic>? driverDoc = null;
      const String nameField = 'n';
      final String driverName =
          (driverDoc?[nameField] ?? '').toString().trim();
      expect(driverName, '');
    });

    test('plate from stock_location vehicle doc plateField (default ln)', () {
      final vehicleDoc = {
        'lt': 'vehicle',
        'dv': '777',
        'lv': 'V1',
        'ln': 'B 1234 XY',
      };
      const String plateField = 'ln'; // component['plateField'] ?? 'ln'
      final String plate =
          (vehicleDoc[plateField] ?? '').toString().trim();
      expect(plate, 'B 1234 XY');
    });

    test('plate from custom plateField', () {
      final vehicleDoc = {'lt': 'vehicle', 'plate_number': 'D 5678 AB'};
      const String plateField = 'plate_number';
      final String plate =
          (vehicleDoc[plateField] ?? '').toString().trim();
      expect(plate, 'D 5678 AB');
    });

    test('null vehicleDoc -> empty plate -> noVehicleLabel subtitle', () {
      final Map<String, dynamic>? vehicleDoc = null;
      const String plateField = 'ln';
      final String plate =
          (vehicleDoc?[plateField] ?? '').toString().trim();
      expect(plate, '');
      // subtitle logic: plate.isEmpty -> noVehicleLabel
      const String vehicleLabel = 'kendaraan ditugaskan';
      const String noVehicleLabel = 'Belum ditugaskan kendaraan';
      final String subtitle = plate.isNotEmpty
          ? '$plate · $vehicleLabel'
          : noVehicleLabel;
      expect(subtitle, 'Belum ditugaskan kendaraan');
    });

    test('plate present -> plate + vehicleLabel subtitle', () {
      final vehicleDoc = {'ln': 'B 1234 XY'};
      const String plateField = 'ln';
      final String plate =
          (vehicleDoc[plateField] ?? '').toString().trim();
      const String vehicleLabel = 'kendaraan ditugaskan';
      const String noVehicleLabel = 'Belum ditugaskan kendaraan';
      final String subtitle = plate.isNotEmpty
          ? '$plate · $vehicleLabel'
          : noVehicleLabel;
      expect(subtitle, 'B 1234 XY · kendaraan ditugaskan');
    });
  });

  group('Header 8-slot index reads', () {
    // Mirrors the _t(i, def) pattern in the widget.
    String t(List<String> arr, int i, [String def = '']) =>
        arr.length > i ? arr[i] : def;

    test('vehicleLabel from slot 5', () {
      final arr = diamondTextToList(
          'Rute Hari Ini\u{25C6}stop\u{25C6}gagal\u{25C6}Drop\u{25C6}Pickup\u{25C6}kendaraan ditugaskan\u{25C6}Keluar\u{25C6}Belum ditugaskan kendaraan');
      expect(t(arr, 5, 'kendaraan ditugaskan'), 'kendaraan ditugaskan');
    });

    test('logoutLabel from slot 6', () {
      final arr = diamondTextToList(
          'Rute Hari Ini\u{25C6}stop\u{25C6}gagal\u{25C6}Drop\u{25C6}Pickup\u{25C6}kendaraan ditugaskan\u{25C6}Keluar\u{25C6}Belum ditugaskan kendaraan');
      expect(t(arr, 6, 'Keluar'), 'Keluar');
    });

    test('noVehicleLabel from slot 7', () {
      final arr = diamondTextToList(
          'Rute Hari Ini\u{25C6}stop\u{25C6}gagal\u{25C6}Drop\u{25C6}Pickup\u{25C6}kendaraan ditugaskan\u{25C6}Keluar\u{25C6}Belum ditugaskan kendaraan');
      expect(t(arr, 7, 'Belum ditugaskan kendaraan'),
          'Belum ditugaskan kendaraan');
    });

    test('short array falls back to defaults', () {
      final arr = diamondTextToList('Rute\u{25C6}stop');
      expect(t(arr, 5, 'kendaraan ditugaskan'), 'kendaraan ditugaskan');
      expect(t(arr, 6, 'Keluar'), 'Keluar');
      expect(t(arr, 7, 'Belum ditugaskan kendaraan'),
          'Belum ditugaskan kendaraan');
    });
  });

  group('Vehicle doc plate selection (contract)', () {
    // Mirrors _findVehicleDoc logic: find doc where lt=='vehicle' && dv==driverVid.
    Map<String, dynamic>? findVehicleDoc(
        List<Map<String, dynamic>> slDocs, String driverVid) {
      if (driverVid.isEmpty) return null;
      for (final doc in slDocs) {
        final String lt = (doc['lt'] ?? '').toString().trim();
        final String dv = (doc['dv'] ?? '').toString().trim();
        if (lt == 'vehicle' && dv == driverVid) return doc;
      }
      return null;
    }

    test('returns full doc including ln plate field', () {
      final docs = [
        {'lt': 'warehouse', 'dv': '', 'lv': 'W1', 'ln': 'Gudang A'},
        {'lt': 'vehicle', 'dv': '777', 'lv': 'V1', 'ln': 'B 1234 XY'},
      ];
      final doc = findVehicleDoc(docs, '777');
      expect(doc, isNotNull);
      expect(doc!['ln'], 'B 1234 XY');
      expect(doc['lv'], 'V1');
    });

    test('no vehicle doc -> null -> plate empty', () {
      final docs = [
        {'lt': 'warehouse', 'dv': '', 'lv': 'W1'},
      ];
      final doc = findVehicleDoc(docs, '777');
      expect(doc, isNull);
      final String plate = (doc?['ln'] ?? '').toString().trim();
      expect(plate, '');
    });

    test('vehicle doc without ln field -> plate empty', () {
      final docs = [
        {'lt': 'vehicle', 'dv': '777', 'lv': 'V1'}, // no ln
      ];
      final doc = findVehicleDoc(docs, '777');
      expect(doc, isNotNull);
      final String plate = (doc?['ln'] ?? '').toString().trim();
      expect(plate, '');
    });

    test('empty driverVid -> null', () {
      final docs = [
        {'lt': 'vehicle', 'dv': '777', 'lv': 'V1', 'ln': 'B 1234 XY'},
      ];
      expect(findVehicleDoc(docs, ''), isNull);
    });
  });
}
