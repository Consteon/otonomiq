// test/visible_when_test.dart
//
// Pure-function tests for the `visibleWhen` conditional-rendering primitive
// (dev spec visiblewhen-conditional-rendering, §3.1 grammar / §3.2 evaluation
// / §3.4 duplicate positions / §6.5 required coverage).
//
// No pump, no Firebase, no GetX controller. TestWidgetsFlutterBinding is
// initialised only because the visibleWhenReader group constructs real
// TextEditingControllers and assigns InputController.finalData, whose setter
// touches WidgetsBinding.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show emptyString;
import 'package:otonomiq/model/input_controller.dart';
import 'package:otonomiq/widget/visible_when.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // Literal glyphs, written as escapes so a copy/paste cannot silently mangle
  // them. Same code points autheniumDecode produces.
  const String sep = '\u{25FC}'; // ◼
  const String and = '\u{2B58}'; // ⭘
  const String inn = '\u{2605}'; // ★
  const String ro = '\u{25C1}'; // ◁
  const String rc = '\u{25B7}'; // ▷

  /// A map-backed value reader: unfilled positions read as '' (spec §3.2.3).
  VisibleWhenValueReader reader(Map<int, String> values) =>
      (int position) => values[position] ?? '';

  // The pilot form (spec §4): position 2 = JENIS IZIN, 4 = Jam mulai,
  // 5 = Jam selesai, 9 = an always-empty slot, 10 = a numeric slot.
  final VisibleWhenValueReader base = reader(<int, String>{
    2: 'Telat masuk',
    4: '10:00',
    5: '09:00',
    9: '',
    10: '10',
  });

  group('visibleWhenOf', () {
    test('absent key -> ""', () {
      expect(visibleWhenOf(<String, dynamic>{'type': 'TXF'}), '');
    });
    test('explicit null -> ""', () {
      expect(visibleWhenOf(<String, dynamic>{'visibleWhen': null}), '');
    });
    test('blank -> "" (backward compatible, spec §3 table)', () {
      expect(visibleWhenOf(<String, dynamic>{'visibleWhen': '   '}), '');
    });
    test('non-Map -> ""', () {
      expect(visibleWhenOf('not a component'), '');
      expect(visibleWhenOf(null), '');
    });
    test('present value is returned trimmed, NOT decoded', () {
      expect(visibleWhenOf(<String, dynamic>{'visibleWhen': ' 2_25FC_x '}),
          '2_25FC_x');
    });
  });

  group('parseVisibleWhen — malformed returns null (spec §3.2.2)', () {
    test('non-numeric position', () {
      expect(parseVisibleWhen('abc${sep}x'), isNull);
    });
    test('no ◼ at all', () {
      expect(parseVisibleWhen('2x'), isNull);
    });
    test('empty position key', () {
      expect(parseVisibleWhen('${sep}x'), isNull);
    });
    test('★ with != (spec §3.2.7)', () {
      expect(parseVisibleWhen('2$sep!=a${inn}b'), isNull);
    });
    test('★ with > (spec §3.2.7)', () {
      expect(parseVisibleWhen('2$sep>a${inn}b'), isNull);
    });
    test('★ with <= (spec §3.2.7)', () {
      expect(parseVisibleWhen('2$sep<=a${inn}b'), isNull);
    });
    test('◁…▷ with a non-integer inside', () {
      expect(parseVisibleWhen('4$sep<=${ro}abc$rc'), isNull);
    });
    test('one bad clause poisons the whole string', () {
      expect(parseVisibleWhen('2${sep}Telat masuk${and}abc${sep}x'), isNull);
    });
  });

  group('parseVisibleWhen — well-formed', () {
    test('empty -> zero clauses (always visible)', () {
      expect(parseVisibleWhen('')!.isEmpty, isTrue);
    });
    test('bare equality', () {
      final List<VisibleWhenClause> c = parseVisibleWhen('2${sep}Telat masuk')!;
      expect(c.length, 1);
      expect(c[0].position, 2);
      expect(c[0].op, VisibleWhenOp.eq);
      expect(c[0].literal, 'Telat masuk');
      expect(c[0].refPosition, isNull);
      expect(c[0].inList, isNull);
    });
    test('longest-match-first: >= is not parsed as >', () {
      expect(parseVisibleWhen('4$sep>=5')![0].op, VisibleWhenOp.gte);
      expect(parseVisibleWhen('4$sep>=5')![0].literal, '5');
    });
    test('longest-match-first: <= is not parsed as <', () {
      expect(parseVisibleWhen('4$sep<=5')![0].op, VisibleWhenOp.lte);
      expect(parseVisibleWhen('4$sep<=5')![0].literal, '5');
    });
    test('!= parsed, operand keeps the rest', () {
      expect(parseVisibleWhen('9$sep!=')![0].op, VisibleWhenOp.ne);
      expect(parseVisibleWhen('9$sep!=')![0].literal, '');
    });
    test('> and <', () {
      expect(parseVisibleWhen('4$sep>5')![0].op, VisibleWhenOp.gt);
      expect(parseVisibleWhen('4$sep<5')![0].op, VisibleWhenOp.lt);
    });
    test('◁N▷ operand', () {
      final VisibleWhenClause c = parseVisibleWhen('5$sep<=${ro}4$rc')![0];
      expect(c.op, VisibleWhenOp.lte);
      expect(c.refPosition, 4);
      expect(c.literal, '');
    });
    test('★ IN list splits and trims', () {
      final VisibleWhenClause c =
          parseVisibleWhen('2${sep}Paruh hari$inn Telat masuk ')![0];
      expect(c.op, VisibleWhenOp.eq);
      expect(c.inList, <String>['Paruh hari', 'Telat masuk']);
    });
    test('multi-clause ⭘ AND', () {
      expect(parseVisibleWhen('2${sep}Paruh hari${and}5$sep<=${ro}4$rc')!.length,
          2);
    });
    test('empty clause is SKIPPED, not a parse failure', () {
      final List<VisibleWhenClause> c =
          parseVisibleWhen('2${sep}Telat masuk$and')!;
      expect(c.length, 1);
      expect(c[0].literal, 'Telat masuk');
    });
    test('server escapes are decoded before splitting', () {
      final List<VisibleWhenClause> c =
          parseVisibleWhen('2_25FC_Telat masuk_u2B58_10_25FC_>4')!;
      expect(c.length, 2);
      expect(c[0].position, 2);
      expect(c[1].op, VisibleWhenOp.gt);
    });
    test('_u25C1_/_u25B7_ escapes decode into a ◁N▷ operand', () {
      expect(parseVisibleWhen('5_25FC_<=_u25C1_4_u25B7_')![0].refPosition, 4);
    });
  });

  group('visibleWhenCompare (spec §3.2.5 / §3.2.6)', () {
    test('numeric when BOTH sides parse: 10 vs 4 is numeric, not string', () {
      expect(visibleWhenCompare('10', '4')! > 0, isTrue);
    });
    test('string ordinal when either side is not numeric', () {
      expect(visibleWhenCompare('09:00', '10:00')! < 0, isTrue);
      expect(visibleWhenCompare('abc', '10')! > 0, isTrue);
    });
    test('empty left -> null', () {
      expect(visibleWhenCompare('', '5'), isNull);
    });
    test('empty right -> null', () {
      expect(visibleWhenCompare('5', ''), isNull);
    });
    test('whitespace-only counts as empty', () {
      expect(visibleWhenCompare('   ', '5'), isNull);
    });
    test('equal values compare 0', () {
      expect(visibleWhenCompare('5', '5'), 0);
      expect(visibleWhenCompare('abc', 'abc'), 0);
    });
  });

  group('visibleWhenVisible — always-visible cases (spec §3.2.1)', () {
    test('empty string', () {
      expect(visibleWhenVisible('', base), isTrue);
    });
    test('whitespace only', () {
      expect(visibleWhenVisible('   ', base), isTrue);
    });
    test('separator only -> zero clauses', () {
      expect(visibleWhenVisible(and, base), isTrue);
    });
  });

  group('visibleWhenVisible — fail-open on malformed (spec §3.2.2, §9)', () {
    test('abc◼x', () {
      expect(visibleWhenVisible('abc${sep}x', base), isTrue);
    });
    test('2◼>★a', () {
      expect(visibleWhenVisible('2$sep>a${inn}b', base), isTrue);
    });
    test('missing ◼', () {
      expect(visibleWhenVisible('2x', base), isTrue);
    });
    test('empty key', () {
      expect(visibleWhenVisible('${sep}x', base), isTrue);
    });
    test('◁abc▷', () {
      expect(visibleWhenVisible('4$sep<=${ro}abc$rc', base), isTrue);
    });
  });

  group('visibleWhenVisible — equality', () {
    test('== match', () {
      expect(visibleWhenVisible('2${sep}Telat masuk', base), isTrue);
    });
    test('== mismatch', () {
      expect(visibleWhenVisible('2${sep}Paruh hari', base), isFalse);
    });
    test('== is case-SENSITIVE (matches filterByMultiClause, not '
        'evaluateRbtSearch)', () {
      expect(visibleWhenVisible('2${sep}TELAT MASUK', base), isFalse);
    });
    test('== against an empty slot is a normal comparison (spec §3.2.6)', () {
      expect(visibleWhenVisible('9$sep', base), isTrue);
    });
    test('!= against an empty slot means "is filled"', () {
      expect(visibleWhenVisible('9$sep!=', base), isFalse);
      expect(visibleWhenVisible('2$sep!=', base), isTrue);
    });
    test('numeric tolerance: slot "10" == literal 10', () {
      expect(visibleWhenVisible('10${sep}10', base), isTrue);
    });
    test('eq() round-trip guard survives: "10" != "010"', () {
      expect(visibleWhenVisible('10${sep}010', base), isFalse);
    });
    test('surrounding blanks are tolerated on both halves', () {
      expect(visibleWhenVisible('2 $sep  Telat masuk ', base), isTrue);
    });
  });

  group('visibleWhenVisible — ordering operators', () {
    test('numeric > : "10" > "4" is TRUE (spec §9, not a string compare)', () {
      expect(visibleWhenVisible('10$sep>4', base), isTrue);
    });
    test('numeric < : "10" < "4" is FALSE', () {
      expect(visibleWhenVisible('10$sep<4', base), isFalse);
    });
    test('>= and <= at equality', () {
      expect(visibleWhenVisible('10$sep>=10', base), isTrue);
      expect(visibleWhenVisible('10$sep<=10', base), isTrue);
    });
    test('empty LEFT makes an ordering clause false (spec §3.2.6)', () {
      expect(visibleWhenVisible('9$sep>1', base), isFalse);
      expect(visibleWhenVisible('9$sep<1', base), isFalse);
      expect(visibleWhenVisible('9$sep>=1', base), isFalse);
      expect(visibleWhenVisible('9$sep<=1', base), isFalse);
    });
    test('empty RIGHT makes an ordering clause false', () {
      expect(visibleWhenVisible('10$sep>${ro}9$rc', base), isFalse);
    });
    test('ISO time strings order correctly as strings', () {
      expect(visibleWhenVisible('5$sep<=${ro}4$rc', base), isTrue);
      expect(visibleWhenVisible('4$sep<=${ro}5$rc', base), isFalse);
    });
  });

  group('visibleWhenVisible — ◁N▷ operands', () {
    test('out-of-range N resolves to "" -> ordering clause false', () {
      expect(visibleWhenVisible('4$sep<=${ro}99$rc', base), isFalse);
    });
    test('out-of-range N with == compares against "" -> false', () {
      expect(visibleWhenVisible('4$sep${ro}99$rc', base), isFalse);
    });
    test('out-of-range N with != compares against "" -> true', () {
      expect(visibleWhenVisible('4$sep!=${ro}99$rc', base), isTrue);
    });
    test('unfilled N resolves to ""', () {
      expect(visibleWhenVisible('4$sep!=${ro}9$rc', base), isTrue);
    });
  });

  group('visibleWhenVisible — ★ IN list (only with ==)', () {
    test('hit', () {
      expect(visibleWhenVisible('2${sep}Paruh hari${inn}Telat masuk', base),
          isTrue);
    });
    test('miss', () {
      expect(visibleWhenVisible('2${sep}Seharian${inn}Pulang cepat', base),
          isFalse);
    });
    test('single-entry list behaves like ==', () {
      // ★ MUST be present or the operand never reaches the inList branch and
      // this test degenerates into a copy of '== match'. A trailing ★ splits
      // to ['Telat masuk', ''] — one real entry.
      expect(visibleWhenVisible('2${sep}Telat masuk$inn', base), isTrue);
      // Miss direction: without it an inList hard-wired to true still passes.
      expect(visibleWhenVisible('2${sep}Seharian$inn', base), isFalse);
    });
  });

  group('visibleWhenVisible — multi-clause ⭘ AND (spec §3.2.8)', () {
    test('both true -> visible', () {
      expect(visibleWhenVisible('2${sep}Telat masuk${and}10$sep>4', base),
          isTrue);
    });
    test('second false -> hidden', () {
      expect(visibleWhenVisible('2${sep}Telat masuk${and}10$sep>40', base),
          isFalse);
    });
    test('first false -> hidden', () {
      expect(visibleWhenVisible('2${sep}Seharian${and}10$sep>4', base),
          isFalse);
    });
    test('trailing ⭘ does NOT turn the string into fail-open', () {
      expect(visibleWhenVisible('2${sep}Telat masuk$and', base), isTrue);
      expect(visibleWhenVisible('2${sep}Seharian$and', base), isFalse);
    });
    test('legacy _2B58_ is NOT decoded by autheniumDecode, so the string '
        'stays ONE clause and evaluates false (documented risk R3)', () {
      expect(visibleWhenVisible('2_25FC_Telat masuk_2B58_10_25FC_>4', base),
          isFalse);
    });
  });

  group('spec §4 pilot walkthrough (form Izin)', () {
    final VisibleWhenValueReader seharian =
        reader(<int, String>{2: 'Seharian'});
    final VisibleWhenValueReader paruhBad =
        reader(<int, String>{2: 'Paruh hari', 4: '10:00', 5: '09:00'});
    final VisibleWhenValueReader paruhOk =
        reader(<int, String>{2: 'Paruh hari', 4: '09:00', 5: '10:00'});
    final VisibleWhenValueReader paruhPartial =
        reader(<int, String>{2: 'Paruh hari', 4: '10:00'});
    const String notice = '2\u{25FC}Paruh hari\u{2B58}5\u{25FC}<=\u{25C1}4\u{25B7}';

    test('Seharian hides every hour field', () {
      expect(visibleWhenVisible('2${sep}Paruh hari', seharian), isFalse);
      expect(visibleWhenVisible('2${sep}Telat masuk', seharian), isFalse);
      expect(visibleWhenVisible('2${sep}Pulang cepat', seharian), isFalse);
    });
    test('Paruh hari shows positions 4 and 5', () {
      expect(visibleWhenVisible('2${sep}Paruh hari', paruhBad), isTrue);
    });
    test('noticeBar appears when selesai <= mulai', () {
      expect(visibleWhenVisible(notice, paruhBad), isTrue);
    });
    test('noticeBar hidden when selesai > mulai', () {
      expect(visibleWhenVisible(notice, paruhOk), isFalse);
    });
    test('noticeBar is NOT premature while position 5 is still empty '
        '(spec §9)', () {
      expect(visibleWhenVisible(notice, paruhPartial), isFalse);
    });
  });

  group('hiddenVisibleWhenPositions (submit exclusion, D8)', () {
    final List<dynamic> izin = <dynamic>[
      <String, dynamic>{'type': 'SELECTABLE_BTN', 'position': 2},
      <String, dynamic>{'type': 'TXF', 'position': 3},
      <String, dynamic>{
        'type': 'TXF',
        'position': 4,
        'visibleWhen': '2\u{25FC}Paruh hari'
      },
      <String, dynamic>{
        'type': 'TXF',
        'position': 5,
        'visibleWhen': '2\u{25FC}Paruh hari'
      },
      <String, dynamic>{
        'type': 'TXF',
        'position': 6,
        'visibleWhen': '2\u{25FC}Telat masuk'
      },
      <String, dynamic>{
        'type': 'TXF',
        'position': 7,
        'visibleWhen': '2\u{25FC}Pulang cepat'
      },
      <String, dynamic>{
        'type': 'noticeBar',
        'visibleWhen': '2\u{25FC}Paruh hari'
      },
      <String, dynamic>{'type': 'TXF', 'position': 8},
    ];

    test('Seharian excludes exactly 4,5,6,7', () {
      expect(
          hiddenVisibleWhenPositions(izin, reader(<int, String>{2: 'Seharian'})),
          <int>{4, 5, 6, 7});
    });
    test('Paruh hari excludes only 6,7', () {
      expect(
          hiddenVisibleWhenPositions(
              izin, reader(<int, String>{2: 'Paruh hari'})),
          <int>{6, 7});
    });
    test('unconditional positions are NEVER excluded (regression zero)', () {
      final Set<int> hidden = hiddenVisibleWhenPositions(
          izin, reader(<int, String>{2: 'Seharian'}));
      expect(hidden.contains(2), isFalse);
      expect(hidden.contains(3), isFalse);
      expect(hidden.contains(8), isFalse);
    });
    test('a page with no visibleWhen at all excludes nothing', () {
      expect(
          hiddenVisibleWhenPositions(<dynamic>[
            <String, dynamic>{'type': 'TXF', 'position': 1},
            <String, dynamic>{'type': 'TXF', 'position': 2},
          ], base),
          isEmpty);
    });
    test('positionless conditional widget contributes no exclusion', () {
      expect(
          hiddenVisibleWhenPositions(<dynamic>[
            <String, dynamic>{
              'type': 'noticeBar',
              'visibleWhen': '2\u{25FC}Nope'
            }
          ], base),
          isEmpty);
    });
    test('string position is parsed', () {
      expect(
          hiddenVisibleWhenPositions(<dynamic>[
            <String, dynamic>{
              'type': 'TXF',
              'position': '6',
              'visibleWhen': '2\u{25FC}Nope'
            }
          ], base),
          <int>{6});
    });
    test('malformed visibleWhen fails open, so the slot survives', () {
      expect(
          hiddenVisibleWhenPositions(<dynamic>[
            <String, dynamic>{
              'type': 'TXF',
              'position': 6,
              'visibleWhen': 'abc\u{25FC}x'
            }
          ], base),
          isEmpty);
    });
    test('non-List children -> empty set', () {
      expect(hiddenVisibleWhenPositions(null, base), isEmpty);
      expect(hiddenVisibleWhenPositions('nope', base), isEmpty);
    });

    // spec §3.4 — duplicate position is the OFFICIAL per-mode label pattern.
    final List<dynamic> dup = <dynamic>[
      <String, dynamic>{
        'type': 'TXF',
        'position': 6,
        'label': 'Perkiraan jam tiba',
        'visibleWhen': '2\u{25FC}Telat masuk'
      },
      <String, dynamic>{
        'type': 'TXF',
        'position': 6,
        'label': 'Jam pulang',
        'visibleWhen': '2\u{25FC}Pulang cepat'
      },
    ];
    test('duplicate position: ONE visible -> slot survives', () {
      expect(hiddenVisibleWhenPositions(dup, base), isEmpty);
    });
    test('duplicate position: NONE visible -> slot excluded', () {
      expect(
          hiddenVisibleWhenPositions(dup, reader(<int, String>{2: 'Seharian'})),
          <int>{6});
    });
    test('an unconditional twin protects the slot outright', () {
      expect(
          hiddenVisibleWhenPositions(<dynamic>[
            <String, dynamic>{
              'type': 'TXF',
              'position': 6,
              'visibleWhen': '2\u{25FC}Pulang cepat'
            },
            <String, dynamic>{'type': 'TXT', 'position': 6},
          ], base),
          isEmpty);
    });
  });

  group('visibleWhenChildren (validation skip, D9)', () {
    test('drops only the non-matching conditional children', () {
      final List<dynamic> kids = visibleWhenChildren(<dynamic>[
        <String, dynamic>{'type': 'GET_IMAGES', 'position': 3},
        <String, dynamic>{
          'type': 'GET_IMAGES',
          'position': 4,
          'optional': 'FALSE',
          'visibleWhen': '2\u{25FC}Seharian'
        },
        <String, dynamic>{
          'type': 'GET_IMAGES',
          'position': 5,
          'optional': 'FALSE',
          'visibleWhen': '2\u{25FC}Telat masuk'
        },
      ], base);
      expect(kids.length, 2);
      expect((kids[0] as Map)['position'], 3);
      expect((kids[1] as Map)['position'], 5);
    });
    test('non-Map entries are passed through untouched', () {
      expect(visibleWhenChildren(<dynamic>['x'], base).length, 1);
    });
    test('non-List -> empty', () {
      expect(visibleWhenChildren('nope', base), isEmpty);
      expect(visibleWhenChildren(null, base), isEmpty);
    });
  });

  group('visibleWhenReader (D6 — matches what saveSend submits)', () {
    InputController slot(String finalData, String text) => InputController(
        1, TextEditingController(text: text), '', finalData);

    test('a fresh untouched slot reads as "" (finalData is the "--" '
        'sentinel and controller.text is empty)', () {
      final Map<int, InputController> slots = <int, InputController>{
        1: slot(emptyString, '')
      };
      expect(visibleWhenReader(slots)(1), '');
    });
    test('finalData wins when it is not the sentinel', () {
      expect(
          visibleWhenReader(<int, InputController>{
            1: slot('Telat masuk', 'stale text')
          })(1),
          'Telat masuk');
    });
    test('controller.text wins while finalData is still the sentinel', () {
      expect(
          visibleWhenReader(<int, InputController>{
            1: slot(emptyString, 'typed')
          })(1),
          'typed');
    });
    test('a deliberately cleared field reads as "" (finalData "" beats '
        'controller text)', () {
      expect(
          visibleWhenReader(<int, InputController>{
            1: slot('', 'leftover')
          })(1),
          '');
    });
    test('absent position -> ""', () {
      expect(visibleWhenReader(<int, InputController>{})(7), '');
    });
    test('null map -> ""', () {
      expect(visibleWhenReader(null)(1), '');
    });
  });

  group('InputController.finalData setter (D1)', () {
    test('assigning finalData never throws when no GetX controller is '
        'registered — a throwing setter would break unrelated tests', () {
      final InputController ic =
          InputController(1, TextEditingController(text: ''), '', emptyString);
      expect(() => ic.finalData = 'first', returnsNormally);
      expect(() => ic.finalData = 'first', returnsNormally); // no-op path
      expect(() => ic.finalData = 'second', returnsNormally);
      expect(ic.finalData, 'second');
    });
    test('the constructor round-trips its positional finalData argument', () {
      expect(
          InputController(1, TextEditingController(text: ''), '', emptyString)
              .finalData,
          emptyString);
    });
  });
}
