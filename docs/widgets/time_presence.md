# TimePresence

Display-only card showing check-in time, live elapsed counter, and last action time in a three-column layout.

- **File:** [lib/widget/time_presence.dart](../../lib/widget/time_presence.dart)
- **Class:** `TimePresence` (StatefulWidget)
- **Status:** done
- **Widget version:** v2 (v1 = literal `text` slot 6; v2 adds the optional `lastAction` ledger read)

## Purpose

Shows a compact time-presence summary card with three columns:
1. **Check-in** — the time the user checked in (static display).
2. **Live** — a real-time counter (HH:MM) ticking every second since check-in.
3. **Last Action** — the time of the most recent recorded action.

When the user has already checked out, both check-in and last-action columns show the no-data placeholder and the live counter stops.

Use this widget on attendance/presence screens where the user needs to see how long they've been on-site.

## Signature / Constructor

```dart
const TimePresence({
  required Key key,
  required dynamic component,
  required String scrName,
  required bool single,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `single` | `bool` | yes | — | Standard flag from the v2 component family |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `text` | `String` | Diamond-separated (`◆`) bundle of label and time strings — see text parts table below. |
| `borderRadius` | `num?` | Card corner radius in px. Default `12`. Ignored by `variant: "v4"`, which has no card. |
| `variant` | `String?` | **Optional look switch.** Only `v4` (trimmed, case-folded) selects the Vertika v4 timeline module. Absent, blank, or any unrecognised value renders the original three-tile card. |
| `lastAction` | `String?` | **v2, optional.** One `◆`-separated field with 5 positions — see below. Drives the **Aksi terakhir** column. Absent / blank / `--` / `[TOKEN]` ⇒ v1 behaviour: `text[6]` literal, **zero query**. |
| `checkIn` | `String?` | **r2, optional.** The **same 5-position grammar** as `lastAction`, driving the **Check-in** column from the same ledger. Absent / blank / `--` / `[TOKEN]` ⇒ v1 behaviour: `text[5]` literal, **zero query**. When it resolves a time, that time also becomes the origin of the live Durasi counter — the card never shows a ledger check-in beside a counter running from the sheet literal. Example: `t◆asc◆t◆HH:mm◆ty◼clock-in` = the first `clock-in` of today. |
| `vidtable` | `String?` | **v2, strongly recommended when `lastAction` is set.** Firestore container VID, resolved by `resolveAppVid`. **Omitting it is not blocked** — it falls back to `getTableVid(component['com'])` and then to `applicationTableVid`, whose build-time default is `60936087747650`. For a `tableDocId` that exists under more than one appVid (`84214220504259/event` does) that silently reads the **wrong tenant**: no error, no log. Always set it explicitly. |
| `table` | `String?` | **v2, required when `lastAction` is set.** Event ledger path, e.g. `84214220504259//event`. Parsed by `parseTablePath`. Absent ⇒ no subscription ⇒ placeholder. |
| `search` | `String?` | **v2/r2, required when `lastAction` or `checkIn` is set.** `key◼value⭘…` filter, scoping the ledger to one user, e.g. `cv◼87544551624342` or `cv◼{userVid}`. **Blank ⇒ the widget renders the placeholder and runs no query** — the search evaluators fail OPEN on an empty condition, so an unscoped read would show another user's event. A **non-blank** `search` that contains no well-formed `field◼value` clause — a space instead of the `◼`, or an empty field name — fails open the same way and returns **every** doc, and the widget cannot detect that: always verify the `◼` survived the paste. Both slots use this ONE `search`, each AND-ing its own position-5 `filter` onto it, and both read ONE shared subscription; a blank `search` therefore blocks **both** slots. |

### `variant: "v4"`

Opt-in redesign, following `redesign-otonomiq/v4/vertika-design-system-MASTER.md`.
The data contract is unchanged — same `text` slots, same `lastAction` rules,
same resolve table below. Only the presentation differs:

| | absent / unknown `variant` | `variant: "v4"` |
|---|---|---|
| Container | White card, 1 dp `#E2E8F0` border, `borderRadius` | None — the module sits directly on the page |
| Header | 11 px letter-spaced caps, clock icon | Section heading, 16 / 600, no icon (hidden when `text` slot 0 is empty) |
| Columns | Three grey tiles with borders | Three centred label/value pairs, label 12 / 600, value 18 / 600 tabular |
| Progress | None | Timeline track above the columns: done (green, check), live (ringed dot, pulsing), pending (grey ring), joined by solid or dashed connectors |
| Accent | — | `Theme.of(context).primaryColor`, stepped down to `#0F2A33` when the tenant colour measures below 4.5:1 on white |

