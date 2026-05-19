# Approval

Widget daftar approval yang menampilkan list request berdasarkan role (MAKER/APPROVER) dengan tab filtering, search, dan aksi approve/reject langsung dari card.

- **File:** [lib/widget/approval.dart](../../lib/widget/approval.dart)
- **Class:** `Approval` (StatefulWidget)
- **Status:** done
- **Widget version:** v2
- **Introduced in commit:** `c556732`

## Purpose

Menampilkan daftar request approval dalam format card list dengan fitur:
- Tab filtering berdasarkan status (PENDING/APPROVED/REJECTED)
- Search text pada semua field
- Action buttons langsung di card (approve/reject) untuk approver
- Multi-level approval chain support
- Navigasi ke detail page saat card di-tap

Digunakan oleh role **MAKER** (pembuat request) dan **APPROVER** (pemberi persetujuan) dengan behavior filtering yang berbeda.

## Signature / Constructor

```dart
Approval({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `scrName` | `String` | yes | — | Nama screen tempat widget ini di-mount |
| `component` | `dynamic` | yes | — | Config JSON dari RBT/server (struktur di bawah) |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Padding kiri/atas/kanan/bawah |

### `component` shape

| Key | Type | Required | Description |
|---|---|---|---|
| `toDo` | `String` | yes | Daftar status tab, format: `[PENDING, APPROVED, REJECTED]`. Index 0 = default status, index 1 = continue status, index 2+ = terminal status |
| `text` | `String` | yes | Template text dipisah `◆` (diamond). Index: [0]=title, [1]=name template, [2]=subtitle template, [3]=date template, [4]=search label, [5]=search hint |
| `role` | `String` | yes | `MAKER` atau `APPROVER` — menentukan behavior filtering |
| `table` | `String` | yes | Nama tabel Firestore (authenium-encoded) |
| `vidtable` | `String` | no | Table VID, fallback ke `appCodeController.applicationTableVid` |
| `route` | `String` | no | Route tujuan saat card di-tap (ke detail page) |
| `buttons` | `List<Map>` | no | Daftar tombol aksi yang muncul di card. Setiap button: `{text, color, actions, chain}` |
| `search` | `String` | no | Filter statis, format authenium-encoded: `<fieldIndex>◼<value>⭘...`. Jika value cocok dengan salah satu tab → digunakan sebagai `_statusFieldIndex` |
| `conditions` | `String` | no | (Hanya APPROVER) Filter field dan deteksi approval level, format authenium-encoded: `◀fieldIdx▶◼value, ◁step▷◼PENDING` |
| `status` | `String` | no | Template marker untuk resolve status dari row (misal `◀2▶`). Jika kosong, gunakan `_statusFieldIndex` |
| `typeField` | `int` | no | Index field untuk menentukan icon tipe request |
| `indexStart` | `int` | no | Base index untuk `replaceMarker`, default `1` |

### `buttons` item shape

| Key | Type | Description |
|---|---|---|
| `text` | `String` | Label tombol (misal "Approve", "Reject") |
| `color` | `String` | Warna tombol: `red`, `green`, `blue` |
| `actions` | `String` | Template aksi approval chain (authenium-encoded). Format: `<posisi>◼value⭘<posisi>◼value⭘...` Contoh: `<2>◼APPROVED⭘<3>◼VID⭘<4>◼timestamp` |
| `chain` | `String` | Config doChain untuk dialog setelah aksi |

## Component JSON Example

```json
{
  "type": "approval",
  "toDo": "[PENDING, APPROVED, REJECTED]",
  "text": "◆Approval Cuti◆◀2▶◆◀3▶◆◀4▶◆Search◆Cari request...",
  "role": "APPROVER",
  "table": "<authenium_encoded_table_name>",
  "vidtable": "123",
  "route": "approval_detail_page",
  "search": "<authenium_encoded: 5◼DIVISION_A>",
  "conditions": "<authenium_encoded: ◀5▶◼DIVISION_A, ◁1▷◼PENDING>",
  "typeField": 6,
  "buttons": [
    {
      "text": "Approve",
      "color": "green",
      "actions": "<authenium_encoded: <2>◼APPROVED⭘<3>◼VID⭘<4>◼timestamp>",
      "chain": "<chain_config>"
    },
    {
      "text": "Reject",
      "color": "red",
      "actions": "<authenium_encoded: <2>◼REJECTED⭘<3>◼VID>",
      "chain": "<chain_config>"
    }
  ]
}
```

## State / Dependencies

- **State management:** GetX (`Obx` reactive) untuk `tableContent`
- **Repository:** `table_repository.dart` — `subscribeToTable()`, `updateTableRow()`
- **Redux:** `transactionStore` — dispatch data ke detail page via `UpdateScreenTxAction`
- **Side effects:**
  - `subscribeToTable` pada `initState` — mulai listen Firestore table
  - `updateTableRow` pada aksi approve/reject — update chain + optional overall status
  - `doChain` setelah aksi — menampilkan dialog konfirmasi/navigasi

## Data Flow

### Initialization

```
initState
  ├── _initConfig()
  │   ├── Parse toDo → _tabs [PENDING, APPROVED, REJECTED]
  │   ├── Parse text → _textArray (diamond-separated)
  │   ├── Set _role dari component['role']
  │   ├── Parse search → _searchFilters + _statusFieldIndex
  │   └── (APPROVER only) Parse conditions → _fieldConditions + _myApprovalLevel
  │
  └── _subscribeTable()
      ├── Decode + normalize table name → _tableCode
      └── subscribeToTable(_tableCode, tableVid) → listen Firestore
