# Kehadiran (Attendance) Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a server-driven attendance ("Kehadiran") worker list + per-worker correction page over the KEYED `workforce` Firestore table, and add a generic `updateEventRow` primitive so a supervisor can patch a worker's display clock times in place.

**Architecture:** Three independent, server-driven pieces. (1) A new dispatch-level widget `ListStatisticCardKeyed` (variant of `LIST_STATISTIC_CARD`) that reads `workforce` keyed docs — one card per doc — filtered by `sv == {ccVid}`, with attendance aggregate + per-card status tokens. (2) A `variant:"keyed"` branch of `WORKER_CARD_DETAIL` that reads one keyed doc by `<vid>`. (3) A new `updateEventRow` write primitive (keyed sibling of `updateTableRow`) wired through `saveSend` → `history[14]` → `historySync`. All data shapes, separators, and the read/write Firestore paths were verified against the codebase before this plan was written.

**Tech Stack:** Flutter, Dart ≥3.3.1, GetX (`mapTableContent` RxMap), Redux (`screenTx` nav params), cloud_firestore, flutter_test.

**Locked design facts (do NOT re-derive):**
- `workforce` = **1 doc per worker**, `vid` is **globally unique**. FK `sv` == cost center `av`/`sv`. `{ccVid}` (in `screenTx`) carries that value.
- Read path: `subscribeToMapCollection(appVid, tableDocId, subColl, code)` → `MobileTable/{appVid}/tables/{tableDocId}/{subColl}` → `mapTableContent[code]` (`List<Map<String,dynamic>>`).
- For this feature: `table = "84214220504259//workforce"`, `vidtable = "20342033315492"`. So `appVid = 20342033315492`, `tableDocId = 84214220504259`, `subColl = workforce`. Read & write resolve to `MobileTable/20342033315492/tables/84214220504259/workforce`.
- Issue derived from `ci`/`co`, never stored: `ci` not-set → "Belum scan" (danger); `ci` set & `co` not-set → "Belum clock-out" (warn); else ok. Use `attendanceSet()` (`-1`/`''`/`0` all mean not-set).
- Search per dev spec = SINGLE `search◼vid★<vid>`. No `☆` compound AND. (`parseSearchClause` still supports compound for reuse; it is just never exercised here.)
- Separators (`lib/global.dart:368`): `separator[0]`=`⬤`, `[1]`=`◆`, `[2]`=`◼`, `[3]`=`★`, `[6]`=`☆`, `[8]`=`⭘`. `folderSeparator`=`//` (`global.dart:329`).

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/widget/statistic_card_support.dart` | Add kehadiran-list aggregate + per-worker status helpers (pure functions) | Modify (append) |
| `lib/widget/list_statistic_card_keyed.dart` | New keyed worker-list widget (one card per `workforce` doc) | Create |
| `lib/widget/worker_card_detail_keyed.dart` | New keyed detail widget (one doc by `<vid>`) | Create |
| `lib/widget/build_display_component.dart` | Dispatch `variant:"keyed"` for `list_statistic_card` + `worker_card_detail` | Modify (`:1140`, `:1154`) |
| `lib/firestore_repository/update_event_row.dart` | New pure parser: `parseSearchClause`, `parseUpdateEventRow`, `UpdateEventTarget` | Create |
| `lib/firestore_repository/table_repository.dart` | New `writeUpdateEventRow` (Firestore I/O); wire `historySync` 5th segment | Modify (`:2699`, append) |
| `lib/api.dart` | `saveSend`: read `component['updateEventRow']` → append 5th `⬤`-segment | Modify (`:3692-3710`) |
| `test/kehadiran_support_test.dart` | Unit tests for aggregate + status helpers | Create |
| `test/update_event_row_test.dart` | Unit tests for `parseSearchClause` + `parseUpdateEventRow` | Create |
| `docs/firestore/update_event_row.md` | Op doc for `updateEventRow` | Create |

**Why a new widget file (not branching inside `ListStatisticCard`):** the existing widget builds items from ONE matched site doc's nested `ll[]` array (`list_statistic_card.dart:110-123`); the keyed worker list builds one card PER doc. Different data model → separate widget keeps the patrol path untouched (user decision: "new widget, dispatch-level").

---

## PART 1 — Kehadiran aggregate + per-worker status helpers (pure, TDD)

Append to `lib/widget/statistic_card_support.dart`. These feed the keyed list widget's stat boxes and per-card status. Reuse `attendanceSet` (already in `panel_card_support.dart:228`).

### Task 1: `workerStatus` + `workerStatusLine`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart` (append at end)
- Test: `test/kehadiran_support_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/kehadiran_support_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';

void main() {
  Map<String, dynamic> w(dynamic ci, dynamic co) => {'ci': ci, 'co': co};

  group('workerStatus', () {
    test('ci not set -> danger', () {
      expect(workerStatus(w(-1, -1)), 'danger');
      expect(workerStatus(w('', '')), 'danger');
      expect(workerStatus(w(0, 0)), 'danger');
    });
    test('ci set, co not set -> warn', () {
      expect(workerStatus(w(1780000000000, -1)), 'warn');
    });
    test('ci set and co set -> ok', () {
      expect(workerStatus(w(1780000000000, 1780000900000)), 'ok');
    });
  });

  group('workerStatusLine', () {
    test('belum scan', () => expect(workerStatusLine(w(-1, -1)), 'Belum scan'));
    test('belum clock-out',
        () => expect(workerStatusLine(w(1, -1)), 'Belum clock-out'));
    test('ok -> empty', () => expect(workerStatusLine(w(1, 2)), ''));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/kehadiran_support_test.dart`
