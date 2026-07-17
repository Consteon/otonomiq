import 'admin_home_support.dart'; // evaluateGate

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
    final String label =
        segs.length > 1 ? segs[1].trim() : value; // ponytail: missing label = value
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
    List<StatsDef> defs, List<Map<String, dynamic>> docs) {
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
