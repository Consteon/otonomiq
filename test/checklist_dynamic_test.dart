// test/checklist_dynamic_test.dart
//
// Pure-function tests for CHECKLIST_DYNAMIC (per-field output, round 2).
// NO harness, NO Firebase, NO mocks (mockito/mocktail are not dependencies of
// this repo and must not be added).
//
// Two groups carry more weight than the rest:
//
//  * "delivered value" asserts what the SERVER receives after saveSend's
//    stringCleanUp pass, not merely what the widget built. The `|` and the
//    surrounding spaces must survive; `◆` must not.
//
//  * "sort stability" uses a 40-DOC fixture on purpose. Dart's List.sort is a
//    dual-pivot quicksort that falls back to insertion sort below 32 elements,
//    so a 3-doc fixture is stable even WITHOUT the explicit tie-break and would
//    certify nothing. 40 all-equal keys is the smallest measured size at which
//    the plain sort actually reorders (measured: n=33 stable, n=40 unstable).
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/sdui_spec.dart';
import 'package:otonomiq/widget/checklist_dynamic.dart';

void main() {
  final String d = separator[1]; // ◆

  List<ChecklistOption> opts4() => checklistParseOptions(<String>[
        '✓', 'Selesai', 'Tandai Selesai',
        '✖', 'Tidak Tersedia', 'Barang tidak ada di area ini',
        '>', 'Dilewati', 'Kembali lagi nanti',
        '!', 'Masalah', 'Jelaskan dalam laporan',
      ]);

  Map<String, String> l2k4() => checklistLabelToKey(
        <String>['Selesai', 'Tidak Tersedia', 'Dilewati', 'Masalah'],
        'belum',
      );

  /// The four documents that actually exist in
  /// MobileTable/20342033315492/tables/84214220504259/checklist_template on
  /// 2026-08-21, in Firestore's default document-id-ascending order.
  /// NOTE the seed is mid-normalisation: `ord` on one doc, `order` on three,
  /// two Restroom docs tied at 3, and no Restroom doc at 1.
  List<Map<String, dynamic>> liveDocs() => <Map<String, dynamic>>[
        <String, dynamic>{
          '__docId': '4tmKu8rG1Ie6O9vEVjeV',
          'ord': 1,
          'tmp': 'Pantry',
          'tsk': 'Bersihkan sink & keran',
        },
        <String, dynamic>{
          '__docId': 'FaHaUC4AjsIdzmGJGJF2',
          'order': 2,
          'tmp': 'Restroom',
          'tsk': 'Isi ulang sabun & tisu',
        },
        <String, dynamic>{
          '__docId': 'bzJM0qsvJ7DucJDgN9hg',
          'order': 3,
          'tmp': 'Restroom',
          'tsk': 'Sapu & pel lantai',
        },
        <String, dynamic>{
          '__docId': 'f5zvzeYd2LfYmzgRRUEt',
          'order': 3,
          'tmp': 'Restroom',
          'tsk': 'Semprot pengharum',
        },
      ];

  // ── pure-01 .. pure-04 : serialize, the " | " format ─────────────────────

  group('checklistSerialize', () {
    // RED if: the space-pipe-space join is changed (M1).
    test('pure-01 emits "title | label" with a spaced pipe', () {
      expect(checklistSerialize('Sapu & pel lantai', 'Selesai'),
          'Sapu & pel lantai | Selesai');
    });

    // RED if: the pipe strip is dropped from either operand (M2).
    test('pure-02 a pipe in EITHER operand becomes a space', () {
      expect(checklistSerialize('Cek panel A|B', 'Selesai'),
          'Cek panel A B | Selesai');
      expect(checklistSerialize('Ganti filter', 'Sele|sai'),
          'Ganti filter | Sele sai');
      expect(checklistSerialize('Cek A|B|C', 'Dilewati'),
          'Cek A B C | Dilewati');
    });

    // ★ THE SYMMETRY RULE. The emitted title operand IS its own map key, so a
    // title that ENDS in the delimiter cannot leave a trailing space that makes
    // the writer's key differ from the reader's.
    // RED if: checklistSerialize stops routing the title through
    // checklistTitleKey (M3).
    test('pure-03 the title operand is emitted in normalised key form', () {
      expect(checklistSerialize('Cek A|', 'Selesai'), 'Cek A | Selesai');
      expect(checklistSerialize('  Cek A  ', 'Selesai'), 'Cek A | Selesai');
      final String v = checklistSerialize('Cek A|', 'Selesai');
      expect(checklistParsePair(v)!.first, checklistTitleKey('Cek A|'));
    });

    // ★ D6: `~` RETIRED as a structural delimiter. A tenant task title
    // containing a tilde must now survive verbatim.
    // RED if: a `~` strip is (re-)added to checklistSanitize (M4).
    test('pure-04 a tilde is NO LONGER structural and survives verbatim', () {
      expect(checklistSerialize('Cek panel A~B', 'Selesai'),
          'Cek panel A~B | Selesai');
      expect(checklistTitleKey('Cek panel A~B'), 'Cek panel A~B');
    });
  });

  // ── pure-05 .. pure-06 : the gate that protects the wire format ──────────

  group('delivered value (survives saveSend stringCleanUp)', () {
    // ★ RED if: the pair separator becomes any forbiddenCharacter entry.
    test('pure-05 a per-field value survives the submit pipeline intact', () {
      final String v = checklistSerialize('Cek jam: shift pagi', 'Dilewati');
      expect(stringCleanUp(v), 'Cek jam: shift pagi | Dilewati');
    });

    // ★ RED the day forbiddenCharacter changes. The dev spec's `◆` proposal
    // written down as an executable fact: it is destroyed in transit. `★` is
    // pinned too because it is the history row's own field separator
    // (api.dart:5041) -- a title carrying one would split the row.
    test('pure-06 the spec ◆ would NOT survive; " | " and spaces do', () {
      expect(stringCleanUp('a◆b'), 'a b');
      expect(stringCleanUp('a★b'), 'a b');
      expect(stringCleanUp('a ⭘ b'), 'a   b');
      expect(stringCleanUp('a | b'), 'a | b');
      expect(stringCleanUp('a~b'), 'a~b');
    });
  });

  // ── pure-07 .. pure-11 : parse / re-hydrate ──────────────────────────────

  group('checklistParsePair / checklistParseSlots', () {
    // ★ BOTH shapes must re-hydrate: ' | ' is what this build writes, bare '|'
    // is what the LIVE build wrote (CLN-2026-000525, ck="…|Selesai").
    test('pure-07 both "a | b" and the live bare "a|b" re-hydrate', () {
      expect(checklistParsePair('A | Selesai'), <String>['A', 'Selesai']);
      expect(checklistParsePair('A|Selesai'), <String>['A', 'Selesai']);
      expect(checklistParsePair('A |  Selesai '), <String>['A', 'Selesai']);
    });

    // ★ '--'.isEmpty is FALSE, and null.toString() is the 4-char "null" that
    // getInitialValue seeds when `currentValue` is absent (init_values.dart:11).
    // Every one of the three needs its own comparison.
    test('pure-08 empty, the -- sentinel and the literal "null" all yield null',
        () {
      expect(checklistParsePair(''), isNull);
      expect(checklistParsePair('   '), isNull);
      expect(checklistParsePair(emptyString), isNull);
      expect(checklistParsePair('null'), isNull);
      expect(emptyString, '--'); // pins the sentinel this test relies on
      expect(checklistSlotIsEmpty('--'), isTrue);
      expect(checklistSlotIsEmpty('null'), isTrue);
      expect(checklistSlotIsEmpty('A | Selesai'), isFalse);
    });

    test('pure-09 malformed values are skipped, not crashed on', () {
      expect(checklistParsePair('nodelimiter'), isNull);
      expect(checklistParsePair(' | Selesai'), isNull); // empty title
      expect(
        checklistParseSlots(<String>['A | Selesai', '', 'B | belum', '--']),
        <String, String>{'A': 'Selesai', 'B': 'belum'},
      );
    });

    // ★ D6 migration tolerance. A slot still holding a round-1 joined blob
    // splits on the FIRST pipe, so the label is garbage, matches no configured
    // status, and the task falls back to pending. Degrades; never throws.
    test('pure-10 a legacy ~-joined blob degrades to pending, never a crash',
        () {
      expect(checklistParsePair('a|X~b|Y'), <String>['a', 'X~b|Y']);
      expect(checklistStatusByTitle(<String>['a|X~b|Y'], l2k4()), isEmpty);
    });

    test('pure-11 an unknown stored label is dropped (task falls to pending)',
        () {
      final Map<String, String> byTitle = checklistStatusByTitle(
          <String>['A | Selesai', 'B | LabelYangSudahDiganti'], l2k4());
      expect(byTitle, <String, String>{'A': 'done'});
      expect(byTitle.containsKey('B'), isFalse);
    });
  });

  // ── pure-12 .. pure-14 : label <-> key ───────────────────────────────────

  group('checklistLabelToKey', () {
    test('pure-12 maps every option label plus the pending label', () {
      expect(l2k4(), <String, String>{
        'belum': 'pending',
        'Selesai': 'done',
        'Tidak Tersedia': 'not_available',
        'Dilewati': 'skipped',
        'Masalah': 'issue',
      });
    });

    // ★ W1: a BLANK option label is NOT skipped -- it registers the status KEY
    // as its own label, because checklistLabelForKey emits that key for a blank
    // option. Skipping it breaks the round trip: the stored 'title | ' re-parses
    // to '', finds nothing here, and the row snaps back to pending on the very
    // next build -- silently, because _content recomposes unconditionally.
    // RED if either half of the repair is removed.
    test('pure-13 a short options list maps what it has; a blank maps its key',
        () {
      expect(checklistLabelToKey(<String>['Selesai', '', 'Dilewati'], 'belum'),
          <String, String>{
            'belum': 'pending',
            'Selesai': 'done',
            'not_available': 'not_available',
            'Dilewati': 'skipped',
          });
    });

    test('pure-14 maps each key to its option label and TASKLIST colour', () {
      final List<ChecklistOption> o = opts4();
      expect(checklistLabelForKey('done', o, 'belum'), 'Selesai');
      expect(checklistLabelForKey('issue', o, 'belum'), 'Masalah');
      expect(checklistLabelForKey('pending', o, 'belum'), 'belum');
      // out of range -> pendingLabel, never a crash
      expect(checklistLabelForKey('issue', o.sublist(0, 2), 'belum'), 'belum');
      expect(checklistLabelForKey('nonsense', o, 'belum'), 'belum');

      expect(checklistStatusColor('done').toARGB32(), 0xFF22C55E);
      expect(checklistStatusColor('not_available').toARGB32(), 0xFF9CA3AF);
      expect(checklistStatusColor('skipped').toARGB32(), 0xFFF59E0B);
      expect(checklistStatusColor('issue').toARGB32(), 0xFFEF4444);
      expect(checklistStatusColor('pending').toARGB32(), 0xFFD1D5DB);
    });
  });

  // ── pure-15 .. pure-20 : the fan-out value list ──────────────────────────

  group('checklistSlotValues', () {
    test('pure-15 an untouched checklist writes all-pending, one task per slot',
        () {
      expect(
        checklistSlotValues(
            <String>['A', 'B'], <String, String>{}, opts4(), 'belum', 2),
        <String>['A | belum', 'B | belum'],
      );
    });

    test('pure-16 statuses land on the right slot index, in display order', () {
      expect(
        checklistSlotValues(
          <String>['A', 'B', 'C'],
          <String, String>{'C': 'skipped', 'A': 'done'},
          opts4(),
          'belum',
          3,
        ),
        <String>['A | Selesai', 'B | belum', 'C | Dilewati'],
      );
    });

    // ★ D3/D4: the unused tail is BLANK, not pending. '' means "the template has
    // no task here"; '… | belum' means "a task exists and was left undone".
    // RED if: the tail branch is deleted (M5).
    test('pure-17 N < block: the tail slots are BLANK, not pending', () {
      expect(
        checklistSlotValues(
            <String>['A', 'B'], <String, String>{'A': 'done'}, opts4(),
            'belum', 4),
        <String>['A | Selesai', 'B | belum', '', ''],
      );
    });

    // ★ D3: NEVER write outside the block. The list can never be longer than
    // the block, whatever the task count.
    // RED if: the `k < block` bound is widened (M6).
    test('pure-18 N > block: the list is truncated to the block, never longer',
        () {
      expect(
        checklistSlotValues(
            <String>['A', 'B', 'C'], <String, String>{}, opts4(), 'belum', 2),
        <String>['A | belum', 'B | belum'],
      );
    });

    // ★ merge-by-title across slots: an edited template degrades, never crashes.
    test('pure-19 a removed title drops out; survivors keep their status', () {
      final List<String> before = checklistSlotValues(
        <String>['A', 'B', 'C'],
        <String, String>{'A': 'done', 'B': 'issue', 'C': 'skipped'},
        opts4(),
        'belum',
        3,
      );
      expect(before,
          <String>['A | Selesai', 'B | Masalah', 'C | Dilewati']);
      // Template edited: B deleted, D added. C has MOVED from slot 3 to slot 2.
      final List<String> after = checklistSlotValues(
        <String>['A', 'C', 'D'],
        checklistStatusByTitle(before, l2k4()),
        opts4(),
        'belum',
        3,
      );
      expect(after, <String>['A | Selesai', 'C | Dilewati', 'D | belum']);
    });

    // D8 support: a zero block produces zero writes.
    test('pure-20 a zero block yields an empty write list', () {
      expect(
          checklistSlotValues(
              <String>['A'], <String, String>{}, opts4(), 'belum', 0),
          isEmpty);
    });
  });

  // ── pure-21 .. pure-25 : block arithmetic (D3) ───────────────────────────

  group('block arithmetic', () {
    // ★ D3 degradation: absent / 0 / negative `slots` => claim exactly N.
    test('pure-21 slots absent, 0 or negative => block == taskCount', () {
      expect(checklistBlockSize(0, 4), 4);
      expect(checklistBlockSize(-3, 4), 4);
      expect(checklistBlockSize(0, 0), 0);
    });

    test('pure-22 slots set => block == slots, whatever the task count', () {
      expect(checklistBlockSize(6, 4), 6);
      expect(checklistBlockSize(6, 9), 6);
      expect(checklistBlockSize(6, 0), 6);
    });

    // ★ saveSend only submits slots 1..100 (api.dart:4834). A block running past
    // 100 would be dropped SILENTLY, so it is clamped and the clamp surfaces
    // through the same warning row.
    // RED if: the clamp is removed (M7).
    test('pure-23 the block never runs past form slot 100', () {
      expect(checklistEffectiveBlock(12, 6), 6);
      expect(checklistEffectiveBlock(98, 6), 3);
      expect(checklistEffectiveBlock(100, 6), 1);
      expect(checklistEffectiveBlock(101, 6), 0);
      expect(checklistEffectiveBlock(0, 6), 0); // no position => no block
      expect(checklistEffectiveBlock(12, 0), 0);
    });

    test('pure-24 overflow is the number of tasks the block cannot hold', () {
      expect(checklistOverflowCount(4, 6), 0);
      expect(checklistOverflowCount(6, 6), 0);
      expect(checklistOverflowCount(8, 6), 2);
      expect(checklistOverflowCount(3, 0), 3);
    });

    // The officer must be told BOTH numbers: how many are lost, and what the
    // page can hold. RED if either is dropped from the message.
    test('pure-25 the overflow message names the count and the capacity', () {
      final String m = checklistOverflowMessage(2, 6);
      expect(m.contains('2'), isTrue);
      expect(m.contains('6'), isTrue);
      expect(m.toLowerCase().contains('tidak akan terkirim'), isTrue);
    });
  });

  // ── pure-26 .. pure-32 : titles + sort ───────────────────────────────────

  group('checklistTitles / checklistSortDocs', () {
    test('pure-26 trims, drops blanks and missing task fields', () {
      expect(
        checklistTitles(<Map<String, dynamic>>[
          <String, dynamic>{'tsk': '  Sapu  '},
          <String, dynamic>{'tsk': ''},
          <String, dynamic>{'other': 'x'},
          <String, dynamic>{'tsk': 'Pel'},
        ], 'tsk'),
        <String>['Sapu', 'Pel'],
      );
      expect(checklistTitles(<Map<String, dynamic>>[
        <String, dynamic>{'tsk': 'Sapu'}
      ], ''), isEmpty);
    });

    // ★ RED if: coerceNum is replaced by a String compare. `ord` arrives as "10"
    // from a sheet and as 10 from a typed writer; "10" < "9" as strings.
    test('pure-27 sorts numerically even when ord is a String', () {
      final List<Map<String, dynamic>> docs = <Map<String, dynamic>>[
        <String, dynamic>{'tsk': 'T10', 'ord': '10'},
        <String, dynamic>{'tsk': 'T2', 'ord': 2},
        <String, dynamic>{'tsk': 'T9', 'ord': '9'},
      ];
      checklistSortDocs(docs, 'ord', false);
      expect(checklistTitles(docs, 'tsk'), <String>['T2', 'T9', 'T10']);
    });

    // desc flips the PRIMARY key only; ties keep incoming order.
    test('pure-28 desc flips the primary key, ties keep incoming order', () {
      final List<Map<String, dynamic>> docs = <Map<String, dynamic>>[
        <String, dynamic>{'tsk': 'T1', 'ord': 1},
        <String, dynamic>{'tsk': 'T3a', 'ord': 3},
        <String, dynamic>{'tsk': 'T3b', 'ord': 3},
      ];
      checklistSortDocs(docs, 'ord', true);
      expect(checklistTitles(docs, 'tsk'), <String>['T3a', 'T3b', 'T1']);

      final List<Map<String, dynamic>> untouched = <Map<String, dynamic>>[
        <String, dynamic>{'tsk': 'B'},
        <String, dynamic>{'tsk': 'A'},
      ];
      checklistSortDocs(untouched, '', false);
      expect(checklistTitles(untouched, 'tsk'), <String>['B', 'A']);
    });

    // ★★ REQUIREMENT (c). Three of the four LIVE docs have no `ord` key at all
    // until the owner renames them. coerceNum(null) == 0, so they sort as 0 --
    // they may lose their ordering, they must NEVER be dropped from the render.
    // RED if: checklistSortDocs starts filtering, or coerceNum stops defaulting.
    test('pure-29 a doc missing the sort field sorts as 0 and is NEVER dropped',
        () {
      final List<Map<String, dynamic>> docs = <Map<String, dynamic>>[
        <String, dynamic>{'tsk': 'NoOrd'},
        <String, dynamic>{'tsk': 'HasOrd', 'ord': 1},
        <String, dynamic>{'tsk': 'AlsoNoOrd'},
      ];
      checklistSortDocs(docs, 'ord', false);
      expect(docs.length, 3, reason: 'sort must never remove a doc');
      expect(checklistTitles(docs, 'tsk'),
          <String>['NoOrd', 'AlsoNoOrd', 'HasOrd']);
    });

    // ★ THE LIVE SEED, as it is TODAY (mid-normalisation).
    test('pure-30 the live seed sorts deterministically by ord', () {
      final List<Map<String, dynamic>> docs = liveDocs();
      checklistSortDocs(docs, 'ord', false);
      expect(checklistTitles(docs, 'tsk'), <String>[
        'Isi ulang sabun & tisu', // no `ord` -> 0
        'Sapu & pel lantai', //     no `ord` -> 0
        'Semprot pengharum', //     no `ord` -> 0
        'Bersihkan sink & keran', // ord == 1
      ]);
    });

    // ★★ REQUIREMENT (b). Production has TWO Restroom docs at value 3. They must
    // land in a deterministic, stable order or a status re-hydrated by title
    // would appear to jump rows between builds.
    // RED if: the tie-break direction is reversed (M9).
    test('pure-31 the live duplicate order=3 keeps incoming (doc-id) order', () {
      final List<Map<String, dynamic>> docs = liveDocs()
          .where((Map<String, dynamic> m) => m['tmp'] == 'Restroom')
          .toList();
      checklistSortDocs(docs, 'order', false);
      expect(checklistTitles(docs, 'tsk'), <String>[
        'Isi ulang sabun & tisu', // order 2
        'Sapu & pel lantai', //     order 3, docId bzJM…
        'Semprot pengharum', //     order 3, docId f5zv…
      ]);
    });

    // ★★★ THE ONLY MUTATION-PROOF FOR THE DECORATION. Dart's List.sort uses
    // insertion sort below 32 elements (stable) and dual-pivot quicksort above
    // (not stable). Measured on Flutter 3.44.4: n=33 stable, n=40 NOT. A small
    // fixture would stay green with the tie-break deleted and would certify
    // nothing. RED if: the index decoration is removed (M8).
    test('pure-32 40 docs with identical ord keep their incoming order', () {
      final List<Map<String, dynamic>> docs = <Map<String, dynamic>>[
        for (int i = 0; i < 40; i++)
          <String, dynamic>{
            'tsk': 'T${i.toString().padLeft(2, '0')}',
            'ord': 3,
          },
      ];
      final List<String> before = checklistTitles(docs, 'tsk');
      checklistSortDocs(docs, 'ord', false);
      expect(checklistTitles(docs, 'tsk'), before);
    });
  });

  // ── pure-33 .. pure-35 : config reads through SduiSpec ───────────────────

  group('config reads', () {
    test('pure-33 parses options in groups of 3 and drops a partial trailer',
        () {
      final List<ChecklistOption> o =
          checklistParseOptions(<String>['a', 'b', 'c', 'x', 'y']);
      expect(o.length, 1);
      expect(o.first.icon, 'a');
      expect(o.first.label, 'b');
      expect(o.first.description, 'c');
    });

    // ★ THE SduiSpec ASYMMETRY TRAP. text() guards LENGTH ONLY
    // (sdui_spec.dart:40): slot 0 of "◆Selesai◆…" EXISTS and is '', so
    // spec.text(0, def) returns '' -- not def. str() IS blank-aware
    // (sdui_spec.dart:47-51), which is exactly why D5 changes the defaults.
    // checklistText is the blank-aware wrapper for text slots.
    // RED if that wrapper is replaced by a bare spec.text (M10).
    test('pure-34 a blank text slot falls back; an out-of-range one too', () {
      final SduiSpec spec = SduiSpec(<String, dynamic>{
        'text': <String>[
          '', // 0 blank on purpose -- this is the spec's own config
          'Selesai',
          'Tidak tersedia di area ini',
          'Dilewati - Kunjungi kembali nanti',
          'Masalah - jelaskan dalam laporan.',
        ].join(d),
      });
      // The trap itself, pinned:
      expect(spec.text(0, 'FALLBACK'), '');
      // The wrapper repairs it:
      expect(checklistText(spec, 0, 'FALLBACK'), 'FALLBACK');
      expect(checklistEmptyMessage(spec), checklistDefaultEmptyMessage);
      expect(checklistText(spec, 9, 'OUT'), 'OUT');
      expect(checklistText(spec, 1, 'FALLBACK'), 'Selesai');
      // D5's premise, pinned: a BLANK cell selects the DEFAULT, it is not ''.
      expect(spec.str('taskField', checklistDefaultTaskField), 'tsk');
      expect(
          SduiSpec(<String, dynamic>{'taskField': '   '})
              .str('taskField', checklistDefaultTaskField),
          'tsk');
      expect(
          SduiSpec(<String, dynamic>{'taskField': 'task'})
              .str('taskField', checklistDefaultTaskField),
          'task');
    });

    test('pure-35 an authored slot 0 overrides the Indonesian default', () {
      final SduiSpec spec = SduiSpec(<String, dynamic>{
        'text': <String>['Belum ada task.', 'Selesai'].join(d),
      });
      expect(checklistEmptyMessage(spec), 'Belum ada task.');
      // D5 / D9: the defaults live in ONE named place each.
      expect(checklistDefaultTaskField, 'tsk');
      expect(checklistDefaultSortField, 'ord');
      expect(checklistDefaultPendingLabel, 'belum');
    });
  });

  // ── pure-36 .. pure-37 : W1, the blank options label ─────────────────────

  group('blank options label (W1)', () {
    // ★ THE W1 DEFECT, pinned, now across SLOTS. A blank configured label used
    // to make the officer's tap vanish: compose wrote 'title | ' (blank label),
    // which re-parses to '', which has no entry in labelToKey, so the status was
    // DROPPED and the row snapped back to pending on the very next build.
    // The repair is two-sided: checklistLabelForKey emits the status KEY for a
    // blank option, and checklistLabelToKey registers that key so the reverse
    // lookup finds it. A key is never blank, so the value always round-trips.
    // RED if: either half of the repair is removed.
    test('pure-36 a blank label survives write -> parse -> write', () {
      final List<ChecklistOption> o = checklistParseOptions(<String>[
        '✓', 'Selesai', 'Tandai Selesai',
        '✖', '', 'Barang tidak ada di area ini', // ← blank label on purpose
        '>', 'Dilewati', 'Kembali lagi nanti',
      ]);
      final Map<String, String> l2k = checklistLabelToKey(
        <String>[for (final ChecklistOption x in o) x.label],
        'belum',
      );

      final List<String> v = checklistSlotValues(
        <String>['A', 'B'],
        <String, String>{'A': 'not_available', 'B': 'skipped'},
        o,
        'belum',
        2,
      );
      // The blank label is emitted as its own key, never as ''.
      expect(v, <String>['A | not_available', 'B | Dilewati']);

      // The status SURVIVES the re-hydrate that every build performs...
      final Map<String, String> back = checklistStatusByTitle(v, l2k);
      expect(back, <String, String>{'A': 'not_available', 'B': 'skipped'});

      // ...and the rewrite is idempotent, so the row does not revert.
      expect(checklistSlotValues(<String>['A', 'B'], back, o, 'belum', 2), v);
    });

    // A full write -> parse -> write cycle over a block WITH a blank tail, to
    // prove the tail does not poison the map on the next build.
    test('pure-37 a blank tail slot does not poison the next re-hydrate', () {
      final List<String> v = checklistSlotValues(
        <String>['A', 'B'],
        <String, String>{'A': 'done'},
        opts4(),
        'belum',
        4,
      );
      expect(v, <String>['A | Selesai', 'B | belum', '', '']);
      final Map<String, String> back = checklistStatusByTitle(v, l2k4());
      expect(back, <String, String>{'A': 'done', 'B': 'pending'});
      expect(checklistSlotValues(<String>['A', 'B'], back, opts4(), 'belum', 4),
          v);
    });
  });
}
