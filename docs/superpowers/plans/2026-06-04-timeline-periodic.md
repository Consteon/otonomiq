# TIMELINE (variant `periodic`) — Patrol Point Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Execution is NO-COMMIT per the user — implement + test each task but SKIP every `git add`/`git commit` step until told otherwise.**

**Goal:** Add the `periodic` variant of the server-driven `TIMELINE` component — a per-point patrol visit timeline (status dots, relative time, evidence badge, who + capture method, note, "Jeda N jam" gap pills, period selector, locked-note footer).

**Architecture:** Sibling of `ListStatisticCard`. Pure logic in a tested support file `lib/widget/timeline_periodic_support.dart` (relative time, method, gap, multi-condition filter). A new `StatefulWidget` `TimelinePeriodic` binds those + reused `statistic_card_support` helpers (`parsePeriods`/`deriveEvidence`/`eventEpoch`) to the map store (`mapTableContent` via `subscribeToMapCollection`/`Obx`). The `tip=='timeline'` dispatch routes `variant=='periodic'` to it; the existing `Timeline` is untouched. The LIST_STATISTIC_CARD tap is extended to dispatch `point` into `screenTx`.

**Tech Stack:** Flutter, GetX (`Obx`, `mapTableContent`), Redux (`transactionStore` read), `intl` (`DateFormat`), reused `statistic_card_support.dart` / `panel_card_support.dart`.

**Spec:** `docs/superpowers/specs/2026-06-04-timeline-periodic-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/widget/timeline_periodic_support.dart` | Pure: `relativeTimestamp`, `MethodInfo`/`deriveMethod`, `gapLabel`, `resolveAngleTokens`, `filterEventsByConditions`. Imports only `package:intl`. | Create |
| `test/timeline_periodic_support_test.dart` | Unit tests for every helper. | Create |
| `lib/widget/timeline_periodic.dart` | `TimelinePeriodic` widget: subscribe `event`, period state, `Obx` render (header + tabs + timeline list + gap pills + footer). | Create |
| `lib/widget/all_widget.dart` | Barrel — add export. | Modify |
| `lib/widget/build_display_component.dart` | `tip=='timeline'` → route `variant=='periodic'` to `TimelinePeriodic`. | Modify |
| `lib/widget/list_statistic_card.dart` | `_onPointTap` also dispatches `'point'`. | Modify |

**Reused (imported by the widget):** `statusColor`/`statusBgColor`/`normalizeStatus`/`resolveMapTokens`/`parseTablePath`/`TablePath` (`panel_card_support.dart`); `parsePeriods`/`PeriodOption`/`deriveEvidence`/`eventEpoch` (`statistic_card_support.dart`); `mapTableContent`/`diamondTextToList`/`autheniumDecode` (`global.dart`); `subscribeToMapCollection` (`table_repository.dart`); `transactionStore` (`redux/screen_transaction.dart`).

---

### Task 1: `relativeTimestamp`

**Files:**
- Create: `lib/widget/timeline_periodic_support.dart`
- Test: `test/timeline_periodic_support_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/timeline_periodic_support_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/timeline_periodic_support.dart';

void main() {
  group('relativeTimestamp', () {
    final now = DateTime(2026, 6, 4, 15, 0).millisecondsSinceEpoch;
    test('same calendar day → "HH:mm hari ini"', () {
      final t = DateTime(2026, 6, 4, 13, 42).millisecondsSinceEpoch;
      expect(relativeTimestamp(t, now), '13:42 hari ini');
    });
    test('yesterday → "Kemarin HH:mm"', () {
      final t = DateTime(2026, 6, 3, 14, 55).millisecondsSinceEpoch;
      expect(relativeTimestamp(t, now), 'Kemarin 14:55');
    });
    test('older → "N hari lalu"', () {
      final t = DateTime(2026, 6, 2, 9, 10).millisecondsSinceEpoch;
      expect(relativeTimestamp(t, now), '2 hari lalu');
    });
  });
}
```

