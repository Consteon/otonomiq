# updateTableRow — Update Data di Firestore Dynamic Table

Fitur untuk meng-update sebagian kolom pada row yang sudah ada di Firestore dynamic table (tipe `D`), tanpa menimpa kolom lain yang tidak diubah.

- **File utama:** [lib/firestore_repository/table_repository.dart](../../lib/firestore_repository/table_repository.dart)
- **Controller:** [lib/states/mobile_table_controller.dart](../../lib/states/mobile_table_controller.dart)
- **Dispatch dari:** [lib/api.dart](../../lib/api.dart) (saveSend), [lib/widget/ftz_checker.dart](../../lib/widget/ftz_checker.dart) (checkerSaveData)
- **Status:** done
- **Tipe tabel:** Hanya `D` (Dynamic) — tabel dengan subcollection `content/`

## Gambaran Umum

```
Server JSON → component['updateTableRow']
     │
     ▼
saveSend() / ftz_checker
     │ decode + placeholder substitution
     │ gabungkan ke tableString via separator[0] (⬤)
     ▼
saveSendRows → appendToSheet → SubmitBloc → addNewSubmit2
     │ simpan ke local history queue
     ▼
historySync (saat online)
     │ split eventHistory[14] by separator[0]
     │ tbParts[0]=addStr, tbParts[1]=updateStr, tbParts[2]=deleteStr
     ▼
updateTableRow(updateStr, eventRowString)
     │ parse input → identify search + columns to patch
     ▼
MobileTableController.updateContent()
     │ Firestore query (where) → patch matching docs
     │ auto-detect indexed fields dari existing document
     ▼
Firestore: row updated, header checksum shifted
     │
     ▼
subscribeToTable listener → UI rebuild
```

> **Offline-capable:** Operasi update di-buffer di local history queue dan diproses saat device online, mengikuti flow yang sama dengan `addToTable`.

## Format Input dari Server

### Component JSON key

```json
{
  "updateTableRow": "<input string>"
}
```

### Input String Format

```
<tableName>⭘tablevid◼<vid>⭘search◼<field>★<value>⭘<col1>◼<newValue1>⭘<col2>◼<newValue2>
```

#### Separator yang digunakan

| Karakter | Unicode | Nama | Fungsi |
|---|---|---|---|
| `⬤` | `\u{2B24}` | Black circle (separator[0]) | Pemisah operasi: addStr⬤updateStr⬤deleteStr |
| `⭘` | `\u{2B58}` | White hollow circle (separator[8]) | Pemisah antar field |
| `◼` | `\u{25FC}` | Black square (separator[2]) | Pemisah key=value |
| `★` | `\u{2605}` | Black star (separator[3]) | Pemisah dalam search (field★value) |
| `◆` | `\u{25C6}` | Black diamond (separator[1]) | Pemisah antar tabel (jika multi-table) |
| `◀` | `\u{25C0}` | Black left triangle | Buka placeholder |
| `▶` | `\u{25B6}` | Black right triangle | Tutup placeholder |

#### Field-field dalam input

| Field | Wajib | Deskripsi |
|---|---|---|
| Position 0 (table name) | Ya | Nama tabel, format: `$folder//tableName` |
| `tablevid` | Tidak | Override application table VID. Default = `appCodeController.applicationTableVid` |
| `search` | Ya | Kriteria pencarian: `<indexedField>★<value>`. Menentukan row mana yang di-update |
| `<n>` | Ya (min. 1) | Kolom yang akan di-update. `n` = nomor kolom 1-based. Value = nilai baru |

### Contoh Nyata dari Server

```
$test/agenia-demo-7//vtl.attendance-check-in⭘tablevid◼20342033315492⭘search◼3★87544551624342⭘<5>◼test update
```

Artinya:
- **Tabel:** `$test/agenia-demo-7//vtl.attendance-check-in`
- **TableVid:** `20342033315492`
- **Search:** field index `3` yang bernilai `87544551624342`
- **Update:** kolom `5` diubah menjadi `"test update"`

## Placeholder Substitution

Placeholder di-resolve sebelum string dikirim ke `updateTableRow`:

### Placeholder `◀n▶` (event data)

