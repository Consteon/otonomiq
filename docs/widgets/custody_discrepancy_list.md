# custody_discrepancy_list

| field | value |
|---|---|
| file | `lib/widget/custody_discrepancy_list.dart` |
| dispatch | `custody_discrepancy_list` |
| status | draft |

## Purpose

P8 read-only discrepancy list. Reads `dp[]` from the opening vehicle_check
doc. Renders a section title, a summary strip (`N item selisih · X kurang ·
Y lebih`, counted from `dp[]`), then one card per item: name + Kurang/Lebih
severity pill, left severity accent bar (amber=Kurang / violet=Lebih), and a
stat strip `Gudang → Hitung … Selisih` with a big color-coded signed delta.

## Component JSON

| key | type | required | notes |
|---|---|---|---|
| `table` | string | yes | vehicle_check path |
| `search` | string | yes | opening doc search |
| `joinTable` | string | yes | item subcollection path |
| `text` | string | no | diamond-separated label slots (9 slots): [0] title · [1] Gudang · [2] Hitung · [3] Selisih · [4] Kurang · [5] Lebih · [6] item selisih · [7] kurang · [8] lebih |
| `discrepancyField` | string | no | default `dp` |
| `vidtable` | string | no | explicit appVid |
| `com` | string | no | tenant container |

## Subscriptions

- `vehicle_check` via `table`
- `item` via `joinTable`

## See Also

- `custody_reveal.md` (writes dp[])
- `custody_confirmed_list.md` (reads ip[])
