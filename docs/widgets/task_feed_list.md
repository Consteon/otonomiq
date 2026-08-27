# TaskFeedList

Grouped or flat task/entity card list with configurable `groupField` mode.

- **File:** [lib/widget/task_feed_list.dart](../../lib/widget/task_feed_list.dart)
- **Class:** `TaskFeedList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** TBD

## Purpose

Replaces the abandoned `driverStopCardFull` type. Two modes selected by `groupField`:

### MODE GROUPED (groupField non-empty, e.g. `"tst"`)
Groups task docs by state (assigned+on_delivery / failed / completed), renders per-card layout with avatar, customer, state chip, drop/pickup badges, and state-specific footer. Shows allDone banner when all tasks are completed or failed. Used by driver P10 TaskFeed.

### MODE FLAT (groupField empty `""`)
Self-contained search bar + count header + avatar cards + empty state. Reads docs matching `search`, then locally filters by user-typed query (title OR address, case-insensitive substring). Card tap dispatches `idField` to `#ACTIVE_TASK` and navigates to `route`. No status grouping, no delivery badges, no return-gate evaluation. Used by Admin P1 customer picker.

## Signature / Constructor

TaskFeedList({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad, tPad, rPad, bPad,
})

### `component` shape

| Key | Type | Mode | Description |
|---|---|---|---|
| `vidtable` | `String` | Both | Firestore container VID (`20342033315492`) |
| `table` | `String` | Both | Table path (e.g. `84214220504259//task` or `84214220504259//stock_location`) |
| `search` | `String` | Both | Filter condition (e.g. `vv◼{vehicleId}⭘tdt◼{today}` or `lt◼client⭘lst◼active`) |
| `groupField` | `String` | Both | State field for grouping. Non-empty (e.g. `tst`) = GROUPED. Empty `""` = FLAT. Absent = defaults to `tst` (GROUPED). |
| `idField` | `String` | Both | Entity ID field (default `tnm`). Dispatched to `#ACTIVE_TASK` on card tap. |
| `titleField` | `String` | Both | Display name field (default `kn`) |
| `addressField` | `String` | Both | Address/subtitle field (default `al`) |
| `iconField` | `String` | Flat | Avatar content field (default `''`). Non-empty: read `task[iconField]`. Empty or value empty: fall back to first character of `titleField` (uppercased). |
| `searchHint` | `String` | Flat | Placeholder text for the built-in search bar (default `'Cari...'`). |
| `countLabel` | `String` | Flat | Count header label (e.g. `"Customer"`). Renders as `"{N} {countLabel}"` uppercase. Empty = no count header. |
| `emptyText` | `String` | Flat | Empty-state main line (e.g. `"Belum ada customer"`). Shown when filtered count = 0. Empty = `"Tidak ada data"`. |
| `badgeTable` | `String` | Flat | Secondary table for the per-row outstanding badge (e.g. `84214220504259//asset_cache`). Subscribed in `_subscribe()`. Empty = no badge. |
| `badgeSearch` | `String` | Flat | Per-row gate over `badgeTable`, `{idField}` substituted to the row's id (e.g. `lt◼client⭘lv◼{lv}`). `autheniumDecode`'d before matching. |
| `badgeField` | `String` | Flat | Numeric field summed across matched `badgeTable` rows (e.g. `qt`). Coerced via `coerceNum`. |
| `badgeLabel` | `String` | Flat | Suffix on the outstanding chip → "↑ {sum} {badgeLabel}" (e.g. `outstanding`). |
| `seedLabel` | `String` | Flat | Amber chip text when `badgeSearch` matches **0** rows (client not seeded, e.g. `belum di-seed`). Matched rows with sum 0 still show "↑ 0 {badgeLabel}" (seeded), NOT this. |
| `typeField` | `String` | Grouped | Task type field (default `tty`). Ignored in FLAT. |
| `itemsField` | `String` | Grouped | Items array field (default `it`). Ignored in FLAT. |
| `dropField` | `String` | Grouped | Planned drop field (default `pd`). Ignored in FLAT. |
| `pickupField` | `String` | Grouped | Planned pickup field (default `pp`). Ignored in FLAT. |
| `actualDropField` | `String` | Grouped | Actual drop field (default `ad`). Ignored in FLAT. |
| `actualPickupField` | `String` | Grouped | Actual pickup field (default `ap`). Ignored in FLAT. |
| `route` | `String` | Both | Card-tap navigation route |
| `returnRoute` | `String` | Grouped | allDone button route. Ignored in FLAT. |
| `returnGateTable` | `String` | Grouped | Return-CTA gate table. Ignored in FLAT. |
| `returnGateSearch` | `String` | Grouped | Return-CTA gate search. Ignored in FLAT. |
| `mapsUrl` | `String` | Grouped | Keyed DSL `url◼<template>⭘fallback◼<template>⭘empty◼<message>⭘label◼<button text>`. `url` required, the rest optional. `<field>` tokens are task-doc fields, URL-encoded on substitution. Absent = no button anywhere (backward compat). See "Maps button" below. |
| `text` | `String` | Grouped | Diamond-separated labels. 15 segments (section headers, badges, banners). Unused in FLAT. **No maps slot** — the button caption lives in `mapsUrl`'s `label◼` key. |

### Maps button (GROUPED only)

