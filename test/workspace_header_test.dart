// test/workspace_header_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // ── stopNumber derivation (pure function) ─────────────────────────────

  group('stopNumber derivation', () {
    /// Pure function mirroring WorkspaceHeader's stopNumber logic:
    /// iterate filtered task docs in doc-order, return the 1-based index
    /// of the doc whose [idField] matches [activeTaskVid].
    /// Returns 0 if not found.
    int deriveStopNumber(
      List<Map<String, dynamic>> tasks,
      String activeTaskVid,
      String idField,
    ) {
      for (int i = 0; i < tasks.length; i++) {
        final String docId = (tasks[i][idField] ?? '').toString().trim();
        if (docId == activeTaskVid) return i + 1;
      }
      return 0;
    }

    test('finds correct 1-based index for second task', () {
      final tasks = [
        {'tnm': 'T001', 'kn': 'Customer A'},
        {'tnm': 'T002', 'kn': 'Customer B'},
        {'tnm': 'T003', 'kn': 'Customer C'},
      ];
      expect(deriveStopNumber(tasks, 'T002', 'tnm'), 2);
    });

    test('returns 0 when activeTaskVid not found', () {
      final tasks = [
        {'tnm': 'T001'},
        {'tnm': 'T002'},
      ];
      expect(deriveStopNumber(tasks, 'T999', 'tnm'), 0);
    });

    test('returns 0 for empty task list', () {
      expect(deriveStopNumber([], 'T001', 'tnm'), 0);
    });

    test('first task returns 1', () {
      final tasks = [
        {'tnm': 'T001'},
      ];
      expect(deriveStopNumber(tasks, 'T001', 'tnm'), 1);
    });
  });

  // ── diamondTextToList length guards (workspace header 2 segments) ─────

  group('workspace header text segment guards', () {
    test('2-segment text parses correctly', () {
      final arr = diamondTextToList('Stop\u{25C6}Berjalan');
      expect(arr.isNotEmpty ? arr[0] : '', 'Stop');
      expect(arr.length > 1 ? arr[1] : '', 'Berjalan');
    });

    test('empty text falls back to defaults', () {
      final arr = diamondTextToList('');
      // diamondTextToList('') returns [''] (length 1, arr[0] == '').
      // The index-0 read therefore yields the empty parse value (NOT the
      // 'Stop' default, since length>0). The length-guard default only kicks
      // in at index >= 1.
      expect(arr.length, 1);
      expect(arr.isNotEmpty ? arr[0] : 'Stop', ''); // '' from parse
      expect(arr.length > 1 ? arr[1] : 'Berjalan', 'Berjalan'); // default
    });

    test('single segment falls back for index 1', () {
      final arr = diamondTextToList('OnlyOne');
      expect(arr.isNotEmpty ? arr[0] : '', 'OnlyOne');
      expect(arr.length > 1 ? arr[1] : 'fallback', 'fallback');
    });
  });
}
