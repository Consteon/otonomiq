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
    List<Map<String, dynamic>> events) {
  final Map<String, List<Map<String, dynamic>>> m = {};
  for (final e in events) {
    final String ln = (e['ln'] ?? '').toString();
    if (ln.isEmpty) continue;
    (m[ln] ??= <Map<String, dynamic>>[]).add(e);
  }
  return m;
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

/// Replace `{key}` tokens in `raw` with `screenTx[key]` (missing → left literal).
String resolveScreenTxTokens(String raw, Map<String, dynamic> screenTx) {
  return raw.replaceAllMapped(RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'), (m) {
    final v = screenTx[m.group(1)];
    return v == null ? m.group(0)! : v.toString();
  });
}

/// Filter char-code-map docs by ONE equality condition. Accepts `field◼value`
/// (search) or `[[◀field▶◼value]]` (conditions); `{...}` tokens resolve from
/// `screenTx` first. Empty conditions → unchanged; an unresolvable value
/// (still containing `{`) → no match. Equality only (YAGNI).
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
  if (value.isEmpty || value.contains('{')) return const [];
  return docs
      .where((d) => (d[field] ?? '').toString().trim() == value)
      .toList();
}
