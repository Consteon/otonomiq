# Cost Center Card — Phase B Aggregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`) syntax. **Execution is currently NO-COMMIT per the user — implement + test each task but SKIP every `git add`/`git commit` step until told otherwise.**

**Goal:** Fill the cost-center card's aggregation tokens with real data so statuses, pills, accordion grouping and the colored summary become live. `{hadir}`/`{issues}`/`{ps}` come from the `workforce` subcollection; `{staleCount}`/`{longestGap}`/`{qs}` from the `event` subcollection; `{ws}` = worst of the two panel statuses.

**Architecture:** Phase A already binds the widget to the `site` subcollection (char-code map docs) and renders search + summary + status accordions + cards + nested panels, with `_computeCardValues` a stub returning only `{llCount}`. Phase B (1) also subscribes the widget to `workforce` and `event` (same `subscribeToMapCollection`, same `tableDocId`, different subcollection), (2) adds pure aggregation helpers to `panel_card_support.dart`, and (3) wires `_computeCardValues` to those helpers using build-scoped precomputed indexes (one pass over workforce + events per build, O(points)/O(1) per card). A small generic `okText` panel option supplies the "Tidak ada jeda signifikan" fallback.

**Tech Stack:** Flutter, GetX (`Obx`, `mapTableContent`), pure Dart helpers (unit-tested).

**Confirmed data model (real Firestore):**
- `site` doc (one per card): `sv` (site VID), `av` (cc VID), `nm` (headcount), `ll` = array of objects `{ln, li, la, lo, ra}`.
- `workforce` doc (subcollection, joined to a card by **`worker['sv'] == site['sv']`** — `sv` already present on workers): `ci` (clock-in), `co` (clock-out). **`-1` (also `''`/`0`) is the empty sentinel — NOT a timestamp.**
- `event` doc (subcollection, joined to a point by **`event['lq'] == ll[].li`**): `ty` (type, e.g. `"report-patrol"`), `t` (epoch ms; `et` is an equal-valued fallback), `lq` (point QR id).
- Path for all three: `MobileTable/{appVid}/tables/{tableDocId}/{site|workforce|event}`. `appVid` = `vidtable`; `tableDocId` = first `//`-segment of `table`.

**Token → source:**

| Token | Source | Rule |
|-------|--------|------|
| `{hadir}` | workforce | COUNT workers (sv match) with `ci` set |
| `{issues}` | workforce | "X belum scan" (`ci` unset) + "Y lupa clock-out" (`ci` set, `co` unset); else "Semua beres" |
| `{ps}` | workforce | `danger` if any belum-scan; `warn` if only lupa-clock-out; else `ok` |
| `{llCount}` | site | `ll.length` (already real in Phase A) |
| `{staleCount}` | event | COUNT points with gap ≥ threshold, plus never-patrolled points |
| `{longestGap}` | event | MAX gap among visited points, in whole hours |
| `{qs}` | event | `warn` if `staleCount` > 0 else `ok` |
| `{ws}` | derived | `worstStatus([ps, qs])` |

