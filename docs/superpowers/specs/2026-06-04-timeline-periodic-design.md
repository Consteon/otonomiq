# TIMELINE (variant `periodic`) — Patrol Point Visit Timeline — Design Spec

**Date:** 2026-06-04
**Status:** Built + reconciled to the authoritative dev spec `patrol-cleaning-timeline-dev-spec (1).md`.

> **Reconciliation (2026-06-04) — these override the sections below where they conflict:**
> 1. `{gap}` is **always** "Jeda N jam" (no jam→hari switch; dev spec §5.2).
> 2. `{method}` **always** appends " + foto" (dev spec §5.3) — `deriveMethod(String lq)` (no `hasImage` arg).
> 3. Event filter is **point + site**: `conditions` `[[◀ln▶◼<point>◁sv▷◼<site>]]` (field `sv` = the real event site-VID field). `filterEventsByConditions` now accepts white-triangle `◁…▷` markers too, and `list_statistic_card._onPointTap` dispatches `site` = the matched site doc's `sv`.
> 4. subtitle `{type}` is a **literal** in the JSON (e.g. `"Patroli · {visitCount} Kunjungan Periode Ini"`), not a computed token.

## Goal

Add the `periodic` variant of the server-driven `TIMELINE` component — the per-point
patrol **visit timeline** detail screen. It lists every patrol visit at one point as a
vertical timeline (newest first): colored status dot, time, evidence badge, who visited,
capture method, and the note; with "Jeda N jam" gap pills between far-apart visits, a
period selector, a header (point name + visit count), and a locked-note footer.

## Where it sits (navigation)

```
LIST_STATISTIC_CARD (per-point list)
  └─ tap a point card  →  route vertikaTeknoLokaciptaPatrolPointTimeline
        └─ page hosts  TIMELINE variant=periodic   ← THIS component
```

The card tap already dispatches the point context into `screenTx`; this component reads
`<point>` (the tapped point name) to filter its events.

## Component JSON (authoritative)

The updated LIST_STATISTIC_CARD now routes to this screen:
```json
{ "type":"LIST_STATISTIC_CARD", ..., "route":"vertikaTeknoLokaciptaPatrolPointTimeline" }
```

The new timeline component:
```json
{
  "type":"TIMELINE","variant":"periodic","flag":"timeline","ledgerCode":"event-patrol",
  "vidtable":"20342033315492",
  "table":"84214220504259//event",
  "search":"ln◼<point>",
  "conditions":"[[◀ln▶◼<point>◀ty▶◼report-patrol]]",
  "period":"24 jam◼86400000★7 hari◼604800000★30 hari◼2592000000",
  "periodDefault":"604800000",
  "title":"<ln>",
  "subtitle":"{visitCount} Kunjungan Periode Ini",
  "text":"<ts>◆oleh <cn>◆{method}◆<d>",
  "badge":"{evidence}",
  "divider":"{gap}"
}
```

## Confirmed data model (real Firestore `event` docs)

Path: `MobileTable/{appVid}/tables/{tableDocId}/event` (`appVid`=`vidtable`;
`tableDocId`=first `//`-segment of `table`). Each doc = one visit:
- `ln` — point name (the **join/filter key**, e.g. "Genset"/"BSD Tech Center #18")
- `cn` — worker / creator name (e.g. "Agus")
- `lq` — point QR id; **non-empty = QR-scanned, empty `""` = typed/GPS-only** (the fix
  from the qrScan widget guarantees `""` on manual entry)
- `t` — epoch ms; `ts` — stored formatted string ("04 Jun 2026 09:35:24")
- `ty` — type ("report-patrol")
- `d` — note / keterangan (e.g. "Patroli rutin")
- `i` — image URL (non-empty when a photo was attached)
- auto: `et`/`p`/`ev`

## Architecture & files (Approach A)

