import 'dart:ui' show Color;

import 'package:intl/intl.dart';

import 'panel_card_support.dart';
import 'statistic_card_support.dart';
import 'timeline_periodic_support.dart';

// ---- Category palette -------------------------------------------------------

/// 8 distinct category colors for badge pills. Assigned to badgeMap values in
/// ORDER of keys (deterministic within a config). Wraps via modulo.
const List<Color> kCategoryColors = [
  Color(0xFF2563EB), // blue
  Color(0xFFD97706), // amber
  Color(0xFF16A34A), // green
  Color(0xFFDC2626), // red
  Color(0xFF7C3AED), // violet
  Color(0xFF0891B2), // cyan
  Color(0xFFDB2777), // pink
  Color(0xFF65A30D), // lime
];

/// Soft background tints matching [kCategoryColors], same index.
const List<Color> kCategoryBgColors = [
  Color(0xFFDBEAFE), // blue bg
  Color(0xFFFEF3C7), // amber bg
  Color(0xFFDCFCE7), // green bg
  Color(0xFFFEE2E2), // red bg
  Color(0xFFEDE9FE), // violet bg
  Color(0xFFCFFAFE), // cyan bg
  Color(0xFFFCE7F3), // pink bg
  Color(0xFFECFCCB), // lime bg
];

// ---- Badge map parsing ------------------------------------------------------

/// Parsed badge map entry: original value, display label, palette index.
class BadgeEntry {
  final String value;
  final String label;
  final int index;
  const BadgeEntry(this.value, this.label, this.index);
}

/// Parse `badgeMap` config: `"value◼Label★value◼Label★..."`.
///
/// [raw] must already be `autheniumDecode`d by the caller.
/// Returns an ordered list (for palette assignment) and populates [lookup]
/// for O(1) value->BadgeEntry retrieval.
///
/// Length-guards every split segment: `seg.length > 1 ? seg[1] : seg[0]`
/// (label defaults to value if ◼ missing).
List<BadgeEntry> parseBadgeMap(String raw, Map<String, BadgeEntry> lookup) {
  final List<BadgeEntry> entries = [];
  if (raw.trim().isEmpty) return entries;
  final List<String> parts = raw.split('\u{2605}'); // ★
  for (int i = 0; i < parts.length; i++) {
    final List<String> seg = parts[i].split('\u{25FC}'); // ◼
    final String value = seg.isNotEmpty ? seg[0].trim() : '';
    if (value.isEmpty) continue;
    final String label = seg.length > 1 ? seg[1].trim() : value;
    final BadgeEntry entry = BadgeEntry(value, label, i);
    entries.add(entry);
    lookup[value] = entry;
  }
  return entries;
}

/// Foreground color for a badge value. Mapped values get a category palette
/// color by their index in the badgeMap; unmapped values get [kNeutralColor].
Color badgeFgColor(BadgeEntry? entry) {
  if (entry == null) return kNeutralColor;
  return kCategoryColors[entry.index % kCategoryColors.length];
}

/// Background color for a badge value. Mapped values get a category palette
/// background; unmapped values get [kNeutralBgColor].
Color badgeBgColor(BadgeEntry? entry) {
  if (entry == null) return kNeutralBgColor;
  return kCategoryBgColors[entry.index % kCategoryBgColors.length];
}

// ---- Condition relabel (condMap) --------------------------------------------

/// Relabel the canonical condition value `cd` in [doc] via [lookup]
/// (produced by [parseBadgeMap] from the `condMap` config).
///
/// Returns [doc] UNCHANGED (same instance) when:
/// - [lookup] is empty (no condMap configured -- zero-regression path), or
/// - the doc's `cd` value is not in the map (unmapped -> raw passthrough).
///
/// Returns a SHALLOW COPY with only `cd` replaced when mapped. The caller's
/// original doc is never mutated -- grouping/badge/conditions keep seeing
/// canonical raw values.
Map<String, dynamic> applyCondMap(
  Map<String, dynamic> doc,
  Map<String, BadgeEntry> lookup,
) {
  if (lookup.isEmpty) return doc;
  final BadgeEntry? e = lookup[(doc['cd'] ?? '').toString().trim()];
  if (e == null) return doc;
  return Map<String, dynamic>.from(doc)..['cd'] = e.label;
}

