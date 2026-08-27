import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/tasklist.dart';

/// Tests for the TASKLIST submit serialization delimiter.
///
/// Each task is emitted into its form slot as `{title}|{statusLabel}` — a plain
/// ASCII pipe.
///
/// The dev spec originally asked for `☆` (U+2606). That was REJECTED in review:
/// `☆` is `forbiddenCharacter[14]`, and `stringCleanUp` (global.dart) replaces
/// every `forbiddenCharacter` entry except `separator[5]` with a SPACE. `saveSend`
/// pipes both `controller.text` and `finalData` through `stringCleanUp`, so a `☆`
/// delimiter would be silently deleted in transit — the server would receive
/// "title status" with no delimiter at all, and no test that stops at the widget
/// boundary would notice. The same applies to `★` (`forbiddenCharacter[13]`), `◆`,
/// and every other entry in that alphabet.
///
/// Hence the "delivered value" group below: it asserts what the SERVER receives,
/// not merely what the widget built.
///
/// Second invariant: the join SANITIZES both operands, replacing any `|` in the
/// title or the label with a space, so the emitted value carries exactly one `|`
/// structurally rather than by convention. `|` survives `stringCleanUp` (that is
/// why it was chosen), so nothing else stops a tenant sheet from authoring
/// "Cek panel A|B" and reintroducing the split ambiguity that killed `:`.
/// Consequence for the assertions below: `substring(0, indexOf('|'))` equals the
/// SANITIZED title, which is the raw title only when the raw title had no pipe.
/// For the three spec vectors (no pipes) verbatim still holds exactly.
///
/// What CANNOT be tested here (requires device QA):
/// - The status sheet / circle toggle writing into txfController (needs a pump).
/// - The seeded pending value on page init (canInitializePage + txfController).
void main() {
  // Spec §6 vectors, retargeted from the rejected `☆` to `|`.
  const vectors = [
    ['Sapu dan pel lantai', 'Selesai'],
    ['Isi ulang tissue dan sabun', 'Tidak Tersedia'],
    ['Cek jam: shift pagi', 'Dilewati'],
  ];

  // Pipe-bearing inputs: [rawTitle, rawLabel, expectedEmittedValue].
  // These are what actually challenge the "exactly one pipe" invariant — none of
  // the three spec vectors above contains a pipe, so they cannot exercise it.
  const pipeVectors = [
    // pipe in the title (tenant-authored sheet text)
    ['Cek panel A|B', 'Selesai', 'Cek panel A B|Selesai'],
    // pipe in the label — labels come from `options` config, which contains no
    // pipe today, but that is a convention and not an enforcement
    ['Ganti filter udara', 'Selesai|Sebagian', 'Ganti filter udara|Selesai Sebagian'],
    // MULTIPLE pipes: all replaced, not just the first
    ['Cek A|B|C|D', 'Dilewati', 'Cek A B C D|Dilewati'],
  ];

  group('tasklistSerialize', () {
    // RED if: the delimiter changes (spec §6 vector 1)
    test('vector 1 — plain title', () {
      expect(
        tasklistSerialize('Sapu dan pel lantai', 'Selesai'),
        'Sapu dan pel lantai|Selesai',
      );
    });

    // RED if: the delimiter changes (spec §6 vector 2)
    test('vector 2 — multi-word status label', () {
      expect(
        tasklistSerialize('Isi ulang tissue dan sabun', 'Tidak Tersedia'),
        'Isi ulang tissue dan sabun|Tidak Tersedia',
      );
    });

    // RED if: a ':' in the title is treated as a delimiter (spec §6 vector 3)
    test('vector 3 — colon inside the title is preserved verbatim', () {
      expect(
        tasklistSerialize('Cek jam: shift pagi', 'Dilewati'),
        'Cek jam: shift pagi|Dilewati',
      );
    });

    // RED if: more than one delimiter is emitted (one cell = one task|status pair).
    // Covers the pipe-bearing inputs too — that is where the invariant can break.
    test('exactly one | per emitted value', () {
      for (final v in [
        ...vectors,
        ...pipeVectors.map((v) => [v[0], v[1]]),
      ]) {
        final out = tasklistSerialize(v[0], v[1]);
        expect('|'.allMatches(out).length, 1, reason: 'value: $out');
      }
    });

    // RED if: the title is trimmed, escaped, or split on ':'.
    // Unweakened: for pipe-free input the title must survive byte-for-byte.
    test('substring before | equals the title verbatim (no pipe in input)', () {
      for (final v in vectors) {
        final out = tasklistSerialize(v[0], v[1]);
        final i = out.indexOf('|');
        expect(out.substring(0, i), v[0]);
        expect(out.substring(i + 1), v[1]);
      }
    });

    // RED if: a pipe in the title survives into the emitted value
    test('pipe in the title is replaced with a space', () {
      expect(
        tasklistSerialize('Cek panel A|B', 'Selesai'),
        'Cek panel A B|Selesai',
      );
    });

    // RED if: only the title is sanitized and the label is trusted
    test('pipe in the label is replaced with a space', () {
      expect(
        tasklistSerialize('Ganti filter udara', 'Selesai|Sebagian'),
        'Ganti filter udara|Selesai Sebagian',
      );
    });

    // RED if: sanitization stops at the first pipe (e.g. replaceFirst)
    test('every pipe is replaced, not just the first', () {
      expect(
        tasklistSerialize('Cek A|B|C|D', 'Dilewati'),
        'Cek A B C D|Dilewati',
      );
    });

    // RED if: sanitized operands stop landing either side of the one delimiter.
    // Expectations come from the hardcoded pipeVectors[2] literal, NOT from
    // re-running replaceAll — a test that re-implements the code it checks only
    // ever agrees with itself.
    test('emitted value matches the hardcoded expectation, split cleanly', () {
      for (final v in pipeVectors) {
        final out = tasklistSerialize(v[0], v[1]);
        expect(out, v[2]);
        expect(out.split('|'), v[2].split('|'), reason: 'value: $out');
        expect(out.split('|').length, 2, reason: 'value: $out');
      }
    });

    // RED if: someone reverts the delimiter back to ':'
    test('never emits the old colon form', () {
      for (final v in vectors) {
        expect(tasklistSerialize(v[0], v[1]), isNot('${v[0]}:${v[1]}'));
      }
    });
  });

  // The gate that would have caught C1. Building the right string is not enough —
  // the value must still be intact after saveSend's stringCleanUp pass.
  group('delivered value (survives saveSend stringCleanUp)', () {
    // RED if: the delimiter becomes any forbiddenCharacter entry (☆, ★, ◆, …)
    test('delimiter survives the submit pipeline', () {
      for (final v in vectors) {
        final out = tasklistSerialize(v[0], v[1]);
        final delivered = stringCleanUp(out)!;
        expect(delivered.split('|'), [v[0], v[1]], reason: 'value: $out');
      }
    });

    // RED if: a pipe-bearing title reaches the server with two delimiters, which
    // is what a naive downstream split('|') would misparse into three columns.
    test('pipe-bearing input still delivers exactly two parts', () {
      for (final v in pipeVectors) {
        final out = tasklistSerialize(v[0], v[1]);
        final delivered = stringCleanUp(out)!;
        // stringCleanUp leaves | and spaces alone, so the delivered value is the
        // hardcoded expectation verbatim.
        expect(delivered, v[2], reason: 'raw: ${v[0]} / ${v[1]}');
        expect(delivered.split('|').length, 2, reason: 'delivered: $delivered');
      }
    });

    // RED if: stringCleanUp stops stripping U+2606 — i.e. the day someone edits
    // forbiddenCharacter. This is the C1 regression as an executable fact:
    // the spec's ☆ delimiter is destroyed in transit.
    test('the rejected ☆ delimiter would NOT have survived', () {
      expect(stringCleanUp('a☆b'), 'a b');
      expect(stringCleanUp('Cek jam: shift pagi☆Dilewati')!.contains('☆'),
          isFalse);
      // ★ (forbiddenCharacter[13]) shares the fate — same reason.
      expect(stringCleanUp('a★b'), 'a b');
    });
  });
}
