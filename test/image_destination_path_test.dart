import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart';
import 'package:otonomiq/global.dart';

void main() {
  group('buildImageDestinationName', () {
    test('produces correct format with simple folder and fileName', () {
      final result = buildImageDestinationName('claims', 'proof_abc12');
      // Expected: FTZIMG%2Fclaims___proof_abc12.jpg
      expect(result, 'FTZIMG%2Fclaims___proof_abc12.jpg');
      // Verify the separator is present
      expect(result.contains('___'), isTrue);
    });

    test('folder containing a / is URI-encoded', () {
      final result = buildImageDestinationName('reports/daily', 'img_x9k2f');
      // '/' encodes to %2F
      expect(result, 'FTZIMG%2Freports%2Fdaily___img_x9k2f.jpg');
    });

    test('folder with characters that Uri.encodeComponent escapes', () {
      final result = buildImageDestinationName('folder name&special=yes', 'file_01');
      final parts = result.split('___');
      expect(parts.length, 2);
      // Decode the folder part and strip the FTZIMG/ prefix via folderFromRawPath
      final decodedFirst = Uri.decodeComponent(parts[0]);
      final folder = folderFromRawPath(decodedFirst);
      expect(folder, 'folder name&special=yes');
      expect(parts[1], 'file_01.jpg');
    });

    test('fileName with characters that Uri.encodeComponent escapes', () {
      final result = buildImageDestinationName('default', 'photo #1 (copy)');
      final parts = result.split('___');
      expect(parts.length, 2);
      final decodedFileName = Uri.decodeComponent(parts[1].replaceAll('.jpg', ''));
      expect(decodedFileName, 'photo #1 (copy)');
    });

    test('empty folder string produces valid split', () {
      final result = buildImageDestinationName('', 'file_abc');
      final parts = result.split('___');
      expect(parts.length, 2);
      // An empty folder URI-encodes to empty string
      expect(parts[0], 'FTZIMG%2F');
      expect(parts[1], 'file_abc.jpg');
    });

    test('folder with trailing / has it stripped', () {
      final result = buildImageDestinationName('myFolder/', 'img_1');
      // The trailing / should be removed before encoding
      expect(result, 'FTZIMG%2FmyFolder___img_1.jpg');
    });
  });

  group('buildImageDestinationName + folderFromRawPath round-trip', () {
    void verifyRoundTrip(String folder, String fileName) {
      final name = buildImageDestinationName(folder, fileName);
      final parts = name.split(localImageFolderSeparator);
      expect(parts.length, 2,
          reason: 'Name must contain exactly one ___ separator');

      // Consumer path: Uri.decodeComponent on the first part, then folderFromRawPath
      final decodedFirst = Uri.decodeComponent(parts[0]);
      final recoveredFolder = folderFromRawPath(decodedFirst);
      // Folder round-trips (trailing / stripped is expected)
      final expectedFolder =
          folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder;
      expect(recoveredFolder, expectedFolder);

      // Second part is <encoded fileName>.jpg
      final recoveredFileName =
          Uri.decodeComponent(parts[1].replaceAll('.jpg', ''));
      expect(recoveredFileName, fileName);
    }

    test('simple folder', () => verifyRoundTrip('claims', 'proof_abc12'));
    test('folder with slash', () => verifyRoundTrip('reports/daily', 'img_99'));
    test('folder with spaces and symbols',
        () => verifyRoundTrip('folder name&special=yes', 'file_01'));
    test('empty folder', () => verifyRoundTrip('', 'file_abc'));
    // Non-ASCII (multi-byte UTF-8) folder — tenant folders in this app are
    // Indonesian and can carry accented/CJK characters; exercises the real
    // Uri.encodeComponent/decodeComponent percent-encoding round-trip.
    test('unicode folder', () => verifyRoundTrip('laporan/café_日本', 'foto_1'));
    test('fileName with spaces',
        () => verifyRoundTrip('default', 'my photo 2024'));
  });
}
