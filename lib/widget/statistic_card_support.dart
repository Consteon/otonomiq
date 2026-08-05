import 'dsl_eq.dart';
import 'panel_card_support.dart';

/// One option in the LIST_STATISTIC_CARD period selector.
class PeriodOption {
  final String label;
  final int ms;
  const PeriodOption(this.label, this.ms);
}

/// Parse the `period` config `label◼ms★label◼ms...`. Skips entries missing a
/// `◼` or whose ms is not an integer. Caller decodes (autheniumDecode) first.
List<PeriodOption> parsePeriods(String raw) {
  final List<PeriodOption> out = [];
  if (raw.trim().isEmpty) return out;
  for (final part in raw.split('★')) {
    final seg = part.split('◼');
    if (seg.length < 2) continue;
    final int? ms = int.tryParse(seg[1].trim());
    if (ms == null) continue;
    out.add(PeriodOption(seg[0].trim(), ms));
  }
  return out;
}

/// One summary stat box: a `{token}` template + its label.
class StatSpec {
  final String template;
  final String label;
  const StatSpec(this.template, this.label);
}

/// Parse the `stats` config `template◆label★template◆label...`. Skips entries
/// with an empty template.
List<StatSpec> parseStatSpecs(String raw) {
  final List<StatSpec> out = [];
  if (raw.trim().isEmpty) return out;
  for (final part in raw.split('★')) {
    final seg = part.split('◆');
    if (seg.isEmpty || seg[0].trim().isEmpty) continue;
    out.add(StatSpec(seg[0].trim(), seg.length > 1 ? seg[1].trim() : ''));
  }
  return out;
}

/// Humanize a non-negative elapsed-ms into Indonesian "N menit/jam/hari lalu".
/// `< 1 min` → "Baru saja".
String humanizeAgo(int deltaMs) {
  if (deltaMs < 60000) return 'Baru saja';
  final int minutes = deltaMs ~/ 60000;
  if (minutes < 60) return '$minutes menit lalu';
  final int hours = deltaMs ~/ 3600000;
  if (hours < 24) return '$hours jam lalu';
  final int days = deltaMs ~/ 86400000;
  return '$days hari lalu';
}

/// Map an event `ty` to a display label. Contains `patrol` → "PATROLI",
/// contains `clean` → "CLEANING", else the uppercased ty. Empty → "".
String deriveType(String ty) {
  final String t = ty.trim().toLowerCase();
  if (t.isEmpty) return '';
  if (t.contains('patrol')) return 'PATROLI';
  if (t.contains('clean')) return 'CLEANING';
  return ty.trim().toUpperCase();
}

/// Evidence label from the latest event `lq`: non-empty (QR-scanned) →
/// "Bukti kuat", empty (typed / GPS-only) → "GPS saja".
String deriveEvidence(String lq) =>
    lq.trim().isEmpty ? 'GPS saja' : 'Bukti kuat';

/// Group event docs by their point name `ln` (skips events without `ln`).
Map<String, List<Map<String, dynamic>>> eventsByLn(
  List<Map<String, dynamic>> events,
) {
  final Map<String, List<Map<String, dynamic>>> m = {};
  for (final e in events) {
    final String ln = (e['ln'] ?? '').toString();
    if (ln.isEmpty) continue;
    (m[ln] ??= <Map<String, dynamic>>[]).add(e);
  }
  return m;
}

/// A typed-only patrol point derived from orphan events (not registered in
/// the site doc's `ll[]` array). Built by [groupOrphans].
class TypedEntry {
  /// Display name from the latest orphan event (verbatim casing).
  final String ln;

  /// Lowercase key used for dedup and lookup.
  final String lnLower;

  /// All orphan events with this lowercase name.
  final List<Map<String, dynamic>> events;

  const TypedEntry({
    required this.ln,
    required this.lnLower,
    required this.events,
  });
}