**Open decisions (documented defaults; refine later, not blockers):**
- **Worker `st` field** (e.g. `"off"`) is NOT filtered — all sv-matching workers count. If off-duty workers should be excluded from "belum scan", add `st` filtering later.
- **Patrol type filter** = `ty` contains `"patrol"` (matches `"report-patrol"`). If cleaning/other visit types also count as "touched", widen the filter.
- **Never-patrolled points** count toward `staleCount` but are excluded from the `{longestGap}` hour figure (no "belum pernah" label yet — render refinement).
- **Now** = device clock (`DateTime.now()`). A server-synced clock (`#REF_TIME`) can replace it if drift matters.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/widget/panel_card_support.dart` | Add `okText` to `PanelConfig`; add `attendanceSet`, `KehadiranAgg`/`computeKehadiran`, `groupBySv`, `latestPatrolByPoint`, `PatroliAgg`/`computePatroli`. | Modify |
| `test/panel_card_support_test.dart` | Tests for all new helpers + `okText`. | Modify |
| `lib/widget/list_multiple_panel_card.dart` | Subscribe workforce+event; precompute indexes in build; real `_computeCardValues`; threshold; `okText` render. | Modify |

---

### Task 1: `PanelConfig.okText`

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

`okText` is an optional per-panel fallback shown as the panel details when the panel's status resolves to `ok` (e.g. the patrol panel shows "Tidak ada jeda signifikan" instead of "0 titik jeda lama · terlama 0 jam").

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `test/panel_card_support_test.dart`:

```dart
  group('PanelConfig.okText', () {
    test('parsed when present, empty default', () {
      final panels = parsePanels([
        {'icon': 'clipboard-check', 'text': 'a◆b◆c', 'status': '{qs}',
         'route': 'r', 'okText': 'Tidak ada jeda signifikan'},
        {'icon': 'users', 'text': 'x'},
      ]);
      expect(panels[0].okText, 'Tidak ada jeda signifikan');
      expect(panels[1].okText, '');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `The getter 'okText' isn't defined for the type 'PanelConfig'`.

- [ ] **Step 3: Implement**

In `lib/widget/panel_card_support.dart`, replace the `PanelConfig` class with:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS (all groups, incl. the prior PanelConfig tests which don't assert `okText`).

- [ ] **Step 5: Commit** (SKIP while no-commit)

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): PanelConfig.okText optional fallback"
```

---

### Task 2: Kehadiran aggregation (`attendanceSet`, `groupBySv`, `computeKehadiran`)

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart`:

```dart
  group('attendanceSet', () {
    test('-1 / empty / 0 are unset; a real epoch is set', () {
      expect(attendanceSet('-1'), isFalse);
      expect(attendanceSet(''), isFalse);
      expect(attendanceSet('0'), isFalse);
      expect(attendanceSet(null), isFalse);
      expect(attendanceSet('1780479159902'), isTrue);
      expect(attendanceSet(1780479159902), isTrue);
    });
  });

  group('groupBySv', () {
    test('buckets workers by sv, skips empty sv', () {
      final g = groupBySv([
        {'sv': '11', 'ci': '-1'},
        {'sv': '11', 'ci': '5'},
        {'sv': '22', 'ci': '-1'},
        {'ci': '5'}, // no sv -> skipped
      ]);
      expect(g['11']!.length, 2);
      expect(g['22']!.length, 1);
      expect(g.containsKey(''), isFalse);
    });
  });

  group('computeKehadiran', () {
    test('all present, clocked out -> ok / Semua beres', () {
      final r = computeKehadiran([
        {'ci': '100', 'co': '200'},
        {'ci': '100', 'co': '200'},
      ]);
      expect(r.hadir, 2);
      expect(r.issues, 'Semua beres');
      expect(r.ps, 'ok');
    });
    test('a belum-scan -> danger', () {
      final r = computeKehadiran([
        {'ci': '100', 'co': '200'},
        {'ci': '-1', 'co': '-1'},
      ]);
      expect(r.hadir, 1);
      expect(r.issues, '1 belum scan');
      expect(r.ps, 'danger');
    });
    test('only lupa-clock-out -> warn', () {
      final r = computeKehadiran([
        {'ci': '100', 'co': '-1'},
        {'ci': '100', 'co': '200'},
      ]);
      expect(r.hadir, 2);
      expect(r.issues, '1 lupa clock-out');
      expect(r.ps, 'warn');
    });
    test('both issues -> danger, combined text', () {
      final r = computeKehadiran([
        {'ci': '-1', 'co': '-1'},
        {'ci': '100', 'co': '-1'},
      ]);
      expect(r.issues, '1 belum scan, 1 lupa clock-out');
      expect(r.ps, 'danger');
    });
    test('empty list -> ok / Semua beres', () {
      final r = computeKehadiran(const []);
      expect(r.hadir, 0);
      expect(r.ps, 'ok');
      expect(r.issues, 'Semua beres');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `'attendanceSet' isn't defined` / `'groupBySv' isn't defined` / `'computeKehadiran' isn't defined`.

- [ ] **Step 3: Implement**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP while no-commit)

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): Kehadiran aggregation helpers"
```

---

### Task 3: Patroli aggregation (`latestPatrolByPoint`, `computePatroli`)

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart`:

```dart
  group('latestPatrolByPoint', () {
    test('keeps max t per lq, patrol-type only, skips empty/zero', () {
      final m = latestPatrolByPoint([
        {'ty': 'report-patrol', 'lq': 'A', 't': '100'},
        {'ty': 'report-patrol', 'lq': 'A', 't': '300'}, // newer wins
        {'ty': 'report-patrol', 'lq': 'A', 't': '200'},
        {'ty': 'report-incident', 'lq': 'A', 't': '999'}, // not patrol -> ignored
        {'ty': 'report-patrol', 'lq': '', 't': '500'}, // empty lq -> ignored
        {'ty': 'report-patrol', 'lq': 'B', 't': '50'},
      ]);
      expect(m['A'], 300);
      expect(m['B'], 50);
      expect(m.containsKey(''), isFalse);
    });
    test('falls back to et when t missing', () {
      final m = latestPatrolByPoint([
        {'ty': 'patrol', 'lq': 'A', 'et': '700'},
      ]);
      expect(m['A'], 700);
    });
  });

  group('computePatroli', () {
    const now = 1000000000000; // fixed "now" for tests
    const stale = 43200000; // 12h
    test('recent visits -> staleCount 0, qs ok', () {
      final ll = [
        {'li': 'A'},
        {'li': 'B'}
      ];
      final last = {'A': now - 1000, 'B': now - 2000};
      final r = computePatroli(ll, last, now, stale);
      expect(r.llCount, 2);
      expect(r.staleCount, 0);
      expect(r.qs, 'ok');
    });
    test('one stale visit -> staleCount 1, qs warn, longestGap hours', () {
      final ll = [
        {'li': 'A'},
        {'li': 'B'}
      ];
      final last = {'A': now - (stale + 3600000), 'B': now - 1000}; // A 13h ago
      final r = computePatroli(ll, last, now, stale);
      expect(r.staleCount, 1);
      expect(r.qs, 'warn');
      expect(r.longestGapHours, 13);
    });
    test('never-patrolled point counts as stale', () {
      final ll = [
        {'li': 'A'},
        {'li': 'B'}
      ];
      final last = {'A': now - 1000}; // B never visited
      final r = computePatroli(ll, last, now, stale);
      expect(r.staleCount, 1);
      expect(r.qs, 'warn');
    });
    test('non-map / missing li tolerated', () {
      final ll = [
        'oops',
        {'li': 'A'}
      ];
      final r = computePatroli(ll, {'A': now - 1000}, now, stale);
      expect(r.llCount, 1);
      expect(r.staleCount, 0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `'latestPatrolByPoint' isn't defined` / `'computePatroli' isn't defined`.

- [ ] **Step 3: Implement**

Append to `lib/widget/panel_card_support.dart`:

```dart
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

/// For each point: gap = now - latest patrol epoch. A point with gap ≥ `staleMs`
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP while no-commit)

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): Patroli aggregation helpers"
```

---

### Task 4: Wire `ListMultiplePanelCard` to real aggregation

**Files:**
- Modify: `lib/widget/list_multiple_panel_card.dart`

Subscribe to `workforce` + `event` alongside `site`; precompute `_nowMs`/`_workersBySv`/`_lastVisitByLi` once per build (reads the two observables inside `Obx` for reactivity); make `_computeCardValues` real; read the threshold; apply the `okText` fallback.

- [ ] **Step 1: Add fields**

In `lib/widget/list_multiple_panel_card.dart`, replace the state fields block:

```dart
  List<String> _textArray = [];
  List<PanelConfig> _panels = [];
  String _code = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expanded = {'danger': true, 'warn': true, 'ok': true};
