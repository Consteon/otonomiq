# CustodyStepHeader

Title + plate + STEP badge header for P6 CustodyCount, and vehicleId publisher.

- **File:** [lib/widget/custody_step_header.dart](../../lib/widget/custody_step_header.dart)
- **Class:** `CustodyStepHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

P6 page header that displays the custody confirmation title, vehicle plate,
and a STEP badge (e.g. "STEP 1/2"). Also serves as the vehicleId publisher
for the P6 page (P6 has no route_progress_header). Subscribes stock_location,
derives vehicleId from `lt==vehicle && dv==driverVid`, publishes into
`getDriverHomeState(scrName).vehicleId` via post-frame callback.

## Signature / Constructor

```dart
CustodyStepHeader({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vehicleTable` | `String` | Table path for stock_location (e.g. `84214220504259//stock_location`) |
| `plateField` | `String` | Field on stock_location doc for plate display (default `ln`) |
| `text` | `String` | Diamond-separated: `[0]` title, `[1]` step badge |
| `vidtable` | `String?` | Container VID for the stock_location subscription (applicationTableVid, e.g. `20342033315492`); read first by `resolveAppVid` |

## Data Dependencies

- **stock_location** (subscribed): vehicleId derivation + plate display
- **#has_user_login** (Redux, read-only): driverVid for stock_location filter

## New fields (driver-custody-outcome)

| key | type | required | notes |
|---|---|---|---|
| `workforceTable` | string | no | workforce subcollection path (e.g. `84214220504259//workforce`); if set, subscribes and publishes `driverName` to DriverHomeState |
| `nameField` | string | no | workforce doc field for driver name (default `n`) |

When `workforceTable` is absent or empty, the header behaves identically to
its original implementation: no workforce subscription is created,
`driverName` stays empty in DriverHomeState, and the existing `{vehicleId}`
publish + plate rendering are completely untouched. The workforce driver doc
is matched on `VID == driverVid` (uppercase per spec, lowercase `vid`
fallback -- mirrors route_progress_header._findDriverDoc). Downstream, an empty
`driverName` causes `resolveDriverCurlyTokens` to leave the literal
`{driverName}` token in the DSL string, which writes a degraded but non-fatal
value to the evidence doc's `cn` field.

## See Also

- [route_progress_header.md](route_progress_header.md) -- P4 vehicleId publisher
- [vehicle_custody_header.md](vehicle_custody_header.md) -- P5 vehicleId publisher
