import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/crypto/auth_crypto.dart';
import 'package:otonomiq/global.dart';

void main() {
  group('makeLqrCode', () {
    test('matches the version-0 location QR shape', () {
      final code = makeLqrCode('Gudang Cikarang');
      expect(code.length, 42);
      expect(code.substring(0, 2), '0l');
      expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(code.substring(2)), isTrue);
    });

    test('uses standard sha1 (known-answer vector)', () {
      // sha1('abc') = a9993e364706816aba3e25717850c26c9cd0d89d
      expect(makeLqrCode('abc'), '0la9993e364706816aba3e25717850c26c9cd0d89d');
    });

    test('is deterministic and collision-free for distinct text', () {
      expect(makeLqrCode('Pos Satpam 1'), makeLqrCode('Pos Satpam 1'));
      expect(makeLqrCode('Pos Satpam 1') == makeLqrCode('Pos Satpam 2'), isFalse);
    });

    test('handles empty and non-ascii text without throwing', () {
      expect(makeLqrCode('').length, 42);
      expect(makeLqrCode('Gudang Ciréndeu ⬤').length, 42);
    });

    test('round-trips through lqrVerify as a plaintext payload', () async {
      final code = makeLqrCode('Kantor Pusat');
      final decoded = await lqrVerify('', '', code);
      expect(decoded, isNot(errorString));
      // lqrVerify strips only the version marker; the rest is the lookup key.
      expect(decoded, code.substring(1));
    });

    test('round-trips when wrapped in a /qr/ URL', () async {
      final code = makeLqrCode('Kantor Pusat');
      final decoded = await lqrVerify('', '', 'https://otq.id/qr/$code');
      expect(decoded, code.substring(1));
    });
  });
}
