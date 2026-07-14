import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/table_picker.dart';
import 'package:otonomiq/widget/picker_list.dart'; // PickerList.filterRows reuse (W2)

void main() {
  // ── resolveValueFromDoc ────────────────────────────────────────────────
  group('TablePicker.resolveValueFromDoc', () {
    test('empty valueField returns __docId', () {
      final doc = {'__docId': 'DOC123', 'n': 'Alice', 'mv': 'V1'};
      expect(TablePicker.resolveValueFromDoc(doc, ''), 'DOC123');
    });

    test('explicit valueField returns that field', () {
      final doc = {'__docId': 'DOC123', 'n': 'Alice', 'mv': 'V1'};
      expect(TablePicker.resolveValueFromDoc(doc, 'mv'), 'V1');
    });

    test('missing valueField returns empty string', () {
      final doc = {'__docId': 'DOC123', 'n': 'Alice'};
      expect(TablePicker.resolveValueFromDoc(doc, 'mv'), '');
    });

    test('missing __docId returns empty string when valueField empty', () {
      final doc = {'n': 'Alice'};
      expect(TablePicker.resolveValueFromDoc(doc, ''), '');
    });
  });

  // ── encodeSelection ────────────────────────────────────────────────────
  group('TablePicker.encodeSelection', () {
    test('single mode returns bare string', () {
      final result = TablePicker.encodeSelection(['V1'], isSingle: true);
      expect(result, 'V1');
    });

    test('single mode with empty list returns empty string', () {
      final result = TablePicker.encodeSelection([], isSingle: true);
      expect(result, '');
    });

    test('multi mode returns JSON-array string', () {
      final result =
          TablePicker.encodeSelection(['V1', 'V2'], isSingle: false);
      expect(result, jsonEncode(['V1', 'V2']));
    });

    test('multi mode with one item still returns JSON-array', () {
      final result = TablePicker.encodeSelection(['V1'], isSingle: false);
      expect(result, jsonEncode(['V1']));
    });

    test('multi mode with empty list returns empty JSON-array', () {
      final result = TablePicker.encodeSelection([], isSingle: false);
      expect(result, jsonEncode([]));
    });
  });

  // ── decodeSelection (re-open: parse stored value back to list) ─────────
  group('TablePicker.decodeSelection', () {
    test('bare string (single) returns one-element list', () {
      expect(TablePicker.decodeSelection('V1', isSingle: true), ['V1']);
    });

    test('empty string (single) returns empty list', () {
      expect(TablePicker.decodeSelection('', isSingle: true), isEmpty);
    });

    test('JSON-array string (multi) returns parsed list', () {
      expect(
        TablePicker.decodeSelection(jsonEncode(['V1', 'V2']), isSingle: false),
        ['V1', 'V2'],
      );
    });

    test('empty JSON-array string (multi) returns empty list', () {
      expect(
        TablePicker.decodeSelection(jsonEncode([]), isSingle: false),
        isEmpty,
      );
    });

    test('malformed JSON (multi) returns empty list (no crash)', () {
      expect(
        TablePicker.decodeSelection('not json', isSingle: false),
        isEmpty,
      );
    });

    test('emptyString sentinel (--) returns empty list', () {
      expect(TablePicker.decodeSelection('--', isSingle: true), isEmpty);
      expect(TablePicker.decodeSelection('--', isSingle: false), isEmpty);
    });
  });

  // ── textSegment length-guard ───────────────────────────────────────────
  group('TablePicker.textSegment', () {
    test('full 6-segment array returns each segment', () {
      final arr = [
        'Pilih Model',
        'Cari nama',
        'Kosong',
        'OK',
        'Batal',
        '{n} dipilih'
      ];
      expect(TablePicker.textSegment(arr, 0, 'def'), 'Pilih Model');
      expect(TablePicker.textSegment(arr, 5, 'def'), '{n} dipilih');
    });

    test('short array (2 segments) returns default for index >= 2', () {
      final arr = ['Title', 'Search'];
      expect(TablePicker.textSegment(arr, 0, 'def'), 'Title');
      expect(TablePicker.textSegment(arr, 1, 'def'), 'Search');
      expect(TablePicker.textSegment(arr, 2, 'fallback'), 'fallback');
      expect(TablePicker.textSegment(arr, 5, 'x'), 'x');
    });

    test('empty array returns default for all indexes', () {
      expect(TablePicker.textSegment([], 0, 'fb'), 'fb');
    });
  });

  // ── max enforcement ────────────────────────────────────────────────────
  group('TablePicker.canAddMore', () {
    test('max 0 (unlimited) always allows', () {
      expect(TablePicker.canAddMore(currentCount: 99, max: 0), true);
    });

    test('max 3, current 2 allows', () {
      expect(TablePicker.canAddMore(currentCount: 2, max: 3), true);
    });

    test('max 3, current 3 disallows', () {
      expect(TablePicker.canAddMore(currentCount: 3, max: 3), false);
    });

    test('max 1 (single), current 1 disallows', () {
      expect(TablePicker.canAddMore(currentCount: 1, max: 1), false);
    });

    test('max 1 (single), current 0 allows', () {
      expect(TablePicker.canAddMore(currentCount: 0, max: 1), true);
    });
  });

  // ── clientSearch (text filter on rows) ─────────────────────────────────
  group('TablePicker.clientSearch', () {
    final rows = [
      {'n': 'Alice Wonderland', 'ps': 'model'},
      {'n': 'Bob Builder', 'ps': 'crew'},
      {'n': 'Charlie Brown', 'ps': 'model'},
    ];

    test('empty query returns all', () {
      expect(TablePicker.clientSearch(rows, '', 'n', 'ps').length, 3);
    });

    test('matches labelField case-insensitive', () {
      final r = TablePicker.clientSearch(rows, 'alice', 'n', 'ps');
      expect(r.length, 1);
      expect(r[0]['n'], 'Alice Wonderland');
    });

    test('matches subField', () {
      final r = TablePicker.clientSearch(rows, 'crew', 'n', 'ps');
      expect(r.length, 1);
      expect(r[0]['n'], 'Bob Builder');
    });

    test('partial match works', () {
      final r = TablePicker.clientSearch(rows, 'li', 'n', 'ps');
      // 'Ali' matches Alice, 'li' matches Charlie
      expect(r.length, 2);
    });

    test('no match returns empty', () {
      expect(TablePicker.clientSearch(rows, 'zzz', 'n', 'ps'), isEmpty);
    });
  });

  // ── server-encoded search DSL (reuses PickerList.filterRows) ───────────
  // TABLE_PICKER passes component['search'] straight to PickerList.filterRows,
  // which autheniumDecodes (◼ = _25FC_, ⭘ = _u2B58_) before gating. These
  // assert the encoded search a TABLE_PICKER may carry actually filters rows.
  group('filterRows with server-encoded search', () {
    final rows = [
      {'n': 'Alice', 'ps': 'model', 'st': 'active'},
      {'n': 'Bob', 'ps': 'crew', 'st': 'active'},
      {'n': 'Carol', 'ps': 'model', 'st': 'idle'},
    ];

    test('_25FC_ (◼) single-clause encoded search filters by ps', () {
      final r = PickerList.filterRows(rows, 'ps_25FC_model');
      expect(r.map((d) => d['n']).toList(), ['Alice', 'Carol']);
    });

    test('_25FC_/_u2B58_ (◼/⭘) AND-gate encoded search narrows further', () {
      final r =
          PickerList.filterRows(rows, 'ps_25FC_model_u2B58_st_25FC_active');
      expect(r.length, 1);
      expect(r.single['n'], 'Alice');
    });
  });
}
