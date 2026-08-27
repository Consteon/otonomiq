import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/otq_txf_2.dart';

// A reference-table row (#TABLE<code> / #LQR_LIST) arrives from the server as a
// List<dynamic>; a cell the tenant left blank is a real Dart null. The old code
// wrote `elementArray[index].toString()` straight into InputController.finalData,
// and Null.toString() is the four-character string "null" - which sails through
// stringCleanUp (not a forbidden character) into the ★ section of Event C, where
// the report renders the word "null" to the user.
//
// txfCellText is the null-safe conversion, applied at the PRODUCER. Filtering the
// text "null" at the sink (stringCleanUp / saveSendRows) is forbidden: a user may
// legitimately type it.
//
// atiJoinRow is the row-level twin: it joins a whole reference-table row into the
// ati-coded, ☆-separated bundle written to `mainRef`'s finalData. Its separator is
// INDEX-driven. The inline form it replaced chose the separator by content
// (`if (contentResult != atiCode)`), which meant that routing cells through
// txfCellText alone would have turned a visible "null" into a SILENT column
// misalignment: an empty first cell left `contentResult == atiCode`, the second
// separator was never emitted, and every following field shifted one position left
// in the downstream ☆-split. That trap is what the `leading null` / `leading empty`
// tests below exist to catch.
//
// Mutation checks (each was run, observed RED, and reverted):
//   * txfCellText body -> `v.toString()`          => group 1 test 1 goes RED.
//   * atiJoinRow separator -> `if (result != atiCode) { result += separator[6]; }`
//                                                  => group 2 leading-null,
//                                                     leading-empty and all-null
//                                                     arity tests go RED.
//
// NOTE ON COVERAGE: these tests pin the two helpers only. The call sites inside
// otq_txf_2.dart's widget/setState bodies cannot be reached from flutter_test
// without a Firebase-bound widget pump, so the wiring is guarded by grep instead.
// Counts below are the CURRENT decomposition - recompute them if you add a site:
//
//   grep -c "txfCellText" lib/widget/otq_txf_2.dart   -> 11
//       1 definition (`String txfCellText(...)`)
//     + 2 comment mentions (`// end of txfCellText`, and one dartdoc reference
//       inside atiJoinRow's doc block)
//     + 8 call sites: 7 in widget bodies (A1, A2, B, C1, C2, D1, D2) and 1 inside
//       atiJoinRow - that last one IS covered by the tests below.
//     Executable-only cross-check:
//       grep "txfCellText" lib/widget/otq_txf_2.dart | grep -vc "^ *//"   -> 9
//
//   grep -c "atiJoinRow" lib/widget/otq_txf_2.dart    -> 4
//       1 definition + 2 call sites (the tableSearchFound branch and the QR
//       branch) + 1 comment mention (`} // end of atiJoinRow`).

void main() {
  final String sep = separator[6]; // ☆ - intra-section separator

  int separatorCount(String s) => s.split(sep).length - 1;

  group('txfCellText', () {
    test('null becomes an empty string, never the literal "null"', () {
      expect(txfCellText(null), '');
      expect(txfCellText(null), isNot('null'));
    });

    test('a user who literally typed "null" keeps their text', () {
      expect(txfCellText('null'), 'null');
    });

    test('non-string cells keep their toString form', () {
      expect(txfCellText(1786665600000), '1786665600000');
      expect(txfCellText(12.5), '12.5');
      expect(txfCellText(true), 'true');
      expect(txfCellText('Ada'), 'Ada');
    });

    test('empty cell stays empty - slot reserved, content empty', () {
      expect(txfCellText(''), '');
    });
  });

  group('atiJoinRow - arity is structural, not content-driven', () {
    test('the bundle always starts with atiCode', () {
      expect(atiJoinRow(<dynamic>[]), atiCode);
      expect(atiJoinRow(<dynamic>['Ada']), startsWith(atiCode));
      expect(atiJoinRow(<dynamic>[null, null]), startsWith(atiCode));
    });

    test('N cells produce exactly N-1 separators (N = 1, 2, 3)', () {
      // RED mutation: any change that makes the separator conditional on the
      // accumulated text instead of on the index.
      expect(separatorCount(atiJoinRow(<dynamic>['a'])), 0);
      expect(separatorCount(atiJoinRow(<dynamic>['a', 'b'])), 1);
      expect(separatorCount(atiJoinRow(<dynamic>['a', 'b', 'c'])), 2);
      expect(atiJoinRow(<dynamic>['a', 'b', 'c']), '${atiCode}a${sep}b${sep}c');
    });

    test('a LEADING null cell still yields the full separator count', () {
      // THE TRAP. Content-driven separators + txfCellText => the first cell
      // renders '', contentResult stays == atiCode, and the second separator is
      // never emitted: every following field shifts one position left in the
      // downstream ☆-split and the report columns misalign silently.
      // RED mutation: restore `if (result != atiCode) { result += separator[6]; }`
      // -> observed 1 separator instead of 2.
      final String r = atiJoinRow(<dynamic>[null, 'Ada', '1786665600000']);
      expect(separatorCount(r), 2);
      expect(r, '$atiCode${sep}Ada${sep}1786665600000');
      expect(r.contains('null'), isFalse);
    });

    test('a LEADING empty-string cell likewise (pre-existing collapse)', () {
      // Same defect, reachable before this change too: an empty first cell
      // suppressed the next separator.
      final String r = atiJoinRow(<dynamic>['', 'Ada', 'Tidak']);
      expect(separatorCount(r), 2);
      expect(r, '$atiCode${sep}Ada${sep}Tidak');
    });

    test('an all-null row keeps its arity and emits no "null" text', () {
      final String r = atiJoinRow(<dynamic>[null, null, null]);
      expect(separatorCount(r), 2);
      expect(r, '$atiCode$sep$sep');
      expect(r.contains('null'), isFalse);
    });

    test('a null in the MIDDLE reserves its slot, empty', () {
      final String r = atiJoinRow(<dynamic>['Ada', null, 'Tidak']);
      expect(separatorCount(r), 2);
      expect(r, '${atiCode}Ada$sep${sep}Tidak');
      expect(r.contains('null'), isFalse);
    });

    test('a cell whose toString() throws does not abort the row', () {
      // The inline form wrapped each cell in try/catch; the helper keeps it.
      // RED mutation: remove the try/catch -> this test throws instead of failing.
      final String r = atiJoinRow(<dynamic>['a', _ThrowingCell(), 'c']);
      expect(separatorCount(r), 2);
      expect(r, '${atiCode}a$sep${sep}c');
    });

    test('non-string cells keep their toString form inside the bundle', () {
      final String r = atiJoinRow(<dynamic>[1786665600000, 12.5, true]);
      expect(r, '${atiCode}1786665600000${sep}12.5${sep}true');
    });
  });
}

class _ThrowingCell {
  @override
  String toString() => throw StateError('cell toString blew up');
}