Node state is derived, never configured: a column whose value is the slot-4
placeholder gets a pending node, the duration column is live while the counter
runs, and everything else is done. A connector goes solid green only once
neither of the nodes it joins is still pending.

Type sizes sit one step below the MASTER scale (which calls for 18 / 600
headings and 22 / 600 numbers) — on a handset the mockup sizes read oversized
against 12 px labels, and 12 is MASTER's own absolute floor. The pulse is the design system's one
permitted automatic motion and stops under `MediaQuery.disableAnimations`.

Two deliberate deviations from the mockup, both for contrast: placeholder
values use `#4A5F66` (6.73:1) instead of `--color-disabled-fg` `#93A6AC`
(2.53:1), and the pending node ring uses `#7E9298` (3.25:1) instead of
`#C5D3D7` (1.54:1), which misses the 3:1 bar a meaningful non-text indicator
owes.

Removing `variant` from the screen JSON restores the card — a config-only
rollback, no rebuild. Locked by `test/time_presence_variant_test.dart`.


Both v4/v6 widgets pad themselves up to a **16 dp content edge** via
`otqContentInset()`: the page body is padded by the sheet's
`systemUIComponent['Mobile']['leftPad']` (8 in this workbook) and the design
system asks for 16. It tops up the difference, so raising the sheet value to
16 later makes it a no-op instead of double-padding.

### `lastAction` / `checkIn` positions

One grammar, two slots. Format `pos1◆pos2◆pos3◆pos4◆pos5`. Order is fixed; every
position is length-guarded. Positions 1–4 are required in practice (each has a
documented default); position 5 is optional and may be omitted entirely.

| # | name | default | meaning |
|---|---|---|---|
| 1 | `sortField` | `t` | Field that orders the docs. Epoch ms. Also the **day-scope's** input: a doc whose `sortField` is not a readable epoch on today is out of scope. |
| 2 | `sortDir` | `desc` | Only a case-insensitive `asc` selects ascending. Anything else — including a typo — means `desc`. The scope is always today, so `desc` = the **last** event today and `asc` = the **first**. |
| 3 | `valueField` | the resolved `sortField` | Field whose value is printed in the slot. |
| 4 | `format` | `HH:mm` | `DateFormat` pattern, applied only when the value is an epoch; a non-epoch value is printed as-is. |
| 5 | `filter` | *(empty)* | **Optional.** Extra WHERE clauses `key◼value⭘…`, AND-ed onto `search` — not a replacement for it. Empty / absent = every doc that matches `search`. |

Examples:

- `lastAction:"t◆desc◆t◆HH:mm"` — every `ty`, the **last** event of today.
- `checkIn:"t◆asc◆t◆HH:mm◆ty◼clock-in"` — only `ty=clock-in`, the **first** of today.

### Ledger resolve rules (per slot)

Applies independently to `checkIn` (Check-in column, literal `text[5]`) and to
`lastAction` (Aksi terakhir column, literal `text[6]`). `text` indices are
0-based; the dev spec's "segmen 5/6/7" are `text[4]`/`text[5]`/`text[6]`.

| condition | rendered |
|---|---|
| the slot's key is absent / blank / `--` / `[TOKEN]` | that slot's `text` literal (v1). No query, no `Obx` for it. |
| the key is set, `search` blank | `text[4]` placeholder. No query. Fail-closed — and it blocks **both** slots. |
| `text[7]` (checkout) is a real value | `text[4]` in all three columns — checkout wins over the ledger, same as v1. |
| no doc in scope after `search` + position-5 `filter` + the day-scope (or `table` absent, or offline) | `text[4]` placeholder — **never** the slot's literal. |
| the winning doc has no `valueField` (or it is blank / `--`) | `text[4]` placeholder. |
| otherwise | `valueField` formatted with `format`, in the **device** timezone. |

**Order is scope → pick, not pick → guard.** The docs are first scoped to the
current device-local day on `sortField`, and only then sorted and reduced to one.
A doc whose `sortField` is unreadable, or dated yesterday or tomorrow, is simply
out of scope. Reversing the two steps breaks `asc` outright — the pick would
return the oldest doc in the whole ledger and the day test would then reject it,
leaving the Check-in slot permanently empty. It also removes the only case where
`asc` could pick a doc that is **missing** `sortField` (which the shared
`pickNewestDoc` scores as `0`, below every real epoch).

