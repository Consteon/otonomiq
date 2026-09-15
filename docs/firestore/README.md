# Firestore Table Operations

Dokumentasi untuk operasi CRUD pada Firestore dynamic tables (`MobileTable`).

## Operation Index

| Operation | File | Status | Description |
|---|---|---|---|
| writeToTable (add) | — | existing (belum didokumentasikan) | Menambah row baru ke dynamic/array/summary table |
| updateTableRow | [update_table_row.md](update_table_row.md) | done | Update sebagian kolom pada row di dynamic table |
| deleteFromTable | [delete_from_table.md](delete_from_table.md) | done | Hapus row dari dynamic table berdasarkan search query |
| addToEvent | [add_to_event.md](add_to_event.md) | done | Tulis dokumen event keyed ke collection bernama (tambahan, selain Event spreadsheet) |
| updateEventRow | [update_event_row.md](update_event_row.md) | done | keyed sparse merge of an existing keyed doc |
| publishLedger | [publish_ledger.md](publish_ledger.md) | done | Publish pesan JSON ke pub-sub-gateway (HTTPS, bukan Firestore) lewat outbox terpisah |

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
                         ├── tbParts[0] (addStr)    → writeToTable()    → addContent()    ─┐
                         ├── tbParts[1] (updateStr) → updateTableRow()  → updateContent() ─┤ Firestore
                         ├── tbParts[2] (deleteStr) → deleteFromTable() → deleteContent() ─┤ MobileTable/{vid}/tables/{name}/content/{id}
                         ├── tbParts[3] (eventStr)  → writeToEvent()                      ─┤
                         ├── tbParts[4] (updEvStr)  → writeUpdateEventRow()               ─┘
                         └── tbParts[5] (publish)   → enqueueLedgerPublish()
                                                          │  _LEDGER_OUTBOX (secure storage)
                                                          ▼
                                                    drainLedgerOutbox()
                                                          │
                                                          ▼
                                                    POST pub-sub-gateway
                                                    (NOT Firestore — see publish_ledger.md)
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