| Placeholder | Sumber |
|---|---|
| `◀1▶` sampai `◀14▶` | `ref[0][n-1]` — 14 kolom pertama dari event row |
| `◀15▶` dst | `ref[1][n-15]` — kolom extended dari event row |

### Placeholder `◀n\|format▶` (formatted)

| Contoh | Deskripsi |
|---|---|
| `◀2\|T7\|Ddd MMM yyyy HH:mm:ss▶` | Format timestamp dari ref[0][1] ke date string |

### Placeholder `{{POS(n)}}` / `{{DOC(n)}}` (di saveSend)

| Placeholder | Deskripsi |
|---|---|
| `{{POS(n)}}` | Diganti `ref[1][n]` apa adanya |
| `{{DOC(n)}}` | Diganti `getDocumentName(ref[1][n])` |

## Flow Detail

### 1. Penggabungan ke tableString di `saveSend` (api.dart)

```dart
// 1. Ambil raw string dari component
String raw = component['updateTableRow'] ?? '';

// 2. Decode karakter encoded
updateString = autheniumDecode(raw) ?? '';

// 3. Inject tableVid jika format D ada
updateString = updateString.replaceAll("◼D⭘", "◼D⭘tableVid◼$currentTableVid⭘");

// 4. Replace {{POS(n)}} / {{DOC(n)}} placeholders
updateString = replacePlaceholders(updateString, ref);

// 5. Gabungkan ke tableString (addToTable string) menggunakan separator[0]
//    Format: addStr⬤updateStr⬤deleteStr
if (updateString.isNotEmpty || deleteString.isNotEmpty) {
  tableString =
      '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString';
}

// 6. tableString dikirim ke saveSendRows → masuk history queue
saveSendRows(scrName, '', row, flag, timeStamp, locString, tableString, ...);
```

### 2. Penggabungan ke checkerTableString di `ftz_checker`

```dart
String checkerTableString = widget.component['addToTable'] ?? '';
String updateRaw = widget.component['updateTableRow'] ?? '';
String deleteRaw = widget.component['deleteFromTable'] ?? '';
if (updateRaw.isNotEmpty || deleteRaw.isNotEmpty) {
  checkerTableString =
      '$checkerTableString${separator[0]}$updateRaw${separator[0]}$deleteRaw';
}
// checkerTableString dikirim ke appendToSheet → masuk history queue
appendToSheet(row, defaultVid(), ..., checkerTableString);
```

> **Tidak lagi fire-and-forget:** Sebelumnya `updateTableRow()` dipanggil langsung. Sekarang string digabungkan ke `tableString` dan masuk history queue, sehingga operasi di-buffer offline dan diproses oleh `historySync` saat online.

### 3. `historySync()` — table_repository.dart (dispatch)

```
Saat device online, historySync memproses history queue:
  1. Baca eventHistory[14] (tb field = gabungan tableString)
  2. Split by separator[0] (⬤) → tbParts[]
     - tbParts[0] = addStr (addToTable)
     - tbParts[1] = updateStr (updateTableRow)
     - tbParts[2] = deleteStr (deleteFromTable)
  3. Build eventRowString dari eventHistory[0..2]
  4. if (updateStr.isNotEmpty) → updateTableRow(updateStr, eventRowString)
```

> **Backward compatible:** History record lama tanpa separator[0] menghasilkan single-element split, hanya memanggil `writeToTable` seperti sebelumnya.

### 4. `updateTableRow()` — table_repository.dart (parsing)

```
Input parsing:
  1. autheniumDecode(inp)
  2. splitTableInput(decoded) → split by ◆ (tables) → ⭘ (fields) → ◼ (key=val)
  3. Extract tablevid override
  4. parseTableInput() → resolve placeholders ◀n▶, build contentArray + indexContent
  5. Scan splitInput for 'search' field → extract searchField + searchValue
  6. Scan splitInput for '<n>' fields → build explicitPositions set
  7. Build partialFields map (only explicit columns)
  8. Filter indexContent to only patched columns → indexFieldUpdates

Execute:
  9. MobileTableController.updateContent(tableName, searchField, searchValue, partialFields, indexFieldUpdates)
```

