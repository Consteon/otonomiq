import 'package:intl/intl.dart';

import 'list_card_support.dart'; // resolveNoteTemplate — spec section 3 auto-hide

// ─── Config separators ─────────────────────────────────────────────────────
//
// TIMELINE_CARD's dotMap/chipMap separate ENTRIES with ⭘ (U+2B58), not ★
// (U+2605) as LIST_CARD's badgeMap/groupRoutes do. Kept as escapes, never as
// pasted glyphs, matching list_card_support.dart.

const String _entrySep = '\u{2B58}'; // ⭘ white big circle — separates entries
const String _fieldSep = '\u{25FC}'; // ◼ black square      — separates fields

/// `<field>` token, same shape as resolveNoteTemplate's and
/// panel_card_support's `_angleToken`. Kept character-identical on purpose.
final RegExp _angleToken = RegExp(r'<([a-zA-Z][a-zA-Z0-9]*)>');

// ─── dotMap ────────────────────────────────────────────────────────────────

/// Parse `dotMap`: `value◼tier⭘value2◼tier2`.
///
/// Returns value -> tier. Entries without a `◼` are SKIPPED (fail-closed: a
/// malformed entry means "no colour opinion", never a colour for the wrong
/// value) — the same rule as `parseGroupRoutes` in list_card_support.dart, with
/// ⭘ instead of ★ as the entry separator. A third `◼` segment is ignored.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling (SduiSpec.str
/// already does).
Map<String, String> parseDotMap(String raw) {
  if (raw.trim().isEmpty) return const {};
  final Map<String, String> out = {};
  for (final String part in raw.split(_entrySep)) {
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final List<String> segs = trimmed.split(_fieldSep);
    if (segs.length < 2) continue; // no ◼ -> skip
    final String value = segs[0].trim();
    final String tier = segs[1].trim().toLowerCase();
    if (value.isEmpty || tier.isEmpty) continue;
    out[value] = tier;
  }
  return out;
}

// ─── chipMap ───────────────────────────────────────────────────────────────

/// One `chipMap` entry: `value◼Label◼tier`.
///
/// ORDER IS SEMANTIC. Entry 0 is the "open / in-progress" state and its chip
/// shows with NO date condition (spec section 4: a night-shift clock-in at
/// 22:00 yesterday still reads "Sedang Bekerja" at 06:00 today). Every other
/// entry is a terminal state and shows only when the newest row's local day is
/// today.
class ChipEntry {
  final String value;
  final String label;
  final String tier; // ok | info | warn | danger | muted
  const ChipEntry(this.value, this.label, this.tier);
}

/// Parse `chipMap`: `value◼Label◼tier⭘value2◼Label2◼tier2`.
///
/// Missing label -> the value doubles as the label. Missing/blank tier ->
/// `'info'`. Entries with a blank value are skipped. Mirrors
/// `parseBadgeMap` in list_card_support.dart with ⭘ as the entry separator.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
List<ChipEntry> parseChipMap(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<ChipEntry> out = [];
  for (final String part in raw.split(_entrySep)) {
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final List<String> segs = trimmed.split(_fieldSep);
    final String value = segs.isNotEmpty ? segs[0].trim() : '';
    if (value.isEmpty) continue;
    final String rawLabel = segs.length > 1 ? segs[1].trim() : '';
    String tier = segs.length > 2 ? segs[2].trim().toLowerCase() : '';
    if (tier.isEmpty) tier = 'info';
    out.add(ChipEntry(value, rawLabel.isEmpty ? value : rawLabel, tier));
  }
  return out;
}

/// Lookup index of [value] in [entries]; -1 when absent or [value] blank.
int chipIndexOf(List<ChipEntry> entries, String value) {
  final String v = value.trim();
  if (v.isEmpty) return -1;
  for (int i = 0; i < entries.length; i++) {
    if (entries[i].value == v) return i;
  }
  return -1;
}

// ─── row template ──────────────────────────────────────────────────────────

/// Field name that drives the time cell, the day grouping and the chip date
/// test: the FIRST `<field>` token of `row` slot 0 (spec section 3 requires
/// exactly one; a second token is ignored rather than fatal).
///
/// Returns `''` when `row` is absent/empty or slot 0 has no token — the widget
/// then renders no time, emits no day separator, and falls the chip through to
/// its empty-condition label. No throw.
String timeFieldOf(List<String> rowSlots) {
  if (rowSlots.isEmpty) return '';
  final RegExpMatch? m = _angleToken.firstMatch(rowSlots[0]);
  return m == null ? '' : (m.group(1) ?? '');
}

/// Epoch ms for one doc. `0` when [timeField] is blank, the key is absent, or
/// the value does not parse as an int (Firestore hands back both `1756…` and
/// `"1756…"` depending on the writer).
int docEpochMs(Map<String, dynamic> doc, String timeField) {
  if (timeField.isEmpty) return 0;
  final dynamic v = doc[timeField];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse((v ?? '').toString().trim()) ?? 0;
}

/// Resolve `row` slot [index] against [doc] with spec section 3 auto-hide.
///
/// Length-guarded (Convention 3): an out-of-range slot yields `''`, never a
/// RangeError on a lean tenant `row` string.
///
/// Delegates to `resolveNoteTemplate` (list_card_support.dart) — IMPORTED, not
/// copied, so the skip-on-ANY-empty-token rule can never diverge between
/// LIST_CARD's `note` and TIMELINE_CARD's row slots.
String resolveRowSlot(
  List<String> rowSlots,
  int index,
  Map<String, dynamic> doc,
) {
  if (rowSlots.length <= index) return '';
  return resolveNoteTemplate(rowSlots[index], doc);
}

