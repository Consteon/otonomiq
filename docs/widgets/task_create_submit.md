# TaskCreateSubmit

Submit button for the Admin create-task wizard (P4).

- **File:** [lib/widget/task_create_submit.dart](../../lib/widget/task_create_submit.dart)
- **Class:** `TaskCreateSubmit` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** admin-create-task slice

## Purpose

Assembles the complete task doc (scalars from screenTx bare keys + it[] from
the draft) and writes it via `createNativeDoc` (one native Firestore set,
offline-safe). On success: clears draft, navigates to P5. Mirrors
`CustodyCountSubmit` O1 path.

## Signature / Constructor

(Standard SDUI widget: key, scrName, component, lPad, tPad, rPad, bPad.)

### `component` shape

| Key | Type | Description |
|-----|------|-------------|
| `table` | String | Firestore table path for task collection |
| `vidtable` | String | appVid override |
| `wizardKey` | String | Draft holder key (default `admin_create_task`) |
| `originWarehouse` | String | gl value (warehouse FK) |
| `klKey`/`knKey`/`alKey`/`vvKey`/`glKey` | String | screenTx key name overrides |
| `route` | String | P5 route on success |
| `routeParams` | String | **Optional.** `key◼value⭘key◼value`; values resolve `{field}` against the task doc just written, then session tokens. Dispatched as BARE screenTx keys immediately after a successful create and BEFORE the `chain`/`route` branch, so both navigation paths carry them. Live use: `taskVid◼{tnm}` for `OrderConfirm`. Absent = no dispatch (unchanged behaviour). Every declared key is blanked first, so a key this submit cannot fill reads as `''` rather than as the previous task's value. |
| `chain` | dynamic | Chain config (optional) |
| `text` | String | Diamond-separated label slots (4 slots) |

## Event audit row

After a successful native write and **before** navigation, the widget calls
`emitSubmitEventRow` (`lib/widget/driver_home_support.dart`), which routes through
`saveSend` -> `saveSendRows` -> `appendToSheet` -> the history queue -> the Event
tab. **Unconditional** -- no config key gates it.

- `ev` (Event col C) = geo block (`⬤`-left) + every `txfController[scrName]` slot
  with `1 <= position <= 100`, joined by `★`. On this page that is the generated
  `tnm` at `numberPos` PLUS the four scalars `TaskCreateSubmit.writeEventSlots`
  writes immediately before the emit (renderer-submit-event-gap round 2, spec
  §5A-2):

  | ★ slot | value |
  |---|---|
  | 11 | `kl` -- customer vid |
  | 12 | `kn` -- customer name |
  | 13 | `vv` -- vehicle; PRESENT but empty on the "Tugaskan Nanti" adhoc path |
  | 14 | `itArray.length` -- count of distinct item types |
  | 15, 16 | reserved by the spec, deliberately unwritten |
  | 17 | `tnm` -- generated at `numberPos`, NOT touched by `writeEventSlots` |

  `saveSend` maps form position P to `row[P + 14]` (`input.position +
  sheetSystemLength - 1`, api.dart:4845, `sheetSystemLength = 15`), so slot 11
  sits behind **10** leading `★`, not 11. The numbers are HARDCODED in Dart, not
  configurable, which makes it a PRECONDITION that the hosting page declares no
  component at positions 11-16 -- a component there would have its submitted
  value overwritten silently. Verified for tenant `20342033315492`
  (`docs/admin_runtime/admin-create-task-op1screen.md`: zero `position` keys
  across all six P4 components); NOT verified for any other tenant -- grep that
  tenant's recorded page JSON before enabling this route there. The remaining
  wizard scalars (`al`, `gl`, `la`/`lo`) stay in the draft holder and the report
  reads them off the task doc.
- `p` (col B) = `scrName`.
- `component['flag']` travels as a **prefix inside `ev` itself** -- `saveSendRows`
  builds `'0' + flag + locString + ⬤ + ...` (api.dart:5035-5038) -- not as a
  separate field. Blank when the config omits it; the row still lands.
- **`w` (widget type) and `desc` never leave the device.** `historySync` writes
  only `{"t","p","c","s"}` to Firestore (table_repository.dart:3099-3104); the
  `toDocument2()` path that would carry `w`/`f` is commented out
  (submit_repository.dart:54, :61). They exist in the LOCAL history row
  (`historyAdd([t, p, c, w, f, tb])`, table_repository.dart:2500-2502) and
  nowhere else. So with `flag` unset the report can key only on `p`.
- **GPS is UNCONDITIONAL.** `gpsPosition` is NOT read (renderer-submit-event-gap
  round 2): `emitSubmitEventRow` always awaits `OtqState().setAllDataAsync()`.
  When the fix is invalid, `eventLocString` (driver_home_support.dart) BLANKS the
  latitude / longitude / `isoCountryCode` slots rather than shipping `OtqState`'s
  field initialisers (`888.8888888`, `88`) as if they were a measurement. The
  `locationStatus` slot keeps its `No Gps` value -- so the report can still tell
  "GPS failed" from "geo never captured" -- and the geo block stays at exactly
  16 ◆-separated fields, leaving the report's column mapping unchanged.
- The component copy handed to `saveSend` has `addToTable`, `updateTableRow`,
  `deleteFromTable`, `addToEvent`, `updateEventRow` and `route` removed, so it can
  never double-write or fire `clearData` mid-submit.
- Best-effort: a GPS/compose failure logs and is swallowed, and it never rolls back the
  task doc. It DOES delay navigation, but **boundedly**: `emitSubmitEventRow` wraps the
  capture in an 8-second `.timeout`, because `getAppGps` puts no `timeLimit` on its
  `Geolocator.getCurrentPosition` fallback (api.dart:301-305) and this await sits on the
  pre-navigation path. Worst case the user waits ~8s before the success route appears;
  the row is still emitted, degraded to the blanked no-GPS geo block described above
  (lat/lng and `isoCountryCode` empty, `locationStatus` = `No Gps`, still 16 ◆ fields).

The task doc itself no longer carries `search` or `tablevid` (owner decision
2026-08-27) -- they were config parameters, not business data, and nothing read
them.

## Task doc timestamps

`AdminCreateTaskSupport.assembleTaskDoc` writes **two**:

| key | type | value |
|---|---|---|
| `t` | int | epoch ms, from `getNowMillisecondFromEpoch()` in `_onSubmit` |
| `ts` | String | `"yyyy-MM-dd HH:mm"` WIB, from `AdminCreateTaskSupport.formatWibTimestamp(t)` — the same formatter the nota uses |

`ts` is **derived inside the assembler from its own `t`**, not passed in, so the
two can never disagree — the same reasoning as `tot`, which is computed from the
it[] array that gets written. Both are ALWAYS present; the omit-when-empty idiom
on this doc is reserved for `vv`/`ln`/`tdt`, where absence means "invisible to
every driver feed".

`ts` exists for the `Tanggal` row of `RECEIPT_DOC` on `OrderConfirm`, which
reads its date by config name (`dateField: "ts"`). Added by spec (4) §6b-2.2
no.5; before it, that row rendered blank.

## See Also

- [task_item_builder.md](task_item_builder.md) -- P2 builder
- [task_draft_summary.md](task_draft_summary.md) -- P4 preview
- [custody_count_submit.md](custody_count_submit.md) -- structural mirror
