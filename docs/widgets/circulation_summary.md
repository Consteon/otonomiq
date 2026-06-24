# CirculationSummary

Per-item cross-route circulation totals (Muat/Drop/Pickup) for the P5 CustodyNotification page.

- **File:** [lib/widget/circulation_summary.dart](../../lib/widget/circulation_summary.dart)
- **Class:** `CirculationSummary` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Groups all tasks' it[] entries by item name and sums planned_drop and planned_pickup per distinct item. Displays a columnar table with Muat (== Drop), Drop, and Pickup values per item, plus grand-total footer and italic note.

Column headers "Item"/"↓Drop"/"↑Pick" are intentionally hardcoded (not server-overridable); only the "Muat" column header comes from text slot 1. Slots 2/3 are footer labels.

## Component JSON Fields

| Field | Type | Description |
|---|---|---|
| `type` | String | `"circulation_summary"` |
| `table` | String | `"84214220504259//task"` |
| `search` | String | `"vv◼{vehicleId}⭘tdt◼{today}"` |
| `itemsField` | String | Items array field (default `it`) |
| `dropField` | String | Drop qty field in it[] (default `pd`) |
| `pickupField` | String | Pickup qty field in it[] (default `pp`) |
| `text` | String | 5-slot diamond: title, muat label, drop footer label, pickup footer label, italic note |
| `excludeStatus` | String | Task status to exclude from totals (e.g. `"load_rejected"`). Empty/absent = no exclusion. |

## Dependencies

- `driver_home_support.dart`: `resolveAppVid`, `filterDriverHomeDocs`, `getDriverHomeState`, `aggregateItemCirculation`, `CirculationResult`, `ItemCirculation`, `excludeByStatus`
- `panel_card_support.dart`: `parseTablePath`, `diamondTextToList`
- `table_repository.dart`: `subscribeToMapCollection`