/// Filter events to those matching patrol scope: `ty` contains [tyMatch]
/// (case-insensitive), `av` == [avValue] (exact), epoch >= [windowStartMs],
/// and `ln` non-empty. Returns a new list (does not mutate input).
List<Map<String, dynamic>> scopePatrolEvents(
  List<Map<String, dynamic>> events,
  String tyMatch,
  String avValue,
  int windowStartMs,
) {
  if (avValue.isEmpty) return const [];
  final String tyLower = tyMatch.toLowerCase();
  return events.where((e) {
    final String ty = (e['ty'] ?? '').toString().toLowerCase();
    if (!ty.contains(tyLower)) return false;
    final String av = (e['av'] ?? '').toString().trim();
    if (av != avValue) return false;
    final String ln = (e['ln'] ?? '').toString();
    if (ln.isEmpty) return false;
    final int t = eventEpoch(e);
    if (t < windowStartMs) return false;
    return true;
  }).toList();
}

/// Group events by their point name `ln` lowercased. Skips events with empty
/// `ln`. Used in merge mode for case-insensitive matching.
Map<String, List<Map<String, dynamic>>> eventsByLnLower(
  List<Map<String, dynamic>> events,
) {
  final Map<String, List<Map<String, dynamic>>> m = {};
  for (final e in events) {
    final String ln = (e['ln'] ?? '').toString();
    if (ln.isEmpty) continue;
    (m[ln.toLowerCase()] ??= <Map<String, dynamic>>[]).add(e);
  }
  return m;
}

/// From a lowercase-keyed event map, extract groups whose key is NOT in
/// [officialNamesLower]. Each orphan group collapses to one [TypedEntry]
/// whose [TypedEntry.ln] is the `ln` from the latest event (highest epoch).
List<TypedEntry> groupOrphans(
  Map<String, List<Map<String, dynamic>>> byLnLower,
  Set<String> officialNamesLower,
) {
  final List<TypedEntry> out = [];
  for (final entry in byLnLower.entries) {
    if (officialNamesLower.contains(entry.key)) continue;
    final List<Map<String, dynamic>> evs = entry.value;
    if (evs.isEmpty) continue;
    // Find latest event to determine display name.
    Map<String, dynamic> latest = evs.first;
    int latestT = eventEpoch(latest);
    for (final e in evs) {
      final int t = eventEpoch(e);
      if (t > latestT) {
        latestT = t;
        latest = e;
      }
    }
    out.add(
      TypedEntry(
        ln: (latest['ln'] ?? '').toString(),
        lnLower: entry.key,
        events: evs,
      ),
    );
  }
  return out;
}

/// Merge-aware stats summary.
/// - [totalVisits]: all events in [scopedEvents] (already window-filtered).
/// - [noVisitCount]: official points in [points] with 0 events in
///   [byLnLower] matching their `ln.toLowerCase()`.
/// - [typedCount]: number of [typedEntries] (distinct orphan groups displayed).
StatsSummary computeStatsSummaryMerge({
  required List<dynamic> points,
  required List<TypedEntry> typedEntries,
  required List<Map<String, dynamic>> scopedEvents,
  required Map<String, List<Map<String, dynamic>>> byLnLower,
}) {
  final int totalVisits = scopedEvents.length;
  int noVisit = 0;
  for (final p in points) {
    if (p is! Map) continue;
    final String ln = (p['ln'] ?? '').toString().toLowerCase();
    final List<Map<String, dynamic>> evs =
        byLnLower[ln] ?? const <Map<String, dynamic>>[];
    if (evs.isEmpty) noVisit++;
  }
  return StatsSummary(totalVisits, noVisit, typedEntries.length);
}

