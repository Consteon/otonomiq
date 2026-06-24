# CustodyCountSubmit

P6 send-button: writes driver counts (ip[]) natively to Firestore then navigates.

- **File:** [lib/widget/custody_count_submit.dart](../../lib/widget/custody_count_submit.dart)
- **Class:** `CustodyCountSubmit` (StatelessWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Replaces the plain RBT at the bottom of P6 CustodyCount. Reads the reactive
count store from CustodyCountList, computes n/N progress, and enables/disables
accordingly. On tap, builds ip[] from the store, writes it natively to the
opening vehicle_check doc via writeNativeFields (set-merge), then navigates
to custodyReveal.

## Signature / Constructor

| Key | Type | Description |
|---|---|---|
| `table` | `String` | Table path for vehicle_check (for the native write target) |
| `search` | `String` | Multi-clause AND filter for the opening doc |
| `writeField` | `String` | Target field for ip[] (default `ip`) |
| `route` | `String` | Navigation target (custodyReveal page name) |
| `vidtable` | `String` | Tenant VID for appVid resolution |

## Data Dependencies

- **CustodyCountList.countStore** (GetX RxMap, reactive): cross-widget read
- **vehicle_check** (Firestore, write-only): native set-merge of ip[]
- **DriverHomeState.vehicleId** (for token resolution in search)

## See Also

- [custody_count_list.md](custody_count_list.md) -- the stepper list that feeds the count store
- [custody_reveal.md](custody_reveal.md) -- the page navigated to on success
