# TimelineCard

Day-grouped timeline card: coloured timeline dots, a big time column, a 4-slot `row` template with auto-hide, and a status chip inferred from the newest row. Fully config-driven — no hardcoded labels, no per-tenant Dart.

- **File:** [lib/widget/timeline_card.dart](../../lib/widget/timeline_card.dart)
- **Support:** [lib/widget/timeline_card_support.dart](../../lib/widget/timeline_card_support.dart) (pure parsers, grouping, chip inference — deliberately NOT barrel-exported)
- **Class:** `TimelineCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Dispatch:** `tip == 'timeline_card'` in `build_display_component.dart` (SDUI type `TIMELINE_CARD`)

## Purpose

`LIST_CARD` is a flat list of cards. This widget is a different render class: day-group separators, a coloured dot per row on a connecting rail, a big left-hand time column, a small note line, and a **status chip inferred from the newest row**. Forcing that into `LIST_CARD` — used by ~40 config rows — would mean stacking flags on a widget that many screens already depend on, so `TIMELINE_CARD` is its own type (spec §1).

First consumer: the home "Riwayat Absensi" card. The widget itself knows nothing about attendance — driver-trip, patrol and task-status timelines reuse it with **config only, zero Dart changes** (spec §7).

## `component` shape

Every key is read through [`SduiSpec`](../../lib/sdui_spec.dart), so values are `autheniumDecode`d and `◆`-split with index guards in one place.

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `vidtable` | `String` | no | app vid | Container VID, via `resolveAppVid`. Identical to `LIST_CARD`. |
| `table` | `String` | yes | — | `docId//subcollection`, via `parseTablePath`. Absent/unusable ⇒ no subscription, card renders its empty state. |
| `search` | `String` | no | `''` | Multi-clause `[[…]]` DSL, via `filterDriverHomeDocs`. Read RAW — the filter decodes and resolves `{token}`s internally, in that order. |
| `sortField` | `String` | no | `''` | Sort key, coerced via `coerceNum`. |
| `sortDir` | `String` | no | asc | `desc` (case-insensitive) sorts newest-first. |
| `limit` | `int`/`String` | no | `0` | `0` = no cap. Read RAW via `parseLimit` (it is a plain number, not a `◼`/`⭘`-encoded value). |
| `moreRoute` | `String` | no | `''` | Header "see all" route. `[ROUTE:x]` wrappers are stripped. |
| `row` | `String` | yes | — | `◆`-separated 4-slot template with `<field>` tokens — see [`row` slots](#row-slots). |
| `dotMap` | `String` | no | `''` | `value◼tier⭘value2◼tier2` — dot colour per row, keyed on the **same field as `chipField`**. |
| `chipField` | `String` | no | `''` | Field that drives both the chip and `dotMap`. |
| `chipMap` | `String` | no | `''` | `value◼Label◼tier⭘…` — see [Chip rule](#chip-rule-spec-4). **Entry order is semantic.** |
| `groupByDay` | `String` | no | `TRUE` | Anything but `FALSE` (case-insensitive) groups by local calendar day. |
| `text` | `String` | no | `''` | `◆`-separated static labels — see [`text` segments](#text-segments). |

Theme tier keys for `dotMap` / `chipMap`: `ok` · `info` · `warn` · `danger` · `muted`. They resolve through the shared `statusColor` / `statusBgColor` in [`panel_card_support.dart`](../../lib/widget/panel_card_support.dart).

### `text` segments

| Slot (0-based) | Meaning | Example |
|---|---|---|
| `0` | Card title | `Riwayat Absensi` |
| `1` | "see all" link label (header, right) | `Lihat semua` |
| `2` | Today-group prefix | `HARI INI` → `HARI INI · 31 AUG 2026` |
| `3` | Empty-condition chip label | `Belum Absen` |
| `4` | Empty state | `Belum ada riwayat absensi` |

**Chip placement.** The status chip is drawn on the **first day separator** (right-hand side) whenever a separator is emitted, and falls back to the **header** otherwise — `groupByDay:FALSE`, an empty list, or a blank `row` slot 0 time token (every group label is then `''`). It renders in exactly one of the two, never both. Chip casing is taken from `chipMap` verbatim; the widget does not upper-case it.

Every segment is optional and **blank-aware**: a present-but-empty `◆` slot reads as empty, not as a default. A blank segment renders nothing — the widget never invents a label.

### `row` slots

```
"row": "<t>◆<d>◆<i>, <lq>, <ln>◆GPS ±<acc> m"
```

| Slot (0-based) | Meaning | Rendered as |
|---|---|---|
| `0` | **time** — exactly one `<field>` token, an epoch-ms field. Drives the time cell, the day grouping AND the chip's date test. | `13:05` big/bold, left column |
| `1` | Row label | `CLOCK IN` |
| `2` | Description / location | `Sampora, Kecamatan Cisauk, Banten` |
| `3` | Small note | `GPS ±8 m` |

**Auto-hide (slots 1–3 only).** A slot renders only if it is token-free, OR every `<field>` token in it resolves non-empty. A slot whose tokens are missing/blank vanishes **together with its literal text** — `GPS ±<acc> m` on a doc without `acc` renders nothing, not `GPS ± m`. Integer `0` counts as non-empty. Implemented by delegating to `resolveNoteTemplate` ([`list_card_support.dart`](../../lib/widget/list_card_support.dart)), imported rather than copied so LIST_CARD's `note` and these row slots can never diverge.

An out-of-range slot yields `''`, never a `RangeError` — a lean tenant `row` with only two slots renders time + label and nothing else.

## Important behavior

- **`chipMap` entry order is SEMANTIC. The FIRST entry is the open / in-progress state and its chip shows regardless of date; every later entry is a terminal state and shows only when the newest row's local day is today. Authoring the terminal value first silently inverts the chip — no error, no log, no analyzer finding, just the wrong label on the card.**
- **A misspelled `<field>` token is indistinguishable from missing data — both render nothing.** First debug step for "the line disappeared": check the field code against the actual Firestore doc, not the widget.
- **`conditions` is NOT implemented.** Use `search` — it carries the same `[[…]]` multi-clause DSL through `filterDriverHomeDocs`.
- **Per-row `route` / `routeParams` are NOT implemented** (spec §10, v1 scope). Rows are not tappable.
- **`autheniumDecode` does NOT decode the legacy `_2B58_` form** (only `_u2B58_`, plus legacy `_25FC_`). A `dotMap` / `chipMap` written with `_2B58_` will not split, and the whole map silently parses as one malformed entry. Write `⭘` or `_u2B58_`. Do not "fix" `autheniumDecode` — the asymmetry is deliberate and pinned by tests.
- **`search` fails CLOSED.** A throwing or malformed search yields an EMPTY list, never the unfiltered set, and `devPrint`s the raw search string with the cause.
- **Timezone is DEVICE-LOCAL**, not `System!B3` (interview decision D2). `System!B3` has no path into the app (`grep -rn "#TIMEZONE\|#GMT\|#TZ" lib/` → zero hits). Times, day keys and the "is today" test all use `DateTime.fromMillisecondsSinceEpoch(ms)` in the device's local zone — the same convention as `formatEpochHHmm` and `formatEpochTime`. If a fixed offset is ever needed, that is a separate round and a separate config key.
- **A malformed `dotMap` entry (no `◼`) is SKIPPED**, never given a colour — fail-closed. An unmapped `dotMap` value falls back to `muted` (grey), never to the palette's default green.
- **No per-screen state.** Everything is derived per build from `mapTableContent` inside an `Obx`, so there is nothing keyed by `scrName` and nothing to reset in `clearData`.
- **Rows are built eagerly** (a plain `Column`, not a lazy `ListView`). Fine for a card capped by `limit`; the uncapped "Lihat Semua" page scrolls via the host `SingleChildScrollView` in `main_page.dart`. Switch to `ListView.builder` only if a tenant renders hundreds of rows.

### Chip rule (spec §4)

Read from the TOP row of the same already-sorted result set — **no second query, and never `workforce.st`** (spec §4 rejects it by name: `on`/`off` without a date cannot tell "just clocked out" from "never clocked in", and this timeline is itself the answer).

```
no rows / blank chipField / empty chipMap → empty-condition chip (text segment 3, tier `muted`)
value not found in chipMap                → empty-condition chip
chipMap index 0                           → its label + tier, with NO date condition
any other index, top row's day == today   → its label + tier
any other index, top row's day != today   → empty-condition chip
```

Spec §4's two worked examples, so a builder can pattern-match their own case:

| `chipMap` | Entry 0 (date-free, "open") | Entry 1+ (today-only, terminal) |
|---|---|---|
| `clock-in◼Sedang Bekerja◼info⭘clock-out◼Sudah Clock Out◼muted` | `clock-in` → `Sedang Bekerja` even for a 22:00 clock-in read at 06:00 the next morning (night shift crosses midnight) | `clock-out` → `Sudah Clock Out` only if the clock-out was today; otherwise `Belum Absen` |
| `mulai◼Dalam Perjalanan◼info⭘selesai◼Selesai◼ok` | `mulai` → `Dalam Perjalanan`, any date | `selesai` → `Selesai` only today |

The rule is **never** keyed off the literal string `clock-out` — that would break the generic reuse spec §4 demands.

### Day grouping

- `groupByDay` absent or anything but `FALSE` → grouped; `FALSE` → flat, **no separators at all**.
- Grouping walks the already-sorted list and closes a group whenever the local calendar day changes (consecutive runs, order preserved).
- Separator label: `HARI INI · 31 AUG 2026` when the day is today and `text` segment 2 is non-empty; the plain date (`30 AUG 2026`) otherwise; **no separator at all** for rows whose epoch is ≤ 0.
- Each separator carries `ValueKey('tlcard-day-<index>')` — a debugging affordance and the seam the widget tests count separators with.

## The `◀17▶` GPS-accuracy token

Shipped with this widget (spec §6). `getLocationString` ([`api.dart`](../../lib/api.dart)) now emits **17** `◆` fields; the appended slot (0-based index 16) is the GPS accuracy in whole metres, addressable from an `addToEvent` / `addToTable` config as the system token **`◀17▶`**.

Sheet config — append to the attendance writer line:

```
⭘acc◼◀17▶
```

Once deployed, the `//event` doc carries `acc` and `row` slot 3 (`GPS ±<acc> m`) comes alive on its own.

- **`◀17▶` is EMPTY, not `"0"`, when there is no GPS fix** (`OtqState.accuracy` is only assigned inside `getDataFrom`'s valid-fix branch). Empty is deliberate: it makes the whole `GPS ±… m` line vanish under the auto-hide rule instead of rendering a fake `GPS ±0 m`.
- **Never renumber the slots below 17.** Every deployed `◀N▶` is positional, and [update_table_row.md](../firestore/update_table_row.md) records live attendance configs bound to `◀2▶` / `◀5▶` / `◀6▶`. An out-of-range token (e.g. `◀18▶`) resolves to the literal `*`, not to a leftover marker — a short locString would write `GPS ±* m` into the doc.

Full slot map: [docs/firestore/update_table_row.md](../firestore/update_table_row.md).

## Usage example

Spec §7, the first consumer (home "Riwayat Absensi"), verbatim:

```json
{"type":"TIMELINE_CARD","vidtable":"20342033315492","table":"84214220504259//event","search":"grp◼attendance⭘cv◼87544551624342","sortField":"t","sortDir":"desc","limit":3,"moreRoute":"vertikaTeknoLokaciptaRiwayatAbsensi","row":"<t>◆<d>◆<i>, <lq>, <ln>◆GPS ±<acc> m","dotMap":"clock-in◼warn⭘clock-out◼info","chipField":"ty","chipMap":"clock-in◼Sedang Bekerja◼info⭘clock-out◼Sudah Clock Out◼muted","groupByDay":"TRUE","text":"Riwayat Absensi◆Lihat semua◆HARI INI◆Belum Absen◆Belum ada riwayat absensi"}
```

(`cv` in the live config is a `Settings!B1` ref, resolved per sheet-owning user.)

The `acc` field in `row` slot 3 stays blank until the **writer** config also carries the new token — append `⭘acc◼◀17▶` to the attendance `addToEvent` / `addToTable` line (`V146` / `V147`). Until then slot 3 simply hides itself.

Reuse with no Flutter change (spec §7):

- Driver trip timeline: `row:"<t>◆<d>◆<kn>◆<vv>"`, `chipMap:"mulai◼Dalam Perjalanan◼info⭘selesai◼Selesai◼ok"`.
- A full "Lihat Semua" page: the same widget with `limit:0` and `moreRoute:""` → an uncapped, day-grouped timeline.

## State / dependencies

- **State:** none of its own. Reactive read of the GetX `mapTableContent` `RxMap` ([`global.dart`](../../lib/global.dart)) inside an `Obx`. No Redux, no Bloc, no new controller, nothing added to `global.dart` / `global2.dart`.
- **Repository:** `subscribeToMapCollection` ([`table_repository.dart`](../../lib/firestore_repository/table_repository.dart)), keyed `appVid/tableDocId/subColl` so two tenants cannot collide.
- **Side effects:** the Firestore subscription, and `routeStack.push(route)` → `gotoRoute(route)` on the header link (in that order — the AppBar back button pops `routeStack`, not the Flutter Navigator). The link renders only when BOTH `text` segment 1 and `moreRoute` are present; a route that fails `routeExist` is a no-op tap.

## Tests

- [test/timeline_card_test.dart](../../test/timeline_card_test.dart) — all eight spec §8 cases, at two layers: pure (parsers, auto-hide, grouping, chip inference, with an injected `now`) and pump (which list feeds the chip, where separators land, `limit` cutting rendered rows, `moreRoute` gating the link).
- [test/gps_accuracy_token_test.dart](../../test/gps_accuracy_token_test.dart) — pins `◀17▶` through the REAL `getLocationString` → `saveSendRows` framing → `parseEventString` → `resolveValueTokens` chain.

## See Also

- [list_card.md](list_card.md) — the flat-card alternative; source of `parseLimit` / `applyLimit` / `resolveNoteTemplate`.
- [timeline_ledger.md](timeline_ledger.md) — the `TIMELINE` variant `ledger` (grouped + expandable audit timeline); a different widget, source of `formatEpochHHmm`.
- [docs/firestore/update_table_row.md](../firestore/update_table_row.md) — the `◀N▶` slot map, including `◀17▶`.