```

with:

```dart
  List<String> _textArray = [];
  List<PanelConfig> _panels = [];
  String _code = ''; // site subcollection code
  String _workforceCode = '';
  String _eventCode = '';
  int _staleMs = 43200000; // 12h default, configurable via component['staleMs']
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expanded = {'danger': true, 'warn': true, 'ok': true};
  // Build-scoped precomputed indexes (rebuilt each Obx pass).
  int _nowMs = 0;
  Map<String, List<Map<String, dynamic>>> _workersBySv = const {};
  Map<String, int> _lastVisitByLi = const {};
```

- [ ] **Step 2: Read the threshold in `_initConfig`**

Replace `_initConfig`:

```dart
  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    _panels = parsePanels(widget.component['panels']);
  }
```

with:

```dart
  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    _panels = parsePanels(widget.component['panels']);
    _staleMs =
        int.tryParse((widget.component['staleMs'] ?? '').toString()) ?? 43200000;
  }
```

- [ ] **Step 3: Subscribe to all three subcollections**

Replace `_subscribe`:

```dart
  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    _code = '${tp.tableDocId}/${tp.subColl}';
    if (tp.tableDocId.isNotEmpty && appVid.isNotEmpty) {
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    }
  }
```

with:

```dart
  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    _code = '${tp.tableDocId}/${tp.subColl}'; // site (or whatever subColl)
    _workforceCode = '${tp.tableDocId}/workforce';
    _eventCode = '${tp.tableDocId}/event';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    subscribeToMapCollection(appVid, tp.tableDocId, 'workforce', _workforceCode);
    subscribeToMapCollection(appVid, tp.tableDocId, 'event', _eventCode);
  }
