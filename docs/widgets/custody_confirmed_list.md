# custody_confirmed_list

| field | value |
|---|---|
| file | `lib/widget/custody_confirmed_list.dart` |
| dispatch | `custody_confirmed_list` |
| status | draft |

## Purpose

P7 read-only list of driver-confirmed items. Reads `ip[]` from the opening
vehicle_check doc, JOINs item names from the item subcollection. Renders per
item: name, category chip, qty, green checkmark -- inside a grouped white card
with an eyebrow section title and theme-aware summary count pill. Optionally
renders a "next-step" hint footer card below the grouped card when text
slots 3-4 are provided.

## Component JSON

| key | type | required | notes |
|---|---|---|---|
| `table` | string | yes | vehicle_check path |
| `search` | string | yes | opening doc search with curly tokens |
| `joinTable` | string | yes | item subcollection path |
| `text` | string | no | diamond-separated label slots |
| `actualField` | string | no | default `ip` |
| `vidtable` | string | no | explicit appVid |
| `com` | string | no | tenant container |

### Text slots

| index | default | description |
|---|---|---|
| 0 | `Yang Dikonfirmasi` | section title (eyebrow) |
| 1 | `returnable` | category label: returnable |
| 2 | `consumable` | category label: consumable |
| 3 | *(empty)* | hint label (e.g. `Selanjutnya`); uppercased in widget |
| 4 | *(empty)* | hint body (e.g. `Mulai eksekusi task hari ini, dimulai dari stop 1.`) |

## Subscriptions

- `vehicle_check` via `table` + `subscribeToMapCollection`
- `item` via `joinTable` + `subscribeToMapCollection`

## Visual Layout (v2 redesign)

1. **Eyebrow row** -- section title (text slot 0) left-aligned, summary count
   pill (`"N item"`) right-aligned. Pill uses theme-aware HSLColor derived from
   `Theme.of(context).primaryColor` (matches `otq_bottom_nav_bar.dart` pattern).
2. **Grouped card** -- single white rounded card (borderRadius 16, subtle dual
   shadow, 1px border), containing item rows separated by inset hairline
   dividers (indent 50, not after last row).
3. **Item row** -- check_circle_rounded icon (green), item name (15px w600),
   optional neutral gray category chip, right-aligned qty (18px w700 green).
4. **Next-step hint footer** -- optional; rendered only when text slot 3 or 4
   is non-empty. Theme-tinted container (hintBg/hintBorder from primaryColor
   HSL), left icon chip (arrow_forward_rounded in hintIconBg/hintAccent), right
   column with uppercased label (slot 3, hintAccent) and body text (slot 4).
   Gap 14px below grouped card.
5. **Loading** -- `CircularProgressIndicator` (unchanged).
6. **Empty** -- `Text('--')` (unchanged).

## See Also

- `custody_reveal.md` (writes ip[])
- `custody_discrepancy_list.md` (reads dp[])
