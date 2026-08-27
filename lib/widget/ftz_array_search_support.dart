//
// ftz_array_search_support.dart
//
// Pure helpers for the FtzArraySearch card renderer. Kept out of the widget so
// they stay unit-testable (test/ftz_array_search_support_test.dart).
//
import 'package:flutter/material.dart';

/// One `Label: value` line parsed out of a rendered `content` template.
///
/// [label] is `''` when the line carried no usable label — the caller then
/// renders [value] on its own, so nothing is ever dropped.
class ContentLine {
  final String label;
  final String value;
  const ContentLine(this.label, this.value);
}

/// Longest leading run still accepted as a field label. Anything longer is a
/// sentence that happens to contain ':', not a field name.
const int maxContentLabelLength = 24;

final RegExp _leadingDigit = RegExp(r'^\d');

/// Split a rendered `content` blob into label/value lines.
///
/// Splits on the FIRST ':' only, so values that themselves contain ':'
/// (`Tanggal: 05 Aug 2026 10:05`, URLs) survive intact. A leading segment that
/// is empty, over [maxContentLabelLength], or starts with a digit is NOT a
/// label — the whole line becomes the value, so a bare `10:05` stays `10:05`.
List<ContentLine> parseContentLines(String rendered) {
  final List<ContentLine> out = [];
  for (final String raw in rendered.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    final int i = line.indexOf(':');
    if (i > 0 && i <= maxContentLabelLength) {
      final String label = line.substring(0, i).trim();
      if (label.isNotEmpty && !_leadingDigit.hasMatch(label)) {
        out.add(ContentLine(label, line.substring(i + 1).trim()));
        continue;
      }
    }
    out.add(ContentLine('', line));
  }
  return out;
}

/// Index of the first line whose label matches [label] (case-insensitive),
/// or -1. Used to lift one field out of the meta rows and into the chip.
int indexOfLabel(List<ContentLine> lines, String label) {
  final String want = label.trim().toLowerCase();
  if (want.isEmpty) return -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].label.toLowerCase() == want) return i;
  }
  return -1;
}

/// Longest chip value. A longer value is free text, not a category, and would
/// squeeze the card title out of its row.
const int maxChipValueLength = 24;

/// True when [label] names a *category* field — the kind worth promoting from
/// a meta row to a chip (Jenis Laporan, Jenis Keluhan, Kondisi, Status…).
///
/// Used only when the component authors no explicit `chipLabel`, so a screen
/// can always override this by naming the field it wants.
bool isChipLabel(String label) {
  final String l = label.toLowerCase();
  return l.contains('jenis') ||
      l.contains('kategori') ||
      l.contains('tipe') ||
      l.contains('kondisi') ||
      l.contains('status');
}

/// Index of the first line in [lines] that should become the chip, or -1.
///
/// Searches only [from, to) so the caller can keep the eyebrow/title/note out
/// of range. An explicit [configured] label wins outright; otherwise falls
/// back to [isChipLabel] on a value short enough to sit beside the title.
int chipLineIndex(
  List<ContentLine> lines,
  String configured, {
  required int from,
  required int to,
}) {
  final int lo = from < 0 ? 0 : from;
  final int hi = to > lines.length ? lines.length : to;
  if (configured.trim().isNotEmpty) {
    final int i = indexOfLabel(lines, configured);
    return (i >= lo && i < hi && lines[i].value.isNotEmpty) ? i : -1;
  }
  for (int i = lo; i < hi; i++) {
    if (isChipLabel(lines[i].label) &&
        lines[i].value.isNotEmpty &&
        lines[i].value.length <= maxChipValueLength) {
      return i;
    }
  }
  return -1;
}

/// The card slots a parsed content blob maps onto.
class ContentRoles {
  final ContentLine? eyebrow;
  final ContentLine? title;
  final ContentLine? note;
  final List<ContentLine> meta;
  final String chip;
  const ContentRoles({
    this.eyebrow,
    this.title,
    this.note,
    this.meta = const [],
    this.chip = '',
  });
}

/// Assign [lines] to card slots: first = eyebrow (timestamp), second = title,
/// last = free text, the rest = meta rows, with one meta row optionally lifted
/// into the chip.
///
/// Positional by necessity — the `content` template is a flat string with no
/// per-field semantics. Every report screen in the sheet authors the same shape
/// (`Tanggal … Nama … <fields> … Keterangan`). Shorter blobs collapse from the
/// bottom up: 2 lines lose the note, 1 line is title-only, 0 lines is empty.
ContentRoles splitContentRoles(List<ContentLine> lines, String chipLabel) {
  if (lines.isEmpty) return const ContentRoles();
  if (lines.length == 1) return ContentRoles(title: lines[0]);
  if (lines.length == 2) {
    return ContentRoles(eyebrow: lines[0], title: lines[1]);
  }
  final List<ContentLine> meta = lines.length > 3
      ? lines.sublist(2, lines.length - 1)
      : <ContentLine>[];
  String chip = '';
  final int ci = chipLineIndex(
    lines,
    chipLabel,
    from: 2,
    to: lines.length - 1,
  );
  if (ci >= 0) {
    chip = lines[ci].value;
    meta.removeWhere((l) => l.label == lines[ci].label);
  }
  return ContentRoles(
    eyebrow: lines[0],
    title: lines[1],
    note: lines.last,
    meta: meta,
    chip: chip,
  );
}