```

- [ ] **Step 4: Make `_computeCardValues` real**

Replace `_computeCardValues`:

```dart
  /// Fase 1: only `{llCount}` is real ...
  Map<String, String> _computeCardValues(Map<String, dynamic> doc) =>
      {'llCount': llCount(doc).toString()};
```

with:

```dart
  /// Real aggregation from the build-scoped indexes: Kehadiran (workforce by
  /// sv) + Patroli (events joined to ll[].li). `{ws}` = worst(ps, qs).
  Map<String, String> _computeCardValues(Map<String, dynamic> doc) {
    final String sv = (doc['sv'] ?? '').toString();
    final KehadiranAgg keh =
        computeKehadiran(_workersBySv[sv] ?? const <Map<String, dynamic>>[]);
    final List<dynamic> ll =
        (doc['ll'] is List) ? doc['ll'] as List : const [];
    final PatroliAgg pat =
        computePatroli(ll, _lastVisitByLi, _nowMs, _staleMs);
    return {
      'hadir': '${keh.hadir}',
      'issues': keh.issues,
      'ps': keh.ps,
      'llCount': '${pat.llCount}',
      'staleCount': '${pat.staleCount}',
      'longestGap': '${pat.longestGapHours}',
      'qs': pat.qs,
      'ws': worstStatus([keh.ps, pat.qs]),
    };
  }
```

- [ ] **Step 5: Precompute indexes at the top of `build`**

In `build`, replace the opening of the `Obx` body:

```dart
    return Obx(() {
      final List<Map<String, dynamic>> all =
          List<Map<String, dynamic>>.from(mapTableContent[_code] ?? const []);
      final List<Map<String, dynamic>> filtered = _search(_searchQuery, all);
      final groups = groupByStatus<Map<String, dynamic>>(
        filtered,
        (doc) => _cardWorstStatus(doc, _computeCardValues(doc)),
      );
```

with:

```dart
    return Obx(() {
      final List<Map<String, dynamic>> all =
          List<Map<String, dynamic>>.from(mapTableContent[_code] ?? const []);
      // Read workforce + event observables INSIDE Obx (reactivity) and index
      // them once per build; per-card aggregation is then O(points)/O(1).
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _workersBySv = groupBySv(List<Map<String, dynamic>>.from(
          mapTableContent[_workforceCode] ?? const []));
      _lastVisitByLi = latestPatrolByPoint(List<Map<String, dynamic>>.from(
          mapTableContent[_eventCode] ?? const []));
      final List<Map<String, dynamic>> filtered = _search(_searchQuery, all);
      final groups = groupByStatus<Map<String, dynamic>>(
        filtered,
        (doc) => _cardWorstStatus(doc, _computeCardValues(doc)),
      );
```

- [ ] **Step 6: Apply the `okText` fallback in `_buildPanel`**

In `_buildPanel`, replace:

```dart
    final PanelText t =
        splitPanelText(_resolve(p.text, doc, v));
    final String status = _panelStatus(p, doc, v);
```

with:

```dart
    final PanelText t = splitPanelText(_resolve(p.text, doc, v));
    final String status = _panelStatus(p, doc, v);
    final String details = (normalizeStatus(status) == 'ok' && p.okText.isNotEmpty)
        ? p.okText
        : t.details;
```

Then, further down in `_buildPanel`, replace BOTH references to `t.details` in the details `Text` block:

```dart
                  if (t.details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.details,
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF9AA1AD))),
                  ],
```

with:

```dart
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(details,
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF9AA1AD))),
                  ],
