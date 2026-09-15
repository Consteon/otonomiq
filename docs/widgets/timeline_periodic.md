# TimelinePeriodic

Config-driven event timeline widget (TIMELINE variant `periodic`). Renders a period-selectable, newest-first vertical timeline of event docs from a Firestore map collection, with status dots, badge chips, gap pills, image galleries, and a configurable footer.

- **File:** [lib/widget/timeline_periodic.dart](../../lib/widget/timeline_periodic.dart)
- **Class:** `TimelinePeriodic` (StatefulWidget)
- **Support:** [lib/widget/timeline_periodic_support.dart](../../lib/widget/timeline_periodic_support.dart)
- **Status:** draft
- **Widget version:** v1
- **Dispatch:** `tip == 'timeline'` + `tlVariant == 'periodic'` in `build_display_component.dart:1215-1228`

## Purpose

Renders a scrollable vertical timeline of event documents (e.g. patrol visits, audit logs, status histories) from a Firestore `event` or similar subcollection. Default behavior derives `{method}` and `{evidence}` computed tokens from a configurable doc field (default `lq`). Generic reuse substitutes `<charcode>` tokens and optional `statusField` coloring.

## `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `String` | yes | -- | `"TIMELINE"` |
| `variant` | `String` | yes | -- | `"periodic"` |
| `vidtable` | `String` | yes | -- | App VID for Firestore subscription |
| `table` | `String` | yes | -- | `"<tableDocId>//<subColl>"` (e.g. `"84214220504259//event"`) |
| `search` | `String` | yes | -- | Search/equality filter (e.g. `"ln◼<point>"`) |
| `conditions` | `String` | yes | -- | Multi-field AND filter: `"[[◀field▶◼value...]]"`. Tokens `<key>` resolve from screenTx. |
| `period` | `String` | yes | -- | Period tabs: `"label◼ms★label◼ms★..."` (autheniumDecode applied) |
| `periodDefault` | `String` | no | first tab | Default selected period in ms |
| `gapMs` | `String` | no | `"43200000"` (12h) | Gap threshold in ms for "Jeda N jam" pills |
| `title` | `String` | no | -- | Title template. `<charcode>` tokens resolve from doc map. |
| `subtitle` | `String` | no | -- | Subtitle template. `{visitCount}` = count of windowed events. |
| `text` | `String` | no | -- | Diamond-separated entry body. `<charcode>` from doc, `{method}`/`{evidence}` from computed. A ◆-segment whose tokens ALL resolve empty is blanked — see "Empty-segment blanking". |
| `badge` | `String` | no | `"{evidence}"` | Badge chip template. `<charcode>` from doc, `{evidence}` from computed. Empty result = no chip. |
| `divider` | `String` | no | -- | Gap pill template. `{gap}` = "Jeda N jam". |
| `image` | `String` | no | -- | Image field template. `<charcode>` from doc. Multi-image (space/diamond separated). |
| `evidenceField` | `String` | no | `"lq"` | Doc field name feeding `deriveMethod()`/`deriveEvidence()`. |
| `statusField` | `String` | no | -- (absent) | Doc field for dot/badge color. Value normalized: `ok`/`warn`/`danger` use status colors; unknown/empty = neutral gray. Absent = patrol-mode evidence-based coloring. |
| `empty` | `String` | no | `"Belum ada kunjungan"` | Empty-state text when no events match the window. |
| `footer` | `String` | no | locked-note default | Footer text. Value `"-"` = footer not rendered. Empty/absent = default patrol note. |
| `flag` | `String` | no | -- | General-purpose flag (unused by widget logic, passed through) |

## Token resolution

Templates in `text`, `badge`, `title`, `subtitle`, `image` resolve in two passes via `resolveMapTokens()`:

1. **Angle-bracket `<charcode>`**: replaced by `doc[charcode].toString()`. Missing key = empty string.
2. **Curly-brace `{key}`**: replaced from a computed map. Unknown key = left as literal.

Computed tokens always available:
- `{method}` -- "Scan QR + foto" or "Lokasi diketik + foto" (derived from `evidenceField`)
- `{evidence}` -- "Bukti kuat" or "GPS saja" (derived from `evidenceField`)
- `{visitCount}` -- number of events in the active period window
- `{gap}` -- "Jeda N jam" gap label

## Empty-segment blanking (`text` only)

A `text` segment whose tokens **all** resolve empty renders as an empty slot instead of as its bare punctuation. Without it, an event doc missing `pvo`/`sd`/`du` renders `<pvo> → <sd> (+<du> m³)` as the literal `" →  (+ m³)"`.