Expected: FAIL — `workerStatus`/`workerStatusLine` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`. Import `attendanceSet` by adding `import 'panel_card_support.dart';` at the top **only if not already present** (check the existing imports first; `statistic_card_support.dart` currently has no imports — add the line):

```dart
import 'panel_card_support.dart';
```

Then at the end of the file:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/kehadiran_support_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widget/statistic_card_support.dart test/kehadiran_support_test.dart
git commit -m "feat(kehadiran): add per-worker status helpers"
```

### Task 2: `KehadiranListAgg` + `computeKehadiranList`

**Files:**
- Modify: `lib/widget/statistic_card_support.dart` (append)
- Test: `test/kehadiran_support_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/kehadiran_support_test.dart`:

```dart
  group('computeKehadiranList', () {
    final workers = [
      {'ci': 1, 'co': 2}, // ok
      {'ci': 1, 'co': -1}, // belum clock-out -> perluTindak
      {'ci': -1, 'co': -1}, // belum scan -> belumScan + perluTindak
      {'ci': 1700, 'co': 1800}, // ok
    ];
    final agg = computeKehadiranList(workers.cast<Map<String, dynamic>>());

    test('total counts all', () => expect(agg.total, 4));
    test('hadir counts ci-set', () => expect(agg.hadir, 3));
    test('belumScan counts ci-not-set', () => expect(agg.belumScan, 1));
    test('perluTindak = belumScan OR (ci set & co not set)',
        () => expect(agg.perluTindak, 2));

    test('toTokens exposes the four counts', () {
      final t = agg.toTokens();
      expect(t['total'], '4');
      expect(t['hadir'], '3');
      expect(t['belumScan'], '1');
      expect(t['perluTindak'], '2');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/kehadiran_support_test.dart`
