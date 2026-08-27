# FtzRowOfButton2

Row of action buttons, version 2 — renders a horizontal row of configurable buttons (save, navigate, update remote tables, run chained actions) for a screen.

- **File:** [lib/widget/ftz_row_of_button_2.dart](../../lib/widget/ftz_row_of_button_2.dart)
- **Class:** `FtzRowOfButton2` (StatefulWidget, with `AutomaticKeepAliveClientMixin`)
- **Status:** draft
- **Widget version:** v2
- **Previous version:** [FtzRowOfButton](ftz_row_of_button.md) (`lib/widget/ftz_row_of_button.dart`)

## Purpose

`FtzRowOfButton2` is the action bar for v2 screens. Each child entry in `component['children']` becomes a button with its own per-button config (route, table update, chained actions, GPS gating, etc.). It coordinates the wait-screen timer, dispatches `ScreenTransaction` updates, and triggers the `do_chain` flow when a button has a chain definition.

## Signature / Constructor

```dart
const FtzRowOfButton2({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
  bool? dialog,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config; `children` array drives button generation. |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `lPad` / `tPad` / `rPad` / `bPad` | `double` | yes | — | Outer padding on left/top/right/bottom |
| `dialog` | `bool?` | no | `null` | Set when the row is rendered inside a dialog so post-action navigation can pop the dialog instead of the current route. |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `children` | `List<Map>` | List of button definitions. See per-child shape below. |

### Per-child shape (`component['children'][i]`)

| Key | Type | Description |
|---|---|---|
| `position` | `int?` | Slot in `txfController[scrName]`; controls the per-button enabled state. |
| `isEnabled` | `String/bool?` | Initial enabled state. Anything other than `'false'` is treated as enabled. |
| `com` | `String?` | Command/identifier resolved into `tableVid` via `getTableVid(...)`. |
| `route` | `String?` | Route to navigate to after save. Defaults to the current `scrName`. |
| `delay` | `int?` | Wait-screen duration in seconds (default `5`). |
| `updateTable` | `Map?` | Remote table-update spec (`{ table, update }`). Both fields are passed through `autheniumDecode(...)`. |

> The encoded `updateTable.table` looks like `"$vtl/request//request_master⭘<12>◼approved"`. Separators come from `separator[]` in `init_values.dart`.

## Usage Example

```dart
FtzRowOfButton2(
  key: const ValueKey('actions'),
  scrName: 'submitClaim',
  component: const {
    'children': [
      {
        'position': 10,
        'label': 'Cancel',
        'isEnabled': 'true',
        'route': 'home',
      },
      {
        'position': 11,
        'label': 'Submit',
        'isEnabled': 'true',
        'com': 'request',
        'updateTable': {
          'table': '...',     // authenium-encoded
          'update': '...',    // authenium-encoded
        },
        'route': 'home',
        'delay': 5,
      },
    ],
  },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
)
```

## State / Bloc / Dependencies

- **Bloc:** [`TimerBloc`](../../lib/bloc_timer/timer_bloc.dart) — receives `Start(duration: ...)` to drive the wait screen.
- **Auth bloc:** [`AuthenticationBloc`](../../lib/login/bloc_authentication/authentication_bloc.dart) — used for token refresh / re-auth around save flows.
- **Redux:** `transactionStore` + [`UpdateScreenTxAction`](../../lib/redux/screen_transaction.dart) — sets `#NEXTROUTE`, `#TIMER_CONTEXT`, `#TIMER_DURATION` for the wait screen pipeline.
- **Repositories / API:** [`TableRepository`](../../lib/firestore_repository/table_repository.dart), [`Api`](../../lib/api.dart), `ConnectionData`.
- **Sibling widgets:** [`do_chain`](../../lib/widget/do_chain.dart) for chained actions.
- **Globals:** `txfController`, `txfControllerCheck`, `canInitializePage`, `getTableVid`, `autheniumDecode`, `defaultVid`, `saveSend`, `errorReport`, `rootThis`.
- **Packages:** `cloud_firestore`, `flutter_bloc`, `geolocator`, `get`.

