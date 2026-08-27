import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/otq_txt.dart';

void main() {
  group('OtqTxt.splitSectionMeta', () {
    test('title with " -- " meta splits and reformats date/time', () {
      expect(OtqTxt.splitSectionMeta('ABSEN MASUK -- 18-Aug 8:34'),
          ['ABSEN MASUK', '18 Aug · 8:34']);
    });

    test('no " -- " returns whole trimmed data, empty meta', () {
      expect(OtqTxt.splitSectionMeta('  Laporan  '), ['Laporan', '']);
    });

    test('meta without space kept raw', () {
      expect(OtqTxt.splitSectionMeta('X -- 18-Aug'), ['X', '18-Aug']);
    });

    test('only FIRST " -- " splits; title never loses text', () {
      final parts = OtqTxt.splitSectionMeta('A -- b -- c');
      expect(parts[0], 'A');
      expect(parts[1], contains('c'));
    });

    test('empty string safe', () {
      expect(OtqTxt.splitSectionMeta(''), ['', '']);
    });
  });
}
