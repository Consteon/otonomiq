import 'package:flutter/material.dart';

import '../global.dart';

/// One nav panel inside a LIST_MULTIPLE_PANEL_CARD card.
/// `text` is the raw `label◆headline◆details` template (tokens unresolved).
/// `status`/`route` are raw too — resolved at render time.
/// `okText`, when non-empty, replaces the resolved details when status == ok.
class PanelConfig {
  final String icon;
  final String text;
  final String status;
  final String route;
  final String okText;
  const PanelConfig({
    required this.icon,
    required this.text,
    required this.status,
    required this.route,
    this.okText = '',
  });

  factory PanelConfig.fromMap(Map<String, dynamic> m) => PanelConfig(
        icon: (m['icon'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        status: (m['status'] ?? '').toString(),
        route: (m['route'] ?? '').toString(),
        okText: (m['okText'] ?? '').toString(),
      );
}

/// Parse the component `panels` array into typed configs. Non-list → empty.
List<PanelConfig> parsePanels(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => PanelConfig.fromMap(Map<String, dynamic>.from(m)))
      .toList();
}

/// Resolved 3-part panel text.
class PanelText {
  final String label;
  final String headline;
  final String details;
  const PanelText(this.label, this.headline, this.details);
}

/// Split a token-resolved panel string on `◆` into label/headline/details.
PanelText splitPanelText(String resolved) {
  final List<String> parts = diamondTextToList(resolved);
  String at(int i) => parts.length > i ? parts[i] : '';
  return PanelText(at(0), at(1), at(2));
}

/// Resolve `<i>` numeric markers (via replaceMarker) then `{key}` tokens from
/// `computed`. Unknown `{key}` is left literal so it is visible during Fase 1.
String resolvePanelText(
  String template,
  List<dynamic> row,
  Map<String, String> computed,
  int indexStart,
) {
  String res = replaceMarker(template, row, indexStart, false);
  computed.forEach((k, v) {
    res = res.replaceAll('{$k}', v);
  });
  return res;
}

const Map<String, IconData> _panelIcons = {
  'users': Icons.people_alt_rounded,
  'clipboard-check': Icons.fact_check_rounded,
  'map-pin': Icons.location_on_rounded,
  'clock': Icons.schedule_rounded,
};

/// Map a spec icon name (e.g. "users", "clipboard-check") to an IconData.
/// Unknown names fall back to a neutral default.
IconData panelIcon(String name) =>
    _panelIcons[name.trim().toLowerCase()] ?? Icons.dashboard_rounded;

/// Normalize a status token to lowercase trimmed form.
String normalizeStatus(String s) => s.trim().toLowerCase();

const Map<String, int> _statusRank = {'ok': 1, 'warn': 2, 'danger': 3};

/// Worst (highest-severity) status among the given list. Unknown/unresolved
/// tokens rank 0 and never win; an all-unknown list returns 'ok'.
String worstStatus(List<String> statuses) {
  String worst = 'ok';
  int wv = 0;
  for (final s in statuses) {
    final n = normalizeStatus(s);
    final v = _statusRank[n] ?? 0;
    if (v > wv) {
      wv = v;
      worst = n;
    }
  }
  return worst;
}

/// Fixed render order for status groups.
const List<String> statusOrder = ['danger', 'warn', 'ok'];

/// Bucket items by status into danger/warn/ok. Unknown status -> ok bucket.
/// Returned map preserves `statusOrder` key order.
Map<String, List<T>> groupByStatus<T>(
  List<T> items,
  String Function(T) statusOf,
) {
  final groups = <String, List<T>>{
    'danger': <T>[],
    'warn': <T>[],
    'ok': <T>[],
  };
  for (final it in items) {
    final s = normalizeStatus(statusOf(it));
    (groups[s] ?? groups['ok']!).add(it);
  }
  return groups;
}

/// Group/summary label (ok -> "Aman").
String statusGroupLabel(String status) {
  switch (normalizeStatus(status)) {
    case 'danger':
      return 'Perlu tindak';
    case 'warn':
      return 'Perhatian';
    default:
      return 'Aman';
  }
}

/// Panel pill label (ok -> "Beres").
String statusPillLabel(String status) {
  switch (normalizeStatus(status)) {
    case 'danger':
      return 'Perlu tindak';
    case 'warn':
      return 'Perhatian';
    default:
      return 'Beres';
  }
}

/// "{nDanger} perlu tindak · {nWarn} perhatian · {nOk} aman".
String summaryLine(Map<String, List<dynamic>> groups) {
  final d = groups['danger']?.length ?? 0;
  final w = groups['warn']?.length ?? 0;
  final o = groups['ok']?.length ?? 0;
  return '$d perlu tindak · $w perhatian · $o aman';
}

/// Strong status color (strip + pill text).
Color statusColor(String status) {
  switch (normalizeStatus(status)) {
    case 'danger':
      return const Color(0xFFDC2626);
    case 'warn':
      return const Color(0xFFD97706);
    default:
      return const Color(0xFF16A34A);
  }
}

/// Soft status background color (pill fill).
Color statusBgColor(String status) {
  switch (normalizeStatus(status)) {
    case 'danger':
      return const Color(0xFFFEE2E2);
    case 'warn':
      return const Color(0xFFFEF3C7);
    default:
      return const Color(0xFFDCFCE7);
  }
}

/// Parsed component `table` string: `<tableDocId>//<subColl>`.
class TablePath {
  final String tableDocId;
  final String subColl;
  const TablePath(this.tableDocId, this.subColl);
}

/// Parse the component `table` value. `"84214220504259//site"` ->
/// (tableDocId: "84214220504259", subColl: "site"). No `//` or empty tail ->
/// subColl defaults to "content".
TablePath parseTablePath(String table) {
  final parts = table.split('//');
  final String docId = parts.isNotEmpty ? parts.first.trim() : '';
  final String tail = parts.length > 1 ? parts.last.trim() : '';
  return TablePath(docId, tail.isEmpty ? 'content' : tail);
}

/// Number of location points (`ll` array of objects) on a site doc.
int llCount(Map<String, dynamic> doc) {
  final dynamic ll = doc['ll'];
  return ll is List ? ll.length : 0;
}

final RegExp _angleToken = RegExp(r'<([a-zA-Z][a-zA-Z0-9]*)>');

/// Resolve `<charcode>` tokens against the site doc map (value stringified;
/// missing -> empty), then `{key}` tokens against `computed` (unknown left
/// literal so it stays visible during phased rollout).
String resolveMapTokens(
  String template,
  Map<String, dynamic> doc,
  Map<String, String> computed,
) {
  String res = template.replaceAllMapped(_angleToken, (m) {
    final dynamic val = doc[m.group(1)];
    return val == null ? '' : val.toString();
  });
  computed.forEach((k, v) {
    res = res.replaceAll('{$k}', v);
  });
  return res;
}

// ─── Kehadiran (attendance) aggregation ────────────────────────────────────

/// True when a clock-in/out value is a real reading. The data uses `-1` (also
/// `''`/`0`) as the "not set" sentinel.
bool attendanceSet(dynamic v) {
  final String s = (v ?? '').toString().trim();
  return s.isNotEmpty && s != '-1' && s != '0';
}

/// Group workers by their site VID `sv` (skips workers without `sv`).
Map<String, List<Map<String, dynamic>>> groupBySv(
    List<Map<String, dynamic>> workers) {
  final Map<String, List<Map<String, dynamic>>> m = {};
  for (final w in workers) {
    final String sv = (w['sv'] ?? '').toString();
    if (sv.isEmpty) continue;
    (m[sv] ??= <Map<String, dynamic>>[]).add(w);
  }
  return m;
}

/// Attendance roll-up for one cost center's workers.
class KehadiranAgg {
  final int hadir;
  final String issues;
  final String ps; // 'danger' | 'warn' | 'ok'
  const KehadiranAgg(this.hadir, this.issues, this.ps);
}

/// Count present workers, build the issues string, derive the panel status.
KehadiranAgg computeKehadiran(List<Map<String, dynamic>> workers) {
  int hadir = 0, belumScan = 0, lupaCheckout = 0;
  for (final w in workers) {
    if (attendanceSet(w['ci'])) {
      hadir++;
      if (!attendanceSet(w['co'])) lupaCheckout++;
    } else {
      belumScan++;
    }
  }
  final List<String> parts = [];
  if (belumScan > 0) parts.add('$belumScan belum scan');
  if (lupaCheckout > 0) parts.add('$lupaCheckout lupa clock-out');
  final String issues = parts.isEmpty ? 'Semua beres' : parts.join(', ');
  final String ps =
      belumScan > 0 ? 'danger' : (lupaCheckout > 0 ? 'warn' : 'ok');
  return KehadiranAgg(hadir, issues, ps);
}

// ─── Patroli aggregation ────────────────────────────────────────────────────

/// Index: location QR id (`lq`) -> latest patrol-event epoch. One pass over all
/// events; patrol-type only (`ty` contains "patrol"); `t` (or `et` fallback).
Map<String, int> latestPatrolByPoint(List<Map<String, dynamic>> events) {
  final Map<String, int> m = {};
  for (final e in events) {
    final String ty = (e['ty'] ?? '').toString().toLowerCase();
    if (!ty.contains('patrol')) continue;
    final String lq = (e['lq'] ?? '').toString();
    if (lq.isEmpty) continue;
    final int t = int.tryParse((e['t'] ?? e['et'] ?? '').toString()) ?? 0;
    if (t <= 0) continue;
    if (t > (m[lq] ?? 0)) m[lq] = t;
  }
  return m;
}

/// Patrol roll-up for one cost center's points (`ll`).
class PatroliAgg {
  final int llCount;
  final int staleCount;
  final int longestGapHours;
  final String qs; // 'warn' | 'ok'
  const PatroliAgg(this.llCount, this.staleCount, this.longestGapHours, this.qs);
}

/// For each point: gap = now - latest patrol epoch. A point with gap >= `staleMs`
/// is stale; a never-patrolled point is also stale (but excluded from the
/// longest-gap hour figure). `qs` = warn if any stale, else ok.
PatroliAgg computePatroli(
  List<dynamic> ll,
  Map<String, int> lastVisitByLi,
  int nowMs,
  int staleMs,
) {
  int llCount = 0, staleCount = 0, longestGapMs = 0, never = 0;
  for (final p in ll) {
    if (p is! Map) continue;
    llCount++;
    final String li = (p['li'] ?? '').toString();
    final int? last = li.isEmpty ? null : lastVisitByLi[li];
    if (last == null) {
      never++;
      continue;
    }
    final int gap = nowMs - last;
    if (gap > longestGapMs) longestGapMs = gap;
    if (gap >= staleMs) staleCount++;
  }
  staleCount += never;
  final String qs = staleCount > 0 ? 'warn' : 'ok';
  return PatroliAgg(llCount, staleCount, longestGapMs ~/ 3600000, qs);
}
