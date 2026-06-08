# LIST_STATISTIC_CARD — Patroli & Cleaning Point Detail — Design Spec

**Date:** 2026-06-03
**Status:** Approved (design). Next: implementation plan (writing-plans).

## Goal

Add a new server-driven UI component type **`LIST_STATISTIC_CARD`** — the per-point
detail screen for one cost center's **Patroli & Cleaning** activity. It lists every
patrol/cleaning point of a cost center as a card showing last-visit recency, who
visited, visit count in a selectable time window, an evidence badge, and a status
strip; above the list sit a period selector and three summary stat boxes.

## Where it sits (navigation)

```
LIST_MULTIPLE_PANEL_CARD (cost-center list)
  └─ tap "Patroli & Cleaning" panel  →  route patroliCleaningPerSite
        └─ page hosts  LIST_STATISTIC_CARD   ← THIS component
              └─ tap a point card  →  route patroliCleaningPointTimeline  (future, out of scope)
```

The front card (`ListMultiplePanelCard._onPanelTap`) already dispatches `ccVid` (= site
doc `<av>`) into `transactionStore` / `screenTx`. This component reads `{ccVid}` back to
self-filter.

## Component JSON (authoritative, from server)

```json
{
  "type": "LIST_STATISTIC_CARD",
  "ledgerCode": "site",
  "vidtable": "20342033315492",
  "table": "84214220504259//site",
  "search": "av◼{ccVid}",
  "conditions": "[[◀av▶◼{ccVid}]]",
  "text": "Cari titik◆Ketik nama titik◆Data tidak ditemukan",
  "period": "24 jam◼86400000★7 hari◼604800000★30 hari◼2592000000",
  "periodDefault": "86400000",
  "stats": "{totalVisits}◆Total kunjungan★{noVisitCount}◆Titik tanpa kunjungan★{typedCount}◆Lokasi diketik",
  "content": "<ln>◆{type}◆Terakhir {lastAgo} · {lastBy}◆{visits} kunjungan dalam {period}",
  "status": "{ps}",
  "badge": "{evidence}",
  "route": "patroliCleaningPointTimeline"
}
```

## Confirmed data model

Path for all subcollections: `MobileTable/{appVid}/tables/{tableDocId}/{subColl}`
(`appVid` = `vidtable`; `tableDocId` = first `//`-segment of `table`).

- **`site` doc** (char-code map; one per cost center): `an` cc name, `sn` site name,
  `av` cc VID, `sv` site VID, `nm` headcount, `ll` = **array of point objects**.
  - **`ll[]` point object:** `ln` (point name), `li` (QR id), `la`/`lo` (lat/lng),
    `ra` (radius m).
- **`event` doc** (char-code map; one per visit): `ln` (point name — the join key),
  `cn` (worker / creator name), `lq` (point QR id; **empty string `""` when location
  was typed manually, non-empty when QR-scanned**), `t` (epoch ms), `ty` (type, e.g.
  `report-patrol`), plus auto-injected `et`/`p`/`ev`.

**Join:** `event['ln'] == point['ln']` (by point name). `lq` is used only to derive
evidence/typed, NOT as the join key.

## Architecture & files (Approach A)

