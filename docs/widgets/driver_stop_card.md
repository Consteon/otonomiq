# DriverStopCard

Stop list + progress card for DriverHome (P4). Dual-mode: locked preview (pending) or active list with progress bar (confirmed).

- **File:** [lib/widget/driver_stop_card.dart](../../lib/widget/driver_stop_card.dart)
- **Class:** `DriverStopCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Renders the driver's today-route as a stop list. In pending mode, shows a
locked preview with numbered stops (not tappable). In confirmed mode, shows
a progress bar, per-stop status badges (SELESAI/GAGAL/LANJUT/KIRIM/AMBIL),
active-row highlight, and a CTA to the taskFeed screen.

Uses `computeStopProgress` from `driver_home_support.dart` for the
tst-to-status mapping and closed/total/allClosed computation.

> **Trip sequence:** the `{activeTrip}` token (newest non-closed `vehicle_check` opening doc-id) is available for the `search` config — e.g. `tr◼{activeTrip}` scopes stops to the current trip. Unresolved (no active opening) it stays literal and fails closed.

When `rejectRoute` is set, the locked preview gains per-row "Tolak" buttons
(amber outline) for non-completed stops, a "Selesai" chip for completed ones,
and a footnote at card bottom. Tapping Tolak dispatches `#REJECT_TASK` and
navigates to the reject sheet.

When `excludeStatus` is set, tasks whose raw `tst` field matches are dropped
from both the rendered list and the "N tujuan" count. It defaults to
`load_rejected` (via `kDefaultExcludeStatus`): an absent or empty
`excludeStatus` triggers that default, so `load_rejected` tasks are excluded
unless a tenant explicitly overrides the field. This keeps the stop-card
progress in sync with NAV_ACTION_CARD's `allClosed`.

### Maps button

When `mapsUrl` is set, every stop row in BOTH modes -- `done` rows included --
gains a "Lihat Lokasi" button under the address.

**Label source, in order:** `mapsUrl`'s `label◼` key → `text` slot **20**
(legacy) → the hardcoded default `📍 Lihat Lokasi`.

> **Use `label◼`. The `text` slot is legacy.** It stays only so tenants that
> already migrated their `text` keep working. Appending a `◆` segment is a
> hand-counted edit with a silent failure mode — this widget's reject footnote
> was destroyed exactly that way (see the note below). `label◼` is a
> named key in a DSL this field already parses, so nothing has to be counted.

Template choice: try `url`; if any `<token>` in it is empty / absent /
whitespace-only, try `fallback`; if that also fails the button is greyed out and
the `empty` message is printed beneath it. The emptiness test is generic -- no
field name is hardcoded in Dart, so a tenant can point the templates at any
task-doc fields. Values are URL-encoded on substitution; separators that are
literal text in the template (the comma in `<la>,<lo>`) are not.

Tapping opens the URL with `LaunchMode.externalApplication` -- the Google Maps
app when installed, the browser otherwise. Never an in-app webview: the driver
needs real turn-by-turn navigation.

In locked mode the button is the partner of `Tolak`: look at the map, then
decide whether to reject. They render on ONE line under the address — maps left,
`Tolak` right — because they are one decision, and a `📍` on the far left with
`Tolak` at the top right reads as two unrelated controls. A `done` stop keeps
its green `Selesai` chip in the trailing position and the maps button sits
alone.

`Lihat Lokasi` is a **filled tint** (indigo-50 on indigo-700, 7.07:1) and
`Tolak` stays an **outline**: one is safe, the other sends the task back to
Admin, and the heavier control should be the harmless one. A disabled maps
button is a gray-600 outline plus the `empty` message — never hidden.

The address renders up to **2 lines**. Since the map became the only address
source, every new customer's address is a full reverse-geocode string ending in
`…, Banten, 15345, Indonesia`; one line was never going to be enough.