The scope excludes tomorrow as well as yesterday, which is stricter than the dev
spec's `t >= 00:00` wording. It is one calendar day in the **device** timezone,
not a "not in the future" test: a doc stamped 23:59 today is in scope from 00:00
onwards and still wins `desc` when the card is read at 08:00. Only clock skew of
a full calendar day or more is filtered out.

A doc is in scope only when its `sortField` is readable as an epoch **and**
`int.tryParse` accepts it — the same parse the shared `pickNewestDoc` uses to
score it. The two are deliberately crossed: the epoch reader tolerates a `num`,
so a Firestore `double` would otherwise pass the scope and still score `0`,
which under `asc` wins every time.

### `text` parts

`component['text']` is split by `◆` into up to 8 parts:

| Index | Purpose | Default |
|---|---|---|
| `0` | Header label (displayed uppercase-style) | `"TIME PRESENCE"` |
| `1` | Check-in column label | `"CHECK-IN"` |
| `2` | Live counter column label | `"LIVE"` |
| `3` | Last action column label | `"LAST ACTION"` |
| `4` | No-data fallback display | `"--:--"` |
| `5` | Check-in time value (`HH:mm`) or placeholder. **v1 fallback only — overridden whenever `checkIn` is configured.** | `""` |
| `6` | Last action time value (`HH:mm`) or placeholder. **v1 fallback only — overridden whenever `lastAction` is configured.** | `""` |
| `7` | Checkout time value (`HH:mm`) or placeholder / empty = no checkout | `""` |

### Time value format

- **Valid time**: `"HH:mm"` format (e.g. `"08:30"`, `"14:05"`).
- **Placeholder**: Empty string `""` or bracket-wrapped token like `"[CHECKIN]"`, `"[LASTACTION]"`, `"[CHECKOUT]"`. Treated as "no data".

## Display Logic

```
if checkout time is set (text[7] is valid):
  → check-in column = noDataLabel
  → last action column = noDataLabel
  → live counter = noDataLabel (timer not started)

else if check-in time is set (text[5] is valid):
  → check-in column = formatted check-in time
  → live counter = elapsed time since check-in (ticking every second)
  → last action column = formatted last action time (or noDataLabel)

else:
  → all columns show noDataLabel
  → live counter not started
```

## Usage Example (Screen JSON)

### v2 / r2 — check-in and last action from the event ledger (Home worker)

```json
{
  "type": "TIME_PRESENCE",
  "width": 100,
  "height": 50,
  "format": "mm:ss",
  "vidtable": "20342033315492",
  "table": "84214220504259//event",
  "search": "cv◼87544551624342",
  "checkIn": "t◆asc◆t◆HH:mm◆ty◼clock-in",
  "lastAction": "t◆desc◆t◆HH:mm",
  "text": "Absensi hari ini◆Absen Masuk◆Durasi◆Aksi terakhir◆--:--◆16:02◆◆"
}
```

Displays: Absen Masuk = the `HH:mm` of this user's **first** `ty=clock-in` today ·
Durasi ticking from that same moment · Aksi terakhir = the `HH:mm` of this user's
**newest** `//event` doc today, whatever its `ty`. Both update live as new events
arrive, from one shared subscription. With no matching event today a slot shows
`--:--`, never the `text` literal. Dropping `checkIn` alone reverts the first
column to the `16:02` literal; dropping both keys reverts the whole card to v1
with zero queries. `search` may also be written `cv◼{userVid}`, which resolves
from `#VID` at runtime.

### Active session (checked in, not yet checked out)

```json
{
  "type": "TIME_PRESENCE",
  "text": "TIME PRESENCE◆CHECK-IN◆LIVE◆LAST ACTION◆--:--◆08:30◆09:45◆",
  "borderRadius": 12
}
```

Displays: Check-in `08:30` | Live `01:15` (ticking) | Last Action `09:45`

### Pre-check-in (no data yet)

```json
{
  "type": "TIME_PRESENCE",
  "text": "WAKTU KEHADIRAN◆MASUK◆DURASI◆TERAKHIR◆-:-◆[CHECKIN]◆[LASTACTION]◆"
}
```

Displays: Masuk `-:-` | Durasi `-:-` | Terakhir `-:-`

### After checkout (session ended)

```json
{
  "type": "TIME_PRESENCE",
  "text": "TIME PRESENCE◆CHECK-IN◆LIVE◆LAST ACTION◆--:--◆08:30◆16:00◆17:00"
}
```

