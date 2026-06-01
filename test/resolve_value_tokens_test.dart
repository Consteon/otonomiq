import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';
import 'package:otonomiq/global.dart';

void main() {
  // forbiddenCharacter[7/9]=◀/▶ (system/ref[0]); [8/10]=◁/▷ (form/ref[1]).
  final lo = forbiddenCharacter[7], lc = forbiddenCharacter[9];
  final ro = forbiddenCharacter[8], rc = forbiddenCharacter[10];

  test('◀N▶ pulls from ref[0] (system), 1-based', () {
    final ref = [['sysA', 'sysB'], ['formA', 'formB']];
    final out = resolveValueTokens('${lo}2${lc}', ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(out, 'sysB');
  });

  test('◁N▷ pulls from ref[1] (form), 1-based', () {
    final ref = [['sysA'], ['formA', 'formB']];
    final out = resolveValueTokens('${ro}1${rc}', ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(out, 'formA');
  });

  test('literal passes through unchanged', () {
    final ref = [<String>[], <String>[]];
    final out = resolveValueTokens('hello', ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(out, 'hello');
  });
}