Mirror the `ListMultiplePanelCard` pattern: map binding (`mapTableContent` +
`subscribeToMapCollection`), `Obx` render, custom router (`routeStack.push` +
`gotoRoute`). All branching/decision logic in a pure, fully-unit-tested support file;
the widget only wires helpers to GetX/Redux/Flutter.

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/widget/statistic_card_support.dart` | Create | Pure logic: period/stats parse, event-by-ln index, per-point aggregation, ago-humanizer, type/evidence/status derivation, summary, cc filter. Imports shared helpers from `panel_card_support.dart`. |
| `test/statistic_card_support_test.dart` | Create | TDD for every pure helper. |
| `lib/widget/list_statistic_card.dart` | Create | `ListStatisticCard` StatefulWidget: config parse, subscribe site+event, period state, `Obx` render (period tabs + stat boxes + searched, status-sorted point list), per-point nav. |
| `lib/widget/all_widget.dart` | Modify | Barrel — add `export 'list_statistic_card.dart';`. |
| `lib/widget/build_display_component.dart` | Modify | Dispatch branch `else if (tip == 'list_statistic_card')`. |

**Reused from `panel_card_support.dart` (import, no change to that file):**
`statusColor`, `statusBgColor`, `normalizeStatus`, `worstStatus`, `statusOrder`,
`parseTablePath` / `TablePath`, `resolveMapTokens`. Plus globals
`mapTableContent` (`global.dart`), `subscribeToMapCollection` (`table_repository.dart`),
`diamondTextToList` / `autheniumDecode` / `routeExist` / `routeStack` / `gotoRoute`
(`global.dart`), `transactionStore` / `UpdateScreenTxAction` / `ScreenTransaction`.

## Data binding & cost-center filter

1. Subscribe two subcollections (keys mirror the sibling):
   - site: `subscribeToMapCollection(appVid, tableDocId, subColl, '{tableDocId}/{subColl}')`
   - event: `subscribeToMapCollection(appVid, tableDocId, 'event', '{tableDocId}/event')`
2. Resolve `{ccVid}` from `screenTx` (`transactionStore.state.screenTx['ccVid']`).
3. Filter `site` docs to the **one** where `doc['av'].toString() == ccVid`
   (encoded by both `conditions` `[[◀av▶◼{ccVid}]]` and `search` `av◼{ccVid}`).
   - Support helper parses `field◼value` and `[[◀field▶◼value]]`, resolves `{...}`
     tokens from `screenTx`, applies **equality on a char-code field**. Equality only
     (YAGNI). If no doc matches → empty state.
4. **List items = the matched site doc's `ll[]` array** (each object → one point card).
5. In-card search box filters points by `<ln>` substring (hint = `text[0]`,
   empty-state = `text[2]`).

## Period window

- Parse `period`: `autheniumDecode` then `split('★')`, each entry `split('◼')` →
  `PeriodOption(label, ms)`. Render as a segmented control.
- Initial selection = the option whose `ms == int(periodDefault)`, else first option.
- Tapping a tab → `setState(selectedMs)` → full recompute.
- **Window** = events with `t ≥ now − selectedMs`. `{period}` token = selected label.

## Per-point token computation

For each point, `events = eventsByLn[point['ln']] ?? []`; `latest` = event with max
`t` (over ALL time, not just window). Resolve via `resolveMapTokens(pointMap, computed)`
so `<ln>` reads the point object and `{...}` reads the computed map.

| Token | Source / rule |
|-------|---------------|
| `<ln>` | point name (char-code from the `ll` object) |
| `{type}` | `deriveType(latest.ty)`: contains `patrol` → `"PATROLI"`, contains `clean` → `"CLEANING"`, else `ty.toUpperCase()`. No event → `""`. (Current data: all `report-patrol` → PATROLI; the patrol/cleaning split is intentionally not special-cased.) |
| `{lastAgo}` | `humanizeAgo(now − latest.t)`: `< 60 min` → `"N menit lalu"` (`< 1 min` → `"Baru saja"`); `< 24 h` → `"N jam lalu"`; else `"N hari lalu"`. No event → `"Belum pernah"`. |
| `{lastBy}` | `latest.cn`. No event → `""`. |
| `{visits}` | count of `events` with `t ≥ windowStart` (in selected period). |
| `{period}` | selected period label. |
| `{evidence}` | `deriveEvidence(latest.lq)`: non-empty → `"Bukti kuat"`, empty → `"GPS saja"`. No event → `""` (badge hidden). |
| `{ps}` | `{visits} == 0` → **`danger`**; else if `(now − latest.t ≥ staleMs)` OR `latest.lq == ""` → **`warn`**; else **`ok`**. |

`staleMs` default **43200000** (12 h), configurable via `component['staleMs']`. Fixed
threshold (not period-relative).

## Summary stats (over all points of the cc, in the window)

| Token | Rule |
|-------|------|
| `{totalVisits}` | count of all events (across the cc's points) with `t ≥ windowStart`. |
| `{noVisitCount}` | count of points with `{visits} == 0` in the window. |
| `{typedCount}` | count of events in the window with `lq == ""` (typed/manual). |

`stats` parse: `split('★')`, each `valueTemplate◆label` `split('◆')`; resolve
`valueTemplate` against the computed stats map.

## Layout (matches the supplied design image)

- **Period tabs** (segmented, full width).
- **Three stat boxes** in a row: box 0 (`{totalVisits}`) neutral white; boxes ≥ 1
  green-tint when the resolved value is `"0"`, amber-tint otherwise. Big number +
  label under it.
- **Point list**, sorted **status severity desc** (danger → warn → ok via
  `statusOrder` rank), then **oldest-first** within a group (`latest.t` ascending →
  larger `lastAgo` first). Flat list — NO accordion headers.
- **Point card:** `Material` white, radius ~16, soft shadow, `IntrinsicHeight` row:
  - Left strip width ~6, color `statusColor({ps})`.
  - Row 1: `<ln>` bold ~18 + ` · ` + `{type}` gray uppercase ~13 (ellipsis) … `Spacer`
    … **evidence badge** pill + `chevron_right`.
  - Row 2: `"Terakhir {lastAgo} · {lastBy}"`, weight ~600, **tinted `statusColor({ps})`
    when warn/danger, gray when ok**.
  - Row 3: `"{visits} kunjungan dalam {period}"` gray ~13.
  - **Evidence badge:** `"Bukti kuat"` → green bg/text + shield-check icon;
    `"GPS saja"` → amber bg/text + warning icon; empty → hidden. (Map evidence → status:
    Bukti kuat = ok, GPS saja = warn, for color via `statusColor`/`statusBgColor`.)
- **Tap** a card → dispatch `{ pointId: li, pointName: ln, ccVid: <passthrough>,
  point_route: route }` into `screenTx`; if `routeExist(route)` → `routeStack.push(route)`
  + `gotoRoute(route)`.

## Support-file API (pure, testable)

```text
class PeriodOption { String label; int ms; }
List<PeriodOption> parsePeriods(String raw)

