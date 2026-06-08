# Cost Center Card — Char-Code Map Data Binding (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`) syntax. **Execution is currently NO-COMMIT per the user — implement + test each task but SKIP every `git add`/`git commit` step until told otherwise.**

**Goal:** Make `ListMultiplePanelCard` bind to the real `site` data, which lives as **char-code-keyed map documents** in a subcollection (`MobileTable/{appVid}/tables/{tableDocId}/site`), not as the positional `content`/`c`-array rows the widget currently assumes. After this phase the card header (`<an>`/`<sn>`), `<nm>`, `{llCount}`, and the `{ccVid}` tap-context resolve from real data. Per-card aggregation tokens (`{hadir}`/`{issues}`/`{ps}`/`{staleCount}`/`{longestGap}`/`{qs}`/`{ws}`) remain stubbed until Phase B (Fase 2: workforce + events).

**Architecture:** Add (1) a reactive map store `mapTableContent`, (2) a Firestore reader `subscribeToMapCollection` that listens to the subcollection and stores each doc as `Map<String,dynamic>` (mirrors the `proxy_repository` `.data()` listener pattern), and (3) pure helpers in `panel_card_support.dart` — `parseTablePath`, `llCount`, `resolveMapTokens` (resolve `<charcode>` from the doc map + `{key}` from the computed map). The widget switches its data binding from positional rows to maps and resolves tokens via map lookup instead of `replaceMarker`.

**Tech Stack:** Flutter, GetX (`Obx`, `RxMap`), Firestore (`firestoreDb`, `snapshots().listen`), existing globals `mobileTable`/`mobileTableCollection`.

**Confirmed data (real Firestore doc, tenant 84214220504259):**
- Path: `MobileTable/20342033315492/tables/84214220504259/site/{docId}` — each doc = one cost center, a char-code map.
- Fields: `an`="A Product Group" (cc name), `sn`="S Product Group" (site name), `av`=83674161979544 (cc VID), `sv`=83674161979544 (site VID), `nm`=2 (headcount), `st`="active", `af`/`sf`="vtl◆product-group" (slug), `en`="encripted…" (never render), `ll`=array of objects `{ln, li, la, lo, ra}`.
- Component config:
  ```json
  {"type":"LIST_MULTIPLE_PANEL_CARD","ledgerCode":"site","vidtable":"20342033315492",
   "table":"84214220504259//site","text":"◆<an>◆<sn>◆Cari cost center◆Ketik nama cost center◆Data tidak ditemukan",
   "status":"{ws}", "panels":[ {icon:"users","text":"Kehadiran◆{hadir}/<nm> hadir◆{issues}","status":"{ps}","route":"checkinSiteDetail"},
   {icon:"clipboard-check","text":"Patroli & Cleaning◆{llCount} titik◆{staleCount} titik jeda lama · terlama {longestGap} jam","status":"{qs}","route":"patroliCleaningPerSite"} ]}
  ```
- Path mapping: `appVid` = `vidtable` (`20342033315492`); `tableDocId` = `table` first `//`-segment (`84214220504259`, dynamic per tenant); `subColl` = `table` last `//`-segment (`site`).

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/widget/panel_card_support.dart` | Add pure helpers: `TablePath`/`parseTablePath`, `llCount`, `resolveMapTokens`. | Modify |
| `test/panel_card_support_test.dart` | Tests for the three new helpers. | Modify |
| `lib/global.dart` | Add `RxMap<String, List<Map<String,dynamic>>> mapTableContent`. | Modify |
| `lib/firestore_repository/table_repository.dart` | Add `subscribeToMapCollection(appVid, tableDocId, subColl, code)`. | Modify |
| `lib/widget/list_multiple_panel_card.dart` | Switch data binding from positional rows to char-code maps. | Rewrite render/data methods |

---

### Task 1: `parseTablePath` + `llCount` helpers

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/panel_card_support_test.dart`:

