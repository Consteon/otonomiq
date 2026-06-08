# Cost Center Card (`LIST_MULTIPLE_PANEL_CARD`) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new server-driven UI component type `LIST_MULTIPLE_PANEL_CARD` — a cost-center list where each card carries N tappable nav panels (Kehadiran, Patroli & Cleaning), grouped into status accordions (Perlu tindak / Perhatian / Aman).

**Architecture:** Sibling of the existing `LIST_ITEM_CARD` (`lib/widget/list_item_card.dart`). All per-card decision logic (panel parsing, token resolution, status grouping, worst-status, labels, colors) lives in a pure, fully-unit-tested support file `lib/widget/panel_card_support.dart`. A new `StatefulWidget` `ListMultiplePanelCard` wires those helpers to the reactive table source (`tableContent[code]` via `Obx`) and the custom router (`routeStack.push` + `gotoRoute`). A new dispatch branch in `build_display_component.dart` routes the type to the widget.

**Tech Stack:** Flutter, GetX (`Obx`, `tableContent`), Redux (`transactionStore`), existing helpers `replaceMarker` / `diamondTextToList` (`lib/global.dart`), `subscribeToTable` (`lib/firestore_repository/table_repository.dart`).

**Scope — this plan covers Fase 1 only (the widget shell).** It renders cards + panels from the subscribed table, resolving `<i>` numeric tokens and substituting `{...}` tokens from a per-card computed map that is **empty in Fase 1** (so `{...}` tokens fall back to literal/`ok`). Fase 2 (real aggregation of `{hadir}`/`{issues}`/`{staleCount}`/`{longestGap}`/`{ws}` from `ref/workforce` + `event/content`, the `ln` event field, and the named-char-code `<an>`/`<sn>` resolver) is outlined at the end and becomes a separate plan once the runtime data schema is confirmed.

> **DESIGN NOTE (2026-06-03).** The confirmed reference is the "Cari site atau klien" design: search field + colored status summary (`N perlu tindak · N perhatian · N aman`) + collapsible status accordions (PERLU TINDAK / PERHATIAN / AMAN as tinted full-width pills) + cost-center cards. Each card = header (name + sub) + colored left strip (worst status) + N **nested** nav panels separated by dividers, each panel = neutral icon box + UPPERCASE label + status pill + bold headline + details + chevron, tapping its own route. This matches Task 6's original nested structure below. (An intermediate flat single-panel-card variant was built then reverted after the reference was corrected.) Styling was polished beyond the Task 6 code block (tinted accordion pills, colored summary spans, panel dividers) — the implemented file `lib/widget/list_multiple_panel_card.dart` is authoritative for exact styling. All `panel_card_support.dart` helpers are used and fully tested.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/widget/panel_card_support.dart` | Pure logic: `PanelConfig` model, `parsePanels`, `splitPanelText`, `resolvePanelText`, `panelIcon`, `worstStatus`, `groupByStatus`, status labels, `summaryLine`, status colors. No Flutter state, no I/O. | Create |
| `test/panel_card_support_test.dart` | Unit tests for every pure function above. | Create |
| `lib/widget/list_multiple_panel_card.dart` | `ListMultiplePanelCard` StatefulWidget + state: config parse, table subscribe, `Obx` render of search + status accordions + cards + panels + per-panel nav. | Create |
| `lib/widget/all_widget.dart` | Barrel — add export of the new widget. | Modify |
| `lib/widget/build_display_component.dart` | Add dispatch branch `tip == 'list_multiple_panel_card'`. | Modify (after L1125) |

**Why a separate support file:** mirrors the existing `lib/firestore_repository/add_to_event.dart` pattern (pure parse split out from the writer for testability). The widget itself depends on `GetX`/`Redux`/`Obx` and is verified manually; all branching logic is in the tested helpers.

---

### Task 1: `PanelConfig` model + `parsePanels`

**Files:**
- Create: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/panel_card_support_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/panel_card_support.dart';

