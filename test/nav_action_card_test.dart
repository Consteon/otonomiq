import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  group('navActionCard text parsing', () {
    test('3-slot text parsed correctly', () {
      final text =
          'Return Kendaraan\u{25C6}Balik & serahkan kendaraan + sisa muatan ke gudang\u{25C6}Semua kelar — balik & serahkan ke gudang';
      final arr = diamondTextToList(text);
      expect(arr.length, 3);
      expect(arr.isNotEmpty ? arr[0] : '', 'Return Kendaraan');
      expect(arr.length > 1 ? arr[1] : '', contains('Balik'));
      expect(arr.length > 2 ? arr[2] : '', contains('Semua kelar'));
    });

    test('short array length-guarded', () {
      final arr = diamondTextToList('OnlyTitle');
      expect(arr.isNotEmpty ? arr[0] : '', 'OnlyTitle');
      expect(arr.length > 1 ? arr[1] : 'default', 'default');
      expect(arr.length > 2 ? arr[2] : 'default', 'default');
    });
  });

  group('navActionCard allClosed logic', () {
    test('all done -> allClosed, CTA active', () {
      final docs = [
        {'tst': 'done'},
        {'tst': 'done'},
      ];
      final p = computeStopProgress(docs);
      expect(p.allClosed, isTrue);
    });

    test('mixed done + failed -> allClosed', () {
      final docs = [
        {'tst': 'done'},
        {'tst': 'failed'},
      ];
      final p = computeStopProgress(docs);
      expect(p.allClosed, isTrue);
    });

    test('one active -> not allClosed, CTA disabled', () {
      final docs = [
        {'tst': 'done'},
        {'tst': 'active'},
      ];
      final p = computeStopProgress(docs);
      expect(p.allClosed, isFalse);
    });

    test('empty -> not allClosed', () {
      final p = computeStopProgress([]);
      expect(p.allClosed, isFalse);
    });

    test('one pending -> not allClosed', () {
      final docs = [
        {'tst': 'done'},
        {'tst': ''},
      ];
      final p = computeStopProgress(docs);
      expect(p.allClosed, isFalse);
    });
  });
}
