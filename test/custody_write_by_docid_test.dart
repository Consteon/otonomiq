import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── P6 doc-id extraction from pickActiveOpening result ─────────────────

  group('P6 doc-id extraction for write targeting', () {
    /// Pure mirror of the doc-pick logic added to _onTapP6:
    /// given a list of matched docs, pick via pickActiveOpening,
    /// then extract __docId. Returns empty string when no doc or no id.
    String pickDocId(List<Map<String, dynamic>> matched) {
      if (matched.isEmpty) return '';
      final Map<String, dynamic>? picked = pickActiveOpening(matched);
      final Map<String, dynamic> doc = picked ?? matched.first;
      return (doc['__docId'] ?? '').toString().trim();
    }

    test('single active opening -> returns its __docId', () {
      final docs = [
        {
          'cty': 'opening',
          'cst': 'awaiting_custody',
          't': 100,
          '__docId': 'B4ktZ4ZjurMjaXsEI8a0',
        },
      ];
      expect(pickDocId(docs), 'B4ktZ4ZjurMjaXsEI8a0');
    });

    test('two openings same day: closed + active -> picks active docId', () {
      final docs = [
        {
          'cty': 'opening',
          'cst': 'closed',
          't': 100,
          '__docId': 'ZbjH1nJw1UWzD4WAFcsa',
        },
        {
          'cty': 'opening',
          'cst': 'awaiting_custody',
          't': 200,
          '__docId': 'B4ktZ4ZjurMjaXsEI8a0',
        },
      ];
      expect(pickDocId(docs), 'B4ktZ4ZjurMjaXsEI8a0');
    });

    test('all openings closed -> returns newest overall docId', () {
      final docs = [
        {
          'cty': 'opening',
          'cst': 'closed',
          't': 100,
          '__docId': 'OLD',
        },
        {
          'cty': 'opening',
          'cst': 'closed',
          't': 300,
          '__docId': 'NEWEST',
        },
        {
          'cty': 'opening',
          'cst': 'closed',
          't': 200,
          '__docId': 'MID',
        },
      ];
      // pickActiveOpening returns newest closed; write follows read
      expect(pickDocId(docs), 'NEWEST');
    });

    test('no opening-shaped docs -> falls back to matched.first __docId', () {
      // Non-vehicle_check table; pickActiveOpening returns null
      final docs = [
        {
          'cty': 'task',
          'cst': '',
          't': 100,
          '__docId': 'TASK_DOC',
        },
      ];
      // pickActiveOpening returns null -> matched.first
      expect(pickDocId(docs), 'TASK_DOC');
    });

    test('doc missing __docId -> empty string (triggers search fallback)', () {
      final docs = [
        {
          'cty': 'opening',
          'cst': 'awaiting_custody',
          't': 100,
          // no __docId key
        },
      ];
      expect(pickDocId(docs), '');
    });

    test('empty matched list -> empty string (triggers search fallback)', () {
      expect(pickDocId([]), '');
    });

    test('three openings: 2 closed + 1 active -> picks the active', () {
      final docs = [
        {
          'cty': 'opening',
          'cst': 'closed',
          't': 100,
          '__docId': 'TRIP1',
        },
        {
          'cty': 'opening',
          'cst': 'closed',
          't': 200,
          '__docId': 'TRIP2',
        },
        {
          'cty': 'opening',
          'cst': 'awaiting_custody',
          't': 300,
          '__docId': 'TRIP3',
        },
      ];
      expect(pickDocId(docs), 'TRIP3');
    });
  });

  // ── P7 doc-id extraction (custody_reveal reuses _findCheckDoc) ─────────

  group('P7 doc-id extraction from _findCheckDoc result', () {
    /// Pure mirror: given the doc returned by _findCheckDoc (nullable),
    /// extract __docId. Returns empty string when null or no id.
    String docIdFromCheckDoc(Map<String, dynamic>? doc) {
      if (doc == null) return '';
      return (doc['__docId'] ?? '').toString().trim();
    }

    test('non-null doc with __docId -> returns id', () {
      expect(
        docIdFromCheckDoc({
          'cty': 'opening',
          'cst': 'awaiting_custody',
          '__docId': 'ABC123',
        }),
        'ABC123',
      );
    });

    test('non-null doc without __docId -> empty', () {
      expect(
        docIdFromCheckDoc({'cty': 'opening', 'cst': 'awaiting_custody'}),
        '',
      );
    });

    test('null doc -> empty', () {
      expect(docIdFromCheckDoc(null), '');
    });
  });
}
