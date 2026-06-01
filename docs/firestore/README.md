# Firestore Table Operations

Dokumentasi untuk operasi CRUD pada Firestore dynamic tables (`MobileTable`).

## Operation Index

| Operation | File | Status | Description |
|---|---|---|---|
| writeToTable (add) | — | existing (belum didokumentasikan) | Menambah row baru ke dynamic/array/summary table |
| updateTableRow | [update_table_row.md](update_table_row.md) | done | Update sebagian kolom pada row di dynamic table |
| deleteFromTable | [delete_from_table.md](delete_from_table.md) | done | Hapus row dari dynamic table berdasarkan search query |
| addToEvent | [add_to_event.md](add_to_event.md) | done | Tulis dokumen event keyed ke collection bernama (tambahan, selain Event spreadsheet) |

## Arsitektur

Semua operasi tabel (add, update, delete) melalui **history queue pipeline** yang sama, sehingga mendukung offline:

```
Server JSON (component)
     │
     ├── addToTable       ─┐
     ├── updateTableRow   ─┤ digabungkan ke tableString via separator[0] (⬤)
     └── deleteFromTable  ─┘ Format: addStr⬤updateStr⬤deleteStr
                              │
                              ▼
                    saveSendRows → appendToSheet → SubmitBloc
                              │
                              ▼
                    addNewSubmit2 → historyAdd (local history queue)
                              │
                              ▼
                    historySync (saat online)
                         │ split eventHistory[14] by separator[0]
                         │
                         ├── tbParts[0] (addStr)    → writeToTable()    → addContent()
                         ├── tbParts[1] (updateStr) → updateTableRow()  → updateContent()
                         └── tbParts[2] (deleteStr) → deleteFromTable() → deleteContent()
                                                                              │
                                                                              ▼
                                                                         Firestore
                                                                    MobileTable/{vid}/tables/{name}/content/{id}
```

## Dispatch Points

| Source | File | Penggabungan |
|---|---|---|
| `saveSend()` | `lib/api.dart` | Pre-decode updateString/deleteString, gabungkan ke `tableString` via `separator[0]`, kirim ke `saveSendRows` |
| `checkerSaveData` | `lib/widget/ftz_checker.dart` | Gabungkan raw strings ke `checkerTableString` via `separator[0]`, kirim ke `appendToSheet` |

## Tipe Tabel

| Type | Code | Supported Operations |
|---|---|---|
| Dynamic | `tt='D'` | add, update, delete |
| Array/Static | `tt='A'` | add only |
| Summary | `tt='S'` | add only |
