# deleteFromTable — Hapus Data dari Firestore Dynamic Table

Fitur untuk menghapus row dari Firestore dynamic table (tipe `D`) berdasarkan query search.

- **File utama:** [lib/firestore_repository/table_repository.dart](../../lib/firestore_repository/table_repository.dart)
- **Controller:** [lib/states/mobile_table_controller.dart](../../lib/states/mobile_table_controller.dart)
- **Dispatch dari:** [lib/api.dart](../../lib/api.dart) (saveSend), [lib/widget/ftz_checker.dart](../../lib/widget/ftz_checker.dart) (checkerSaveData)
- **Status:** done
- **Tipe tabel:** Hanya `D` (Dynamic)

## Format Input dari Server

### Component JSON key

```json
{
  "deleteFromTable": "<input string>"
}
```

### Input String Format

```
<tableName>⭘tablevid◼<vid>⭘search◼<field>★<value>
```

Lebih simpel dari `updateTableRow` — hanya butuh nama tabel, vid, dan search criteria. Tidak perlu kolom content.

### Contoh

```
$test/agenia-demo-7//vtl.attendance-check-in⭘tablevid◼20342033315492⭘search◼3★87544551624342
```

Artinya: hapus semua row di tabel `vtl.attendance-check-in` dimana indexed field `3` bernilai `87544551624342`.

## Flow

```
component['deleteFromTable']
     │
     ▼
saveSend / ftz_checker (decode + placeholder substitution)
     │ gabungkan ke tableString via separator[0] (⬤)
     │ Format: addStr⬤updateStr⬤deleteStr
     ▼
saveSendRows → appendToSheet → SubmitBloc → addNewSubmit2
     │ simpan ke local history queue
     ▼
historySync (saat online)
     │ split eventHistory[14] by separator[0]
     │ tbParts[2] = deleteStr
     ▼
deleteFromTable(deleteStr, eventRowString)
     │ splitTableInput → extract tableName, tablevid, search
     ▼
MobileTableController.deleteContent(tableName, searchField, searchValue)
     │ Firestore: query → delete each match → shift header checksum
     ▼
Row(s) deleted, UI rebuilds via header listener
```

> **Offline-capable:** Operasi delete di-buffer di local history queue dan diproses saat device online, mengikuti flow yang sama dengan `addToTable`.

### Perbedaan dengan updateTableRow

| Aspek | updateTableRow | deleteFromTable |
|---|---|---|
| Posisi di separator[0] | tbParts[1] | tbParts[2] |
| Perlu `parseTableInput` | Ya (untuk resolve placeholders di value) | Tidak (hanya butuh search) |
| Field `<n>` | Wajib (kolom yang diupdate) | Tidak ada |
| Operasi Firestore | `doc.reference.update()` | `doc.reference.delete()` |
| Return value | `"OK N updated"` | `"OK N deleted"` |

## Error Handling

| Kondisi | Return |
|---|---|
| Input null/empty | `[]` |
| Field `search` tidak ada | `"Error: missing search"` |
| Tabel tidak ditemukan | `"Error: table not found"` |
| Tabel bukan tipe D | `"Error: delete only supported for dynamic tables (tt=X)"` |
| Tidak ada match | `"Error: no match for field=value"` |
| Sukses | `"OK N deleted"` |

## Catatan

- **Offline-capable** — operasi delete masuk ke local history queue dan diproses oleh `historySync` saat device online. Tidak lagi fire-and-forget.
- **Separator[0] (⬤)** — delete string berada di posisi ke-3 (tbParts[2]) dalam gabungan `addStr⬤updateStr⬤deleteStr`.
- **Backward compatible** — history record lama tanpa separator[0] tetap berfungsi karena split menghasilkan single element.
- **Multiple matches dihapus semua** — jika query mengembalikan >1 dokumen, semuanya dihapus.
- **Header checksum tetap di-shift** — memicu UI rebuild meskipun operasinya delete.

## See Also

- [update_table_row.md](update_table_row.md) — fitur update row (lebih detail tentang separator, placeholder, dan parsing)
