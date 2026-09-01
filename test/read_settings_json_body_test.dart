import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart';

void main() {
  group('looksLikeJson', () {
    // The gate both readSettingsStart and readSettingsContext use before
    // handing a response body to jsonDecode. Getting it wrong either way is
    // costly: a false negative silently keeps the cached UI on a perfectly
    // good payload, a false positive throws FormatException on a routine
    // refresh and logs a Crashlytics non-fatal.

    test('real readSS payloads pass', () {
      expect(looksLikeJson('[["home","{}"]]'), isTrue);
      expect(looksLikeJson('{"systemRange":"A1:B2"}'), isTrue);
      // The backend indents/newlines some responses; the leading whitespace
      // must not disqualify them.
      expect(looksLikeJson('\n\t  [1,2,3]'), isTrue);
    });

    test('gateway plain-text answers are rejected', () {
      // The body that actually reached jsonDecode in production.
      expect(looksLikeJson('upstream request timeout'), isFalse);
      expect(looksLikeJson('<html><body>502</body></html>'), isFalse);
    });

    test('empty and whitespace-only bodies are rejected', () {
      expect(looksLikeJson(''), isFalse);
      expect(looksLikeJson('   '), isFalse);
      expect(looksLikeJson('\n\t '), isFalse);
    });

    test('trailing whitespace is not trimmed, and does not matter', () {
      // Only the first non-space character is inspected, so a trailing newline
      // (which every one of these bodies has) can never flip the verdict.
      expect(looksLikeJson('{}  \n'), isTrue);
      expect(looksLikeJson('nope  \n'), isFalse);
    });
  });
}
