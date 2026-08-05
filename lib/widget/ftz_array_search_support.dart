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
  final int ci = chipLineIndex(lines, chipLabel, from: 2, to: lines.length - 1);
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
