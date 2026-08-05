import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart';
import 'package:otonomiq/global.dart';

/// Covers the two pure steps of loadPagesFromProxy() — the part that decides
/// what ends up in screenUIComponent/systemUIComponent and what type #VID gets.
/// The Firestore I/O around them is not unit-testable here (the repo uses no
/// mock packages); these lock the logic that has actually broken before.
void main() {
  Map<String, dynamic> doc(String name, String content) => {
        'p': name,
        'c': content,
        't': 1,
        'v': 87544551624342,
      };

  group('proxyDocsToUiMap', () {
    test('decodes each document under its page name', () {
      final result = proxyDocsToUiMap([
        doc('home', '{"a":1}'),
        doc('profile', '{"b":2}'),
      ]);

      expect(result.keys, containsAll(<String>['home', 'profile']));
      expect(result['home'], {'a': 1});
      expect(result['profile'], {'b': 2});
    });

    test('skips documents with a blank or missing page name', () {
      final result = proxyDocsToUiMap([
        doc('home', '{"a":1}'),
        doc('', '{"junk":true}'),
        {'c': '{"nameless":true}', 't': 1},
      ]);

      expect(result.length, 1);
      expect(result.containsKey(''), isFalse);
    });

    test('skips null document bodies instead of throwing', () {
      final result = proxyDocsToUiMap([null, doc('home', '{"a":1}')]);
      expect(result.length, 1);
    });

    // Pages: one bad blob must not lose the other 66 pages.
    test('unparsable page falls back to the error page, others survive', () {
      errorPage = '{"error":true}';
      final result = proxyDocsToUiMap(
        [doc('home', '{"a":1}'), doc('broken', 'not json at all')],
        onDecodeError: () => json.decode(errorPage),
      );

      expect(result['home'], {'a': 1});
      expect(result['broken'], {'error': true});
    });

    // System: no safe substitute for a broken system map, so it must throw and
    // let the caller fall back to Sheets rather than commit a half-built theme.
    test('unparsable system doc throws when no fallback is supplied', () {
      expect(
        () => proxyDocsToUiMap([doc('ThemeAgenia', 'not json at all')]),
        throwsFormatException,
      );
    });
  });

  group('proxyProfileKeys', () {
    test('stringifies numeric vid and phone', () {
      final result = proxyProfileKeys({
        'v': 87544551624342,
        'n': 'Agenia Demo-7',
        'e': 'someone@example.com',
        'p': 62812981761217,
      });

      // ★ String, matching settingCell()'s row[0].toString() on the Sheets path.
      expect(result['#VID'], '87544551624342');
      expect(result['#VID'], isA<String>());
      expect(result['#PHONE'], '62812981761217');
      expect(result['#PHONE'], isA<String>());
      expect(result['#NAME'], 'Agenia Demo-7');
      expect(result['#EMAIL'], 'someone@example.com');
    });

    test('omits absent and empty fields rather than blanking them', () {
      final result = proxyProfileKeys({'v': 87544551624342, 'n': '', 'e': null});

      expect(result.keys, ['#VID']);
      expect(result.containsKey('#NAME'), isFalse);
      expect(result.containsKey('#EMAIL'), isFalse);
      expect(result.containsKey('#PHONE'), isFalse);
    });

    test('returns empty map for a null document', () {
      expect(proxyProfileKeys(null), isEmpty);
    });
  });
}
