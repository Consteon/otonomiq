# ChecklistDynamic

DB-driven cleaning checklist: N task rows pulled from a Firestore sub-collection filtered by a `{template}` routeParam, rendered exactly like `TASKLIST`, and submitted as **one form slot per task** — a contiguous block starting at the component's own `position`.

- **File:** [lib/widget/checklist_dynamic.dart](../../lib/widget/checklist_dynamic.dart)
- **Class:** `ChecklistDynamic` (StatefulWidget)
- **SDUI `type`:** `CHECKLIST_DYNAMIC` — the dispatch branch also accepts `checklistDynamic` (both are lower-cased before matching)
- **Status:** draft
- **Widget version:** v2 (per-field output). v1 wrote one joined `task|status~…` value into one slot; the owner rejected it after a device test because it is hard to map per item.
- **Spec:** `cleaning-checklist-db-driven-dev-spec (1).md` §5.5 "REVISI 08-21", §7.4

> ### ⚠ **`output` IS INERT — READ BY NOBODY**
> The dev spec's contract JSON carries `"output": "ck"` and calls it a *prefix*. **This app has no
> mechanism for a widget to name a submitted field.** `grep -rn "\['output'\]" lib/widget/` → 0 hits.
> `saveSend` writes the submitted record **by POSITION**, never by field name.
>
> **The field names `ck1 … ckN` are assigned SHEET-SIDE, by the close button's `updateEventRow`**
> (see [Config / deploy](#config--deploy)). Leaving `"output"` in the page JSON is harmless, but it
> has no effect whatsoever — an unknown SDUI key is ignored with no crash, no log and no analyzer
> hit. Do not expect changing it to rename anything.

## Purpose

Replaces the five static per-category "Form Akhir" pages, each of which baked one [`Tasklist`](tasklist.md) component per task with the task name hardcoded in `text` slot 0. Adding a task meant editing a page; a new tenant meant a new page.

Here the task rows come from `//checklist_template`, scoped by the `template` routeParam a scanner **must** write on the previous screen — that entry route is a hard requirement, not an incidental one; see the callout in [State / dependencies](#state--dependencies). Adding a task = adding a row in the admin sheet. `Tasklist` is **not** deprecated by this widget — spec §8 keeps the five static pages as a fallback.

## Signature / Constructor

```dart
const ChecklistDynamic({
  Key? key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

## `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `position` | `int` / `String` | **YES** | — | **First** slot of the block. Task 1 lands here, task 2 at `position+1`, and so on. Without it nothing is submitted and the widget renders an error marker. |
| `slots` | `int` / `String` | **STRONGLY RECOMMENDED** | `0` | **Size of the slot block the sheet config enumerates.** Set it to the number of `ckN` keys the close button lists. `0` / absent / negative ⇒ the widget claims exactly the current task count — see [Capacity](#capacity--the-slots-key). Note: an unrelated widget ([item_execution_list](item_execution_list.md)) also has a `slots` key, but there it is a `value^Label~…` **String**; component keys are per widget type, there is no collision. |
| `currentValue` | `String` | **YES — must be `""`** | — | ⚠ **Not optional, and the failure is a value in a submitted report.** With the key absent, `getInitialValue` evaluates `null.toString()` and seeds the literal 4-character string `"null"` into slot `position`. When the template has AT LEAST ONE task the widget overwrites that slot on its first build, so the seed never survives. **When the template has ZERO tasks it does not** — D8 forbids writing to any slot on an empty list (that write is what would destroy the officer's ticks on a pre-snapshot remount, see [w-15](#tests)), so the seed reaches Firestore as **`ck1: "null"`**. Three of the five live templates have zero seeded docs today, so this is reachable now, not theoretical. Setting `""` closes it completely. Note this is NOT covered by any test — the widget-test harness always supplies `'currentValue': ''`. This widget cannot resume a stored value from `currentValue`. |
| `table` | `String` | yes | — | `"<tableDocId>//<subColl>"`, e.g. `"84214220504259//checklist_template"`. No `//` ⇒ `subColl` defaults to `content`. |
| `vidtable` | `String` | no | tenant lookup | Firestore container vid. Resolution order: `vidtable` > `getTableVid(com)` > `applicationTableVid`. |
| `search` | `String` | no | — | Multi-clause filter, `field◼value` joined by `⭘`. `{token}`s resolve from driver/session tokens then from **bare** screenTx keys. Server escapes `_25FC_` / `_u25FC_` / `_u2B58_` are decoded. **Fail-closed on an UNRESOLVED or EMPTY value:** either yields ZERO rows, never an unfiltered list. It is **not** a guard against a *stale* value. Live shape: `tmp◼{template}`. |
| `sortField` | `String` | no | **`ord`** | Doc field to sort by. Numeric-coerced, so `"10"` sorts after `"9"`. A doc **missing** this field coerces to `0`: it sorts first, and it is **never dropped**. Ties are broken **stably** by the incoming (Firestore document-id ascending) order. |
| `sortDir` | `String` | no | `asc` | `desc` (case-insensitive) reverses the **primary** key only; ties keep incoming order either way. |
| `taskField` | `String` | no | **`tsk`** | Doc field holding the task text. A blank/missing value drops the row. |
| `pendingLabel` | `String` | no | `belum` | Label written for a task nobody has touched. |
| `category` | `String` | no | `''` | Blue badge above the task name; blank ⇒ not rendered. Component-level, same as `TASKLIST`. |
| `borderRadius` | `int` / `String` | no | `10` | Card corner radius. |
| `margin` | `String` | no | `0,0,0,0` | `top,bottom,left,right`, per row. |
| `text` | `String` | no | — | ◆-separated, see the slot map below. |
| `options` | `String` | no | — | ◆-separated `icon ◆ label ◆ description` triplets, one per status, in the order `done, not_available, skipped, issue`. Extra triplets beyond 4 are ignored; fewer than 4 simply offers fewer statuses. |
| `output` | `String` | — | — | **INERT — see the boxed warning at the top of this page.** |
| `width` / `height` | any | — | — | **INERT.** `TASKLIST` does not read them either. |

> ⚠ **A blank sheet cell selects the DEFAULT, it is not `""`.** `SduiSpec.str()` returns the default
> for a missing *or blank* value (`sdui_spec.dart:47-51`). That is why `taskField` / `sortField`
> default to the live DB field codes `tsk` / `ord` and not to the spec's earlier human-readable
> `task` / `order`: a stale default would make a blank cell silently read a field that does not
> exist, and the checklist would render empty with no error.
>
> Consequence: with `sortField` defaulting to `ord`, a blank cell can no longer mean "render in
> snapshot order". Nothing in the spec asks for that.

### `text` slot map

Slots 1–4 are byte-identical to `TASKLIST`, so an existing static config ports over by deleting the task name from slot 0.

| Slot | Meaning | Blank ⇒ |
|---|---|---|
| 0 | empty-state message | `Belum ada task untuk kategori ini.` |
| 1 | "completed at" prefix | `Completed at` |
| 2 | subtitle when status = `not_available` | no subtitle |
| 3 | subtitle when status = `skipped` | no subtitle |
| 4 | subtitle when status = `issue` | no subtitle |
| 5 | status-sheet header | `Change Status` |

> The over-capacity warning message is **deliberately NOT configurable** and has no `text` slot: a
> warning a tenant can blank out is a warning the officer never sees, and this one reports silent
> data loss.

## Example config

```json
{
  "type": "CHECKLIST_DYNAMIC",
  "position": 12,
  "slots": 6,
  "currentValue": "",
  "vidtable": "20342033315492",
  "table": "84214220504259//checklist_template",
  "search": "tmp◼{template}",
  "sortField": "ord",
  "sortDir": "asc",
  "taskField": "tsk",
  "pendingLabel": "belum",
  "borderRadius": 10,
  "margin": "0,5,0,0",
  "text": "◆Selesai◆Tidak tersedia di area ini◆Dilewati - Kunjungi kembali nanti◆Masalah - jelaskan dalam laporan.◆Ubah Status",
  "options": "✓◆Selesai◆Tandai Selesai◆✖◆Tidak Tersedia◆Barang tidak ada di area ini◆>◆Dilewati◆Kembali lagi nanti◆!◆Masalah◆Jelaskan dalam laporan"
}
```

## Submitted value

**One form slot per task**, in render order, starting at `position`:

| slot | value |
|---|---|
| 12 | `Sapu & pel lantai \| Selesai` |
| 13 | `Sikat kloset & urinoir \| Selesai` |
| 14 | `Bersihkan wastafel & cermin \| Tidak Tersedia` |
| 15 | `Isi ulang sabun & tisu \| belum` |
| 16 | `` (empty — the template has no task here) |
| 17 | `` |

Format: `<task> | <status>` — space, pipe, space.

- `""` means **the template has no task in this position**.
- `<task> | belum` means **a task exists and the officer left it undone**. The two are deliberately different.
- The reader splits on the **first** `|` and trims both sides, so a legacy bare `task|status` value still re-hydrates.
- `|` is stripped from **both** operands (replaced by a space), so a tenant-authored title can never inject a second delimiter.
- `stringCleanUp` (inside `saveSend`) deletes every `forbiddenCharacter` — `◆ ⬤ ★ ◼ ⭘ ◁ ▷` included — so a task title can neither inject `updateEventRow` DSL nor break the history row's own `★` field separator. Spaces and `|` survive; this is confirmed by production visit documents.

> ### ⚠ `~` HAS RETIRED — THE `op1Script` SPLIT INSTRUCTION IS WITHDRAWN
> v1 joined every task into one slot with `~` between tasks, and the sheet-side `op1Script` was told
> to split on `~`. **That instruction no longer applies.** There is nothing to split: each task
> arrives in its own column. `~` is also no longer stripped from task titles, so a task named
> `Cek A~B` now submits verbatim.

> ### ⚠ `ckN` IS THE RENDER INDEX, NOT THE `ord` VALUE
> `ck1` is the **first task after sorting**, `ck2` the second, and so on. `ckN == ord` **only when
> `ord` is contiguous 1..N** for that template (which the spec §3 seed is). If `ord` is `10/20/30`,
> or has gaps, or repeats, the keys stay `ck1..ckN` and only the ORDER follows `ord`.
>
> This is deliberate. Deriving the slot from `ord` would make an uncontrolled tenant value decide
> which form slot is written — `10/20/30` would fling tasks to slots 21/31/41 and collide with other
> page components, and two docs sharing an `ord` (which production has today) would collide on one
> slot and lose a task silently.

> ### ⚠ LEGACY VISITS CARRY `ck`, NEW VISITS CARRY `ck1..ckN`
> Visits written **before** this change carry a single joined field `ck`
> (`"task|status~task|status~…"`) and **no** `ck1..ckN`. Visits written **after** carry `ck1..ckN`
> and **no** `ck`. There is no backfill and no dual write. Any downstream reader — the Ringkasan
> screen, the tenant's sheet-side reporting — must tolerate both shapes, or the old docs must be
> normalised by hand. As of 2026-08-21 exactly two test visits are affected.

## Capacity — the `slots` key

`slots` declares the size of the block, and should equal the number of `ckN` keys the close button lists.

| Situation | Behaviour |
|---|---|
| `taskCount == slots` | every slot holds a task |
| `taskCount < slots` | the unused tail slots are written `""` **on every build** (a shrunken template cannot leave a stale value behind) |
| `taskCount > slots` | a red warning row renders above the list naming how many tasks will be lost; the excess rows render **greyed and non-interactive**; **nothing outside the block is written** |
| `slots` absent / `0` / negative | the widget claims exactly `taskCount`: no tail-blanking, no warning row |
| `position + slots - 1 > 100` | the block is clamped to slot 100 (`saveSend` only submits slots 1..100) and the clamp surfaces through the same warning row |

> **Why `slots` is strongly recommended.** Without it, a template that SHRINKS mid-visit leaves stale
> values in the freed tail slots, and the parse phase can no longer see a status belonging to a task
> that moved out of the shortened block.

> ### ⚠ THE BLOCK MUST BE RESERVED ON THE PAGE
> Positions `position … position + slots - 1` must be used by **no other component on that page**.
> Nothing in the app can detect a collision: two components writing the same `txfController` slot
> just overwrite each other, last build wins, with no crash and no log.

## State / dependencies

- **Firestore:** `subscribeToMapCollection` → `mapTableContent['<vid>/<tableDocId>/<subColl>']`. The subscription code is vid-scoped; an unscoped code collides across tenants. Live path: `MobileTable/20342033315492/tables/84214220504259/checklist_template`.
- **Form slots:** `txfController[scrName][position + k].finalData` — the **single source of truth** for the N statuses. The whole block is re-parsed and re-written on every build.
- **Redux:** read-only, indirectly — `{token}`s in `search` resolve from bare screenTx keys (e.g. `template`, written by the scanner's `routeParams`). No dispatch, no `#`-key, no `documentation.md` entry.
- **GetX:** `Obx` on `mapTableContent`, `GetBuilder<WidgetUpdateController>` on id `'$scrName-$position'` so `clearData`'s repaint reaches the widget. No new controller, no `ScreenSession` entry.

> ### ⚠ THE ENTRY ROUTE IS PART OF THE CONTRACT — A **STALE** `template` IS NOT FAIL-CLOSED
> `template` is a **bare screenTx key**, and screenTx is **merge-only**: `UpdateScreenTxAction` never
> removes a key, and `DeleteAllScreenTxRowAction` is declared but never dispatched anywhere in `lib/`
> (documented at `scanner.dart:56-64`). A value written by a PREVIOUS scan therefore survives for the
> whole app session.
>
> `filterByMultiClause` is fail-closed only on an **empty or `{`-containing** value
> (`driver_home_support.dart:672`). A stale value is neither: every clause resolves cleanly.
>
> **So this page MUST be entered through a scanner whose `routeParams` declares `template`.** That
> scanner dispatches `scannerBlankRouteParams` (`lib/widget/scanner.dart:80`, dispatched at `:449` —
> i.e. BEFORE the row write at `:455`), which blanks every declared key first, so a key *this* scan
> cannot resolve reads as `''` — and `''` **is** fail-closed.
>
> Reach this page by any OTHER route — a `GOTO`, a back-navigation, a menu tap, or a scanner whose
> `routeParams` omits `template` — and it silently renders the **previous category's** tasks. No
> blank screen, no log, no failing test: it arrives as wrong data inside a submitted report.

## Important behavior

- **The whole block is parsed BEFORE any of it is written.** The re-hydration source *is* the block about to be overwritten, and a task **moves slot** when the admin deletes an earlier task. Interleaving the read and the write would lose the moved task's status.
- **An EMPTY task list writes to NO slot at all** — not even `""`. A remount that precedes the Firestore snapshot renders zero titles (SDUI rows live in `AnyPage`'s `ListView.builder` with no keep-alive, `page/any_page.dart:168`, so a scrolled-off row is disposed and remounts with fresh `State`); blanking the block there would erase the officer's ticks. An unresolved `{template}` and a template with zero seeded docs take the same path. **Accepted cost:** if a template's docs are ALL deleted mid-visit, the previously written slots survive into the submitted row.
- **Statuses survive `ListView` recycling.** Because they live in `finalData` and are re-parsed on mount, the ticks come back. `clearData` resets `finalData` to `initialValue` on navigation, so a fresh visit starts all-pending.
- **`finalData` is written on EVERY build, unconditionally** (when there is at least one task). `txfControllerCheck` births every slot with `'--'`, and `saveSend` falls back to `controller.text` whenever `finalData == '--'`. Making the write conditional re-opens that path. `controller.text` is deliberately never written (assigning it mid-build is a `setState`-during-build).
- **Reads never create controllers.** The parse phase uses `txfController[scrName]?[slot]?.finalData ?? ''`. In the over-capacity case the write phase may never reach a slot, and an empty-but-existing entry would become a real `''` cell in the submitted row.
- **Merge is by task TITLE.** An edited template degrades: a surviving title keeps its status even if it moved slot, a new title starts pending, a deleted title drops out. Two docs with the SAME title share one status — a config error; both rows move together.
- **The sort is STABLE.** Dart's `List.sort` is a dual-pivot quicksort and is stable only below 32 elements. Ties (two docs with the same `ord`, or several docs missing `ord` and all coercing to `0`) are broken by the incoming Firestore document-id order, so slot→task assignment does not change between builds.
- **A blank `options` label is emitted as the status KEY** (`done`, `not_available`, `skipped`, `issue`), never as an empty string, so the officer's pick still round-trips through the slot.
- **Two triplets must never resolve to the SAME label — that is a config error.** The reverse map is keyed by label and the later index overwrites the earlier one, so picking the *earlier* status reads back, from the next build on, as the *later* one. The submitted string is NOT corrupted (both statuses serialize to that same label); what flips is the internal status key, and with it the badge colour, the circle icon, the `text` slot 2/3/4 subtitle, and which row the status sheet marks as selected. A configured label that literally **equals a status key** collides the same way with a *blank* label on another triplet. One rule covers both: **every `options` triplet needs a distinct, non-blank label that is not one of `done` / `not_available` / `skipped` / `issue`.**
- **The report is self-describing:** each value carries the task text, so a template edited later does not rewrite old reports.
- **"Completed at HH:MM" is cosmetic and not persisted** — the slots store task+status only, so the line disappears after a remount until the task is re-ticked.
- **No progress bar** (spec §5.4 optional): `TaskProgressStore` is keyed `(scrName, position)`; wiring it to a block of positions needs a new store shape.
- **No `isEnabled` gate** — `TASKLIST` has none either.
- **The status sheet renders `min(options.length, 4)` entries.** The dev spec's own `options` string has only three triplets, so it offers three statuses; add a fourth triplet to expose `Masalah`.

## Config / deploy

The renderer and the sheet config **must ship together** (spec §5.5). Full paste-ready note: see the plan `.claude/plans/cleaning-checklist-per-field-output.md` §8.

In the Form Akhir close button's `updateEventRow`, **delete** `⭘ck◼◁12▷` and **append** one segment per slot:

```
⭘ck1◼◁12▷⭘ck2◼◁13▷⭘ck3◼◁14▷⭘ck4◼◁15▷⭘ck5◼◁16▷⭘ck6◼◁17▷
```

`◁N▷` resolves to **form position N** — do **not** add 1.

## Tests

- [test/checklist_dynamic_test.dart](../../test/checklist_dynamic_test.dart) — pure seams: the `" | "` serializer, delivered-value survival through `stringCleanUp`, the tolerant parser and its three empty sentinels, label↔key maps, the fan-out value list (tail blanking, block truncation, merge across slots), block arithmetic (`slots` degradation, the slot-100 clamp, overflow count/message), title extraction, the stable numeric sort against production fixtures, the `SduiSpec.text` blank-slot trap, the blank-`options`-label round trip.
- [test/checklist_dynamic_widget_test.dart](../../test/checklist_dynamic_widget_test.dart) — pump: fan-out + order, `{template}` scoping, the fail-closed empty state, taps landing in the right slot, the `Obx` zero-observable guard, the `'--'` sentinel, remount re-hydration, a task moving slot, tail blanking, the over-capacity warning + inert rows, the empty-list zero-write guard, the `tsk`/`ord` defaults, and the live half-normalised production seed.

## See Also

- [tasklist.md](tasklist.md) — the static per-task widget this replaces (kept as a fallback)
- [progress_bar.md](progress_bar.md) — aggregator over multiple `Tasklist` positions; **not** compatible with this widget
- [list_card.md](list_card.md) — the read-path idiom (`resolveAppVid` / `parseTablePath` / `filterDriverHomeDocs` / `coerceNum` sort) this widget copies