Mirror the LIST_STATISTIC_CARD pattern: map binding (`mapTableContent` +
`subscribeToMapCollection`), `Obx` render, period state. Pure logic in a tested support
file; the widget wires it to GetX/Flutter.

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/widget/timeline_periodic_support.dart` | Create | Pure: `relativeTimestamp`, `deriveMethod`/`MethodInfo`, `gapLabel`, `resolveAngleTokens`, `filterEventsByConditions`. Imports `statistic_card_support.dart` for `parsePeriods`/`PeriodOption`/`deriveEvidence`/`eventEpoch`. |
| `test/timeline_periodic_support_test.dart` | Create | TDD every helper. |
| `lib/widget/timeline_periodic.dart` | Create | `TimelinePeriodic` widget: subscribe `event`, period state, `Obx` render (header + tabs + timeline list + gap pills + footer), per-event token resolution. |
| `lib/widget/all_widget.dart` | Modify | Barrel — add `export 'timeline_periodic.dart';`. |
| `lib/widget/build_display_component.dart` | Modify | In the `tip=='timeline'` branch, route `variant=='periodic'` → `TimelinePeriodic`, else keep existing `Timeline`. |
| `lib/widget/list_statistic_card.dart` | Modify | `_onPointTap` also dispatches `'point': (point['ln'] ?? '').toString()` so `<point>` resolves on the timeline. |

**Reused (import, no change):** from `statistic_card_support.dart` — `parsePeriods`/
`PeriodOption`, `deriveEvidence`, `eventEpoch`; from `panel_card_support.dart` —
`statusColor`/`statusBgColor`/`normalizeStatus`/`resolveMapTokens`/`parseTablePath`/
`TablePath`/`splitPanelText` (or `diamondTextToList`); globals `mapTableContent`,
`subscribeToMapCollection`, `transactionStore`, `diamondTextToList`, `autheniumDecode`.

## Data binding, `<point>` resolution & filter

1. Subscribe the `event` subcollection: `subscribeToMapCollection(appVid, tableDocId,
   'event', '{tableDocId}/event')`.
2. Resolve `<point>` from `screenTx` (set by the card tap — see integration below).
3. Filter events by `conditions` `[[◀ln▶◼<point>◀ty▶◼report-patrol]]` — a **multi-field
   AND equality**: `event.ln == <point>` AND `event.ty == report-patrol`. `<point>` (and
   any `<key>`) resolves from `screenTx` first; a still-unresolved value → no match.
   (`search` `ln◼<point>` encodes the same `ln` filter; `conditions` is authoritative.)
4. Period tabs from `period`; default = option matching `periodDefault` (604800000 = 7
   hari). Window = `t ≥ now − selectedMs`. **Sort newest-first** (`t` desc).

### Integration — `list_statistic_card._onPointTap`

Add `'point': (point['ln'] ?? '').toString()` to the dispatched `ScreenTransaction`
(keep existing `pointId`/`pointName`/`point_route`). This sets `screenTx['point']` =
the tapped point's name, which `<point>` resolves against here.

## Token computation

**Header:** `title` `<ln>` resolves against `{'ln': screenTx['point']}` (fallback: first
filtered event's `ln`). `subtitle` `{visitCount}` = count of events in the window.

**Per event** (resolution doc = the event map with `ts` overridden to the relative
string; computed map = `{'method': <label>}`):
| Token | Rule |
|---|---|
| `<ts>` | `relativeTimestamp(t, now)`: same calendar day → `"HH:mm hari ini"`; yesterday → `"Kemarin HH:mm"`; else → `"N hari lalu"` (N = calendar-day diff) |
| `<cn>` | event `cn` |
| `{method}` | `deriveMethod(lq, i≠"")` → `lq` set → `"Scan QR"`, empty → `"Lokasi diketik"`; append `" + foto"` when `i` non-empty. `isQr` flag drives the row icon (QR vs text-cursor) |
| `<d>` | event note (rendered italic, quoted) |
| badge `{evidence}` | `deriveEvidence(lq)`: set → "Bukti kuat" (green), empty → "GPS saja" (amber) |
| dot color | from evidence: Bukti kuat → `statusColor('ok')` (green); GPS saja → `statusColor('warn')` (amber) |

The `text` `<ts>◆oleh <cn>◆{method}◆<d>` splits (on `◆`) into 4 slots →
`[0]`=time, `[1]`=by-line, `[2]`=method, `[3]`=note. The widget renders them into the
card layout (time+badge on row 1; by-line + method-with-icon on row 2; note on row 3).

**Gap divider `{gap}`** (between consecutive entries, sorted newest-first): for each
adjacent pair, `gapLabel(newerT, olderT, gapMs)` → gap < `gapMs` → `""` (no pill); else
`< 48h` → `"Jeda N jam"`, else `"Jeda N hari"`. The 48h jam→hari cutoff keeps a mid-range
gap like 30h shown in hours (per the design, which renders "Jeda 30 jam"). `gapMs` default
**43200000** (12h), configurable via `component['gapMs']`.

## Layout (matches the design)

- **Header**: title (point name, bold ~20) + subtitle (gray; renders the resolved
  `subtitle`, e.g. "4 Kunjungan Periode Ini").
- **Period tabs** (segmented, 24 jam / 7 hari / 30 hari), default 7 hari.
- **Timeline list** (newest first): a vertical line on the left with a colored status dot
  per entry; each entry a white card — row 1: `<ts>` (bold) + evidence badge pill (icon +
  label); row 2: "oleh `<cn>`" + method icon + `{method}`; row 3: `"<d>"` italic gray.
  Between two entries whose gap ≥ `gapMs`, a dashed "Jeda N jam" pill (amber) on the line.
- **Footer**: a dashed, lock-icon note box — text from `component['footer']` else the
  default: *"Catatan tak bisa diubah. Setiap kunjungan terkunci sejak dibuat. Sistem tidak
  menyajikan 'rata-rata' atau 'frekuensi normal' — itu bisa dibaca sebagai standar."*
- Empty state (no events in window): a centered "Belum ada kunjungan" message.

## Support-file API (pure, testable)

```text
// reused from statistic_card_support.dart: PeriodOption, parsePeriods, deriveEvidence, eventEpoch

