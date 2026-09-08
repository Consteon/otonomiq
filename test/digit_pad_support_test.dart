// test/digit_pad_support_test.dart
//
// Pure-function tests for DIGIT_PAD. No binding, no Firebase, no GetX.
//
// Mutation checks are named per group: each says which production line to break
// to see the group go red. A test that survives its own mutation is guarding
// nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/digit_pad_support.dart';

void main() {
  group('digitPadNormalizeSeed', () {
    // RED if: digitPadNormalizeSeed is changed to `=> raw`.
    // Guards the api.dart record-composer hazard: finalData left at '--' makes
    // saveSend fall back to controller.text and submit the raw hole-buffer.
    test("all three empty sentinels collapse to ''", () {
      expect(digitPadNormalizeSeed(''), '');
      expect(digitPadNormalizeSeed('   '), '');
      expect(digitPadNormalizeSeed('null'), '');
      expect(digitPadNormalizeSeed('--'), ''); // '--'.isEmpty is FALSE
    });

    test('a real value survives untrimmed', () {
      expect(digitPadNormalizeSeed('00987'), '00987');
      expect(digitPadNormalizeSeed(' 5 '), ' 5 ');
    });
  });

  group('digitPadParsePosition', () {
    test('plain, ◁N▷ and ◀N▶ all yield N — no +1', () {
      expect(digitPadParsePosition('7'), 7);
      expect(digitPadParsePosition('◁7▷'), 7);
      expect(digitPadParsePosition('◀12▶'), 12);
    });

    test('blank and garbage yield null instead of throwing', () {
      expect(digitPadParsePosition(''), isNull);
      expect(digitPadParsePosition('   '), isNull);
      expect(digitPadParsePosition('abc'), isNull);
    });
  });

  group('digitPadNum', () {
    test('num, numeric String, and every empty sentinel', () {
      expect(digitPadNum(1234), 1234);
      expect(digitPadNum(12.5), 12.5);
      expect(digitPadNum('1234'), 1234);
      expect(digitPadNum(' 1234 '), 1234);
      expect(digitPadNum(null), isNull);
      expect(digitPadNum(''), isNull);
      expect(digitPadNum('--'), isNull);
      expect(digitPadNum('null'), isNull);
      expect(digitPadNum('abc'), isNull);
    });
  });

  group('digitPadNormalizeBuffer', () {
    // RED if: `buf.substring(0, boxes)` becomes
    //         `buf.substring(buf.length - boxes)`.
    // This is spec §11's "kotak kelebihan dibuang dari kanan".
    test('shrinking drops boxes from the RIGHT', () {
      expect(digitPadNormalizeBuffer('12345', 3), '123');
      expect(digitPadNormalizeBuffer('01_2_', 3), '01_');
    });

    test('growing pads holes on the right', () {
      expect(digitPadNormalizeBuffer('12', 5), '12___');
      expect(digitPadNormalizeBuffer('', 5), '_____');
    });

    test('non-digit, non-hole characters are dropped', () {
      expect(digitPadNormalizeBuffer('1a2b3', 5), '123__');
      expect(digitPadNormalizeBuffer('1.2', 3), '12_');
      expect(digitPadNormalizeBuffer('-12', 3), '12_');
    });

    test('empty sentinels become an all-hole buffer', () {
      expect(digitPadNormalizeBuffer('--', 4), '____');
      expect(digitPadNormalizeBuffer('null', 4), '____');
    });

    test('zero or negative boxes yield an empty buffer', () {
      expect(digitPadNormalizeBuffer('123', 0), '');
      expect(digitPadNormalizeBuffer('123', -1), '');
    });
  });

  group('digitPadSubmitValue', () {
    test('incomplete buffers submit NOTHING, never a partial number', () {
      expect(digitPadSubmitValue('012__'), '');
      expect(digitPadSubmitValue('_____'), '');
      expect(digitPadSubmitValue('0_987'), '');
      expect(digitPadSubmitValue(''), '');
    });

    // RED if: the leading-zero strip is removed. Spec §5 — the value must agree
    // with the `★N` typed top-level key the builder writes.
    test('leading zeros are display only', () {
      expect(digitPadSubmitValue('00987'), '987');
      expect(digitPadSubmitValue('98765'), '98765');
      expect(digitPadSubmitValue('00000'), '0');
      expect(digitPadSubmitValue('0'), '0');
      expect(digitPadSubmitValue('0001'), '1');
    });
  });

  group('digitPadHoleCount', () {
    test('counts empty boxes for the {n} token', () {
      expect(digitPadHoleCount('012__'), 2);
      expect(digitPadHoleCount('01234'), 0);
      expect(digitPadHoleCount('_____'), 5);
    });
  });

  group('keypress model', () {
    test('digits fill left to right and advance the cursor', () {
      DigitPadEntry e = digitPadPressDigit('_____', 0, '0');
      expect(e.buffer, '0____');
      expect(e.cursor, 1);
      e = digitPadPressDigit(e.buffer, e.cursor, '9');
      expect(e.buffer, '09___');
      expect(e.cursor, 2);
    });

    // RED if: the `c >= n` guard in digitPadPressDigit is removed.
    // Spec §11: "Ketik angka ke-6 -> tidak ada yang terjadi".
    test('a digit past the last box is a NO-OP, not a shift', () {
      final DigitPadEntry e = digitPadPressDigit('00987', 5, '3');
      expect(e.buffer, '00987');
      expect(e.cursor, 5);
    });

    test('non-digit input is rejected without moving the cursor', () {
      expect(digitPadPressDigit('_____', 0, '.').buffer, '_____');
      expect(digitPadPressDigit('_____', 0, '.').cursor, 0);
      expect(digitPadPressDigit('_____', 0, '-').buffer, '_____');
      expect(digitPadPressDigit('_____', 0, '12').buffer, '_____');
    });

    test('retyping the same digit still advances the cursor', () {
      final DigitPadEntry e = digitPadPressDigit('9____', 0, '9');
      expect(e.buffer, '9____');
      expect(e.cursor, 1);
    });

    test('backspace clears the box before the cursor and moves there', () {
      DigitPadEntry e = digitPadPressBackspace('00987', 5);
      expect(e.buffer, '0098_');
      expect(e.cursor, 4);
      e = digitPadPressBackspace(e.buffer, e.cursor);
      expect(e.buffer, '009__');
      expect(e.cursor, 3);
    });

    test('backspace at box 0 clears box 0 and stays', () {
      final DigitPadEntry e = digitPadPressBackspace('9____', 0);
      expect(e.buffer, '_____');
      expect(e.cursor, 0);
    });

    test('tapping a box moves the cursor there, clamped', () {
      expect(digitPadTapBox('_____', 3).cursor, 3);
      expect(digitPadTapBox('_____', 99).cursor, 4);
      expect(digitPadTapBox('_____', -2).cursor, 0);
      expect(digitPadTapBox('_____', 3).buffer, '_____');
    });

    test('typing into a tapped box overwrites it', () {
      final DigitPadEntry e = digitPadPressDigit('01234', 1, '9');
      expect(e.buffer, '09234');
      expect(e.cursor, 2);
    });
  });

  group('digitPadResolveCount', () {
    test('a usable slot value wins over the doc field', () {
      expect(digitPadResolveCount(slotValue: '4', docValue: 6), 4);
    });

    test('an unusable slot value falls through to the doc field', () {
      expect(digitPadResolveCount(slotValue: '', docValue: 6), 6);
      expect(digitPadResolveCount(slotValue: '--', docValue: '6'), 6);
      expect(digitPadResolveCount(slotValue: 'null', docValue: 6), 6);
      expect(digitPadResolveCount(slotValue: '0', docValue: 6), 6);
    });

    test('neither source resolvable -> null (render nothing, do not crash)', () {
      expect(digitPadResolveCount(slotValue: '', docValue: null), isNull);
      expect(digitPadResolveCount(slotValue: '', docValue: ''), isNull);
      expect(digitPadResolveCount(slotValue: 'abc', docValue: 'abc'), isNull);
      expect(digitPadResolveCount(slotValue: '', docValue: 0), isNull);
    });

    test('a runaway sheet value is capped', () {
      expect(digitPadResolveCount(slotValue: '500', docValue: null),
          digitPadMaxBoxes);
    });
  });

  group('digitPadVerdict', () {
    const num mult = 4;

    // RED if: the `prev == null` half of the first guard is removed — the
    // `value < prev` comparison then throws on a null prev. Spec §7.5: no
    // comparator means SILENCE, never an error.
    test('no value or no comparator -> none (silent)', () {
      expect(
          digitPadVerdict(
              value: null, prev: 1000, avg: 30, spikeMultiplier: mult),
          DigitPadVerdict.none);
      expect(
          digitPadVerdict(
              value: 1200, prev: null, avg: 30, spikeMultiplier: mult),
          DigitPadVerdict.none);
    });

    test('value < prev -> backward', () {
      expect(
          digitPadVerdict(
              value: 900, prev: 1000, avg: 30, spikeMultiplier: mult),
          DigitPadVerdict.backward);
    });

    test('delta > avg * multiplier -> spike', () {
      expect(
          digitPadVerdict(
              value: 1500, prev: 1000, avg: 30, spikeMultiplier: mult),
          DigitPadVerdict.spike);
    });

    test('delta exactly on the threshold is still sane (strict >)', () {
      expect(
          digitPadVerdict(
              value: 1120, prev: 1000, avg: 30, spikeMultiplier: mult),
          DigitPadVerdict.sane);
    });

    test('no avg -> spike check off, backward check still on', () {
      expect(
          digitPadVerdict(
              value: 99999, prev: 1000, avg: null, spikeMultiplier: mult),
          DigitPadVerdict.sane);
      expect(
          digitPadVerdict(
              value: 900, prev: 1000, avg: null, spikeMultiplier: mult),
          DigitPadVerdict.backward);
    });

    test('avg 0 behaves like no avg (documented deviation)', () {
      expect(
          digitPadVerdict(
              value: 1001, prev: 1000, avg: 0, spikeMultiplier: mult),
          DigitPadVerdict.sane);
    });

    test('equal value and prev is sane, not backward', () {
      expect(
          digitPadVerdict(
              value: 1000, prev: 1000, avg: 30, spikeMultiplier: mult),
          DigitPadVerdict.sane);
    });
  });

  group('digitPadShouldBlock', () {
    // RED if: the condition becomes `verdict != DigitPadVerdict.sane`.
    // Spec §10: a spike must NEVER block — leaks are real and must be reported.
    test('only backward + blockOnBackward blocks', () {
      expect(digitPadShouldBlock(DigitPadVerdict.backward, true), isTrue);
      expect(digitPadShouldBlock(DigitPadVerdict.backward, false), isFalse);
      expect(digitPadShouldBlock(DigitPadVerdict.spike, true), isFalse);
      expect(digitPadShouldBlock(DigitPadVerdict.sane, true), isFalse);
      expect(digitPadShouldBlock(DigitPadVerdict.none, true), isFalse);
    });
  });

  group('digitPadFillTokens', () {
    test('the closed list substitutes', () {
      expect(
        digitPadFillTokens('Masuk akal — selisih {delta} m³ dari {prev}',
            <String, String>{'delta': '34', 'prev': '1234'}),
        'Masuk akal — selisih 34 m³ dari 1234',
      );
      expect(
        digitPadFillTokens('Kurang {n} angka', <String, String>{'n': '2'}),
        'Kurang 2 angka',
      );
    });

    test('an empty or absent value leaves the token LITERAL', () {
      expect(digitPadFillTokens('biasanya {avg}', const <String, String>{}),
          'biasanya {avg}');
      expect(
          digitPadFillTokens('biasanya {avg}', <String, String>{'avg': ''}),
          'biasanya {avg}');
    });

    // RED if: the regex alternation is widened (e.g. to `\w+`). The list is
    // CLOSED by spec §3.1 so a screenTx key can never hijack a verdict message.
    test('a token outside the closed list is never substituted', () {
      expect(
        digitPadFillTokens('{userVid} {vehicleId} {value}',
            <String, String>{'userVid': 'X', 'vehicleId': 'Y', 'value': '987'}),
        '{userVid} {vehicleId} 987',
      );
    });

    test('an empty template comes back unchanged', () {
      expect(digitPadFillTokens('', <String, String>{'n': '2'}), '');
    });
  });

  group('digitPadSaveSendPositions', () {
    dynamic page(List<dynamic> children) => children;

    // RED if: the scan reads `kid['actions']` (plural) instead of
    // `kid['action']`. `actions` is the approval-chain field.
    test('finds savesend children of rbt components only', () {
      expect(
        digitPadSaveSendPositions(page(<dynamic>[
          <String, dynamic>{'type': 'txf', 'position': 3},
          <String, dynamic>{
            'type': 'RBT',
            'children': <dynamic>[
              <String, dynamic>{'position': 21, 'action': 'route'},
              <String, dynamic>{'position': 22, 'action': 'saveSend'},
            ],
          },
        ])),
        <int>[22],
      );
    });

    test('a String position parses; duplicates collapse', () {
      expect(
        digitPadSaveSendPositions(page(<dynamic>[
          <String, dynamic>{
            'type': 'rbt',
            'children': <dynamic>[
              <String, dynamic>{'position': '30', 'action': ' SAVESEND '},
              <String, dynamic>{'position': 30, 'action': 'savesend'},
            ],
          },
        ])),
        <int>[30],
      );
    });

    test('a savesend child with no position is skipped (static button)', () {
      expect(
        digitPadSaveSendPositions(page(<dynamic>[
          <String, dynamic>{
            'type': 'rbt',
            'children': <dynamic>[
              <String, dynamic>{'action': 'savesend'},
            ],
          },
        ])),
        isEmpty,
      );
    });

    test('approval-chain `actions` is NOT mistaken for `action`', () {
      expect(
        digitPadSaveSendPositions(page(<dynamic>[
          <String, dynamic>{
            'type': 'rbt',
            'children': <dynamic>[
              <String, dynamic>{'position': 40, 'actions': 'savesend'},
            ],
          },
        ])),
        isEmpty,
      );
    });

    test('malformed input never throws', () {
      expect(digitPadSaveSendPositions(null), isEmpty);
      expect(digitPadSaveSendPositions('not a list'), isEmpty);
      expect(digitPadSaveSendPositions(<dynamic>[null, 7, 'x']), isEmpty);
      expect(
          digitPadSaveSendPositions(<dynamic>[
            <String, dynamic>{'type': 'rbt'},
            <String, dynamic>{'type': 'rbt', 'children': 'nope'},
          ]),
          isEmpty);
    });
  });

  group('digitPadFmt', () {
    test('whole values lose the .0', () {
      expect(digitPadFmt(34), '34');
      expect(digitPadFmt(34.0), '34');
      expect(digitPadFmt(34.5), '34.5');
    });
  });

  // ── rev c / rev d / rev e ────────────────────────────────────────────────

  group('digitPadResolveRedCount', () {
    // RED if: the `>= 0` in the slot branch becomes `> 0`.
    // `0` red boxes is a MEANINGFUL answer ("this site bills in whole m³"), not
    // an absent one. Falling through to the doc there would resurrect the site
    // default the officer just overrode.
    test('a slot value of 0 WINS instead of falling through', () {
      expect(digitPadResolveRedCount(slotValue: '0', docValue: 2), 0);
      expect(digitPadResolveRedCount(slotValue: '1', docValue: 2), 1);
    });

    test('an empty slot falls through to the doc', () {
      expect(digitPadResolveRedCount(slotValue: '', docValue: 2), 2);
      expect(digitPadResolveRedCount(slotValue: '--', docValue: '2'), 2);
      expect(digitPadResolveRedCount(slotValue: 'null', docValue: 2), 2);
      expect(digitPadResolveRedCount(slotValue: 'abc', docValue: 0), 0);
    });

    // RED if: the tail returns null instead of 0. A resolved BLACK count with
    // no red config anywhere is the Kawasan Ruko shape (5 black, 0 red) — a
    // complete configuration, not a missing one.
    test('nothing anywhere means 0 red boxes, never null', () {
      expect(digitPadResolveRedCount(slotValue: '', docValue: null), 0);
      expect(digitPadResolveRedCount(slotValue: '', docValue: ''), 0);
      expect(digitPadResolveRedCount(slotValue: 'abc', docValue: 'abc'), 0);
    });

    test('a runaway value is capped', () {
      expect(digitPadResolveRedCount(slotValue: '500', docValue: null),
          digitPadMaxBoxes);
    });
  });

  group('digitPadLayout', () {
    test('the three known site shapes', () {
      // Kawasan Ruko: 5 black, 0 red -> no comma.
      final DigitPadLayout ruko = digitPadLayout(5, 0);
      expect(ruko.black, 5);
      expect(ruko.red, 0);
      expect(ruko.total, 5);
      expect(ruko.hasComma, isFalse);
      // Paskal Lodge: 5 black, 2 red.
      final DigitPadLayout lodge = digitPadLayout(5, 2);
      expect(lodge.total, 7);
      expect(lodge.hasComma, isTrue);
      // AMICO field photo, 20 Aug: 4 black, 1 red.
      final DigitPadLayout amico = digitPadLayout(4, 1);
      expect(amico.black, 4);
      expect(amico.red, 1);
      expect(amico.total, 5);
      expect(amico.hasComma, isTrue);
    });

    // RED if: the cap is applied to the total without trimming RED first.
    // Black is the m³ part that becomes the bill; a cap that eats black digits
    // is a 10x billing error, a cap that eats red digits is a rounding loss.
    test('the total cap trims RED, never BLACK', () {
      final DigitPadLayout l = digitPadLayout(10, 5);
      expect(l.black, 10);
      expect(l.red, 2);
      expect(l.total, digitPadMaxBoxes);
    });

    test('negatives and a runaway black value cannot paint a broken pad', () {
      expect(digitPadLayout(-3, -2).total, 0);
      final DigitPadLayout l = digitPadLayout(500, 3);
      expect(l.black, digitPadMaxBoxes);
      expect(l.red, 0);
    });
  });

  group('digitPadParseOptions', () {
    // RED if: allowZero is ignored. `0` is the "no red digits" choice and must
    // survive in the red list; in the black list it would offer the officer a
    // pad with no boxes.
    test('0 survives in the red list and is dropped from the black one', () {
      expect(
          digitPadParseOptions(<String>['0', '1', '2'], allowZero: true),
          <int>[0, 1, 2]);
      expect(
          digitPadParseOptions(<String>['0', '4', '5'], allowZero: false),
          <int>[4, 5]);
    });

    test('garbage, negatives, over-cap and duplicates are dropped', () {
      expect(
          digitPadParseOptions(
              <String>['4', 'abc', '', '-1', '999', '5', '4', ' 6 '],
              allowZero: false),
          <int>[4, 5, 6]);
    });

    // SduiSpec.list() already short-circuits diamondTextToList('') == [''] ,
    // but a hand-built [''] must not survive either.
    test('an empty list and a blank entry both yield nothing', () {
      expect(digitPadParseOptions(const <String>[], allowZero: false), isEmpty);
      expect(digitPadParseOptions(<String>[''], allowZero: true), isEmpty);
    });
  });

  group('digitPadPickerState', () {
    // ★ RED if: the `!hasOptions` early return is removed.
    // Interview decision 5 / product #17: one bad config cell must never
    // permanently lock a field officer out of the page.
    test('nothing pickable is always hidden, even with no count', () {
      expect(
          digitPadPickerState(
              hasCount: false,
              mode: 'auto',
              hasOptions: false,
              canPersist: true),
          DigitPadPickerState.hidden);
      expect(
          digitPadPickerState(
              hasCount: false,
              mode: 'editable',
              hasOptions: false,
              canPersist: true),
          DigitPadPickerState.hidden);
    });

    // ★★ RED if: the `!canPersist` term is removed.
    // Options WITH nowhere to store the pick is the worst of both worlds: the
    // picker renders, the gate engages, and every chip tap is a no-op because
    // _writeSlot bails on a null / self-referential position. The officer is
    // then locked out of the page with no escape. Same product #17 rule as the
    // no-options case, different trigger.
    test('options with nowhere to store the pick are hidden, not forced', () {
      expect(
          digitPadPickerState(
              hasCount: false,
              mode: 'auto',
              hasOptions: true,
              canPersist: false),
          DigitPadPickerState.hidden);
      expect(
          digitPadPickerState(
              hasCount: false,
              mode: 'editable',
              hasOptions: true,
              canPersist: false),
          DigitPadPickerState.hidden);
      // Even with a resolved count the link must not offer an edit that cannot
      // be saved.
      expect(
          digitPadPickerState(
              hasCount: true,
              mode: 'editable',
              hasOptions: true,
              canPersist: false),
          DigitPadPickerState.hidden);
    });

    test('no config with options is FORCED in both modes', () {
      expect(
          digitPadPickerState(
              hasCount: false,
              mode: 'auto',
              hasOptions: true,
              canPersist: true),
          DigitPadPickerState.forced);
      expect(
          digitPadPickerState(
              hasCount: false,
              mode: 'editable',
              hasOptions: true,
              canPersist: true),
          DigitPadPickerState.forced);
    });

    test('config present: auto hides, editable offers the link', () {
      expect(
          digitPadPickerState(
              hasCount: true,
              mode: 'auto',
              hasOptions: true,
              canPersist: true),
          DigitPadPickerState.hidden);
      expect(
          digitPadPickerState(
              hasCount: true,
              mode: ' EDITABLE ',
              hasOptions: true,
              canPersist: true),
          DigitPadPickerState.link);
      // Unknown / blank mode behaves as auto (spec §8 default).
      expect(
          digitPadPickerState(
              hasCount: true, mode: '', hasOptions: true, canPersist: true),
          DigitPadPickerState.hidden);
    });
  });

  group('digitPadBlockSubmit', () {
    // RED if: the forced-picker term is dropped. Spec §7 item 7 — with no boxes
    // there is no legitimate number to send.
    test('a forced picker blocks regardless of blockOnBackward', () {
      expect(
          digitPadBlockSubmit(
              verdict: DigitPadVerdict.none,
              blockOnBackward: false,
              picker: DigitPadPickerState.forced),
          isTrue);
      expect(
          digitPadBlockSubmit(
              verdict: DigitPadVerdict.sane,
              blockOnBackward: false,
              picker: DigitPadPickerState.forced),
          isTrue);
    });

    // RED if: the picker term swallows `link` or `hidden` too.
    test('a link or hidden picker never blocks on its own', () {
      expect(
          digitPadBlockSubmit(
              verdict: DigitPadVerdict.sane,
              blockOnBackward: true,
              picker: DigitPadPickerState.link),
          isFalse);
      expect(
          digitPadBlockSubmit(
              verdict: DigitPadVerdict.spike,
              blockOnBackward: true,
              picker: DigitPadPickerState.hidden),
          isFalse);
    });

    test('the backward rule is unchanged underneath', () {
      expect(
          digitPadBlockSubmit(
              verdict: DigitPadVerdict.backward,
              blockOnBackward: true,
              picker: DigitPadPickerState.hidden),
          isTrue);
      expect(
          digitPadBlockSubmit(
              verdict: DigitPadVerdict.backward,
              blockOnBackward: false,
              picker: DigitPadPickerState.hidden),
          isFalse);
    });
  });

  group('digitPadResolveSource', () {
    // ★ RED if: the latch clause is removed.
    // Once the count comes from the slot, `fromDoc` is false on every later
    // build; without the latch a doc-seeded count would flip to `field` on
    // build 2 and the office would review every single point.
    test('an already-recorded provenance is never overwritten', () {
      expect(digitPadResolveSource('config', fromDoc: false),
          digitPadSourceConfig);
      expect(
          digitPadResolveSource('field', fromDoc: true), digitPadSourceField);
      expect(digitPadResolveSource(' FIELD ', fromDoc: true),
          digitPadSourceField);
    });

    test('an empty slot records this build\'s source', () {
      expect(
          digitPadResolveSource('', fromDoc: true), digitPadSourceConfig);
      expect(
          digitPadResolveSource('', fromDoc: false), digitPadSourceField);
      expect(digitPadResolveSource('--', fromDoc: true), digitPadSourceConfig);
      expect(digitPadResolveSource('null', fromDoc: false),
          digitPadSourceField);
    });

    test('a garbage slot value is replaced, not latched', () {
      expect(digitPadResolveSource('yes', fromDoc: true), digitPadSourceConfig);
    });
  });

  group('digitPadShouldRaiseSheet', () {
    // ★ RED if: `sane` is allowed through. §4c rule 1 — a sheet on every unit
    // trains officers to dismiss it unread, and then the backward verdict is
    // dismissed unread too.
    test('sane and none never raise', () {
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.sane,
              submitValue: '1100',
              verdictText: 'Masuk akal',
              alreadyRaisedFor: null),
          isFalse);
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.none,
              submitValue: '1100',
              verdictText: 'x',
              alreadyRaisedFor: null),
          isFalse);
    });

    test('spike and backward raise on a fresh complete value', () {
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '9999',
              verdictText: 'Lonjakan',
              alreadyRaisedFor: null),
          isTrue);
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.backward,
              submitValue: '900',
              verdictText: 'Mundur',
              alreadyRaisedFor: null),
          isTrue);
    });

    // ★ RED if: the alreadyRaisedFor comparison is dropped. §4c rule 3 — a
    // dismissed sheet must not come back on the next rebuild.
    test('the same value does not get a second raise', () {
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '9999',
              verdictText: 'Lonjakan',
              alreadyRaisedFor: '9999'),
          isFalse);
      // A different complete value earns a fresh raise.
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '9998',
              verdictText: 'Lonjakan',
              alreadyRaisedFor: '9999'),
          isTrue);
    });

    test('an incomplete buffer or a blank segment never raises', () {
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '',
              verdictText: 'Lonjakan',
              alreadyRaisedFor: null),
          isFalse);
      // A blank verdict segment means there is nothing to show — §3.1
      // "segmen kosong = fitur itu diam".
      expect(
          digitPadShouldRaiseSheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '9999',
              verdictText: '',
              alreadyRaisedFor: null),
          isFalse);
    });
  });
  // ── meter-serial-verify ───────────────────────────────────────────────────

  group('digitPadNormalizeSerial', () {
    // RED if: the A-Z/0-9 filter is dropped, or the toUpperCase is dropped.
    // This is spec §3.1 step 2 and it is the ONLY reason `A21-4471908` and
    // `A21 4471908` are the same serial.
    test('uppercases and drops everything that is not A-Z or 0-9', () {
      expect(digitPadNormalizeSerial('A21-4471908'), 'A214471908');
      expect(digitPadNormalizeSerial('A21 4471908'), 'A214471908');
      expect(digitPadNormalizeSerial('a21.4471908/'), 'A214471908');
    });

    test('a punctuation-only or blank value normalises to empty', () {
      expect(digitPadNormalizeSerial('  --  '), '');
      expect(digitPadNormalizeSerial(''), '');
    });
  });

  group('digitPadSerialOwnsSheet', () {
    // ★ RED if: the verdict terms are dropped. Spec §12 concedes a mismatch has
    // a high false-positive rate; letting it mask a BACKWARD reading would kill
    // the one check product #21 exists for.
    test('a numeric verdict always beats the serial message', () {
      expect(
          digitPadSerialOwnsSheet(
              verdict: DigitPadVerdict.backward,
              serialMismatch: true,
              serialBlocking: false),
          isFalse);
      expect(
          digitPadSerialOwnsSheet(
              verdict: DigitPadVerdict.spike,
              serialMismatch: true,
              serialBlocking: false),
          isFalse);
    });

    test('the serial owns the sheet over sane and over no reading at all', () {
      expect(
          digitPadSerialOwnsSheet(
              verdict: DigitPadVerdict.sane,
              serialMismatch: true,
              serialBlocking: false),
          isTrue);
      expect(
          digitPadSerialOwnsSheet(
              verdict: DigitPadVerdict.none,
              serialMismatch: true,
              serialBlocking: false),
          isTrue);
    });

    test('no mismatch, nothing to own', () {
      expect(
          digitPadSerialOwnsSheet(
              verdict: DigitPadVerdict.sane,
              serialMismatch: false,
              serialBlocking: false),
          isFalse);
      expect(
          digitPadSerialOwnsSheet(
              verdict: DigitPadVerdict.none,
              serialMismatch: false,
              serialBlocking: false),
          isFalse);
    });
  });

  group('digitPadSheetKey', () {
    // ★ RED if: the '' short circuit is removed. '' is ALSO the re-arm signal
    // in _applySheet, so a key that is never empty would latch forever and
    // segment 12 would stop re-arming the raise.
    test("nothing to raise for yields '' (the re-arm signal)", () {
      expect(digitPadSheetKey(submitValue: '', ocrKey: 'k', serialOwns: false),
          '');
      expect(digitPadSheetKey(submitValue: '', ocrKey: '', serialOwns: true),
          '');
    });

    test('a reading alone still keys per value, exactly as rev e did', () {
      expect(
          digitPadSheetKey(submitValue: '9999', ocrKey: 'k', serialOwns: false),
          '9999|');
      expect(
          digitPadSheetKey(submitValue: '9999', ocrKey: 'k', serialOwns: false),
          isNot(digitPadSheetKey(
              submitValue: '9998', ocrKey: 'k', serialOwns: false)));
    });

    // ★ RED if: ocrKey stops entering the key. Spec §7.7 — a replaced photo
    // must recompute AND re-raise, not stick to the first photo's verdict.
    test('a photo-only mismatch keys on the photo and re-raises when it changes',
        () {
      expect(
          digitPadSheetKey(submitValue: '', ocrKey: 'A', serialOwns: true),
          isNotEmpty);
      expect(digitPadSheetKey(submitValue: '', ocrKey: 'A', serialOwns: true),
          isNot(digitPadSheetKey(
              submitValue: '', ocrKey: 'B', serialOwns: true)));
    });
  });

  group('digitPadShouldRaiseAnySheet', () {
    const String seg6 = 'Nomor seri di foto tidak cocok';

    // ★ RED if: the serialOwns short circuit is removed. This is the ONE case
    // rev e's rules refuse — spec §5's sketch is exactly "photo taken, boxes
    // still empty, sheet up".
    test('the serial half raises with the digit boxes still empty', () {
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.none,
              submitValue: '',
              sheetText: seg6,
              serialOwns: true,
              sheetKey: '|A',
              alreadyRaisedFor: null),
          isTrue);
    });

    test('a dismissed serial sheet does not come back on the next rebuild', () {
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.none,
              submitValue: '',
              sheetText: seg6,
              serialOwns: true,
              sheetKey: '|A',
              alreadyRaisedFor: '|A'),
          isFalse);
    });

    // §3.1 "segmen kosong = fitur itu diam".
    test('a blank segment 6 silences the serial half completely', () {
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.none,
              submitValue: '',
              sheetText: '',
              serialOwns: true,
              sheetKey: '|A',
              alreadyRaisedFor: null),
          isFalse);
    });

    // ★ RED if: the delegation to digitPadShouldRaiseSheet is replaced by an
    // inlined copy that drifts. rev e §4c rule 1 — `sane` NEVER raises, because
    // a sheet on every unit trains officers to close it without reading.
    test('the numeric half keeps rev e rules: sane never raises, spike does',
        () {
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.sane,
              submitValue: '1100',
              sheetText: 'Masuk akal',
              serialOwns: false,
              sheetKey: '1100|',
              alreadyRaisedFor: null),
          isFalse);
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '9999',
              sheetText: 'Lonjakan',
              serialOwns: false,
              sheetKey: '9999|',
              alreadyRaisedFor: null),
          isTrue);
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '9999',
              sheetText: 'Lonjakan',
              serialOwns: false,
              sheetKey: '9999|',
              alreadyRaisedFor: '9999|'),
          isFalse);
    });

    test('an empty sheet key raises nothing at all', () {
      expect(
          digitPadShouldRaiseAnySheet(
              verdict: DigitPadVerdict.spike,
              submitValue: '',
              sheetText: seg6,
              serialOwns: false,
              sheetKey: '',
              alreadyRaisedFor: null),
          isFalse);
    });
  });

  // ── r2 W1: the two axes remember INDEPENDENTLY ───────────────────────────

  group('digitPadSheetKey halves', () {
    // ★ RED if: the split moves to the LAST separator. The serial half is
    // itself `photo slot value` + `|` + `doc serial`, so it carries separators
    // of its own; only the FIRST one divides the two axes.
    test('splits at the first separator, never the last', () {
      const String key = '1100|aum__/a.jpg__mua|A21-4471908';
      expect(digitPadSheetKeyNumeric(key), '1100');
      expect(digitPadSheetKeySerial(key), 'aum__/a.jpg__mua|A21-4471908');
    });

    test('a missing separator is all numeric, and an empty key is empty', () {
      expect(digitPadSheetKeyNumeric('1100'), '1100');
      expect(digitPadSheetKeySerial('1100'), '');
      expect(digitPadSheetKeyNumeric(''), '');
      expect(digitPadSheetKeySerial(''), '');
    });

    test('the halves of a real key round-trip', () {
      final String key =
          digitPadSheetKey(submitValue: '1100', ocrKey: 'K', serialOwns: true);
      expect(digitPadSheetKeyNumeric(key), '1100');
      expect(digitPadSheetKeySerial(key), 'K');
    });
  });

  group('digitPadNextSheetLatch', () {
    test('nothing raised and nothing to remember yields the remove signal', () {
      expect(digitPadNextSheetLatch(previous: '', sheetKey: '', raised: false),
          '');
      expect(
          digitPadNextSheetLatch(
              previous: '9999|', sheetKey: '', raised: false),
          '');
    });

    // ★ RED if: the serial half stops being STICKY. This is the r1 W1 residual
    // — a numeric sheet taking its turn must not make the pad forget which
    // photo the officer already dismissed, or backspacing out of the spike
    // re-raises the serial sheet he closed two taps ago.
    test('a numeric raise keeps the serial half', () {
      expect(
          digitPadNextSheetLatch(
              previous: '|K', sheetKey: '9999|', raised: true),
          '9999|K');
    });

    // The mirror image: a serial raise must not re-arm the numeric axis, or a
    // reading that already had its sheet would get a second one.
    test('a serial raise keeps the numeric half', () {
      expect(
          digitPadNextSheetLatch(
              previous: '9999|', sheetKey: '1100|K2', raised: true),
          '9999|K2');
    });

    // ★ RED if: the numeric half stops re-arming on an incomplete buffer. That
    // re-arm IS rev e's behaviour ('segment 12 clears the buffer and the next
    // complete value raises again'), and it must survive the widening.
    test('an incomplete buffer re-arms the numeric half only', () {
      expect(
          digitPadNextSheetLatch(
              previous: '9999|K', sheetKey: '|K', raised: false),
          '|K');
      // Nothing left on either axis: the entry goes away entirely, which is the
      // remove signal _applySheet keys on.
      expect(
          digitPadNextSheetLatch(
              previous: '9999|', sheetKey: '', raised: false),
          '');
    });

    test('a pass that raises nothing leaves both halves untouched', () {
      expect(
          digitPadNextSheetLatch(
              previous: '9999|K', sheetKey: '9999|K', raised: false),
          '9999|K');
    });
  });

  // ★★ SEQUENCES, not single states. r1's W1 and W2 both survived a green 154
  // precisely because every test in both suites asserted ONE state at a time —
  // and neither defect is visible in any single state.
  //
  // The driver below composes the REAL production helpers in the order _content
  // and _applySheet call them (key -> should-raise -> next-latch). The only
  // things written here are the event script and the counter. What it does NOT
  // prove is that the widget composes them in that order — that is what the
  // widget-level twins in digit_pad_widget_test.dart are for.
  group('the raise-once latch over a SEQUENCE', () {
    const String seg6 = 'Nomor seri di foto tidak cocok';
    const String ocrK = 'aum__/a.jpg__mua|A21-4471908';

    // ★ RED if: digitPadShouldRaiseAnySheet compares the latch WHOLE again
    // (r1), or the serial branch goes back to an unconditional `return true`.
    // The orchestrator measured FIVE raises here on the r1 code, for ONE
    // mismatch: correcting a single digit cost two modal bottom sheets.
    test('a live mismatch raises ONCE across type -> backspace -> retype', () {
      String? latch;
      int raised = 0;
      void step(DigitPadVerdict verdict, String submit) {
        final bool serialOwns =
            digitPadSerialOwnsSheet(
                verdict: verdict, serialMismatch: true, serialBlocking: false);
        final String key = digitPadSheetKey(
            submitValue: submit, ocrKey: ocrK, serialOwns: serialOwns);
        final bool raise = digitPadShouldRaiseAnySheet(
          verdict: verdict,
          submitValue: submit,
          sheetText: serialOwns ? seg6 : 'Lonjakan',
          serialOwns: serialOwns,
          sheetKey: key,
          alreadyRaisedFor: latch,
        );
        if (raise) raised++;
        final String next = digitPadNextSheetLatch(
            previous: latch ?? '', sheetKey: key, raised: raise);
        latch = next.isEmpty ? null : next;
      }

      step(DigitPadVerdict.none, ''); // the photo lands, boxes still empty
      step(DigitPadVerdict.sane, '12345'); // the officer types a reading
      step(DigitPadVerdict.none, ''); // backspace
      step(DigitPadVerdict.sane, '12345'); // retype
      step(DigitPadVerdict.none, ''); // backspace
      step(DigitPadVerdict.sane, '12345'); // retype

      expect(raised, 1);
    });

    // ★ RED if: the serial half of the latch stops being sticky. Two sheets are
    // correct here (one serial, one spike); a THIRD is the residual the
    // obvious two-line W1 fix would have left behind.
    test('a spike between two serial states does not re-open the serial sheet',
        () {
      String? latch;
      int raised = 0;
      void step(DigitPadVerdict verdict, String submit) {
        final bool serialOwns =
            digitPadSerialOwnsSheet(
                verdict: verdict, serialMismatch: true, serialBlocking: false);
        final String key = digitPadSheetKey(
            submitValue: submit, ocrKey: ocrK, serialOwns: serialOwns);
        final bool raise = digitPadShouldRaiseAnySheet(
          verdict: verdict,
          submitValue: submit,
          sheetText: serialOwns ? seg6 : 'Lonjakan',
          serialOwns: serialOwns,
          sheetKey: key,
          alreadyRaisedFor: latch,
        );
        if (raise) raised++;
        final String next = digitPadNextSheetLatch(
            previous: latch ?? '', sheetKey: key, raised: raise);
        latch = next.isEmpty ? null : next;
      }

      step(DigitPadVerdict.none, ''); // serial sheet #1
      step(DigitPadVerdict.spike, '9999'); // the NUMERIC verdict takes over: #2
      step(DigitPadVerdict.none, ''); // backspace — nothing new to say

      expect(raised, 2);
    });
  });

  group('digitPadFillTokens — {serial} in, {ocr} retired', () {
    test('{serial} resolves to the value it is given', () {
      expect(
          digitPadFillTokens('tercatat ({serial})',
              <String, String>{'serial': 'A21-4471908'}),
          'tercatat (A21-4471908)');
    });

    // The pending-safe dialect: a token with no value stays LITERAL. Do not
    // "harmonise" it with the <KEY> grammar, which resolves empty to ''.
    test('{serial} with no value stays literal', () {
      expect(digitPadFillTokens('tercatat ({serial})', <String, String>{}),
          'tercatat ({serial})');
    });

    // ★ RED if: `ocr` is put back into the token regex. Spec §3.2 retires it —
    // with substring matching there is no single "OCR value" to display, so it
    // must stay literal EVEN when a value is supplied.
    test('{ocr} is retired and stays literal even with a value present', () {
      expect(digitPadFillTokens('{ocr}', <String, String>{'ocr': 'X'}), '{ocr}');
    });

    test('the surviving tokens are untouched', () {
      expect(
          digitPadFillTokens('{value} {prev} {delta} {avg} {n}',
              <String, String>{
                'value': '1',
                'prev': '2',
                'delta': '3',
                'avg': '4',
                'n': '5'
              }),
          '1 2 3 4 5');
    });
  });

  // ── digit-pad-deltamax-serial (2026-09-04) ───────────────────────────────

  group('digitPadPow10', () {
    // RED if: the cap is dropped (a runaway red count overflows), or the loop
    // is off by one.
    test('exact powers of ten, floored at 1 and capped at digitPadMaxBoxes',
        () {
      expect(digitPadPow10(0), 1);
      expect(digitPadPow10(1), 10);
      expect(digitPadPow10(2), 100);
      expect(digitPadPow10(3), 1000);
      expect(digitPadPow10(-4), 1);
      expect(digitPadPow10(digitPadMaxBoxes), 1000000000000);
      expect(digitPadPow10(99), digitPadPow10(digitPadMaxBoxes));
    });
  });

  group('digitPadCubic', () {
    // ★ RED if: the `pow10 <= 1` short circuit is removed. Nothing else in
    // either suite can see that mutation — 1000 / 1 is 1000.0 and digitPadFmt
    // prints both as "1000" — so this is the ONLY assertion that pins the
    // no-promotion guarantee the zero-regression claim rests on.
    test('pow10 1 returns the argument untouched, int stays int', () {
      expect(digitPadCubic(1000, 1), 1000);
      expect(digitPadCubic(1000, 1), isA<int>());
      expect(digitPadCubic(1000, 0), isA<int>());
      expect(digitPadCubic(null, 100), isNull);
    });

    // RED if: the division is inverted or the divisor is dropped.
    test('a dgm 2 stand becomes m³', () {
      expect(digitPadCubic(12600, 100), 126.0);
      expect(digitPadCubic(17600, 100), 176.0);
      expect(digitPadCubic(12601, 100), 126.01);
      expect(digitPadCubic(1000, 10), 100.0);
    });

    // The pair BOTH previous boundary tests picked: 22600 and 12600 are each
    // exactly representable after the division, so subtracting the quotients
    // happens to give exactly 100.0. This is the LUCKY case, kept only to show
    // that it IS lucky — see the test below for the same boundary on a prev
    // that is not.
    test('two exact quotients happen to subtract exactly', () {
      final num delta =
          digitPadCubic(22600, 100)! - digitPadCubic(12600, 100)!;
      expect(delta, 100.0);
      expect(digitPadFmt(delta), '100');
    });
  });

  group('digitPadDelta', () {
    // ★★ THE reason this function exists, stated as an assertion.
    //
    // ★ RED if: digitPadDelta goes back to dividing both sides. 2802 / 100 and
    // 12802 / 100 are each the correctly-rounded nearest double, and their
    // difference is 100.00000000000001 — which is `> 100` and so tripped a
    // `deltaMax: 100` ceiling on a reading of exactly 100 m³. Measured at
    // 1.64% of raw prev values in 0..999999 at dgm:2, always sane -> spike.
    test('the DIFFERENCE is divided once, not each side separately', () {
      // What the first cut computed, and why it was wrong:
      expect(digitPadCubic(12802, 100)! - digitPadCubic(2802, 100)!,
          isNot(100.0));
      // What this function computes:
      expect(digitPadDelta(value: 12802, prev: 2802, pow10: 100), 100.0);
      expect(digitPadDelta(value: 12802, prev: 2802, pow10: 100)! > 100,
          isFalse);
      expect(digitPadFmt(digitPadDelta(value: 12802, prev: 2802, pow10: 100)!),
          '100');
      // The ordinary sane path the officer reads every month, which rendered
      // "50.00999999999999" before.
      expect(digitPadFmt(digitPadDelta(value: 17601, prev: 12600, pow10: 100)!),
          '50.01');
    });

    // ★ RED if: the pow10 <= 1 short circuit is lost on this path. dgm:0 is the
    // one live shape and must stay int-in / int-out, byte-identical copy.
    test('pow10 1 keeps the delta an int', () {
      expect(digitPadDelta(value: 1150, prev: 1000), 150);
      expect(digitPadDelta(value: 1150, prev: 1000), isA<int>());
    });

    // Null is "no delta", never 0 — an incomplete reading must not render
    // `{delta}` as a real number.
    test('either side null is null, never zero', () {
      expect(digitPadDelta(value: null, prev: 1000, pow10: 100), isNull);
      expect(digitPadDelta(value: 1000, prev: null, pow10: 100), isNull);
    });

    // Backward stays negative through the division, which is what keeps the
    // `value < prev` branch scale-invariant.
    test('a backward reading keeps its sign', () {
      expect(digitPadDelta(value: 900, prev: 1000, pow10: 100), -1.0);
    });
  });

  group('digitPadVerdict — deltaMax', () {
    DigitPadVerdict v(num value, num prev, {num? avg, num deltaMax = 0}) =>
        digitPadVerdict(
          value: value,
          prev: prev,
          avg: avg,
          spikeMultiplier: 4,
          deltaMax: deltaMax,
        );

    // ★ Acceptance §11 line 3. RED if: the `deltaMax > 0` guard is dropped —
    // an absent cell defaults to 0 and would then flag EVERY reading.
    test('deltaMax 0, negative or absent leaves the verdict exactly as it was',
        () {
      expect(v(1150, 1000, avg: 100), DigitPadVerdict.sane);
      expect(v(1150, 1000, avg: 100, deltaMax: 0), DigitPadVerdict.sane);
      expect(v(1150, 1000, avg: 100, deltaMax: -5), DigitPadVerdict.sane);
      expect(v(900, 1000, deltaMax: 100), DigitPadVerdict.backward);
    });

    // ★ Acceptance §11 line 1 — the new-point hole. RED if: the deltaMax branch
    // is never reached when avg is null.
    test('an avg-less point finally has a ceiling', () {
      expect(v(1150, 1000), DigitPadVerdict.sane); // no avg, no deltaMax
      expect(v(1150, 1000, deltaMax: 100), DigitPadVerdict.spike);
    });

    // ★ RED if: the branch uses `>=`. Segment 15 says "melewati batas".
    test('exactly at deltaMax is sane; one unit past it is a spike', () {
      expect(v(1100, 1000, deltaMax: 100), DigitPadVerdict.sane);
      expect(v(1101, 1000, deltaMax: 100), DigitPadVerdict.spike);
    });

    // RED if: the deltaMax branch is placed before the backward branch.
    test('backward still wins over deltaMax', () {
      expect(v(500, 1000, deltaMax: 100), DigitPadVerdict.backward);
    });

    // Both branches produce the SAME verdict; the message choice is the
    // widget's, not this function's.
    test('the avg branch and the deltaMax branch are the same verdict', () {
      expect(v(9999, 1000, avg: 30), DigitPadVerdict.spike);
      expect(v(9999, 1000, deltaMax: 100), DigitPadVerdict.spike);
    });
  });

  group('digitPadFillTokens — {deltaMax}', () {
    // ★★ THE regex-ordering test. RED if: `deltaMax` is listed after `delta` in
    // _digitPadToken AND the engine stops backtracking, and RED today if anyone
    // "simplifies" the alternation to `delta` alone.
    test('{delta} and {deltaMax} both resolve from the same template', () {
      expect(
        digitPadFillTokens(
          'Pemakaian {delta} m³ — melewati batas {deltaMax} m³.',
          <String, String>{'delta': '150', 'deltaMax': '100'},
        ),
        'Pemakaian 150 m³ — melewati batas 100 m³.',
      );
    });

    // The pending-safe dialect: no value -> the token stays LITERAL.
    test('{deltaMax} with no value stays literal', () {
      expect(
        digitPadFillTokens('batas {deltaMax} m³', <String, String>{}),
        'batas {deltaMax} m³',
      );
    });
  });

  group('digitPadSerialMatch', () {
    // ★ Acceptance §11 line 4, first half.
    test('punctuation and case disappear on BOTH sides', () {
      expect(digitPadSerialMatch('B21-4471902', 'B214471902'), isTrue);
      expect(digitPadSerialMatch('B21-4471902', 'b21 4471902'), isTrue);
      expect(digitPadSerialMatch('B21-4471902', 'B21/4471902'), isTrue);
    });

    // ★ RED if: the match goes back to one direction only (the deleted
    // digitPadSerialSatisfied did `read.contains(recorded)` and nothing else).
    test('substring matches in BOTH directions', () {
      expect(digitPadSerialMatch('B214471902', 'PDAM B214471902 SNI'), isTrue);
      expect(digitPadSerialMatch('PDAM B214471902 SNI', 'B214471902'), isTrue);
    });

    // ★ RED if: the < 4 rule is dropped. 'A1' substring-matches half the fleet.
    test('under four characters demands exact equality', () {
      expect(digitPadSerialMatch('A1', 'A1'), isTrue);
      expect(digitPadSerialMatch('A1', 'A1B2C3'), isFalse);
      expect(digitPadSerialMatch('A1B2C3', 'A1'), isFalse);
      expect(digitPadSerialMatch('ABC', 'ABCD'), isFalse);
    });

    test('a different unit is a mismatch', () {
      expect(digitPadSerialMatch('B21-4471902', 'X99-1234567'), isFalse);
    });

    test('either side empty is never a match', () {
      expect(digitPadSerialMatch('', 'B214471902'), isFalse);
      expect(digitPadSerialMatch('B214471902', ''), isFalse);
      expect(digitPadSerialMatch('B214471902', '  -- '), isFalse);
    });
  });

  group('digitPadSerialState', () {
    // ★ Acceptance §11 line 6 — the owner's second sentence.
    test('a blank recorded serial is OFF, whatever the slot holds', () {
      expect(digitPadSerialState(recorded: '', read: ''),
          DigitPadSerialState.off);
      expect(digitPadSerialState(recorded: '  ', read: 'X99'),
          DigitPadSerialState.off);
      expect(digitPadSerialState(recorded: '--', read: 'X99'),
          DigitPadSerialState.off);
    });

    // ★★ RED if: digitPadNormalizeSeed is dropped from the read side. Without
    // it 'null' normalises to the serial NULL and every unauthored TXF reports
    // a MISMATCH instead of MISSING — on a page the officer never touched.
    test('every empty sentinel in the slot is MISSING, never a mismatch', () {
      for (final String seed in <String>['', '  ', '--', 'null', '---']) {
        expect(
          digitPadSerialState(recorded: 'B21-4471902', read: seed),
          DigitPadSerialState.missing,
          reason: 'slot seed "$seed" must read as MISSING',
        );
      }
    });

    test('a matching slot is OK and a different one is MISMATCH', () {
      expect(
          digitPadSerialState(recorded: 'B21-4471902', read: 'B214471902'),
          DigitPadSerialState.ok);
      expect(
          digitPadSerialState(recorded: 'B21-4471902', read: 'X99-1234567'),
          DigitPadSerialState.mismatch);
    });
  });

  group('digitPadSerialKey', () {
    // What this test can and cannot see, stated honestly.
    //
    // digitPadSerialKey has NO `read` parameter, so no mutation of THIS
    // function can make the key carry the read value; this test therefore
    // cannot be the pin for that defect, and its name is scoped accordingly.
    // What it does pin is that the mismatch key ignores `readingComplete` —
    // the one input it has that could move it mid-edit.
    //
    // ★ The anti-keystroke defect itself is pinned by exactly ONE test, in the
    // other suite: `editing a wrong serial raises the sheet ONCE, not per
    // keystroke` (test/digit_pad_widget_test.dart), which drives the real
    // per-character writes through the call site that composes `recorded`.
    // Do not delete it believing this group covers it.
    //
    // ★ RED if: the mismatch key starts varying with readingComplete.
    test('the mismatch key ignores readingComplete', () {
      final String a = digitPadSerialKey(
          state: DigitPadSerialState.mismatch,
          recorded: 'B21-4471902',
          readingComplete: true);
      final String b = digitPadSerialKey(
          state: DigitPadSerialState.mismatch,
          recorded: 'B21-4471902',
          readingComplete: false);
      expect(a, isNotEmpty);
      expect(a, b);
    });

    // ★ RED if: MISSING and MISMATCH collapse to one key. `missing ->
    // mismatch` is new information and earns its own single raise.
    test('missing and mismatch are different keys', () {
      expect(
        digitPadSerialKey(
            state: DigitPadSerialState.missing,
            recorded: 'B21-4471902',
            readingComplete: true),
        isNot(digitPadSerialKey(
            state: DigitPadSerialState.mismatch,
            recorded: 'B21-4471902',
            readingComplete: true)),
      );
    });

    // ★ RED if: readingComplete stops gating MISSING — the sheet would then
    // rise on page load for every meter in the fleet.
    test('MISSING waits for a complete reading, MISMATCH does not', () {
      expect(
          digitPadSerialKey(
              state: DigitPadSerialState.missing,
              recorded: 'B21-4471902',
              readingComplete: false),
          '');
      expect(
          digitPadSerialKey(
              state: DigitPadSerialState.missing,
              recorded: 'B21-4471902',
              readingComplete: true),
          isNotEmpty);
      expect(
          digitPadSerialKey(
              state: DigitPadSerialState.mismatch,
              recorded: 'B21-4471902',
              readingComplete: false),
          isNotEmpty);
    });

    // ★ RED if: off/ok return something non-empty. '' is ALSO the re-arm
    // signal digitPadSheetKey documents — a key that is never empty latches
    // forever.
    test("off and ok yield '' — the re-arm signal", () {
      expect(
          digitPadSerialKey(
              state: DigitPadSerialState.off,
              recorded: '',
              readingComplete: true),
          '');
      expect(
          digitPadSerialKey(
              state: DigitPadSerialState.ok,
              recorded: 'B21-4471902',
              readingComplete: true),
          '');
    });
  });

  group('digitPadSerialOwnsSheet — the LOCKING problem wins', () {
    // ★ RED if: the serialBlocking short circuit is dropped. With the gate on,
    // _sheetBlocked hides segment 13, so a sheet carrying the SPIKE copy would
    // demand a correction that cannot lift the block.
    test('a blocking serial problem takes the sheet from any verdict', () {
      for (final DigitPadVerdict v in DigitPadVerdict.values) {
        expect(
          digitPadSerialOwnsSheet(
              verdict: v, serialMismatch: true, serialBlocking: true),
          isTrue,
          reason: 'blocking serial must own the sheet over $v',
        );
      }
    });

    // ★ RED if: serialBlocking is ORed in without the !serialMismatch guard.
    test('no serial problem, nothing to own — even when blocking is true', () {
      expect(
        digitPadSerialOwnsSheet(
            verdict: DigitPadVerdict.sane,
            serialMismatch: false,
            serialBlocking: true),
        isFalse,
      );
    });

    // The pre-2026-09-04 precedence, unchanged when nothing is locking.
    test('a non-blocking serial problem still yields to the numbers', () {
      expect(
        digitPadSerialOwnsSheet(
            verdict: DigitPadVerdict.backward,
            serialMismatch: true,
            serialBlocking: false),
        isFalse,
      );
      expect(
        digitPadSerialOwnsSheet(
            verdict: DigitPadVerdict.sane,
            serialMismatch: true,
            serialBlocking: false),
        isTrue,
      );
    });
  });

  group('the serial latch over a SEQUENCE — one raise per state transition', () {
    // ★★ The end-to-end script the widget runs, driven with the same pure
    // functions. The officer's keystrokes are the INPUT: `read` goes through
    // digitPadSerialState exactly as _content passes it, so the mismatch steps
    // below are derived, not asserted by hand.
    //
    // RED, both measured against the mutants rather than reasoned:
    //   * missing and mismatch collapse to one key -> `raised` drops to 1;
    //   * the MISSING raise stops waiting for a complete reading -> `raised`
    //     stays 2 but `raisedAt` becomes [0, 2]. The count alone does NOT see
    //     that mutant: the page-load raise DISPLACES the reading-complete
    //     raise (both carry the same serial key, so the latch swallows the
    //     second) instead of adding to it. That is why this test asserts the
    //     step indices; asserting only the total was the gap.
    //
    // ★ NOT red if the key starts carrying the read value: digitPadSerialKey
    // has no `read` parameter, so that defect is not expressible against these
    // signatures at all. It is pinned by exactly ONE test, in the other suite —
    // `editing a wrong serial raises the sheet ONCE, not per keystroke`
    // (test/digit_pad_widget_test.dart), which drives the real per-character
    // writes through the call site that composes `recorded`. That test is the
    // sole pin; do not delete it believing this script covers it.
    test('missing -> mismatch -> two edits -> match raises exactly twice', () {
      String? latch;
      int raised = 0;
      // WHICH step raised, not only how many did. Measured: a count alone
      // cannot see the missing-raise gate, because dropping it MOVES the first
      // raise from step 1 to step 0 instead of adding one — the total stays 2.
      final List<int> raisedAt = <int>[];
      int stepIndex = 0;
      void step(String read, String submit) {
        final DigitPadSerialState state = digitPadSerialState(
          recorded: 'B21-4471902',
          read: read,
        );
        final String serialKey = digitPadSerialKey(
          state: state,
          recorded: 'B21-4471902',
          readingComplete: submit.isNotEmpty,
        );
        final bool problem = state == DigitPadSerialState.missing ||
            state == DigitPadSerialState.mismatch;
        final bool owns = digitPadSerialOwnsSheet(
          verdict: DigitPadVerdict.sane,
          serialMismatch: problem,
          serialBlocking: problem,
        );
        final String key = digitPadSheetKey(
            submitValue: submit, ocrKey: serialKey, serialOwns: owns);
        final bool raise = digitPadShouldRaiseAnySheet(
          verdict: DigitPadVerdict.sane,
          submitValue: submit,
          sheetText: owns ? 'seri' : 'masuk akal',
          serialOwns: owns,
          sheetKey: key,
          alreadyRaisedFor: latch,
        );
        if (raise) {
          raised++;
          raisedAt.add(stepIndex);
        }
        stepIndex++;
        final String next = digitPadNextSheetLatch(
            previous: latch ?? '', sheetKey: key, raised: raise);
        latch = next.isEmpty ? null : next;
      }

      // read '' -> missing; 'B'/'B2'/'B21' -> mismatch (under four characters
      // demands exact equality); 'B214' -> ok (substring of the recorded
      // 'B214471902'). All four verdicts come from digitPadSerialState.
      step('', ''); // page load — silent
      step('', '1100'); // reading complete            -> raise 1
      step('B', '1100'); //   mismatch, new state      -> raise 2
      step('B2', '1100'); //  still mismatch           -> silent
      step('B21', '1100'); // still mismatch           -> silent
      step('B214', '1100'); // ok                      -> silent

      expect(raised, 2);
      // Step 0 is the page load and MUST be silent; the two raises are the
      // completed reading and the first mismatch.
      expect(raisedAt, <int>[1, 2]);
    });
  });
}
