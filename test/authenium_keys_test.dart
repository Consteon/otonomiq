import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/crypto/auth_crypto.dart';
import 'package:otonomiq/firestore_repository/authenium_keys.dart';

/// Real keys from authenium-prod1 / public_keys (read 2026-08-27). Public
/// values; the app pulls these same strings from Firestore at runtime.
const String kTenant62Hex =
    'f05cbc36004a25073ead1f3962566f970881172d6583ef3c8af27acd27374031';
const String kTenant00Hex =
    '4955c4d5d9c8c7fbeffbb730a846c827eb0c86bb0b5a452ef38b417e828d56b0';

/// The exact document shape the console shows for public_keys/62000000000000.
Map<String, dynamic> liveDoc() => <String, dynamic>{
      'keys': <String, dynamic>{'1': kTenant62Hex},
      'latest_version': 1,
      'tenant_id': '62000000000000',
    };

void main() {
  group('autheniumParseKeyDoc on the live document shape', () {
    test('parses the single version into 32 raw bytes', () {
      final out = autheniumParseKeyDoc(liveDoc());
      expect(out.keys, [1]);
      expect(out[1], scheme3ParseKey(kTenant62Hex));
      expect(out[1]!.length, 32);
    });

    test('the parsed key actually verifies a production token', () async {
      final out = autheniumMergeKeyDocs([liveDoc()]);
      final r = await decodeScheme3(
          'https://autsorz/l/3MQETna5EBvQXD0tGX8syl1bFupM-qEQ0W5zUm__1GzC5UN-xf6SHhGocLCtuy2hFNhWXHivnMmM9TxkNUFoA5pOr3zTrgiUP',
          out);
      expect(r.status, Scheme3Status.ok);
      expect(r.value, '21567954487028');
    });

    test('latest_version is ignored -- every listed version is trusted', () {
      // latest_version says 1, but a verifier must still accept version 2.
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'1': kTenant62Hex, '2': kTenant00Hex},
        'latest_version': 1,
      });
      expect(out.keys.toList()..sort(), [1, 2]);
    });

    test('a version above 1 alone is kept', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'7': kTenant62Hex},
      });
      expect(out.keys, [7]);
    });
  });

  group('autheniumParseKeyDoc rejects without throwing', () {
    test('null document', () {
      expect(autheniumParseKeyDoc(null), isEmpty);
    });

    test('document with no keys field', () {
      expect(
          autheniumParseKeyDoc(<String, dynamic>{'latest_version': 1}), isEmpty);
    });

    test('keys is not a map', () {
      expect(autheniumParseKeyDoc(<String, dynamic>{'keys': 'nope'}), isEmpty);
      expect(autheniumParseKeyDoc(<String, dynamic>{'keys': 5}), isEmpty);
      expect(autheniumParseKeyDoc(<String, dynamic>{'keys': <String>[]}),
          isEmpty);
    });

    test('empty keys map', () {
      expect(autheniumParseKeyDoc(<String, dynamic>{'keys': <String, dynamic>{}}),
          isEmpty);
    });

    test('a null value is skipped, not crashed on', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'1': null, '2': kTenant62Hex},
      });
      expect(out.keys, [2]);
    });
  });

  group('autheniumParseKeyDoc: one bad entry must not disable the others', () {
    test('non-numeric version key is skipped', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'latest': kTenant00Hex, '1': kTenant62Hex},
      });
      expect(out.keys, [1]);
      expect(out[1], scheme3ParseKey(kTenant62Hex));
    });

    test('malformed hex value is skipped', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'1': 'not-a-key', '2': kTenant62Hex},
      });
      expect(out.keys, [2]);
    });

    test('a short key is skipped, not stored at the wrong length', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'1': 'f05cbc36', '2': kTenant62Hex},
      });
      expect(out.keys, [2]);
      expect(out[1], isNull);
    });

    test('a numeric (non-string) value is skipped', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'1': 12345, '2': kTenant62Hex},
      });
      expect(out.keys, [2]);
    });

    test('every entry bad -> empty, which is what the anti-clobber floor '
        'in the listener checks for', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{'1': 'nope', 'x': 'also-nope'},
      });
      expect(out, isEmpty);
    });
  });

  group('autheniumParseKeyDoc accepts the alternate key encoding', () {
    test('base64url value parses to the same bytes as hex', () {
      const String b64 = '8Fy8NgBKJQc-rR85YlZvlwiBFy1lg-88ivJ6zSc3QDE';
      final out =
          autheniumParseKeyDoc(<String, dynamic>{'keys': <String, dynamic>{'1': b64}});
      expect(out[1], scheme3ParseKey(kTenant62Hex));
    });

    test('surrounding whitespace in the version key is tolerated', () {
      final out = autheniumParseKeyDoc(<String, dynamic>{
        'keys': <String, dynamic>{' 1 ': kTenant62Hex},
      });
      expect(out.keys, [1]);
    });
  });

  group('autheniumKeys guards', () {
    // A whitespace-only filter must not be treated as a real tenant id. It
    // cannot reach Firebase here, so this only pins the trim.
    test('a whitespace tenant id trims to the all-tenants filter', () async {
      expect(await autheniumKeys(tenantId: '   '), isEmpty);
    });
  });

  group('autheniumMergeKeyDocs (all tenants in one keyring)', () {
    test('two tenants both publishing version 1 give two candidates', () {
      final out = autheniumMergeKeyDocs([
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant62Hex}},
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant00Hex}},
      ]);
      expect(out.keys, [1]);
      expect(out[1], hasLength(2));
      // `contains` compares elements with ==, and Uint8List == is identity, so
      // match on content instead.
      final seen = out[1]!.map((k) => k.join(',')).toList();
      expect(seen, contains(scheme3ParseKey(kTenant62Hex).join(',')));
      expect(seen, contains(scheme3ParseKey(kTenant00Hex).join(',')));
    });

    test('the same key published twice is collapsed, not verified twice', () {
      final out = autheniumMergeKeyDocs([
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant62Hex}},
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant62Hex}},
      ]);
      expect(out[1], hasLength(1));
    });

    test('different versions stay in their own slots', () {
      final out = autheniumMergeKeyDocs([
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant62Hex}},
        <String, dynamic>{'keys': <String, dynamic>{'2': kTenant00Hex}},
      ]);
      expect(out.keys.toList()..sort(), [1, 2]);
      expect(out[1], hasLength(1));
      expect(out[2], hasLength(1));
    });

    test('a broken document does not poison the others', () {
      final out = autheniumMergeKeyDocs([
        <String, dynamic>{'keys': 'nope'},
        null,
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant62Hex}},
      ]);
      expect(out[1], hasLength(1));
    });

    test('no documents, or none usable, yields empty -- which the listener '
        'floor treats as "keep what we had"', () {
      expect(autheniumMergeKeyDocs(const []), isEmpty);
      expect(
          autheniumMergeKeyDocs([
            <String, dynamic>{'keys': <String, dynamic>{'1': 'nope'}}
          ]),
          isEmpty);
    });

    test('the live three-tenant collection merges to one version, three keys',
        () {
      final out = autheniumMergeKeyDocs([
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant62Hex}},
        <String, dynamic>{'keys': <String, dynamic>{'1': kTenant00Hex}},
        <String, dynamic>{
          'keys': <String, dynamic>{
            '1': '3a440c8facf16315a911d0ce44d491d41987ca110ffcd981a1eb81b7ab3981a2'
          }
        },
      ]);
      expect(out.keys, [1]);
      expect(out[1], hasLength(3));
    });
  });
}
