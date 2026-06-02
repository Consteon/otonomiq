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