// ---- Configurable time field ------------------------------------------------

/// Read epoch (ms) from a configurable field. Falls back to the standard
/// `eventEpoch` (t/et) when [field] is empty or the field value doesn't parse.
int docEpoch(Map<String, dynamic> doc, String field) {
  if (field.isNotEmpty) {
    final int? v = int.tryParse((doc[field] ?? '').toString());
    if (v != null) return v;
  }
  return eventEpoch(doc);
}

/// Format an epoch (ms) as bare `HH:mm` (local timezone). Returns empty
/// string for non-positive epoch (guard against missing/zero time data).
String formatEpochHHmm(int epochMs) {
  if (epochMs <= 0) return '';
  return DateFormat(
    'HH:mm',
  ).format(DateTime.fromMillisecondsSinceEpoch(epochMs));
}

// ---- Conditions with {curly} fail-closed ------------------------------------

final RegExp _unresolvedCurly = RegExp(r'\{[a-zA-Z_]\w*\}');

/// Resolve `{key}` tokens in [rawConditions] from [screenTx] bare keys, then
/// check for unresolved tokens. Returns the resolved string, or `null` if any
/// `{key}` remains unresolved (fail-closed: caller should return empty data).
///
/// Uses [resolveScreenTxTokens] (statistic_card_support.dart) which reads ALL
/// screenTx bare keys directly with NO reserved switch cases. This is
/// INTENTIONAL: `resolveDriverCurlyTokens` (driver_home_support.dart) has a
/// hardcoded `case 'vehicleId'` that reads from DriverHomeState (the driver
/// session vehicle), which SHADOWS the bare screenTx key dispatched by
/// routeParams. Admin/supervisor users have no driver session, so that path
/// returns empty and the token stays literal -- breaking the first consumer.
/// `resolveScreenTxTokens` avoids this by reading `screenTx['vehicleId']`
/// directly (the value routeParams dispatched).
///
/// The caller is responsible for `autheniumDecode` BEFORE calling this.
String? resolveConditionsFailClosed(
  String rawConditions,
  Map<String, dynamic> screenTx,
) {
  final String resolved = resolveScreenTxTokens(rawConditions, screenTx);
  if (_unresolvedCurly.hasMatch(resolved)) return null;
  return resolved;
}

// ---- Grouping ---------------------------------------------------------------

/// A group of docs sharing the same [groupField] value.
class LedgerGroup {
  final String key;
  final List<Map<String, dynamic>> docs;
  final int maxEpoch;
  const LedgerGroup(this.key, this.docs, this.maxEpoch);
}

/// Group [docs] by [groupField], sort docs within each group by [timeField]
/// desc, sort groups by max epoch desc. Each group's [maxEpoch] is the highest
/// epoch among its members.
///
/// [timeField] is passed to [docEpoch] for epoch extraction.
List<LedgerGroup> groupDocs(
  List<Map<String, dynamic>> docs,
  String groupField,
  String timeField,
) {
  final Map<String, List<Map<String, dynamic>>> buckets = {};
  for (final doc in docs) {
    final String key = (doc[groupField] ?? '').toString();
    (buckets[key] ??= []).add(doc);
  }

  final List<LedgerGroup> groups = [];
  for (final entry in buckets.entries) {
    final List<Map<String, dynamic>> members = entry.value;
    // Sort members by epoch desc (newest first within group).
    members.sort(
      (a, b) => docEpoch(b, timeField).compareTo(docEpoch(a, timeField)),
    );
    int maxEp = 0;
    for (final m in members) {
      final int ep = docEpoch(m, timeField);
      if (ep > maxEp) maxEp = ep;
    }
    groups.add(LedgerGroup(entry.key, members, maxEp));
  }
  // Sort groups by max epoch desc (newest group first).
  groups.sort((a, b) => b.maxEpoch.compareTo(a.maxEpoch));
  return groups;
}

