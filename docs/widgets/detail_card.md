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
| `rows` | String | no | `Label◼template★...` key-value rows |
| `hideEmptyRows` | String | no | `TRUE` (default) or `FALSE` |
| `images` | String | no | `◆`-separated `<field>` templates of image URLs |
| `imageLabels` | String | no | `◆`-separated captions per image slot |
| `text` | String | no | notFoundText when doc not found |

## Important Behavior

- **Numeric-tolerant search:** via `filterDriverHomeDocs` -> `filterByMultiClause` -> `eq()` (dsl_eq.dart). Numeric field values match regardless of String/num type.
- **Numeric-first `<15>` keys NOT supported (v1):** template tokens must be letter-first `<field>` (shared `resolveMapTokens` regex `<[a-zA-Z][a-zA-Z0-9]*>`). Numeric-first keys like `<15>` (spec rule 5, collection-indexed reads) render literally (unresolved); deferred until an indexed-collection migration needs them.
- **Empty optional = hidden:** subtitle, rows, gallery all auto-hide when their resolved content is empty.
- **hideEmptyRows = TRUE (default):** rows with empty resolved template are skipped. When FALSE, empty rows show `-`.
- **Gallery tap:** opens `FullScreenImageView` (pinch-zoom, single image).

## See Also

- [list_card.md](list_card.md) -- sibling universal list renderer
- [workspace_header.md](workspace_header.md) -- keyed detail (id/title/address only)
- [item_card_detail.md](item_card_detail.md) -- positional detail (indexed collections)
