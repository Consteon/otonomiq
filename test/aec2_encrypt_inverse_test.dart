import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/crypto/auth_crypto.dart';
import 'package:otonomiq/global.dart';

// Empirical proof for docs/backend/aec2_lqr_crypto_spec.md §6:
// the derived aec2Encrypt is the exact inverse of the shipped aec2Decrypt.
// Ported verbatim from the spec (dummy key — NOT the real ftzSecretSixCode).

String aec2Encrypt(String keyHex, String payload, String nonce24) {
  const m = [0, 13, 17, 19, 23, 29];
  const mod = 4096;
  final keyByte = keyHex.length ~/ 2;
  final keyVec = <int>[0];
  for (var j = 0; j < keyByte; j++) {
    keyVec.add(int.parse(keyHex.substring(j * 2, j * 2 + 2), radix: 16));
  }
  final plain = nonce24 + payload;
  var out = '', lastPass = 0, lastXor = 0, keyCursor = 0;
  final inputVec = <int>[0];
  for (var i = 0; i < plain.length; i++) {
    final sym = base64ToDec(plain[i]);
    final value2 = (i == 0)
        ? (keyVec[1] * m[1] * m[2]) % mod
        : (lastPass * m[1] +
                  keyVec[keyCursor + 1] * m[2] +
                  lastXor * m[3] +
                  inputVec[i] * m[4]) %
              mod;
    final value = sym ^ value2;
    out += a64[value >> 6] + a64[value & 63];
    inputVec.add(value);
    lastPass = value2;
    lastXor = sym;
    keyCursor = (keyCursor + 1) % keyByte;
  }
  return '2$out';
}

void main() {
  const nonce = 'AAAAAAAAAAAAAAAAAAAAAAAA'; // 24 a64 chars, test-only
  const key = 'abcdef1234567890a1b2c3d4e5f60718'; // dummy 16-byte hex key

  test('nonce is exactly 24 symbols', () => expect(nonce.length, 24));

  test('encrypt then real aec2Decrypt round-trips the payload', () {
    for (final payload in ['l0a1b2c3', 'l', 'ab', 'gudang-cikarang_01', '9f8e7d6c5b4a']) {
      final ct = aec2Encrypt(key, payload, nonce);
      expect(ct[0], '2'); // version byte
      expect((ct.length - 1) % 2, 0); // even body
      // strip version byte, feed the exact shipped decryptor:
      expect(aec2Decrypt(key, ct.substring(1)), payload,
          reason: 'round-trip failed for "$payload"');
    }
  });

  test('wrong key drifts xor out of [0,63] and throws (no MAC, unguarded a64[])', () {
    // Confirms spec §8.1/§8.5: a64[xorValue] has no bounds check, so a bad key
    // usually throws RangeError rather than returning silent garbage.
    // In production aecDecrypt() wraps this in try/catch (found=false).
    final ct = aec2Encrypt(key, 'l0a1b2c3', nonce).substring(1);
    expect(() => aec2Decrypt('00112233445566778899aabbccddeeff', ct),
        throwsA(isA<RangeError>()));
  });
}
