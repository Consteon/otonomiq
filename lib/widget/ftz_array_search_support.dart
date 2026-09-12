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

// ─────────────────────────────────────────────────────────────────────────
// v6 report list (`variant: "tableCardInteractiveV6"`)
//
// Everything below is pure so the rules the list decides on — which chip
// colour, which day a row belongs to, whether a range filter can exist at all
// — are testable without a device. The v1 card above is untouched: a component
// that does not author the v6 variant never reaches any of it.
// ─────────────────────────────────────────────────────────────────────────

/// Semantic level of a condition/status value, for the row chip.
///
/// The v1 card painted every chip the same indigo. v6 gives the three levels
/// the design system's own colours, so "Insiden" cannot read as "Aman".
enum ReportTone { ok, warn, err, neutral }

/// Words that decide a chip's colour, most severe first.
///
/// Order is load-bearing, not cosmetic: "Tidak aman" contains `aman`, so the
/// danger list has to win before the ok list is consulted.
const List<String> kReportToneErr = <String>[
  'insiden',
  'darurat',
  'bahaya',
  'kritis',
  'gawat',
  'tidak aman',
  'kecelakaan',
  'kebakaran',
  'pencurian',
  'ditolak',
];
const List<String> kReportToneWarn = <String>[
  'perlu',
  'perhatian',
  'tindak',
  'lanjut',
  'temuan',
  'waspada',
  'rusak',
  'pending',
  'menunggu',
  'proses',
];
const List<String> kReportToneOk = <String>[
  'aman',
  'kondusif',
  'normal',
  'lancar',
  'bersih',
  'selesai',
  'beres',
  'terkirim',
];

/// Values that are only a tone when they are the WHOLE string. `ok` as a
/// substring matches `lokasi`, `blokir` and `tokoh`.
const List<String> kReportToneOkExact = <String>['ok', 'oke', 'baik', 'ya'];

ReportTone reportTone(String value) {
  final String v = value.trim().toLowerCase();
  if (v.isEmpty) return ReportTone.neutral;
  if (kReportToneOkExact.contains(v)) return ReportTone.ok;
  for (final String w in kReportToneErr) {
    if (v.contains(w)) return ReportTone.err;
  }
  for (final String w in kReportToneWarn) {
    if (v.contains(w)) return ReportTone.warn;
  }
  for (final String w in kReportToneOk) {
    if (v.contains(w)) return ReportTone.ok;
  }
  return ReportTone.neutral;
}

/// Oldest value still read as a row timestamp: 2010-01-01 in epoch ms.
const int kMinReportEpochMs = 1262304000000;

/// `row[0]` as epoch milliseconds, or null when it is not a timestamp.
///
/// `MobileTableController.addContent` stamps every content document with
/// `t = getNowMillisecondFromEpoch()` and `createInternalTableDynamic`
/// (`table_repository.dart:2097`) inserts that `t` at index 0 of every row, so
/// on live data this always parses. It is still guarded, because:
///   * `indexTableType: 'K'` tables key on a data column instead, and
///   * a 14-digit `yyyyMMddHHmmss` id would clear the lower bound and land in
///     the year 2612, which is why there is an upper bound at all.
/// A null here never hides a row — it only means that row cannot carry a clock
/// or a day header.
int? reportEpoch(List<dynamic> row, DateTime now) {
  if (row.isEmpty) return null;
  final int? ms = int.tryParse(row[0].toString().trim());
  if (ms == null) return null;
  if (ms < kMinReportEpochMs) return null;
  // One year ahead absorbs a clock-skewed device; a date-shaped id does not
  // survive it.
  if (ms > now.millisecondsSinceEpoch + 31536000000) return null;
  return ms;
}

const List<String> kHariIndonesia = <String>[
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];
const List<String> kBulanIndonesia = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

/// Whole days between the two calendar dates, ignoring the clock.
int reportDaysBetween(DateTime from, DateTime to) => DateTime(
  to.year,
  to.month,
  to.day,
).difference(DateTime(from.year, from.month, from.day)).inDays;

