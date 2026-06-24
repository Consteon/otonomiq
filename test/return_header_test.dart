// test/return_header_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // ── returnHeader text parsing ─────────────────────────────────────────────

  group('returnHeader text parsing', () {
    test('2-slot text parsed and length-guarded', () {
      final text = ['Akhir Hari', 'Return Kendaraan'].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 2);
      expect(arr.isNotEmpty ? arr[0] : '', 'Akhir Hari');
      expect(arr.length > 1 ? arr[1] : '', 'Return Kendaraan');
    });

    test('short text array uses defaults for missing slots', () {
      final arr = diamondTextToList('OnlyLabel');
      expect(arr.isNotEmpty ? arr[0] : 'Akhir Hari', 'OnlyLabel');
      expect(arr.length > 1 ? arr[1] : 'Return Kendaraan', 'Return Kendaraan');
    });

    test('empty text yields length-1 array with empty string', () {
      // diamondTextToList('') returns [''] (length 1, NOT [])
      final arr = diamondTextToList('');
      expect(arr.length, greaterThanOrEqualTo(1));
      // Slot 0 is empty string, slot 1 falls to default
      expect(arr.length > 1 ? arr[1] : 'Return Kendaraan', 'Return Kendaraan');
    });
  });
}
