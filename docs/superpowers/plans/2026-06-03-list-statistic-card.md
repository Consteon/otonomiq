# LIST_STATISTIC_CARD (Patroli & Cleaning Point Detail) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Execution is NO-COMMIT per the user — implement + test each task but SKIP every `git add`/`git commit` step until told otherwise.**

**Goal:** Add a new server-driven UI component type `LIST_STATISTIC_CARD` — the per-point Patroli & Cleaning detail for one cost center: a period selector + three summary stat boxes + a status-sorted list of point cards (recency, who, visit count, evidence badge), each tapping its own route.

**Architecture:** Sibling of `ListMultiplePanelCard`. All decision logic lives in a pure, fully-unit-tested support file `lib/widget/statistic_card_support.dart` (zero imports). A `StatefulWidget` `ListStatisticCard` binds those helpers to the map store (`mapTableContent` via `subscribeToMapCollection`/`Obx`) and the custom router. The list items are the `ll[]` points of the single `site` doc whose `<av>` equals `screenTx['ccVid']`; per-point stats aggregate the `event` subcollection joined by `event.ln == point.ln`.

**Tech Stack:** Flutter, GetX (`Obx`, `RxMap mapTableContent`), Redux (`transactionStore`), existing helpers `subscribeToMapCollection`/`resolveMapTokens`/`parseTablePath`/`statusColor` (reused), `diamondTextToList`/`autheniumDecode`/`routeExist` (`global.dart`).

**Spec:** `docs/superpowers/specs/2026-06-03-list-statistic-card-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/widget/statistic_card_support.dart` | Pure logic: `parsePeriods`/`PeriodOption`, `parseStatSpecs`/`StatSpec`, `humanizeAgo`, `deriveType`, `deriveEvidence`, `eventsByLn`, `PointStat`/`computePointStat`, `StatsSummary`/`computeStatsSummary`, `resolveScreenTxTokens`, `filterByCharCodeEquality`. No Flutter, no I/O, no imports. | Create |
| `test/statistic_card_support_test.dart` | Unit tests for every pure helper. | Create |
| `lib/widget/list_statistic_card.dart` | `ListStatisticCard` StatefulWidget: config parse, subscribe site+event, period state, `Obx` render (period tabs + stat boxes + searched, status-sorted point list), per-point nav. | Create |
| `lib/widget/all_widget.dart` | Barrel — add export. | Modify |
| `lib/widget/build_display_component.dart` | Add dispatch branch `tip == 'list_statistic_card'`. | Modify (after the `list_multiple_panel_card` branch) |

**Why a separate support file:** mirrors `panel_card_support.dart` — pure logic split from the widget for testability. Reuses (imports in the widget, not the support file) `statusColor`/`statusBgColor`/`statusOrder`/`normalizeStatus`/`resolveMapTokens`/`parseTablePath`/`TablePath` from `panel_card_support.dart`.

---

### Task 1: `PeriodOption` + `parsePeriods`

**Files:**
- Create: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/statistic_card_support_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';

