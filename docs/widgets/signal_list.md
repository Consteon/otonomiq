# SignalList (`SIGNAL_LIST`)

Generic "obligation-at-risk" signal card list: one Firestore row = one card telling an operator that something needs a human follow-up. Case-agnostic -- Reorder Radar (customers who stopped ordering) and Service AC (assets overdue for maintenance) run the same code with different JSON.

- **File:** [lib/widget/signal_list.dart](../../lib/widget/signal_list.dart)
- **Support (pure parsers):** [lib/widget/signal_list_support.dart](../../lib/widget/signal_list_support.dart)
- **Tests:** [test/signal_list_support_test.dart](../../test/signal_list_support_test.dart)
- **Class:** `SignalList` (StatefulWidget)
- **SDUI type:** server sends `SIGNAL_LIST`; the dispatch chain lowercases it, so the branch literal is `signal_list`
- **Status:** draft
- **Widget version:** v1 + REV2 (aging compute)

## Purpose

A signal card list, not an analytics view. It answers "who needs attention right now?" and its entire behavioural surface is: **tap the card -> go to the detail screen.** Anything richer (contacting the customer, editing a cadence, creating a task) belongs on that detail screen.

**Two modes:**

- **Display-only** (`agingTimeField` empty): the source doc already carries a status and a days-since number. The widget displays them.
- **Aging mode** (`agingTimeField` set): the widget **computes** `ds` (days-since) and `st` (tier) at render time from `lo` (epoch ms) and `cad` (cadence) fields in the doc. No cron, no server refresh needed -- status is always current at render time.

Use `LIST_CARD` instead when you need a plain data list with stats boxes and accordions.

## Doctrine -- three rules the code enforces

1. **Amber, never red.** `tone: danger` is FORCED to `warn` by an explicit guard in `resolveSignalTone`. Red is reserved for engineering failure; an operational signal is amber. This is unit-tested -- a red can never be reached, even by a misconfigured sheet.
2. **Silence is the success state.** Rows that do not match `search` simply do not appear. An empty list renders a green reassurance (`text` segment 6), not an error or a grey "no results found".
3. **The card navigates and nothing else.** No inline write, no bottom sheet, no cadence editor, no chart.

## Signature / Constructor

```dart
SignalList({
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

All separators are server-encoded and `autheniumDecode`-d before splitting: `◼` (`_25FC_`), `⭘` (`_2B58_`), `★` (entry separator), `◆` (`text` segment separator).

| Key | Description | Empty => |
|---|---|---|
| `vidtable` | Tenant vid for the vid-scoped subscription key (`resolveAppVid`). | falls back to `getTableVid(component['com'])` |
| `table` | Keyed collection `{tableDocId}//{subColl}` (e.g. `84214220504259//reorder_cache`). **Required.** | nothing renders |
| `search` | WHERE DSL `field◼value⭘field2◼value2`; `{token}` resolved from screenTx. **Fail-closed** -- see gotchas. | no server filter |
| `sort` | `field◼asc\|desc`. Numeric-coerced. May use `{ds}` or `{st}` (brace-stripped to `ds`/`st`). | arrival order |
| `groupField` | Field to section by. May use `{st}` (brace-stripped). | flat list |
| `statusField` | Row key whose value selects the status entry. May use `{st}` (brace-stripped). Defaults to `st` when aging mode is ON and empty. | no pill, neutral tone |
| `statusMap` | `value◼Label◼tone★value2◼Label2◼tone2`. `tone` in `warn` \| `ok` \| `accent` \| `neutral`. **`danger` is silently forced to `warn`.** Order defines section order. **In aging mode, also acts as the visibility filter** -- tiers not listed are hidden. | no pill, neutral tone |
| `agingTimeField` | Doc field holding epoch ms of last activity (e.g. `lo`). **Non-empty = aging mode ON.** | display-only mode (v1) |
| `cadenceField` | Doc field holding cadence value (e.g. `cad`). **NOT `cd`** -- `cd` = condition, a different field. | required when aging ON |
| `cadenceUnit` | `hari` or `bulan`. `bulan` multiplies cadence by 30. | `hari` |
| `attentionFraction` | Fresh boundary: `ds <= cadDays * f`. | `0.8` |
| `dormantMultiplier` | Dormant boundary: `ds > cadDays * m`. | `3.0` |
| `gapsField` | Row key holding the array of past gaps (mini-timeline). | timeline skipped |
| `markerField` | Row key holding the current "days since" number (mini-timeline marker). | timeline skipped |
| `route` | Destination route on tap. | card not tappable, ripple off |
| `routeParams` | `key◼{field}⭘key2◼{field2}` -- resolved row-first, then session; dispatched as **bare** screenTx keys on the destination page. | no params written |
| `text` | **All 8 labels in one field, `◆`-joined.** See below. **Required.** | everything hidden |