// ─── day grouping (device-local — interview decision D2) ───────────────────

/// Local calendar-day key `yyyy-MM-dd`, or `''` for a non-positive epoch.
String dayKeyOf(int epochMs) {
  if (epochMs <= 0) return '';
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final String mm = d.month.toString().padLeft(2, '0');
  final String dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// Day separator date, e.g. `30 AUG 2026`. `''` for a non-positive epoch.
///
/// Device-local by interview decision D2 — the spec asked for a `System!B3`
/// offset, but that value has no path into the app (`grep -rn "#TIMEZONE"` =>
/// zero hits). Same convention as formatEpochHHmm / formatEpochTime.
///
/// try/catch because `Intl.defaultLocale` is mutated globally by `stringFormat`
/// (table_repository.dart) and an uninitialised locale makes DateFormat throw.
/// One bad locale must not take the whole card down.
String formatDayLabel(int epochMs) {
  if (epochMs <= 0) return '';
  try {
    return DateFormat(
      'dd MMM yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(epochMs)).toUpperCase();
  } catch (_) {
    return '';
  }
}

/// True when [epochMs] falls on [now]'s local calendar day.
bool isTodayEpoch(int epochMs, DateTime now) {
  if (epochMs <= 0) return false;
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

/// One rendered day bucket. [label] `''` means "emit no separator".
class TimelineDayGroup {
  final String dayKey;
  final String label;
  final List<Map<String, dynamic>> docs;
  const TimelineDayGroup(this.dayKey, this.label, this.docs);
}

/// Split [docs] into consecutive local-day runs, preserving order.
///
/// Consecutive runs rather than hash buckets: the list arrives sorted `t desc`,
/// so runs ARE the day buckets, and a tenant that sorts differently still gets
/// its own order back instead of a silent re-sort.
///
/// [todayPrefix] is `text` segment 3 (e.g. `HARI INI`); blank => the today
/// group shows the plain date.
List<TimelineDayGroup> groupDocsByDay(
  List<Map<String, dynamic>> docs,
  String timeField,
  String todayPrefix,
  DateTime now,
) {
  final List<TimelineDayGroup> out = [];
  // NULL sentinel, deliberately NOT a magic character: `''` IS a real day key
  // (dayKeyOf returns '' for every epoch <= 0), so no String value can safely
  // mean "no group open yet". `flush()` closes over this mutable local, and
  // Dart does not promote captured mutable locals, which is why the reads
  // below are written `currentKey?.isNotEmpty ?? false` and `currentKey ?? ''`
  // rather than relying on flow analysis.
  String? currentKey;
  List<Map<String, dynamic>> bucket = [];
  int bucketEpoch = 0;

  void flush() {
    if (bucket.isEmpty) return;
    String label = '';
    if (currentKey?.isNotEmpty ?? false) {
      final String date = formatDayLabel(bucketEpoch);
      if (date.isNotEmpty) {
        label = isTodayEpoch(bucketEpoch, now) && todayPrefix.trim().isNotEmpty
            ? '${todayPrefix.trim()} \u{00B7} $date' // middle dot
            : date;
      }
    }
    // TimelineDayGroup.dayKey stays a non-nullable String; the sentinel
    // collapses to '' here, which is also what a non-positive epoch yields.
    out.add(TimelineDayGroup(currentKey ?? '', label, bucket));
  }

  for (final Map<String, dynamic> doc in docs) {
    final int ms = docEpochMs(doc, timeField);
    final String key = dayKeyOf(ms);
    if (key != currentKey) {
      flush();
      currentKey = key;
      bucket = <Map<String, dynamic>>[];
      bucketEpoch = ms;
    }
    bucket.add(doc);
  }
  flush();
  return out;
}

// ─── chip inference (spec section 4) ───────────────────────────────────────

/// The rendered status chip.
class TimelineChip {
  final String label;
  final String tier;
  const TimelineChip(this.label, this.tier);
}

/// Infer the status chip from the TOP row of the already-sorted [sortedDocs].
///
/// No second query, and deliberately NO read of `workforce.st` — spec section 4
/// rejects it by name: `on`/`off` without a date cannot tell "just clocked out"
/// from "never clocked in", and this timeline is itself the answer.
///
/// Two asymmetric rules, made generic by chipMap ENTRY ORDER:
///   * entry 0 = the open / in-progress state -> shown with NO date condition
///     (night shift crosses midnight);
///   * every other entry = a terminal state -> shown ONLY when the top row's
///     local day is today.
/// Anything else (no rows, blank chipField, empty chipMap, unmapped value, or a
/// terminal state on a non-today row) -> [emptyLabel] with the `muted` tier.
TimelineChip inferChip({
  required List<Map<String, dynamic>> sortedDocs,
  required String chipField,
  required List<ChipEntry> chipMap,
  required String timeField,
  required String emptyLabel,
  required DateTime now,
}) {
  const TimelineChip nothingYet = TimelineChip('', 'muted');
  final TimelineChip empty = emptyLabel.trim().isEmpty
      ? nothingYet
      : TimelineChip(emptyLabel, 'muted');

  if (sortedDocs.isEmpty || chipField.isEmpty || chipMap.isEmpty) return empty;

  final Map<String, dynamic> top = sortedDocs.first;
  final int idx = chipIndexOf(
    chipMap,
    (top[chipField] ?? '').toString().trim(),
  );
  if (idx < 0) return empty;
  if (idx == 0) return TimelineChip(chipMap[0].label, chipMap[0].tier);
  if (isTodayEpoch(docEpochMs(top, timeField), now)) {
    return TimelineChip(chipMap[idx].label, chipMap[idx].tier);
  }
  return empty;
}
