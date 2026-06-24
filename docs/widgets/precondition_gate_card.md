# PreconditionGateCard

Custody confirmation gate card for DriverHome (P4). Binary state: pending (amber) or confirmed (green).

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
| `vidtable` | String | yes | App VID for Firestore path |
| `itemsTable` | String | no | Table for planned items (e.g. `"<docId>//task"`) |
| `itemsSearch` | String | no | Multi-clause filter for task docs; empty (default) = unscoped. When non-empty, task docs are filtered via `filterDriverHomeDocs` (autheniumDecode + token resolve + AND filter) before aggregation |
| `labelField` | String | no | Field for item label (default `iv`) |
| `qtyField` | String | no | Field for item quantity (default `pq`) |
| `saleField` | String | no | Field for sale qty (default `ps`) |
| `refillField` | String | no | Field for refill/exchange qty (default `pr`) |
| `excludeStatus` | String | no | Task `tst` value to exclude from aggregation (default empty = skip nothing; live: `load_rejected`) |
| `hideZero` | String | no | `"TRUE"` to hide items with zero total qty after aggregation (default empty = show all) |
| `buyField` | String | no | Declared-only: buy qty field (default `pb`); NOT summed into manifest |
| `txField` | String | no | Declared-only: tx discriminator (default `tx`); NOT used in aggregation |
| `route` | String | no | Route for CTA button (e.g. `custodyConfirm`) |
| `text` | String | yes | `◆`-delimited 9 slots |

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

1. `initState` → parse text, subscribe to `vehicle_check` + `task`
2. `build` (Obx) → evaluate gate, publish confirmed state (deferred to a
   `WidgetsBinding.addPostFrameCallback`), render pending/confirmed card
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## See Also

- `RouteProgressHeader` — publishes `(VEHICLEID)` consumed by this widget's search
- `DriverHomeState` (`driver_home_support.dart`) — state propagation
- `OtqTxt` — the state-aware label that reads `DriverHomeState.confirmed`
