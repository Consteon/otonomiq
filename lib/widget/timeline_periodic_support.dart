import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';

import '../global.dart' show blackDiamond;
import 'dsl_eq.dart';
import 'panel_card_support.dart';

/// Relative timestamp for a timeline entry, computed from the event epoch.
/// Same calendar day → "HH:mm hari ini"; yesterday → "Kemarin HH:mm"; else
/// "N hari lalu" (N = whole-day difference). Uses the device clock / local tz.
String relativeTimestamp(int tMs, int nowMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(tMs);
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final int dayDiff = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  final String hhmm = DateFormat('HH:mm').format(t);
  if (dayDiff <= 0) return '$hhmm hari ini';
  if (dayDiff == 1) return 'Kemarin $hhmm';
  return '$dayDiff hari lalu';
}

/// Capture method for a timeline entry. `label` is the display text; `isQr`
/// drives the row icon (QR code vs text-cursor).
class MethodInfo {
  final String label;
  final bool isQr;
  const MethodInfo(this.label, this.isQr);
}

/// `lq` non-empty → "Scan QR" (QR-scanned), empty → "Lokasi diketik" (typed).
/// Always appends " + foto" (per dev spec §5.3).
MethodInfo deriveMethod(String lq) {
  final bool isQr = lq.trim().isNotEmpty;
  final String base = isQr ? 'Scan QR' : 'Lokasi diketik';
  return MethodInfo('$base + foto', isQr);
}

/// Gap pill text between two consecutive (newer, older) entries. Below `gapMs`
/// → "" (no pill); otherwise always "Jeda N jam" (whole hours, per dev spec §5.2).
String gapLabel(int newerT, int olderT, int gapMs) {
  final int gap = newerT - olderT;
  if (gap < gapMs) return '';
  return 'Jeda ${gap ~/ 3600000} jam';
}

/// Resolve `<key>` markers in `raw` against `screenTx` (missing → left literal).
String resolveAngleTokens(String raw, Map<String, dynamic> screenTx) {
  return raw.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
    final v = screenTx[m.group(1)];
    return v == null ? m.group(0)! : v.toString();
  });
}

final RegExp _condPair = RegExp(r'[◀◁]([a-zA-Z][a-zA-Z0-9]*)[▶▷]◼([^◀◁▶▷\]]*)');

/// Filter event docs by a multi-field AND equality parsed from
/// `[[◀field▶◼value◀field▶◼value]]`. `<key>` values resolve from `screenTx`
/// first. Empty conditions → unchanged; any value still containing `<` (an
/// unresolvable token) → no match. Equality only.
List<Map<String, dynamic>> filterEventsByConditions(
  List<Map<String, dynamic>> events,
  String rawConditions,
  Map<String, dynamic> screenTx,
) {
  if (rawConditions.trim().isEmpty) return events;
  final String resolved = resolveAngleTokens(rawConditions, screenTx);
  final List<MapEntry<String, String>> conds = [];
  for (final m in _condPair.allMatches(resolved)) {
    conds.add(MapEntry(m.group(1)!.trim(), m.group(2)!.trim()));
  }
  if (conds.isEmpty) return events;
  if (conds.any((c) => c.value.isEmpty || c.value.contains('<')))
    return const [];
  return events.where((e) {
    for (final c in conds) {
      if (!eq((e[c.key] ?? '').toString().trim(), c.value)) return false;
    }
    return true;
  }).toList();
}

/// Neutral-gray foreground for status values outside ok/warn/danger.
const Color kNeutralColor = Color(0xFF6B7280);

/// Neutral-gray background for status values outside ok/warn/danger.
const Color kNeutralBgColor = Color(0xFFF3F4F6);

const Set<String> _knownStatuses = {'ok', 'warn', 'danger'};

/// Dot / badge foreground color.
///
/// When [statusField] is non-null, reads `doc[statusField]`, normalizes it,
/// and maps through [statusColor] for known statuses (ok/warn/danger).
/// Unknown or empty values -> [kNeutralColor].
///
/// When [statusField] is null (patrol mode), derives color from [evidence]:
/// `'Bukti kuat'` -> ok (green), else -> warn (amber).
Color resolveStatusColor(
  String? statusField,
  Map<String, dynamic> doc,
  String evidence,
) {
  if (statusField != null) {
    final String raw = (doc[statusField] ?? '').toString();
    final String norm = normalizeStatus(raw);
    if (norm.isEmpty || !_knownStatuses.contains(norm)) return kNeutralColor;
    return statusColor(norm);
  }
  return statusColor(evidence == 'Bukti kuat' ? 'ok' : 'warn');
}

/// Dot / badge background color. Same routing logic as [resolveStatusColor].
Color resolveStatusBgColor(
  String? statusField,
  Map<String, dynamic> doc,
  String evidence,
) {
  if (statusField != null) {
    final String raw = (doc[statusField] ?? '').toString();
    final String norm = normalizeStatus(raw);
    if (norm.isEmpty || !_knownStatuses.contains(norm)) return kNeutralBgColor;
    return statusBgColor(norm);
  }
  return statusBgColor(evidence == 'Bukti kuat' ? 'ok' : 'warn');
}