/// Build a [PointStat] for a typed-only entry. Computes visits/lastAgo/lastBy
/// from [events] (all already scoped to window), then forces `ps` to 'warn'
/// and `evidence` to 'GPS saja' regardless of event content.
PointStat computeTypedPointStat(List<Map<String, dynamic>> events, int nowMs) {
  if (events.isEmpty) {
    return const PointStat(
      type: '',
      lastAgo: 'Belum pernah',
      lastBy: '',
      evidence: 'GPS saja',
      ps: 'warn',
      visits: 0,
      lastEpoch: 0,
      hasEvent: false,
    );
  }
  Map<String, dynamic> latest = events.first;
  int latestT = eventEpoch(latest);
  for (final e in events) {
    final int t = eventEpoch(e);
    if (t > latestT) {
      latestT = t;
      latest = e;
    }
  }
  return PointStat(
    type: deriveType((latest['ty'] ?? '').toString()),
    lastAgo: humanizeAgo(nowMs - latestT),
    lastBy: (latest['cn'] ?? '').toString(),
    evidence: 'GPS saja',
    ps: 'warn',
    visits: events.length,
    lastEpoch: latestT,
    hasEvent: true,
  );
}

/// Event epoch (ms): `t`, falling back to `et` when `t` is missing OR
/// non-numeric. 0 when neither parses.
int eventEpoch(Map<String, dynamic> e) {
  final int? fromT = int.tryParse((e['t'] ?? '').toString());
  if (fromT != null) return fromT;
  return int.tryParse((e['et'] ?? '').toString()) ?? 0;
}

/// Per-point roll-up for the statistic card.
class PointStat {
  final String type;
  final String lastAgo;
  final String lastBy;
  final String evidence;
  final String ps; // 'danger' | 'warn' | 'ok'
  final int visits; // within the window
  final int lastEpoch; // max t all-time (0 if none)
  final bool hasEvent;
  const PointStat({
    required this.type,
    required this.lastAgo,
    required this.lastBy,
    required this.evidence,
    required this.ps,
    required this.visits,
    required this.lastEpoch,
    required this.hasEvent,
  });

  /// Computed `{...}` tokens consumed by the `content`/`status`/`badge` templates.
  Map<String, String> toTokens() => {
    'type': type,
    'lastAgo': lastAgo,
    'lastBy': lastBy,
    'evidence': evidence,
    'visits': '$visits',
    'ps': ps,
  };
}

/// Roll up one point's events. `latest` (max `t`, all-time) feeds
/// type/lastAgo/lastBy/evidence; `visits` counts events with `t ≥ windowStartMs`;
/// status: no in-window visit → danger; stale or GPS-only → warn; else ok.
PointStat computePointStat(
  List<Map<String, dynamic>> events,
  int nowMs,
  int windowStartMs,
  int staleMs,
) {
  if (events.isEmpty) {
    return const PointStat(
      type: '',
      lastAgo: 'Belum pernah',
      lastBy: '',
      evidence: '',
      ps: 'danger',
      visits: 0,
      lastEpoch: 0,
      hasEvent: false,
    );
  }
  Map<String, dynamic> latest = events.first;
  int latestT = eventEpoch(latest);
  int visits = 0;
  for (final e in events) {
    final int t = eventEpoch(e);
    if (t > latestT) {
      latestT = t;
      latest = e;
    }
    if (t >= windowStartMs) visits++;
  }
  final String lq = (latest['lq'] ?? '').toString();
  final String ps = visits == 0
      ? 'danger'
      : ((nowMs - latestT >= staleMs || lq.trim().isEmpty) ? 'warn' : 'ok');
  return PointStat(
    type: deriveType((latest['ty'] ?? '').toString()),
    lastAgo: humanizeAgo(nowMs - latestT),
    lastBy: (latest['cn'] ?? '').toString(),
    evidence: deriveEvidence(lq),
    ps: ps,
    visits: visits,
    lastEpoch: latestT,
    hasEvent: true,
  );
}

/// Summary stats across a cost center's points within the window.
class StatsSummary {
  final int totalVisits;
  final int noVisitCount;
  final int typedCount;
  const StatsSummary(this.totalVisits, this.noVisitCount, this.typedCount);

  Map<String, String> toTokens() => {
    'totalVisits': '$totalVisits',
    'noVisitCount': '$noVisitCount',
    'typedCount': '$typedCount',
  };
}

