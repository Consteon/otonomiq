import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart';
import 'package:otonomiq/global.dart';

// folderFromRawPath (api.dart) strips the "<dir>/FTZIMG/" prefix off a decoded
// local image path, leaving the Firebase Storage folder.
//
// The inline version it replaced did:
//   rawFolder.substring(rawFolder.lastIndexOf('FTZIMG/') + 6 + 1)
// With no FTZIMG marker lastIndexOf gives -1, so that collapsed to
// substring(6) -- a RangeError when the path is shorter than 6 chars (camera
// cancelled => empty path => Fatal in saveImagePutInImageMap), and a silently
// chopped folder when it is longer. Both branches are pinned below.

void main() {
  group('folderFromRawPath', () {
    test('strips the marker on a real camera path', () {
      // What renamePath writes, after split('___')[0] + decodeComponent.
      const raw = '/var/mobile/Containers/Data/otq_images/FTZIMG/absensi';
      expect(folderFromRawPath(raw), 'absensi');
    });

    test('empty path returns empty, does NOT RangeError', () {
      // The reported crash: acquireCamera returns '' when the dialog is
      // dismissed, so localPath is '' by the time it reaches this call.
      expect(folderFromRawPath(''), '');
    });

    test('short marker-less paths do not RangeError', () {
      // substring(6) threw on every one of these.
      for (final s in ['a', 'ab', 'abc', 'abcd', 'abcde']) {
        expect(folderFromRawPath(s), s, reason: 'input "$s"');
      }
    });

    test('long marker-less path is returned WHOLE, not chopped by 6', () {
      // renamePath falls back to the raw camera path when rename+copy both
      // fail. That path is long, so the old code did not throw -- it silently
      // returned the path minus its first 6 chars and uploaded to a garbage
      // Storage folder. This is the invisible half of the bug.
      const raw = '/private/var/mobile/tmp/CAP_0F3A.jpg';
      expect(folderFromRawPath(raw), raw);
      expect(folderFromRawPath(raw), isNot(raw.substring(6)));
    });

    test('exactly 6 chars, no marker', () {
      // The old boundary: substring(6) on a length-6 string returns '' rather
      // than throwing, so this silently produced an empty folder.
      expect(folderFromRawPath('abcdef'), 'abcdef');
    });

    test('marker at the very end yields an empty folder', () {
      expect(folderFromRawPath('/dir/$localImageBeginningFolderDivider/'), '');
    });

    test('uses the LAST marker when the path repeats it', () {
      const raw = '/dir/FTZIMG/outer/FTZIMG/inner';
      expect(folderFromRawPath(raw), 'inner');
    });

    test('bare marker without a trailing slash is not treated as a match', () {
      // lastIndexOf looks for 'FTZIMG/', so a folder merely named FTZIMG is
      // left alone rather than half-stripped.
      expect(folderFromRawPath('/dir/FTZIMG'), '/dir/FTZIMG');
    });

    test('end-to-end: the encoding renamePath actually writes', () {
      const stored = '/data/otq_images/'
          '${localImageBeginningFolderDivider}%2Fabsensi%2Fpagi'
          '${localImageFolderSeparator}selfie_ab12c.jpg';
      final rawFolder = Uri.decodeComponent(
        stored.split(localImageFolderSeparator)[0],
      );
      expect(folderFromRawPath(rawFolder), 'absensi/pagi');
    });
  });
}