> Test epochs are built with `DateTime(...).millisecondsSinceEpoch` (local) and read back local, so `HH:mm` and the calendar-day diff are timezone-consistent. Times are mid-day to avoid midnight-boundary flakiness.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'otonomiq' ... timeline_periodic_support.dart` / `'relativeTimestamp' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/widget/timeline_periodic_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/timeline_periodic_support.dart test/timeline_periodic_support_test.dart
git commit -m "feat(timeline-periodic): relativeTimestamp"
```

---

### Task 2: `MethodInfo` + `deriveMethod`

**Files:**
- Modify: `lib/widget/timeline_periodic_support.dart`
- Test: `test/timeline_periodic_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/timeline_periodic_support_test.dart`:

```dart
  group('deriveMethod', () {
    test('QR vs typed, with/without foto, isQr flag', () {
      final qrFoto = deriveMethod('q1', true);
      expect(qrFoto.label, 'Scan QR + foto');
      expect(qrFoto.isQr, isTrue);
      expect(deriveMethod('', true).label, 'Lokasi diketik + foto');
      expect(deriveMethod('', true).isQr, isFalse);
      expect(deriveMethod('q1', false).label, 'Scan QR');
      expect(deriveMethod('   ', false).label, 'Lokasi diketik'); // blank lq = typed
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: FAIL — `'deriveMethod' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/timeline_periodic_support.dart`:

```dart
/// Capture method for a timeline entry. `label` is the display text; `isQr`
/// drives the row icon (QR code vs text-cursor).
class MethodInfo {
  final String label;
  final bool isQr;
  const MethodInfo(this.label, this.isQr);
}

/// `lq` non-empty → "Scan QR" (QR-scanned), empty → "Lokasi diketik" (typed).
/// Appends " + foto" when the entry has an image.
MethodInfo deriveMethod(String lq, bool hasImage) {
  final bool isQr = lq.trim().isNotEmpty;
  final String base = isQr ? 'Scan QR' : 'Lokasi diketik';
  return MethodInfo(hasImage ? '$base + foto' : base, isQr);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/timeline_periodic_support.dart test/timeline_periodic_support_test.dart
git commit -m "feat(timeline-periodic): MethodInfo + deriveMethod"
```

---

### Task 3: `gapLabel`

**Files:**
- Modify: `lib/widget/timeline_periodic_support.dart`
- Test: `test/timeline_periodic_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/timeline_periodic_support_test.dart`:

```dart
  group('gapLabel', () {
    const gapMs = 43200000; // 12h
    const t = 1000000000000;
    test('below threshold → empty', () {
      expect(gapLabel(t, t - 6 * 3600000, gapMs), '');
    });
    test('jam when < 48h', () {
      expect(gapLabel(t, t - 23 * 3600000, gapMs), 'Jeda 23 jam');
      expect(gapLabel(t, t - 30 * 3600000, gapMs), 'Jeda 30 jam');
    });
    test('hari when >= 48h', () {
      expect(gapLabel(t, t - 50 * 3600000, gapMs), 'Jeda 2 hari');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: FAIL — `'gapLabel' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/timeline_periodic_support.dart`:

```dart
/// Gap pill text between two consecutive (newer, older) entries. Below `gapMs`
/// → "" (no pill). `< 48h` → "Jeda N jam"; otherwise "Jeda N hari". (The 48h
/// jam→hari cutoff keeps mid-range gaps like 30h shown in hours, per design.)
String gapLabel(int newerT, int olderT, int gapMs) {
  final int gap = newerT - olderT;
  if (gap < gapMs) return '';
  if (gap < 172800000) return 'Jeda ${gap ~/ 3600000} jam';
  return 'Jeda ${gap ~/ 86400000} hari';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/timeline_periodic_support.dart test/timeline_periodic_support_test.dart
git commit -m "feat(timeline-periodic): gapLabel"
```

---

### Task 4: `resolveAngleTokens` + `filterEventsByConditions`

**Files:**
- Modify: `lib/widget/timeline_periodic_support.dart`
- Test: `test/timeline_periodic_support_test.dart`

Resolves `<key>` markers from `screenTx`, then filters event docs by a multi-field AND
equality parsed from `[[◀field▶◼value…]]`.

- [ ] **Step 1: Write the failing test**

Append to `test/timeline_periodic_support_test.dart`:

```dart
  group('resolveAngleTokens', () {
    test('<key> from screenTx, unknown left literal', () {
      expect(resolveAngleTokens('ln◼<point>', {'point': 'Genset'}), 'ln◼Genset');
      expect(resolveAngleTokens('ln◼<point>', const {}), 'ln◼<point>');
    });
  });

  group('filterEventsByConditions', () {
    final events = [
      {'ln': 'Genset', 'ty': 'report-patrol', 'cn': 'Agus'},
      {'ln': 'Genset', 'ty': 'report-incident', 'cn': 'Budi'}, // ty mismatch
      {'ln': 'Mushola', 'ty': 'report-patrol', 'cn': 'Sari'}, // ln mismatch
    ];
    test('AND match on ln + ty with <point> resolved', () {
      final r = filterEventsByConditions(
          events, '[[◀ln▶◼<point>◀ty▶◼report-patrol]]', {'point': 'Genset'});
      expect(r.length, 1);
      expect(r.first['cn'], 'Agus');
    });
    test('unresolved <point> → no match', () {
      expect(
          filterEventsByConditions(
              events, '[[◀ln▶◼<point>◀ty▶◼report-patrol]]', const {}),
          isEmpty);
    });
    test('empty conditions → unchanged list', () {
      expect(filterEventsByConditions(events, '', const {}).length, 3);
    });
  });
```

> Append the two groups above **inside** `main()` — before the single closing `}`
> that Task 1 created. Do NOT add another `}`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: FAIL — `'resolveAngleTokens' isn't defined` / `'filterEventsByConditions' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/timeline_periodic_support.dart`:

```dart
/// Resolve `<key>` markers in `raw` against `screenTx` (missing → left literal).
String resolveAngleTokens(String raw, Map<String, dynamic> screenTx) {
  return raw.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
    final v = screenTx[m.group(1)];
    return v == null ? m.group(0)! : v.toString();
  });
}

final RegExp _condPair = RegExp(r'◀([a-zA-Z][a-zA-Z0-9]*)▶◼([^◀▶\]]*)');

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit** (SKIP — no-commit)

```bash
git add lib/widget/timeline_periodic_support.dart test/timeline_periodic_support_test.dart
git commit -m "feat(timeline-periodic): resolveAngleTokens + filterEventsByConditions"
```

---

### Task 5: `TimelinePeriodic` widget

**Files:**
- Create: `lib/widget/timeline_periodic.dart`

Subscribes the `event` subcollection; filters by `ln==<point>` AND `ty==report-patrol`;
windows by the selected period; sorts newest-first; renders header + period tabs +
vertical timeline (status dots + cards + gap pills) + locked-note footer.

- [ ] **Step 1: Create the widget file**

Create `lib/widget/timeline_periodic.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';
import 'timeline_periodic_support.dart';

/// TIMELINE variant `periodic` — per-point patrol visit timeline. Binds to the
/// `event` subcollection (char-code map docs), filters by `ln == screenTx['point']`
/// AND `ty == report-patrol`, windows by a period selector, and renders a
/// newest-first vertical timeline: status dot + relative time + evidence badge +
/// "oleh <cn>" + capture method + note, with "Jeda N jam" gap pills and a
/// locked-note footer.
class TimelinePeriodic extends StatefulWidget {
  const TimelinePeriodic({
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
  State<TimelinePeriodic> createState() => _TimelinePeriodicState();
}

const String _kDefaultFooter =
    'Catatan tak bisa diubah. Setiap kunjungan terkunci sejak dibuat. '
    'Sistem tidak menyajikan "rata-rata" atau "frekuensi normal" — itu bisa '
    'dibaca sebagai standar.';

class _TimelinePeriodicState extends State<TimelinePeriodic> {
  List<PeriodOption> _periods = [];
  int _selectedMs = 604800000;
  int _gapMs = 43200000;
  String _eventCode = '';
  int _nowMs = 0;
  int _windowStartMs = 0;

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    final String periodRaw = (widget.component['period'] ?? '').toString();
    _periods = parsePeriods(autheniumDecode(periodRaw) ?? periodRaw);
    _gapMs =
        int.tryParse((widget.component['gapMs'] ?? '').toString()) ?? 43200000;
    final int def =
        int.tryParse((widget.component['periodDefault'] ?? '').toString()) ?? 0;
    _selectedMs = _periods.any((p) => p.ms == def)
        ? def
        : (_periods.isNotEmpty ? _periods.first.ms : 604800000);
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    _eventCode = '${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _eventCode);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  String get _selectedLabel {
    for (final p in _periods) {
      if (p.ms == _selectedMs) return p.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> events =
          List<Map<String, dynamic>>.from(mapTableContent[_eventCode] ?? const []);
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _windowStartMs = _nowMs - _selectedMs;

      final String conditions =
          (widget.component['conditions'] ?? '').toString();
      final List<Map<String, dynamic>> matched =
          filterEventsByConditions(events, conditions, _screenTx);
      final List<Map<String, dynamic>> windowed = matched
          .where((e) => eventEpoch(e) >= _windowStartMs)
          .toList()
        ..sort((a, b) => eventEpoch(b).compareTo(eventEpoch(a)));

      final String pointName = (_screenTx['point'] ??
              (windowed.isNotEmpty ? windowed.first['ln'] : '') ??
              '')
          .toString();
      final String title = resolveMapTokens(
          (widget.component['title'] ?? '').toString(),
          {'ln': pointName},
          const {});
      final String subtitle = resolveMapTokens(
          (widget.component['subtitle'] ?? '').toString(),
          const {},
          {'visitCount': '${windowed.length}'});

      final List<Widget> entries = [];
      for (int i = 0; i < windowed.length; i++) {
        entries.add(_buildEntry(windowed[i]));
        if (i < windowed.length - 1) {
          final String gap = gapLabel(
              eventEpoch(windowed[i]), eventEpoch(windowed[i + 1]), _gapMs);
          if (gap.isNotEmpty) entries.add(_buildGapPill(gap));
        }
      }

      final double availableH = MediaQuery.of(context).size.height * 0.82;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              widget.lPad, widget.tPad, widget.rPad, widget.bPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2233))),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 14, color: Color(0xFF9AA1AD))),
              ],
              const SizedBox(height: 14),
              if (_periods.isNotEmpty) _buildPeriodTabs(),
              const SizedBox(height: 14),
              Expanded(
                child: windowed.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          ...entries,
                          const SizedBox(height: 14),
                          _buildFooter(),
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
                  ),
                  child: Text(p.label,
                      style: TextStyle(
                          fontSize: 13,
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

  Widget _buildEmptyState() {
    return const Center(
      child: Text('Belum ada kunjungan',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
    );
  }

  /// Left rail: a continuous vertical line with a hollow status-colored dot.
  Widget _rail(Color ringColor, {IconData? icon}) {
    return SizedBox(
      width: 30,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Center(
                child: Container(width: 2, color: const Color(0xFFE5E7EB))),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: icon != null
                ? Icon(icon, size: 16, color: ringColor)
                : Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 3),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(Map<String, dynamic> e) {
    final String lq = (e['lq'] ?? '').toString();
    final bool hasImage = (e['i'] ?? '').toString().trim().isNotEmpty;
    final String evidence = deriveEvidence(lq);
    final MethodInfo method = deriveMethod(lq, hasImage);
    final String mapped = evidence == 'Bukti kuat' ? 'ok' : 'warn';
    final Color dotColor = statusColor(mapped);

    final Map<String, dynamic> doc = Map<String, dynamic>.from(e)
      ..['ts'] = relativeTimestamp(eventEpoch(e), _nowMs);
    final List<String> seg = diamondTextToList(resolveMapTokens(
        (widget.component['text'] ?? '').toString(), doc, {'method': method.label}));
    String at(int i) => seg.length > i ? seg[i] : '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(dotColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEEF0F2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(at(0),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A2233))),
                        ),
                        const SizedBox(width: 8),
                        _evidenceBadge(evidence),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(at(1),
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280))),
                        const SizedBox(width: 10),
                        Icon(method.isQr ? Icons.qr_code_2 : Icons.text_fields,
                            size: 15, color: const Color(0xFF9AA1AD)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(at(2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF6B7280))),
                        ),
                      ],
                    ),
                    if (at(3).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('"${at(3)}"',
                          style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF9AA1AD))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGapPill(String label) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(const Color(0xFFD97706), icon: Icons.hourglass_bottom),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF1D08A)),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309))),
            ),
          ),
        ],
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
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: statusColor(mapped))),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final String footer =
        (widget.component['footer'] ?? '').toString().trim().isNotEmpty
            ? widget.component['footer'].toString()
            : _kDefaultFooter;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 16, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(footer,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: Color(0xFF9CA3AF))),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/widget/timeline_periodic.dart`
Expected: No `error` lines. Confirm every referenced symbol resolves: `parsePeriods`,
`PeriodOption`, `deriveEvidence`, `eventEpoch` (`statistic_card_support.dart`);
`statusColor`, `statusBgColor`, `resolveMapTokens`, `parseTablePath`, `TablePath`
(`panel_card_support.dart`); `relativeTimestamp`, `deriveMethod`, `MethodInfo`, `gapLabel`,
`filterEventsByConditions` (`timeline_periodic_support.dart`); `mapTableContent`,
`autheniumDecode`, `diamondTextToList`, `transactionStore`, `subscribeToMapCollection`
(globals/redux/repository).

> Note: `transactionStore` resolves through `global.dart` (the sibling
> `list_statistic_card.dart` imports `redux/screen_transaction.dart` explicitly — if
> `flutter analyze` reports `transactionStore` undefined, add
> `import '../redux/screen_transaction.dart';`).

- [ ] **Step 3: Commit** (SKIP — no-commit)

```bash
git add lib/widget/timeline_periodic.dart
git commit -m "feat(timeline-periodic): TimelinePeriodic widget"
```

---

### Task 6: Register the variant + extend the card tap

**Files:**
- Modify: `lib/widget/all_widget.dart`
- Modify: `lib/widget/build_display_component.dart` (the `tip=='timeline'` branch ~L1182)
- Modify: `lib/widget/list_statistic_card.dart` (`_onPointTap`)

- [ ] **Step 1: Add the barrel export**

In `lib/widget/all_widget.dart`, near the other widget exports, add:

```dart
export 'timeline_periodic.dart';
```

- [ ] **Step 2: Route the `periodic` variant in the dispatch**

In `lib/widget/build_display_component.dart`, replace the existing `timeline` branch:

```dart
  } else if (tip == 'timeline') {
    try {
      result = Timeline(
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

with:

```dart
  } else if (tip == 'timeline') {
    try {
      final String tlVariant =
          (component['variant'] ?? '').toString().trim().toLowerCase();
      if (tlVariant == 'periodic') {
        result = TimelinePeriodic(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else {
        result = Timeline(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      }
    } catch (e) {
      result = Text('--${component['type']}-- Error: $e');
    }
```

- [ ] **Step 3: Dispatch `point` on the card tap**

In `lib/widget/list_statistic_card.dart`, in `_onPointTap`, replace:

```dart
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      'pointId': (point['li'] ?? '').toString(),
      'pointName': (point['ln'] ?? '').toString(),
      'point_route': route,
    })));
```

with (adds `point`, which `<point>` resolves against on the timeline):

```dart
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      'point': (point['ln'] ?? '').toString(),
      'pointId': (point['li'] ?? '').toString(),
      'pointName': (point['ln'] ?? '').toString(),
      'point_route': route,
    })));
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/widget/build_display_component.dart lib/widget/all_widget.dart lib/widget/list_statistic_card.dart`
Expected: No NEW `error` lines (pre-existing `info`/`warning` elsewhere are fine).
`TimelinePeriodic` resolves via the barrel import.

- [ ] **Step 5: Run the full support suite** + commit (SKIP commit — no-commit)

Run: `flutter test test/timeline_periodic_support_test.dart`
Expected: PASS (all groups).

```bash
git add lib/widget/all_widget.dart lib/widget/build_display_component.dart lib/widget/list_statistic_card.dart
git commit -m "feat(timeline-periodic): register periodic variant + dispatch point context"
```

---

### Task 7: Manual verification

**Files:** none (manual).

- [ ] **Step 1** Wire the `vertikaTeknoLokaciptaPatrolPointTimeline` page (Sheets/proxy)
  hosting the TIMELINE component JSON from the spec, and confirm the LIST_STATISTIC_CARD
  `route` points to it. Ensure `event` docs carry `ln`/`cn`/`lq`/`t`/`ty`/`d`/`i`.

- [ ] **Step 2** Run the app: `./set_android.sh && flutter run`. From the cost-center card →
  "Patroli & Cleaning" panel → a point card → tap it.

- [ ] **Step 3** Confirm:
  - header = point name + "{visitCount} Kunjungan Periode Ini"; period tabs default **7 hari**;
  - newest-first entries: relative time ("13:42 hari ini" / "Kemarin 14:55" / "N hari lalu"),
    evidence badge (Bukti kuat green / GPS saja amber) + matching dot color, "oleh <cn>" +
    method ("Scan QR + foto" / "Lokasi diketik + foto") with QR/text icon, note in italic quotes;
  - "Jeda N jam" pills only between entries ≥ 12h apart;
  - locked-note footer at the bottom;
  - changing the period tab re-windows + recomputes; empty window → "Belum ada kunjungan".

- [ ] **Step 4** Verify the filter: only events whose `ln` equals the tapped point AND
  `ty == report-patrol` appear. A manual-typed visit (empty `lq`) shows "Lokasi diketik" +
  "GPS saja" + amber dot.

---

## Self-Review

**Spec coverage (spec § → task):**
- Map binding to `event` + `<point>` filter (ln AND ty) → Task 4 (`filterEventsByConditions`), Task 5 (`_subscribe`/build).
- `<point>` from screenTx via card tap → Task 6 Step 3.
- Period window + default 7d + newest-first → Task 5 (`_initConfig`/build sort).
- Header `<ln>`/`{visitCount}` → Task 5 (build `title`/`subtitle`).
- `<ts>` relative → Task 1 (`relativeTimestamp`), Task 5 (`ts` override before resolve).
- `{method}` + icon → Task 2 (`deriveMethod`), Task 5 (`_buildEntry`).
- `{evidence}` badge + dot color → reused `deriveEvidence` (statistic_card_support) + Task 5.
- `{gap}` divider, 12h, jam/hari → Task 3 (`gapLabel`), Task 5 (entry loop).
- Layout (dots/line/cards/gap pills/footer) → Task 5.
- Footer text (`component['footer']` else default) → Task 5 (`_buildFooter`, `_kDefaultFooter`).
- Dispatch variant routing → Task 6 Step 2; barrel → Task 6 Step 1.
- Testing → Tasks 1-4 unit tests; Task 7 manual.

**Placeholder scan:** none — every step has complete test + implementation code, exact paths, exact commands.

**Type consistency:** `relativeTimestamp(int,int)→String`, `MethodInfo{label,isQr}` + `deriveMethod(String,bool)→MethodInfo`, `gapLabel(int,int,int)→String`, `resolveAngleTokens(String,Map)→String`, `filterEventsByConditions(List<Map>,String,Map)→List<Map>` — names/signatures identical across the widget (Task 5) and the helpers (Tasks 1-4). Reused `parsePeriods`/`PeriodOption`/`deriveEvidence`/`eventEpoch` match `statistic_card_support.dart`; `statusColor`/`statusBgColor`/`resolveMapTokens`/`parseTablePath`/`TablePath` match `panel_card_support.dart`. Dispatch string `'periodic'` = `component['variant'].toLowerCase()`.
