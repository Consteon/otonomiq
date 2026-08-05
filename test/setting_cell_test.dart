import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart';

void main() {
  group('settingCell', () {
    // The exact shape readSS returns for Settings!B1:B5 when the workbook has
    // B3 (Gmail account) and B5 (type) blank: the blank row in the middle comes
    // back as [], the trailing blank row is dropped entirely (length 4, not 5).
    // Indexing rows[2][0] on this threw
    // "RangeError (length): Invalid value: Valid value range is empty: 0".
    final live = [
      ['20847881463241'],
      ['Oki'],
      <dynamic>[],
      ['62895372298625'],
    ];

    test('reads present cells', () {
      expect(settingCell(live, 0), '20847881463241');
      expect(settingCell(live, 1), 'Oki');
      expect(settingCell(live, 3), '62895372298625');
    });

    test('blank row in the middle returns empty, not RangeError', () {
      expect(settingCell(live, 2), '');
    });

    test('truncated trailing row returns empty, not RangeError', () {
      expect(settingCell(live, 4), '');
    });

    test('degenerate inputs', () {
      expect(settingCell(<dynamic>[], 0), '');
      expect(settingCell(null, 0), '');
      expect(settingCell('not a list', 0), '');
      expect(settingCell(live, -1), '');
      expect(
        settingCell([
          [null],
        ], 0),
        '',
      );
      // Non-string cell (readSS may hand back a number) is stringified, which
      // is what the old `.length > 0` / `.toString()` call sites assumed.
      expect(
        settingCell([
          [42],
        ], 0),
        '42',
      );
    });
  });
}
