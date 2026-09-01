import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/crypto/auth_crypto.dart';

/// Real public key, tenant 62000000000000, keyVersion 1
/// (authenium-prod1 / public_keys / 62000000000000 / keys.1).
///
/// This is a PUBLIC key — embedding it here is intentional. It is the same
/// value the app pulls from Firestore at runtime.
const String kPubHex =
    'f05cbc36004a25073ead1f3962566f970881172d6583ef3c8af27acd27374031';

/// The four vectors from flutter_integration_guide.md section 6.
const String kUser49729 =
    'https://autsorz/l/3MQETna5EBvQXD0tGX8syl1bFupM-qEQ0W5zUm__1GzC5UN-xf6SHhGocLCtuy2hFNhWXHivnMmM9TxkNUFoA5pOr3zTrgiUP';
const String kUser49730 =
    'https://autsorz/l/3MQFNP05CrlEeqLetm90Rpd8ESXHaDwhR5pUpt4yeBVzd-s9GAhIDZLTgDllzzCl2em1uuiSZ-jo64zr64KA5ETlqhm4MB-IJ';
const String kLocation101 =
    'https://autsorz/l/3EQEBaAMAAAAAZXM85Ixdx-gkzu1AFuV8gVg0MuYKTFQUBpUjDJeg5mJw_FREzniRIm1PEws-d9M3lBjQpOki9ovjLpWIr1BZMQg';

/// Same bytes as [kUser49729] except the last signature byte.
const String kCounterfeit =
    'https://autsorz/l/3MQETna5EBvQXD0tGX8syl1bFupM-qEQ0W5zUm__1GzC5UN-xf6SHhGocLCtuy2hFNhWXHivnMmM9TxkNUFoA5pOr3zTrgiUX';