```

### Filtering Pipeline (pada setiap Obx rebuild)

```
tableContent[_tableCode] (semua row dari Firestore)
  │
  ├── [APPROVER] → _applyFieldConditions() → filter by ◀fieldIdx▶◼value conditions
  │                                           (misal: hanya tampilkan division tertentu)
  │
  └── [MAKER]    → _applySearchFilter()    → filter by search config statis
  │
  ├── Tab counting:
  │   ├── [APPROVER] → _applyApproverTabFilter() per tab → count by chain step status
  │   └── [MAKER]    → _getStatus() per row per tab → count by overall status field
  │
  ├── Tab filtering (selected tab):
  │   ├── [APPROVER] → _applyApproverTabFilter(selStatus)
  │   │                 → cek chain: semua level sebelum myLevel harus APPROVED,
  │   │                   level saya harus == selected tab status
  │   └── [MAKER]    → filter row where _getStatus(row) == selStatus
  │
  └── searchTable(_searchQuery, filtered) → text search pada semua field
```

### Approver Tab Filtering Detail

Untuk APPROVER dengan `_myApprovalLevel = 2` dan tab PENDING:

```
Chain: [[1, APPROVED, ...], [2, PENDING, ...], [3, PENDING, ...]]
                ↑ harus APPROVED      ↑ harus PENDING (my level)

→ Tampil di tab PENDING ✓

Chain: [[1, PENDING, ...], [2, PENDING, ...], [3, PENDING, ...]]
                ↑ belum APPROVED

→ Tidak tampil di tab PENDING ✗ (level sebelumnya belum approve)
```

### Card Tap → Navigate to Detail

```
_onCardTap(row)
  ├── Dispatch ke transactionStore:
  │   ├── no_request, request_vid, request_doc_t
  │   ├── approval_status, approval_role
  │   ├── approval_tabs, approval_level
  │   ├── approval_buttons, approval_table, approval_vidtable
  │   └── approval_status_field
  │
  └── routeStack.push(route) → gotoRoute(route) → navigasi ke detail page
```

### Action Pressed (Approve/Reject dari Card)

```
_onActionPressed(row, buttonConfig)
  │
  ├── 1. Decode actions template dari buttonConfig['actions']
  │
  ├── 2. Auto-detect chain column
  │      → Scan row fields, cari yang startsWith('[[')
  │      → chainColIdx = index, chainStr = raw value
  │
  ├── 3. Parse chain string → List<List<String>> steps
  │      Input:  "[[1, APPROVED, VID1], [2, PENDING, VID2], [3, PENDING, VID3]]"
  │      Output: [[1, APPROVED, VID1], [2, PENDING, VID2], [3, PENDING, VID3]]
  │
  ├── 4. Find target step (first step with defaultStatus)
  │      defaultStatus = _tabs[0] (biasanya "PENDING")
  │      targetIdx = step dimana step[1] == "PENDING"
  │
  ├── 5. Apply actions template ke target step
  │      Template: "<2>◼APPROVED⭘<3>◼VID⭘<4>◼timestamp"
  │      → step[1] = "APPROVED", step[2] = "VID", step[3] = "timestamp"
  │
  ├── 6. Re-encode chain
  │      → "[[1, APPROVED, VID1], [2, APPROVED, VID_NEW, ts], [3, PENDING, VID3]]"
  │
  ├── 7. Determine overall status update
  │      actionStatus = newStep[1] (misal "APPROVED" atau "REJECTED")
  │      continueStatus = _tabs[1] (misal "APPROVED")
  │      isLastLevel = _myApprovalLevel == steps.length
  │      updateOverallStatus = isLastLevel || actionStatus != continueStatus
  │
  │      Logika:
  │      - APPROVED di level terakhir → update overall status
  │      - REJECTED di level manapun → update overall status (terminal action)
  │      - APPROVED di level bukan terakhir → TIDAK update overall (masih ada level berikutnya)
  │
  ├── 8. Build updateTableRow input string
  │      Format: "tableName⭘tablevid◼vid⭘search◼1♦noRequest⭘<chainPos>◼newChainStr[⭘<statusField>◼actionStatus]"
  │
  ├── 9. Build event row JSON (untuk history/audit trail)
  │      Format: [nowMs, scrName, "0②{nowMs}♦scrName♦noRequest♦status♦ts♦..."]
  │
  ├── 10. Call updateTableRow(input, eventRowString)
  │       → Update Firestore table row (chain + optional overall status)
  │       → Write event record
  │
  └── 11. doChain(context, scrName, buttonConfig['chain'])
          → Show confirmation dialog / navigate