void main() {
  group('parsePeriods', () {
    test('parses label◼ms★... into options', () {
      final p = parsePeriods(
          '24 jam◼86400000★7 hari◼604800000★30 hari◼2592000000');
      expect(p.length, 3);
      expect(p[0].label, '24 jam');
      expect(p[0].ms, 86400000);
      expect(p[2].label, '30 hari');
      expect(p[2].ms, 2592000000);
    });
    test('skips malformed entries and empty input', () {
      expect(parsePeriods(''), isEmpty);
      expect(parsePeriods('oops★7 hari◼604800000').length, 1);
      expect(parsePeriods('bad◼notanumber'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'otonomiq' ... statistic_card_support.dart` (file does not exist) / `'parsePeriods' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): PeriodOption + parsePeriods"
```

---

### Task 2: `StatSpec` + `parseStatSpecs`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/statistic_card_support_test.dart`:

```dart
  group('parseStatSpecs', () {
    test('parses template◆label★... into specs', () {
      final s = parseStatSpecs(
          '{totalVisits}◆Total kunjungan★{noVisitCount}◆Titik tanpa kunjungan★{typedCount}◆Lokasi diketik');
      expect(s.length, 3);
      expect(s[0].template, '{totalVisits}');
      expect(s[0].label, 'Total kunjungan');
      expect(s[2].template, '{typedCount}');
      expect(s[2].label, 'Lokasi diketik');
    });
    test('empty input → empty; missing label → empty label', () {
      expect(parseStatSpecs(''), isEmpty);
      final s = parseStatSpecs('{x}');
      expect(s.length, 1);
      expect(s[0].label, '');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'parseStatSpecs' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): StatSpec + parseStatSpecs"
```

---

### Task 3: `humanizeAgo`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/statistic_card_support_test.dart`:

```dart
  group('humanizeAgo', () {
    test('menit / jam / hari boundaries', () {
      expect(humanizeAgo(30000), 'Baru saja'); // 30s
      expect(humanizeAgo(30 * 60000), '30 menit lalu');
      expect(humanizeAgo(60 * 60000), '1 jam lalu'); // exactly 1h
      expect(humanizeAgo(8 * 3600000), '8 jam lalu');
      expect(humanizeAgo(23 * 3600000), '23 jam lalu');
      expect(humanizeAgo(24 * 3600000), '1 hari lalu'); // exactly 24h
      expect(humanizeAgo(30 * 3600000), '1 hari lalu');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'humanizeAgo' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): humanizeAgo"
```

---

### Task 4: `deriveType` + `deriveEvidence`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/statistic_card_support_test.dart`:

```dart
  group('deriveType', () {
    test('patrol/clean substrings, else uppercase, empty→empty', () {
      expect(deriveType('report-patrol'), 'PATROLI');
      expect(deriveType('report-cleaning'), 'CLEANING');
      expect(deriveType(''), '');
      expect(deriveType('survey'), 'SURVEY');
    });
  });

  group('deriveEvidence', () {
    test('non-empty lq → Bukti kuat, empty → GPS saja', () {
      expect(deriveEvidence('QR123'), 'Bukti kuat');
      expect(deriveEvidence(''), 'GPS saja');
      expect(deriveEvidence('  '), 'GPS saja');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'deriveType' isn't defined` / `'deriveEvidence' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): deriveType + deriveEvidence"
```

---

### Task 5: `eventsByLn`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/statistic_card_support_test.dart`:

```dart
  group('eventsByLn', () {
    test('groups events by ln, skips empty ln', () {
      final g = eventsByLn([
        {'ln': 'Gudang', 't': '100'},
        {'ln': 'Gudang', 't': '200'},
        {'ln': 'Mushola', 't': '50'},
        {'t': '999'}, // no ln → skipped
      ]);
      expect(g['Gudang']!.length, 2);
      expect(g['Mushola']!.length, 1);
      expect(g.containsKey(''), isFalse);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'eventsByLn' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): eventsByLn index"
```

---

### Task 6: `PointStat` + `computePointStat`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

Per-point roll-up. `latest` = event with max `t` (all-time) → feeds type/lastAgo/lastBy/evidence/lastEpoch. `visits` = events with `t ≥ windowStart`. Status: `visits==0` → danger; else `(now−latestT ≥ staleMs)` OR `lq==""` → warn; else ok.

> **Post-review amendments (applied):** (1) `computePointStat` does NOT take a `point` parameter — its signature is `computePointStat(List<Map<String,dynamic>> events, int nowMs, int windowStartMs, int staleMs)` (the point map was unused; the widget passes only the point's events). The 6 test calls below pass the events list as the first argument (drop the leading `{'ln': ...}`). (2) `eventEpoch` falls back to `et` when `t` is missing OR non-numeric: `final fromT = int.tryParse((e['t'] ?? '').toString()); if (fromT != null) return fromT; return int.tryParse((e['et'] ?? '').toString()) ?? 0;`. (3) the `humanizeAgo` boundaries test includes `expect(humanizeAgo(-1), 'Baru saja');`.

- [ ] **Step 1: Write the failing test**

Append to `test/statistic_card_support_test.dart`:

```dart
  group('computePointStat', () {
    const now = 1000000000000;
    const stale = 43200000; // 12h
    final windowStart = now - 86400000; // 24h window

    test('no events → danger / Belum pernah', () {
      final r = computePointStat({'ln': 'A'}, const [], now, windowStart, stale);
      expect(r.ps, 'danger');
      expect(r.lastAgo, 'Belum pernah');
      expect(r.visits, 0);
      expect(r.hasEvent, isFalse);
      expect(r.type, '');
      expect(r.evidence, '');
      expect(r.lastEpoch, 0);
    });

    test('recent QR visit → ok / Bukti kuat', () {
      final r = computePointStat({'ln': 'A'}, [
        {'ln': 'A', 't': '${now - 3600000}', 'lq': 'q', 'cn': 'Budi', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.ps, 'ok');
      expect(r.visits, 1);
      expect(r.lastAgo, '1 jam lalu');
      expect(r.lastBy, 'Budi');
      expect(r.type, 'PATROLI');
      expect(r.evidence, 'Bukti kuat');
      expect(r.hasEvent, isTrue);
    });

    test('stale visit (≥12h) → warn even with QR evidence', () {
      final r = computePointStat({'ln': 'A'}, [
        {'ln': 'A', 't': '${now - 13 * 3600000}', 'lq': 'q', 'cn': 'Agus', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.ps, 'warn');
      expect(r.visits, 1);
      expect(r.lastAgo, '13 jam lalu');
      expect(r.evidence, 'Bukti kuat');
    });

    test('recent but GPS-only (empty lq) → warn / GPS saja', () {
      final r = computePointStat({'ln': 'A'}, [
        {'ln': 'A', 't': '${now - 3600000}', 'lq': '', 'cn': 'Sari', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.ps, 'warn');
      expect(r.evidence, 'GPS saja');
    });

    test('events only outside window → danger, last-ever still shown', () {
      final r = computePointStat({'ln': 'A'}, [
        {'ln': 'A', 't': '${now - 30 * 3600000}', 'lq': 'q', 'cn': 'X', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.visits, 0);
      expect(r.ps, 'danger');
      expect(r.lastAgo, '1 hari lalu');
      expect(r.hasEvent, isTrue);
    });

    test('picks latest among many and counts window', () {
      final r = computePointStat({'ln': 'A'}, [
        {'ln': 'A', 't': '${now - 2 * 3600000}', 'lq': 'q', 'cn': 'New', 'ty': 'report-patrol'},
        {'ln': 'A', 't': '${now - 5 * 3600000}', 'lq': 'q', 'cn': 'Old', 'ty': 'report-patrol'},
      ], now, windowStart, stale);
      expect(r.visits, 2);
      expect(r.lastBy, 'New');
      expect(r.lastEpoch, now - 2 * 3600000);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'computePointStat' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
/// Event epoch (ms): `t`, falling back to `et`. 0 when neither parses.
int eventEpoch(Map<String, dynamic> e) =>
    int.tryParse((e['t'] ?? e['et'] ?? '').toString()) ?? 0;

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
  Map<String, dynamic> point,
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): PointStat + computePointStat"
```

---

### Task 7: `StatsSummary` + `computeStatsSummary`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/statistic_card_support_test.dart`:

```dart
  group('computeStatsSummary', () {
    const now = 1000000000000;
    final windowStart = now - 86400000;

    test('totalVisits / noVisitCount / typedCount in window', () {
      final points = [
        {'ln': 'A'},
        {'ln': 'B'},
        {'ln': 'C'},
      ];
      final byLn = eventsByLn([
        {'ln': 'A', 't': '${now - 1000}', 'lq': 'q'},
        {'ln': 'A', 't': '${now - 2000}', 'lq': ''}, // typed
        {'ln': 'B', 't': '${now - 30 * 3600000}', 'lq': 'q'}, // outside window
        // C has no events
      ]);
      final s = computeStatsSummary(points, byLn, now, windowStart);
      expect(s.totalVisits, 2); // both A events in window; B's is out
      expect(s.noVisitCount, 2); // B (out of window) and C
      expect(s.typedCount, 1); // A's empty-lq event
    });

    test('non-map point tolerated', () {
      final s = computeStatsSummary(['oops', {'ln': 'A'}],
          eventsByLn([{'ln': 'A', 't': '${now - 1000}', 'lq': 'q'}]),
          now, windowStart);
      expect(s.totalVisits, 1);
      expect(s.noVisitCount, 0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'computeStatsSummary' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): StatsSummary + computeStatsSummary"
```

---

### Task 8: `resolveScreenTxTokens` + `filterByCharCodeEquality`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart`
- Test: `test/statistic_card_support_test.dart`

Resolves `{ccVid}` from `screenTx`, then filters char-code-map docs by a single
equality (`field == value`). Accepts both `field◼value` (search form) and
`[[◀field▶◼value]]` (conditions form). Caller decodes (autheniumDecode) first.

- [ ] **Step 1: Write the failing test**

Append to `test/statistic_card_support_test.dart`:

```dart
  group('resolveScreenTxTokens', () {
    test('replaces {key} from screenTx, leaves unknown literal', () {
      expect(resolveScreenTxTokens('av◼{ccVid}', {'ccVid': '83'}), 'av◼83');
      expect(resolveScreenTxTokens('av◼{ccVid}', const {}), 'av◼{ccVid}');
    });
  });

  group('filterByCharCodeEquality', () {
    final docs = [
      {'av': '83', 'an': 'A Group'},
      {'av': '99', 'an': 'B Group'},
    ];
    test('conditions form filters by av == ccVid', () {
      final r = filterByCharCodeEquality(
          docs, '[[◀av▶◼{ccVid}]]', {'ccVid': '83'});
      expect(r.length, 1);
      expect(r.first['an'], 'A Group');
    });
    test('search form filters by av == ccVid', () {
      final r = filterByCharCodeEquality(docs, 'av◼{ccVid}', {'ccVid': '99'});
      expect(r.length, 1);
      expect(r.first['an'], 'B Group');
    });
    test('empty conditions → unchanged list', () {
      expect(filterByCharCodeEquality(docs, '', const {}).length, 2);
    });
    test('unresolved token → no match (empty)', () {
      expect(filterByCharCodeEquality(docs, 'av◼{ccVid}', const {}), isEmpty);
    });
  });
```

> Append the two groups above **inside** `main()` — i.e. before the single
> closing `}` that Task 1 already added at the end of the file. Do NOT add
> another `}`; `main()` stays closed exactly once.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: FAIL — `'resolveScreenTxTokens' isn't defined` / `'filterByCharCodeEquality' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/statistic_card_support.dart test/statistic_card_support_test.dart
git commit -m "feat(statistic-card): screenTx token resolve + char-code equality filter"
```

---

### Task 9: `ListStatisticCard` widget

**Files:**
- Create: `lib/widget/list_statistic_card.dart`

Binds the helpers to GetX/Redux/Flutter. Subscribes `site` + `event`; filters the
`site` doc by `av == screenTx['ccVid']`; renders that doc's `ll[]` as period-windowed,
status-sorted point cards. Token resolution reuses `resolveMapTokens` (point map +
computed tokens). Status color/order reuse `panel_card_support.dart`.

> **Post-review amendments (applied):** (1) the `content` template is parsed once into a
> `_contentArray` field in `_initConfig` (next to `_textArray`), NOT re-parsed per card in
> `_buildPointCard`. (2) the `entries.sort` comparator maps an unknown status
> (`statusOrder.indexOf` → −1) to `statusOrder.length` so it sorts AFTER `ok`, not before
> `danger`. (3) the list area's empty-state gates on `entries.isEmpty` (the filtered list),
> not `points.isEmpty`, so a search-miss shows the empty message instead of a blank area.
> (4) `_buildStatBoxes` wraps its `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` in
> `IntrinsicHeight`. Without it the stretch inherits the parent `Column`'s unbounded height
> and throws a runtime **"BoxConstraints forces an infinite height"** (caught only on device,
> not by `flutter analyze`). The point-card row already uses this `IntrinsicHeight` idiom; the
> stat-boxes row had missed it (the code-quality reviewer's M4 wrongly assumed a bounded parent).

- [ ] **Step 1: Create the widget file**

Create `lib/widget/list_statistic_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// LIST_STATISTIC_CARD — per-point Patroli & Cleaning detail for one cost center.
/// Filters the `site` subcollection to the doc whose `<av>` == screenTx['ccVid'],
/// renders that doc's `ll[]` points as cards: period selector + 3 stat boxes +
/// status-sorted point list (recency, last-by, visit count, evidence badge),
/// each tapping `route` with the point context (`pointId`/`pointName`).
class ListStatisticCard extends StatefulWidget {
  const ListStatisticCard({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  @override
  State<ListStatisticCard> createState() => _ListStatisticCardState();
}

class _ListStatisticCardState extends State<ListStatisticCard> {
  List<String> _textArray = [];
  List<PeriodOption> _periods = [];
  List<StatSpec> _statSpecs = [];
  int _selectedMs = 86400000;
  int _staleMs = 43200000;
  String _siteCode = '';
  String _eventCode = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Build-scoped indexes (rebuilt each Obx pass).
  int _nowMs = 0;
  int _windowStartMs = 0;
  Map<String, List<Map<String, dynamic>>> _byLn = const {};

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    final String periodRaw = (widget.component['period'] ?? '').toString();
    _periods = parsePeriods(autheniumDecode(periodRaw) ?? periodRaw);
    final String statsRaw = (widget.component['stats'] ?? '').toString();
    _statSpecs = parseStatSpecs(autheniumDecode(statsRaw) ?? statsRaw);
    _staleMs =
        int.tryParse((widget.component['staleMs'] ?? '').toString()) ?? 43200000;
    final int def =
        int.tryParse((widget.component['periodDefault'] ?? '').toString()) ?? 0;
    _selectedMs = _periods.any((p) => p.ms == def)
        ? def
        : (_periods.isNotEmpty ? _periods.first.ms : 86400000);
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    _siteCode = '${tp.tableDocId}/${tp.subColl}';
    _eventCode = '${tp.tableDocId}/event';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _siteCode);
    subscribeToMapCollection(appVid, tp.tableDocId, 'event', _eventCode);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  String get _selectedLabel {
    for (final p in _periods) {
      if (p.ms == _selectedMs) return p.label;
    }
    return '';
  }

  /// The matched site doc's `ll[]` points (cc filtered by av == ccVid).
  List<Map<String, dynamic>> _points(List<Map<String, dynamic>> siteDocs) {
    final String condRaw =
        (widget.component['conditions'] ?? widget.component['search'] ?? '')
            .toString();
    final String cond = autheniumDecode(condRaw) ?? condRaw;
    final List<Map<String, dynamic>> matched =
        filterByCharCodeEquality(siteDocs, cond, _screenTx);
    if (matched.isEmpty) return const [];
    final dynamic ll = matched.first['ll'];
    if (ll is! List) return const [];
    return ll.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  List<Map<String, dynamic>> _search(List<Map<String, dynamic>> points) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return points;
    return points
        .where((p) => (p['ln'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  void _onPointTap(Map<String, dynamic> point) {
    final String route = (widget.component['route'] ?? '').toString();
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      'pointId': (point['li'] ?? '').toString(),
      'pointName': (point['ln'] ?? '').toString(),
      'point_route': route,
    })));
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> siteDocs =
          List<Map<String, dynamic>>.from(mapTableContent[_siteCode] ?? const []);
      final List<Map<String, dynamic>> events =
          List<Map<String, dynamic>>.from(
              mapTableContent[_eventCode] ?? const []);
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _windowStartMs = _nowMs - _selectedMs;
      _byLn = eventsByLn(events);

      final List<Map<String, dynamic>> points = _points(siteDocs);
      final StatsSummary summary =
          computeStatsSummary(points, _byLn, _nowMs, _windowStartMs);
      final List<Map<String, dynamic>> searched = _search(points);

      // Pair each point with its stat, then sort severity-desc, oldest-first.
      final List<MapEntry<Map<String, dynamic>, PointStat>> entries =
          searched.map((p) {
        final stat = computePointStat(
            _byLn[(p['ln'] ?? '').toString()] ?? const [],
            _nowMs,
            _windowStartMs,
            _staleMs);
        return MapEntry(p, stat);
      }).toList();
      entries.sort((a, b) {
        final int ra = statusOrder.indexOf(a.value.ps);
        final int rb = statusOrder.indexOf(b.value.ps);
        if (ra != rb) return ra - rb;
        return a.value.lastEpoch.compareTo(b.value.lastEpoch);
      });

      final double availableH = MediaQuery.of(context).size.height * 0.82;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              widget.lPad, widget.tPad, widget.rPad, widget.bPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_periods.isNotEmpty) _buildPeriodTabs(),
              const SizedBox(height: 14),
              if (_statSpecs.isNotEmpty) _buildStatBoxes(summary),
              const SizedBox(height: 14),
              _buildSearchField(),
              const SizedBox(height: 12),
              Expanded(
                child: points.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final e in entries)
                            _buildPointCard(e.key, e.value),
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildPeriodTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final p in _periods)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedMs = p.ms),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        p.ms == _selectedMs ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: p.ms == _selectedMs
                        ? const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 6,
                                offset: Offset(0, 2))
                          ]
                        : null,
                  ),
                  child: Text(p.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.ms == _selectedMs
                              ? const Color(0xFF1A2233)
                              : const Color(0xFF8A93A6))),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatBoxes(StatsSummary summary) {
    final Map<String, String> tokens = summary.toTokens();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _statSpecs.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _statBox(i, _statSpecs[i], tokens)),
        ],
      ],
    );
  }

  Widget _statBox(int index, StatSpec spec, Map<String, String> tokens) {
    final String value = resolveMapTokens(spec.template, const {}, tokens);
    final bool neutral = index == 0;
    final bool good = value.trim() == '0';
    final Color bg = neutral
        ? Colors.white
        : (good ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7));
    final Color fg = neutral
        ? const Color(0xFF1A2233)
        : (good ? const Color(0xFF16A34A) : const Color(0xFFD97706));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: neutral ? Border.all(color: const Color(0xFFE5E7EB)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: fg)),
          const SizedBox(height: 4),
          Text(spec.label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final String hint = _textArray.isNotEmpty ? _textArray[0] : 'Cari';
    return TextFormField(
      controller: _searchController,
      keyboardType: TextInputType.text,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final String empty =
        _textArray.length > 2 ? _textArray[2] : 'Data tidak ditemukan';
    return Center(
      child: Text(empty,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
    );
  }

  Widget _buildPointCard(Map<String, dynamic> point, PointStat stat) {
    final Map<String, String> tokens = stat.toTokens()
      ..['period'] = _selectedLabel;
    final List<String> content =
        diamondTextToList((widget.component['content'] ?? '').toString());
    String at(int i) =>
        content.length > i ? resolveMapTokens(content[i], point, tokens) : '';
    final String name = at(0);
    final String type = at(1);
    final String line2 = at(2);
    final String line3 = at(3);
    final String ps = stat.ps;
    final Color sColor = statusColor(ps);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onPointTap(point),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 10,
                    offset: Offset(0, 4)),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      color: sColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: RichText(
                                  overflow: TextOverflow.ellipsis,
                                  text: TextSpan(children: [
                                    TextSpan(
                                        text: name,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1A2233))),
                                    if (type.isNotEmpty)
                                      TextSpan(
                                          text: '   ·   $type',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                              color: Color(0xFF8A93A6))),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (stat.hasEvent) _evidenceBadge(stat.evidence),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Color(0xFFC7CCD4), size: 24),
                            ],
                          ),
                          if (line2.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(line2,
                                style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: normalizeStatus(ps) == 'ok'
                                        ? const Color(0xFF6B7280)
                                        : sColor)),
                          ],
                          if (line3.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(line3,
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF9AA1AD))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _evidenceBadge(String evidence) {
    final bool strong = evidence == 'Bukti kuat';
    final String mapped = strong ? 'ok' : 'warn';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusBgColor(mapped),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(strong ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
              size: 14, color: statusColor(mapped)),
          const SizedBox(width: 4),
          Text(evidence,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: statusColor(mapped))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/widget/list_statistic_card.dart`
Expected: No `error` lines. Confirm every referenced symbol resolves:
`diamondTextToList`, `autheniumDecode`, `mapTableContent`, `subscribeToMapCollection`,
`routeExist`, `routeStack`, `gotoRoute`, `transactionStore`, `UpdateScreenTxAction`,
`ScreenTransaction` (globals/redux); `parseTablePath`, `TablePath`, `statusColor`,
`statusBgColor`, `statusOrder`, `normalizeStatus`, `resolveMapTokens`
(`panel_card_support.dart`); `parsePeriods`, `PeriodOption`, `parseStatSpecs`,
`StatSpec`, `eventsByLn`, `computeStatsSummary`, `StatsSummary`, `computePointStat`,
`PointStat`, `filterByCharCodeEquality` (`statistic_card_support.dart`).

- [ ] **Step 3: Commit** (SKIP — no-commit)

```bash
git add lib/widget/list_statistic_card.dart
git commit -m "feat(statistic-card): ListStatisticCard render + per-point aggregation"
```

---

### Task 10: Register the type (barrel export + dispatch branch)

**Files:**
- Modify: `lib/widget/all_widget.dart`
- Modify: `lib/widget/build_display_component.dart` (insert after the `list_multiple_panel_card` branch, which ends at the `}` before `} else if (tip == 'worker_card_detail') {` around line 1139)

- [ ] **Step 1: Add the barrel export**

In `lib/widget/all_widget.dart`, near the other `list_*` exports (just below
`export 'list_multiple_panel_card.dart';` at line 21), add:

```dart
export 'list_statistic_card.dart';
```

- [ ] **Step 2: Add the dispatch branch**

In `lib/widget/build_display_component.dart`, immediately AFTER the
`list_multiple_panel_card` branch's closing `}` and BEFORE
`  } else if (tip == 'worker_card_detail') {`, insert:

```dart
  } else if (tip == 'list_statistic_card') {
    try {
      result = ListStatisticCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
```

The resulting code reads:

```dart
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'list_statistic_card') {
    try {
      result = ListStatisticCard(
        key: txfKey,
        component: component,
        scrName: scrName,
        lPad: lPad,
        tPad: tPad,
        rPad: rPad,
        bPad: bPad,
      );
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
  } else if (tip == 'worker_card_detail') {
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/widget/build_display_component.dart lib/widget/all_widget.dart`
Expected: No `error` lines. `ListStatisticCard` resolves via the barrel import.

- [ ] **Step 4: Run the full support suite** + commit (SKIP commit — no-commit)

Run: `flutter test test/statistic_card_support_test.dart`
Expected: PASS (all groups).

```bash
git add lib/widget/all_widget.dart lib/widget/build_display_component.dart
git commit -m "feat(statistic-card): register LIST_STATISTIC_CARD dispatch + barrel export"
```

---

### Task 11: Manual verification

**Files:** none (manual).

- [ ] **Step 1** Ensure prerequisites are live for tenant `84214220504259`:
  - the `site` doc with `av == ccVid` carries an `ll[]` of points (`ln`/`li`/…);
  - the `event` subcollection has patrol/cleaning docs with `ln` (matching point names),
    `cn` (worker name), `lq` (QR id or empty), `t` (epoch ms), `ty` (`report-patrol`).
  - Add the component to the `patroliCleaningPerSite` page JSON (the screen reached by
    the front card's "Patroli & Cleaning" panel), using the confirmed config:
    `vidtable":"20342033315492","table":"84214220504259//site","search":"av◼{ccVid}",
    "conditions":"[[◀av▶◼{ccVid}]]"` + `period`/`stats`/`content`/`status`/`badge`/`route`.

- [ ] **Step 2** Run the app: `./set_android.sh && flutter run`. From the cost-center
  list, tap a card's "Patroli & Cleaning" panel to reach the screen hosting this component.

- [ ] **Step 3** Confirm:
  - period tabs (24 jam / 7 hari / 30 hari), default 24 jam selected;
  - three stat boxes — `{totalVisits}` neutral, `{noVisitCount}`/`{typedCount}` green when 0;
  - point cards sorted danger→warn→ok, oldest-first within a group;
  - each card: `<ln>` · `{type}` (PATROLI), "Terakhir {lastAgo} · {lastBy}" (orange when
    warn/danger, gray when ok), "{visits} kunjungan dalam {period}", evidence badge
    (Bukti kuat green / GPS saja amber), chevron;
  - changing the period tab live-recomputes counts + statuses + stats;
  - search filters points by name;
  - tapping a card navigates to `patroliCleaningPointTimeline` (or shows nothing if that
    route's page is not yet loaded) and AppBar back pops `routeStack`.

- [ ] **Step 4** Edit/age an `event` doc in Firestore → the card live-updates (Obx).

---

## Self-Review

**Spec coverage (spec § → task):**
- Component dispatch + file structure → Task 9 (widget), Task 10 (register).
- Map binding to `site` + `event`, `{ccVid}` filter → Task 8 (`filterByCharCodeEquality`), Task 9 (`_subscribe`/`_points`).
- List = matched site doc's `ll[]` → Task 9 (`_points`).
- Period tabs + window → Task 1 (`parsePeriods`), Task 9 (`_initConfig`/`_buildPeriodTabs`/`_windowStartMs`).
- Per-point tokens `<ln>`/`{type}`/`{lastAgo}`/`{lastBy}`/`{visits}`/`{period}`/`{evidence}`/`{ps}` → Task 3 (`humanizeAgo`), Task 4 (`deriveType`/`deriveEvidence`), Task 6 (`computePointStat`), Task 9 (`_buildPointCard` token merge incl. `period`).
- Join `event.ln == point.ln` → Task 5 (`eventsByLn`), Task 6/7 (lookup by `ln`).
- Stats `{totalVisits}`/`{noVisitCount}`/`{typedCount}` → Task 2 (`parseStatSpecs`), Task 7 (`computeStatsSummary`), Task 9 (`_buildStatBoxes`).
- Status rule (no-visit→danger, stale/GPS→warn, else ok) → Task 6 (`computePointStat`).
- Layout (tabs, stat boxes, sorted list, card, badge, tap) → Task 9.
- Testing → Tasks 1-8 unit tests; Task 11 manual.
- Documented defaults (staleMs 12h, no-event→danger/"Belum pernah", typedCount=events, stat-box green@0, equality-only filter, sort severity then oldest) → Task 6/7/8/9 as coded.

**Placeholder scan:** none — every step has complete test + implementation code, exact paths, exact commands.

**Type consistency:** `PeriodOption(label,ms)`, `StatSpec(template,label)`, `PointStat{type,lastAgo,lastBy,evidence,ps,visits,lastEpoch,hasEvent}.toTokens()`, `StatsSummary{totalVisits,noVisitCount,typedCount}.toTokens()`, `eventEpoch(Map)→int`, `computePointStat(Map,List<Map>,int,int,int)→PointStat`, `computeStatsSummary(List,Map<String,List<Map>>,int,int)→StatsSummary`, `parsePeriods(String)→List<PeriodOption>`, `parseStatSpecs(String)→List<StatSpec>`, `deriveType`/`deriveEvidence(String)→String`, `eventsByLn(List<Map>)→Map<String,List<Map>>`, `resolveScreenTxTokens(String,Map)→String`, `filterByCharCodeEquality(List<Map>,String,Map)→List<Map>` — names/signatures identical across the widget (Task 9) and the helper definitions (Tasks 1-8). Reused `statusColor`/`statusBgColor`/`statusOrder`/`normalizeStatus`/`resolveMapTokens`/`parseTablePath`/`TablePath` match `panel_card_support.dart`. Dispatch string `'list_statistic_card'` = `'LIST_STATISTIC_CARD'.toLowerCase()`.