/// The rendered value of a `rowSplit` slot the source row never filled.
///
/// `CHECKLIST_DYNAMIC` writes `*` into a checklist slot it did not use, so on a
/// `rowSplit` line the star is bookkeeping, not a status. Only an exact match
/// after trimming counts — `*Selesai` is real data and is kept.
const String emptyRowSlotMarker = '*';

/// A template line (or a rendered value) that is nothing but one `<N>` marker.
final RegExp _bareMarkerLine = RegExp(r'^<\d+>$');

/// True when [text] is a bare `<N>` placeholder once trimmed.
///
/// [parseContentLinesSplit] asks this twice. On the TEMPLATE line it decides
/// whether `rowSplit` applies at all — `Tanggal: <2>` and `Catatan <9>` both
/// carry literal text and are refused, which is the spec's non-breaking
/// promise. On the RENDERED value it catches a marker `replaceMarker` never
/// substituted: that loop runs only while `i < ref.length` (global.dart:1300),
/// so `<19>` on a short row reaches us verbatim as the text `<19>`.
bool isBareMarkerLine(String text) => _bareMarkerLine.hasMatch(text.trim());

/// Parse a `content`/`detail` template into label/value lines with the
/// component's optional `rowSplit` [separator] applied.
///
/// Provenance is the whole point. "Was this line a bare `<N>`?" is a property
/// of the TEMPLATE, and the fully rendered blob no longer knows — worse,
/// template-line and rendered-line indexes diverge, because a substituted value
/// may itself contain a line break. So the template is split into lines FIRST
/// and [render] substitutes one line at a time. [render] is the caller's
/// `replaceMarker(...)` + literal-`\n` fold, injected rather than imported so
/// this file stays free of global.dart and stays unit-testable.
///
/// Per template line:
/// * blank                       -> dropped, as [parseContentLines] already does
/// * NOT a bare `<N>`            -> handed to [parseContentLines] verbatim, so
///                                  `Label: value` keeps its existing path and a
///                                  value that merely contains [separator] is
///                                  NOT split
/// * bare `<N>`, empty value     -> dropped (empty / whitespace /
///                                  [emptyRowSlotMarker] / unsubstituted `<N>`)
/// * bare `<N>`, no [separator]  -> one plain line, label `''`
/// * bare `<N>`, has [separator] -> split at the FIRST occurrence, both sides
///                                  trimmed: left = label, right = value
///
/// A blank [separator] means the caller wants the pre-`rowSplit` behaviour, so
/// the whole template is rendered in ONE pass and handed to
/// [parseContentLines] — byte-identical to the old path.
///
/// The label produced here is deliberately NOT capped at
/// [maxContentLabelLength]: that cap stops a sentence containing a ':' from
/// masquerading as a label, whereas a `rowSplit` header is an explicit field
/// name ("Sapu halaman dan area pedestrian" is 32 chars and legitimate).
///
/// Cost: one [render] pass per template line instead of one per blob. Only
/// screens that author `rowSplit` pay it.
List<ContentLine> parseContentLinesSplit(
  String template,
  String separator,
  String Function(String templateLine) render,
) {
  if (separator.trim().isEmpty) return parseContentLines(render(template));
  final List<ContentLine> out = [];
  // Fold a sheet-authored literal `\n` before splitting, so both spellings of a
  // line break yield the same set of template lines.
  for (final String rawLine in template.replaceAll('\\n', '\n').split('\n')) {
    if (rawLine.trim().isEmpty) continue;
    final String rendered = render(rawLine);
    if (!isBareMarkerLine(rawLine)) {
      out.addAll(parseContentLines(rendered));
      continue;
    }
    final String value = rendered.trim();
    if (value.isEmpty ||
        value == emptyRowSlotMarker ||
        isBareMarkerLine(value)) {
      continue;
    }
    // indexOf, not RegExp: the separator is arbitrary config text and task
    // names legitimately contain '/', '(' and ')'.
    final int cut = value.indexOf(separator);
    if (cut < 0) {
      out.add(ContentLine('', value));
      continue;
    }
    out.add(
      ContentLine(
        value.substring(0, cut).trim(),
        value.substring(cut + separator.length).trim(),
      ),
    );
  }
  return out;
}

/// Icon for a field label, matched on Indonesian/English keywords.
///
/// Returns null when nothing matches — the caller then falls back to printing
/// the label text, so an unmapped label never loses information.
IconData? metaIcon(String label) {
  final String l = label.toLowerCase();
  if (l.contains('tanggal') || l.contains('waktu') || l.contains('jam')) {
    return Icons.schedule;
  }
  if (l.contains('nama') || l.contains('petugas') || l.contains('pelapor')) {
    return Icons.person_outline;
  }
  if (l.contains('lokasi') || l.contains('alamat') || l.contains('posisi')) {
    return Icons.place_outlined;
  }
  if (l.contains('site') || l.contains('area') || l.contains('gedung')) {
    return Icons.apartment_outlined;
  }
  if (l.contains('jenis') || l.contains('kategori') || l.contains('tipe')) {
    return Icons.sell_outlined;
  }
  if (l.contains('kondisi') || l.contains('status')) {
    return Icons.verified_outlined;
  }
  if (l.contains('hadir') || l.contains('peserta')) {
    return Icons.groups_outlined;
  }
  if (l.contains('tujuan') || l.contains('keperluan')) {
    return Icons.flag_outlined;
  }
  if (l.contains('keterangan') || l.contains('catatan')) {
    return Icons.notes_outlined;
  }
  return null;
}