/// totalVisits = all in-window events at the cc's points; noVisitCount = points
/// with 0 in-window visits; typedCount = in-window events with empty `lq`.
StatsSummary computeStatsSummary(
  List<dynamic> points,
  Map<String, List<Map<String, dynamic>>> byLn,
  int nowMs,
  int windowStartMs,
) {
  int total = 0, noVisit = 0, typed = 0;
  for (final p in points) {
    if (p is! Map) continue;
    final String ln = (p['ln'] ?? '').toString();
    final List<Map<String, dynamic>> evs =
        byLn[ln] ?? const <Map<String, dynamic>>[];
    int inWindow = 0;
    for (final e in evs) {
      if (eventEpoch(e) >= windowStartMs) {
        inWindow++;
        total++;
        if ((e['lq'] ?? '').toString().trim().isEmpty) typed++;
      }
    }
    if (inWindow == 0) noVisit++;
  }
  return StatsSummary(total, noVisit, typed);
}

/// Replace `{key}` tokens in `raw` with `screenTx[key]`.
///
/// Missing key (null) -> left as literal `{key}`.
/// Empty value (`""` / whitespace) -> left as literal `{key}` (defense-in-depth:
/// aligns with `resolveDriverCurlyTokens` which already leaves the literal for
/// empty tokens; an empty resolved value would create an empty search clause,
/// which `filterByMultiClause` / `filterByCharCodeEquality` independently
/// catch as "match nothing", but leaving the literal preserves the
/// `value.contains('{')` guard as a visible signal).
String resolveScreenTxTokens(String raw, Map<String, dynamic> screenTx) {
  return raw.replaceAllMapped(RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'), (m) {
    final v = screenTx[m.group(1)];
    if (v == null) return m.group(0)!;
    final String sv = v.toString();
    return isTokenEmpty(sv) ? m.group(0)! : sv;
  });
}

/// Filter char-code-map docs by ONE equality condition. Accepts `field◼value`
/// (search) or `[[◀field▶◼value]]` (conditions); `{...}` tokens resolve from
/// `screenTx` first. Empty conditions → unchanged; an unresolvable value
/// (still containing `{`) → no match. Equality only (YAGNI).
///
/// ## Two-evaluator contract (spec S3-A)
///
/// Same fail-closed shape as `filterByMultiClause` (in
/// `driver_home_support.dart`): empty resolved value OR unresolved `{token}`
/// → return empty list (match nothing). For match-empty semantics (empty
/// value = doc field must be empty), see `evaluateGate` in
/// `admin_home_support.dart`.
List<Map<String, dynamic>> filterByCharCodeEquality(
  List<Map<String, dynamic>> docs,
  String rawConditions,
  Map<String, dynamic> screenTx,
) {
  if (rawConditions.trim().isEmpty) return docs;
  final String cleaned = resolveScreenTxTokens(rawConditions, screenTx)
      .replaceAll('[', '')
      .replaceAll(']', '')
      .replaceAll('◀', '')
      .replaceAll('▶', '')
      .trim();
  final int sep = cleaned.indexOf('◼');
  if (sep < 0) return docs;
  final String field = cleaned.substring(0, sep).trim();
  final String value = cleaned.substring(sep + 1).trim();
  if (field.isEmpty) return docs;
  if (value.isEmpty || value.contains('{')) return <Map<String, dynamic>>[];
  return docs
      .where((d) => eq((d[field] ?? '').toString().trim(), value))
      .toList();
}

// ─── Kehadiran (attendance) worker-list helpers ─────────────────────────────

/// Per-worker status code from clock-in/out state.
/// `ci` not set -> 'danger'; `ci` set & `co` not set -> 'warn'; else 'ok'.
String workerStatus(Map<String, dynamic> w) {
  if (!attendanceSet(w['ci'])) return 'danger';
  if (!attendanceSet(w['co'])) return 'warn';
  return 'ok';
}

