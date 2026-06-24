import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  group('driverStopCard text parsing', () {
    test('18-slot text parsed and length-guarded', () {
      final text = [
        'Stop Berikutnya', // 0
        'Dilaporkan Gagal', // 1
        'Sudah Selesai', // 2
        'Pilih sesuai kondisi lapangan', // 3
        'Mulai Eksekusi', // 4
        'Selesai', // 5
        'Customer confirmed', // 6
        'Dilaporkan gagal', // 7
        'kirim', // 8
        'ambil', // 9
        'Pickup Only', // 10
        'Rute Hari Ini', // 11
        '{closed} dari {total} stop', // 12
        'lanjut:', // 13
        'semua kelar', // 14
        '{total} tujuan', // 15
        'Konfirmasi muatan dulu', // 16
        'Buka Tasklist (eksekusi)', // 17
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 18);
      // Length-guard every slot access
      expect(arr.isNotEmpty ? arr[0] : '', 'Stop Berikutnya');
      expect(arr.length > 11 ? arr[11] : '', 'Rute Hari Ini');
      expect(arr.length > 17 ? arr[17] : '', 'Buka Tasklist (eksekusi)');
    });

    test('short text array does not throw with length guard', () {
      final arr = diamondTextToList('A\u{25C6}B');
      expect(arr.length, 2);
      expect(arr.length > 11 ? arr[11] : 'default', 'default');
      expect(arr.length > 17 ? arr[17] : 'default', 'default');
    });
  });

  group('progress template substitution', () {
    test('{closed} and {total} replaced in progress text', () {
      const template = '{closed} dari {total} stop';
      final result =
          template.replaceAll('{closed}', '3').replaceAll('{total}', '7');
      expect(result, '3 dari 7 stop');
    });

    test('{total} replaced in count text', () {
      const template = '{total} tujuan';
      final result = template.replaceAll('{total}', '5');
      expect(result, '5 tujuan');
    });
  });

  group('stop badge mapping', () {
    test('done -> SELESAI', () {
      expect(stopStatusOf({'tst': 'done'}), 'done');
    });

    test('failed -> GAGAL', () {
      expect(stopStatusOf({'tst': 'failed'}), 'failed');
    });

    test('active -> LANJUT', () {
      expect(stopStatusOf({'tst': 'active'}), 'active');
    });

    test('absent/empty -> pending (KIRIM/AMBIL)', () {
      expect(stopStatusOf({}), 'pending');
      expect(stopStatusOf({'tst': ''}), 'pending');
    });

    // --- Spec vocab (section 4) ---

    test('closed (spec vocab) -> done -> SELESAI badge', () {
      // stopStatusOf normalizes 'closed' to 'done'; badge maps done -> SELESAI.
      expect(stopStatusOf({'tst': 'closed'}), 'done');
    });

    test('ongoing (spec vocab) -> active -> LANJUT badge', () {
      expect(stopStatusOf({'tst': 'ongoing'}), 'active');
    });

    test('assigned (spec vocab) -> pending -> KIRIM/AMBIL badge', () {
      expect(stopStatusOf({'tst': 'assigned'}), 'pending');
    });

    test('backward compat: done still maps to done (SELESAI)', () {
      expect(stopStatusOf({'tst': 'done'}), 'done');
    });

    test('backward compat: active still maps to active (LANJUT)', () {
      expect(stopStatusOf({'tst': 'active'}), 'active');
    });
  });
}
