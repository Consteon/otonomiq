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
| `text` | `String` | no | -- | Diamond-separated entry body. `<charcode>` from doc, `{method}`/`{evidence}` from computed. |
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