Expected: FAIL — `computeKehadiranList`/`KehadiranListAgg` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/statistic_card_support.dart`:

```dart
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
      this.total, this.hadir, this.belumScan, this.perluTindak);

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/kehadiran_support_test.dart`
Expected: PASS (11 tests total).

- [ ] **Step 5: Commit**

```bash
git add lib/widget/statistic_card_support.dart test/kehadiran_support_test.dart
git commit -m "feat(kehadiran): add worker-list attendance aggregate"
```

---

## PART 2 — Keyed worker-list widget + dispatch

### Task 3: Create `ListStatisticCardKeyed`

**Files:**
- Create: `lib/widget/list_statistic_card_keyed.dart`

This widget is verified by manual run (Task 5) — the codebase has no widget tests for `ListStatisticCard`; its logic is unit-tested via Part 1. Build it by adapting the patrol widget's reusable scaffolding.

- [ ] **Step 1: Write the widget**

Create `lib/widget/list_statistic_card_keyed.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// LIST_STATISTIC_CARD · variant:"keyed" — attendance worker list (today).
/// Reads the KEYED `workforce` subcollection (one doc per worker), filters to
/// `sv == {ccVid}`, renders one card per worker with attendance aggregate stat
/// boxes and a per-card status strip. Tapping a card pushes the worker's `vid`
/// to screenTx and routes to the correction page.
class ListStatisticCardKeyed extends StatefulWidget {
  const ListStatisticCardKeyed({
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
  State<ListStatisticCardKeyed> createState() => _ListStatisticCardKeyedState();
}

class _ListStatisticCardKeyedState extends State<ListStatisticCardKeyed> {
  List<String> _textArray = [];
  List<String> _contentArray = [];
  List<StatSpec> _statSpecs = [];
  String _code = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    try {
      _contentArray =
          diamondTextToList((widget.component['content'] ?? '').toString());
    } catch (_) {
      _contentArray = [];
    }
    final String statsRaw = (widget.component['stats'] ?? '').toString();
    _statSpecs = parseStatSpecs(autheniumDecode(statsRaw) ?? statsRaw);
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    _code = '${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  /// Workers matching the `sv == {ccVid}` filter (one card each).
  List<Map<String, dynamic>> _workers(List<Map<String, dynamic>> docs) {
    final String condRaw =
        (widget.component['conditions'] ?? widget.component['search'] ?? '')
            .toString();
    final String cond = autheniumDecode(condRaw) ?? condRaw;
    return filterByCharCodeEquality(docs, cond, _screenTx);
  }

  List<Map<String, dynamic>> _search(List<Map<String, dynamic>> workers) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return workers;
    return workers
        .where((w) => (w['n'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  void _onWorkerTap(Map<String, dynamic> worker) {
    final String route = (widget.component['route'] ?? '').toString();
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      'vid': (worker['vid'] ?? '').toString(),
      'n': (worker['n'] ?? '').toString(),
      'worker': (worker['n'] ?? '').toString(),
      'worker_route': route,
    })));
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> docs =
          List<Map<String, dynamic>>.from(mapTableContent[_code] ?? const []);
      final List<Map<String, dynamic>> workers = _workers(docs);
      final KehadiranListAgg agg = computeKehadiranList(workers);
      final List<Map<String, dynamic>> searched = _search(workers);

      // severity-desc (danger, warn, ok), then name asc.
      searched.sort((a, b) {
        final int sa = statusOrder.indexOf(workerStatus(a));
        final int sb = statusOrder.indexOf(workerStatus(b));
        final int ra = sa < 0 ? statusOrder.length : sa;
        final int rb = sb < 0 ? statusOrder.length : sb;
        if (ra != rb) return ra - rb;
        return (a['n'] ?? '').toString().compareTo((b['n'] ?? '').toString());
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
              if (_statSpecs.isNotEmpty) _buildStatBoxes(agg),
              const SizedBox(height: 14),
              _buildSearchField(),
              const SizedBox(height: 12),
              Expanded(
                child: searched.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final w in searched) _buildWorkerCard(w),
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

  Widget _buildStatBoxes(KehadiranListAgg agg) {
    final Map<String, String> tokens = agg.toTokens();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _statSpecs.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: _statBox(i, _statSpecs[i], tokens)),
          ],
        ],
      ),
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
                  fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
          const SizedBox(height: 4),
          Text(spec.label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final String hint = _textArray.isNotEmpty ? _textArray[0] : 'Cari worker';
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

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    final Map<String, String> tokens = {
      'status': workerStatus(worker),
      'statusLine': workerStatusLine(worker),
    };
    String at(int i) => _contentArray.length > i
        ? resolveMapTokens(_contentArray[i], worker, tokens)
        : '';
    final String statusTemplate =
        (widget.component['status'] ?? '{status}').toString();
    final String ps =
        normalizeStatus(resolveMapTokens(statusTemplate, worker, tokens));
    final Color sColor = statusColor(ps);
    final String name = at(0);
    final String line2 = at(1);
    final String line3 = at(2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onWorkerTap(worker),
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
                              Expanded(
                                child: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A2233))),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Color(0xFFC7CCD4), size: 20),
                            ],
                          ),
                          if (line2.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(line2,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280))),
                          ],
                          if (line3.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(line3,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ps == 'ok'
                                        ? const Color(0xFF9AA1AD)
                                        : sColor)),
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
}
```

- [ ] **Step 2: Analyze for compile errors**

Run: `flutter analyze lib/widget/list_statistic_card_keyed.dart`
Expected: No issues (all referenced symbols — `parseTablePath`, `subscribeToMapCollection`, `mapTableContent`, `filterByCharCodeEquality`, `resolveMapTokens`, `parseStatSpecs`, `statusColor`, `statusOrder`, `normalizeStatus`, `routeExist`, `routeStack`, `gotoRoute`, `transactionStore`, `UpdateScreenTxAction`, `ScreenTransaction` — exist in the imported files).

- [ ] **Step 3: Commit**

```bash
git add lib/widget/list_statistic_card_keyed.dart
git commit -m "feat(kehadiran): add ListStatisticCardKeyed worker-list widget"
```

### Task 4: Dispatch `variant:"keyed"` for `list_statistic_card`

**Files:**
- Modify: `lib/widget/build_display_component.dart:1140-1153`

- [ ] **Step 1: Replace the `list_statistic_card` branch**

Find this exact block at `lib/widget/build_display_component.dart:1140`:

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
  } else if (tip == 'worker_card_detail') {
```

Replace with (mirrors the `timeline` variant pattern at `:1182`):

```dart
  } else if (tip == 'list_statistic_card') {
    try {
      final String lscVariant =
          (component['variant'] ?? '').toString().trim().toLowerCase();
      if (lscVariant == 'keyed') {
        result = ListStatisticCardKeyed(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else {
        result = ListStatisticCard(
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
  } else if (tip == 'worker_card_detail') {
```

- [ ] **Step 2: Add the import**

Find the imports block at the top of `lib/widget/build_display_component.dart`. Confirm `list_statistic_card.dart` is imported (it must be, since `ListStatisticCard` is referenced). Add directly beneath it:

```dart
import 'list_statistic_card_keyed.dart';
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/widget/build_display_component.dart`
Expected: No new issues; `ListStatisticCardKeyed` resolves.

- [ ] **Step 4: Commit**

```bash
git add lib/widget/build_display_component.dart
git commit -m "feat(kehadiran): dispatch list_statistic_card variant:keyed"
```

### Task 5: Manual verification of the worker list

**Files:** none (verification only)

- [ ] **Step 1: Run the app to the Kehadiran panel**

Run: `flutter run` (attach a device/emulator). Navigate: cost-center card → tap the **"Kehadiran"** panel (route `vertikaTeknoLokaciptaCheckinSiteDetail`, op1Screen row 989).

- [ ] **Step 2: Confirm the rendered behavior**