```

- [ ] **Step 7: Verify it compiles**

Run: `flutter analyze lib/widget/list_multiple_panel_card.dart`
Expected: `No issues found!`. Confirm `computeKehadiran`/`KehadiranAgg`/`groupBySv`/`computePatroli`/`PatroliAgg`/`latestPatrolByPoint`/`normalizeStatus` all resolve from `panel_card_support.dart`, and `llCount` (Phase A) is no longer referenced by `_computeCardValues` (it now uses `computePatroli`).

- [ ] **Step 8: Run full support suite + commit** (SKIP commit while no-commit)

Run: `flutter test test/panel_card_support_test.dart` — all pass.

```bash
git add lib/widget/list_multiple_panel_card.dart
git commit -m "feat(panel-card): wire real Kehadiran + Patroli aggregation"
```

---

### Task 5: Manual verification

**Files:** none (manual).

- [ ] **Step 1** Ensure the data prerequisites are live: workers carry `sv` (= site `sv`); patrol events write to `tables/{tableDocId}/event` with `ty`/`t`/`lq`. Add `"okText":"Tidak ada jeda signifikan"` to the patrol panel JSON for the ok-state details.

- [ ] **Step 2** Hot restart (`R`) and open the cost-center screen.

- [ ] **Step 3** Confirm real values:
  - KEHADIRAN headline `{hadir}/<nm> hadir` (e.g. "0/2 hadir" if no one scanned); details = issues ("2 belum scan" / "Semua beres"); pill reflects `{ps}`.
  - PATROLI headline `{llCount} titik`; details `{staleCount} titik jeda lama · terlama {longestGap} jam`, or "Tidak ada jeda signifikan" when `{qs}`=ok; pill reflects `{qs}`.
  - Card left strip + accordion group (PERLU TINDAK / PERHATIAN / AMAN) + colored summary reflect `{ws}` (worst of the two panels).

- [ ] **Step 4** Edit a worker's `ci`/`co` or add/age a patrol event in Firestore → the card live-updates (Obx) status/grouping/summary.

---

## Self-Review

**Coverage:** `{hadir}`/`{issues}`/`{ps}` (Task 2, `computeKehadiran`, join by `sv` via `groupBySv` in Task 4) ✓; `{staleCount}`/`{longestGap}`/`{qs}` (Task 3, `computePatroli` + `latestPatrolByPoint`, join `lq`==`li`, threshold) ✓; `{ws}` = `worstStatus([ps,qs])` (Task 4) ✓; `{llCount}` from `computePatroli.llCount` (Task 4) ✓; threshold configurable via `staleMs` (Task 4 `_initConfig`) ✓; ok-state fallback via `okText` (Task 1 + Task 4 Step 6) ✓; reactivity (workforce/event read inside Obx) ✓; perf (one pass index per build) ✓; existing render/grouping/summary unchanged — activates automatically once `_computeCardValues` returns real values ✓.

**Placeholders:** none — every step has complete code. Open decisions (st filter, cleaning types, never-patrolled label, synced clock) are documented defaults, not gaps.

**Type consistency:** helpers `attendanceSet(dynamic)→bool`, `groupBySv(List<Map>)→Map<String,List<Map>>`, `computeKehadiran(List<Map>)→KehadiranAgg{hadir,issues,ps}`, `latestPatrolByPoint(List<Map>)→Map<String,int>`, `computePatroli(List,Map<String,int>,int,int)→PatroliAgg{llCount,staleCount,longestGapHours,qs}`, `PanelConfig.okText` — names/signatures match across Tasks 1-4. Build-scoped fields `_nowMs:int`, `_workersBySv:Map<String,List<Map>>`, `_lastVisitByLi:Map<String,int>`, `_staleMs:int` consistent. `_computeCardValues` returns the exact token keys the panel templates reference (`hadir`/`issues`/`ps`/`llCount`/`staleCount`/`longestGap`/`qs`/`ws`).
