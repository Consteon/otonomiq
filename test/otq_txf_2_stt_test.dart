import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/otq_txf_2.dart';

void main() {
  test('sttCompose returns spoken words alone when field was empty', () {
    expect(sttCompose('', 'halo dunia', -1), 'halo dunia');
  });

  test('sttCompose appends spoken words to existing text with a space', () {
    expect(sttCompose('catatan awal', 'lanjutan suara', -1),
        'catatan awal lanjutan suara');
  });

  test('sttCompose truncates to maxLength when set', () {
    expect(sttCompose('12345', '67890', 8), '12345 67');
  });

  test('sttCompose ignores maxLength <= 0', () {
    expect(sttCompose('abc', 'def', 0), 'abc def');
    expect(sttCompose('abc', 'def', -1), 'abc def');
  });

  test('sttCompose keeps text unchanged shape for empty speech result', () {
    expect(sttCompose('tetap', '', -1), 'tetap ');
  });
}
