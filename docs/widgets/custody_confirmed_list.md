# custody_confirmed_list

| field | value |
|---|---|
| file | `lib/widget/custody_confirmed_list.dart` |
| dispatch | `custody_confirmed_list` |
| status | draft |

## Purpose

P7 read-only list of driver-confirmed items. Reads `ip[]` from the opening
vehicle_check doc, JOINs item names from the item subcollection. Renders per
item: name, category chip, qty, green checkmark -- inside a grouped white card
with an eyebrow section title and theme-aware summary count pill. Optionally
renders a "next-step" hint footer card below the grouped card when text
slots 3-4 are provided.

Also used by the VTL `WarehouseClosingMatch` screen, where the optional
`flow*` config adds a movement-badge layer: per item, `Antar {Σad}` and
`Ambil {Σap}` chips sourced from `task.it[]` actual quantities. A recount
knows condition (isi/kosong), never direction -- so the badge is an ADDITIVE
layer and is never derived from `ip`. With the `flow*` keys absent the widget
renders exactly as before (driver P7 depends on this).

## Component JSON

| key | type | required | notes |
|---|---|---|---|
| `table` | string | yes | vehicle_check path |
| `search` | string | yes | opening doc search with curly tokens |
| `joinTable` | string | yes | item subcollection path |
| `text` | string | no | diamond-separated label slots |
| `actualField` | string | no | default `ip` |
| `vidtable` | string | no | explicit appVid |
| `com` | string | no | tenant container |
| `flowTable` | string | no | movement source table (e.g. `84214220504259//task`). Empty = badge layer off |
| `flowSearch` | string | no | trip/vehicle/day filter (e.g. `vv◼{activeVehicle}⭘tdt◼{today}`). REQUIRED with `flowTable`: empty = badge layer off (fail-closed — an empty search would sum the whole task collection) |
| `flowItemsField` | string | no | items array in the task doc; default `it` |
| `flowKeyField` | string | no | item key joining to a list row; default `ii` (`in` also works) |
| `dropField` | string | no | **names the ACTUAL drop field** on this widget; default `ad`. ⚠ INVERTED vs `CIRCULATION_SUMMARY` / `TASK_FEED_LIST` / `ROUTE_FEED_HEADER`, where `dropField` names the PLAN (`pd`). Writing `pd` here silently sums planned instead of delivered — see [Field-name trap](#field-name-trap-dropfield--pickupfield-mean-actual-here) |
| `pickupField` | string | no | **names the ACTUAL pickup field** on this widget; default `ap`. ⚠ Same inversion: writing `pp` here silently sums planned instead of collected — see [Field-name trap](#field-name-trap-dropfield--pickupfield-mean-actual-here) |
| `flowText` | string | no | ◆-separated badge labels; default `Antar◆Ambil` |
| `groupByItem` | string | no | `TRUE` to merge ip[] rows by `ii` into one row per item (counter counts unique items, qty = sum across conditions). Truthy whitelist: `TRUE`/`true`/`1`/`yes`/`ya`; everything else = OFF. |
| `condField` | string | no | condition field on ip[] entries; default `cd` |
| `condLabels` | string | no | `circle`-separated `square`-pairs mapping raw condition values to display labels (e.g. `full◼Penuh⭘empty◼Kosong`). Parsed via `parseCondLabels` / `parseBuckets` (driver_home_support.dart). Missing = raw `cd` values shown. The literal label `'ok'` is unsupported due to a `parseBuckets` default; see section 8 of the plan. |
| `condText` | -- | -- | **NOT IMPLEMENTED. DO NOT SET THIS KEY -- it is INERT.** Use `condLabels` instead. This key was proposed as an alternative (positional diamond-segment format) but rejected as fragile (D-C). Setting it has no effect: no crash, no log, no analyzer warning -- the value is silently ignored. This warning exists because dead SDUI config has shipped silently before in this repo (see `custody-mode-toggle` incident). |

### Text slots

| index | default | description |
|---|---|---|
| 0 | `Yang Dikonfirmasi` | section title (eyebrow) |
| 1 | `returnable` | category label: returnable |
| 2 | `consumable` | category label: consumable |
| 3 | *(empty)* | hint label (e.g. `Selanjutnya`); uppercased in widget |
| 4 | *(empty)* | hint body (e.g. `Mulai eksekusi task hari ini, dimulai dari stop 1.`) |

## Subscriptions

- `vehicle_check` via `table` + `subscribeToMapCollection`
- `item` via `joinTable` + `subscribeToMapCollection`
- `task` via `flowTable` + `subscribeToMapCollection` — opened **only when
  `flowTable` is non-empty**. Screens that omit the badge layer (driver P7)
  open no third listener at all. Uses the same `<appVid>/<tableDocId>/<subColl>`
  code prefix as the two above: the `mapTableContent` key omits the vid, so
  without that prefix another tenant's identical path would dedup the stream
  away.

## Visual Layout (v2 redesign)

1. **Eyebrow row** -- section title (text slot 0) left-aligned, summary count
   pill (`"N item"`) right-aligned. Pill uses theme-aware HSLColor derived from
   `Theme.of(context).primaryColor` (matches `otq_bottom_nav_bar.dart` pattern).
2. **Grouped card** -- single white rounded card (borderRadius 16, subtle dual
   shadow, 1px border), containing item rows separated by inset hairline
   dividers (indent 50, not after last row).
3. **Item row** -- check_circle_rounded icon (green), item name (15px w600),
   then a `Wrap` (spacing 6, runSpacing 4) carrying the optional neutral gray
   category chip plus up to two movement badges (`Antar` / `Ambil`, each hidden
   when its sum is 0); right-aligned qty (18px w700 green). With the `flow*`
   keys absent the `Wrap` holds exactly one child -- the unchanged chip, at the
   same top-4 offset, because the chip's own `margin` moved out to the `Wrap`'s
   `Padding`.
4. **Next-step hint footer** -- optional; rendered only when text slot 3 or 4
   is non-empty. Theme-tinted container (hintBg/hintBorder from primaryColor
   HSL), left icon chip (arrow_forward_rounded in hintIconBg/hintAccent), right
   column with uppercased label (slot 3, hintAccent) and body text (slot 4).
   Gap 14px below grouped card.
5. **Loading** -- `CircularProgressIndicator` (unchanged).
6. **Empty** -- `Text('--')` (unchanged).

## Movement badges (`flow*`)

Aggregation, per render:

1. `filterDriverHomeDocs(taskDocs, flowSearch, scrName)` — decodes `◼`/`⭘`,
   resolves `{activeVehicle}` / `{today}` / screenTx tokens, AND-filters.
2. `excludeByStatus(filtered, kDefaultExcludeStatus, statusField: 'tst')` —
   `load_rejected` tasks are dropped **unconditionally**. There is no
   `excludeStatus` key on this widget by design.
3. `aggregateItemCirculation(..., dropField: X, actualDropField: X,
   pickupField: Y, actualPickupField: Y)` — passing the same field name as
   both plan and actual makes the sum **actual-only**: `ad`/`ap` never fall
   back to `pd`/`pp`. A present-but-null `ad` (what `toItMap()` writes at task
   creation) resolves to 0.
4. Rows are built by `buildConfirmedRows()` in `driver_home_support.dart`.

### Field-name trap: `dropField` / `pickupField` mean ACTUAL here

**Read this before writing the config.** This widget uses the key names
`dropField` / `pickupField` for the **ACTUAL** movement fields (`ad` / `ap`).
Every other widget in this repo that reads the same `task.it[]` collection uses
those exact key names for the **PLAN** fields, with a *separate* pair for the
actuals:

| widget | `dropField` default | separate actual key? |
|---|---|---|
| `CIRCULATION_SUMMARY` (`circulation_summary.dart`) | `pd` — PLAN | yes, `actualDropField` → `ad` |
| `TASK_FEED_LIST` (`task_feed_list.dart`) | `pd` — PLAN | yes, `actualDropField` → `ad` |
| `ROUTE_FEED_HEADER` (`route_feed_header.dart`) | `pd` — PLAN | yes, `actualDropField` → `ad` |
| **`CUSTODY_CONFIRMED_LIST` (this widget)** | **`ad` — ACTUAL** | **no — there is no `actualDropField` key** |

Consequence: a builder who copies a working block from one of those widgets, or
who simply applies the vocabulary used everywhere else, writes `dropField: pd`
here. The badge then sums the **planned** quantity. A closing reconciliation
screen would read `Antar 20` when only 18 were actually delivered — silently.
No crash, no analyzer warning, no failing test; the number is just wrong, which
is precisely the outcome spec §2 rejects.

**Correct usage: leave both keys unset.** The defaults (`ad` / `ap`) are the
intended values. Only override them to point at a *different actual* pair — for
example the consumable flows `as` (jual) / `ab` (beli). **Never** set them to
`pd` / `pp`.

The key spellings are fixed by the source spec (§4) and are deliberately not
renamed — this note exists because the contract cannot be changed without
breaking it.

Badge rules:

- Hide any badge whose sum is 0. Both zero → no badges at all.
- `ip[]` carries one entry per (item, condition), so an item can occupy two
  rows (isi + kosong). Badges attach to the **first row per `ii`** only;
  later rows keep 0 so the same sum is never read twice.
- Colours are literals — Antar `bg 0xFFFEF3C7 / fg 0xFF92400E`, Ambil
  `bg 0xFFDBEAFE / fg 0xFF1E40AF`. Deliberately **not** `AdminTierColors`,
  whose `warn*` is violet and `danger*` is amber.

Sheet-authoring note: `_2B58_` (`⭘`) is commented out in `autheniumDecode`
(`lib/global.dart`), so the `flowSearch` cell must carry a literal `⭘`, the
same as the existing `search` cell.

### Item grouping (`groupByItem`)

When `groupByItem: TRUE` is set, ip[] entries sharing the same `ii` are merged
into one display row:

- **Qty** = sum of `qt` across all conditions for that item.
- **Condition breakdown** (e.g. `Penuh 0 . Kosong 5`) shown on its own line,
  below the category chip, above the badges.
- **Consumable items** (category matches text slot 2, case-insensitive): the
  condition breakdown is suppressed; only the summed qty and badges show.
  **Text slot 2 must hold the raw `ic` value (e.g. `consumable`), not a display
  label (e.g. `Habis Pakai`).** A display label silently disables D-A
  suppression because the case-insensitive comparison against `ItemDetail.category`
  will not match.
- **Pill count** = number of unique items, not (item, condition) pairs.
- **Badges** attach directly to the single row (no first-row-only dedup
  needed).
- **Category chip fallback** -- when the item JOIN misses (no `ItemDetail`),
  non-grouped mode shows the raw `cd` value in the chip; grouped mode shows
  no chip (blank). This is intentional: in grouped mode the raw `cd` appears
  in the condition breakdown line, so echoing it in the chip would duplicate it.

With `groupByItem` absent or non-truthy, the render is unchanged from round 1.

`condLabels` uses the same `circle`-separated `square`-pairs format as the
`buckets` field (parsed by `parseCondLabels` which delegates to `parseBuckets`).
`autheniumDecode` decodes `_25FC_` (◼) but NOT `_2B58_` (⭘) -- the sheet cell
must carry a literal `⭘`, same constraint as `search` and `flowSearch`.

### Known limitations

An item that was fully dropped and never picked up may have **no `ip[]` row**
at closing, so it has no row to carry a badge. By design (spec §6) the badge
is an additive layer over the existing recount rows; the widget does not
synthesise rows.

The eyebrow pill counts `ip[]` entries in non-grouped mode, i.e.
`(item, condition)` pairs -- so an item with both isi and kosong reads "2 item"
while showing a single badge pair on its first row. In grouped mode
(`groupByItem: TRUE`), the pill counts unique items and this mismatch
disappears. Pre-existing behaviour in non-grouped mode, unchanged by the badge
layer.

## See Also

- `custody_reveal.md` (writes ip[])
- `custody_discrepancy_list.md` (reads dp[])
