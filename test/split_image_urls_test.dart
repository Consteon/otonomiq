import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/panel_card_support.dart';

// Regression: a ◇-joined image field reached Image.network whole, so Firebase
// Storage answered 403 (url #2 sat inside url #1's ?token=) and the unhandled
// load error was reported as a Crashlytics fatal.
void main() {
  const String u1 =
      'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/a.jpg?alt=media&token=aaa';
  const String u2 =
      'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/b.jpg?alt=media&token=bbb';

  test('splits the ◇-joined field into whole urls', () {
    expect(splitImageUrls('$u1◇$u2'), <String>[u1, u2]);
  });

  test('single url passes through', () {
    expect(splitImageUrls(u1), <String>[u1]);
  });

  test('empty and blank-only fields yield no urls', () {
    expect(splitImageUrls(''), isEmpty);
    expect(splitImageUrls('◇◇'), isEmpty);
    expect(splitImageUrls('   '), isEmpty);
  });

  test('trailing separator and padding are dropped', () {
    expect(splitImageUrls('  $u1  ◇'), <String>[u1]);
  });
}
