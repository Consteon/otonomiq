# VehicleFeedHeader

Sticky header for the H1 Warehouse Vehicle Feed: checker identity (workforce
lookup) + station subtitle + menu icon + 3 snapshot count boxes.

- **File:** [lib/widget/vehicle_feed_header.dart](../../lib/widget/vehicle_feed_header.dart)
- **Class:** `VehicleFeedHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Renders the checker's identity and provides at-a-glance snapshot counts for
the vehicle feed (Perlu Tindakan / Opening Check / Hari Ini). Subscribes the
same Firestore collections as VehicleFeedList; each widget computes counts
independently.

## Signature / Constructor

Same 7-param SDUI pattern as all driver/warehouse widgets (key, component,
scrName, lPad/tPad/rPad/bPad).

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | Firestore container VID |
| `workforceTable` | `String` | `docId//workforce` |
| `checkerSearch` | `String` | `VID◼{checkerVid}` |
| `nameField` | `String` | Workforce doc field for name (default `n`) |
| `station` | `String` | Static station label |
| `menuRoute` | `String` | Route for menu icon tap (empty = icon hidden) |
| `table` | `String` | `docId//stock_location` (for feed row subscription) |
| `search` | `String` | Stock_location filter (e.g. `lt◼vehicle⭘lst◼active`) |
| `openingGate` | `String` | Vehicle_check subscription gate |
| `taskTable` | `String` | `docId//task` |
| `text` | `String` | Diamond-separated labels (4 slots) |

## Important Behavior

- `checkerSearch` is **vestigial for H1**: the header resolves the checker by
  looping the subscribed `workforce` collection directly against
  `screenTx['#VID']` (`_findCheckerDoc`), it does NOT run `checkerSearch`
  through `filterDriverHomeDocs`. The `{checkerVid}` curly-token resolver case
  is retained for forward O1/C1 use (those pages scope their vehicle_check
  subscription by `{checkerVid}`).

## See Also

- [vehicle_feed_list.md](vehicle_feed_list.md) -- companion list widget
- [route_feed_header.md](route_feed_header.md) -- driver P10 analog