- **Always on** for variant `periodic`. There is **no config key** — the builder's only action is to widen `conditions` (e.g. drop a `ty` clause) and let more event types through.
- A segment with **no token at all** (static label, static punctuation) is never touched.
- "Token" means both dialects `resolveMapTokens` handles: `<field>` from the doc, and `{key}` when `key` is one of the computed tokens. `{method}` / `{evidence}` are never empty, so a segment carrying one never blanks. A `{key}` the widget does not compute is left literal by `resolveMapTokens`, so it counts as visible text, not a token.
- A doc value that is whitespace-only counts as empty.
- **BLANKED IN PLACE, never dropped.** `_buildEntry` is a fixed-slot layout — `at(0)` title, `at(1)`+`at(2)` one gray row, `at(3)` the italic note. Dropping a segment would slide the note into `at(2)`, which is `maxLines: 1` with ellipsis.
- `badge` and `image` are NOT affected: `badge` is already gated on `resolvedBadge.isNotEmpty`, `image` on `_splitImages`, which skips blanks. `title` / `subtitle` are single strings, not ◆-segmented.
- Implemented as `resolveHidingEmptySegments` in `timeline_periodic_support.dart`. It is scoped to this variant on purpose: `resolveMapTokens` itself is shared by thirteen other widgets and is NOT changed.
- Zero-regression is structural **for a template separated by real `◆` only**. Whether any live tenant config mixes the two separator forms is **unverified** — the proxy config was unreadable from the machine this was built on, so read the ⚠ below as a live limitation, not a theoretical one. (Evidence it is at least plausible: the sibling `timeline_ledger.dart` `autheniumDecode`s every template key precisely because the server encodes `◆` as `_u25C6_`, `global.dart` records two escape forms, and `timeline_periodic.dart` reads `component['text']` raw.) The helper splits the RAW template, resolves each segment, and re-joins with `blackDiamond` before the existing `diamondTextToList` call, so with nothing blanked the string reaching `diamondTextToList` is byte-identical to before, and a doc value containing a `◆` still expands into extra slots.
- ⚠ **Known divergence: a template that MIXES a real `◆` with a literal `_u25C6_`, plus a `"` in any resolved value.** `diamondTextToList` has two paths — its `jsonDecode` path honours `_u25C6_`, its `catch` fallback is a plain `split('◆')` that does not. A value that breaks `jsonDecode` — a quote, an INVALID escape such as `\d`, or a raw control char — throws into that fallback; realistically the officer's free-text note. A VALID escape like `\n` does **not** throw, so `\` alone is not the trigger. The old code saw the `_u25C6_` as literal text there; the helper has already turned it into a separator. Consequence: **one extra segment**, so a later slot can fall past `at(3)` and never render — `_buildEntry` renders exactly four. Pinned as-is by `a MIXED-separator template with a quoted value is a KNOWN divergence` in `test/timeline_periodic_support_test.dart`; it documents what happens, NOT what is wanted.
  - A **uniformly** `_u25C6_`-escaped template under the same trigger is an **improvement**, not a regression: the old code collapsed the whole row into one garbage segment showing the literal escapes, the helper renders the four intended slots. Do not "restore" it.
  - Not fixed in the helper on purpose: matching the old output would mean copying `diamondTextToList`'s own internal inconsistency into it, and the real root — one quote in one data value re-segmenting the string for **every** widget that calls `diamondTextToList` — is a pre-existing, app-wide bug and a separate change.

## Icon gating

- **Method icon** (qr_code_2 / text_fields on entry row 2): rendered ONLY when `text` template contains `{method}`.
- **Shield icons** (verified_user / gpp_maybe on badge chip): rendered ONLY when `badge` template contains `{evidence}` (including the absent-fallback case).

## Coloring rules

| `statusField` | Dot + badge color source |
|---|---|
| Absent | Patrol mode: `evidence == 'Bukti kuat'` -> ok (green), else -> warn (amber) |
| Present, value `ok`/`warn`/`danger` | `statusColor()`/`statusBgColor()` for that status |
| Present, unknown/empty value | Neutral gray (foreground `#6B7280`, background `#F3F4F6`) |

## Backward compatibility

Live patrol JSON (`badge:"{evidence}"`, `text:"<ts>...{method}..."`, no `evidenceField`/`statusField`/`empty`) renders pixel-identical to the pre-refactor widget. All new config keys have safe defaults that preserve patrol behavior.

## See Also

- Support functions: `lib/widget/timeline_periodic_support.dart` (relativeTimestamp, deriveMethod, gapLabel, resolveAngleTokens, filterEventsByConditions, resolveStatusColor, resolveStatusBgColor, badgeContainsEvidence, textContainsMethod)
- Shared helpers: `lib/widget/panel_card_support.dart` (resolveMapTokens, statusColor, statusBgColor, normalizeStatus)
- Shared helpers: `lib/widget/statistic_card_support.dart` (deriveEvidence, eventEpoch, parsePeriods, PeriodOption)
- Sibling widget docs: [list_statistic_card.md](list_statistic_card.md), [list_multiple_panel_card.md](list_multiple_panel_card.md)
