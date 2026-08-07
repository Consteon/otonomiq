# PreconditionGateCard

Custody confirmation gate card for DriverHome (P4). Four states: hidden (no opening doc today), pending (amber), confirmed (green), confirmed-with-discrepancy (green + amber warn sub-bar).

- **File:** [lib/widget/precondition_gate_card.dart](../../lib/widget/precondition_gate_card.dart)
- **Class:** `PreconditionGateCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

THE page-state source. Evaluates a multi-clause AND gate search against
`vehicle_check` to determine pending/confirmed. Publishes the result into
`DriverHomeState.confirmed` for the TXT label and Phase 2 gated widgets.

## Signature / Constructor

```dart
PreconditionGateCard({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

## `component` shape

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | String | yes | `"PRECONDITION_GATE_CARD"` |
| `table` | String | yes | `"<docId>//vehicle_check"` |
| `search` | String | yes | Multi-clause: `"cty◼opening⭘vv◼(VEHICLEID)⭘cdt◼(TODAY)"` |
| `gateTable` | String | no | Existence-gate table path (e.g. `"84214220504259//vehicle_check"`). Separate from `table` (status gate). When present, subscribes for date-scoped hide/show via `gateSearch`. |
| `gateSearch` | String | no | Multi-clause AND filter for existence gate (e.g. `"cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}"`). Intentionally omits `cst` — checks existence only, not status. Empty (default) = no gate = card always renders. |
| `vidtable` | String | yes | App VID for Firestore path |
| `itemsTable` | String | no | Table for planned items (e.g. `"<docId>//task"`) |
| `itemsSearch` | String | no | Multi-clause filter for task docs; empty (default) = unscoped. When non-empty, task docs are filtered via `filterDriverHomeDocs` (autheniumDecode + token resolve + AND filter) before aggregation |
| `itemsField` | String | no | Source field for manifest items. `"ie"` = read from vehicle_check opening doc `ie[]` (spec section 9). Default `"it"` = legacy task.it[] aggregation (spec sections 1-3). |
| `labelField` | String | no | Field for item label (default `iv`) |
| `qtyField` | String | no | Field for item quantity (default `pq`) |
| `saleField` | String | no | Field for sale qty (default `ps`) |
| `refillField` | String | no | Field for refill/exchange qty (default `pr`) |
| `excludeStatus` | String | no | Task `tst` value to exclude from aggregation (default empty = skip nothing; live: `load_rejected`) |
| `hideZero` | String | no | `"TRUE"` to hide items with zero total qty after aggregation (default empty = show all) |
| `buyField` | String | no | Declared-only: buy qty field (default `pb`); NOT summed into manifest |
| `txField` | String | no | Declared-only: tx discriminator (default `tx`); NOT used in aggregation |
| `dpField` | String | no | Field for discrepancy array on the gate doc (default `dp`). Non-empty list triggers state-4 warn sub-bar. |
| `route` | String | no | Route for CTA button (e.g. `custodyConfirm`) |
| `text` | String | yes | `◆`-delimited 9 slots (0–8). Slots 7+8 feed the state-4 selisih sub-bar. |

## Multi-clause AND gate

The `search` string is decoded (`autheniumDecode`), then `(TOKEN)` and `{curly}`
tokens are resolved, then split on `⭘` (AND separator) into `field◼value`
clauses. A `vehicle_check` doc must match ALL clauses to confirm. If any clause
still holds an unresolved `(...)`/`{...}` token (e.g. `(VEHICLEID)` before the
header publishes it), the filter returns empty — the safe **pending** default.

The planned-item list (`itemsTable`, shown only in the pending card) is filtered
the same way via `itemsSearch` (vehicle AND today), so foreign/stale items never
appear before the header resolves the vehicle.

## Warehouse name (`<2>`)

The `<2>` token in slot 2 currently renders the **static** label `Gudang Pusat`
(single-warehouse assumption). A dynamic warehouse source is a future TODO
(noted in the widget code).

## TXT label state-switch dependency (W2)

The state-aware TXT label on the same screen reacts to `DriverHomeState.confirmed`
that THIS card publishes. For the swap to work, the op1Screen DriverHome label
component (row 1010) MUST carry `"stateSwitch":"HARI INI"` in its JSON. With that
field, the label shows `data` ("SEBELUM BERANGKAT") while pending and swaps to
`HARI INI` once this card confirms. **Without the `stateSwitch` field the label
silently never switches — by design** (zero impact on the thousands of other TXT
components, which lack the field). See `OtqTxt.build()`.

## Lifecycle

1. `initState` → parse text, subscribe to `vehicle_check` + `task` + existence gate table
2. `build` (Obx) → evaluate existence gate (hide if no doc today), then evaluate
   status gate, publish confirmed state (deferred via `_publishConfirmed`),
   render pending/confirmed card
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## Item source: ie[] vs task.it[] (spec section 9)

The pending card's item list is **config-gated** by `itemsField`:

### ie[] path (itemsField: "ie")

Reads the `ie[]` array from the vehicle_check **opening** doc (the same doc
the existence gate finds via `gateSearch`). Each entry is `{ii, cd, qt}`.
Quantities are summed per `ii` across all `cd` values (full + empty = total
per item). Item names are resolved via the item collection FK (`itemTable`).
Zero-qty rows are dropped when `hideZero:"TRUE"`.

The opening doc is found by `_matchedOpeningDoc()`, which filters
`mapTableContent[_existGateCode]` by `gateSearch` (existence gate search,
NOT status `search`). This means the ie[] is available in PENDING state
(before custody confirmation).

Config:
```json
"itemsField":"ie", "qtyField":"qt", "labelField":"in"
```

Fields NOT read in ie[] mode: `txField`, `saleField`, `refillField`,
`buyField`, `excludeStatus`, `itemsSearch`, `itemsTable`.

### task.it[] path (itemsField: "it", default)

Legacy path. Reads task docs from `itemsTable`, filters by `itemsSearch`,
aggregates `pd+ps+pr` per item name, excludes by `excludeStatus`, hides
zero-qty rows. Unchanged from the original implementation.

## State-4: Selisih sub-bar (spec section 10)

When the confirmed gate doc (`_matchedGateDoc()`) carries a non-empty `dp[]`
array, the green confirmed card renders an additional amber warn sub-bar
below the confirmed line. The sub-bar uses text slots 7 and 8.

### Detection

`hasLoadDiscrepancy(gateDoc[dpField])` (driver_home_support.dart) -- returns
`true` iff the value is a non-empty `List`. Entry contents ({ac, ex, dl})
are not inspected.

### Visual

The green Container's child is a `Column`:
1. The confirmed `Row` (check_circle + label + summary) -- always rendered
   (identical in states 3 and 4).
2. Conditionally: `SizedBox(height:12)` + an amber sub-bar `Container`
   (amber-50 bg, amber-300 border, radius 10, padding 12) holding a `Row`
   of `Icon(warning_amber_rounded, amber-600)` + `SizedBox(w:8)` +
   `Expanded(Column[slot 7 bold amber-800 14sp, SizedBox(h:2), slot 8
   caption amber-700 12.5sp])`.

### Backward-compat

- `dpField` absent/empty -> default `'dp'`.
- `dp[]` absent/null/empty/non-List -> no sub-bar (state 3).
- Text slots 7+8 absent (lean tenant) -> hardcoded defaults render.

## Mode toggle: count vs ack (custody-mode-toggle)

Two config keys select which route the CTA opens, resolved by the static
`PreconditionGateCard.resolveCtaRoute(component)`:

| Key | Effect |
|---|---|
| `custodyMode` | `"ack"` (case-insensitive, trimmed) selects Mode B. Absent or `"count"` = Mode A. |
| `ackRoute` | Route opened in Mode B. Ignored in Mode A. |

| Mode | CTA opens | `text` slot [3] | Driver flow |
|---|---|---|---|
| A (default) | `route` | `Konfirmasi Penerimaan` | CustodyNotif -> Count -> Reveal -> Success |
| B (ack) | `ackRoute` | `Terima & Berangkat` | Ack page (manifest + reject + photo + 1-tap) |

Backward-compat: a tenant that never sets `custodyMode` reads `route` exactly as
before. `custodyMode:"ack"` with an empty/missing `ackRoute` falls back to `route`
rather than dead-ending the button.

The **CTA label is not** part of the toggle — it is `text` slot [3], flipped in the
sheet alongside the mode. The button always appends ` →` (hardcoded at
`precondition_gate_card.dart:586`).

See `docs/driver_runtime/custody-mode-toggle-op1screen.md` for the ack page rows.
Covered by `test/precondition_gate_card_route_test.dart`.

The gate logic, items display, existence-gate, confirmed/pending state,
and selisih sub-bar are all mode-independent — identical behavior in A and B.

## See Also

- `RouteProgressHeader` — publishes `(VEHICLEID)` consumed by this widget's search
- `DriverHomeState` (`driver_home_support.dart`) — state propagation
- `OtqTxt` — the state-aware label that reads `DriverHomeState.confirmed`