```

### Status Color Mapping

| Status | Text Color | Background |
|---|---|---|
| PENDING | `#E8910C` (amber) | `#FEF3C7` (light yellow) |
| APPROVED | `#16A34A` (green) | `#DCFCE7` (light green) |
| REJECTED | `#DC2626` (red) | `#FEE2E2` (light red) |
| Default | `#6B7280` (gray) | `#F3F4F6` (light gray) |

### Type Icon Mapping

| Keyword | Icon |
|---|---|
| permission, izin, leave, cuti | `access_time_rounded` |
| time correction, koreksi waktu | `history_rounded` |
| attendance, kehadiran | `edit_note_rounded` |
| sick, sakit | `medical_services_outlined` |
| swap, tukar | `swap_horiz_rounded` |
| overtime, lembur | `more_time_rounded` |
| Default | `description_outlined` |

## UI Structure

```
SizedBox (height: 79% screen)
  └── Column
      ├── Title text (_textArray[0])
      ├── Search field (TextFormField)
      ├── Tab bar (animated, with counts)
      └── Expanded
          └── ListView.builder
              └── _buildCard per row
                  ├── Left accent bar (colored by status)
                  ├── Icon + Name + Subtitle + Date
                  ├── Status badge (with chain progress for APPROVER)
                  └── Action buttons (only if status == defaultStatus)
```

## Important Behavior

1. **APPROVER vs MAKER filtering**: APPROVER menggunakan `_applyFieldConditions` + `_applyApproverTabFilter` (chain-aware), MAKER menggunakan `_applySearchFilter` (overall status field)

2. **Chain progress display**: Badge menampilkan progress chain, misal "Approved (1/3)" menunjukkan 1 dari 3 level sudah APPROVED

3. **Action buttons hanya muncul pada defaultStatus**: Tombol approve/reject hanya ditampilkan jika status card == `_tabs[0]` (biasanya PENDING). Card yang sudah APPROVED/REJECTED tidak menampilkan tombol

4. **Multi-level chain logic**: Approver level 2 hanya melihat request PENDING jika level 1 sudah APPROVED. Ini mencegah approver level tinggi mengambil tindakan sebelum level sebelumnya selesai

5. **Overall status update conditional**: Status overall hanya di-update jika: (a) ini level terakhir dan aksi = continue, atau (b) aksi = terminal (REJECTED). Jika approve di level menengah, hanya chain yang di-update

6. **Event recording**: Setiap aksi approve/reject menulis event row ke Firestore via parameter `eventRowString` di `updateTableRow`. Ini BUKAN melalui flow `saveSend`/`appendToSheet`

7. **TransactionStore dispatch**: Saat card di-tap, data approval di-dispatch ke transactionStore untuk digunakan oleh `ApprovalDetail` dan `FtzRowOfButton2` di detail page

## Relationship with Other Widgets

```
                     ┌─────────────────────────┐
                     │    Approval (List)       │
                     │  - Tab filtering          │
                     │  - Card display           │
                     │  - Direct approve/reject  │
                     └────────┬────────────────┘
                              │ _onCardTap()
                              │ dispatch to transactionStore
                              │ routeStack.push → gotoRoute
                              ▼
                     ┌─────────────────────────┐
                     │   ApprovalDetail         │
                     │  - Single request view    │
                     │  - Status display         │
                     │  - currentStatus (RxString)│
                     └────────┬────────────────┘
                              │ currentStatus changes
                              ▼
┌──────────────────────┐    ┌─────────────────────────┐
│ build_display_       │───▶│  ApproverStickyBar       │
│ component.dart       │    │  - Overlay/slot buttons   │
│ (RBT detection by    │    │  - Visibility by status   │
│  actions field)      │    └────────┬────────────────┘
└──────────────────────┘             │ wraps
                                     ▼
                            ┌─────────────────────────┐
                            │   FtzRowOfButton2        │
                            │  - _updateApprovalChain  │
                            │  - Same chain logic      │
                            └─────────────────────────┘
```

## See Also

- [approval_detail.md](approval_detail.md) — Detail page untuk single request
- [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — Button handler yang mengeksekusi chain update di detail page