Verify ALL of:
- One card per worker whose `sv` == the tapped cost center's `av`/`sv` (no other sites' workers).
- Stat boxes read `{hadir}/{total}`, `{belumScan}`, `{perluTindak}` with correct counts.
- Cards show `<n>`, `Masuk <is> · Keluar <os>`, and the `{statusLine}` ("Belum scan" / "Belum clock-out" / blank).
- Left strip color: red (belum scan) / amber (belum clock-out) / green (ok).
- Search box filters by name.
- Tapping a card navigates to the correction page (verified fully in Task 8 once the detail lands).

Expected: matches the dev spec §2. If counts/filter are wrong, debug `filterByCharCodeEquality` (`{ccVid}` present in `screenTx`?) and `attendanceSet` sentinels before proceeding.

---

## PART 3 — Keyed worker-detail variant

### Task 6: Create `WorkerCardDetailKeyed`

**Files:**
- Create: `lib/widget/worker_card_detail_keyed.dart`

Reads ONE keyed `workforce` doc by `<vid>` (resolved from `screenTx`, pushed by the list tap), renders the read-only fact card. Uses `resolveMapTokens` for named `<key>` substitution (NOT the positional `replaceMarker` the v1 detail uses).

- [ ] **Step 1: Write the widget**

Create `lib/widget/worker_card_detail_keyed.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// WORKER_CARD_DETAIL · variant:"keyed" — read-only fact card for ONE worker.
/// Reads the keyed `workforce` doc whose `vid` matches `<vid>` from screenTx
/// (set by the worker-list tap). `text` layout (diamond-separated):
///   [0]=<n>  [1]=<is>  [2]=<os>  [3]=role label  [4]=Masuk label  [5]=Keluar label
class WorkerCardDetailKeyed extends StatefulWidget {
  const WorkerCardDetailKeyed({
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
  State<WorkerCardDetailKeyed> createState() => _WorkerCardDetailKeyedState();
}

class _WorkerCardDetailKeyedState extends State<WorkerCardDetailKeyed> {
  String _code = '';
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    _code = '${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  /// Resolve `<key>` markers from screenTx so `vid◼<vid>` becomes `vid◼<value>`
  /// before the char-code equality filter runs.
  String _resolveNamedMarkers(String text) {
    return text.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
      final v = _screenTx[m.group(1)!];
      return v == null ? m.group(0)! : v.toString();
    });
  }

  String _at(int i, Map<String, dynamic> doc) =>
      _textArray.length > i ? resolveMapTokens(_textArray[i], doc, const {}) : '';

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _factTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A93A6))),
            const SizedBox(height: 4),
            Text(value.isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2233))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> docs =
          List<Map<String, dynamic>>.from(mapTableContent[_code] ?? const []);
      final String condRaw =
          (widget.component['conditions'] ?? widget.component['search'] ?? '')
              .toString();
      String cond = autheniumDecode(condRaw) ?? condRaw;
      cond = _resolveNamedMarkers(cond);
      final List<Map<String, dynamic>> matched =
          filterByCharCodeEquality(docs, cond, _screenTx);
      if (matched.isEmpty) return const SizedBox.shrink();
      final Map<String, dynamic> doc = matched.first;

      final String name = _at(0, doc);
      final String isVal = _at(1, doc);
      final String osVal = _at(2, doc);
      final String roleLabel = _textArray.length > 3 ? _textArray[3] : '';
      final String masukLabel =
          _textArray.length > 4 ? _textArray[4] : 'Masuk';
      final String keluarLabel =
          _textArray.length > 5 ? _textArray[5] : 'Keluar';

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE0E7FF),
                    child: Text(_getInitials(name),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4F46E5))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937))),
                        if (roleLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(roleLabel,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF9CA3AF))),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _factTile(masukLabel, isVal),
                    const SizedBox(width: 12),
                    _factTile(keluarLabel, osVal),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/widget/worker_card_detail_keyed.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/widget/worker_card_detail_keyed.dart
git commit -m "feat(kehadiran): add WorkerCardDetailKeyed detail widget"
```

### Task 7: Dispatch `variant:"keyed"` for `worker_card_detail`

**Files:**
- Modify: `lib/widget/build_display_component.dart:1154-1167`

- [ ] **Step 1: Replace the `worker_card_detail` branch**

Find this exact block at `lib/widget/build_display_component.dart:1154`:

```dart
  } else if (tip == 'worker_card_detail') {
    try {
      result = WorkerCardDetail(
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
  } else if (tip == 'item_card_detail') {
```

Replace with:

```dart
  } else if (tip == 'worker_card_detail') {
    try {
      final String wcdVariant =
          (component['variant'] ?? '').toString().trim().toLowerCase();
      if (wcdVariant == 'keyed') {
        result = WorkerCardDetailKeyed(
          key: txfKey,
          component: component,
          scrName: scrName,
          lPad: lPad,
          tPad: tPad,
          rPad: rPad,
          bPad: bPad,
        );
      } else {
        result = WorkerCardDetail(
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
  } else if (tip == 'item_card_detail') {
```

- [ ] **Step 2: Add the import**