### 5. `MobileTableController.updateContent()` — mobile_table_controller.dart

```
1. Validate table exists and tt == 'D'
2. Query: collection(contentPath).where(searchField, isEqualTo: searchValue)
3. For each matching doc:
   a. Decode current content: jsonDecode(doc['c'])
   b. Apply partialFields (sparse map, only explicit positions)
   c. Encode back: jsonEncode(updatedArray)
   d. Build rowUpdate: { 'c': newContent, 't': nowMilli, ...indexFieldUpdates }
   e. Auto-detect indexed fields: cek existing document fields,
      jika colKey ada di existing → update dengan type inference (bool/num/string)
   f. Update doc: doc.reference.update(rowUpdate)
4. Shift header checksum (slot 0 = new, slot 1 = previous)
5. Update table metadata: { 'cr': nowMilli, 'hd': newHeader }
```

## Firestore Path Structure

```
MobileTable/
  └── {tableVid}/           ← e.g. "20342033315492"
       └── tables/
            └── {tableName}/     ← e.g. "$test/agenia-demo-7/vtl.attendance-check-in"
                 ├── [document fields: t, cr, d, f, r, tt, hd]
                 └── content/
                      └── {autoId}/   ← row documents
                           ├── c: "[...]"      ← JSON array of column values
                           ├── t: 1714988322000  ← last modified timestamp
                           ├── 3: 87544551624342  ← indexed field (number)
                           └── 4: "Agenia Demo-7" ← indexed field (string)
```

## Search Type Detection (`_parseSearchValue`)

| Input | Detected Type | Result |
|---|---|---|
| `"true"` / `"false"` | `bool` | `true` / `false` |
| `"87544551624342"` | `num` | `87544551624342` |
| `"3.14"` | `num` | `3.14` |
| `"hello world"` | `String` | `"hello world"` |

> Firestore menyimpan semua numbers sebagai IEEE 754 64-bit float secara internal, sehingga int dan double match dalam query.

## Partial Update Logic

Hanya kolom yang **eksplisit disebutkan** dalam input yang di-update. Contoh:

```
Input: ⭘<5>◼new value⭘<8>◼another value
```

- `explicitPositions = {4, 7}` (0-based dari `<5>` dan `<8>`)
- `contentArray` dari parseTableInput = `['', '', '', '', 'new value', '', '', 'another value']` (padded)
- `partialFields = {4: 'new value', 7: 'another value'}`

Di Firestore, jika row sebelumnya:
```json
["attendance-check-in", "Mon May 06 2026 10:58:42", "87544551624342", "Agenia Demo-7", "old value 5", "val6", "val7", "old value 8", ...]
```

Setelah update:
```json
["attendance-check-in", "Mon May 06 2026 10:58:42", "87544551624342", "Agenia Demo-7", "new value", "val6", "val7", "another value", ...]
```

Kolom 1-4, 6, 7 **tidak berubah**.

## Index Field Updates

Index field di-update melalui dua mekanisme:

### 1. Explicit dari parseTableInput

Jika input `updateTableRow` mengandung definisi `index◼3★N◼4★S`, maka `parseTableInput` menghasilkan `indexContent` yang di-filter ke kolom yang di-patch. Namun dalam praktik, input `updateTableRow` jarang mengandung `index` definition.

### 2. Auto-detect dari existing document (utama)

`MobileTableController.updateContent()` secara otomatis mendeteksi indexed fields dari existing Firestore document. Untuk setiap kolom yang di-update:

```dart
partialFields.forEach((idx, newValue) {
  String colKey = (idx + 1).toString();  // 0-based → 1-based
  if (rowUpdate.containsKey(colKey)) return;  // skip jika sudah di-set oleh indexFieldUpdates
  if (!existing.containsKey(colKey)) return;  // skip jika bukan indexed field
  dynamic existingVal = existing[colKey];
  if (existingVal is bool) {
    rowUpdate[colKey] = newValue.toLowerCase() == 'true';
  } else if (existingVal is num) {
    rowUpdate[colKey] = num.tryParse(newValue);
  } else {
    rowUpdate[colKey] = newValue;
  }
});
```

