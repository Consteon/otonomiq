import '../global.dart';

/// Structure-only parse of one decoded addToEvent block (a single `◆`-segment).
/// Splits by `⭘` (separator[8]); first part is the collection name; remaining
/// parts split at the first `◼` (separator[2]) into key/value. Never throws:
/// malformed parts (no `◼`) are skipped; unknown keys pass through.
Map<String, dynamic> parseAddToEvent(String body) {
  final hollow = separator[8]; // ⭘
  final square = separator[2]; // ◼
  final parts = body
      .split(hollow)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final result = <String, dynamic>{};
  if (parts.isEmpty) return result;
  result['_collection'] = parts.first;
  for (final part in parts.skip(1)) {
    final eq = part.indexOf(square);
    if (eq < 0) continue; // malformed, skip silently
    final key = part.substring(0, eq).trim();
    result[key] = part.substring(eq + 1);
  }
  return result;
}

/// Build the DSL suffix that injects notification fields (ntf/nm/dp/bcc)
/// into an existing addToEvent block. Returns '' when [notification] is
/// absent, not a Map, or has an empty mode.
///
/// [resolve] applies the same token pipeline the caller uses for addToEvent
/// values (replacePlaceholders + _resolveScreenTxMarkers). Notification
/// values intentionally skip resolveDriverCurlyTokens so that CF
/// per-recipient {field} tokens (e.g. {nama}) survive literally.
///
/// Separator glyphs literally present in the composed value are sanitized to
/// prevent DSL corruption when an author inlines a literal ◆-separated list
/// instead of using a cell-reference token:
///   separator[1] (◆) → ','   (spec §2 blesses comma for bcc)
///   separator[8] (⭘) → ' '   (prevents fake field boundary)
///   separator[2] (◼) → ' '   (prevents fake key/value split)
///   separator[0] (⬤) → ' '   (protects the OUTER tb segment frame, not the
///                             inner DSL: saveSend joins tableString/update/
///                             delete/event/updateEvent with ⬤, so a stray ⬤
///                             here shifts every later segment and the
///                             updateEventRow payload is silently dropped)
/// The ⬤ guard is the only one that also applies to [mode] — there it is
/// stripped, not spaced (see the comment at the mode assignment). The other
/// three are values-only, so an unknown mode is still written as-is.
/// Token-based values (e.g. ◁2▷) are inherently safe — their ◆ materializes
/// at sync-time resolveValueTokens, after the splitter and structural parse.
String buildNotificationSuffix(
  dynamic notification,
  String Function(String) resolve,
) {
  if (notification == null || notification is! Map) return '';

  final String hollow = separator[8]; // ⭘
  final String square = separator[2]; // ◼
  final String diamond = separator[1]; // ◆
  final String circle = separator[0]; // ⬤

  // mode is a fixed server literal (single/broadcast), not a token or user
  // input, so it skips decode/resolve and the ◆/⭘/◼ sanitizing that clean()
  // applies to values — "unknown mode written as-is" is a locked behavior.
  // The ONE exception is ⬤: it is U+2B24 (category So, NOT whitespace), so
  // trim() cannot remove it, and a raw typed ⬤ here would shift the outer tb
  // segment frame exactly as it would in a value. Stripped rather than
  // spaced — mode is an identifier-like token, not prose, so 'sing⬤le' ->
  // 'single' beats 'sing le' and cannot invent a word boundary. Strip before
  // trim so a mode of only ⬤ collapses to '' and takes the early return.
  final String mode = (notification['mode'] ?? '')
      .toString()
      .replaceAll(circle, '')
      .trim();
  if (mode.isEmpty) return '';

  // Decode server escapes, resolve tokens, then sanitize separator glyphs.
  String clean(String raw) {
    String val = autheniumDecode(raw) ?? '';
    val = resolve(val);
    val = val.replaceAll(diamond, ',');
    val = val.replaceAll(hollow, ' ');
    val = val.replaceAll(square, ' ');
    val = val.replaceAll(circle, ' ');
    return val;
  }

  // Whether a resolved value is usable for a user-facing field (nm/dp).
  // replacePlaceholders returns 'No-DATA' (null ref, api.dart:4217) or
  // 'NO-DATA' (out-of-bounds, api.dart:4227) on a mis-indexed token.
  // Omitting these lets the CF fall back to cn / default message (spec §2).
  // Trim only the TEST — a whitespace-only title must omit nm rather than
  // write an empty one; the emitted value itself stays untrimmed.
  bool usable(String v) =>
      v.trim().isNotEmpty && v != 'No-DATA' && v != 'NO-DATA';

  final buf = StringBuffer();
  buf.write('${hollow}ntf$square$mode');

  final String rawTitle = (notification['title'] ?? '').toString();
  if (rawTitle.isNotEmpty) {
    final String title = clean(rawTitle);
    if (usable(title)) {
      buf.write('${hollow}nm$square$title');
    }
  }

  final String rawMessage = (notification['message'] ?? '').toString();
  if (rawMessage.isNotEmpty) {
    final String message = clean(rawMessage);
    if (usable(message)) {
      buf.write('${hollow}dp$square$message');
    }
  }

  if (mode == 'broadcast') {
    final String rawTarget = (notification['target'] ?? '').toString();
    // Write bcc even when empty — CF logs WARN, no client-side validation.
    buf.write('${hollow}bcc$square${clean(rawTarget)}');
  }

  return buf.toString();
}
