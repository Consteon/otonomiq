import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── parseBuckets ──────────────────────────────────────────────────────────

  group('parseBuckets', () {
    test('parses standard 2-bucket string', () {
      // After autheniumDecode, the raw string has literal ◼ and ⭘.
      final buckets = parseBuckets('isi\u{25FC}ok\u{2B58}kosong\u{25FC}warn');
      expect(buckets.length, 2);
      expect(buckets[0].label, 'isi');
      expect(buckets[0].status, 'ok');
      expect(buckets[1].label, 'kosong');
      expect(buckets[1].status, 'warn');
    });

    test('null or empty returns empty list', () {
      expect(parseBuckets(null), isEmpty);
      expect(parseBuckets(''), isEmpty);
      expect(parseBuckets('   '), isEmpty);
    });

    test('malformed entry (no separator) is skipped', () {
      final buckets =
          parseBuckets('good\u{25FC}ok\u{2B58}bad_entry\u{2B58}also\u{25FC}warn');
      expect(buckets.length, 2);
      expect(buckets[0].label, 'good');
      expect(buckets[1].label, 'also');
    });

    test('empty label is skipped', () {
      final buckets = parseBuckets('\u{25FC}ok\u{2B58}real\u{25FC}warn');
      expect(buckets.length, 1);
      expect(buckets[0].label, 'real');
    });

    test('empty status defaults to ok', () {
      final buckets = parseBuckets('thing\u{25FC}');
      expect(buckets.length, 1);
      expect(buckets[0].status, 'ok');
    });

    test('single bucket without AND separator', () {
      final buckets = parseBuckets('only\u{25FC}warn');
      expect(buckets.length, 1);
      expect(buckets[0].label, 'only');
      expect(buckets[0].status, 'warn');
    });
  });

  // ── stopStatusOf ──────────────────────────────────────────────────────────

  group('stopStatusOf', () {
    test('done returns done', () {
      expect(stopStatusOf({'tst': 'done'}), 'done');
    });

    test('failed returns failed', () {
      expect(stopStatusOf({'tst': 'failed'}), 'failed');
    });

    test('active returns active', () {
      expect(stopStatusOf({'tst': 'active'}), 'active');
    });

    test('absent tst returns pending', () {
      expect(stopStatusOf({}), 'pending');
    });

    test('empty string returns pending', () {
      expect(stopStatusOf({'tst': ''}), 'pending');
    });

    test('unknown value returns pending', () {
      expect(stopStatusOf({'tst': 'scheduled'}), 'pending');
    });

    test('case insensitive', () {
      expect(stopStatusOf({'tst': 'DONE'}), 'done');
      expect(stopStatusOf({'tst': 'Failed'}), 'failed');
      expect(stopStatusOf({'tst': 'Active'}), 'active');
    });

    test('custom tstField', () {
      expect(stopStatusOf({'status': 'done'}, tstField: 'status'), 'done');
    });

    // --- Spec vocab (section 4) ---

    test('closed (spec vocab) returns done', () {
      expect(stopStatusOf({'tst': 'closed'}), 'done');
    });

    test('ongoing (spec vocab) returns active', () {
      expect(stopStatusOf({'tst': 'ongoing'}), 'active');
    });

    test('assigned (spec vocab) returns pending', () {
      expect(stopStatusOf({'tst': 'assigned'}), 'pending');
    });

    test('closed case insensitive', () {
      expect(stopStatusOf({'tst': 'CLOSED'}), 'done');
      expect(stopStatusOf({'tst': 'Closed'}), 'done');
    });

    test('ongoing case insensitive', () {
      expect(stopStatusOf({'tst': 'ONGOING'}), 'active');
      expect(stopStatusOf({'tst': 'Ongoing'}), 'active');
    });

    test('backward compat: done still returns done', () {
      // Ensures old data with tst='done' still works after adding 'closed'.
      expect(stopStatusOf({'tst': 'done'}), 'done');
    });

    test('backward compat: active still returns active', () {
      // Ensures old data with tst='active' still works after adding 'ongoing'.
      expect(stopStatusOf({'tst': 'active'}), 'active');
    });

    // --- P10 alias (Task 0): completed -> done ---

    test('completed returns done', () {
      expect(stopStatusOf({'tst': 'completed'}), 'done');
    });

    test('COMPLETED (uppercase) returns done', () {
      expect(stopStatusOf({'tst': 'COMPLETED'}), 'done');
    });
  });

  // ── isStopClosed ──────────────────────────────────────────────────────────

  group('isStopClosed', () {
    test('done is closed', () {
      expect(isStopClosed('done'), isTrue);
    });

    test('failed is closed', () {
      expect(isStopClosed('failed'), isTrue);
    });

    test('active is not closed', () {
      expect(isStopClosed('active'), isFalse);
    });

    test('pending is not closed', () {
      expect(isStopClosed('pending'), isFalse);
    });

    test('empty is not closed', () {
      expect(isStopClosed(''), isFalse);
    });

    // --- Spec vocab via normalization path ---
    // isStopClosed checks the RAW string against _closedStatuses {'done','failed'}.
    // 'closed' (raw) is NOT in the set, but in the widget it goes through
    // stopStatusOf first (which normalizes to 'done'). These tests verify the
    // direct isStopClosed behavior for documentation.

    test('closed (raw) is NOT directly in _closedStatuses', () {
      // This is correct: the widget normalizes via stopStatusOf before checking.
      expect(isStopClosed('closed'), isFalse);
    });

    test('ongoing (raw) is not closed', () {
      expect(isStopClosed('ongoing'), isFalse);
    });

    test('assigned (raw) is not closed', () {
      expect(isStopClosed('assigned'), isFalse);
    });
  });

  // ── computeStopProgress ───────────────────────────────────────────────────

  group('computeStopProgress', () {
    test('empty docs -> total 0, closed 0, allClosed false, nextStop null', () {
      final p = computeStopProgress([]);
      expect(p.total, 0);
      expect(p.closed, 0);
      expect(p.allClosed, isFalse);
      expect(p.nextStop, isNull);
    });

    test('all done -> allClosed true, nextStop null', () {
      final docs = [
        {'tst': 'done', 'n': 'A'},
        {'tst': 'done', 'n': 'B'},
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 2);
      expect(p.closed, 2);
      expect(p.allClosed, isTrue);
      expect(p.nextStop, isNull);
    });

    test('all failed -> allClosed true', () {
      final docs = [
        {'tst': 'failed', 'n': 'A'},
        {'tst': 'failed', 'n': 'B'},
      ];
      final p = computeStopProgress(docs);
      expect(p.allClosed, isTrue);
    });

    test('mixed done + failed -> allClosed true', () {
      final docs = [
        {'tst': 'done', 'n': 'A'},
        {'tst': 'failed', 'n': 'B'},
      ];
      final p = computeStopProgress(docs);
      expect(p.allClosed, isTrue);
    });

    test('mixed with active -> not allClosed, nextStop = first active', () {
      final docs = [
        {'tst': 'done', 'n': 'A'},
        {'tst': 'active', 'n': 'B'},
        {'tst': 'pending', 'n': 'C'},
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 3);
      expect(p.closed, 1);
      expect(p.allClosed, isFalse);
      expect(p.nextStop?['n'], 'B');
    });

    test('all pending -> closed 0, nextStop = first doc', () {
      final docs = [
        {'tst': '', 'n': 'A'},
        {'n': 'B'},
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 2);
      expect(p.closed, 0);
      expect(p.allClosed, isFalse);
      expect(p.nextStop?['n'], 'A');
    });

    test('nextStop picks first non-closed, skipping done/failed at front', () {
      final docs = [
        {'tst': 'done', 'n': 'A'},
        {'tst': 'failed', 'n': 'B'},
        {'tst': 'active', 'n': 'C'},
        {'tst': '', 'n': 'D'},
      ];
      final p = computeStopProgress(docs);
      expect(p.closed, 2);
      expect(p.nextStop?['n'], 'C');
    });

    test('custom tstField works', () {
      final docs = [
        {'status': 'done', 'n': 'A'},
        {'status': 'active', 'n': 'B'},
      ];
      final p = computeStopProgress(docs, tstField: 'status');
      expect(p.closed, 1);
      expect(p.nextStop?['n'], 'B');
    });

    test('malformed tst values treated as pending', () {
      final docs = [
        {'tst': 'xyz', 'n': 'A'},
        {'tst': 123, 'n': 'B'},
        {'tst': null, 'n': 'C'},
      ];
      final p = computeStopProgress(docs);
      expect(p.closed, 0);
      expect(p.nextStop?['n'], 'A');
    });
  });

  group('computeStopProgress with spec vocab', () {
    test('closed (spec) normalizes to done -> counts as terminal', () {
      final docs = [
        {'tst': 'closed', 'n': 'A'},
        {'tst': 'assigned', 'n': 'B'},
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 2);
      expect(p.closed, 1); // 'closed' -> stopStatusOf -> 'done' -> in _closedStatuses
      expect(p.allClosed, isFalse);
      expect(p.nextStop?['n'], 'B');
    });

    test('ongoing (spec) normalizes to active -> NOT terminal', () {
      final docs = [
        {'tst': 'ongoing', 'n': 'A'},
        {'tst': 'closed', 'n': 'B'},
      ];
      final p = computeStopProgress(docs);
      expect(p.closed, 1); // only 'closed' is terminal
      expect(p.nextStop?['n'], 'A'); // ongoing is the first non-closed
    });

    test('all closed+failed -> allClosed true', () {
      final docs = [
        {'tst': 'closed', 'n': 'A'},
        {'tst': 'failed', 'n': 'B'},
        {'tst': 'closed', 'n': 'C'},
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 3);
      expect(p.closed, 3);
      expect(p.allClosed, isTrue);
      expect(p.nextStop, isNull);
    });

    test('mixed spec vocab: assigned + ongoing + closed + failed', () {
      final docs = [
        {'tst': 'closed', 'n': 'A'},
        {'tst': 'ongoing', 'n': 'B'},
        {'tst': 'assigned', 'n': 'C'},
        {'tst': 'failed', 'n': 'D'},
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 4);
      expect(p.closed, 2); // closed (->done) + failed
      expect(p.allClosed, isFalse);
      expect(p.nextStop?['n'], 'B'); // ongoing is first non-closed
    });

    test('backward compat: done + active still work alongside spec vocab', () {
      final docs = [
        {'tst': 'done', 'n': 'A'},     // old done
        {'tst': 'closed', 'n': 'B'},   // spec closed
        {'tst': 'active', 'n': 'C'},   // old active
        {'tst': 'ongoing', 'n': 'D'},  // spec ongoing
        {'tst': 'assigned', 'n': 'E'}, // spec assigned
      ];
      final p = computeStopProgress(docs);
      expect(p.total, 5);
      expect(p.closed, 2); // done + closed
      expect(p.nextStop?['n'], 'C'); // first non-closed
    });

    test('completed tasks count as closed in computeStopProgress', () {
      final docs = [
        {'tst': 'assigned'},
        {'tst': 'completed'},
        {'tst': 'failed'},
        {'tst': 'on_delivery'},
      ];
      final progress = computeStopProgress(docs);
      expect(progress.total, 4);
      expect(progress.closed, 2); // completed + failed
      expect(progress.allClosed, false);
      expect(progress.nextStop, isNotNull);
      // nextStop should be the first non-closed doc (assigned)
      expect(progress.nextStop!['tst'], 'assigned');
    });
  });
}
