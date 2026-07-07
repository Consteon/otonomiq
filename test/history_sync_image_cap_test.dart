import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';

void main() {
  group('shouldDeferForImage', () {
    test('no pending image never defers (hasAum=false)', () {
      expect(
        shouldDeferForImage(forceSend: false, hasAum: false, newTries: 1),
        isFalse,
      );
      expect(
        shouldDeferForImage(forceSend: false, hasAum: false, newTries: 99),
        isFalse,
      );
    });

    test('forceSend never defers even with a pending image', () {
      expect(
        shouldDeferForImage(forceSend: true, hasAum: true, newTries: 1),
        isFalse,
      );
    });

    test('under cap defers', () {
      expect(
        shouldDeferForImage(
            forceSend: false, hasAum: true, newTries: 1, max: 5),
        isTrue,
      );
      expect(
        shouldDeferForImage(
            forceSend: false, hasAum: true, newTries: 4, max: 5),
        isTrue,
      );
    });

    test('at cap proceeds (does not defer)', () {
      expect(
        shouldDeferForImage(
            forceSend: false, hasAum: true, newTries: 5, max: 5),
        isFalse,
      );
    });

    test('past cap proceeds', () {
      expect(
        shouldDeferForImage(
            forceSend: false, hasAum: true, newTries: 6, max: 5),
        isFalse,
      );
    });

    test('default max is historyImageRetryMax (5)', () {
      expect(historyImageRetryMax, 5);
      expect(
        shouldDeferForImage(forceSend: false, hasAum: true, newTries: 4),
        isTrue,
      );
      expect(
        shouldDeferForImage(forceSend: false, hasAum: true, newTries: 5),
        isFalse,
      );
    });
  });
}