### `text` -- 8 segments, read BY POSITION

```
<title>◆<subtitle>◆<metric>◆<meta>◆<actionLabel>◆<emptyText>◆<searchHint>◆<listTitle>
```

| Spec # | Array index | Role | Scope | Tokens? |
|---|---|---|---|---|
| 1 | `[0]` | card title | per-card | `<field>` doc, `{ds}`/`{st}` computed |
| 2 | `[1]` | card subtitle | per-card | same |
| 3 | `[2]` | metric (big bold line) | per-card | same |
| 4 | `[3]` | meta (small line) | per-card | same |
| 5 | `[4]` | action button label | per-card | same (usually literal) |
| 6 | `[5]` | empty-state text | list-level | no (never normalised) |
| 7 | `[6]` | search hint | list-level | no (never normalised) |
| 8 | `[7]` | list title | list-level | no (never normalised) |

**Token syntax:**

- **Angle `<field>`** resolves from the row doc (e.g. `<cn>`, `<cad>`).
- **Curly `{ds}` / `{st}`** resolves from the computed aging values (aging mode only, segments 1-5 only). The widget normalises them to angle tokens in `_initConfig`, so `resolveMapTokens` handles both uniformly.
- **An unresolvable token renders as NOTHING**, not as the literal token (see gotchas).
- `{field}` in `routeParams` is a different mechanism (row-first then session resolve) and is NOT normalised.
- `{word}` in segments 6-8 is NOT normalised (those segments never pass through `_resolve`) and would render literally.

## Aging mode (REV2)

When `agingTimeField` is set, the widget computes `ds` and `st` at render time:

```
cadDays = cad * (cadenceUnit == "bulan" ? 30 : 1)
ds = floor((now() - lo) / 86400000)
st = tier(ds, cadDays, attentionFraction, dormantMultiplier):
     ds <= cadDays * attFraction   -> "fresh"
     ds <= cadDays                 -> "approaching"
     ds <= cadDays * dormantMult   -> "overdue"
     ds >  cadDays * dormantMult   -> "dormant"
```

### Skip rules

- `lo` empty/missing/non-numeric/<=0/future -> card **skipped** (`never_ordered` tier is CUT; future epoch = clock skew or ms-vs-seconds confusion).
- `cad` empty/missing/non-numeric/<=0 -> card **skipped** (broken cadence; a config-time `devPrint` fires when `cadenceField` itself is empty).
- Computed `st` not in `statusMap` -> card **hidden** (`statusMap` = visibility filter). This is how `fresh` customers are hidden: omit `fresh` from `statusMap`.

### Backward compatibility

When `agingTimeField` is empty (the default), aging mode is OFF. No augmentation, no tier computation, unmapped status renders with no badge. **No v1 config breaks.**

### `cd` is NOT cadence

The Reorder Radar CF stores cadence as `cad`, not `cd`. The field `cd` means "condition" -- a different field entirely. Using the wrong field name silently produces wrong tiers: no error, no crash, just every customer in the wrong bucket.

## Anatomy

