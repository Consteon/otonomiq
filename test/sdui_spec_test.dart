import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'; // diamondTextToList — raw dependency-contract pin
import 'package:otonomiq/sdui_spec.dart';

void main() {
  group('constructor tolerance', () {
    test('null component → all defaults, no throw', () {
      final s = SduiSpec(null);
      expect(s.text(0), '');
      expect(s.textLength, 0);
      expect(s.str('x', 'd'), 'd');
      expect(s.intOr('x', 7), 7);
      expect(s.list('x'), isEmpty);
      expect(s.has('x'), false);
    });

    test('non-Map component (String, num) → all defaults, no throw', () {
      for (final dynamic c in <dynamic>['oops', 42]) {
        final s = SduiSpec(c);
        expect(s.text(0), '');
        expect(s.textLength, 0);
        expect(s.str('x', 'd'), 'd');
        expect(s.intOr('x', 7), 7);
        expect(s.list('x'), isEmpty);
        expect(s.has('x'), false);
      }
    });
  });

  group('text / textLength', () {
    test('splits ◆ segments', () {
      final s = SduiSpec({'text': 'a◆b◆c'});
      expect(s.text(0), 'a');
      expect(s.text(2), 'c');
      expect(s.textLength, 3);
    });

    test('index out of range → default', () {
      final s = SduiSpec({'text': 'a◆b◆c'});
      expect(s.text(3), '');
      expect(s.text(9, 'X'), 'X');
    });

    test('missing text key → empty', () {
      final s = SduiSpec({'other': 'x'});
      expect(s.textLength, 0);
      expect(s.text(0), '');
    });

    test("{'text': ''} → textLength 0 (SduiSpec short-circuits empty)", () {
      // The raw helper returns [''] for ''; the constructor guard shields us.
      final s = SduiSpec({'text': ''});
      expect(s.textLength, 0);
    });

    test("{'text': '--'} → textLength 0 (sentinel: empty == '--')", () {
      // rawText '--' is non-empty (no short-circuit) → diamondTextToList('--')
      // hits the `empty == "--"` guard (global.dart:364) → [] → textLength 0.
      final s = SduiSpec({'text': '--'});
      expect(s.textLength, 0);
    });

    test('RAW helper contract pin: diamondTextToList empty asymmetry', () {
      // Pinned as the dependency contract (NOT fixed here). diamondTextToList's
      // guard compares against `empty == "--"` (global.dart:364), NOT the empty
      // string — so an empty input takes the jsonDecode `[""]` path:
      expect(diamondTextToList(''), equals([''])); // '' → [''] (length 1!)
      expect(diamondTextToList('--'), isEmpty); // '--' → [] (the sentinel)
      // SduiSpec's constructor short-circuit exists precisely to keep the
      // '' → [''] trap away from widgets (see the {'text': ''} case above).
    });

    test('decode BEFORE split (_u25FC_ escape)', () {
      final s = SduiSpec({'text': '_u25FC_ok◆b'});
      expect(s.text(0), '\u{25FC}ok');
    });

    test('legacy _25FC_ IS decoded', () {
      final s = SduiSpec({'text': '_25FC_x'});
      expect(s.text(0), '\u{25FC}x');
    });

    test('legacy _2B58_ is NOT decoded (commented out in autheniumDecode)', () {
      // Pinned as the real contract: only _25FC_ has a legacy (non-u) form;
      // _2B58_ and the other legacy _XXXX_ forms are commented out.
      final s = SduiSpec({'text': '_2B58_x'});
      expect(s.text(0), '_2B58_x');
    });

    test('decode-before-split: _u25C6_ → ◆ → splits', () {
      final s = SduiSpec({'text': 'a_u25C6_b'});
      expect(s.textLength, 2);
    });
  });

  group('str', () {
    test('missing / null / empty → default', () {
      expect(SduiSpec({'other': 'x'}).str('k'), '');
      expect(SduiSpec({'k': null}).str('k', 'd'), 'd');
      expect(SduiSpec({'k': ''}).str('k', 'd'), 'd');
    });

    test('whitespace-only → def (blank-aware), consistent with has()', () {
      final s = SduiSpec({'label': '   '});
      expect(s.str('label', 'D'), 'D');
      expect(s.has('label'), false);
    });

    test('trims by default', () {
      expect(SduiSpec({'k': '  padded  '}).str('k'), 'padded');
    });

    test('num value stringified', () {
      expect(SduiSpec({'k': 5}).str('k'), '5');
    });

    test('escape decoded', () {
      expect(SduiSpec({'k': '_u2B58_go'}).str('k'), '\u{2B58}go');
    });
  });

  group('intOr', () {
    test('type-tolerant across int / num / string / junk', () {
      expect(SduiSpec({'k': 5}).intOr('k', 0), 5);
      expect(SduiSpec({'k': 5.7}).intOr('k', 0), 5); // truncate
      expect(SduiSpec({'k': '5'}).intOr('k', 0), 5);
      expect(SduiSpec({'k': ' 5 '}).intOr('k', 0), 5); // trim path
      expect(SduiSpec({'k': ''}).intOr('k', 9), 9);
      expect(SduiSpec({'k': 'abc'}).intOr('k', 9), 9);
      expect(SduiSpec({'other': 'x'}).intOr('k', 9), 9); // missing
      expect(SduiSpec({'k': null}).intOr('k', 9), 9);
    });
  });

  group('list', () {
    test("missing / empty → [] and NEVER ['']", () {
      expect(SduiSpec({'other': 'x'}).list('k'), isEmpty);
      expect(SduiSpec({'k': ''}).list('k'), isEmpty);
    });

    test('splits ◆', () {
      expect(SduiSpec({'k': 'a◆b'}).list('k'), ['a', 'b']);
      expect(SduiSpec({'k': 'a'}).list('k'), ['a']);
    });

    test('decode before split', () {
      expect(SduiSpec({'k': '_u25FC_m◆n'}).list('k'), ['\u{25FC}m', 'n']);
    });

    test('jsonDecode-fallback path (value contains ")', () {
      expect(SduiSpec({'k': 'say "hi"◆b'}).list('k'), ['say "hi"', 'b']);
    });
  });

  group('has', () {
    test('missing / empty / whitespace-only → false', () {
      expect(SduiSpec({'other': 'x'}).has('k'), false);
      expect(SduiSpec({'k': ''}).has('k'), false);
      expect(SduiSpec({'k': '   '}).has('k'), false); // trims to empty
    });

    test('real value → true; numeric 0 → true (non-empty "0")', () {
      expect(SduiSpec({'k': 'x'}).has('k'), true);
      expect(SduiSpec({'k': 0}).has('k'), true);
    });
  });
}