Displays: Check-in `--:--` | Live `--:--` | Last Action `--:--` (all reset because checkout is present)

## Internal Widgets

| Class | Type | Purpose |
|---|---|---|
| `_TimeColumn` | StatelessWidget | Renders a single label + value column (used for check-in and last action). |
| `_LiveCounter` | StatefulWidget | Renders the live elapsed counter with a 1-second `Timer.periodic`. |
| `_ColumnDivider` | StatelessWidget | 8px horizontal spacer between columns. |

## State / Bloc / Dependencies

- **Timer:** `_LiveCounter` starts a 1-second periodic timer only when `checkInDt` is non-null. Timer is cancelled on dispose.
- **No external state in v1** — with both `lastAction` and `checkIn` absent the widget is purely display and touches no repository.
- **v2/r2 ledger read** — when `search` is set and at least one of `lastAction` / `checkIn` is configured, `initState` calls `subscribeToMapCollection(appVid, tableDocId, subColl, '$appVid/$tableDocId/$subColl')` (`lib/firestore_repository/table_repository.dart`). **ONE subscription serves BOTH slots** — same `table`, same `search`; only the position-5 filter and the sort direction differ, and both are applied client-side per slot. The subscription code **must** carry the appVid: `mapTableContent` and the dedup set are keyed by it alone, and `84214220504259/event` exists under two appVids with different content. It is idempotent per code and never cancelled — sibling widgets share the stream.
- **Realtime without a bespoke listener** — `mapTableContent` is an `RxMap` (`lib/global.dart:260`), so reading it inside `Obx` repaints on every Firestore snapshot. There is exactly **one** `Obx`, wrapping the whole module, and it is constructed only when at least one slot is live and neither the blank-`search` guard nor a checkout has fired: an `Obx` whose closure can complete without reading an observable throws `ObxError`.
- **Search evaluation** — `filterDriverHomeDocs` (`lib/widget/driver_home_support.dart`) does `autheniumDecode` → `resolveDriverCurlyTokens` (`{userVid}` → `#VID`, `{userName}` → `#NAME`) → `resolveScreenTxTokens` → `filterByMultiClause`. Each slot passes `search ⭘ filter` as one condition string, so there is a single evaluator. An unresolved `{token}` fails closed (empty result); an **empty** condition fails open, which is why the widget guards a blank `search` itself.
- **Doc selection** — `search`-filtered docs are scoped to today on `sortField`, then reduced by `pickNewestDoc(docs, field:, descending:)` (`lib/widget/driver_home_support.dart`), a single linear scan; ties keep the first doc in list order.
- **Live counter origin** — the Durasi counter starts from the resolved `checkIn` time when that slot is ledger-driven, and from `text[5]` otherwise. `_LiveCounter` re-arms its 1 s timer in `didUpdateWidget` because a ledger check-in arrives on a later frame than the first paint.
- **Helpers:** `diamondTextToList` from `global.dart` for parsing the text bundle.

## Important Behavior

- **Live counter ticks every second** — uses `Timer.periodic(Duration(seconds: 1))`. Display updates are `HH:MM` (no seconds shown), but the timer fires per second for smooth minute transitions.
- **Negative duration clamped to zero** — if the parsed check-in time is somehow in the future, the counter shows `00:00` instead of negative values.
- **Checkout resets all displays** — when `text[7]` contains a valid time (not placeholder), the widget intentionally hides check-in and last-action data. This signals "session ended" to the user.
- **Timer only created when needed** — if there's no valid check-in or if checkout is present, no timer is allocated (no unnecessary resource usage).
- **Mounted check** — timer callback verifies `mounted` before calling `setState`.
- **Tabular figures** — time values use `FontFeature.tabularFigures()` so digits don't shift when the counter ticks.

## UI Layout

```
┌─────────────────────────────────────────────┐
│ 🕐 TIME PRESENCE                            │  ← header (text[0])
│                                             │
│ ┌───────────┐  ┌───────────┐  ┌──────────┐ │
│ │ CHECK-IN  │  │   LIVE    │  │LAST ACTION│ │
│ │   08:30   │  │   01:15   │  │   09:45  │ │
│ └───────────┘  └───────────┘  └──────────┘ │
└─────────────────────────────────────────────┘
```

## See Also

- [location_detector.md](location_detector.md) — often paired on attendance screens
- [attendance_qr_selfie_gps_verify.md](../../lib/widget/attendance_qr_selfie_gps_verify.dart) — full attendance verification flow
