# receipt_doc

**File:** `lib/widget/receipt_doc.dart`
**Type key:** `RECEIPT_DOC`
**Status:** draft

## Purpose

Read-only on-screen nota (receipt) card. Reads one nota document by search,
renders scalar fields by config-driven field names, loops `li[]` array into
line rows, and looks up the depo header from a second table.

## Config Fields

| Field | Type | Description |
|-------|------|-------------|
| `table` | string | Nota collection path (`84214220504259//nota`) |
| `vidtable` | string | App VID for subscription |
| `search` | string | Search condition (`nno◼{nno}`) |
| `headerTable` | string | Header collection path (`84214220504259//stock_location`) |
| `headerSearch` | string | Header search condition (`lv◼{gl}`) |
| `headerNameField` | string | Field name for depo name (`ln`) |
| `headerAddrField` | string | Field name for depo address (`al`) |
| `headerName` | string | Literal header name (e.g. "Gudang Bintaro"). When BOTH `headerName` and `headerAddr` are non-empty, the widget uses these literals and skips the `headerTable` Firestore lookup |
| `headerAddr` | string | Literal header address. See `headerName` |
| `noField` | string | Doc field for nota number |
| `buyerField` | string | Doc field for buyer name |
| `buyerEmpty` | string | Fallback when buyer is empty |
| `dateField` | string | Doc field for date. Use `t` (epoch-ms) for the formatted `08 Jul 2026 09:39`; a preformatted string field (`ts`) is tolerated and shown verbatim |
| `paymentField` | string | Doc field for payment method |
| `statusField` | string | Doc field for status badge |
| `totalField` | string | Doc field for total amount |
| `linesField` | string | Doc field for line items array |
| `lineNameField` | string | Line item name field |
| `lineQtyField` | string | Line item quantity field |
| `linePriceField` | string | Line item unit price field |
| `lineSubField` | string | Line item subtotal field |
| `money` | string | Money format locale. Only `id` (dot-thousands) implemented; formatting is currently hardcoded to `id` regardless of this value (YAGNI — add locale switch when a second locale exists) |
| `text` | string | Diamond-separated labels (7 indexes) |

## text[] Layout

| Index | Content | Fallback |
|-------|---------|----------|
| 0 | Title | `NOTA` |
| 1 | No. label | `No.` |
| 2 | Date label | `Tanggal` |
| 3 | Buyer label | `Pembeli` |
| 4 | Payment label | `Bayar` |
| 5 | Total label | `TOTAL` |
| 6 | Footer text | (empty) |

## Data Path

Reactive `subscribeToMapCollection` + `Obx` on `mapTableContent`. Same
idiom as `worker_card_detail_keyed.dart`.

## See Also

- `ftz_bluetooth_printer.dart` — PRN keyed (same data source, print output)
- `nota_create_submit.dart` — writes the nota doc and sets `{nno}` token
- `worker_card_detail_keyed.dart` — sibling keyed read-only card pattern
