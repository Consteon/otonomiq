# StatCardRow (`STAT_CARD_ROW`)

Horizontal row of N stat number-cards from ONE keyed Firestore cache document.

- **File:** [lib/widget/stat_card_row.dart](../../lib/widget/stat_card_row.dart)
- **Class:** `StatCardRow` (StatefulWidget)
- **Status:** draft (Dart renderer) -- deploy-coupled: inert until a screen JSON references `type:"STAT_CARD_ROW"`
- **Widget version:** v1
- **Dev spec:** `stat-card-row-widget-dev-spec.md`

## Purpose

Renders a row of number-cards where each card shows a large number (from a precomputed doc field) and a label (from config). Fills the gap where DETAIL_CARD (key-value table) is forced into a stat-counter role and looks wrong. Read-only, no buttons, no actions.

## Signature / Constructor

```dart
StatCardRow({
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
| `cards` | String | yes | `Label◼field◼tone★...` card definitions |
| `highlight` | String | no | Field name whose card gets emphasis border |
| `text` | String | no | Empty-state text when doc not found |

### Tone vocabulary

`ok` (green) · `warn` (amber) · `danger` (red) · `accent` (blue) · `muted` (grey). Unknown falls back to `muted` + WARN log.

## Config rules

- **A label must NOT contain `◼` (U+25FC).** Card entries are parsed positionally — split on `★` (U+2605) into entries, then each entry split on `◼` into `label◼field◼tone`. An extra `◼` inside a label shifts `field` and `tone` by one segment (e.g. `Batch◼siap◼bt◼ok` → label `Batch`, field `siap`, tone `bt`; `bt` is not a known tone so it normalizes to `muted`). Keep labels `◼`-free.
- **Config fields are `autheniumDecode`d** (`cards`, `highlight`, `text`) before parsing; the server may send `◼`/`⭘` as `_25FC_`/`_2B58_`. `search` is stored RAW because `filterDriverHomeDocs` decodes internally — same as DetailCard.
- **Unknown/typo tone** is normalized to `muted` once at parse time (`initState`), not per rebuild.

## Important Behavior

- **Keyed read engine:** identical to DetailCard (`subscribeToMapCollection` + `filterDriverHomeDocs`).
- **Field absent in doc:** renders `0` (not blank, not crash).
- **Empty state (0 docs matched):** renders `text` config line, hides all cards. With no cards configured at all, renders nothing.
- **Highlight:** matching card gets 2px tone-color border + tinted bg. Others get 1px light-grey border + white bg.
- **Dynamic card count:** changing `cards` in the sheet (adding/removing entries) takes effect without deploy.
- **Wrap overflow:** 5+ cards flow to a second line via `Wrap` + `LayoutBuilder`.

## See Also

- [detail_card.md](detail_card.md) -- keyed single-doc detail (KV rows, gallery)
- [list_card.md](list_card.md) -- keyed multi-doc list
