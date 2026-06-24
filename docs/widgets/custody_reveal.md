# CustodyReveal

STEP 2/2: reveal warehouse quantities, compare vs driver counts, branch.

- **File:** [lib/widget/custody_reveal.dart](../../lib/widget/custody_reveal.dart)
- **Class:** `CustodyReveal` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Comparison page. Subscribes vehicle_check for the opening doc, reads
ie[] (warehouse expected) and ip[] (driver actual, written by P6). JOINs the
item table for display names + categories. Groups items by category (with
section dot-headers + per-item category chips), renders per-item comparison as
a status-tinted shared `CustodyStepper` (big centered driver qty + status line,
italic "Warehouse: N" above: green match / violet over / amber under), an
overall callout banner, and computed branch buttons.

The reveal page is now EDITABLE: the driver can adjust counts inline via -/+
on each item. Edits trigger live recomputation of per-item match/selisih
status, overall match/mismatch, callout banner, and branch button labels.
On confirm, `ip[]` is built from the EDITED state and written to Firestore
(set-merge). A seed-once guard prevents Firestore snapshot re-emits from
overwriting in-progress edits.

The edit state lives in a per-scrName static store on `CustodyReveal`,
SEEDED ONCE from the opening doc's `ip[]` (the values P6 wrote). The seed is
gated on `checkDoc != null` so a cold pre-data build cannot poison the store
with an empty seed. The store + seeded flag are cleared on route change via
`clearEditState`, invoked from the `buildPage` clear hook in `ui_component.dart`.

## Static API

| Member | Description |
|---|---|
| `CustodyReveal.getEditMap(scrName)` | Get or create the editable count map for a screen |
| `CustodyReveal.clearEditState(scrName)` | Clear edit state + seeded flag on route change |

## Confirm write

A single native set-merge (`writeNativeFields`) bundles the fields:

- **Match:** `{writeField: ip[], reconcileField: 'matched'}`
- **Mismatch:** `{writeField: ip[], discrepancyField: dp[], reconcileField: 'discrepancy_detected'}`

`writeField` (default `ip`) carries the EDITED driver counts and OVERWRITES the
P6 blind count. `dp[]` is computed from `ie[]` vs the edited state (only items
with a non-zero delta).

## Signature / Constructor

| Key | Type | Description |
|---|---|---|
| `table` | `String` | Table path for vehicle_check |
| `search` | `String` | Multi-clause AND filter for the opening doc |
| `expectedField` | `String` | Field on doc for warehouse array (default `ie`) |
| `actualField` | `String` | Field on doc for driver array (default `ip`) |
| `joinTable` | `String` | Table path for item collection |
| `joinKey` | `String` | JOIN key field (default `ii`) |
| `labelField` | `String` | Item name field (default `in`) |
| `categoryField` | `String` | Item category field (default `ic`) |
| `writeField` | `String` | Target field for the edited ip[] write (default `ip`) |
| `discrepancyField` | `String` | Target field for dp[] write (default `dp`) |
| `reconcileField` | `String` | Target field for rs write (default `rs`) |
| `matchRoute` | `String` | Nav target on match (P7) |
| `mismatchRoute` | `String` | Nav target on mismatch (P8) |
| `recountRoute` | `String` | Nav target for recount (P6) |
| `text` | `String` | 9-slot diamond-separated labels |
| `vidtable` | `String` | Tenant VID for appVid resolution |

## Data Dependencies

- **vehicle_check** (subscribed): opening doc with ie[] + ip[]
- **item** (subscribed): name + category JOIN
- **DriverHomeState.vehicleId** (reactive): search token resolution

## See Also

- [custody_count_submit.md](custody_count_submit.md) -- P6 button that writes ip[] and navigates here
- [custody_step_header.md](custody_step_header.md) -- header shared between P6 and this page