/// A section of groups sharing the same [groupField2] value. Used for
/// 2-level grouping: section (by groupField2) -> cards (by groupField).
class LedgerSection {
  final String key;
  final List<LedgerGroup> groups;

  /// Total docs across all groups in this section.
  final int sectionCount;

  /// Number of event-card groups in this section.
  final int groupCount;

  /// Earliest doc epoch in this section (trip start; for {sectionTime}).
  final int minEpoch;

  /// Latest doc epoch in this section (for sort order).
  final int maxEpoch;

  const LedgerSection(
    this.key,
    this.groups,
    this.sectionCount,
    this.groupCount,
    this.minEpoch,
    this.maxEpoch,
  );
}

/// Two-level grouping: first by [groupField2] (sections), then by
/// [groupField] within each section (cards). Reuses [groupDocs] for the
/// inner grouping.
///
/// Sections sorted by [maxEpoch] desc (newest section first). Cards within
/// each section are sorted by [groupDocs] (max epoch desc). If [groupField]
/// is empty, each doc becomes its own single-doc group within the section
/// (graceful degradation).
///
/// Returns empty list for empty [docs].
List<LedgerSection> groupSections(
  List<Map<String, dynamic>> docs,
  String groupField2,
  String groupField,
  String timeField,
) {
  if (docs.isEmpty) return const [];

  // Bucket docs by groupField2 value.
  final Map<String, List<Map<String, dynamic>>> sectionBuckets = {};
  for (final doc in docs) {
    final String sKey = (doc[groupField2] ?? '').toString();
    (sectionBuckets[sKey] ??= []).add(doc);
  }

  final List<LedgerSection> sections = [];
  for (final entry in sectionBuckets.entries) {
    final List<Map<String, dynamic>> sectionDocs = entry.value;

    // Inner grouping by groupField. If groupField is empty, each doc is its
    // own group (graceful degradation -- no crash).
    final List<LedgerGroup> groups = groupField.isNotEmpty
        ? groupDocs(sectionDocs, groupField, timeField)
        : (sectionDocs
              .map((d) => LedgerGroup('', [d], docEpoch(d, timeField)))
              .toList()
            ..sort((a, b) => b.maxEpoch.compareTo(a.maxEpoch)));

    // Aggregate: sectionCount = total docs, groupCount = number of cards.
    final int sectionCount = sectionDocs.length;
    final int groupCount = groups.length;

    // Min and max epoch across ALL docs in section.
    int minEp = 0;
    int maxEp = 0;
    bool first = true;
    for (final doc in sectionDocs) {
      final int ep = docEpoch(doc, timeField);
      if (first || ep < minEp) minEp = ep;
      if (first || ep > maxEp) maxEp = ep;
      first = false;
    }

    sections.add(
      LedgerSection(entry.key, groups, sectionCount, groupCount, minEp, maxEp),
    );
  }

  // Sort sections by max epoch desc (newest first).
  sections.sort((a, b) => b.maxEpoch.compareTo(a.maxEpoch));
  return sections;
}

/// Resolve a diamond-segmented template against a doc. Returns the list of
/// resolved segments. Length-guard every index access on the result.
///
/// Example: `"<in> x<qt>◆<cd>"` -> `["Aqua Galon 19 L x3", "penuh"]`.
List<String> resolveSegmentedTemplate(
  String template,
  Map<String, dynamic> doc,
  Map<String, String> computed,
) {
  final String resolved = resolveMapTokens(template, doc, computed);
  // Split on ◆ (U+25C6, diamond).
  return resolved.split('\u{25C6}');
}