```
[LIST TITLE]                 text 8      (hidden if empty)
[SEARCH BAR]                 text 7      (hidden if empty; matches RESOLVED title+subtitle)
[SECTION HEADER]             groupField  (flat if empty; label from statusMap, raw value if unmapped)
 +-+----------------------------------------------+
 |#|  title                         [ pill ]      |  text 1 . statusMap label
 |#|  subtitle                                    |  text 2
 |#|  .  7h  .  6h  .  8h  .--- 24h --- o        |  gapsField + markerField
 |#|  metric                                      |  text 3 (pill-text color)
 |#|  meta                                        |  text 4
 |#|  ----------------------------------------    |
 |#|  [            action             ]           |  text 5 -> route
 +-+----------------------------------------------+
   ^ 4px tone accent bar
[EMPTY STATE]                text 6      (green reassurance, when 0 rows)
```

**The empty state also fires when the SEARCH BAR matches nothing.** Word `text` segment 6 so it does not read as an absolute guarantee. If that matters for a tenant, keep segment 7 (`searchHint`) empty so no search bar renders at all.

## Tone -> colour (design spec)

| `tone` | accent (bar / dot / dash) | pill bg | pill text (also metric + section header) | card tint |
|---|---|---|---|---|
| `warn` | `dangerBorder` #F59E0B | `dangerBadgeBg` #FEF3C7 | `dangerBadgeText` #B45309 | `dangerBg` #FFF7E6 |
| `ok` | `okActionGreen` #15803D | `okBadgeBg` #DCFCE7 | `okActionGreen` #15803D | white |
| `accent` | `okAction` #2563EB | `iconTileBg` #EAF1FF | `okAction` #2563EB | white |
| `neutral` | `mutedText` #9CA3AF | `normalBadgeBg` #F1F5F9 | `normalBadgeText` #475569 | white |
| `danger` | **forced -> the `warn` row** | | | |
| unknown / missing | **-> the `neutral` row** | | | |

**THE PALETTE TRAP.** `AdminTierColors` token names do NOT match the spec's `tone` names. Its `danger*` family is AMBER (#F59E0B) and its `warn*` family is VIOLET (#7C3AED). Use `signalToneColors()`; never touch the tokens directly, and never use `statusColor`/`statusBgColor` from `panel_card_support.dart` (those map `danger` to red).

## Reused machinery (no reinvention)

`resolveAppVid` + `parseTablePath` + `subscribeToMapCollection` (vid-scoped subscription), `filterDriverHomeDocs` (`search` DSL), `coerceNum` (sort), `resolveMapTokens` (angle tokens), `groupByField` (sections), `writeRouteParamsFromRow` (routeParams), `stripRouteWrapper`, `routeExist` + `routeStack` + `gotoRoute` (navigation), `autheniumDecode` + `diamondTextToList` (config), `AdminTierColors` (palette).

Pure parsers in `signal_list_support.dart`: `signalTextSegment`, `parseSignalStatusMap`, `lookupSignalStatus`, `resolveSignalTone`, `signalToneColors`, `parseSignalGaps`, `formatSignalGapValue`, `parseSignalSort`, `computeSignalDaysSince`, `computeSignalCadenceDays`, `computeSignalTier`.

## Example configs -- same widget, zero code difference

### Reorder Radar (bottled water, aging mode)

```json
{"type":"SIGNAL_LIST","vidtable":"20342033315492","table":"84214220504259//reorder_cache","search":"","agingTimeField":"lo","cadenceField":"cad","cadenceUnit":"hari","attentionFraction":"0.8","dormantMultiplier":"3.0","sort":"{ds}◼desc","groupField":"{st}","statusMap":"overdue◼Telat order◼warn★dormant◼Lama menghilang◼warn","route":"vertikaTeknoLokaciptaReorderCustomer","routeParams":"rc◼{rc}","text":"<cn>◆<cp>◆{ds} hari belum order◆biasa tiap <cad> hari◆Follow up◆Semua pelanggan dalam ritme — aman◆Cari nama◆Radar Reorder"}
```

### Service AC (assets, aging mode, bulan cadence)