Beneath the `worker_card_detail.dart` import at the top of `lib/widget/build_display_component.dart`, add:

```dart
import 'worker_card_detail_keyed.dart';
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/widget/build_display_component.dart`
Expected: No new issues.

- [ ] **Step 4: Commit**

```bash
git add lib/widget/build_display_component.dart
git commit -m "feat(kehadiran): dispatch worker_card_detail variant:keyed"
```

### Task 8: Manual verification of list → detail navigation

**Files:** none

- [ ] **Step 1: Run and navigate**

Run: `flutter run`. Kehadiran panel → tap a worker card.

- [ ] **Step 2: Confirm**

Verify: the correction page (route `vertikaTeknoLokaciptaCheckinWorkerCorrection`) shows the tapped worker's `<n>`, `<is>`, `<os>` (the SAME worker — not the wrong row). Tap several different workers; each shows its own data. If it shows blank/wrong worker, confirm the list tap dispatched `vid` to `screenTx` and the detail `conditions` is `[[◀vid▶◼<vid>]]`.

---

## PART 4 — `updateEventRow` parser (pure, TDD)

### Task 9: `parseSearchClause` + `parseUpdateEventRow` + `UpdateEventTarget`

**Files:**
- Create: `lib/firestore_repository/update_event_row.dart`
- Test: `test/update_event_row_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/update_event_row_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/update_event_row.dart';
import 'package:otonomiq/global.dart';

void main() {
  final hollow = separator[8]; // ⭘
  final square = separator[2]; // ◼
  final star = separator[3]; // ★
  final wstar = separator[6]; // ☆

  group('parseSearchClause', () {
    test('single condition -> list of one', () {
      final c = parseSearchClause('vid${star}58111161122230');
      expect(c.length, 1);
      expect(c.first.key, 'vid');
      expect(c.first.value, '58111161122230');
    });
    test('compound AND via ☆', () {
      final c = parseSearchClause('vid${star}X${wstar}sv${star}Y');
      expect(c.length, 2);
      expect(c[0].key, 'vid');
      expect(c[0].value, 'X');
      expect(c[1].key, 'sv');
      expect(c[1].value, 'Y');
    });
    test('malformed condition (no star) skipped', () {
      final c = parseSearchClause('vid${wstar}sv${star}Y');
      expect(c.length, 1);
      expect(c.first.key, 'sv');
    });
    test('empty payload -> empty list', () {
      expect(parseSearchClause(''), isEmpty);
    });
  });

  group('parseUpdateEventRow', () {
    test('extracts collection, tablevid, conditions, sparse body', () {
      final block = '84214220504259//workforce'
          '${hollow}tablevid${square}20342033315492'
          '${hollow}search${square}vid${star}58111161122230'
          '${hollow}os${square}16:00:45'
          '${hollow}is${square}06:58:10';
      final t = parseUpdateEventRow(block);
      expect(t.collection, '84214220504259//workforce');
      expect(t.tablevid, '20342033315492');
      expect(t.conditions.length, 1);
      expect(t.conditions.first.key, 'vid');
      expect(t.conditions.first.value, '58111161122230');
      expect(t.body, {'os': '16:00:45', 'is': '06:58:10'});
      // search/tablevid/_collection are NOT body keys
      expect(t.body.containsKey('search'), false);
      expect(t.body.containsKey('tablevid'), false);
    });
    test('compound search parsed', () {
      final block = '84214220504259//workforce'
          '${hollow}tablevid${square}20342033315492'
          '${hollow}search${square}vid${star}X${wstar}sv${star}Y'
          '${hollow}st${square}on';
      final t = parseUpdateEventRow(block);
      expect(t.conditions.length, 2);
      expect(t.body, {'st': 'on'});
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/update_event_row_test.dart`
Expected: FAIL — `update_event_row.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/firestore_repository/update_event_row.dart`:

```dart
import '../global.dart';
import 'add_to_event.dart';

/// Parsed `updateEventRow` statement: a keyed sparse-merge target.
class UpdateEventTarget {
  /// `<tableDocId>//<subColl>` routing prefix (line-1 collection).
  final String collection;

  /// Firebase table node id override (the `tablevid` header pair).
  final String tablevid;

  /// AND-conditions selecting the doc(s) to merge into.
  final List<MapEntry<String, String>> conditions;

  /// Char-code keys to merge (sparse — only these change).
  final Map<String, String> body;

  const UpdateEventTarget(
      this.collection, this.tablevid, this.conditions, this.body);
}

/// Split a `search` payload into AND conditions.
/// `vid★X☆sv★Y` -> [(vid,X),(sv,Y)]. `☆`=separator[6] joins conditions,
/// `★`=separator[3] splits key/value. Single condition (no `☆`) -> list of one.
/// Conditions missing `★` are skipped silently.
List<MapEntry<String, String>> parseSearchClause(String payload) {
  final star = separator[3]; // ★
  final wstar = separator[6]; // ☆
  final out = <MapEntry<String, String>>[];
  if (payload.trim().isEmpty) return out;
  for (final cond in payload.split(wstar)) {
    final sep = cond.indexOf(star);
    if (sep < 0) continue; // malformed, skip
    final key = cond.substring(0, sep).trim();
    final value = cond.substring(sep + 1).trim();
    if (key.isEmpty) continue;
    out.add(MapEntry(key, value));
  }
  return out;
}

