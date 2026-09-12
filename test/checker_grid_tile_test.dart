import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/ftz_checker.dart';
import 'package:otonomiq/widget/ui_component.dart';

// The VTL home moved its two attendance buttons out of `horizontal_icon` into
// the `hgr` v6 shortcut grid so they stop drawing the legacy white card. That
// only works if buildGridList recognises a `checker` child as a WIDGET item:
// the route tile it builds for every other child navigates on tap and would
// silently swallow the scan/photo flow.
void main() {
  test('buildGridList builds a checker child as FtzChecker in grid mode', () {
    final List<Object?> built = buildGridList(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'checker',
          'text': 'Absen Masuk◆OK',
          'url': '',
          'route': 'vertikaTeknoLokacipta',
        },
        <String, dynamic>{
          'type': 'goto',
          'text': 'Cuti',
          'url': '',
          'route': 'cuti',
        },
      ],
      14,
      'vertikaTeknoLokacipta',
      variant: 'v6',
    );

    expect(built.length, 2);
    final Object? checker = built[0];
    expect(checker, isA<FtzChecker>());
    // false = draw the bare quick tile; true would re-add the Center/SizedBox
    // white card the legacy call sites still use.
    expect((checker! as FtzChecker).single, isFalse);
    expect(built[1], isNot(isA<FtzChecker>()));
  });

  test('buildGridList tolerates a null/empty children payload', () {
    expect(buildGridList(null, 14, 'scr'), isEmpty);
    expect(buildGridList(<dynamic>[], 14, 'scr'), isEmpty);
  });
}
