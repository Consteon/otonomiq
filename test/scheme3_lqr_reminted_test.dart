import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/crypto/auth_crypto.dart';
import 'package:otonomiq/widget/scanner.dart';

/// End-to-end check of the re-minted `lqr` / `aqr` sheet, run through the REAL
/// decode path the scanner uses: scheme3Token -> scheme3Base45Decode -> Ed25519
/// verify -> scheme3Unpack -> scannerScheme3Lqr.
///
/// Every token here is copied verbatim out of the production sheet
/// `1yGkPJoFT5eO9kBdg5R52yV4PB5QeLeOeaRKJhaaznZE` and the key is the one the app
/// actually reads at runtime -- `public_keys/62000000000000` on authenium-prod1,
/// in the exact standard-base64 spelling Firestore stores.
///
/// The point of the OLD-token case is not coverage: it pins the diagnosis. The
/// sheet's previous tokens were signed by a key that no longer exists anywhere,
/// so the app must call them `QR palsu` -- and does.
void main() {
  // public_keys/62000000000000 -> keys.1, verbatim from Firestore.
  const String kTenant62Key = r'8Fy8NgBKJQc+rR85YlZvlwiBFy1lg+88ivJ6zSc3QDE=';

  // lqr!E11, re-minted 2026-09-02. Location ID column D = 0qwISXE0sLhk9_GrbQljy9g
  const String kNewGate = r'3X62H10 30ZB04UBFQ5Q83/+VFWR0BBL6VWH73P06:O9IL7U6Z0WF2S%:MY.QMGV7RE0OQDD9$$UZ9HAVM/WOXXIZN4%PA66G$H4*-R :849MNB4LHNZT60$Q6XI9DT30';

  // The token that sat in lqr!E11 BEFORE the re-mint.
  const String kOldGate = r'3X62H10 30ZB04UBFQ5Q83/+VFWR0BB65VL-QCB1%3J6:KP 7WCG$A3JFM6UE95N0HCIOAEDCN$F68D:PUMJ0RQJ54VLJEB16Y1E-7W92WPH4DG2C.7$6GVT7Q*OP4QD0';

  // lqr!E29, subtype column B = 'room'. Location ID = 0pOAPzEyLAtM7Ietvn676Gg
  const String kNewRoom = r'3X62H10WK0TESA$P PHUVQ/C405EJ5MCE320I1VJF.PPWSU.N*OMZX7B$N+T5SFWZD2NY0VBKP3WO24VY1CDI6:OMPSQD9+L8VO5-VT%NPOUMEMG22ERX6O-8P S$EU10';

  // aqr!E6. Asset ID column D = 0Gq6GPyO_gd_8zda_1XKcBg
  const String kNewAsset = r'3Y74-K0N3S%2M8:7K9OAES:0QEBO0ME:$07X9PTI*6I31VA4DF 9D/AA*BI17DT8.QBNKVJ BS:7.TANUHYCLAKJ2KM/W7Q11$FMROOFMIGF024J4UV+9PO7C2RUCFGC0';

  late Scheme3Keyring keys;

  setUp(() {
    final List<int> parsed = scheme3ParseKey(kTenant62Key);
    expect(parsed.length, 32, reason: 'tenant 62 public key must parse to 32 bytes');
    keys = <int, List<List<int>>>{
      1: <List<int>>[parsed],
    };
  });

  group('re-minted sheet tokens verify against the live keyring', () {
    test('lqr row 11 (gate) decodes to its Location ID', () async {
      final Scheme3Result r = await decodeScheme3(kNewGate, keys);

      expect(r.status, Scheme3Status.ok, reason: r.detail);
      expect(r.type, 'location');
      expect(r.keyVersion, 1);
      expect(r.value, '0qwISXE0sLhk9_GrbQljy9g');
      expect(r.subtypeId, 0);
    });

    test('the sheet Full URL form decodes identically to the bare token',
        () async {
      final Scheme3Result bare = await decodeScheme3(kNewGate, keys);
      final Scheme3Result url =
          await decodeScheme3('https://autsorz.com/l/$kNewGate', keys);

      // The Base45 body owns both '/' and ' ', so a naive last-slash cut
      // would truncate it. Same value from both forms is the guard.
      expect(url.status, Scheme3Status.ok, reason: url.detail);
      expect(url.value, bare.value);
      expect(url.subtypeId, bare.subtypeId);
    });

    test('lqr row 29 carries subtype room (3), not gate', () async {
      final Scheme3Result r = await decodeScheme3(kNewRoom, keys);

      expect(r.status, Scheme3Status.ok, reason: r.detail);
      expect(r.type, 'location');
      expect(r.value, '0pOAPzEyLAtM7Ietvn676Gg');
      expect(r.subtypeId, 3);
    });

    test('aqr row 6 decodes as an asset with its Asset ID', () async {
      final Scheme3Result r = await decodeScheme3(kNewAsset, keys);

      expect(r.status, Scheme3Status.ok, reason: r.detail);
      expect(r.type, 'asset');
      expect(r.value, '0Gq6GPyO_gd_8zda_1XKcBg');
    });
  });

  group('what the scanner screen actually does with the result', () {
    test('a location badge passes the lqr gate and yields the lookup code',
        () async {
      final Scheme3Result r = await decodeScheme3(kNewGate, keys);

      expect(scannerScheme3Reject(r, expect: 'location'), isNull);
      // Already '0'-prefixed, so scannerLqrCode passes it through untouched --
      // the same shape #LQR_LIST is keyed by.
      expect(scannerScheme3Lqr(r), '0qwISXE0sLhk9_GrbQljy9g');
    });

    test('an asset badge is refused on an lqr screen despite a good signature',
        () async {
      final Scheme3Result r = await decodeScheme3(kNewAsset, keys);

      expect(r.status, Scheme3Status.ok);
      expect(scannerScheme3Reject(r, expect: 'location'), 'QR bukan kartu titik');
      expect(scannerScheme3Lqr(r), '');
    });
  });

  group('the pre-re-mint tokens are exactly what the app should reject', () {
    test('old lqr row 11 fails the signature and reports QR palsu', () async {
      final Scheme3Result r = await decodeScheme3(kOldGate, keys);

      expect(r.status, Scheme3Status.badSignature, reason: r.detail);
      expect(scannerScheme3Reject(r, expect: 'location'), 'QR palsu');
      expect(scannerScheme3Lqr(r), '');
    });

    test('old and new differ ONLY in the signature, never in the identity',
        () async {
      // Both tokens carry the same 21-byte body, so the first 31 Base45
      // characters -- header, country, subtype and the 16-byte id -- are equal.
      // Divergence starts exactly where the signature does.
      expect(kOldGate.substring(0, 31), kNewGate.substring(0, 31));
      expect(kOldGate.substring(31), isNot(kNewGate.substring(31)));
    });
  });
}