String relativeTimestamp(int tMs, int nowMs)   // "HH:mm hari ini" / "Kemarin HH:mm" / "N hari lalu"

class MethodInfo { final String label; final bool isQr; const MethodInfo(this.label, this.isQr); }
MethodInfo deriveMethod(String lq, bool hasImage)

String gapLabel(int newerT, int olderT, int gapMs)   // "" / "Jeda N jam" / "Jeda N hari"

String resolveAngleTokens(String raw, Map<String,dynamic> screenTx)  // <key> -> screenTx[key]

List<Map<String,dynamic>> filterEventsByConditions(
    List<Map<String,dynamic>> events, String rawConditions, Map<String,dynamic> screenTx)
```

`relativeTimestamp` uses the device clock (`DateTime.fromMillisecondsSinceEpoch`,
`intl` `DateFormat('HH:mm')`); compares local calendar days. `filterEventsByConditions`
parses `[[◀field▶◼value…]]` into AND-equalities, resolving `<key>` values from `screenTx`;
empty conditions → unchanged; an unresolvable `<…>` value → no match.

## Build-scoped work (perf)

Inside `Obx`: read `mapTableContent[eventCode]`; compute `nowMs`, `windowStartMs`;
`filterEventsByConditions` → window-filter → sort desc once. Per-entry token resolution is
O(1); gap computed from adjacent sorted pairs.

## Testing

`test/timeline_periodic_support_test.dart` — TDD: `relativeTimestamp` (today/Kemarin/
N-hari boundaries, using mid-day epochs to avoid tz edge flakiness), `deriveMethod` (QR/
typed × with/without image), `gapLabel` (< threshold → ""; jam vs hari), `resolveAngleTokens`
(`<point>` from screenTx, unknown left literal), `filterEventsByConditions` (ln AND ty match;
`<point>` resolution; unresolved → empty; empty conditions → unchanged). Widget verified
manually against the design + tenant `84214220504259`.

## Documented defaults (locked)

- `gapMs` = 12h, configurable via `component['gapMs']`.
- `relativeTimestamp` uses device clock + local calendar days; older entries show no time.
- `{method}` appends " + foto" only when `i` is non-empty.
- Status dot + badge both derive from evidence (Bukti kuat → green, GPS saja → amber).
- Footer text = `component['footer']` else the default Indonesian lock-note.
- `{visitCount}`, sort, and the timeline are window-scoped; newest first.
- `title` `<ln>` from `screenTx['point']`, fallback first event `ln`.
- Multi-condition filter supports **equality only**, AND-combined.

## Out of scope

- The page wrapper / AppBar ("Detail Titik") — server-driven, defined in Sheets/proxy.
- Any change to the existing `timeline.dart` (comment/commentbox/timeline variants).
- `flag`/`ledgerCode` are server metadata, not consumed by the widget. **`vidtable` (app
  VID) is REQUIRED** — `_subscribe` early-returns without it and the screen stays on the
  empty state (same contract as every sibling component).
- `badge`/`divider` are presentational tokens — the widget renders the evidence badge and
  gap pill directly from the computed `{evidence}`/`{gap}` values, so editing those two
  templates server-side has no effect. `search` is redundant with `conditions` and unused.

## Self-review

- **Placeholders:** none — every token, helper signature, and default is concrete.
- **Consistency:** `lq`-empty drives evidence, method, and dot uniformly; `ln` is the sole
  join key; period/window rules match the card.
- **Scope:** one widget + one support file + three small edits (dispatch, barrel, card tap)
  — one plan.
- **Ambiguity:** `<ts>` is explicitly the computed relative string (not the raw `ts` field);
  gap is between adjacent sorted pairs; `visitCount`/sort are window-scoped — all stated.
