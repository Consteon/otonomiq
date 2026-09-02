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

  // Production mints Scheme 3 badges in Base45, not the base64url the two
  // guides document. The alphabet carries ' ' and '/', both of which used to
  // destroy a real scan before it ever reached the verifier.
  group('Base45 (RFC 9285)', () {
    String txt(List<int> b) => String.fromCharCodes(b);

    test('the RFC 9285 section 4.3 vectors decode to their bytes', () {
      expect(txt(scheme3Base45Decode('BB8')), 'AB');
      expect(txt(scheme3Base45Decode('%69 VD92EX0')), 'Hello!!');
      expect(txt(scheme3Base45Decode('UJCLQE7W581')), 'base-45');
      expect(txt(scheme3Base45Decode('QED8WEX0')), 'ietf!');
    });

    test('rejects out-of-alphabet, lone-tail, and overflowing groups', () {
      expect(scheme3Base45Decode('bb8'), isEmpty, reason: 'lowercase');
      expect(scheme3Base45Decode('BB8B'), isEmpty, reason: '1 leftover char');
      expect(scheme3Base45Decode('GGW'), isEmpty, reason: '65536 > 0xFFFF');
      expect(scheme3Base45Decode('::'), isEmpty, reason: '2024 > 0xFF');
      expect(scheme3Base45Decode('AB_'), isEmpty, reason: 'underscore');
    });

    test('empty input decodes to empty without throwing', () {
      expect(scheme3Base45Decode(''), isEmpty);
    });

    // Why the 67-byte floor — not "it decoded" — picks the encoding. An
    // all-uppercase base64url body is legal Base45 too, so without the floor
    // Base45 would swallow it; with the floor it comes up short and the base64
    // fallback runs. That is what keeps the fallback from being dead code.
    test('an all-uppercase base64url body is too short read as Base45', () {
      final String body = 'ABC' * 32; // 96 chars, legal in both alphabets
      expect(scheme3Base45Decode(body).length, 64);
    });

    test('a body legal in BOTH alphabets is routed to base64, not Base45',
        () async {
      // Asserts the SELECTOR, not the decoder. Base45 reads these 96 chars as
      // 64 bytes and base64 as 72, so the two readings land on different
      // replies: reaching the header check proves the 67-byte floor sent it
      // down the base64 branch. Drop the floor and this becomes
      // "token 64B, minimum 67".
      final r = await decodeScheme3('3${'ABC' * 32}', keyring);
      expect(r.status, Scheme3Status.unsupportedType);
      expect(r.detail, contains('format version'));
    });
  });

  // The badge as it actually leaves the printer, scanned 2026-09-02. TWO
  // things in this one string broke the old reader: a SPACE (Base45 index 36)
  // and a `/` inside the body. scheme3Token cut at the LAST `/`, leaving
  // `KP*A`; the remains fell through to getVidUQR, which answered -1, which
  // the operator read as "tidak dikenal" with nothing in the log to explain it.
  group('real production Base45 badge', () {
    const String kRealUrl =
        'https://autsorz.com/u/3Z86KI7-K3G QWQFIZFOAGWAK52Q8+68TDUA2Y*Q7.LJ0IR'
        'UM+51U7BWDJCOEGKRFSSB01EE9K23HH6VCD4VC8RDZ-7RSD7WHYLE4OEX/KP*A';

    /// authenium-prod1 / public_keys / 00000000000000 / keys.1 — the key that
    /// actually signs production badges. NOT 62000000000000: that document
    /// exists and holds a different key, so pinning `ten` to it would reject
    /// every real card.
    const String kSignerHex =
        '3d98881ccb67d9b2e58d1dceab4251646b344835dd9287847b155275248f2d6f';

    test('the token survives the URL split intact', () {
      final String token = scheme3Token(kRealUrl);
      expect(token, kRealUrl.split('/u/').last);
      expect(token.length, 109);
      expect(token.contains(' '), isTrue, reason: 'Base45 space must survive');
      expect(token.contains('/'), isTrue, reason: 'Base45 slash must survive');
    });

    test('verifies end to end and yields the 14-digit VID', () async {
      final r = await decodeScheme3(kRealUrl, {
        1: [scheme3ParseKey(kSignerHex)]
      });
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'user');
      expect(r.keyVersion, 1);
      expect(r.value, '64446444131342');
    });

    test('the 62000000000000 key does not verify it', () async {
      final r = await decodeScheme3(kRealUrl, keyring);
      expect(r.status, Scheme3Status.badSignature);
    });

    // The int-shaped contract getVidUQR hands its four callers. Tested here
    // rather than through getVidUQR, which fetches the keyring from Firestore
    // and so cannot run in a plain test.
    group('scheme3Vid', () {
      final Scheme3Keyring signer = {
        1: [scheme3ParseKey(kSignerHex)]
      };

      test('ok yields the VID as an int', () async {
        expect(await scheme3Vid(kRealUrl, signer), 64446444131342);
      });

      test('a wrong key collapses to -1, not to a number', () async {
        expect(await scheme3Vid(kRealUrl, keyring), -1);
      });

      test('an unsynced key version is -1', () async {
        expect(await scheme3Vid(kRealUrl, const {}), -1);
      });

      test('a malformed token is -1', () async {
        expect(await scheme3Vid('3!!!!', signer), -1);
      });

      test('a legacy badge is -1 — it never belonged on this path', () async {
        expect(
            await scheme3Vid('https://autsorz.com/qr/1abcDEF', signer), -1);
      });

      // ★★★ REGRESSION. A genuine LOCATION badge is not a person. This one
      // verifies against its own published key — status `ok` — and its short
      // payload takes the numeric branch of scheme3Unpack, so `value` is the
      // plain string '101'. Gating on `ok` alone hands that straight back as
      // "VID 101", and the operator is told a person is missing from the
      // workforce list rather than that they scanned the wrong kind of card.
      test('a genuine LOCATION badge is -1, however numeric it looks', () async {
        final r = await decodeScheme3(kLocation101, keyring);
        expect(r.status, Scheme3Status.ok, reason: 'genuinely verified');
        expect(r.type, 'location');
        expect(int.tryParse(r.value), 101, reason: 'it DOES parse as a number');
        expect(await scheme3Vid(kLocation101, keyring), -1);
      });

      // The whole point of the int contract: EVERY failure looks the same to
      // the caller, so nothing may leak through as a plausible number.
      test('no failure status escapes as anything but -1', () async {
        for (final bad in <String>['', '3', '3ABC', kCounterfeit]) {
          final int v = await scheme3Vid(bad, signer);
          expect(v, -1, reason: 'input ${bad.isEmpty ? '<empty>' : bad}');
        }
      });

      // Pins the coupling that makes the status half of the gate redundant:
      // `type` becomes 'user' only after verification. Asserted rather than
      // trusted — set `type` in a failure branch and the gate opens silently
      // while every test above still passes.
      test('no failing status ever carries type user', () async {
        for (final bad in <String>['3ABC', kCounterfeit, kLocation101]) {
          final r = await decodeScheme3(bad, signer);
          expect(r.status, isNot(Scheme3Status.ok), reason: bad);
          expect(r.type, isNot('user'), reason: bad);
        }
        // unknownKeyVersion reaches no unpacker at all.
        expect((await decodeScheme3(kRealUrl, const {})).type, isNot('user'));
      });
    });
  });

  // A real point badge, handed over for the location trial on 2026-09-02. It
  // is signed by tenant 62000000000000 — kPubHex, the key `keyring` holds —
  // unlike the user badges, which tenant 00000000000000 signs. Note also that
  // the four tokens sitting in the lqr SHEET do NOT verify: they were minted
  // with an older private key and re-minted afterwards. The published key was
  // never the problem there; the sheet was stale.
  group('real production point badge (lqr)', () {
    const String kRealPoint =
        'https://autsorz.com/l/3X62H10 30ZB04UBFQ5Q83/+VFWR0BBL6VWH73P06:O9IL'
        '7U6Z0WF2S%:MY.QMGV7RE0OQDD9\$\$UZ9HAVM/WOXXIZN4%PA66G\$H4*-R :849MNB'
        '4LHNZT60\$Q6XI9DT30';

    test('the token survives a URL whose path is /l/', () {
      expect(scheme3Token(kRealPoint), kRealPoint.split('/l/').last);
      expect(scheme3Token(kRealPoint).length, 129);
    });

    test('verifies and unpacks to the publisher own Location ID', () async {
      final r = await decodeScheme3(kRealPoint, keyring);
      expect(r.status, Scheme3Status.ok);
      expect(r.type, 'location');
      expect(r.keyVersion, 1);
      expect(r.subtypeId, 0);
      // Character-for-character the `Location ID` column of the lqr sheet.
      expect(r.value, '0qwISXE0sLhk9_GrbQljy9g');
    });

    // ★★★ The leading '0' STAYS. Measured on a real device, not reasoned: a
    // live #LQR_LIST holds keys like
    // `0lefc05bc4c884bd590a3a13c8d99663b1dfd371d8`. An earlier version stripped
    // it because `lqr_code_test` round-trips makeLqrCode as `code.substring(1)`
    // — but that test feeds makeLqrCode's output in as though it were the whole
    // QR string, and makeLqrCode documents itself as a stand-in for a generator
    // whose real algorithm is unknown. It pins mechanics, never production.
    test('scheme3LqrCode keeps the marker #LQR_LIST is actually keyed by',
        () async {
      expect(await scheme3LqrCode(kRealPoint, keyring),
          '0qwISXE0sLhk9_GrbQljy9g');
    });

    test('the value matches the publisher own Location ID column verbatim',
        () async {
      // Nothing may be added or trimmed between the two — the sheet column is
      // the id, and #LQR_LIST is keyed by ids of that same shape.
      final r = await decodeScheme3(kRealPoint, keyring);
      expect(await scheme3LqrCode(kRealPoint, keyring), r.value);
    });

    test('the short numeric form keeps every digit', () {
      // An 8-byte payload unpacks to a bare decimal — no version marker to
      // strip, so a leading-zero rule alone would corrupt it.
      expect(scheme3Unpack(1, 1, const [0, 62, 0, 0, 0, 0, 0, 101]).value,
          '101');
    });

    // ★★★ A verified USER badge must not resolve as a place. Its value is a
    // 14-digit number; returned here, getQRContent would look a person up in
    // the geofence table and then measure GPS distance to them.
    test('a verified USER badge yields no location code', () async {
      expect(await scheme3LqrCode(kUser49729, keyring), '');
    });

    test('every non-ok outcome yields an empty code', () async {
      expect(await scheme3LqrCode(kCounterfeit, keyring), '');
      expect(await scheme3LqrCode(kRealPoint, const {}), '');
      expect(await scheme3LqrCode('3!!!!', keyring), '');
      expect(await scheme3LqrCode('https://autsorz.com/qr/1abc', keyring), '');
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
