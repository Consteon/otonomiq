import 'admin_home_support.dart'; // evaluateGate

// ─── Note template resolution ───────────────────────────────────────────────

/// Mirrors panel_card_support.dart:336 — kept character-identical on purpose.
final RegExp _noteAngleToken = RegExp(r'<([a-zA-Z][a-zA-Z0-9]*)>');

/// Resolve an optional display template (`note`). Returns `''` when the
/// template is blank, or when it contains `<field>` tokens and ANY of them
/// is missing/blank on [doc] — a half-resolved line ("Level  dari ") is
/// worse than no line. A token-free template renders as-is.
String resolveNoteTemplate(String template, Map<String, dynamic> doc) {
  if (template.trim().isEmpty) return '';
  final Iterable<RegExpMatch> matches = _noteAngleToken.allMatches(template);
  if (matches.isEmpty) return template; // token-free note — render as-is
  for (final m in matches) {
    final dynamic val = doc[m.group(1)];
    if (val == null || val.toString().trim().isEmpty) return '';
  }
  // All tokens present and non-empty — substitute.
  return template.replaceAllMapped(_noteAngleToken, (m) {
    final dynamic val = doc[m.group(1)];
    return val == null ? '' : val.toString();
  });
}

// ─── LIST_CARD support — pure parsers ─────────────────────────────────────

/// Parsed badge definition from the `badgeMap` config field.
class BadgeEntry {
  final String value;
  final String label;
  final String tier; // danger|warn|ok|info
  const BadgeEntry(this.value, this.label, this.tier);
}

/// Parsed group label from the `groupLabels` config field.
class GroupLabelEntry {
  final String value;
  final String label;
  const GroupLabelEntry(this.value, this.label);
}

/// Parsed stats box definition from the `stats` config field.
class StatsDef {
  final String label;
  final String filter; // gate DSL string; empty = count all
  const StatsDef(this.label, this.filter);
}

/// Parse `badgeMap`: `value◼Label◼tier★value2◼Label2◼tier2`.
///
/// Tier defaults to `'info'` when absent or empty. `'neutral'` aliases to
/// `'info'` (panel_card_support statusColor/statusBgColor handle danger/warn/
/// ok/info — neutral is not a known tier there, so we map it to info which
/// renders as blue, the closest semantic neutral).
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
List<BadgeEntry> parseBadgeMap(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<BadgeEntry> out = [];
  for (final part in raw.split('\u{2605}')) {
    // ★ separates entries
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final List<String> segs = trimmed.split('\u{25FC}'); // ◼
    final String value = segs.isNotEmpty ? segs[0].trim() : '';
    if (value.isEmpty) continue;
    final String label = segs.length > 1
        ? segs[1].trim()
        : value; // ponytail: missing label = value
    String tier = segs.length > 2 ? segs[2].trim().toLowerCase() : 'info';
    if (tier == 'neutral') tier = 'info';
    if (tier.isEmpty) tier = 'info';
    out.add(BadgeEntry(value, label, tier));
  }
  return out;
}

/// Parse `groupLabels`: `value◼Label★value2◼Label2`.
///
/// Order preserved — sections render in this order. Values in the data that
/// are NOT listed here go into a catch-all section at the bottom (the widget
/// appends them after the ordered keys).
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
List<GroupLabelEntry> parseGroupLabels(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<GroupLabelEntry> out = [];
  for (final part in raw.split('\u{2605}')) {
    // ★ separates entries
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}'); // first ◼
    if (sep < 0) {
      // no ◼ — value doubles as label
      out.add(GroupLabelEntry(trimmed, trimmed));
      continue;
    }
    final String value = trimmed.substring(0, sep).trim();
    final String label = trimmed.substring(sep + 1).trim();
    if (value.isEmpty) continue;
    out.add(GroupLabelEntry(value, label.isEmpty ? value : label));
  }
  return out;
}

