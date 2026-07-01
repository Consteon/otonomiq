import '../global.dart';
import 'add_to_event.dart';

/// Parsed `updateEventRow` statement: a keyed sparse-merge target.
class UpdateEventTarget {
  /// `<tableDocId>//<subColl>` routing prefix (line-1 collection).
  final String collection;

  /// Firebase table node id override (the `tablevid` header pair).
  final String tablevid;

  /// AND-conditions selecting the doc(s) to merge into.
  final List<MapEntry<String, String>> conditions;

  /// Char-code keys to merge (sparse — only these change).
  final Map<String, String> body;

  const UpdateEventTarget(
    this.collection,
    this.tablevid,
    this.conditions,
    this.body,
  );
}

/// Split a `search` payload into AND conditions.
/// `vid★X☆sv★Y` -> [(vid,X),(sv,Y)]. `☆`=separator[6] joins conditions,
/// `★`=separator[3] splits key/value. Single condition (no `☆`) -> list of one.
/// Conditions missing `★` are skipped silently.
List<MapEntry<String, String>> parseSearchClause(String payload) {
  final star = separator[3]; // ★
  final wstar = separator[6]; // ☆
  final out = <MapEntry<String, String>>[];
  if (payload.trim().isEmpty) return out;
  for (final cond in payload.split(wstar)) {
    final sep = cond.indexOf(star);
    if (sep < 0) continue; // malformed, skip
    final key = cond.substring(0, sep).trim();
    final value = cond.substring(sep + 1).trim();
    if (key.isEmpty) continue;
    out.add(MapEntry(key, value));
  }
  return out;
}

/// Parse one decoded `◆`-block of an updateEventRow statement. Reuses
/// `parseAddToEvent` for the `⭘key◼value` extraction, then lifts out the
/// `tablevid` + `search` header pairs; everything else is the sparse body.
UpdateEventTarget parseUpdateEventRow(String block) {
  final parsed = parseAddToEvent(block);
  final collection = (parsed['_collection'] ?? '').toString();
  final tablevid = (parsed['tablevid'] ?? '').toString();
  final conditions = parseSearchClause((parsed['search'] ?? '').toString());
  final body = <String, String>{};
  parsed.forEach((k, v) {
    if (k == '_collection' || k == 'tablevid' || k == 'search') return;
    body[k] = v.toString();
  });
  return UpdateEventTarget(collection, tablevid, conditions, body);
}
