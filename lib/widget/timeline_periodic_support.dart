import 'package:intl/intl.dart';

/// Relative timestamp for a timeline entry, computed from the event epoch.
/// Same calendar day → "HH:mm hari ini"; yesterday → "Kemarin HH:mm"; else
/// "N hari lalu" (N = whole-day difference). Uses the device clock / local tz.
String relativeTimestamp(int tMs, int nowMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(tMs);
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final int dayDiff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
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
  if (conds.any((c) => c.value.isEmpty || c.value.contains('<'))) return const [];
  return events.where((e) {
    for (final c in conds) {
      if ((e[c.key] ?? '').toString().trim() != c.value) return false;
    }
    return true;
  }).toList();
}