```json
{"type":"SIGNAL_LIST","vidtable":"20342033315492","table":"84214220504259//asset","search":"","agingTimeField":"lo","cadenceField":"cad","cadenceUnit":"bulan","attentionFraction":"0.8","dormantMultiplier":"3.0","sort":"{ds}◼desc","groupField":"{st}","statusMap":"overdue◼Servis lewat◼warn★dormant◼Lama tak servis◼warn","route":"vertikaTeknoLokaciptaServiceAssetDetail","routeParams":"as◼{as}","text":"<al>◆<cn> · <mk>◆{ds} hari sejak servis◆servis tiap <cad> bln◆Jadwalkan◆Semua unit terawat◆Cari unit◆Aset Perlu Servis"}
```

> **Both examples come from dev spec REV2 section 4.** `vidtable: "20342033315492"` is confirmed correct. The `table` right-hand sides (`reorder_cache`, `asset`) are **not yet verifiable**: as of 2026-08-06 neither exists in Firestore (the Go Cloud Function has not shipped), so the sub-collection names and every `<field>` token in `text` come from the dev spec, not from real documents. Re-check against one real doc once the CF lands.

## Notes / gotchas

- **`search` is FAIL-CLOSED.** An unresolved `{token}` or a literal-empty clause value yields an EMPTY list, not "show all". A screen whose `search` uses a `{token}` must have that token populated in screenTx *before* this widget renders.
- **Search bar matches RESOLVED title + subtitle** -- the operator searches what they can see.
- **Search text resets when you leave the page** -- local widget `State`, no static store, no `clearData` hook.
- **Unmapped status in display-only mode => no pill**, card renders with neutral tone (v1 behavior). **Unmapped computed tier in aging mode => card HIDDEN** (`statusMap` = visibility filter). This is how `fresh` customers are excluded: omit `fresh` from `statusMap`.
- **Aging ON + empty `statusMap` hides EVERY card** and renders the green "all clear" reassurance. This is the worst failure mode for a risk-surfacing widget: a misconfiguration looks like "everything is fine". A `devPrint` fires at config time naming the problem. Always map at least one tier when aging mode is ON.
- **Aging ON + empty `cadenceField`** skips every card (cadence cannot be computed). A `devPrint` fires at config time naming the missing key.
- **`groupField` rows with an empty group value are NOT lost.** `groupByField` drops them; this widget recovers them and renders them last, under no section header.
- **Section order follows `statusMap` order**; unlisted group values append at the bottom in grey.
- **Mini-timeline needs both `gapsField` and `markerField`**, both resolving non-empty. Code stays from v1; configure it OFF by leaving both empty.
- **Timeline unit is `h`, not " hari".** If a configurable suffix is ever needed, append `text` segment 9.
- **`vidtable` matters, and getting it wrong fails SILENTLY.** The table-group id `84214220504259` exists under two appVids simultaneously. Always set `vidtable` explicitly.
- **`cd` is NOT `cad`.** `cd` = condition, `cad` = cadence. Using the wrong field name produces silently wrong tiers.
- **Computed `ds`/`st` shadow pre-existing doc fields.** If a doc already has a `ds` or `st` field, the computed value wins in aging mode. In display-only mode, doc fields are read directly as before.
- **An unresolvable `<field>` renders as NOTHING**, not as the literal token (`resolveMapTokens` replaces missing keys with empty string). Check token spelling first if a card line looks truncated.
- **`{word}` normalisation is segments 1-5 only.** Segments 6-8 are list-level literals that never pass through `_resolve`. A `{X}` in segment 6-8 renders literally, not as a computed value.

## See Also

- [list_card.md](list_card.md) -- the universal keyed list; use it when you need stats boxes, accordions or a plain data list.
- [coordination_signal_list.md](coordination_signal_list.md) -- the Admin H1 signal list. Different widget: it *derives* signals from 5 collections and performs inline writes. `SIGNAL_LIST` reads one pre-derived projection and only navigates.