/// Day-group header: `Hari ini · Jumat, 11 Sep` / `Kemarin · …` / `Rabu, 9 Sep`.
///
/// Hardcoded Indonesian rather than `intl`: nothing in this app calls
/// `initializeDateFormatting`, so a locale-aware format would silently fall
/// back to English day names on most devices. Same call as the v6 map screen.
String reportDayHeader(DateTime day, DateTime now) {
  final String date =
      '${kHariIndonesia[day.weekday - 1]}, ${day.day} ${kBulanIndonesia[day.month - 1]}';
  final int diff = reportDaysBetween(day, now);
  if (diff == 0) return 'Hari ini · $date';
  if (diff == 1) return 'Kemarin · $date';
  return date;
}

/// Header for rows whose `row[0]` is not a timestamp. They are still listed —
/// hiding a report because its key is shaped oddly is the one failure this
/// screen must not have.
const String kReportNoDateHeader = 'Tanpa tanggal';

String reportClock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// Time window the filter chips select.
enum ReportRange { today, week, month, all }

const List<String> kReportRangeChips = <String>[
  'Hari ini',
  '7 hari',
  '30 hari',
  'Semua',
];

/// The range as it reads inside a sentence: "3 laporan · 7 hari terakhir".
const List<String> kReportRangeSummary = <String>[
  'hari ini',
  '7 hari terakhir',
  '30 hari terakhir',
  'semua waktu',
];

/// True when a row stamped [epochMs] belongs in [range].
///
/// A null [epochMs] always passes. The chips are a view over time, not an
/// access rule, so a row that cannot be dated is shown in every one of them
/// rather than disappearing from three out of four.
bool inReportRange(int? epochMs, ReportRange range, DateTime now) {
  if (range == ReportRange.all || epochMs == null) return true;
  final int days = reportDaysBetween(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
    now,
  );
  if (days < 0) return true; // future stamp — never hidden
  switch (range) {
    case ReportRange.today:
      return days == 0;
    case ReportRange.week:
      return days < 7;
    case ReportRange.month:
      return days < 30;
    case ReportRange.all:
      return true;
  }
}

/// One run of text and whether the search query matched it.
class HighlightSpan {
  final String text;
  final bool hit;
  const HighlightSpan(this.text, this.hit);
}

/// Split [text] into alternating plain/matched runs for [query].
///
/// Plain case-insensitive substring matching on the raw query. `searchTable`'s
/// own grammar is richer (`◆` is an OR of clauses), so this deliberately marks
/// LESS than the filter matched rather than guessing: an unhighlighted row that
/// is genuinely in the result set is a missing hint, while a highlight over
/// text that did not match would be a lie.
List<HighlightSpan> highlightSpans(String text, String query) {
  final String q = query.trim();
  if (q.isEmpty || text.isEmpty)
    return <HighlightSpan>[HighlightSpan(text, false)];
  final String haystack = text.toLowerCase();
  final String needle = q.toLowerCase();
  final List<HighlightSpan> out = <HighlightSpan>[];
  int i = 0;
  while (true) {
    final int hit = haystack.indexOf(needle, i);
    if (hit < 0) break;
    if (hit > i) out.add(HighlightSpan(text.substring(i, hit), false));
    out.add(HighlightSpan(text.substring(hit, hit + needle.length), true));
    i = hit + needle.length;
  }
  if (i < text.length) out.add(HighlightSpan(text.substring(i), false));
  return out.isEmpty ? <HighlightSpan>[HighlightSpan(text, false)] : out;
}

/// The muted `lokasi · unit` line: every role that is not the clock, the chip
/// or the note, joined in template order.
///
/// The title line is included on purpose. v6's mock drops the reporter's name
/// because a personal list does not need it — but that is a CONFIG decision
/// (delete `Nama: <4>` from the sheet's `content`), not something the renderer
/// may do silently to a tenant that authored the field.
String reportSubline(ContentRoles roles) => <String>[
  roles.title?.value ?? '',
  ...roles.meta.map((ContentLine l) => l.value),
].where((String v) => v.trim().isNotEmpty).join(' · ');

// ─────────────────────────────────────────────────────────────────────────
// v6 report DETAIL sheet
// ─────────────────────────────────────────────────────────────────────────

