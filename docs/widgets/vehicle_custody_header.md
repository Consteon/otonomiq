# VehicleCustodyHeader

Vehicle custody card and **vehicleId publisher** for the P5 CustodyNotification page.

- **File:** [lib/widget/vehicle_custody_header.dart](../../lib/widget/vehicle_custody_header.dart)
- **Class:** `VehicleCustodyHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

**STATEFUL PUBLISHER of vehicleId.** P5 has no route_progress_header, so this widget fills the vehicleId publisher role, mirroring route_progress_header._findVehicleDoc (rph:124-138) and _publishVehicleId (rph:145-158).

It finds the stock_location vehicle doc by `lt=='vehicle' && dv==driverVid` (driverVid from `#has_user_login`), reads `lv` (vehicleId) and `ln` (plate) from the same doc, and publishes `lv` into `getDriverHomeState(scrName).vehicleId` via a post-frame callback. All other P5 widgets (taskManifestList, circulationSummary) depend on this publish for their `{vehicleId}` search token resolution.

Also reads the `vehicle_check` opening doc to display:
- Vehicle plate (from stock_location `ln`, via the vehicle doc)
- Custody event id (`cnm`)
- Dimuat oleh (`gn`) -- FUTURE field, shows em-dash when absent
- Waktu loading (`ldt`) -- FUTURE field, shows em-dash when absent

## Component JSON Fields

| Field | Type | Description |
|---|---|---|
| `type` | String | `"vehicle_custody_header"` |
| `table` | String | `"84214220504259//vehicle_check"` |
| `search` | String | `"cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}"` |
| `vehicleTable` | String | `"84214220504259//stock_location"` |
| `vehicleSearch` | String | **Unused/legacy.** The join is by `lt=='vehicle' && dv==driverVid`, not by this field. May still arrive in JSON; the widget ignores it. |
| `plateField` | String | Field code for plate (default `ln`) |
| `eventField` | String | Field code for event id (default `cnm`) |
| `loaderField` | String | Field code for loader name (default `gn`) |
| `loadtimeField` | String | Field code for load datetime (default `ldt`) |
| `text` | String | 4-slot diamond: title (unused on icon row), loader label, loadtime label, event label |

## Dependencies

- `driver_home_support.dart`: `resolveAppVid`, `filterDriverHomeDocs`, `getDriverHomeState`, `DriverHomeState`
- `panel_card_support.dart`: `parseTablePath`, `diamondTextToList`
- `table_repository.dart`: `subscribeToMapCollection`
- `screen_transaction.dart`: `transactionStore` (for `#has_user_login` in _findVehicleDoc)

## See Also

- [route_progress_header.md](route_progress_header.md) -- P4 vehicleId publisher (same _findVehicleDoc / _publishVehicleId pattern)