/// Parse one decoded `◆`-block of an updateEventRow statement. Reuses
/// `parseAddToEvent` for the `⭘key◼value` extraction, then lifts out the
/// `tablevid` + `search` header pairs; everything else is the sparse body.
UpdateEventTarget parseUpdateEventRow(String block) {
  final parsed = parseAddToEvent(block);
  final collection = (parsed['_collection'] ?? '').toString();
  final tablevid = (parsed['tablevid'] ?? '').toString();
  final conditions = parseSearchClause((parsed['search'] ?? '').toString());
  final body = <String, String>{};
  parsed.forEach((k, v) {
    if (k == '_collection' || k == 'tablevid' || k == 'search') return;
    body[k] = v.toString();
  });
  return UpdateEventTarget(collection, tablevid, conditions, body);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/update_event_row_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/firestore_repository/update_event_row.dart test/update_event_row_test.dart
git commit -m "feat(updateEventRow): add keyed search-clause + statement parser"
```

---

## PART 5 — `writeUpdateEventRow` + history wiring

### Task 10: `writeUpdateEventRow` (Firestore I/O)

**Files:**
- Modify: `lib/firestore_repository/table_repository.dart` (append after `writeToEvent`, ~`:1486`)

I/O against live Firestore — verified by the integration test in Task 13 (no emulator unit test; the parse logic is already covered in Task 9).

- [ ] **Step 1: Confirm the import exists**

Open `lib/firestore_repository/table_repository.dart`. Confirm it imports `add_to_event.dart` (it calls `parseAddToEvent`). Add this import beneath it:

```dart
import 'update_event_row.dart';
```

- [ ] **Step 2: Add `writeUpdateEventRow` after `writeToEvent` (after line 1486)**

```dart
/// Keyed sibling of `updateTableRow`: sparse-merge listed char-code keys into
/// an EXISTING keyed doc selected by `search` (AND of `key★value`). Mirrors
/// `writeToEvent`'s decode/ref handling and `updateTableRow`'s search targeting.
/// Returns one result string per `◆`-statement ("ok ..." on success) so
/// historySync's `resultOk` can tally it. NEVER blank-prefills (would wipe the
/// other clock field). 0 matches -> skip+log; >1 -> error+skip (no write).
Future<List<String>> writeUpdateEventRow(
    String? inp, String eventRowString) async {
  final List<String> result = [];
  if (inp == null || inp.trim().isEmpty) return result;
  try {
    final List<dynamic> eventRow = jsonDecode(eventRowString);
    final List<dynamic> ref = parseEventString(eventRow);
    final String decoded = autheniumDecode(inp) ?? '';
    final int tableVid = appCodeController.applicationTableVid;
    final int timeReceived = int.tryParse(eventRow[0].toString()) ?? 0;
    final String receivingPage = eventRow[1].toString();

    final blocks = decoded
        .split(separator[1]) // ◆
        .where((b) => b.trim().isNotEmpty)
        .toList();

    for (final block in blocks) {
      try {
        final UpdateEventTarget t = parseUpdateEventRow(block);
        if (t.conditions.isEmpty) {
          result.add('error: missing search');
          continue;
        }
        final int eventTableVid =
            int.tryParse(t.tablevid.trim()) ?? tableVid;
        final String path = eventCollectionPath(t.collection, eventTableVid);
        if (path.isEmpty) {
          result.add('error: bad collection "${t.collection}"');
          continue;
        }

        // Resolve + type-coerce search values, then build the AND query.
        dynamic query = firestoreDb.collection(path);
        for (final c in t.conditions) {
          final String resolved = resolveValueTokens(
            c.value,
            ref,
            tableVid: eventTableVid,
            appVid: appCodeController.applicationTableVid,
            timeReceived: timeReceived,
            receivingPage: receivingPage,
          );
          query = query.where(c.key, isEqualTo: _parseSearchValue(resolved));
        }
        final snap = await query.get();
        final docs = snap.docs;

        if (docs.isEmpty) {
          devPrint('[writeUpdateEventRow] 0 match at $path; skip (no create)');
          result.add('ok: no match (skipped)');
          continue;
        }
        if (docs.length > 1) {
          errorReport(
              '[writeUpdateEventRow] ${docs.length} matches at $path for '
              '${t.conditions}; refusing to write (corrupt uniqueness)');
          result.add('error: ${docs.length} matches');
          continue;
        }

        // Resolve body values + sparse merge into the single matched doc.
        final Map<String, dynamic> patch = {};
        t.body.forEach((k, v) {
          patch[k] = resolveValueTokens(
            v,
            ref,
            tableVid: eventTableVid,
            appVid: appCodeController.applicationTableVid,
            timeReceived: timeReceived,
            receivingPage: receivingPage,
          );
        });
        await docs.first.reference.set(patch, SetOptions(merge: true));
        debugPrint('[writeUpdateEventRow] merged $patch into '
            '$path/${docs.first.id}');
        result.add('ok');
      } catch (e) {
        errorReport('[writeUpdateEventRow] block failed: $e');
        result.add('error: $e');
      }
    }
  } catch (e, st) {
    devPrint('[writeUpdateEventRow] outer error: $e\n$st');
  }
  return result;
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/firestore_repository/table_repository.dart`
Expected: No new issues. (`SetOptions` comes from `cloud_firestore`, already imported for `WriteBatch`/`batch.set`; `_parseSearchValue`, `resolveValueTokens`, `parseEventString`, `eventCollectionPath`, `firestoreDb`, `appCodeController`, `errorReport`, `devPrint` are all in-file/in-scope.)

- [ ] **Step 4: Commit**

```bash
git add lib/firestore_repository/table_repository.dart
git commit -m "feat(updateEventRow): add writeUpdateEventRow keyed merge"
```

### Task 11: Route the 5th history segment in `historySync`

**Files:**
- Modify: `lib/firestore_repository/table_repository.dart:2668-2704`

`history[14]` is a `⬤`-joined string `add⬤update⬤delete⬤event`. Add a 5th segment `updateEvent`. This is client-internal (the same app writes in `saveSend` and reads here), so it is purely additive and backward/forward compatible (`tbParts.length > N` guards default to `''`).

- [ ] **Step 1: Add the 5th segment read**

Find (at `:2677`):

```dart
                      final String eventStr =
                          tbParts.length > 3 ? tbParts[3] : '';
```

Add directly beneath it:

```dart
                      final String updateEventStr =
                          tbParts.length > 4 ? tbParts[4] : '';
```

- [ ] **Step 2: Add the dispatch**

Find (at `:2699`):

```dart
                        if (eventStr.isNotEmpty) {
                          final ok =
                              await writeToEvent(eventStr, eventRowString);
                          tally('writeToEvent', ok,
                              'writeToEvent returned false');
                        }
```

Add directly beneath it (still inside the same `try`):

```dart
                        if (updateEventStr.isNotEmpty) {
                          final res = await writeUpdateEventRow(
                              updateEventStr, eventRowString);
                          tally('writeUpdateEventRow', resultOk(res), res);
                        }
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/firestore_repository/table_repository.dart`
Expected: No issues (`writeUpdateEventRow` is in the same file; `resultOk`/`tally` are local closures).

- [ ] **Step 4: Commit**

```bash
git add lib/firestore_repository/table_repository.dart
git commit -m "feat(updateEventRow): route 5th history segment in historySync"
```

### Task 12: Emit `component['updateEventRow']` as the 5th segment in `saveSend`

**Files:**
- Modify: `lib/api.dart:3692-3710`

- [ ] **Step 1: Build the `updateEventString`**

Find (at `:3692`):

```dart
    String eventString = '';
    try {
      String raw = component['addToEvent'] ?? '';
      if (raw.isNotEmpty) {
        eventString = autheniumDecode(raw) ?? '';
        eventString = replacePlaceholders(eventString, ref);
        eventString = _resolveScreenTxMarkers(eventString);
      }
    } catch (e) {
      eventString = '';
    }
```

Add directly beneath that `catch` block (keyed DSL carries its own `tablevid`, so no `◼D⭘` injection):

```dart
    String updateEventString = '';
    try {
      String raw = component['updateEventRow'] ?? '';
      if (raw.isNotEmpty) {
        updateEventString = autheniumDecode(raw) ?? '';
        updateEventString = replacePlaceholders(updateEventString, ref);
        updateEventString = _resolveScreenTxMarkers(updateEventString);
      }
    } catch (e) {
      updateEventString = '';
    }
```

- [ ] **Step 2: Append the 5th segment in assembly**

Find (at `:3704`):

```dart
    if (eventString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString${separator[0]}$eventString';
    } else if (updateString.isNotEmpty || deleteString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString';
    }
```

Replace with:

```dart
    if (updateEventString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString${separator[0]}$eventString${separator[0]}$updateEventString';
    } else if (eventString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString${separator[0]}$eventString';
    } else if (updateString.isNotEmpty || deleteString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString';
    }
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/api.dart`
Expected: No new issues.

- [ ] **Step 4: Commit**

```bash
git add lib/api.dart
git commit -m "feat(updateEventRow): emit updateEventRow as 5th history segment in saveSend"
```

### Task 13: Integration verification of the correction write-back

**Files:** none

The correction page form (TXF clock-out pos 1, clock-in pos 2, keterangan pos 3 + write-back RBT) is server-driven config in the op1Screen proxy (rows 995/996) — no Dart change. Its DSL:
- `updateEventRow`: `84214220504259//workforce⭘tablevid◼20342033315492⭘search◼vid★<vid>⭘os◼◁1▷⭘is◼◁2▷`
- `addToEvent` (ledger): `84214220504259//event⭘…⭘ty◼koreksi-presensi⭘…⭘sv◼<sv>⭘sn◼<n>⭘d◼Koreksi: …`

- [ ] **Step 1: Run and submit a correction**

Run: `flutter run`. Kehadiran panel → tap a worker with "Belum clock-out" → open the write-back sheet → enter a clock-out time → save.

- [ ] **Step 2: Confirm the merge (NOT overwrite)**

In the Firebase console (or a quick read), open `MobileTable/20342033315492/tables/84214220504259/workforce` and find the doc with that `vid`. Verify:
- `os` (and/or `is`) now holds the entered value.
- `ci`, `co`, `n`, `sv`, `vid` are **unchanged** (sparse merge — the other clock field was not wiped).
- A new doc landed in `…/tables/84214220504259/event` with `ty: koreksi-presensi`.
- The worker list card status updated accordingly after the daily/live refresh.

- [ ] **Step 3: Confirm offline retry**

Turn off networking, submit a correction, turn networking back on. Verify the merge lands once (historySync retry). Check no duplicate event docs.

Expected: matches dev spec §3. If the merge wipes a field, re-check `writeUpdateEventRow` uses `SetOptions(merge: true)` and never prefills. If 0-match, check `<vid>` resolved to a literal in `saveSend` (it must, via `_resolveScreenTxMarkers`) and `_parseSearchValue` coerced the type to match the stored `vid`.

---

## PART 6 — Documentation

### Task 14: Write the `updateEventRow` op doc

**Files:**
- Create: `docs/firestore/update_event_row.md`

- [ ] **Step 1: Write the doc**

Create `docs/firestore/update_event_row.md`:

```markdown
# updateEventRow — keyed sparse merge

Keyed sibling of `updateTableRow`. Merges listed char-code keys into an EXISTING
keyed (char-code) Firestore doc selected by `search`. Sparse — only the listed
keys change; never blank-prefills. Use `addToEvent` for inserts (0-match → skip).

## DSL

```
<tableDocId>//<subColl>⭘tablevid◼<TABLE_VID>⭘search◼<clause>⭘<key>◼<value>…
```

- `search` clause: `key★value` (single), or `key★value☆key★value` (AND).
  `★`=separator[3], `☆`=separator[6].
- Body keys are char-codes (`is`, `os`, `st`, …), same as `addToEvent`.
- Multiple statements chain with `◆`; may interleave with `updateTableRow`.

## Pipeline

`component['updateEventRow']` → `saveSend` (decode + placeholder/screenTx pre-pass)
→ `history[14]` 5th `⬤`-segment → `historySync` → `writeUpdateEventRow`.

Path = `MobileTable/<tablevid>/tables/<tableDocId>/<subColl>` (via
`eventCollectionPath`). Body + search values resolve through `resolveValueTokens`
(`◀N▶` system, `◁N▷` form). Search values type-coerced by `_parseSearchValue`.

## Match semantics

- 1 match → `set(patch, merge:true)`.
- 0 → skip + log (no create).
- >1 → error + skip (no partial write); uniqueness is corrupt.

## Example — attendance correction (this app)

```
84214220504259//workforce⭘tablevid◼20342033315492⭘search◼vid★<vid>⭘os◼◁1▷⭘is◼◁2▷
```

Worker `vid` is globally unique → single-condition search matches exactly one doc.

See `docs/superpowers/plans/2026-06-09-kehadiran-card.md` and
`2026-06-04-updateEventRow-design.md`.
```

- [ ] **Step 2: Add to the firestore docs index (if present)**

Check `docs/firestore/README.md`. If it lists ops, add a line:

```markdown
- [update_event_row.md](update_event_row.md) — keyed sparse merge of an existing keyed doc
```

- [ ] **Step 3: Commit**

```bash
git add docs/firestore/update_event_row.md docs/firestore/README.md
git commit -m "docs(updateEventRow): add op doc"
```

---

## Final verification

- [ ] **Run the full unit suite**

Run: `flutter test test/kehadiran_support_test.dart test/update_event_row_test.dart test/add_to_event_test.dart test/resolve_value_tokens_test.dart`
Expected: ALL PASS.

- [ ] **Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues introduced by this work.

- [ ] **Re-run the three manual checks** (Tasks 5, 8, 13) end-to-end on a device.

---

## Self-review notes (spec coverage)

| Dev-spec requirement | Task |
|----------------------|------|
| §0 generic `variant:"keyed"` on LIST_STATISTIC_CARD | 3, 4 |
| §1 keyed `workforce` read (named keys, no `c`) | 3 (list), 6 (detail) |
| §2 `{total}/{hadir}/{belumScan}/{perluTindak}` aggregate | 2, 3 |
| §2 `{status}/{statusLine}` per-card | 1, 3 |
| §2 `<n>/<is>/<os>` raw tokens + tap→route w/ `<vid>` | 3 |
| §3 `WORKER_CARD_DETAIL` keyed read by `<vid>` | 6, 7 |
| §3 write-back `updateEventRow` (keyed merge, is/os) | 9, 10, 11, 12 |
| §3 `addToEvent` ledger jejak | existing (verified Task 13) |
| §4 worker history (period) | OUT OF SCOPE (separate plan) |

**Open items carried from analysis (not blockers):** the `☆` compound-search path (Task 9) is implemented but unused for this feature (single search only); `>1 match` guard (Task 10) is dead under `vid`-uniqueness but kept as a safety net.