void main() {
  group('parsePanels', () {
    test('maps each panel map to a PanelConfig', () {
      final raw = [
        {
          'icon': 'users',
          'text': 'Kehadiran◆{hadir}/<3> hadir◆{issues}',
          'status': '{ps}',
          'route': 'checkinSiteDetail',
        },
        {
          'icon': 'clipboard-check',
          'text': 'Patroli & Cleaning◆{llCount} titik◆{staleCount} titik jeda lama',
          'status': '{qs}',
          'route': 'patroliCleaningPerSite',
        },
      ];
      final panels = parsePanels(raw);
      expect(panels.length, 2);
      expect(panels[0].icon, 'users');
      expect(panels[0].route, 'checkinSiteDetail');
      expect(panels[1].status, '{qs}');
    });

    test('non-list input returns empty', () {
      expect(parsePanels(null), isEmpty);
      expect(parsePanels('oops'), isEmpty);
    });

    test('missing keys default to empty string', () {
      final panels = parsePanels([
        {'icon': 'users'}
      ]);
      expect(panels.length, 1);
      expect(panels[0].text, '');
      expect(panels[0].status, '');
      expect(panels[0].route, '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'otonomiq' ... panel_card_support.dart` (file does not exist).

- [ ] **Step 3: Write minimal implementation**

Create `lib/widget/panel_card_support.dart`:

```dart
import 'package:flutter/material.dart';

import '../global.dart';

/// One nav panel inside a LIST_MULTIPLE_PANEL_CARD card.
/// `text` is the raw `label◆headline◆details` template (tokens unresolved).
/// `status`/`route` are raw too — resolved at render time.
class PanelConfig {
  final String icon;
  final String text;
  final String status;
  final String route;
  const PanelConfig({
    required this.icon,
    required this.text,
    required this.status,
    required this.route,
  });

  factory PanelConfig.fromMap(Map<String, dynamic> m) => PanelConfig(
        icon: (m['icon'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        status: (m['status'] ?? '').toString(),
        route: (m['route'] ?? '').toString(),
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
```

(The `material.dart` + `global.dart` imports are unused for now; later tasks in this file use them. If your linter blocks unused imports at this step, add the next task's code together — they share the file.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): PanelConfig model + parsePanels"
```

---

### Task 2: `splitPanelText` + `resolvePanelText`

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

`resolvePanelText` resolves `<i>` numeric markers via the existing `replaceMarker` (`lib/global.dart:1234`, replaces `<0>`,`<1>`,… with `ref[index]`) then substitutes `{key}` tokens from a `computed` map. `splitPanelText` splits a resolved string on `◆` via `diamondTextToList` into label/headline/details.

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart` (inside `main()`):

```dart
  group('resolvePanelText', () {
    // replaceMarker semantics: ref = [sortKey, timestamp, field1, ...];
    // with indexStart=1, <2> -> ref[2], <3> -> ref[3].
    test('resolves <i> numeric markers and {key} computed tokens', () {
      final row = ['sortKey', '1780000000000', 'Budi', '5'];
      final computed = {'hadir': '3', 'issues': '2 belum scan'};
      final out = resolvePanelText(
        'Kehadiran◆{hadir}/<3> hadir◆{issues}',
        row,
        computed,
        1,
      );
      expect(out, 'Kehadiran◆3/5 hadir◆2 belum scan');
    });

    test('unknown {key} left literal when not in computed', () {
      final out = resolvePanelText('x◆{ps}◆y', ['s', 't'], {}, 1);
      expect(out, 'x◆{ps}◆y');
    });
  });

  group('splitPanelText', () {
    test('splits resolved string into label/headline/details', () {
      final p = splitPanelText('Kehadiran◆3/5 hadir◆2 belum scan');
      expect(p.label, 'Kehadiran');
      expect(p.headline, '3/5 hadir');
      expect(p.details, '2 belum scan');
    });

    test('missing segments default to empty', () {
      final p = splitPanelText('OnlyLabel');
      expect(p.label, 'OnlyLabel');
      expect(p.headline, '');
      expect(p.details, '');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `The function 'resolvePanelText' isn't defined` / `'splitPanelText' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS (all groups so far).

- [ ] **Step 5: Commit**

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): splitPanelText + resolvePanelText token resolution"
```

---

### Task 3: `panelIcon` name → IconData

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart`:

```dart
  group('panelIcon', () {
    test('known names map to icons', () {
      expect(panelIcon('users'), Icons.people_alt_rounded);
      expect(panelIcon('clipboard-check'), Icons.fact_check_rounded);
    });
    test('case/whitespace tolerant', () {
      expect(panelIcon('  Users '), Icons.people_alt_rounded);
    });
    test('unknown name falls back to a default icon', () {
      expect(panelIcon('nope'), Icons.dashboard_rounded);
    });
  });
```

Add the Flutter material import at the top of the test file (needed for `Icons`):

```dart
import 'package:flutter/material.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `The function 'panelIcon' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): panelIcon name-to-IconData map"
```

---

### Task 4: `worstStatus` + `groupByStatus`

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart`:

```dart
  group('worstStatus', () {
    test('danger beats warn beats ok', () {
      expect(worstStatus(['ok', 'warn', 'danger']), 'danger');
      expect(worstStatus(['ok', 'warn']), 'warn');
      expect(worstStatus(['ok', 'ok']), 'ok');
    });
    test('case insensitive, unknown ignored', () {
      expect(worstStatus(['OK', 'Warn']), 'warn');
      expect(worstStatus(['{ps}', '{qs}']), 'ok'); // unresolved -> fallback ok
    });
    test('empty list -> ok', () {
      expect(worstStatus([]), 'ok');
    });
  });

  group('groupByStatus', () {
    test('buckets items into danger/warn/ok in fixed order', () {
      final items = ['a', 'b', 'c', 'd'];
      String statusOf(String s) => {
            'a': 'danger',
            'b': 'ok',
            'c': 'warn',
            'd': 'danger',
          }[s]!;
      final g = groupByStatus<String>(items, statusOf);
      expect(g.keys.toList(), ['danger', 'warn', 'ok']);
      expect(g['danger'], ['a', 'd']);
      expect(g['warn'], ['c']);
      expect(g['ok'], ['b']);
    });
    test('unknown status falls into ok bucket', () {
      final g = groupByStatus<String>(['x'], (_) => '{ws}');
      expect(g['ok'], ['x']);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `'worstStatus' isn't defined` / `'groupByStatus' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): worstStatus + groupByStatus"
```

---

### Task 5: Status labels, `summaryLine`, status colors

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

Vocabulary from spec §4.4: group/summary `ok` = "Aman", panel pill `ok` = "Beres"; `danger` = "Perlu tindak", `warn` = "Perhatian" for both.

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart`:

```dart
  group('status labels', () {
    test('group label uses Aman for ok', () {
      expect(statusGroupLabel('danger'), 'Perlu tindak');
      expect(statusGroupLabel('warn'), 'Perhatian');
      expect(statusGroupLabel('ok'), 'Aman');
    });
    test('pill label uses Beres for ok', () {
      expect(statusPillLabel('danger'), 'Perlu tindak');
      expect(statusPillLabel('warn'), 'Perhatian');
      expect(statusPillLabel('ok'), 'Beres');
      expect(statusPillLabel('{ps}'), 'Beres'); // unknown -> ok label
    });
  });

  group('summaryLine', () {
    test('formats counts per status', () {
      final groups = {
        'danger': [1, 2],
        'warn': [3],
        'ok': [4, 5, 6],
      };
      expect(summaryLine(groups), '2 perlu tindak · 1 perhatian · 3 aman');
    });
  });

  group('status colors', () {
    test('distinct colors per status', () {
      expect(statusColor('danger'), const Color(0xFFDC2626));
      expect(statusColor('warn'), const Color(0xFFD97706));
      expect(statusColor('ok'), const Color(0xFF16A34A));
      expect(statusColor('{ws}'), const Color(0xFF16A34A)); // fallback ok
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `'statusGroupLabel' isn't defined` (and the others).

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): status labels, summaryLine, status colors"
```

---

### Task 6: `ListMultiplePanelCard` widget (render)

**Files:**
- Create: `lib/widget/list_multiple_panel_card.dart`

This widget reuses the proven structure of `ListItemCard` (`lib/widget/list_item_card.dart`): `_initConfig` parsing, `_subscribeTable`, an `Obx` `build` over `tableContent[_tableCode]`, the same `replaceMarker`-based `_resolveText`, and the same router (`routeStack.push` + `gotoRoute`). It differs by rendering **status-grouped accordions** of cards, each card carrying **N panels** instead of action buttons.

`_computeCardValues(row)` returns an **empty map in Fase 1** (placeholder for Fase 2 aggregation). With it empty, `{...}` tokens stay literal and all statuses resolve to `ok` (everything lands under the "Aman" group) — that is the expected Fase 1 shell behavior and is verified manually.

- [ ] **Step 1: Create the widget file**

Create `lib/widget/list_multiple_panel_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart'; // normalizeTableName lives here
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';

class ListMultiplePanelCard extends StatefulWidget {
  const ListMultiplePanelCard({
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
  State<ListMultiplePanelCard> createState() => _ListMultiplePanelCardState();
}

class _ListMultiplePanelCardState extends State<ListMultiplePanelCard> {
  List<String> _textArray = [];
  List<PanelConfig> _panels = [];
  String _tableCode = '';
  int _indexStart = 1;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  // Group expand/collapse state, default all open.
  final Map<String, bool> _expanded = {'danger': true, 'warn': true, 'ok': true};

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribeTable();
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
    _panels = parsePanels(widget.component['panels']);
    _indexStart = widget.component['indexStart'] ?? 1;
  }

  void _subscribeTable() {
    String rawTable = (widget.component['table'] ?? '').toString().trim();
    String decoded = autheniumDecode(rawTable) ?? rawTable;
    _tableCode = normalizeTableName(decoded);
    int tableVid =
        int.tryParse((widget.component['vidtable'] ?? '').toString()) ??
            appCodeController.applicationTableVid;
    if (_tableCode.isNotEmpty) {
      tableSourceUpdated[_tableCode] = true;
      subscribeToTable(_tableCode, tableVid);
    }
  }

  String _resolveText(String template, List<dynamic> row) {
    return replaceMarker(template, row, _indexStart, false);
  }

  /// Fase 1: no aggregation yet — returns empty so {...} tokens stay literal
  /// and statuses fall back to 'ok'. Fase 2 fills hadir/issues/llCount/
  /// staleCount/longestGap/ps/qs/ws here.
  Map<String, String> _computeCardValues(List<dynamic> row) => const {};

  String _panelStatus(PanelConfig p, List<dynamic> row, Map<String, String> v) =>
      resolvePanelText(p.status, row, v, _indexStart);

  String _cardWorstStatus(List<dynamic> row, Map<String, String> v) {
    final topLevel =
        resolvePanelText((widget.component['status'] ?? '').toString(),
            row, v, _indexStart);
    final all = <String>[
      topLevel,
      ..._panels.map((p) => _panelStatus(p, row, v)),
    ];
    return worstStatus(all);
  }

  void _onPanelTap(List<dynamic> row, PanelConfig panel) {
    final String noRequest = row.length > 1 ? row[1].toString() : '';
    final String requestDocT = row.isNotEmpty ? row[0].toString() : '';
    if (noRequest.isNotEmpty) {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'no_request': noRequest,
        'request_vid': noRequest,
        'request_doc_t': requestDocT,
        'panel_route': panel.route,
      })));
    }
    if (panel.route.isNotEmpty && routeExist(panel.route)) {
      routeStack.push(panel.route);
      gotoRoute(panel.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      List<dynamic> allData = List.from(tableContent[_tableCode] ?? []);
      List<dynamic> filtered = searchTable(_searchQuery, allData);

      // group cards by worst status
      final groups = groupByStatus<dynamic>(
        filtered,
        (row) => _cardWorstStatus(row as List<dynamic>, _computeCardValues(row)),
      );

      double screenH = MediaQuery.of(context).size.height;
      double availableH = screenH * 0.79;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              widget.lPad, widget.tPad, widget.rPad, widget.bPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  summaryLine(groups),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280)),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final status in statusOrder)
                            if ((groups[status] ?? []).isNotEmpty)
                              _buildGroup(status, groups[status]!, context),
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

  Widget _buildSearchField() {
    String label = _textArray.length > 3 ? _textArray[3] : 'Cari';
    String hint = _textArray.length > 4 ? _textArray[4] : label;
    return TextFormField(
      controller: _searchController,
      keyboardType: TextInputType.text,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
        hintText: hint,
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildEmptyState() {
    String empty = _textArray.length > 5 ? _textArray[5] : 'Data tidak ditemukan';
    return Center(
      child: Text(empty,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
    );
  }

  Widget _buildGroup(String status, List<dynamic> rows, BuildContext context) {
    final bool open = _expanded[status] ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded[status] = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: statusColor(status), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('${statusGroupLabel(status)} (${rows.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: Color(0xFF374151))),
                const Spacer(),
                Icon(open ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF)),
              ],
            ),
          ),
        ),
        if (open)
          for (final row in rows) _buildCard(row as List<dynamic>, context),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCard(List<dynamic> row, BuildContext context) {
    final Map<String, String> v = _computeCardValues(row);
    final String worst = _cardWorstStatus(row, v);
    // header: top-row name = textArray[1], sub = textArray[2]
    final String name = _textArray.length > 1 ? _resolveText(_textArray[1], row) : '';
    final String sub = _textArray.length > 2 ? _resolveText(_textArray[2], row) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: statusColor(worst),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937)),
                            overflow: TextOverflow.ellipsis),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(sub,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF9CA3AF)),
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 12),
                        for (final p in _panels) _buildPanel(p, row, v),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(PanelConfig p, List<dynamic> row, Map<String, String> v) {
    final PanelText t = splitPanelText(resolvePanelText(p.text, row, v, _indexStart));
    final String status = _panelStatus(p, row, v);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onPanelTap(row, p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEF0F2)),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(panelIcon(p.icon),
                  size: 18, color: const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.label,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      _statusPill(status),
                    ],
                  ),
                  if (t.headline.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.headline,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF4B5563))),
                  ],
                  if (t.details.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(t.details,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFD1D5DB), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: statusBgColor(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(statusPillLabel(status),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: statusColor(status))),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/widget/list_multiple_panel_card.dart`
Expected: No `error` lines (pre-existing `info`/`warning` from other files are fine). Confirm every referenced symbol resolves: `diamondTextToList`, `replaceMarker`, `autheniumDecode`, `normalizeTableName`, `subscribeToTable`, `tableSourceUpdated`, `tableContent`, `searchTable`, `routeExist`, `routeStack`, `gotoRoute`, `appCodeController`, `transactionStore`, `UpdateScreenTxAction`, `ScreenTransaction`.

If any symbol is reported undefined, grep its definition and fix the import (most live in `lib/global.dart`, `lib/api.dart`, `lib/firestore_repository/table_repository.dart`, `lib/redux/screen_transaction.dart`, `lib/states/app_code_controller.dart`).

- [ ] **Step 3: Commit**

```bash
git add lib/widget/list_multiple_panel_card.dart
git commit -m "feat(panel-card): ListMultiplePanelCard render (Fase 1 shell)"
```

---

### Task 7: Register the type (barrel export + dispatch branch)

**Files:**
- Modify: `lib/widget/all_widget.dart`
- Modify: `lib/widget/build_display_component.dart` (insert after line 1125, the close of the `list_item_card` branch)

- [ ] **Step 1: Add the barrel export**

In `lib/widget/all_widget.dart`, add this line in alphabetical position near the other `list_*` exports:

```dart
export 'list_multiple_panel_card.dart';
```

- [ ] **Step 2: Add the dispatch branch**

In `lib/widget/build_display_component.dart`, immediately AFTER the `list_item_card` branch (which ends at line 1125 `  }`) and BEFORE `  } else if (tip == 'worker_card_detail') {`, insert:

```dart
  } else if (tip == 'list_multiple_panel_card') {
    try {
      result = ListMultiplePanelCard(
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
  } else if (tip == 'list_multiple_panel_card') {
    try {
      result = ListMultiplePanelCard(
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
Expected: No `error` lines. `ListMultiplePanelCard` resolves via the barrel import `'../widget/all_widget.dart'`.

- [ ] **Step 4: Run the full support test suite + commit**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS (all groups).

```bash
git add lib/widget/all_widget.dart lib/widget/build_display_component.dart
git commit -m "feat(panel-card): register LIST_MULTIPLE_PANEL_CARD dispatch + barrel export"
```

---

### Task 8: Manual verification (shell)

**Files:** none (manual).

- [ ] **Step 1: Add a test screen JSON** using the §2 spec JSON with `type: "LIST_MULTIPLE_PANEL_CARD"` pointing at a real workforce table, but with the panel `text` headers using **numeric `<i>` markers** for the header fields (Fase 1 has no named-char-code resolver). Example header `text`: `◆<2>◆<3>◆Cari cost center◆Ketik nama cost center◆Data tidak ditemukan` (slot0 empty title, `<2>`=name field, `<3>`=site field — adjust indices to the actual table columns).

- [ ] **Step 2: Run the app** (`./set_android.sh && flutter run`) on a screen that renders the component.

- [ ] **Step 3: Confirm the shell** renders: search box, summary line, one "Aman" accordion group (all cards land here in Fase 1), each card with its colored strip + the two panels (icon, label, "Beres" pill, headline/details with literal `{...}` tokens visible), chevrons. Tapping a panel navigates to its `route` (verify `routeStack` back works).

- [ ] **Step 4: Note** that real statuses, `{...}` values, and named `<an>`/`<sn>` resolution arrive in Fase 2 — literal `{...}` and all-"Aman" grouping are expected here.

---

## Fase 2 — Outline (separate plan; aligned to dev-spec v2, the authoritative spec)

Data model now confirmed by dev-spec v2 (`cost-center-card-dev-spec (2).md`). Source of truth = collection **`site`** (`$test/{tenantVid}//site`, one doc = one cost center), with sibling collection **`workforce`** and **`event/content`**.

**Confirmed `site` doc fields (char-codes):** `<an>` cost-center name (header top), `<sn>` site name (header sub), `<av>` cost-center VID, `<sv>` site VID, `<nm>` headcount needed, `<st>` status, `<af>`/`<sf>` slug, `<en>` encrypted (never render). **`ll` = array of OBJECTS**, each: `ln` (point name), `li` (point/QR id), `la`/`lo` (lat/lng), `ra` (radius m).

1. **Named char-code resolver `<an>`/`<sn>`/`<av>`/`<nm>`/`<st>`…** Add a `fields` map (char-code → column index) to the component JSON and resolve it in `panel_card_support.dart` (add `resolveNamedTokens`, fold into `resolvePanelText`/`_resolveText`). The table `hd` header does not carry char-code names, so the mapping must be supplied by the JSON. Required for the card header AND for `{ccVid}` (below). **Do this first — it unblocks header + tap context.**
2. **`{ccVid}` context inject on panel tap.** Change `_onPanelTap` to inject the resolved cost-center VID `<av>` (token `{ccVid}`) into the destination-page context (alongside/instead of `request_vid`=row[1]). The destination page filters itself via `search: "<col>◼{ccVid}"` + `conditions`.
3. **Panel Kehadiran aggregation (collection `workforce`, SEPARATE from `site`).** `$test/{tenantVid}//workforce`, joined to the card via `sv`/`av` (worker's cost-center VID) == `<av>`. Per-worker fields `ci` (clock-in) / `co` (clock-out): `{hadir}` = COUNT `ci` filled; `{issues}` = "X belum scan" (`ci` empty) + "Y lupa clock-out" (`ci` filled, `co` empty), else "Semua beres"; `{ps}` = danger if any "belum scan", warn if only minor, else ok.
4. **Panel Patroli aggregation (`event/content`).** Points = `ll[]` objects on the `site` doc. Join event→point via **`lq` (event QR id) == `ll[].li`** (robust id match); fallback `ln` (event) == `ll[].ln` for manual non-QR scans. Use `t` (epoch ms, NOT `ts`): `jeda_titik = now − MAX(t WHERE point matched AND ty = patrol)`; `{staleCount}` = COUNT(`jeda_titik` ≥ **43200000 ms** = 12h); `{longestGap}` = MAX(`jeda_titik`) / 3600000 (hours, display); `{qs}` = warn if `{staleCount}` > 0 else ok. Threshold stored in **ms** (consistent with other screens' `period`), configurable via a component field. `{staleCount}` = 0 → render "Tidak ada jeda signifikan".
5. **`{llCount}`** = `ll.length` (count of `ll` objects on the `site` doc), computed frontend.
6. **Wire `_computeCardValues`** in `ListMultiplePanelCard` to return the real map from (3)+(4)+(5); `{ws}` = `worstStatus([ps, qs])`. This automatically activates real status grouping + summary (already built in Fase 1).
7. **Orphan handling.** Events whose `lq`/`ln` match no `ll` object, and `ll` points with zero events ("belum pernah dipatroli" — label, not "X jam"). Manual-scan typos in `ln` cause orphans — decide labeling. **Final dev decision.**

> Note: dev-spec v1 placed Kehadiran in `ref/workforce` sub-docs and joined patrol events by `ln`-only; v2 supersedes both (workforce is a separate collection joined by `av`; patrol joins by `lq`==`li`). The earlier "`ln` event write-path field" task from v1 is no longer the primary join key (id `lq`/`li` is) and is dropped unless manual-scan fallback needs it.

---

## Self-Review

**Spec coverage (§ → task):**
- §2 widget JSON `panels` array → Task 1 (`parsePanels`).
- §2 `text` ◆-pack + header → Task 2 (`splitPanelText`), Task 6 (`_initConfig`/`_buildCard`).
- §1/§2 panel = icon+text+status+route, nav (not buttons) → Task 6 (`_buildPanel`, `_onPanelTap`).
- §3 token `<i>` resolution → Task 2 (`resolvePanelText`). Named `<an>`/`<sn>` → **Fase 2** (documented blocker — no runtime name→index map exists; verified `replaceMarker` is numeric-only and `hd` header carries no names).
- §3 `{...}` dev tokens → Task 2 plumbing; values → **Fase 2** (`_computeCardValues` stub in Task 6).
- §1/§4.4 status summary + accordion grouping → Task 4 (`groupByStatus`/`worstStatus`), Task 5 (`summaryLine`/labels), Task 6 (`_buildGroup`).
- §4.4 status vocabulary (danger/warn/ok, Aman vs Beres, colors) → Task 5.
- §4.1/§4.2/§4.3 aggregation → **Fase 2** (outlined; needs live schema).
- §5 Q1 new render type → Task 6/7. Q2 `{llCount}` → Fase 2. Q3 context token → Task 6 (`_onPanelTap` dispatches `request_vid`/`request_doc_t`/`panel_route`). Q4 `text` order → Task 6 header indices. Q5 threshold → Fase 2 (`staleHours`). Q6 vocab → Task 5. Q7 grouping frontend → Task 4-6.
- §6 page wrapper + detail screen → out of scope (unchanged).

**Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Fase 2 items are explicitly outline-only and gated on a named blocker (live schema), not hidden placeholders in Fase 1 tasks.

**Type consistency:** `PanelConfig`/`PanelText` fields, `resolvePanelText(template,row,computed,indexStart)`, `worstStatus(List<String>)`, `groupByStatus<T>(items, statusOf)`, `statusOrder`, `statusGroupLabel`/`statusPillLabel`, `summaryLine(Map)`, `statusColor`/`statusBgColor`, `panelIcon(String)` — names/signatures identical across Task 6 usage and Tasks 1-5 definitions. `_indexStart` (int) used consistently. Dispatch type string `'list_multiple_panel_card'` matches `'LIST_MULTIPLE_PANEL_CARD'.toLowerCase()`.