/// Parse `groupRoutes`: `value◼route★value2◼route2`.
///
/// Returns a map from group value to route string. Entries without `◼` are
/// **skipped** (fail-closed: malformed entry = read-only group, not a
/// fallback to the global route). Empty values before `◼` are skipped.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
Map<String, String> parseGroupRoutes(String raw) {
  if (raw.trim().isEmpty) return const {};
  final Map<String, String> out = {};
  for (final part in raw.split('\u{2605}')) {
    // ★ separates entries
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}'); // first ◼
    if (sep < 0) continue; // ponytail: no ◼ — skip (fail-closed, interview #2)
    final String value = trimmed.substring(0, sep).trim();
    final String route = trimmed.substring(sep + 1).trim();
    if (value.isEmpty) continue;
    out[value] = route;
  }
  return out;
}

/// Effective route for one group section.
///
/// - `null`  -> no `groupRoutes` configured; caller falls back to the global
///              `route` (spec §3: groupBy filled + groupRoutes empty = all
///              groups use `route`).
/// - `''`    -> group is not in the map -> read-only (no tap, no ripple).
/// - other   -> that group's own route.
String? resolveGroupRoute(Map<String, String> groupRoutes, String groupKey) =>
    groupRoutes.isEmpty ? null : (groupRoutes[groupKey] ?? '');

/// Parse `stats`: `Label◼filter★Label2◼filter2`.
///
/// **Split each box at the FIRST ◼ only** — the filter itself may contain ◼
/// as part of the gate DSL field/value separator (e.g. `On Job◼ast◼present`
/// → label `"On Job"`, filter `"ast◼present"`).
///
/// Empty filter after ◼ (e.g. `Total◼`) = count all rows.
/// No ◼ at all (e.g. `Total`) = label only, empty filter.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
List<StatsDef> parseStatsDefs(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<StatsDef> out = [];
  for (final part in raw.split('\u{2605}')) {
    // ★ separates boxes
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}'); // FIRST ◼ only
    if (sep < 0) {
      // no ◼ — label only, count all
      out.add(StatsDef(trimmed, ''));
      continue;
    }
    final String label = trimmed.substring(0, sep).trim();
    final String filter = trimmed.substring(sep + 1).trim();
    if (label.isEmpty) continue;
    out.add(StatsDef(label, filter));
  }
  return out;
}

/// Compute stats counts. For each [StatsDef]:
///   - empty filter → count all docs.
///   - non-empty filter → count docs matching the filter via [evaluateGate].
///
/// Stats filters are literal DSL (no `{token}` resolution needed — spec §5
/// examples are all literal field◼value).
List<int> computeStatsCounts(
  List<StatsDef> defs,
  List<Map<String, dynamic>> docs,
) {
  return defs.map((d) {
    if (d.filter.isEmpty) return docs.length;
    return docs.where((doc) => evaluateGate(doc, d.filter)).length;
  }).toList();
}

/// Lookup a badge entry by [value]. Returns null if not found or value empty.
BadgeEntry? lookupBadge(List<BadgeEntry> entries, String value) {
  final String v = value.trim();
  if (v.isEmpty || entries.isEmpty) return null;
  for (final e in entries) {
    if (e.value == v) return e;
  }
  return null;
}

/// Parsed row definition from the `rows` config field.
class RowDef {
  final String label;
  final String template; // <field> template string
  const RowDef(this.label, this.template);
}

/// Parse `rows`: `Label◼template★Label2◼template2★…`.
///
/// **Split each row at the FIRST ◼ only** — the template itself may contain ◼
/// (e.g. `Jam kerja◼<st>–<et>` → label `"Jam kerja"`, template `"<st>–<et>"`).
///
/// No ◼ at all (e.g. `Label`) = label only, empty template.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
List<RowDef> parseRowDefs(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<RowDef> out = [];
  for (final part in raw.split('\u{2605}')) {
    // ★ separates rows
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}'); // FIRST ◼ only
    if (sep < 0) {
      // no ◼ — label only, empty template
      out.add(RowDef(trimmed, ''));
      continue;
    }
    final String label = trimmed.substring(0, sep).trim();
    final String template = trimmed.substring(sep + 1).trim();
    if (label.isEmpty) continue;
    out.add(RowDef(label, template));
  }
  return out;
}

// ─── Slot gate helpers (approve-leave-gating-and-note) ──────────────────