> ### Do NOT append a `text` segment for the maps label
>
> **One recommendation, no alternative: put the caption in `mapsUrl`'s
> `label◼` key.** Slot **20** is still read, but only so that tenants who
> appended it before `label◼` existed keep working. It is **not** a migration
> path, and no new `◆` segment should ever be added to `text` for this
> feature. A config shorter than 21 segments is not "unmigrated": both the
> label and the reject footnote fall back to their hardcoded defaults, so it
> renders exactly as intended.
>
> The slot is closed rather than merely discouraged because appending is a
> hand-counted edit against an **absolute** index, and every count has its own
> silent failure mode. On a 20-segment `text` the label has to land at index 20
> (one append). On a 19-segment one it takes two -- the footnote at 19, the
> label at 20 -- and appending only one puts the label in the *footnote* slot:
> the footnote then prints `📍 Lihat Lokasi` while the button falls back to an
> identical hardcoded default and **looks correct**. That is exactly the live
> damage recorded below. With `label◼` there is no count to get wrong.
>
> Repairing an already-damaged `text` (restoring an overwritten segment in
> place) is a different operation and is still correct -- see the ⚠ block.

> ### ⚠ Known config damage — `op1Screen!S547`, segment 19
>
> The live DriverHome `DRIVER_STOP_CARD` (`op1Screen` row 547) currently has
> **20** segments whose `[19]` is `📍 Lihat Lokasi`. It should be the reject
> footnote — that segment was **overwritten** instead of appended past.
> `docs/driver_runtime/custody-mode-toggle-op1screen.md:68` records the correct
> shape for the sibling page: `[19]` = *"Ada stop nggak searah? Tolak sebelum
> terima muatan, biar dikembalikan ke Admin."*
>
> **Symptom on the device:** the footnote line under the stop list prints
> `📍 Lihat Lokasi`, while the button itself falls through to its identical
> hardcoded default and therefore *looks* correct. **Verify at the footnote,
> not at the button.**
>
> **Fix (builder):** restore segment 19 to the footnote text and move the label
> to `mapsUrl`'s `label◼` key — do **not** append a 21st segment. The renderer
> cannot repair this; it is config damage.

## Signature / Constructor

```dart
DriverStopCard({
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
| `type` | String | yes | `"DRIVER_STOP_CARD"` |
| `variant` | String | no | `"preview"` |
| `table` | String | yes | `"<docId>//task"` |
| `search` | String | yes | `"vv◼(VEHICLEID)⭘tdt◼(TODAY)"` |
| `vidtable` | String | yes | App VID for Firestore path |
| `navState` | String | no | Forward-compat metadata (e.g. `"assigned"`) |
| `route` | String | no | Route for CTA button (e.g. `taskFeed`) |
| `rejectRoute` | String | no | Route for reject-task sheet (e.g. `rejectTask`). When absent, Tolak buttons are hidden (backward compat). |
| `taskIdField` | String | no | Field on task row for reject VID (default `tnm`) |
| `excludeStatus` | String | no | Raw `tst` value to exclude from list + count (e.g. `"load_rejected"`). Default: `load_rejected` (via `kDefaultExcludeStatus`). Empty string from server JSON triggers the default, not "no exclusion". Compares raw tst, NOT stopStatusOf. Mirrors PRECONDITION_GATE_CARD excludeStatus. |
| `mapsUrl` | String | no | Keyed DSL `url◼<template>⭘fallback◼<template>⭘empty◼<message>⭘label◼<button text>`. `url` required, the other three optional. `<field>` tokens are task-doc fields, URL-encoded on substitution. When absent, no maps button is rendered anywhere and the locked row keeps `Tolak` pinned top-right (backward compat). See "Maps button" below. |
| `text` | String | yes | diamond-delimited 21 slots (18 original + 2 reject + 1 maps) |

## Stop status mapping (SINGLE source: `driver_home_support.dart`)

| `tst` value | Display | Badge color | Closed? |
|---|---|---|---|
| `done` | SELESAI | green | yes |
| `failed` | GAGAL | amber | yes |
| `active` | LANJUT | indigo | no |
| other/absent | KIRIM/AMBIL | gray | no |

## Lifecycle

1. `initState` -> parse text, subscribe to task mapCollection
2. `build` (Obx) -> gate check, filter stops, compute progress, render mode
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## See Also

- `NavActionCard` -- reads the same `allClosed` from `computeStopProgress`
- `PreconditionGateCard` -- publishes `confirmed` state
- `DriverHomeState` (`driver_home_support.dart`) -- shared state holder