## Important Behavior

- `with AutomaticKeepAliveClientMixin` → button row state is preserved across scrolling.
- `initState` lazily creates a `txfController` slot for every child with a `position`, then writes `isEnabled` from each child's config (anything other than the literal string `'false'` becomes `true`).
- The save flow calls `saveSend(...)` (asynchronously) and `dispatch UpdateScreenTxAction(...)` first so the wait screen has its `#NEXTROUTE` and timer context ready before the timer starts.
- `rootThis.wait = true` is toggled before the timer starts — the wait screen reads this flag.
- `updateTable.table` and `updateTable.update` go through `autheniumDecode(...)` (proprietary encoding) before being parsed with `separator[1]` (black diamond `◼`) and `:` for `valueSep`.
- `dialog: true` mode is a hint for downstream save logic so it pops the dialog instead of routing.
- **`case 'savesend':` opens with the GET_IMAGES required-photo gate.** If the page carries a
  `GET_IMAGES` component with `optional:"FALSE"` whose record slot holds no photo, an `AlertDialog`
  is shown and the closure returns — before `dataOk`, before `actionLock`, before `doSaveProcedure`,
  so no event is written, no route is pushed and no chain runs. Title comes from the component's
  `label`, body from its `text` ◆ segment 1; both fall back to constants in
  [`get_images_required_support.dart`](../../lib/widget/get_images_required_support.dart), and a
  missing message never unblocks the submit. Components with no parseable `position`, and components
  whose slot is disabled at press time, are skipped so the gate always has a reachable exit.
  `case 'update':` is deliberately NOT gated. See [otq_get_images_2.md](otq_get_images_2.md).
- **A refused press inside a `DO_BOTTOM_SHEET` leaves the sheet OPEN.** The gate's `return` also
  skips the post-switch `if (dialog ?? false) { Get.back(); }`, so the sheet stays up with every
  input the officer already filled — deliberate, so the refusal is read in the sheet's own
  context and the officer presses again after taking the photo. It is the same shape as the
  existing `if (outBlocked) return;` refusal in this case, which skips that same `Get.back()`.
  A `dataOk` refusal differs: it falls through to `break` and closes the sheet.
- **A refused savesend is not a no-op.** The `run:` command block and `writeRouteParams` both execute
  BEFORE the `action` switch, so a press blocked by the gate has already applied any
  `enable`/`disable`/`toggle`, already consumed a `generate_number`, and already dispatched
  `routeParams` into `screenTx`. Only the event write, the route change and the chain are prevented.

> See the source for the full chain (`do_chain`) and GPS-gated save paths — too long to inline here.

## Save Flow (button press → Firestore)

When a button is pressed, data flows through six layers. The "submit point" is `appendToSheet` in `api.dart`, which dispatches `SubmitBloc.add(AddSubmit(...))` to write a queued document to Firestore.