/// Human status line. 'danger' -> "Belum scan"; 'warn' -> "Belum clock-out";
/// 'ok' -> "".
String workerStatusLine(Map<String, dynamic> w) {
  switch (workerStatus(w)) {
    case 'danger':
      return 'Belum scan';
    case 'warn':
      return 'Belum clock-out';
    default:
      return '';
  }
}

/// Aggregate attendance counts for one cost center's filtered workers.
/// Mirrors the dev spec tokens exactly:
///   total = all matching; hadir = ci set; belumScan = ci not set;
///   perluTindak = ci not set OR (ci set & co not set).
class KehadiranListAgg {
  final int total;
  final int hadir;
  final int belumScan;
  final int perluTindak;
  const KehadiranListAgg(
    this.total,
    this.hadir,
    this.belumScan,
    this.perluTindak,
  );

  Map<String, String> toTokens() => {
    'total': '$total',
    'hadir': '$hadir',
    'belumScan': '$belumScan',
    'perluTindak': '$perluTindak',
  };
}

KehadiranListAgg computeKehadiranList(List<Map<String, dynamic>> workers) {
  int total = 0, hadir = 0, belumScan = 0, perluTindak = 0;
  for (final w in workers) {
    total++;
    final bool ci = attendanceSet(w['ci']);
    final bool co = attendanceSet(w['co']);
    if (ci) {
      hadir++;
      if (!co) perluTindak++;
    } else {
      belumScan++;
      perluTindak++;
    }
  }
  return KehadiranListAgg(total, hadir, belumScan, perluTindak);
}

// ─── Chip spec / badge / time-format helpers (kehadiran rich-card) ──────────

/// Parsed chip specification from a content segment containing `◼`.
/// [iconName] is the Material icon lookup key (e.g. 'login').
/// [valueTemplate] is the raw template string (e.g. `<is>`) to be resolved.
class ChipSpec {
  final String iconName;
  final String valueTemplate;
  const ChipSpec(this.iconName, this.valueTemplate);
}

/// Parse one diamond-split segment into a [ChipSpec] if it contains `◼`.
/// Returns null for plain-text segments (no `◼`). Parts beyond index 1 are
/// ignored (forward-compat for future `iconName◼value◼tone` extension).
ChipSpec? parseChipSpec(String segment) {
  final int sep = segment.indexOf('◼');
  if (sep < 0) return null;
  final String icon = segment.substring(0, sep).trim();
  String tpl = segment.substring(sep + 1);
  final int sep2 = tpl.indexOf('◼');
  if (sep2 >= 0) tpl = tpl.substring(0, sep2); // drop part 3+ (forward-compat)
  tpl = tpl.trim();
  if (icon.isEmpty) return null;
  return ChipSpec(icon, tpl);
}

/// Extract the first HH:MM occurrence from [value].
/// "06:58" -> "06:58"; "15:10:29" -> "15:10"; "10 Jun 2026 15:10:29" -> "15:10".
/// Empty/whitespace -> "—". No match -> value as-is.
String formatTimeShort(String value) {
  final String v = value.trim();
  if (v.isEmpty) return '—'; // em-dash placeholder
  final Match? m = RegExp(r'\d{1,2}:\d{2}').firstMatch(v);
  if (m == null) return v;
  return m.group(0)!;
}

/// Chip tone: filled value (not empty, not the placeholder em-dash) -> 'ok';
/// otherwise inherits [cardStatus] ('danger'/'warn'/'ok').
String chipTone(String formattedValue, String cardStatus) {
  final String v = formattedValue.trim();
  if (v.isEmpty || v == '—') return cardStatus;
  return 'ok';
}

/// Resolve the badge template against doc + computed tokens, then trim.
/// Returns empty string when the result is empty/whitespace (caller suppresses
/// pill rendering).
String resolveBadge(
  String template,
  Map<String, dynamic> doc,
  Map<String, String> computed,
) {
  if (template.trim().isEmpty) return '';
  final String resolved = resolveMapTokens(template, doc, computed);
  return resolved.trim();
}