/// True when [badgeTemplate] contains the `{evidence}` computed token.
/// Used to gate rendering of shield icons (verified_user / gpp_maybe).
bool badgeContainsEvidence(String badgeTemplate) =>
    badgeTemplate.contains('{evidence}');

/// True when [textTemplate] contains the `{method}` computed token.
/// Used to gate rendering of the method icon (qr_code_2 / text_fields).
bool textContainsMethod(String textTemplate) =>
    textTemplate.contains('{method}');

/// Every whitespace run, for the "did any token contribute ink?" test below.
final RegExp _whitespaceRun = RegExp(r'\s+');

String _squeezed(String s) => s.replaceAll(_whitespaceRun, '');

/// Resolve [template] exactly as [resolveMapTokens] does, but BLANK any
/// ◆-segment whose tokens ALL resolved empty. A segment holding no token at all
/// is kept verbatim, so static labels and static punctuation are untouched.
///
/// Returns a JOINED string, not a list, because the caller still hands it to
/// `diamondTextToList`. Split the RAW template, resolve each segment, re-join:
/// for a template separated by real `◆` only, the string reaching
/// `diamondTextToList` with nothing
/// blanked is BYTE-IDENTICAL to the old `resolveMapTokens(whole)` input, so a
/// doc value that itself carries a `◆` still expands into extra slots and no
/// slot index can shift. (`resolveMapTokens` is a position-independent
/// `replaceAll`, and no token can span a separator -- `<...>` accepts only
/// `[a-zA-Z][a-zA-Z0-9]*`.)
///
/// ★ It is NOT byte-identical when a template MIXES a real `◆` with a literal
/// `_u25C6_`, AND some resolved value breaks `jsonDecode` -- a `"`, an INVALID
/// escape such as `\d`, or a raw control character. A VALID escape like `\n`
/// does NOT throw (measured), so `\` alone is not the trigger.
/// `diamondTextToList` has two paths: its `jsonDecode` path
/// honours `_u25C6_`, its `catch` fallback is a plain `split('◆')` that does
/// not. A quote in ANY value -- the officer's free-text note is the realistic
/// one -- throws into that fallback, where the old code saw the `_u25C6_` as
/// literal text and this one has already turned it into a separator. Result:
/// one EXTRA segment, so a later slot can fall past `at(3)` and `_buildEntry`,
/// which renders exactly four, never shows it.
///
/// Deliberately not "fixed" here: matching the old behaviour would mean
/// replicating `diamondTextToList`'s own internal inconsistency inside this
/// helper, and the root -- one quote in one data value re-segmenting the whole
/// string for EVERY widget that calls `diamondTextToList` -- is a pre-existing,
/// app-wide bug. A uniformly `_u25C6_`-escaped template is an IMPROVEMENT under
/// the same trigger (the old code collapsed the row into one garbage segment
/// showing the literal escapes), so do not "restore" that either. Pinned by
/// `a MIXED-separator template with a quoted value is a KNOWN divergence` in
/// test/timeline_periodic_support_test.dart.
///
/// The raw split is deliberately NOT `diamondTextToList`: that one jsonDecodes
/// its input, and decoding here plus decoding again at the call site would
/// unescape a `\n` / `\\` in the template twice. It DOES honour the server's
/// `_u25C6_` escape, which is the only reason a plain `split` is wrong.
///
/// "Is it a token?" and "did it resolve empty?" are both answered by running
/// the SAME [resolveMapTokens] a second time against an empty doc and a blanked
/// [computed], so this can never drift from the real token grammar:
///  * the blank pass can only SHRINK a segment, so a shorter result means at
///    least one `<field>`, or a `{key}` that [computed] actually holds, fired;
///  * deleting every whitespace character is a concatenation homomorphism, so
///    the two passes squeeze to the same string exactly when every token
///    resolved to nothing but whitespace.
///
/// A `{key}` ABSENT from [computed] is left literal by [resolveMapTokens]. It is
/// therefore visible text, not a token, and never blanks its segment.
String resolveHidingEmptySegments(
  String template,
  Map<String, dynamic> doc,
  Map<String, String> computed,
) {
  final List<String> rawSegments = template
      .replaceAll(blackDiamond, '_u25C6_')
      .split('_u25C6_');
  final Map<String, String> blankComputed = <String, String>{
    for (final String k in computed.keys) k: '',
  };
  final List<String> out = <String>[];
  for (final String segment in rawSegments) {
    final String real = resolveMapTokens(segment, doc, computed);
    final String blank = resolveMapTokens(
      segment,
      const <String, dynamic>{},
      blankComputed,
    );
    final bool hasToken = blank.length < segment.length;
    final bool allEmpty = _squeezed(real) == _squeezed(blank);
    out.add(hasToken && allEmpty ? '' : real);
  }
  return out.join(blackDiamond);
}