**Logika:** Jika document sudah memiliki field dengan key `colKey` (misalnya field `'19'`), berarti field tersebut adalah indexed field. Tipe data diinfer dari nilai yang sudah tersimpan di Firestore:

| Existing Value Type | Konversi |
|---|---|
| `bool` | `newValue.toLowerCase() == 'true'` |
| `num` (int/double) | `num.tryParse(newValue)` |
| `String` / lainnya | Langsung sebagai string |

Contoh: Jika field `19` di Firestore berisi `"PENDING"` (string), dan update mengubah kolom 19 menjadi `"APPROVED"`, maka document field `'19'` juga otomatis di-update ke `"APPROVED"`.

## Header Checksum Shift

Setelah update berhasil, table header (`hd`) di-shift:

```
Before: "oldChecksum☆previousChecksum☆...rest..."
After:  "newChecksum☆oldChecksum☆...rest..."
```

Ini memicu:
1. `subscribeToTable` listener mendeteksi perubahan `hd`
2. `createInternalTableDynamic` membaca ulang data
3. Redux dispatch → UI rebuild

## Error Handling

| Kondisi | Return |
|---|---|
| Input null/empty | `[]` (empty list) |
| Field `search` tidak ada | `"Error: missing search"` |
| Tabel tidak ditemukan | `"Error: table not found"` |
| Tabel bukan tipe D | `"Error: update only supported for dynamic tables (tt=X)"` |
| Tidak ada match | `"Error: no match for field=value"` |
| Sukses | `"OK N updated"` (N = jumlah row yang di-update) |

## Contoh Lengkap dari Server JSON

```json
{
  "type": "location",
  "opMode": "qr-single",
  "flag": "attendance-check-in",
  "addToTable": "$test/agenia-demo-7//vtl.attendance-check-in⭘retention◼4320⭘description◼check-in attendance data⭘flag◼attendance-check-in⭘index◼3★N◼4★S⭘tablevid◼20342033315492⭘<1>◼attendance-check-in⭘<2>◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶⭘<3>◼87544551624342⭘<4>◼Agenia Demo-7⭘<5>◼◀5▶⭘<6>◼◀6▶",
  "updateTableRow": "$test/agenia-demo-7//vtl.attendance-check-in⭘tablevid◼20342033315492⭘search◼3★87544551624342⭘<5>◼test update"
}
```

**Execution flow:**
1. `addToTable` → simpan row baru (14 kolom) ke Firestore dengan index field `3` (number) dan `4` (string)
2. `updateTableRow` → cari row dimana field `3` == `87544551624342`, update kolom 5 menjadi `"test update"`

## Catatan Penting

- **Offline-capable** — operasi update masuk ke local history queue dan diproses oleh `historySync` saat device online. Tidak lagi fire-and-forget.
- **Separator[0] (⬤)** — digunakan untuk menggabungkan addToTable, updateTableRow, dan deleteFromTable ke dalam satu field `tb` (eventHistory[14]). Format: `addStr⬤updateStr⬤deleteStr`.
- **Backward compatible** — history record lama tanpa separator[0] tetap berfungsi karena split menghasilkan single element (hanya addStr).
- **Auto-detect indexed fields** — `updateContent()` otomatis mendeteksi dan mengupdate indexed field berdasarkan existing document structure, tanpa perlu definisi `index◼...` di input.
- **Multiple matches** — jika query `where` mengembalikan lebih dari 1 dokumen, **semua** akan di-update.
- **Hanya tipe D** — tabel tipe `A` (Array/static) dan `S` (Summary) tidak di-support untuk update.
- **Scope terbatas** — hanya mengakses path `MobileTable/{vid}/tables/{name}/content/*`. Tidak ada akses ke collection lain.
- **Bug fix (2026-05-06):** Field `search` perlu ditambahkan ke `case` di `parseTableInput` agar di-skip. Tanpa ini, `parseTableInput` crash karena `search` tidak memiliki format `<n>` yang expected oleh `default` case.

## See Also

- [delete_from_table.md](delete_from_table.md) — fitur delete row dari dynamic table
- [lib/firestore_repository/table_repository.dart — writeToTable](../../lib/firestore_repository/table_repository.dart) — fitur add row (existing)
