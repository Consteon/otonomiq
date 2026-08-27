# DisplayList (`displayList`)

Bordered list frame with an optional title chip, driven entirely from page JSON. Three render variants
share the outer frame; `tableCardInteractive` is the one with search, cards and a detail popup.

- **File:** [lib/widget/display_list.dart](../../lib/widget/display_list.dart) · renderer for
  `tableCardInteractive`: [lib/widget/ftz_array_search.dart](../../lib/widget/ftz_array_search.dart) ·
  pure helpers: [lib/widget/ftz_array_search_support.dart](../../lib/widget/ftz_array_search_support.dart)
- **Class:** `DisplayList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1 (`DisplayList2` exists in the index but its source file is empty)
- **Dispatched from:** `build_display_component.dart` on `tip == 'displaylist'`

## Purpose

Renders a table (`MobileTable/{vid}/tables/{name}/content`) as a list inside a rounded, bordered frame.
Which list you get depends on `variant`:

| `variant` | Renderer | Notes |
|---|---|---|
| `widget` | `ListView` of `buildPage(component['children'], scrName, dialog: true, clear: false)` | Not a table at all — an arbitrary child list |
| `tablecard1` | `ListView.builder` of `Card` + `ListTile` | Plain single-line subtitle from `replaceMarker(content, row, indexStart, false)`, so `\n` renders as ` -- `. No label parsing, no detail popup |
| `tableCardInteractive` | `FtzArraySearch` | Search field + result count + rich cards + tap-to-open detail dialog |
| anything else | empty `Container()` | |

`variant` is lower-cased before comparison, so `tableCardInteractive` and `tablecardinteractive` are the
same thing.

## Signature / Constructor

```dart
DisplayList({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

Keys read by `DisplayList` itself:

| Key | Type | Default | Description |
|---|---|---|---|
| `variant` | `String` | `''` | See the table above. Trimmed + lower-cased. |
| `table` | `String` | `''` | Table code, e.g. `84214220504259//report-checklist`. Normalised by `normalizeTableName`. Used directly only when the component has no `position`; with a `position`, `build_display_component.dart` seeds `txfController[scrName][position].finalData` from it and `DisplayList` reads the table code back from there (so another widget can retarget the list at runtime). |
| `position` | `int`/`String` | — | Optional. When present, the table code comes from the form slot (above) and the widget rebuilds through `GetBuilder<WidgetUpdateController>(id: '<scrName>-<position>')`. |
| `filter` | `String` | `''` | `searchTable` DSL, applied once after load. `◆` separates OR clauses. |
| `sort` | `String` | — | `asc` / `desc`; sorts on the integer key at row index 0. Anything else = arrival order. |
| `content` | `String` | — | Row template with `<N>` markers. `null` falls back to the row's own columns. |
| `indexStart` | `int` | `0` | Marker base. `1` means `<N>` = `row[N]` (row[0] is the sort key, row[1] the timestamp). Live screens use `1`. |
| `text` | `String` | — | `◆`-separated. `text[0]` = the title chip drawn on the frame border; a blank `text[0]` collapses the top padding. Further segments are read by `FtzArraySearch` (below). |
| `height` | `num` | `150` | `maxHeight` of the frame. |
| `margin` | `String` | `0,0,0,0` | `top,bottom,left,right`, via `marginArray`. |
| `children` | `List` | — | `variant:"widget"` only. |
| `chain` | any | — | Read into a `hasChain` field that is never used. Inert. |

Additional keys read by `FtzArraySearch` (`tableCardInteractive` only):

| Key | Type | Default | Description |
|---|---|---|---|
| `detail` | `String` | falls back to `content` | Template for the detail popup. Usually longer than `content`. |
| `image` | `String` | `''` | Marker(s) resolved by `getImageList`; drives the 64px card thumbnail (with a `+N` badge) and the popup's horizontal image strip. |
| `chipLabel` | `String` | `''` | Name of the meta field lifted out of the card rows into a chip. Empty = keyword guess (`jenis`/`kategori`/`tipe`/`kondisi`/`status`) on a value ≤ 24 chars. |
| `icon` | `String` | `Icons.search` | `otqIcons` key for the search-field prefix. |
| `color` | `String` | `default` | Search-field text colour, parsed with `int.parse`. |
| `rowSplit` | `String` | `''` | **See below.** Optional; blank = off. |
| `text[1]` / `text[2]` | `String` | `''` | Search placeholder label / hint (when `content` is set). |
| `text[3]` | `String` | `'Tidak ada data'` | Empty-state headline. |
| `text[4]` / `text[5]` / `text[6]` | `String` | — | Legacy shape: when `content` is NULL and `text` has more than 6 segments, `text[6]` is JSON-decoded into the display object and the search label/hint come from `text[4]`/`text[5]`. |

> A `text` string with fewer than 3 segments makes the title/label/hint assignment throw inside its
> `try`/`catch`, leaving all three empty. The list still renders. Nothing crashes, nothing is logged.

## `rowSplit` — stacked header/value for bare-placeholder lines

`rowSplit` is a **separator string**. It is opt-in and defaults to OFF.

**OFF (absent, empty, or whitespace-only): zero behaviour change.** The widget takes the original
single-pass render/parse path. Every `displayList` that does not author `rowSplit` renders exactly as it
did before the param existed.

**ON:** the `content`/`detail` template is processed one line at a time.

| Template line | Behaviour |
|---|---|
| blank | dropped (as before) |
| carries any literal text — `Tanggal: <2>`, `Catatan <9>` | **untouched**: the existing `Label: value` colon path. A value that happens to contain the separator is NOT split. |
| a bare `<N>` and nothing else | the substituted value is split at the FIRST occurrence of the separator; **both sides are trimmed**; left = header, right = value |
| a bare `<N>` whose value is empty, whitespace, `*`, or still the literal `<N>` | the whole line is **dropped** |
| a bare `<N>` whose value has no separator | one plain line, no header |

Both `"task|status"` and `"task | status"` therefore yield the same header `task` and value `status`.
`"a|b|c"` yields `a` / `b|c` — first separator only. A multi-character separator (`" :: "`) works with no
extra config.

`*` is dropped because `CHECKLIST_DYNAMIC` writes it into a checklist slot it did not use. The literal
`<N>` is dropped because `replaceMarker` only iterates `i < row.length`, so a marker past the end of a
lean row survives verbatim as text.

Unlike the colon path, a `rowSplit` header is **not** length-capped: `Sapu halaman dan area pedestrian`
(32 chars) is a legitimate header.

Live example (`op1Screen!D1619`, page `vertikaTeknoLokaciptaLogChecklist`):

```json
{"type":"displayList","variant":"tableCardInteractive",
 "table":"84214220504259//report-checklist",
 "content":"Tanggal: <2>\nJenis: <30>\nLokasi: <8>\nSite: <6>\nKeterangan: <9>",
 "image":"<10>",
 "detail":"Tanggal: <2>\nJenis: <30>\nLokasi: <8>\nSite: <6>\nKeterangan: <9>\n \n<11>\n<12>\n<13>\n<14>\n<15>\n<16>\n<17>\n<18>\n<19>",
 "rowSplit":"|","sort":"desc","indexStart":1}
```

renders `<11> = "Sapu halaman dan area pedestrian|Selesai"` as:

```
SAPU HALAMAN DAN AREA PEDESTRIAN
Selesai
```

### Limitations

- `rowSplit` is read **raw**, like `content` and `detail` (only `table` and `filter` go through
  `autheniumDecode` in this widget). A separator the server escapes — `◼`, `⭘`, `◆` — will arrive as
  `_u25FC_` / `_u2B58_` / `_u25C6_` and will not match. Use a plain ASCII separator.
- `rowSplit` is honoured on `content` too, but `tableCardInteractive` assigns card slots **positionally**
  (`[0]` = eyebrow, `[1]` = title, last = free text, the rest = meta rows). Dropping empty slots changes
  the line count and therefore shifts those roles. **Keep bare placeholders in `detail`, not `content`.**
- `rowSplit` does nothing on `variant:"tablecard1"` or `variant:"widget"` — neither parses labels.
- A bare-placeholder value that itself contains a line break is treated as ONE unit.
- Pre-existing, out of scope: the `tablecard1` no-`content` fallback prints `pickTable.first[...]` instead
  of `pickTable[index][...]`, so every card shows the first row's columns
  ([display_list.dart:200](../../lib/widget/display_list.dart)).

## `tableCardInteractive` card anatomy

`content` is parsed into lines and mapped onto card slots positionally by `splitContentRoles`:
line 0 = eyebrow (timestamp, with an icon and a chevron), line 1 = title, the last line = free text
(2 lines, ellipsised), everything between = meta rows with an icon from `metaIcon` (falling back to
printed `Label: ` when no keyword matches). One meta row may be lifted into a chip via `chipLabel`.
Shorter blobs collapse from the bottom up: 2 lines lose the note, 1 line is title-only.

Tapping a card opens the detail dialog, which renders every line stacked: uppercase 10px dim header,
14px strong value, 14px gap between lines, `-` for an empty value.

## State / Bloc / Dependencies

- **GetX:** `GetBuilder<WidgetUpdateController>` rebuild (`id: '<scrName>-<position>'`); `tableContent`
  is watched with `ever(...)` inside `FtzArraySearch` so the list repaints when the table syncs.
- **Redux:** reads `transactionStore.state.screenTx['#TABLE<code>']` — written by `subscribeToTable`.
- **Repository:** `subscribeToTable` (`lib/firestore_repository/table_repository.dart`).
- **Side effects:** none. `DisplayList` is read-only; it writes no history and no table row.

## Important Behavior

- `FtzArraySearch` is SHARED with PICKER mode: `otq_txf.dart` and `otq_txf_2.dart` open it in a dialog
  with a `resultController`. In picker mode a tap fills the controller and pops instead of opening the
  detail dialog, and the component it receives is a **txf** component (so `rowSplit`, `detail`, `image`
  etc. are simply absent).
- The table code is normalised with `normalizeTableName` before the `#TABLE<code>` read; a keyed `a//b`
  name read back raw resolves to `null` and the list stays empty forever.
- Every `initState` block in `FtzArraySearch` is individually wrapped in `try`/`catch`, and its fields are
  initialised at declaration rather than `late`, so a swallowed parse error cannot become a
  `LateInitializationError` at build/dispose.

## See Also

- [lib/widget/ftz_array_search.dart](../../lib/widget/ftz_array_search.dart) — the
  `tableCardInteractive` renderer; it has no doc page of its own yet
- [list_card.md](list_card.md) — the universal keyed-collection list; prefer `LIST_CARD` for NEW screens
- [detail_card.md](detail_card.md) — keyed single-record detail renderer (2-column summary; a different
  UI from this widget's stacked popup)
- [tasklist.md](tasklist.md), [checklist_dynamic.md](checklist_dynamic.md) — the two writers that produce
  the `task|status` / `task | status` strings `rowSplit` reads back