```dart
  group('parseTablePath', () {
    test('splits "docId//subColl"', () {
      final p = parseTablePath('84214220504259//site');
      expect(p.tableDocId, '84214220504259');
      expect(p.subColl, 'site');
    });
    test('no // defaults subColl to content', () {
      final p = parseTablePath('myTable');
      expect(p.tableDocId, 'myTable');
      expect(p.subColl, 'content');
    });
    test('trailing empty subColl falls back to content', () {
      final p = parseTablePath('docId//');
      expect(p.tableDocId, 'docId');
      expect(p.subColl, 'content');
    });
  });

  group('llCount', () {
    test('counts ll array of objects', () {
      final doc = {
        'an': 'A',
        'll': [
          {'ln': 'P1'},
          {'ln': 'P2'}
        ]
      };
      expect(llCount(doc), 2);
    });
    test('missing or non-list ll -> 0', () {
      expect(llCount({'an': 'A'}), 0);
      expect(llCount({'ll': 'oops'}), 0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `'parseTablePath' isn't defined` / `'llCount' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP while no-commit)

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): parseTablePath + llCount helpers"
```

---

### Task 2: `resolveMapTokens` (char-code `<x>` + computed `{key}`)

**Files:**
- Modify: `lib/widget/panel_card_support.dart`
- Test: `test/panel_card_support_test.dart`

Resolves `<charcode>` tokens from the site doc map (`<an>` -> `doc['an']`) and `{key}` tokens from a computed map (unknown `{key}` left literal, like Fase 1). Replaces the numeric-`replaceMarker` path for this map-based widget.

- [ ] **Step 1: Write the failing test**

Append to `test/panel_card_support_test.dart`:

```dart
  group('resolveMapTokens', () {
    final doc = {
      'an': 'A Product Group',
      'sn': 'S Product Group',
      'nm': 2,
      'av': 83674161979544,
    };
    test('resolves <charcode> from doc map', () {
      expect(resolveMapTokens('◆<an>◆<sn>', doc, const {}),
          '◆A Product Group◆S Product Group');
    });
    test('numeric doc values stringified', () {
      expect(resolveMapTokens('<nm> hadir', doc, const {}), '2 hadir');
    });
    test('missing charcode -> empty string', () {
      expect(resolveMapTokens('x<zz>y', doc, const {}), 'xy');
    });
    test('computed {key} substituted, unknown left literal', () {
      expect(
          resolveMapTokens(
              'Kehadiran◆{hadir}/<nm> hadir◆{issues}', doc, {'hadir': '10'}),
          'Kehadiran◆10/2 hadir◆{issues}');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/panel_card_support_test.dart`
Expected: FAIL — `'resolveMapTokens' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/widget/panel_card_support.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/panel_card_support_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** (SKIP while no-commit)

```bash
git add lib/widget/panel_card_support.dart test/panel_card_support_test.dart
git commit -m "feat(panel-card): resolveMapTokens for char-code map docs"
```

---

### Task 3: `mapTableContent` store + `subscribeToMapCollection` reader

**Files:**
- Modify: `lib/global.dart` (add the store next to `tableContent`)
- Modify: `lib/firestore_repository/table_repository.dart` (add the reader)

- [ ] **Step 1: Add the reactive store**

In `lib/global.dart`, immediately after the `tableContent` declaration (`RxMap<String, dynamic> tableContent` around line 252), add:

```dart
// Char-code map subcollections (e.g. `site`, `workforce`): each entry is a list
// of raw Firestore doc maps (NOT positional `c`-arrays like `tableContent`).
RxMap<String, List<Map<String, dynamic>>> mapTableContent =
    <String, List<Map<String, dynamic>>>{}.obs;
```

- [ ] **Step 2: Add the reader function**

In `lib/firestore_repository/table_repository.dart`, add this top-level function (place it just before `Future subscribeToTable(` around line 1840):

```dart
// Guards against double-listening to the same map subcollection.
final Set<String> _mapSubscribed = <String>{};

/// Listen to a char-code-map subcollection at
/// `MobileTable/<appVid>/tables/<tableDocId>/<subColl>` and store each doc as a
/// raw `Map<String,dynamic>` under `mapTableContent[code]`. Mirrors the
/// `proxy_repository` `.data()` listener pattern. Idempotent per `code`.
Future<void> subscribeToMapCollection(
  String appVid,
  String tableDocId,
  String subColl,
  String code,
) async {
  if (appVid.isEmpty || tableDocId.isEmpty || subColl.isEmpty) return;
  if (_mapSubscribed.contains(code)) return;
  _mapSubscribed.add(code);
  final String path =
      '$mobileTable/$appVid/$mobileTableCollection/$tableDocId/$subColl';
  try {
    firestoreDb.collection(path).snapshots().listen(
      (snap) {
        mapTableContent[code] = snap.docs
            .map((d) => (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{})
            .toList();
      },
      onError: (e) => devPrint('subscribeToMapCollection $path error: $e'),
    );
  } catch (e) {
    devPrint('subscribeToMapCollection $path failed: $e');
    _mapSubscribed.remove(code);
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/global.dart lib/firestore_repository/table_repository.dart`
Expected: No NEW `error` lines from these additions. Confirm `mobileTable`, `mobileTableCollection`, `firestoreDb`, `devPrint` all resolve (they are existing globals used by `subscribeToTable` in the same file). Pre-existing warnings elsewhere are fine.

- [ ] **Step 4: Commit** (SKIP while no-commit)

```bash
git add lib/global.dart lib/firestore_repository/table_repository.dart
git commit -m "feat(panel-card): mapTableContent store + subscribeToMapCollection reader"
```

---

### Task 4: Switch `ListMultiplePanelCard` to char-code map binding

**Files:**
- Modify: `lib/widget/list_multiple_panel_card.dart`

Replace the positional-row data binding with map binding. Rows become `Map<String,dynamic>`; tokens resolve via `resolveMapTokens`; the card subscribes via `subscribeToMapCollection`; `{ccVid}` = `doc['av']`; `{llCount}` is computed real; status tokens stay literal/`ok` (Phase B fills them).

- [ ] **Step 1: Replace the file body**

Overwrite `lib/widget/list_multiple_panel_card.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';

/// LIST_MULTIPLE_PANEL_CARD — cost-center list bound to char-code-map docs in a
/// subcollection (`MobileTable/{appVid}/tables/{tableDocId}/{subColl}`).
/// Search + colored status summary + collapsible status accordions (PERLU
/// TINDAK / PERHATIAN / AMAN) + cost-center cards: header (`<an>`/`<sn>`) +
/// colored left strip (worst status) + N nested nav panels (icon box +
/// UPPERCASE label + status pill + bold headline + details + chevron), each
/// tapping its own route with `{ccVid}` = `<av>` context.
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
  String _code = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expanded = {'danger': true, 'warn': true, 'ok': true};

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
    _panels = parsePanels(widget.component['panels']);
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '').toString().trim();
    _code = '${tp.tableDocId}/${tp.subColl}';
    if (tp.tableDocId.isNotEmpty && appVid.isNotEmpty) {
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    }
  }

  /// Phase A: only `{llCount}` is real (from the site doc `ll`). Aggregation
  /// tokens (hadir/issues/staleCount/longestGap/ps/qs/ws) arrive in Phase B.
  Map<String, String> _computeCardValues(Map<String, dynamic> doc) =>
      {'llCount': llCount(doc).toString()};

  String _resolve(String tmpl, Map<String, dynamic> doc, Map<String, String> v) =>
      resolveMapTokens(tmpl, doc, v);

  String _panelStatus(
          PanelConfig p, Map<String, dynamic> doc, Map<String, String> v) =>
      resolveMapTokens(p.status, doc, v);

  String _cardWorstStatus(Map<String, dynamic> doc, Map<String, String> v) {
    final String topLevel =
        resolveMapTokens((widget.component['status'] ?? '').toString(), doc, v);
    final all = <String>[topLevel, ..._panels.map((p) => _panelStatus(p, doc, v))];
    return worstStatus(all);
  }

  void _onPanelTap(Map<String, dynamic> doc, PanelConfig panel) {
    final String ccVid = (doc['av'] ?? '').toString();
    if (ccVid.isNotEmpty) {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'ccVid': ccVid,
        'request_vid': ccVid,
        'panel_route': panel.route,
      })));
    }
    if (panel.route.isNotEmpty && routeExist(panel.route)) {
      routeStack.push(panel.route);
      gotoRoute(panel.route);
    }
  }

  List<Map<String, dynamic>> _search(
      String query, List<Map<String, dynamic>> docs) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return docs;
    return docs.where((d) {
      final String an = (d['an'] ?? '').toString().toLowerCase();
      final String sn = (d['sn'] ?? '').toString().toLowerCase();
      return an.contains(q) || sn.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> all =
          List<Map<String, dynamic>>.from(mapTableContent[_code] ?? const []);
      final List<Map<String, dynamic>> filtered = _search(_searchQuery, all);
      final groups = groupByStatus<Map<String, dynamic>>(
        filtered,
        (doc) => _cardWorstStatus(doc, _computeCardValues(doc)),
      );

      final double availableH = MediaQuery.of(context).size.height * 0.79;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              widget.lPad, widget.tPad, widget.rPad, widget.bPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(),
              const SizedBox(height: 14),
              _buildSummary(groups),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final status in statusOrder)
                            if ((groups[status] ?? []).isNotEmpty)
                              ..._buildGroup(status, groups[status]!),
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
    final String hint = _textArray.length > 4 ? _textArray[4] : 'Cari';
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

  Widget _buildSummary(Map<String, List<Map<String, dynamic>>> groups) {
    final int d = groups['danger']?.length ?? 0;
    final int w = groups['warn']?.length ?? 0;
    final int o = groups['ok']?.length ?? 0;
    const TextStyle sep = TextStyle(fontSize: 14, color: Color(0xFF9CA3AF));
    TextSpan seg(String text, String status) => TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: statusColor(status)));
    return Text.rich(TextSpan(children: [
      seg('$d perlu tindak', 'danger'),
      const TextSpan(text: ' · ', style: sep),
      seg('$w perhatian', 'warn'),
      const TextSpan(text: ' · ', style: sep),
      seg('$o aman', 'ok'),
    ]));
  }

  Widget _buildEmptyState() {
    final String empty =
        _textArray.length > 5 ? _textArray[5] : 'Data tidak ditemukan';
    return Center(
      child: Text(empty,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
    );
  }

  List<Widget> _buildGroup(String status, List<Map<String, dynamic>> docs) {
    final bool open = _expanded[status] ?? true;
    return [
      _buildGroupHeader(status, docs.length, open),
      if (open)
        for (final doc in docs) _buildCard(doc),
      const SizedBox(height: 6),
    ];
  }

  Widget _buildGroupHeader(String status, int count, bool open) {
    final Color sColor = statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: statusBgColor(status),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded[status] = !open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: sColor, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(statusGroupLabel(status).toUpperCase(),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: sColor)),
                const Spacer(),
                Text('$count',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: sColor)),
                const SizedBox(width: 8),
                Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: sColor, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> doc) {
    final Map<String, String> v = _computeCardValues(doc);
    final String worst = _cardWorstStatus(doc, v);
    final String name = _textArray.length > 1 ? _resolve(_textArray[1], doc, v) : '';
    final String sub = _textArray.length > 2 ? _resolve(_textArray[2], doc, v) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: statusColor(worst),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A2233)),
                            overflow: TextOverflow.ellipsis),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(sub,
                              style: const TextStyle(
                                  fontSize: 14, color: Color(0xFF9AA1AD)),
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 6),
                        for (int i = 0; i < _panels.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: Color(0xFFEEF0F2)),
                          _buildPanel(_panels[i], doc, v),
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
    );
  }

  Widget _buildPanel(
      PanelConfig p, Map<String, dynamic> doc, Map<String, String> v) {
    final PanelText t = splitPanelText(_resolve(p.text, doc, v));
    final String status = _panelStatus(p, doc, v);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onPanelTap(doc, p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(panelIcon(p.icon),
                  size: 22, color: const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(t.label.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: Color(0xFF8A93A6)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      _statusPill(status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (t.headline.isNotEmpty)
                    Text(t.headline,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2233))),
                  if (t.details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.details,
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF9AA1AD))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFC7CCD4), size: 24),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: statusBgColor(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(statusPillLabel(status),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: statusColor(status))),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/widget/list_multiple_panel_card.dart`
Expected: `No issues found!`. Note the import list dropped `../global2.dart` (no longer using `normalizeTableName`) and `table_repository.dart` now provides `subscribeToMapCollection`. Confirm `mapTableContent`, `subscribeToMapCollection`, `parseTablePath`, `TablePath`, `llCount`, `resolveMapTokens`, `routeStack`, `gotoRoute`, `routeExist`, `diamondTextToList`, `transactionStore` all resolve.

- [ ] **Step 3: Run the full support suite + commit** (SKIP commit while no-commit)

Run: `flutter test test/panel_card_support_test.dart` — all pass.

```bash
git add lib/widget/list_multiple_panel_card.dart
git commit -m "feat(panel-card): bind ListMultiplePanelCard to char-code map docs"
```

---

### Task 5: Manual verification

**Files:** none (manual).

- [ ] **Step 1** Wire a screen with the confirmed component JSON (`vidtable":"20342033315492","table":"84214220504259//site"` + the two panels). Run the app (`./set_android.sh && flutter run`).

- [ ] **Step 2** Confirm the card list renders real data: header top = `<an>` (e.g. "A Product Group"), sub = `<sn>` ("S Product Group"); panel 1 headline shows `.../<nm> hadir` with `<nm>`=2 resolved; panel 2 shows `{llCount}` resolved to the real point count (e.g. "2 titik" / "9 titik"); aggregation tokens (`{hadir}`/`{issues}`/`{staleCount}`/`{longestGap}`) still literal; all cards under "AMAN" (status fallback until Phase B).

- [ ] **Step 3** Tap a panel → navigates to its `route`; confirm `ccVid` (= `<av>`) is in `transactionStore` for the destination page; confirm AppBar back pops `routeStack`.

- [ ] **Step 4** Type in search → list filters by `<an>`/`<sn>` substring.

---

## Phase B — Outline (next plan: real aggregation)

Fills `_computeCardValues` with real values, activating real statuses + grouping. Per dev-spec v2 §4:
1. **Kehadiran** — read `workforce` subcollection (`subscribeToMapCollection(appVid, tableDocId, 'workforce', ...)`), filter workers whose `av`/`sv` == this card's `doc['av']`; `{hadir}`=COUNT `ci` filled; `{issues}` text; `{ps}` mapping.
2. **Patroli** — events from `event/content`; join `lq`(event)==`ll[].li`(site doc), fallback `ln`==`ll[].ln`; `{staleCount}`/`{longestGap}` from `t` epoch vs threshold `43200000` ms; `{qs}`.
3. `{ws}` = `worstStatus([ps, qs])`; return all in `_computeCardValues`. Grouping/summary/strip then reflect real status automatically.
4. Orphan handling (points with no events; manual-scan `ln` typos).

---

## Self-Review

**Coverage:** map reader (Task 3) ✓; char-code resolver `<an>`/`<sn>`/`<nm>`/`<av>` (Task 2, used Task 4) ✓; path parse `vidtable`+`table//` (Task 1, Task 4 `_subscribe`) ✓; `{llCount}` real (Task 1 `llCount`, Task 4 `_computeCardValues`) ✓; `{ccVid}` tap (Task 4 `_onPanelTap`) ✓; search by an/sn (Task 4 `_search`) ✓; aggregation deferred to Phase B ✓; styling unchanged from the confirmed Image #6 build ✓.

**Placeholders:** none — every step has complete code. Phase B is an explicit outline gated on workforce/event schema.

**Type consistency:** rows are `Map<String,dynamic>` throughout Task 4; helpers `parseTablePath`→`TablePath`, `llCount(Map)→int`, `resolveMapTokens(String,Map,Map)→String`, `subscribeToMapCollection(String,String,String,String)`, store `mapTableContent` typed `List<Map<String,dynamic>>` — names/signatures match across Tasks 1-4. `groupByStatus<Map<String,dynamic>>` matches the generic helper from the prior plan.
