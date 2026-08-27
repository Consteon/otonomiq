# DetailCard (`DETAIL_CARD`)

Universal config-driven single keyed-doc detail renderer -- title + badge + N key-value rows + optional photo gallery. Sibling of LIST_CARD (same "universal reader" package).

- **File:** [lib/widget/detail_card.dart](../../lib/widget/detail_card.dart) . support: [lib/widget/list_card_support.dart](../../lib/widget/list_card_support.dart)
- **Class:** `DetailCard` (StatefulWidget)
- **Status:** draft (Dart renderer) -- deploy-coupled: inert until a screen JSON references `type:"DETAIL_CARD"`
- **Widget version:** v1
- **Introduced on branch:** `feat/list-card-universal`
- **Dev spec:** `detail-card-universal-dev-spec.md`

## Purpose

Renders a single Firestore keyed document (resolved by search filter) as a detail card. Every display string comes from config (no hardcoded labels). Every optional field left empty = that element is not rendered (card shrinks itself). Read-only: no buttons, no actions, no navigation.

Fills the gap where ITEM_CARD_DETAIL (positional-only) and WORKSPACE_HEADER (keyed but id/title/address only) cannot show arbitrary keyed doc fields.

## Signature / Constructor

```dart
DetailCard({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

| Key | Type | Required | Description |
|---|---|---|---|
| `vidtable` | String | no | App vid for vid-scoped subscription key |
| `table` | String | yes | Keyed collection `{tenant}//name` |
| `search` | String | yes | Resolve ONE doc: `key◼{token}` |
| `title` | String | no | Template with `<field>` tokens |
| `subtitle` | String | no | Template; empty = hidden |
| `note` | String | no | Optional display line template with `<field>` tokens. Empty = hidden. If any token resolves empty/missing, the whole line is hidden. If the note does not appear, check the token spelling first — a misspelled `<field>` is hidden exactly like an unstamped one. |
| `badgeField` | String | no | Doc field for badge value |
| `badgeMap` | String | no | `value◼Label◼tier★...` (tier: danger/warn/ok/neutral) |
| `rows` | String | no | `★`-separated rows, two shapes: `Label◼template` (literal label + resolved value) OR `template` with NO `◼` (label-less: the RESOLVED value is split at the LAST `" \| "` into title + value; no `" \| "` = plain value row) |
| `hideEmptyRows` | String | no | `TRUE` (default) or `FALSE` |
| `images` | String | no | `◆`-separated `<field>` templates of image URLs |
| `imageLabels` | String | no | `◆`-separated label per `images` template (positional) |
| `images2` | String | no | OPTIONAL second photo group: `◆`-separated `<field>` templates, stacked BELOW `images` |
| `imageLabels2` | String | no | `◆`-separated label per `images2` template (positional) |
| `text` | String | no | notFoundText when doc not found |

## Important Behavior

- **Numeric-tolerant search:** via `filterDriverHomeDocs` -> `filterByMultiClause` -> `eq()` (dsl_eq.dart). Numeric field values match regardless of String/num type.
- **Numeric-first `<15>` keys NOT supported (v1):** template tokens must be letter-first `<field>` (shared `resolveMapTokens` regex `<[a-zA-Z][a-zA-Z0-9]*>`). Numeric-first keys like `<15>` (spec rule 5, collection-indexed reads) render literally (unresolved); deferred until an indexed-collection migration needs them.
- **Empty optional = hidden:** subtitle, rows, gallery all auto-hide when their resolved content is empty.
- **hideEmptyRows = TRUE (default):** rows with empty resolved template are skipped. When FALSE, empty rows show `-`.
- **Gallery tap:** opens `FullScreenImageView` (pinch-zoom, single image).
- **Photo label blocks:** `images`+`imageLabels` and `images2`+`imageLabels2` are concatenated into ONE ordered template list with positionally aligned labels. Consecutive templates carrying the SAME label (including consecutive EMPTY labels) merge into one block; each block renders as a label header line (omitted when the label is empty) plus ONE horizontally scrollable strip of 90x90 thumbnails. A thumbnail carries no caption of its own. `images2` empty/absent = exactly one block, so existing pages need no config change. A block whose templates all resolve empty is hidden, header included. Merging requires the equal labels to be CONSECUTIVE: `imageLabels: "X◆Y◆X"` yields THREE blocks `X`, `Y`, `X` — two of them carrying the same header. That is the specified behaviour, not a bug.
- **Two `◆`-family separators, do not confuse them:** the CONFIG fields (`images`, `imageLabels`, `images2`, `imageLabels2`, `rows`) are split on `◆` (BLACK diamond, `separator[1]`) / `★`. The runtime VALUE of a single photo field holding several urls is joined with `◇` (WHITE diamond, `separator[5]` = `whiteDiamond`, the `processData` joiner in `init_values.dart`) and unpacked by `splitImageUrls`. `stringCleanUp` deliberately exempts `◇` from its forbidden-character sweep so multi-photo values survive save.
- **Two row constructs, separated on sight:** labelled rows (`Label◼<f>`) are a key/value TABLE — secondary-grey key in a 120px column, primary-dark value beside it. Label-less rows are a LIST of results — primary-dark title, secondary-grey `w600` 12px tag right-aligned. The first labelled → label-less transition draws a divider and a wider gap, so the two conventions never read as one table that inverts halfway down.
- **Text colours are contrast-measured, not picked by eye:** `#374151` primary (10.3:1 on white), `#6B7280` secondary (4.83:1). `Colors.grey.shade500` was replaced because it measures 2.68:1, under the WCAG AA 4.5:1 floor for normal text. Do not reintroduce a `grey.shadeNNN` here without measuring it.
- **Label-less row split:** a `rows` entry with no `◼` is a TEMPLATE with an empty label. The resolved value is split at the **last** `" | "` (space-pipe-space) — last, not first, so a title containing a pipe stays intact; both sides are trimmed. An UNSPACED `|` is a literal character and does not split. This is the shape `CHECKLIST_DYNAMIC` writes per slot (`'<title> | <status>'`). Under `hideEmptyRows:TRUE` an unfilled `<ckN>` renders nothing.

## See Also

- [list_card.md](list_card.md) -- sibling universal list renderer
- [workspace_header.md](workspace_header.md) -- keyed detail (id/title/address only)
- [item_card_detail.md](item_card_detail.md) -- positional detail (indexed collections)
