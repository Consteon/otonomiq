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
| `tableCardInteractiveV6` | `FtzArraySearch` (v6 layout) | Same data, same detail dialog, different list: no frame, no cards — a heading, range chips, day groups and flat rows. **See below.** |
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

## `variant: "tableCardInteractiveV6"` — the Vertika v6 report list

Opt-in. A component that keeps `tableCardInteractive` renders exactly what it renders today, and so does
every PICKER-mode instance (a `txf` component's `variant` is `qrScan`/`text`, never this). Same table,
same `content`/`detail`/`image`/`chipLabel` keys, same detail dialog — only the list layout differs.

### Sheet config

The base template hardcodes `"variant":"tableCardInteractive"`, so the v6 list needs a template that
does not. **`Widget!` is authored in columns I and J, not A and G** — `A1` is `=ARRAYFORMULA(I1:I)` and
`G<n>` is `=IF(ISERROR(J<n>),"",J<n>)`, so the VLOOKUP source mirrors J. Rows past the last widget
already carry those formulas, so a new widget is two cells in a blank row.

What is live (Sep 2026): `Widget!I377` = `displayTableInteractiveVariant`, `J377` = the same template
with `"variant":"[VARIANT]"`, and each screen's `D` formula gained a 16th `SUBSTITUTE` mapping
`"[VARIANT]"` to a **new column T**. One shared template serves every variant instead of one row per
variant — better than a `displayTableInteractiveV6` row, and it does not disturb the screens that still
point at `displayTableInteractive`.

Per screen, three cells on its `displayList` builder row:

| Cell | Value |
|---|---|
| `B<n>` | `="displayTableInteractiveVariant"` |
| `T<n>` | `="tableCardInteractiveV6"` |
| `D<n>` | the 16-`SUBSTITUTE` formula (copy it down from a row that already has it) |

Live rows: `574` = `vertikaTeknoLokaciptaLogReportPatrol` (page assembled at `B564`), `1284` =
`vertikaTeknoLokaciptaLogReportRoutine` (page at `B1274`). Other report screens keep
`="displayTableInteractive"` and are untouched.

> `op1Screen` holds a SECOND `vertikaTeknoLokaciptaLogReportPatrol` at row `1263` with a different
> layout. `Plug!C` resolves by `VLOOKUP`, which takes the FIRST match — row `564` — so `1263` is dead
> today. Deleting or reordering rows above it would silently swap the page.

One `content` edit is worth making at the same time, though it is not required: drop `Nama: <4>`. This
is the user's own list; the v6 spec removes the reporter's name and shows it again only in a
team/supervisor view. The renderer will not drop an authored field on its own — and the name still
appears in the detail sheet's metadata table, which reads `detail`, not `content`.

### Layout

| Part | Size & colour | Behaviour |
|---|---|---|
| Heading | `text[0]` at 17/600 `foreground`; subtitle 12/500 `v6MutedFg` — `"<n> laporan · <rentang>"` | Subtitle follows the active filter; `Hasil pencarian` while searching; `Belum ada laporan` when empty |
| Search | 44 dp icon button, right of the heading | Toggles the search field **in place of** the filter row. Closing it clears the query |
| Range chips | 36 dp pills, 14/600; active = `primaryColor` + `otqOn(primary)`, idle = `v6Muted` + `v6MutedFg` | `Hari ini · 7 hari · 30 hari · Semua`, default **7 hari**. `Semantics(button:, selected:)` |
| Day header | 13/600 `v6MutedFg` | `Hari ini · Jumat, 11 Sep` / `Kemarin · …` / `Rabu, 9 Sep` — same shape as the Log tab |
| Row | 64 dp thumb + 12 gap + text, 12 dp vertical padding, 1 dp `v6Border` rule (none on the last row of a group) | Whole row is the target (88 dp) → detail dialog. No chevron |
| Row line 1 | Clock 16/600 tabular `foreground`, chip pushed right | Clock is `row[0]` formatted `HH:mm` |
| Row line 2 | 13/500 `v6MutedFg`, **up to two lines** | Title + every meta value joined with ` · `. The mock specifies one line; its sample always fits because it carries two fields. Wrapping costs nothing when the text fits and beats hiding a site name when it does not (ui-ux-pro-max `Essential Text Truncation`, Critical). Two is the ceiling because tapping the row is the full-detail path |
| Row line 3 | 14/400 `foreground`, 2 lines | Empty → `Tanpa catatan`, italic, `v6MutedFg` |
| Chip | 12/600 on a tone ground, radius 13 | Three levels, below |
| Empty | 72 dp `v6Muted` tile + 18/600 headline + 14 `v6MutedFg` body | Headline names the active range. No button — this screen only looks |

### The chip is semantic now

`reportTone` maps the value to ok / warn / err / neutral by keyword, so `Aman kondusif` is green,
`Perlu tindak lanjut` amber and `Insiden` red. The v1 card painted all four the same indigo
(`#E0E7FF`/`#4338CA`), which the v6 audit called out as "outside the palette".

Word order is load-bearing: the danger list is tested before the ok list, because **`Tidak aman`
contains `aman`**. `ok` counts only as a whole value — as a substring it matches `Lokasi` and `Diblokir`.

### Where the clock and the day come from

`row[0]`, which is the document's `t` field: `MobileTableController.addContent` stamps
`t = getNowMillisecondFromEpoch()` on every content document
([mobile_table_controller.dart:137](../../lib/states/mobile_table_controller.dart)) and
`createInternalTableDynamic` inserts it at index 0 of every row
([table_repository.dart:2097](../../lib/firestore_repository/table_repository.dart)).

`reportEpoch` still guards it, and the **upper** bound is the interesting one: a 14-digit
`yyyyMMddHHmmss` id clears the 2010 floor and would be read as the year 2612, collapsing every day
group into one. A row whose `row[0]` is not a stamp is **never hidden** — it keeps its eyebrow text in
the clock slot, groups under `Tanpa tanggal`, and passes every range filter. The chips are a view over
time, not an access rule.

Grouping is **consecutive**, not bucketed: the rows arrive in the order the component's `sort` asked
for, and re-sorting them here would silently override the sheet. On an unsorted table a day can appear
more than once — which is honest about the ordering rather than hiding it.

### Deviations from the v6 mock

- **The navy app bar is not ours.** `AnyPage` paints one app bar for every SDUI page from
  `screenUIComponent[page]['title']`, with the tenant name and the reload button in it. The heading and
  the count the mock puts up there are rendered by the component instead. Changing the app bar itself is
  a page-level change, not a component one.
- **No "Menunggu koneksi" badge.** A report submitted offline is not in `tableContent` at all — the row
  is written to Firestore by `historySync` when the connection returns, so there is nothing for this
  widget to mark. Showing it means decoding the local history queue's `addToTable` payloads back into
  display rows; that is a pipeline change, not a layout one.
- **Range chips `Wrap` instead of scrolling horizontally.** The mock scrolls the row; at large text
  scale a scroller clips the labels it exists to show (ui-ux-pro-max `Chip Collection Reflow`, High).
  Each chip must shrink-wrap: a `Container` with `alignment` and no width expands to its maximum
  constraint, and inside a `Wrap` that maximum is the whole row, so every chip takes a line of its own.
  `Center(widthFactor: 1)` centres vertically without claiming the width.
- **No ground colour of its own.** v6 specifies `--color-background` #FFFFFF, but this app's pages are
  not white: `ThemeData` sets no `scaffoldBackgroundColor`, so it falls through to Flutter's Material-3
  default surface `#FFFBFE`. A white block was tried and rejected on device — it reads as the card the
  redesign exists to remove. Measured against `#FFFBFE` nothing is lost: body text 17.4:1, the muted
  13/500 line and the day headers 7.4:1, chip labels unchanged (they sit on their own grounds). Only the
  decorative grounds flatten — the idle chip and the empty-thumb box go 1.25:1 → 1.11:1 against the
  page, the 1 dp rule 1.25:1 → 1.22:1 — and those are non-text, so no bar applies.
- **Two contrast fixes to the mock's own values.** `--color-disabled-fg` `#949DB3` is 2.72:1 on white —
  it is used for live `Tanpa catatan` text and for the empty-thumbnail icon (2.38:1 on `#EEF0F4`, under
  the 3:1 non-text bar). Those become `v6MutedFg` (7.58:1) and `v6BorderStrong` (3.20:1).
- **The detail view is a modal sheet in v6 only.** A bottom sheet was built for the v1 card in Aug 2026
  and rejected on device ("lebih baik versi sebelumnya yang dialog"). The v6 mock argues for one again
  and the decision was re-taken deliberately in Sep 2026 — see the section below. `tableCardInteractive`
  keeps its centred `Get.dialog` unchanged.

### The detail sheet

`lib/widget/report_detail_sheet.dart` · `showReportDetailSheet(...)`, opened from `_onRowTap` when the
variant is v6. Same `detail` template, same `_linesFor` parse, same images as the v1 dialog — only the
container and the layout change, so a screen that switches variants shows the same fields either way.

| Part | Size & colour | Behaviour |
|---|---|---|
| Sheet | Sized by its content, **ceiling** 88 % of screen height; top radius 24, white; scrim `#0F172A` @ 55 % | `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)`. Closes on X, drag, scrim, or system back. Never draggable to full: a sheet that reaches 100 % is a page, and keeping the list visible behind it is the whole reason it is not one |
| Sticky head | 36×4 handle `v6BorderStrong`, title 17/600, 44 dp close | `builder:` shadows `context`, so `Navigator.of(ctx).pop()` is the sheet's own route — never a State context that may already be gone ([Get.dialog stale-context trap](../../lib/widget/attendance_qr_selfie_gps_verify.dart)) |
| Gallery | 4:3 full-bleed `PageView`; `n/total` pill top-right, `Perbesar` pill bottom-left, page dots (active 16×6) | Tap either the photo or the pill → full-screen viewer. No photos: a 96 dp `v6Muted` strip saying `Tanpa foto`, not an empty 4:3 box |
| Head | Chip (semantic tone), clock 22/600 tabular, 14/500 `v6MutedFg` `"<long date> · <place fields>"` | Clock and long date from `row[0]`; the template's own date text when there is no epoch |
| Keterangan | Label 13/600 `v6MutedFg`, body 16/1.5 `SelectableText` | Full text, never clipped. Empty → `Tanpa catatan`, italic, `v6MutedFg` |
| Metadata | 104 dp label column 14/500 `v6MutedFg`, value 14/400, 1 dp rules | Every field that is neither the chip, a place, the stamp nor the note, in template order, then `Dibuat` |
| Viewer | `#0B0F1A`, `PageView` + `InteractiveViewer` 1–4×, counter in the bar, caption under the image | Same shape as `item_card_detail.dart`'s viewer. Caption is `"<long date> · <clock> · <place>"` — under the photo, not stamped over it |

**Field placement is by LABEL, not by position.** The card has four slots and has to be positional; the
sheet has room for everything, so `splitDetailRoles` reads line 0 as the stamp, the last line as the
note, and sorts the middle by what its label says: `isPlaceLabel` (lokasi/alamat/posisi/site/area/
gedung) to the head, the chip out via `chipLineIndex`, everything else to the table. An unmapped label
lands in the table — the slot that can hold anything — so no field can fall out.

That also hides a config bug the mock complains about: the live patrol screen has `Lokasi` holding the
site and `Site` holding the unit. Both join the same head line, so the swap stops being visible without
the renderer pretending to know better than the sheet.

**The height is a ceiling, not a height.** The mock specifies a flat 88 %, which is right for the three
photos and a paragraph it draws and wrong for a report with no photo and no note — that would sit in a
third of a screen of white. `Column(mainAxisSize: min)` + `Flexible` gives the mock's result whenever the
content is that long and an honest sheet when it is not. `Flexible` and not `Expanded` is the whole
mechanism: `SingleChildScrollView` shrink-wraps its child in the scroll axis
(`_RenderSingleChildViewport.performLayout` constrains the *child's* size), so under a loose `Flexible`
it takes the height it needs; `Expanded` is tight and forces it to the ceiling.

**Not built: the sync-status chip.** The mock puts `Terkirim / Menunggu koneksi / Gagal terkirim` in the
metadata. Every row in the table is by definition already sent — `historySync` is what wrote it — so the
chip would be a constant. Same root cause as the list's missing offline badge.

**A template with no condition field just gets no chip.** `vertikaTeknoLokaciptaLogReportRoutine`
authors `Tanggal / Nama / Lokasi / Site / Keterangan` — five lines, no `Kondisi`. `chipLineIndex` finds
nothing, `chip` stays `''`, and neither the row nor the sheet head draws one. An absent condition is not
rendered as a neutral one. Locked by tests.

**`Pelapor` is whatever the sheet called it.** The mock's label is `Pelapor`; the live template says
`Nama`, and renaming a tenant's authored label in the renderer is not this widget's call.

### Tests

`test/ftz_array_search_v6_test.dart` — 43 tests over the pure helpers: tone keywords (including the
`Tidak aman` ordering trap and the `ok`-as-substring trap), `reportEpoch` at both bounds, Indonesian day
headers at the today/yesterday/older edges, range boundaries at 6/7/29/30 days, `highlightSpans`, and
`reportSubline`, plus `isPlaceLabel`, `splitDetailRoles` on the live patrol template (chip lifted, place
vs table split, nothing dropped, explicit `chipLabel` override, degenerate 0/1/2-line blobs) and the
head/caption strings with and without an epoch.

`test/report_detail_sheet_test.dart` — 5 widget tests. The sheet IS pumpable when `images` is empty:
that branch draws the `Tanpa foto` strip and never calls `displayImage`, so the height rule, the sticky
head, the empty note and the field placement are all checked off-device. The gallery is not — it reaches
for the network.

> The height assertion was wrong on its first pass and passed a deliberately broken layout twice: once
> because `find.ancestor(... ConstrainedBox).first` above the title resolves to the close `IconButton`'s
> box, and once because the broken layout measures 742.72 against a ceiling of 742.72, so
> `lessThan(ceiling)` was true. It now measures `find.byType(BottomSheet)` and demands a full 100 dp of
> clearance.

Six helper mutants (tone loop order, missing epoch upper bound,
`<` → `<=`, chip left in the table, place/table split removed, year dropped from the long date) were
each confirmed to fail the suite. The widget itself is not pumped — `displayImage` reaches for the network and
`subscribeToTable` for Firestore.

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

- [lib/widget/ftz_array_search.dart](../../lib/widget/ftz_array_search.dart) — the renderer for both
  interactive variants; it has no doc page of its own yet
- [lib/widget/report_detail_sheet.dart](../../lib/widget/report_detail_sheet.dart) — the v6 detail sheet
  and its full-screen photo viewer
- [list_card.md](list_card.md) — the universal keyed-collection list; prefer `LIST_CARD` for NEW screens
- [detail_card.md](detail_card.md) — keyed single-record detail renderer (2-column summary; a different
  UI from this widget's stacked popup)
- [tasklist.md](tasklist.md), [checklist_dynamic.md](checklist_dynamic.md) — the two writers that produce
  the `task|status` / `task | status` strings `rowSplit` reads back
