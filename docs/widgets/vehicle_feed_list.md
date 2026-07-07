# VehicleFeedList

Tier-grouped vehicle card list for the H1 Warehouse Vehicle Feed with
per-state styling and action buttons (opening/closing check navigation).

- **File:** [lib/widget/vehicle_feed_list.dart](../../lib/widget/vehicle_feed_list.dart)
- **Class:** `VehicleFeedList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Reads stock_location (vehicles), vehicle_check (opening/closing docs), and
task (route state) to derive each vehicle's tier (loading / custody_pending /
in_route / returning / completed). Groups into 4 sections with per-tier card
styling and action buttons.

> **Trip sequence:** tier derivation anchors to the NEWEST opening per vehicle (sort by `t` desc, non-closed preferred) and scopes the task rollup by trip — but ONLY when that opening is non-closed (an active trip): scope = tasks with `tr == opening __docId` OR `tr` empty (unstamped = admin-created / not yet executed, they belong to the active trip). When every opening is closed (between trips) there is NO trip scope — all (vv, today) tasks roll up, so tasks created for the next trip stay visible on the card. Fallback to (vv, today) also applies when no task matches the active trip (pre-CF data). The `completed` tier is no longer emitted — a closed vehicle returns to the `loading` backlog once `dv`/`dn` are cleared.

## Signature / Constructor

Same 7-param SDUI pattern.

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | Firestore container VID |
| `table` | `String` | `docId//stock_location` |
| `search` | `String` | Stock_location filter |
| `plateField` | `String` | Plate field name (default `ln`) |
| `executorField` | `String` | Driver VID field (default `dv`) |
| `executorNameField` | `String` | Driver name field (default `dn`) |
| `openingGate` | `String` | Vehicle_check gate (e.g. `docId//vehicle_check⭘cty◼opening⭘vv◼{lv}`) |
| `cstField` | `String` | Custody status field (default `cst`) |
| `closingGate` | `String` | Closing gate string |
| `taskTable` | `String` | `docId//task` |
| `taskSearch` | `String` | Task filter (e.g. `vv◼{lv}⭘tdt◼{today}`) |
| `taskStateField` | `String` | Task state field (default `tst`) |
| `itemsField` | `String` | Items array field on task (default `it`) |
| `openingRoute` | `String` | Route for opening check (O1) |
| `closingRoute` | `String` | Route for closing check (C1) |
| `text` | `String` | Diamond-separated labels (7 slots) |

## Important Behavior

- Tier derivation is in-memory over subscribed collections (no N+1 queries).
- `{lv}` in gate/task search is NOT a curly-token resolver case; it is
  replaced per-row inline by `buildVehicleFeed`.
- Completed tier is date-scoped to today (`cdt == {today}`); older trips
  drop from the feed.
- Loading tier has NO date filter (backlog persists).
- Section headers render the uppercased label only (amber dot for Perlu
  Tindakan); the per-section count lives in the header's snapshot boxes, not
  the section header.
- The item-category map is derived from the `{docId}/item` subcollection of
  the same stock_location container (NOT a separate `vidtable`). The category
  summary ("N returnable · M consumable") falls back to NO summary line when
  no item category resolves. **On-device QA:** verify the derived
  `{docId}/item` path actually resolves item `ic` categories on the live
  tenant.
- **Summary status scope:** The category summary counts items ONLY from tasks
  with raw `tst == 'assigned'` (the `kLoadableStatus` constant in
  `vehicle_feed_support.dart`). Completed, failed, and load_rejected tasks are
  excluded from the summary. Tier derivation and stop-progress are NOT affected
  -- they receive the full task set. See `warehouse-feed-summary-status` plan.
- Card tap writes `#ACTIVE_VEHICLE` (tapped `lv`) then routes to
  `openingRoute` (loading) / `closingRoute` (returning) via
  `routeStack.push` before `gotoRoute`. Dead/empty route = silent no-op.

## See Also

- [vehicle_feed_header.md](vehicle_feed_header.md) -- companion header widget
- [task_feed_list.md](task_feed_list.md) -- driver P10 analog
