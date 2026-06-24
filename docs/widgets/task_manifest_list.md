# TaskManifestList

Per-task accordion list with item-level detail and aggregate drop/pickup badges for the P5 CustodyNotification page.

- **File:** [lib/widget/task_manifest_list.dart](../../lib/widget/task_manifest_list.dart)
- **Class:** `TaskManifestList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Lists all tasks for the current vehicle+today, showing per-task customer name, address, and aggregate drop/pickup counts from the nested it[] array. Each task row is an accordion: tapping toggles inline item-line detail. First task is expanded by default (seeded once per scrName). The taskDetail route is parked (unbuilt).

## Component JSON Fields

| Field | Type | Description |
|---|---|---|
| `type` | String | `"task_manifest_list"` |
| `table` | String | `"84214220504259//task"` |
| `search` | String | `"vv◼{vehicleId}⭘tdt◼{today}"` |
| `idField` | String | Task id field (default `tnm`) |
| `titleField` | String | Customer name field (default `kn`) |
| `subtitleField` | String | Address field (default `al`) |
| `itemsField` | String | Items array field (default `it`) |
| `dropField` | String | Drop qty field in it[] (default `pd`) |
| `pickupField` | String | Pickup qty field in it[] (default `pp`) |
| `route` | String | Task detail route (PARKED) |
| `text` | String | 6-slot diamond: title, task unit, item-line unit, drop label, pickup label, hint |
| `excludeStatus` | String | Task status to exclude from list/counts (e.g. `"load_rejected"`). Empty/absent = no exclusion. |

## Dependencies

- `driver_home_support.dart`: `resolveAppVid`, `filterDriverHomeDocs`, `getDriverHomeState`, `aggregateTaskDropPickup`, `TaskAggregate`, `excludeByStatus`
- `panel_card_support.dart`: `parseTablePath`, `diamondTextToList`
- `table_repository.dart`: `subscribeToMapCollection`