When `mapsUrl` is set, every card gets a "Lihat Lokasi" button on its own row
under the address — **every status**, `Sudah Selesai` and `Dilaporkan Gagal`
included. One uniform rule, zero per-status branching.

> **FLAT mode ignores `mapsUrl`, silently.** `_parseMapsCfg()` runs in
> `initState` for both modes, but only the GROUPED card (`_buildTaskCard`)
> renders the button — so `mapsUrl` on a FLAT `TASK_FEED_LIST` is dead
> config: no button, no error, no log line, nothing to find on the device.
> If the button is missing, check `groupField` before anything else (empty
> `""` = FLAT). This is deliberate, not an oversight: the FLAT card is a
> customer picker, not a stop list, and FLAT support was explicitly ruled out
> for this feature. Put the button on the GROUPED screen, or use
> `DRIVER_STOP_CARD` / `WORKSPACE_HEADER`.

Caption: `mapsUrl`'s `label◼` key, else the hardcoded default
`📍 Lihat Lokasi`. **There is no `text` slot for it** — appending a `◆` segment
is a hand-counted edit whose failure mode is silent, and this widget's `text` is
already 15 segments long.

Template choice: try `url`; if any `<token>` in it is empty / absent /
whitespace-only, try `fallback`; if that also fails the button is greyed out and
the `empty` message is printed beneath it. The emptiness test is generic — no
field name is hardcoded in Dart.

Tapping opens the URL with `LaunchMode.externalApplication`. The card itself is
tappable (`_onCardTap`), but no `stopPropagation` equivalent is needed: hit
testing adds gesture recognizers deepest-first and the arena awards the tap to
the innermost, so the maps button wins and the card's route navigation does not
fire. `test/task_feed_list_test.dart` → `maps tap does not navigate the card
(gesture arena)` is the witness.

The GROUPED card address renders up to **2 lines** (reverse-geocode addresses
are long by construction). FLAT-mode cards are unchanged at 1 line.

Implementation: `MapsButton` in `driver_home_support.dart`, shared with
`DRIVER_STOP_CARD` and `WORKSPACE_HEADER`.

### Actual-over-plan display

Per-card drop/pickup counts use `resolveItemQty` (actual-over-plan): if the
actual field is present, non-null, and non-empty, it is displayed; otherwise the
plan field is used. Pre-execution items carry `ad: null` / `ap: null` (from
`toItMap()`), so the null check falls back to plan. The previous `isDone`
if/else branching is replaced by this uniform helper.

## State / Dependencies

- **GetX Obx** for reactive mapTableContent reads.
- **DriverHomeState** (driver_home_support.dart) for vehicleId dependency.
- **stopStatusOf** (driver_home_support.dart) for state normalization (GROUPED only).
- **Static `_flatSearchControllers`** per-scrName `TextEditingController` map. Cleared by `clearFlatSearch(scrName)` on route change (called from `buildPage` in `ui_component.dart`).

## Important Behavior

### Both modes
- Card tap: `_onCardTap` dispatches `task[idField]` to `#ACTIVE_TASK`, then `routeStack.push(route)` + `gotoRoute(route)`.
- `filterDriverHomeDocs` decodes + resolves the config search (autheniumDecode, curly tokens, screenTx tokens, multi-clause AND filter).

### GROUPED mode only
- `on_delivery` tasks group with `assigned` (still-open).
- `load_rejected` tasks are unconditionally excluded from both GROUPED and FLAT modes. The exclusion is applied in `_getFilteredTasks()` via `excludeByStatus(filtered, kDefaultExcludeStatus, statusField: groupField)`, comparing the raw configured `groupField` value (defaulting to `tst`, and falling back to `tst` in FLAT mode where `groupField` is empty; not `stopStatusOf`). No component config key controls this -- it is semantic, not a display preference. This is deliberately unconditional (no `excludeStatus` config override), unlike the sibling `driver_stop_card` / `nav_action_card` widgets which use a config-fallback shape.
- `allDone` = pending group empty AND tasks non-empty.
- Return-CTA gate: opt-in via `returnGateSearch` + `returnGateTable`.
- Dead routes degrade gracefully (silent push+goto).
- Distance line: HIDDEN. customerConfirmed: HIDDEN.
- stopNumber: 1-based global doc-order index.

### FLAT mode
- **Search bar:** built-in, above cards. User-typed query filters loaded docs by `titleField` OR `addressField` (case-insensitive substring). Plain text -- no `autheniumDecode` (config search already decoded upstream).
- **Count header:** `"{N} {countLabel}"` uppercase, where N = count after config search AND local search filters.
- **Card anatomy:** avatar (40x40, iconField value or first-letter fallback) + title (14px bold) + subtitle (11px textMid) + chevron.
- **Empty state:** shown when filtered count = 0. Emoji + emptyText + static secondary hint.
- **Search reset:** `clearFlatSearch(scrName)` clears controller text on route change. State persists across nav (cached SDUI widget, same ObjectKey).
- No status reading, no `stopStatusOf`, no grouping.
- No delivery badges (drop/pickup/actual).
- No return-gate subscription/evaluation.
- No allDone banner or return button.

## See Also

- [route_feed_header.md](route_feed_header.md) -- companion header widget (GROUPED)
- [driver_stop_card.md](driver_stop_card.md) -- P4 sibling card