void main() {
  final Scheme3Keyring keyring = {
    1: [scheme3ParseKey(kPubHex)]
  };

  group('scheme3ParseKey', () {
    test('accepts 64-char hex', () {
      expect(scheme3ParseKey(kPubHex).length, 32);
    });

    test('accepts the same key as base64url', () {
      // 32 bytes -> 43 base64url chars, unpadded.
      const String b64 = '8Fy8NgBKJQc-rR85YlZvlwiBFy1lg-88ivJ6zSc3QDE';
      expect(scheme3ParseKey(b64), scheme3ParseKey(kPubHex));
    });

    test('rejects a wrong-length hex string', () {
      expect(scheme3ParseKey('f05cbc36'), isEmpty);
    });

    test('rejects a non-hex string of the right length', () {
      expect(scheme3ParseKey('z' * 64), isEmpty);
    });

    test('rejects empty input without throwing', () {
      expect(scheme3ParseKey(''), isEmpty);
      expect(scheme3ParseKey('   '), isEmpty);
    });
  });

  group('decodeScheme3 against the production key', () {
    test('user badge 49729 verifies and yields the 14-digit VID', () async {
      final r = await decodeScheme3(kUser49729, keyring);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'user');
      expect(r.keyVersion, 1);
      expect(r.value, '21567954487028');
    });

    test('user badge 49730 verifies', () async {
      final r = await decodeScheme3(kUser49730, keyring);
      expect(r.status, Scheme3Status.ok);
      expect(r.value, '84934291271249');
    });

    test('location 101 verifies and yields the uid', () async {
      final r = await decodeScheme3(kLocation101, keyring);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'location');
      expect(r.value, '101');
      expect(r.subtypeId, 3);
    });

    test('counterfeit is rejected as a bad signature, not as malformed',
        () async {
      final r = await decodeScheme3(kCounterfeit, keyring);
      expect(r.status, Scheme3Status.badSignature);
      expect(r.isValid, isFalse);
    });

    test('raw token without the URL wrapper decodes the same', () async {
      final raw = kUser49729.split('/l/').last;
      final r = await decodeScheme3(raw, keyring);
      expect(r.status, Scheme3Status.ok);
      expect(r.value, '21567954487028');
    });

    test('surrounding whitespace is tolerated', () async {
      final r = await decodeScheme3('  $kUser49729\n', keyring);
      expect(r.status, Scheme3Status.ok);
      expect(r.value, '21567954487028');
    });
  });

  group('decodeScheme3 rejection paths', () {
    test('empty keyring reports unknownKeyVersion, never ok', () async {
      final r = await decodeScheme3(kUser49729, const {});
      expect(r.status, Scheme3Status.unknownKeyVersion);
      expect(r.isValid, isFalse);
    });

    test('a key registered under the wrong version is not consulted', () async {
      final r = await decodeScheme3(kUser49729, {
        2: [scheme3ParseKey(kPubHex)]
      });
      expect(r.status, Scheme3Status.unknownKeyVersion);
      expect(r.keyVersion, 1);
    });

    test('a short (non-32-byte) key is treated as no key at all', () async {
      final r = await decodeScheme3(kUser49729, {
        1: const [
          [1, 2, 3]
        ]
      });
      expect(r.status, Scheme3Status.unknownKeyVersion);
    });

    test('a valid 32-byte key that is the WRONG key fails the signature',
        () async {
      // Another real tenant's key (public_keys/00000000000000). Correct length,
      // correct format, wrong signer.
      final other = scheme3ParseKey(
          '4955c4d5d9c8c7fbeffbb730a846c827eb0c86bb0b5a452ef38b417e828d56b0');
      final r = await decodeScheme3(kUser49729, {
        1: [other]
      });
      expect(r.status, Scheme3Status.badSignature);
    });

    test('non-scheme-3 prefix is refused before any crypto', () async {
      final r = await decodeScheme3('https://autsorz.com/qr/2abcdef', keyring);
      expect(r.status, Scheme3Status.notScheme3);
    });

    test('empty input is refused', () async {
      final r = await decodeScheme3('', keyring);
      expect(r.status, Scheme3Status.notScheme3);
    });

    test('truncated token is malformed, not a crash', () async {
      final r = await decodeScheme3('3MQETna5EBvQXD0tGX8syl1bFupM', keyring);
      expect(r.status, Scheme3Status.malformed);
    });

    test('non-base64 body is malformed, not a crash', () async {
      final r = await decodeScheme3('3!!!!not base64!!!!', keyring);
      expect(r.status, Scheme3Status.malformed);
    });
  });

  // The unpack seam is tested WITHOUT a signature on purpose. Feeding these
  // through decodeScheme3 would stop at the signature step and pass for the
  // wrong reason -- we do not hold the private key, so we cannot mint a
  // validly-signed token of an unsupported type.
  group('format version gate', () {
    // Type 3 user badge, header byte 0x32 = type 3 / format 2, key version 1,
    // six payload bytes and 64 zero bytes where a signature would be. The
    // signature is deliberately worthless: the gate must fire before it is
    // ever checked, which is exactly what makes this branch testable without
    // the issuer's private key.
    const String fmt2 =
        '3MgEAAQIDBAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

    test('an unknown format version is refused, not guessed at', () async {
      final r = await decodeScheme3(fmt2, <int, List<List<int>>>{
        1: <List<int>>[List<int>.filled(32, 7)],
      });
      expect(r.status, Scheme3Status.unsupportedType);
      expect(r.isValid, isFalse);
      expect(r.keyVersion, 1);
      expect(r.detail, contains('format version 2'));
    });

    test('format version 1 passes the gate and goes on to the signature',
        () async {
      final r = await decodeScheme3(kUser49729, <int, List<List<int>>>{
        1: <List<int>>[List<int>.filled(32, 7)],
      });
      expect(r.status, Scheme3Status.badSignature);
    });
  });

  group('scheme3Unpack (pure, no signature involved)', () {
    test('user: 6-byte payload -> padded 14-digit VID', () {
      final r = scheme3Unpack(3, 1, const [0x13, 0x9d, 0xae, 0x44, 0x06, 0xf4]);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'user');
      expect(r.value, '21567954487028');
    });

    test('user: a short VID is left-padded to 14 digits', () {
      final r = scheme3Unpack(3, 1, const [0, 0, 0, 0, 0x01, 0x02]);
      expect(r.value, '00000000000258');
      expect(r.value.length, 14);
    });

    test('user: wrong payload length is malformed', () {
      final r = scheme3Unpack(3, 1, const [1, 2, 3]);
      expect(r.status, Scheme3Status.malformed);
    });

    test('location: 8-byte payload -> uid + subtypeId', () {
      final r =
          scheme3Unpack(1, 1, const [0x01, 0x68, 0x03, 0, 0, 0, 0, 0x65]);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'location');
      expect(r.value, '101');
      expect(r.subtypeId, 3);
    });

    // The layout the CURRENT minter writes. Payload lifted byte for byte from
    // the production location token in the developer guide, whose response
    // names the expected id -- so this pins our reconstruction against the
    // vendor's, not against our own arithmetic.
    test('location: 19-byte payload -> the guide\'s own 23-char uid', () {
      final r = scheme3Unpack(1, 1, const [
        0x00, 0x3e, 0x05, //           country 62, subtype 5 (gate)
        0xb0, 0x9e, 0x2c, 0xcb, 0xb7, 0xf8, 0x15, 0x05, //  16 random bytes
        0x44, 0xe3, 0xea, 0xd8, 0xc9, 0xdf, 0x79, 0x6e,
      ]);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'location');
      expect(r.value, '0sJ4sy7f4FQVE4-rYyd95bg');
      expect(r.subtypeId, 5);
    });

    // Guards the branch ORDER. Read under the old 5-byte rule this same
    // payload still returns ok -- carrying '758567979959', a wrong id that looks
    // entirely plausible. That is the failure this ordering exists to stop.
    test('location: 19 bytes must NOT fall through to the 5-byte uid', () {
      final r = scheme3Unpack(1, 1, const [
        0x00, 0x3e, 0x05, //
        0xb0, 0x9e, 0x2c, 0xcb, 0xb7, 0xf8, 0x15, 0x05, //
        0x44, 0xe3, 0xea, 0xd8, 0xc9, 0xdf, 0x79, 0x6e,
      ]);
      expect(r.value, isNot('758567979959'));
      expect(r.value.length, 23);
      expect(r.value[0], '0');
    });

    test('asset: 19-byte payload -> uid, UNSPSC steps aside', () {
      final r = scheme3Unpack(2, 1, const [
        0x06, 0x97, 0xf3, //           UNSPSC 432115 (computers)
        0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, //
        0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f,
      ]);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'asset');
      expect(r.value, '0ICEiIyQlJicoKSorLC0uLw');
    });

    test('location without a uid is malformed (nothing to look up)', () {
      final r = scheme3Unpack(1, 1, const [0x01, 0x68, 0x03]);
      expect(r.status, Scheme3Status.malformed);
    });

    test('asset: uid present wins over UNSPSC', () {
      final r =
          scheme3Unpack(2, 1, const [0x00, 0x2a, 0xf8, 0, 0, 0, 0x01, 0x2c]);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'asset');
      expect(r.value, '300');
    });

    test('asset: no uid falls back to the padded UNSPSC', () {
      final r = scheme3Unpack(2, 1, const [0x00, 0x2a, 0xf8]);
      expect(r.value, '011000');
    });

    test('asset: a 4-digit UNSPSC pads to 4, not 6', () {
      // 0x000101 = 257
      final r = scheme3Unpack(2, 1, const [0x00, 0x01, 0x01]);
      expect(r.value, '0257');
    });

    test('other: reserved byte 0 is skipped, entity id is bytes 1..6', () {
      final r = scheme3Unpack(
          4, 1, const [0xff, 0x13, 0x9d, 0xae, 0x44, 0x06, 0xf4]);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'other');
      expect(r.value, '21567954487028');
    });

    test('other: short payload is malformed, not a RangeError', () {
      final r = scheme3Unpack(4, 1, const [0xff, 0x13]);
      expect(r.status, Scheme3Status.malformed);
    });

    test('a malformed result carries the key version through', () {
      final r = scheme3Unpack(3, 7, const [1, 2, 3]);
      expect(r.keyVersion, 7);
    });

    // THE fail-open guard. The integration guide returns isValid:true here.
    test('an unsupported typeId is REJECTED, never reported valid', () {
      for (final t in const [0, 5, 6, 9, 15]) {
        final r = scheme3Unpack(t, 1, const [1, 2, 3, 4, 5, 6]);
        expect(r.status, Scheme3Status.unsupportedType,
            reason: 'typeId $t must not be accepted');
        expect(r.isValid, isFalse);
      }
    });
  });

  // scheme3Token is the dispatcher: it decides whether a scanned string goes to
  // the new Ed25519 path or falls through to the legacy getVidUQR path. Getting
  // it wrong in EITHER direction is a live badge that stops working.
  group('scheme3Token (old-format / new-format dispatcher)', () {
    test('a Scheme 3 URL yields the token after /l/', () {
      expect(scheme3Token(kUser49729), kUser49729.split('/l/').last);
      expect(scheme3Token(kUser49729)[0], '3');
    });

    // ★ REGRESSION. Production mints Scheme 3 user badges on the SAME `/qr/`
    // path the legacy encrypted badges use -- not the `/l/` that
    // flutter_integration_guide.md documents. An earlier version of this
    // function keyed on `/l/` and silently handed every real badge to
    // getVidUQR, which answered -1, which the operator saw as "tidak dikenal".
    test('a REAL production user badge on the /qr/ path is claimed', () {
      const real = 'https://autsorz.com/qr/3MQE6nRto1A7d8ot8O9BbJ2uRDidp8BUy'
          'Soe_MnveuzCWkv95BDbtPsC_lvwuYh_TGTsU0dPAApD-2YSIAP210aB-3JjjDH4E';
      final token = scheme3Token(real);
      expect(token, isNotEmpty, reason: 'the /qr/ path must not hide a token');
      expect(token[0], '3');
      expect(token, real.split('/qr/').last);
    });

    test('the path segment carries no meaning — any path works', () {
      final bare = kUser49729.split('/l/').last;
      for (final path in const [
        'https://autsorz/l/',
        'https://autsorz.com/qr/',
        'https://example.test/a/b/c/',
        'https://x/',
      ]) {
        expect(scheme3Token('$path$bare'), bare, reason: 'path $path');
      }
    });

    test('a bare Scheme 3 token is returned unchanged', () {
      final bare = kUser49729.split('/l/').last;
      expect(scheme3Token(bare), bare);
    });

    test('a LEGACY user QR is not claimed', () {
      // Same /qr/ path as a Scheme 3 badge, so ONLY the version prefix can
      // separate them: an a64 cipher opens with the aec version, 1 or 2.
      expect(scheme3Token('https://autsorz.com/qr/1abcDEF-_123'), '');
      expect(scheme3Token('https://autsorz.com/qr/2abcDEF-_123'), '');
    });

    test('a legacy cipher containing the letter l is still not claimed', () {
      expect(scheme3Token('https://autsorz.com/qr/1abclllDEF'), '');
    });

    test('a trailing slash or empty segment yields nothing', () {
      expect(scheme3Token('https://autsorz.com/qr/'), '');
      expect(scheme3Token('/'), '');
    });

    test('empty and whitespace yield nothing', () {
      expect(scheme3Token(''), '');
      expect(scheme3Token('   '), '');
      expect(scheme3Token('\n\t'), '');
    });

    test('surrounding whitespace is trimmed before the prefix test', () {
      expect(scheme3Token('  $kUser49729\n'), kUser49729.split('/l/').last);
    });

    test('a non-3 version prefix is not claimed, bare or wrapped', () {
      expect(scheme3Token('2MQETna5'), '');
      expect(scheme3Token('https://autsorz/l/2MQETna5'), '');
    });

    test('agrees with decodeScheme3 on what is and is not Scheme 3', () async {
      const legacy = 'https://autsorz.com/qr/1abcDEF';
      expect(scheme3Token(legacy), '');
      final r = await decodeScheme3(legacy, const {});
      expect(r.status, Scheme3Status.notScheme3);

      expect(scheme3Token(kUser49729), isNotEmpty);
      final r2 = await decodeScheme3(kUser49729, const {});
      expect(r2.status, isNot(Scheme3Status.notScheme3));
    });
  });

  // Multi-tenant acceptance. The tenant boundary was deliberately dropped at
  // the crypto layer: a badge is accepted if ANY published key of its version
  // verifies it, and the workforce lookup is what decides belonging.
  group('multi-tenant keyring', () {
    const String kTenant00Hex =
        '4955c4d5d9c8c7fbeffbb730a846c827eb0c86bb0b5a452ef38b417e828d56b0';
    const String kTenant10Hex =
        '3a440c8facf16315a911d0ce44d491d41987ca110ffcd981a1eb81b7ab3981a2';

    test('the right key is found even when listed last', () async {
      final r = await decodeScheme3(kUser49729, {
        1: [
          scheme3ParseKey(kTenant00Hex),
          scheme3ParseKey(kTenant10Hex),
          scheme3ParseKey(kPubHex),
        ]
      });
      expect(r.status, Scheme3Status.ok);
      expect(r.value, '21567954487028');
    });

    test('the right key is found when listed first', () async {
      final r = await decodeScheme3(kUser49729, {
        1: [scheme3ParseKey(kPubHex), scheme3ParseKey(kTenant00Hex)]
      });
      expect(r.status, Scheme3Status.ok);
    });

    test('every candidate wrong still means badSignature, never ok', () async {
      final r = await decodeScheme3(kUser49729, {
        1: [scheme3ParseKey(kTenant00Hex), scheme3ParseKey(kTenant10Hex)]
      });
      expect(r.status, Scheme3Status.badSignature);
      expect(r.isValid, isFalse);
    });

    test('a counterfeit is not rescued by extra candidate keys', () async {
      final r = await decodeScheme3(kCounterfeit, {
        1: [
          scheme3ParseKey(kTenant00Hex),
          scheme3ParseKey(kPubHex),
          scheme3ParseKey(kTenant10Hex),
        ]
      });
      expect(r.status, Scheme3Status.badSignature);
    });

    test('malformed candidates are skipped, the good one still verifies',
        () async {
      final r = await decodeScheme3(kUser49729, {
        1: [const [1, 2, 3], scheme3ParseKey(kPubHex), const []]
      });
      expect(r.status, Scheme3Status.ok);
    });

    test('a version whose candidates are ALL malformed is unknownKeyVersion',
        () async {
      final r = await decodeScheme3(kUser49729, {
        1: [const [1, 2, 3], const []]
      });
      expect(r.status, Scheme3Status.unknownKeyVersion);
    });

    test('an empty candidate list is unknownKeyVersion, not ok', () async {
      final r = await decodeScheme3(kUser49729, {1: const []});
      expect(r.status, Scheme3Status.unknownKeyVersion);
    });
  });
}
