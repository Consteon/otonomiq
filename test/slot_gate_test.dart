// Tests for slot gate helpers in lib/widget/list_card_support.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/list_card_support.dart';

void main() {
  // ── parseGateSlot ─────────────────────────────────────────────────────

  group('parseGateSlot', () {
    test('parses full 3 fields', () {
      final cfg = parseGateSlot('sc\u{25C6}ak\u{25C6}cl');
      expect(cfg.slotField, 'sc');
      expect(cfg.pointerField, 'ak');
      expect(cfg.levelField, 'cl');
      expect(cfg.isEmpty, isFalse);
    });

    test('empty string → isEmpty true', () {
      final cfg = parseGateSlot('');
      expect(cfg.isEmpty, isTrue);
      expect(cfg.slotField, '');
      expect(cfg.pointerField, '');
      expect(cfg.levelField, '');
    });

    test('whitespace-only → isEmpty true', () {
      final cfg = parseGateSlot('   ');
      expect(cfg.isEmpty, isTrue);
    });

    test('short: 1 field only → isEmpty true (pointer AND level both empty)', () {
      final cfg = parseGateSlot('sc');
      expect(cfg.slotField, 'sc');
      expect(cfg.pointerField, '');
      expect(cfg.levelField, '');
      expect(cfg.isEmpty, isTrue);
    });

    test('short: 2 fields (slot + pointer) → isEmpty false (pointer present)', () {
      final cfg = parseGateSlot('sc\u{25C6}ak');
      expect(cfg.slotField, 'sc');
      expect(cfg.pointerField, 'ak');
      expect(cfg.levelField, '');
      expect(cfg.isEmpty, isFalse);
    });

    test('trims whitespace in each field', () {
      final cfg = parseGateSlot(' sc \u{25C6} ak \u{25C6} cl ');
      expect(cfg.slotField, 'sc');
      expect(cfg.pointerField, 'ak');
      expect(cfg.levelField, 'cl');
    });

    test('extra segments beyond 3 are ignored', () {
      final cfg = parseGateSlot('sc\u{25C6}ak\u{25C6}cl\u{25C6}extra');
      expect(cfg.slotField, 'sc');
      expect(cfg.pointerField, 'ak');
      expect(cfg.levelField, 'cl');
    });
  });

  // ── parseSlotTerms ────────────────────────────────────────────────────

  group('parseSlotTerms', () {
    test('empty string → empty sets', () {
      final terms = parseSlotTerms('');
      expect(terms.concrete, isEmpty);
      expect(terms.wildcardLevels, isEmpty);
    });

    test('single concrete term', () {
      final terms = parseSlotTerms('83674161979544-1');
      expect(terms.concrete, {'83674161979544-1'});
      expect(terms.wildcardLevels, isEmpty);
    });

    test('multiple concrete terms', () {
      final terms = parseSlotTerms(
          '83674161979544-1|83674161979544-2|32639062303108-3');
      expect(terms.concrete,
          {'83674161979544-1', '83674161979544-2', '32639062303108-3'});
      expect(terms.wildcardLevels, isEmpty);
    });

    test('single wildcard *-3', () {
      final terms = parseSlotTerms('*-3');
      expect(terms.concrete, isEmpty);
      expect(terms.wildcardLevels, {'3'});
    });

    test('mixed concrete and wildcard', () {
      final terms = parseSlotTerms('83674161979544-1|*-2|32639062303108-3');
      expect(terms.concrete, {'83674161979544-1', '32639062303108-3'});
      expect(terms.wildcardLevels, {'2'});
    });

    test('stray pipes and whitespace', () {
      final terms = parseSlotTerms('|term1| |term2|');
      expect(terms.concrete, {'term1', 'term2'});
      expect(terms.wildcardLevels, isEmpty);
    });

    test('wildcard-only', () {
      final terms = parseSlotTerms('*-1|*-2');
      expect(terms.concrete, isEmpty);
      expect(terms.wildcardLevels, {'1', '2'});
    });

    test('concrete-only', () {
      final terms = parseSlotTerms('a-1|b-2');
      expect(terms.concrete, {'a-1', 'b-2'});
      expect(terms.wildcardLevels, isEmpty);
    });

    test('*- alone (length 2) treated as concrete, not wildcard', () {
      final terms = parseSlotTerms('*-');
      // '*-' has length 2, not > 2, so treated as concrete
      expect(terms.concrete, {'*-'});
      expect(terms.wildcardLevels, isEmpty);
    });

    test('whitespace around wildcard level is trimmed', () {
      final terms = parseSlotTerms('*- 3 ');
      expect(terms.wildcardLevels, {'3'});
    });

    test('duplicate terms are deduplicated', () {
      final terms = parseSlotTerms('a-1|a-1|*-2|*-2');
      expect(terms.concrete, {'a-1'});
      expect(terms.wildcardLevels, {'2'});
    });
  });

  // ── filterBySlotGate ──────────────────────────────────────────────────

  group('filterBySlotGate', () {
    final docs = <Map<String, dynamic>>[
      {'ak': '83674161979544-1', 'cl': '1', 'n': 'Alice'},
      {'ak': '83674161979544-2', 'cl': '2', 'n': 'Bob'},
      {'ak': '83674161979544-3', 'cl': '3', 'n': 'Carol'},
      {'ak': '32639062303108-3', 'cl': '3', 'n': 'Dave'},
    ];

    test('both sets empty → empty result', () {
      final result = filterBySlotGate(
          docs, <String>{}, <String>{}, 'ak', 'cl');
      expect(result, isEmpty);
    });

    test('both sets empty → result is growable (sort must not throw)', () {
      final result = filterBySlotGate(
          docs, <String>{}, <String>{}, 'ak', 'cl');
      // This must not throw — callers .sort() the result.
      // const [] would throw: Unsupported operation: Cannot modify an
      // unmodifiable list (C1 regression guard).
      result.sort((a, b) => 0);
      expect(result, isEmpty);
    });

    test('concrete match only', () {
      final result = filterBySlotGate(
          docs, {'83674161979544-1', '83674161979544-2'}, <String>{}, 'ak', 'cl');
      expect(result.length, 2);
      expect(result[0]['n'], 'Alice');
      expect(result[1]['n'], 'Bob');
    });

    test('wildcard match only', () {
      final result = filterBySlotGate(
          docs, <String>{}, {'3'}, 'ak', 'cl');
      expect(result.length, 2);
      expect(result[0]['n'], 'Carol');
      expect(result[1]['n'], 'Dave');
    });

    test('mixed: concrete + wildcard union', () {
      final result = filterBySlotGate(
          docs, {'83674161979544-1'}, {'3'}, 'ak', 'cl');
      expect(result.length, 3);
      expect(result.map((d) => d['n']).toList(), ['Alice', 'Carol', 'Dave']);
    });

    test('no match → empty', () {
      final result = filterBySlotGate(
          docs, {'nonexistent-99'}, {'99'}, 'ak', 'cl');
      expect(result, isEmpty);
    });

    test('int vs String type tolerance for cl (D8)', () {
      final intDocs = <Map<String, dynamic>>[
        {'ak': '83674161979544-1', 'cl': 1, 'n': 'IntLevel'},
        {'ak': '83674161979544-2', 'cl': 2, 'n': 'IntLevel2'},
      ];
      // wildcardLevels contains '1' (String), doc has cl=1 (int)
      final result = filterBySlotGate(
          intDocs, <String>{}, {'1'}, 'ak', 'cl');
      expect(result.length, 1);
      expect(result[0]['n'], 'IntLevel');
    });

    test('int vs String type tolerance for ak (D8)', () {
      final intDocs = <Map<String, dynamic>>[
        {'ak': 12345, 'cl': '1', 'n': 'IntPointer'},
      ];
      final result = filterBySlotGate(
          intDocs, {'12345'}, <String>{}, 'ak', 'cl');
      expect(result.length, 1);
      expect(result[0]['n'], 'IntPointer');
    });

    test('doc missing pointer field entirely → no match', () {
      final noPtrDocs = <Map<String, dynamic>>[
        {'cl': '1', 'n': 'NoPointer'},
      ];
      final result = filterBySlotGate(
          noPtrDocs, {'something'}, <String>{}, 'ak', 'cl');
      expect(result, isEmpty);
    });

    test('doc missing level field → no wildcard match', () {
      final noLvlDocs = <Map<String, dynamic>>[
        {'ak': 'a-1', 'n': 'NoLevel'},
      ];
      final result = filterBySlotGate(
          noLvlDocs, <String>{}, {'1'}, 'ak', 'cl');
      expect(result, isEmpty);
    });

    test('empty docs list → empty result', () {
      final result = filterBySlotGate(
          const [], {'a-1'}, {'1'}, 'ak', 'cl');
      expect(result, isEmpty);
    });
  });

  // ── Union across multiple grant docs (integration-level) ──────────────

  group('union across grant docs', () {
    test('D6: union + dedup across 2 grant docs', () {
      final grantDocs = <Map<String, dynamic>>[
        {'sc': '83674161979544-1|83674161979544-2|32639062303108-3'},
        {'sc': '83674161979544-2|*-1'},
      ];

      final Set<String> allConcrete = {};
      final Set<String> allWildcard = {};
      for (final g in grantDocs) {
        final terms = parseSlotTerms((g['sc'] ?? '').toString());
        allConcrete.addAll(terms.concrete);
        allWildcard.addAll(terms.wildcardLevels);
      }

      // 83674161979544-2 appears in both docs but Set deduplicates
      expect(allConcrete,
          {'83674161979544-1', '83674161979544-2', '32639062303108-3'});
      expect(allWildcard, {'1'});

      final requestDocs = <Map<String, dynamic>>[
        {'ak': '83674161979544-1', 'cl': '1', 'n': 'Alice'},
        {'ak': '83674161979544-2', 'cl': '2', 'n': 'Bob'},
        {'ak': '83674161979544-3', 'cl': '3', 'n': 'Carol'},
        {'ak': '99999999999999-1', 'cl': '1', 'n': 'Dave'},
      ];

      final result = filterBySlotGate(
          requestDocs, allConcrete, allWildcard, 'ak', 'cl');
      // Alice: ak '83674161979544-1' in concrete
      // Bob: ak '83674161979544-2' in concrete
      // Carol: ak '83674161979544-3' NOT in concrete, cl '3' NOT in wildcard {'1'}
      // Dave: ak '99999999999999-1' NOT in concrete, cl '1' in wildcard {'1'}
      expect(result.length, 3);
      expect(result.map((d) => d['n']).toList(), ['Alice', 'Bob', 'Dave']);
    });
  });

  // ── Spec acceptance fixture (VTL live data) ───────────────────────────

  group('spec acceptance (VTL live data)', () {
    // Agenia: sc = 83674161979544-1|83674161979544-2|32639062303108-3
    // Marita: sc = *-1
    // Surya:  sc = 83674161979544-3
    // Dirgahayu: sc = 83674161979544-1|83674161979544-3

    test('cl=1 → Agenia (PG-1), Dirgahayu (PG-1), Marita (*-1)', () {
      final request = <Map<String, dynamic>>[
        {'ak': '83674161979544-1', 'cl': '1', 'st': 'pending'},
      ];

      // Agenia's slots
      final aTerms = parseSlotTerms(
          '83674161979544-1|83674161979544-2|32639062303108-3');
      final aResult = filterBySlotGate(
          request, aTerms.concrete, aTerms.wildcardLevels, 'ak', 'cl');
      expect(aResult.length, 1, reason: 'Agenia sees PG-1 (concrete match)');

      // Marita's slots (wildcard)
      final mTerms = parseSlotTerms('*-1');
      final mResult = filterBySlotGate(
          request, mTerms.concrete, mTerms.wildcardLevels, 'ak', 'cl');
      expect(mResult.length, 1, reason: 'Marita sees level 1 (wildcard)');

      // Dirgahayu's slots
      final dTerms = parseSlotTerms('83674161979544-1|83674161979544-3');
      final dResult = filterBySlotGate(
          request, dTerms.concrete, dTerms.wildcardLevels, 'ak', 'cl');
      expect(dResult.length, 1, reason: 'Dirgahayu sees PG-1 (concrete)');
    });

    test('cl=3 → HIDDEN from Agenia (KP-3 ≠ PG-3), visible to Surya', () {
      final request = <Map<String, dynamic>>[
        {'ak': '83674161979544-3', 'cl': '3', 'st': 'pending'},
      ];

      // Agenia: has 32639062303108-3 (KP-3), NOT 83674161979544-3 (PG-3)
      final aTerms = parseSlotTerms(
          '83674161979544-1|83674161979544-2|32639062303108-3');
      final aResult = filterBySlotGate(
          request, aTerms.concrete, aTerms.wildcardLevels, 'ak', 'cl');
      expect(aResult, isEmpty,
          reason: 'Agenia does NOT see PG-3 (she has KP-3)');

      // Surya: has 83674161979544-3 (PG-3)
      final sTerms = parseSlotTerms('83674161979544-3');
      final sResult = filterBySlotGate(
          request, sTerms.concrete, sTerms.wildcardLevels, 'ak', 'cl');
      expect(sResult.length, 1, reason: 'Surya sees PG-3 (concrete match)');

      // Dirgahayu: PG-1|PG-3 — the multi-slot approver. Field report
      // 2026-07-29 claimed she does NOT see this card while Agenia does,
      // i.e. the gate reading as the inverse of `ak ∈ sc`. Both halves are
      // pinned here so any real inversion fails the suite.
      final dTerms = parseSlotTerms('83674161979544-1|83674161979544-3');
      final dResult = filterBySlotGate(
          request, dTerms.concrete, dTerms.wildcardLevels, 'ak', 'cl');
      expect(dResult.length, 1,
          reason: 'Dirgahayu sees PG-3 — holding PG-1 too must not mask it');
      // The result feeds .sort() in both _getServerFiltered paths.
      dResult.sort((a, b) => 0);
    });

    test('approver with no grant doc → empty list (D5)', () {
      // Simulated: matchedGrants is empty after gateSearch filter.
      // The widget code returns <Map<String, dynamic>>[] in this case.
      // We verify filterBySlotGate with empty sets returns empty AND is
      // growable (callers .sort() it).
      final request = <Map<String, dynamic>>[
        {'ak': '83674161979544-1', 'cl': '1', 'st': 'pending'},
      ];
      final result = filterBySlotGate(
          request, <String>{}, <String>{}, 'ak', 'cl');
      expect(result, isEmpty);
      // C1 regression guard: must survive .sort()
      result.sort((a, b) => 0);
    });
  });

  // ── Gating-OFF back-compat (D4) ──────────────────────────────────────

  group('gating-OFF back-compat (D4)', () {
    test('gateSlot with only slotField (no pointer/level) → isEmpty true', () {
      final cfg = parseGateSlot('sc');
      expect(cfg.isEmpty, isTrue,
          reason: 'Both pointerField and levelField empty → gating OFF');
    });

    test('gateSlot with slotField + pointerField → isEmpty false', () {
      final cfg = parseGateSlot('sc\u{25C6}ak');
      expect(cfg.isEmpty, isFalse,
          reason: 'pointerField present → concrete-only gating is valid');
    });

    test('full gateSlot → isEmpty false', () {
      final cfg = parseGateSlot('sc\u{25C6}ak\u{25C6}cl');
      expect(cfg.isEmpty, isFalse);
    });
  });

  // ── isVisibleBySlotGate ─────────────────────────────────────────────────

  group('isVisibleBySlotGate', () {
    test('both sets empty → false (fail-closed)', () {
      expect(isVisibleBySlotGate('83674161979544-1', '1', {}, {}), isFalse);
    });

    test('concrete match → true', () {
      expect(
        isVisibleBySlotGate(
            '83674161979544-1', '1', {'83674161979544-1'}, {}),
        isTrue,
      );
    });

    test('wildcard match → true', () {
      expect(
        isVisibleBySlotGate('83674161979544-1', '1', {}, {'1'}),
        isTrue,
      );
    });

    test('concrete + wildcard both match → true', () {
      expect(
        isVisibleBySlotGate(
            '83674161979544-1', '1', {'83674161979544-1'}, {'1'}),
        isTrue,
      );
    });

    test('no match → false', () {
      expect(
        isVisibleBySlotGate(
            '83674161979544-3', '3', {'83674161979544-1'}, {'1'}),
        isFalse,
      );
    });

    test('empty pointer, empty level → false', () {
      expect(
        isVisibleBySlotGate(
            '', '', {'83674161979544-1'}, {'1'}),
        isFalse,
      );
    });

    test('empty pointer, valid level match → true', () {
      expect(
        isVisibleBySlotGate('', '1', {}, {'1'}),
        isTrue,
      );
    });

    test('valid pointer match, empty level → true', () {
      expect(
        isVisibleBySlotGate(
            '83674161979544-1', '', {'83674161979544-1'}, {}),
        isTrue,
      );
    });

    test('spec fixture: Agenia at L3 (KP-3 not PG-3) → false', () {
      // Agenia holds 83674161979544-1, 83674161979544-2, 32639062303108-3
      final aTerms = parseSlotTerms(
          '83674161979544-1|83674161979544-2|32639062303108-3');
      expect(
        isVisibleBySlotGate(
            '83674161979544-3', '3',
            aTerms.concrete, aTerms.wildcardLevels),
        isFalse,
        reason: 'Agenia has KP-3, not PG-3 — buttons hidden',
      );
    });

    test('spec fixture: Dirgahayu at L3 (PG-3) → true', () {
      final dTerms = parseSlotTerms('83674161979544-1|83674161979544-3');
      expect(
        isVisibleBySlotGate(
            '83674161979544-3', '3',
            dTerms.concrete, dTerms.wildcardLevels),
        isTrue,
        reason: 'Dirgahayu has PG-3 — buttons visible',
      );
    });

    test('spec fixture: Marita wildcard *-1 at L1 → true', () {
      final mTerms = parseSlotTerms('*-1');
      expect(
        isVisibleBySlotGate(
            '83674161979544-1', '1',
            mTerms.concrete, mTerms.wildcardLevels),
        isTrue,
        reason: 'Marita has *-1 wildcard — buttons visible for any L1',
      );
    });

    test('spec fixture: empty row (direct nav / pre-publish) → false', () {
      // Simulates direct navigation or pre-publish state where currentRow is []
      final dTerms = parseSlotTerms('83674161979544-1|83674161979544-3');
      expect(
        isVisibleBySlotGate('', '', dTerms.concrete, dTerms.wildcardLevels),
        isFalse,
        reason: 'Empty row (direct nav / pre-publish) — fail-closed',
      );
    });

    test('spec fixture: out-of-range index yields empty string → false', () {
      // When currentRow is shorter than the configured index, the caller
      // passes '' — isVisibleBySlotGate sees empty pointer + empty level.
      final dTerms = parseSlotTerms('83674161979544-1|83674161979544-3');
      expect(
        isVisibleBySlotGate('', '', dTerms.concrete, dTerms.wildcardLevels),
        isFalse,
        reason: 'Out-of-range index → empty values → fail-closed',
      );
    });
  });

  // ── filterBySlotGate delegation to isVisibleBySlotGate ────────────────

  group('filterBySlotGate delegates to isVisibleBySlotGate', () {
    test('results match isVisibleBySlotGate per row', () {
      final docs = [
        {'ak': '83674161979544-1', 'cl': '1'},
        {'ak': '83674161979544-3', 'cl': '3'},
        {'ak': '83674161979544-2', 'cl': '2'},
      ];
      final concrete = {'83674161979544-1'};
      final wildcardLevels = <String>{};
      final filtered =
          filterBySlotGate(docs, concrete, wildcardLevels, 'ak', 'cl');
      // Only the first doc matches
      expect(filtered.length, 1);
      expect(filtered[0]['ak'], '83674161979544-1');
      // Verify against isVisibleBySlotGate directly
      for (final doc in docs) {
        final pointer = doc['ak']!;
        final level = doc['cl']!;
        final expected =
            isVisibleBySlotGate(pointer, level, concrete, wildcardLevels);
        expect(filtered.contains(doc), expected);
      }
    });
  });
}