/// True when [label] names a place — the fields the v6 detail head puts on its
/// "Hari, tgl · site · unit" line instead of down in the metadata table.
///
/// Same keyword groups [metaIcon] already uses for its place and building
/// icons, so a label that draws a pin in the list ends up in the head here.
/// Deliberately keyword-based and not positional: the live patrol screen has
/// `Lokasi` and `Site` the wrong way round (`Lokasi` holds the site, `Site`
/// holds the unit), and joining both into one line makes the mix-up invisible
/// while the sheet stays truthful about what it was given.
bool isPlaceLabel(String label) {
  final String l = label.toLowerCase();
  return l.contains('lokasi') ||
      l.contains('alamat') ||
      l.contains('posisi') ||
      l.contains('site') ||
      l.contains('area') ||
      l.contains('gedung');
}

/// The slots the v6 detail sheet renders.
class DetailRoles {
  /// The condition value, drawn as a semantic chip in the head.
  final String chip;

  /// Place fields, in template order — joined into the head's second line.
  final List<ContentLine> place;

  /// The free-text body ("Keterangan").
  final ContentLine? note;

  /// Everything else, rendered as the two-column metadata table.
  final List<ContentLine> meta;

  /// The first line's value (usually `Tanggal`). Kept separate because it is
  /// the fallback for the head's date when the row carries no epoch, and the
  /// "Dibuat" row when it does.
  final String stampText;

  const DetailRoles({
    this.chip = '',
    this.place = const <ContentLine>[],
    this.note,
    this.meta = const <ContentLine>[],
    this.stampText = '',
  });
}

/// Map parsed `detail` lines onto the sheet's slots.
///
/// Unlike [splitContentRoles] this is NOT positional past the first and last
/// line: the sheet has room for every field, so each one is placed by what its
/// label says rather than by where it sits. Line 0 is the stamp and the last
/// line is the note — the two the template always ends up putting there — and
/// everything between is sorted into chip / place / metadata.
///
/// Nothing is dropped. A field that matches no rule lands in the metadata
/// table, which is the slot that can hold anything.
DetailRoles splitDetailRoles(List<ContentLine> lines, String chipLabel) {
  if (lines.isEmpty) return const DetailRoles();
  if (lines.length == 1) {
    return DetailRoles(note: lines[0], stampText: lines[0].value);
  }

  final int chipIndex = chipLineIndex(
    lines,
    chipLabel,
    from: 1,
    to: lines.length - 1,
  );
  final List<ContentLine> place = <ContentLine>[];
  final List<ContentLine> meta = <ContentLine>[];
  for (int i = 1; i < lines.length - 1; i++) {
    if (i == chipIndex) continue;
    if (isPlaceLabel(lines[i].label)) {
      place.add(lines[i]);
    } else {
      meta.add(lines[i]);
    }
  }
  return DetailRoles(
    chip: chipIndex >= 0 ? lines[chipIndex].value : '',
    place: place,
    note: lines.last,
    meta: meta,
    stampText: lines[0].value,
  );
}

/// `Jumat, 11 Sep 2026` — the head's long form, with the year the day-group
/// header in the list omits.
String reportLongDate(DateTime day) =>
    '${kHariIndonesia[day.weekday - 1]}, ${day.day} '
    '${kBulanIndonesia[day.month - 1]} ${day.year}';

/// The head's second line: long date, then every place value, ` · ` joined.
String detailHeadSubline(DetailRoles roles, int? epochMs) => <String>[
  if (epochMs != null)
    reportLongDate(DateTime.fromMillisecondsSinceEpoch(epochMs))
  else
    roles.stampText,
  ...roles.place.map((ContentLine l) => l.value),
].where((String v) => v.trim().isNotEmpty).join(' · ');

/// The photo viewer's caption: when, then where.
String photoCaption(DetailRoles roles, int? epochMs) {
  final DateTime? at = epochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(epochMs);
  return <String>[
    if (at != null)
      '${reportLongDate(at)} · ${reportClock(at)}'
    else
      roles.stampText,
    ...roles.place.map((ContentLine l) => l.value),
  ].where((String v) => v.trim().isNotEmpty).join(' · ');
}