| # | Step | Location | What it does |
|---|---|---|---|
| 1 | `onPressed` callback | [ftz_row_of_button_2.dart:367](../../lib/widget/ftz_row_of_button_2.dart#L367) | Handles `run` commands (`get_gps`, `get_address`, `get_radius`, `enable`, `disable`) locally, then calls `doSaveProcedure(i)`. |
| 2a | Direct Firestore update (optional) | [ftz_row_of_button_2.dart:147-268](../../lib/widget/ftz_row_of_button_2.dart#L147-L268) | If `child['updateTable'].isNotEmpty`, queries `MobileTable/$tableVid/tables/$tableName/content` and runs `doc.reference.update(updateData)` + parent `u` timestamp. Side effect; runs **before** the main submit. |
| 2b | Save dispatcher | [ftz_row_of_button_2.dart:305](../../lib/widget/ftz_row_of_button_2.dart#L305) | `saveData(timeStamp, scrName, child, locString, send: send)` — the local closure at lines 78-95. |
| 3 | `saveData` (local closure) | [ftz_row_of_button_2.dart:78-95](../../lib/widget/ftz_row_of_button_2.dart#L78-L95) | Sets `rootThis.wait = true`, starts `TimerBloc`, dispatches `UpdateScreenTxAction({#NEXTROUTE, #TIMER_CONTEXT, #TIMER_DURATION})`, then calls `saveSend(...)`. |
| 4 | Payload assembly | [api.dart:3494-3656 `saveSend`](../../lib/api.dart#L3494) | Builds `row[]` of length `sheetSystemLength + txfController[scrName].length`. **For every entry in `txfController[scrName]`** writes either `finalData` (if not the `emptyString` sentinel) or `controller.text` into `row[position + sheetSystemLength - 1]` after `stringCleanUp(...)`. Resolves `addToTable` / `updateTableRow` / `deleteFromTable` (authenium-decoded + `replacePlaceholders`). Then calls `saveSendRows(...)`; optionally `updateTableRow(...)` and `deleteFromTable(...)`. |
| 5 | Final encoding | [api.dart:3658-3692 `saveSendRows`](../../lib/api.dart#L3658) | Encodes `row[2] = '0' + flag + locString + separator[0] + ...row[15+] joined with separator[3]` (★). Truncates row to 3 elements (`[timestamp, scrName, encodedPayload]`) and calls `appendToSheet(...)`. |
| 6 | **Submit** | [api.dart:3694-3729 `appendToSheet`](../../lib/api.dart#L3694) | JSON-encodes the row, generates `id = #VID + Random`, dispatches `SubmitBloc.add(AddSubmit(Submit(st, ss, c, id, appVid, t, p, c2, d, f, w, tb)))` — **this is the actual write to Firestore (queued)**. Then `LoadSubmit()` refreshes cache and `TimerBloc` starts the wait screen. |

### Payload anatomy

`row[2]` (the encoded user data) looks like:

```
0<flag><locString>⬤<row[15]>★<row[16]>★<row[17]>★...
```

- `⬤` = `separator[0]` (black circle) — boundary between location string and form data
- `★` = `separator[3]` — separator between form fields
- `row[15]` corresponds to `position 1`, `row[16]` to `position 2`, etc. (offset by `sheetSystemLength = 15`)
- Empty Dart `null` slots emit nothing between `★`s; literal string `"null"` slots emit the word `null`. **`getInitialValue` does NOT prevent this** — [`init_values.dart:11`](../../lib/init_values.dart) gates on `component['currentValue'].toString().trim().isNotEmpty`, and `null.toString()` is the four-character string `"null"`, which passes. An absent `currentValue` therefore reaches `finalData` as `"null"` and is submitted verbatim. Widgets that must detect an empty slot treat `'null'` as an explicit empty sentinel (see `digitPadNormalizeSeed`, `getImagesSlotHasPhoto`).

### Implication for new widgets

A widget contributes to the payload **only** if it registers itself in `txfController[scrName][position]`. Stateless / display-only widgets (e.g. [ProgressBar](progress_bar.md)) intentionally omit this; widgets that should be submitted (e.g. [Tasklist](tasklist.md), [OtqRdo2](otq_rdo_2.md), [OtqDropdown2](otq_dropdown_2.md), [OtqGetImages2](otq_get_images_2.md), [OtqTxf2](otq_txf_2.md)) call `txfControllerCheck(scrName, position)` in `initState` and write to `finalData` whenever their value changes.

## See Also

- [ftz_row_of_button.md](ftz_row_of_button.md) — v1 version (`FtzRowOfButton`)
- [do_chain.md](do_chain.md) — chained-action runner used for buttons with a chain definition
- [otq_txf_2.md](otq_txf_2.md), [otq_rdo_2.md](otq_rdo_2.md), [otq_dropdown_2.md](otq_dropdown_2.md), [otq_get_images_2.md](otq_get_images_2.md), [display_list_2.md](display_list_2.md) — v2 component family
- [tasklist.md](tasklist.md), [progress_bar.md](progress_bar.md) — checklist family that participates in the same payload via `txfController`
