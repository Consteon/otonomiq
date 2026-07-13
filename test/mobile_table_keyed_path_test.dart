import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/states/mobile_table_controller.dart';

// Regression: submitting a keyed-subcollection write (report-incident) wedged
// historySync with "Invalid document reference ... has 5 segments". Root cause:
// getDocumentName's `//` folder form returns `<docId>/<subColl>` (single slash);
// addContent then called `.doc('<docId>/<subColl>')` → a 5-segment (odd) doc
// path. splitKeyedTableName recovers a slash-free docId so `.doc(docId)` is a
// valid 4-segment table-def ref and rows land in the 5-segment subcollection.
void main() {
  group('splitKeyedTableName', () {
    test('plain name → default content subcollection, unchanged', () {
      final (docId, sub) = splitKeyedTableName('report-incident', 'content');
      expect(docId, 'report-incident');
      expect(sub, 'content');
    });

    test('keyed name → (docId, subColl) split on the single slash', () {
      final (docId, sub) =
          splitKeyedTableName('84214220504259/report-incident', 'content');
      expect(docId, '84214220504259');
      expect(sub, 'report-incident');
    });

    test('docId never carries a slash → .doc(docId) stays a 4-segment ref', () {
      // Feed the actual getDocumentName output for the `//` form. The old code
      // passed this whole string to .doc() and crashed at 5 segments.
      for (final name in ['report-incident', 'history']) {
        final keyed = getDocumentName('84214220504259//$name');
        expect(keyed, '84214220504259/$name'); // getDocumentName joins w/ '/'
        final (docId, sub) = splitKeyedTableName(keyed, 'content');
        expect(docId.contains('/'), isFalse); // .doc(docId) → 4 segments, valid
        expect(sub, name); // rows → .../tables/<docId>/<name> (5-seg coll)
      }
    });

    test('multi-level keyed name → single-segment docId, leaf subcoll', () {
      // Regression for "A collection path must point to a valid collection".
      // Input `$test/report-incident//vtl.report-incident-history`: the doc part
      // itself carries a slash. First-slash split put `report-incident/...` in
      // the subcoll → 6-segment (even) `.collection()` → invalid. Boundary is the
      // LAST slash; the doc part collapses to one '%'-joined segment.
      final keyed =
          getDocumentName(r'$test/report-incident//vtl.report-incident-history');
      expect(keyed, r'$test/report-incident/vtl.report-incident-history');
      final (docId, sub) = splitKeyedTableName(keyed, 'content');
      expect(docId, r'$test%report-incident'); // one valid doc segment
      expect(docId.contains('/'), isFalse); // .doc(docId) → 4-segment ref
      expect(sub, 'vtl.report-incident-history'); // 5-segment content coll
    });
  });
}