/// Parsed `gateSlot` config: `slotField◆pointerField◆levelField`.
class GateSlotConfig {
  final String slotField;
  final String pointerField;
  final String levelField;
  const GateSlotConfig(this.slotField, this.pointerField, this.levelField);

  /// True when gating is effectively OFF (incomplete config).
  /// Both pointerField AND levelField must be empty to disable — having only
  /// one of the two is still a valid (concrete-only or wildcard-only) config.
  bool get isEmpty =>
      slotField.isEmpty || (pointerField.isEmpty && levelField.isEmpty);
}

/// Parsed slot terms from a grant doc's slot field value.
class SlotTerms {
  final Set<String> concrete;
  final Set<String> wildcardLevels;
  const SlotTerms(this.concrete, this.wildcardLevels);
}

/// Parse `gateSlot` config: `slotField◆pointerField◆levelField`.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling (use `_cfg()`).
/// Length-guarded: short arrays → empty string defaults.
GateSlotConfig parseGateSlot(String decoded) {
  if (decoded.trim().isEmpty) return const GateSlotConfig('', '', '');
  final List<String> segs = decoded.split('\u{25C6}'); // ◆
  return GateSlotConfig(
    segs.isNotEmpty ? segs[0].trim() : '',
    segs.length > 1 ? segs[1].trim() : '',
    segs.length > 2 ? segs[2].trim() : '',
  );
}

/// Parse slot terms from a grant doc's raw slot field value.
///
/// Split on `|`, trim each term, drop empties.
/// Term starting with `*-` (length > 2) → wildcard: level = substring after
/// `*-`, added to [wildcardLevels].
/// Every other term → concrete (compared verbatim against pointerField).
///
/// Assumption: only `*-{lvl}` is a wildcard form; `{cc}-*` and `*-*` are NOT
/// wildcards — treated as concrete (they simply will not match anything).
SlotTerms parseSlotTerms(String rawSlotValue) {
  final Set<String> concrete = {};
  final Set<String> wildcardLevels = {};
  for (final term in rawSlotValue.split('|')) {
    final String t = term.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('*-') && t.length > 2) {
      wildcardLevels.add(t.substring(2).trim());
    } else {
      concrete.add(t);
    }
  }
  return SlotTerms(concrete, wildcardLevels);
}

/// Filter docs by slot gate.
///
/// A doc is visible iff:
///   `row[pointerField].toString().trim()` is in [concrete]
///   OR `row[levelField].toString().trim()` is in [wildcardLevels].
///
/// Type tolerance: all comparisons via `.toString().trim()` (D8).
/// No self-approve exclusion (D11): gating is purely slot-based.
///
/// Returns empty list when both sets are empty (no valid slots → no visible
/// docs).
List<Map<String, dynamic>> filterBySlotGate(
  List<Map<String, dynamic>> docs,
  Set<String> concrete,
  Set<String> wildcardLevels,
  String pointerField,
  String levelField,
) {
  // ponytail: growable (NOT const []) — callers .sort() this result
  if (concrete.isEmpty && wildcardLevels.isEmpty) {
    return <Map<String, dynamic>>[];
  }
  return docs.where((doc) {
    final String pointer = (doc[pointerField] ?? '').toString().trim();
    final String level = (doc[levelField] ?? '').toString().trim();
    return isVisibleBySlotGate(pointer, level, concrete, wildcardLevels);
  }).toList();
}

/// Single-value slot gate predicate.
///
/// Used by the detail-page choke point (StickyBarRenderer._buildApproval)
/// where the pointer and level arrive as scalar values resolved from the
/// displayed row, not as keyed map fields.
///
/// Also called by [filterBySlotGate] so the visibility rule has ONE definition.
///
/// Returns false when both sets are empty (fail-closed: no valid slots = not
/// visible). Empty pointer/level = not visible (covers direct navigation and
/// pre-publish state).
bool isVisibleBySlotGate(
  String pointerValue,
  String levelValue,
  Set<String> concrete,
  Set<String> wildcardLevels,
) {
  if (concrete.isEmpty && wildcardLevels.isEmpty) return false;
  if (concrete.contains(pointerValue)) return true;
  return wildcardLevels.contains(levelValue);
}
