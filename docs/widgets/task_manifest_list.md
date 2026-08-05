# TaskManifestList

Per-task accordion list with item-level detail and aggregate drop/pickup badges. Supports two source modes: **collection** (default, Firestore subscription) and **draft** (in-memory wizard draft for Admin P4 review).

- **File:** [lib/widget/task_manifest_list.dart](../../lib/widget/task_manifest_list.dart)
- **Class:** `TaskManifestList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

**Collection mode (default):** Lists all tasks for the current vehicle+today from a Firestore map-collection, showing per-task customer name, address, and aggregate drop/pickup counts from the nested it[] array. Each task row is an accordion: tapping toggles inline item-line detail. First task is expanded by default (seeded once per scrName). Used by driver P5/P10 CustodyNotification and warehouse O1.

**Draft mode (`source:"draft"`):** Renders the in-memory create-task wizard draft as a flat item list inside the manifest card. No Firestore subscription. Reads from `AdminCreateTaskSupport.draftItems[wizardKey]`. Used by admin P4 TaskSummary review screen. Item lines are tx-aware: deliver shows drop/pickup arrows, sale/purchase/refill show their respective quantities with config-driven labels (text slots, Indonesian defaults).

## Component JSON Fields

### Common fields

| Field | Type | Description |
|---|---|---|
| `type` | String | `"task_manifest_list"` |
| `source` | String | `"draft"` for in-memory draft mode; absent/empty/`"collection"` for Firestore mode |
| `itemsField` | String | Items array field (default `it`) |
| `dropField` | String | Drop qty field in it[] (default `pd`) |
| `pickupField` | String | Pickup qty field in it[] (default `pp`) |
| `actualDropField` | String | Actual-drop qty field in it[] (default `ad`). Collection mode only. |
| `actualPickupField` | String | Actual-pickup qty field in it[] (default `ap`). Collection mode only. |
| `actualSaleField` | String | Actual-sale qty field in it[] (default `as`). Collection mode only. |
| `actualBuyField` | String | Actual-buy qty field in it[] (default `ab`). Collection mode only. |
| `actualRefillField` | String | Actual-refill qty field in it[] (default `ar`). Collection mode only. |
| `text` | String | Diamond-separated text slots (see mode-specific tables below) |

### Collection-mode fields

| Field | Type | Description |
|---|---|---|
| `table` | String | `"84214220504259//task"` |
| `search` | String | `"vv◼{vehicleId}⭘tdt◼{today}"` |
| `idField` | String | Task id field (default `tnm`) |
| `titleField` | String | Customer name field (default `kn`) |
| `subtitleField` | String | Address field (default `al`) |
| `route` | String | Task detail route (PARKED) |
| `excludeStatus` | String | Task status to exclude from list/counts (e.g. `"load_rejected"`) |
| `hideQty` | String | `"TRUE"` to suppress drop/pickup pills on task rows (O1) |
| `collapsible` | String | `"TRUE"` to start all tasks collapsed (O1) |

### Draft-mode fields

| Field | Type | Description |
|---|---|---|
| `wizardKey` | String | Draft holder key (default `admin_create_task`). Shared with `task_item_builder`, `task_create_submit`, `task_draft_summary`. |
| `txField` | String | Transaction type field in it[] (e.g. `"tx"`). Enables tx-aware annotations. |
| `saleField` | String | Sale qty field in it[] (e.g. `"ps"`) |
| `buyField` | String | Purchase qty field in it[] (e.g. `"pb"`) |
| `refillField` | String | Refill qty field in it[] (e.g. `"pr"`) |

> The draft-mode tx-aware **labels** (sale/purchase/refill) are config-driven via **text slots** (see below), not component fields. The `*Field` entries above name which it[] key holds each quantity.

### Text slots

**Collection mode (6 slots):**

| Index | Usage | Default |
|-------|-------|---------|
| 0 | Card title | `Task Manifest` |
| 1 | Task count unit | `task` |
| 2 | Item-line count unit | `item line` |
| 3 | Drop pill label | `drop` |
| 4 | Pickup pill label | `pickup` |
| 5 | Hint text | `tap untuk lihat detail` |

**Draft mode (7 slots):**

| Index | Usage | Default |
|-------|-------|---------|
| 0 | Card title | `Item Order` |
| 1 | Item-line count unit | `item line` |
| 2 | Drop annotation label | `drop` |
| 3 | Pickup annotation label | `pickup` |
| 4 | Sale annotation label | `Jual` |
| 5 | Purchase annotation label | `Beli` |
| 6 | Refill annotation label | `Refill` |

> **Trailing-diamond caveat:** `diamondTextToList` keeps trailing empties, so a 4-content-segment text written with a trailing `◆` (e.g. the live `"Item Order◆item line◆drop◆pickup◆"`) parses to **5** elements, the 5th being `""`. Slot 4 (sale label) then resolves to that empty string rather than the `Jual` default; slots 5/6 are out-of-range and fall back to `Beli`/`Refill`. To get the `Jual` default for sale rows, the server should either drop the trailing `◆` or supply slot 4 explicitly.

### Actual-over-plan display (collection mode)

Task row pills and item-line annotations use `resolveItemQty`
(actual-over-plan): if the actual field is present, non-null, and non-empty, it
is displayed; otherwise the plan field is used. Pre-execution items carry
`ad: null` / `ap: null` (from `toItMap()`), so the null check falls back to
plan. Draft mode is unaffected (drafts carry the same null values, which fall
back to plan by the same mechanism).

## Dependencies

- `admin_create_task_support.dart`: `AdminCreateTaskSupport.getDraft`, `draftToItArray`, `DraftItem` (draft mode only)
- `driver_home_support.dart`: `resolveAppVid`, `filterDriverHomeDocs`, `getDriverHomeState`, `aggregateTaskDropPickup`, `TaskAggregate`, `excludeByStatus` (collection mode only)
- `panel_card_support.dart`: `parseTablePath`, `diamondTextToList`
- `table_repository.dart`: `subscribeToMapCollection` (collection mode only)

## Static helpers

| Method | Signature | Description |
|--------|-----------|-------------|
| `clearExpandState` | `static void clearExpandState(String scrName)` | Clear accordion state on route change |
| `buildItemAnnotations` | `static List<String> buildItemAnnotations(Map entry, {...})` | Build per-item annotation strings; tx-aware when `txField` non-empty; sale/buy/refill labels supplied via `saleLabel`/`buyLabel`/`refillLabel` params (all default `''`) |

## See Also

- [task_draft_summary.md](task_draft_summary.md) -- P2 draft preview with tx chips and totals
- [task_feed_list.md](task_feed_list.md) -- P10 daily-route task feed (FLAT/GROUPED modes)
