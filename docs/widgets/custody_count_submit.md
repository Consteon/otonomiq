# CustodyCountSubmit

P6 send-button: writes driver counts (ip[]) natively to Firestore then navigates.

- **File:** [lib/widget/custody_count_submit.dart](../../lib/widget/custody_count_submit.dart)
- **Class:** `CustodyCountSubmit` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Replaces the plain RBT at the bottom of P6 CustodyCount. Reads the reactive
count store from CustodyCountList, computes n/N progress, and enables/disables
accordingly. On tap, builds ip[] from the store, writes it natively to the
opening vehicle_check doc via writeNativeFields (set-merge), then navigates
to custodyReveal.

The widget has three code paths selected by `mode`:

- **P6 (default, `mode != opening|closing`)**: driver custody count -> ip[]
  native write -> nav to custodyReveal (behavior described above).
- **O1 (`mode == opening`)**: warehouse opening check. Creates the opening
  vehicle_check doc (scalars + ie[]) via an auto-id native write, designates
  the chosen driver (dv/dn on stock_location) via updateEventRow, then
  navigates by chain/route.
- **C1 (`mode == closing`)**: warehouse closing check. Creates the closing
  vehicle_check doc (ip[] + dp[] + rs), closes the matching opening doc
  (cst -> closed via field search), optionally creates an investigation doc
  on discrepancy, then navigates by reconciliation result (matchRoute /
  mismatchRoute).

**saveSend plug (Phase A):** When the component sets `action: "savesend"`,
O1 and C1 also run the saveSend pipeline after the native write -- preserving
`addToEvent` so an Event audit row (evidence) is queued, and capturing GPS
when `gpsPosition > 0`. When `action` is absent the widget is byte-identical
to the pre-plug behavior (O1 strips addToEvent; C1 skips the audit; GPS is
time-only). The P6 path is unaffected by these fields.

## Signature / Constructor

| Key | Type | Description |
|---|---|---|
| `table` | `String` | Table path for vehicle_check (for the native write target) |
| `search` | `String` | Multi-clause AND filter for the opening doc |
| `writeField` | `String` | Target field for ip[] (default `ip`) |
| `route` | `String` | Navigation target (custodyReveal page name) |
| `vidtable` | `String` | Tenant VID for appVid resolution |
| `action` | `String?` | When `"savesend"`: run saveSend pipeline (Event + GPS) after native write. Absent = no saveSend (byte-identical legacy). |
| `gpsPosition` | `int?` | GPS capture mode. `> 0` = real GPS via setAllDataAsync. `0` or absent = dummy. |
| `flag` | `String?` | Event tag for the saveSend pipeline (e.g. `"warehouse-opening-check"`). |
| `addToEvent` | `String?` | DSL string for the Event audit row. Resolved at compose time ({checkerName}), then at sync time (system/form placeholders). |
| `matchRoute` | `String?` | C1: navigation target when reconciliation `rs` = `matched`. |
| `mismatchRoute` | `String?` | C1: navigation target when `rs` = `discrepancy_detected`. |

## Data Dependencies

- **CustodyCountList.countStore** (GetX RxMap, reactive): cross-widget read
- **vehicle_check** (Firestore, write-only): native set-merge of ip[]
- **DriverHomeState.vehicleId** (for token resolution in search)

## See Also

- [custody_count_list.md](custody_count_list.md) -- the stepper list that feeds the count store
- [custody_reveal.md](custody_reveal.md) -- the page navigated to on success
