import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';
import 'package:otonomiq/global.dart';

// uploadImageToCloud used to declare its OWN copies of invalidPathPrefix and
// invalidPathPostfix ('aume__InvalidImagePath-' / '__emua'), shadowing the
// globals for the whole function body. Every downstream consumer keys on the
// app-wide 'aum__' / '__mua' markers:
//
//   replaceLocalImageToUrl  api.dart:589   newUrl.contains(invalidPathPrefix)
//                                          -> defaultImage
//   replaceLocalImageToUrl  api.dart:563   RegExp(r"aum__(.*?)__mua")
//   historySync             table_repo     content.contains('aum__')
//   sendImagesInImageMap    table_repo     value[1].contains('aum__')
//   updateHistoryImage      table_repo     RegExp(r"aum__(.*?)__mua")
//
// 'aume__...' matches NONE of them, so the give-up sentinel - which embeds the
// raw local file path - was substituted verbatim into the event string and
// shipped to the sheet.
//
// WHAT EACH TEST IS WORTH:
//
//   Test 1 is the ONLY test here that guards the defect. It calls the real
//   uploadImageToCloud and fails while the local shadowing consts exist
//   ('aume__InvalidImagePath-' does not start with 'aum__'). Mutation that
//   turns it RED: put either `const invalidPathPrefix = 'aume__...';` or
//   `const invalidPathPostfix = '__emua';` back into uploadImageToCloud.
//
//   Tests 2 and 3 do NOT touch table_repository.dart at all - they pin the
//   marker values declared in lib/global.dart, and are green with or without
//   the fix. They exist so that a later edit to global.dart:224-227 cannot
//   silently break the 'aum__(.*?)__mua' contract the fix now relies on.
//   Mutation that turns them RED: change localImagePrefix / localImagePostfix
//   / invalidPathPrefix / invalidPathPostfix in lib/global.dart.

void main() {
  group('image failure sentinel wears the app-wide aum__ markers', () {
    test('uploadImageToCloud short-path early return uses the global prefix',
        () async {
      // localPath.length < 5 takes the early return: no Firebase, no network,
      // no file IO - only a devPrint - so this is safe in flutter_test.
      final String r = await uploadImageToCloud('abc');
      expect(r, startsWith(localImagePrefix));
      expect(r, invalidPathPrefix);
    });

    test('a give-up sentinel is seen by the aum__ regex', () {
      // The exact shape uploadImageToCloud builds when
      // imageMapEntry[3] >= maxImageUploadRetry. Pins lib/global.dart, not the
      // fix: the markers below are the globals.
      final String sentinel = '${invalidPathPrefix}13:'
          '/data/user/0/app/files/otq_images/'
          'FTZIMG%2Fid%2F2022___60181816889090-x_241f9.jpg'
          '$invalidPathPostfix';

      // replaceLocalImageToUrl, historySync and updateHistoryImage all key on
      // this regex. A mismatch here is how the local path reached Event C.
      expect(RegExp(r'aum__(.*?)__mua').hasMatch(sentinel), isTrue);
    });

    test('the two markers stay a mirrored pair anchored on localImagePrefix',
        () {
      expect(invalidPathPrefix, startsWith(localImagePrefix));
      expect(invalidPathPostfix, localImagePostfix);
      expect(invalidPathPrefix.contains('aume__'), isFalse);
      expect(invalidPathPostfix.contains('emua'), isFalse);
    });
  });
}
