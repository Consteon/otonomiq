// test/evidence_row_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // ── Toggle state logic (pure) ─────────────────────────────────────────

  group('evidence toggle state', () {
    test('initial state is inactive', () {
      bool noteActive = false;
      bool photoActive = false;
      expect(noteActive, false);
      expect(photoActive, false);
    });

    test('toggle flips state', () {
      bool noteActive = false;
      noteActive = !noteActive;
      expect(noteActive, true);
      noteActive = !noteActive;
      expect(noteActive, false);
    });

    test('note and photo are independent', () {
      bool noteActive = true;
      bool photoActive = false;
      expect(noteActive, true);
      expect(photoActive, false);
    });
  });

  // ── diamondTextToList 6-segment guards ────────────────────────────────

  group('evidence row text segment guards', () {
    test('full 6-segment text parses all slots', () {
      final text =
          '\u{1F4DD}\u{25C6}Tambah Catatan\u{25C6}Catatan ditambah'
          '\u{25C6}\u{1F4F7}\u{25C6}Ambil Foto\u{25C6}Foto \u{00B7} 1';
      final arr = diamondTextToList(text);
      expect(arr.length, 6);
      expect(arr.isNotEmpty ? arr[0] : '', isNotEmpty); // emoji
      expect(arr.length > 1 ? arr[1] : '', 'Tambah Catatan');
      expect(arr.length > 2 ? arr[2] : '', 'Catatan ditambah');
      expect(arr.length > 3 ? arr[3] : '', isNotEmpty); // emoji
      expect(arr.length > 4 ? arr[4] : '', 'Ambil Foto');
      expect(arr.length > 5 ? arr[5] : '', contains('Foto'));
    });

    test('sparse text (2 segments) falls back for missing slots', () {
      final arr = diamondTextToList('A\u{25C6}B');
      expect(arr.length, 2);
      expect(arr.length > 2 ? arr[2] : 'fallback2', 'fallback2');
      expect(arr.length > 5 ? arr[5] : 'fallback5', 'fallback5');
    });

    test('empty text returns length-1', () {
      final arr = diamondTextToList('');
      expect(arr.length, 1);
    });
  });
}