class StatSpec { String template; String label; }
List<StatSpec> parseStatSpecs(String raw)

String humanizeAgo(int deltaMs)                 // menit/jam/hari lalu; deltaMs<0 → "Baru saja"
String deriveType(String ty)                    // PATROLI/CLEANING/uppercase/""
String deriveEvidence(String lq)                // "Bukti kuat"/"GPS saja"
Map<String, List<Map<String,dynamic>>> eventsByLn(List<Map<String,dynamic>> events)

class PointStat { String type, lastAgo, lastBy, evidence, ps; int visits; bool hasEvent; }
PointStat computePointStat(
    Map<String,dynamic> point, List<Map<String,dynamic>> events,
    int nowMs, int windowStartMs, int staleMs)

class StatsSummary { int totalVisits, noVisitCount, typedCount; }
StatsSummary computeStatsSummary(
    List<dynamic> points, Map<String,List<Map<String,dynamic>>> byLn,
    int nowMs, int windowStartMs)

// cost-center filter (equality on a char-code field, screenTx-token resolved)
String resolveScreenTxTokens(String raw, Map<String,dynamic> screenTx)
List<Map<String,dynamic>> filterByCharCodeEquality(
    List<Map<String,dynamic>> docs, String rawConditions, Map<String,dynamic> screenTx)
```

`computePointStat` maps to the token map `{type,lastAgo,lastBy,visits,evidence,ps}`;
`computeStatsSummary` to `{totalVisits,noVisitCount,typedCount}`. The widget feeds these
into `resolveMapTokens` for `content` / `stats` / `status` / `badge`.

## Build-scoped indexing (perf)

Inside `Obx` (for reactivity), once per build:
`_nowMs = now`, `_windowStartMs = now − selectedMs`,
`_byLn = eventsByLn(mapTableContent[eventCode])`. Per-point compute is then
O(events-at-point); the summary is one extra pass. Reads both `mapTableContent[siteCode]`
and `mapTableContent[eventCode]` inside `Obx` so live Firestore updates re-render.

## Testing

`test/statistic_card_support_test.dart` — TDD each helper: `parsePeriods`
(incl. `autheniumDecode`/malformed), `parseStatSpecs`, `humanizeAgo` (menit/jam/hari
boundaries, negative), `deriveType`, `deriveEvidence`, `eventsByLn`,
`computePointStat` (no-event → danger/"Belum pernah"; old-event-outside-window →
danger but last-ever shown; stale → warn; GPS-only → warn; recent+QR → ok),
`computeStatsSummary` (totalVisits/noVisitCount/typedCount), `filterByCharCodeEquality`
(token resolution + equality + no-match). Widget verified manually against the design
image + live tenant `84214220504259`.

## Documented defaults (locked)

- `staleMs` = 12 h, configurable via `component['staleMs']`; fixed, not period-relative.
- No-event point → `ps=danger`, `lastAgo="Belum pernah"`, `lastBy=""`, badge hidden.
- Point with events but none in the window → `visits=0` → `danger`; last-ever info still
  shown in row 2.
- `{typedCount}` counts **events** (visits) with empty `lq`, not distinct points.
- Stat box color: box 0 neutral; boxes ≥ 1 green when value `"0"` else amber.
- cc filter supports **equality only** on a char-code field.
- Point list flat (no status accordions), sorted severity-desc then oldest-first.

## Out of scope

- The `patroliCleaningPerSite` page wrapper JSON (server-driven, defined in Sheets/proxy).
- The `patroliCleaningPointTimeline` per-point timeline screen (likely reuses
  `timeline.dart`; separate work).
- Any change to `panel_card_support.dart` or the existing `ListMultiplePanelCard`.

## Self-review

- **Placeholders:** none — every token, helper signature, and default is concrete.
- **Consistency:** join key (`ln`) used uniformly; `lq` only for evidence/typed; status
  rule referenced identically in the per-point table, the status section, and defaults.
- **Scope:** single component + one support file + two registration edits — one plan.
- **Ambiguity:** `lastAgo`/`lastBy`/`evidence`/`type` use latest-ever event; `visits`/
  `danger`/stats use the window — stated explicitly to avoid the two readings.
