# ApprovalDetail

Widget detail view untuk menampilkan single request approval dengan informasi lengkap, status badge, approval chain progress, gallery gambar, dan sticky action buttons.

- **File:** [lib/widget/approval_detail.dart](../../lib/widget/approval_detail.dart)
- **Class:** `ApprovalDetail` (StatefulWidget)
- **Status:** done
- **Widget version:** v2
- **Introduced in commit:** `c556732`

## Purpose

Menampilkan detail satu request approval setelah user men-tap card di `Approval` list. Widget ini:
- Menampilkan informasi request dalam format card dengan key-value rows
- Menampilkan status approval (overall atau chain-level untuk APPROVER)
- Menampilkan alasan/reason dan gallery gambar pendukung
- Mengatur visibility sticky action buttons (approve/reject) melalui `currentStatus` static RxString
- Support multi-level approval chain progress tracking

## Signature / Constructor

```dart
ApprovalDetail({
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
| `component` | `dynamic` | yes | — | Config JSON dari server (struktur di bawah) |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Padding kiri/atas/kanan/bawah |

### Static Members

| Member | Type | Description |
|---|---|---|
| `currentStatus` | `RxString` | Status request saat ini, di-observe oleh `ApproverStickyBar` untuk visibility control. Shared antara detail page dan sticky bar |

### `component` shape

| Key | Type | Required | Description |
|---|---|---|---|
| `text` | `String` | yes | Template text dipisah `◆`. Index: [0]=type label, [1]=title, [2]=submitted info, [3..n-2]=detail labels, [n-2]=reason header, [n-1]=image section title |
| `content` | `String` | yes | Template value untuk detail rows, dipisah `◆`. Setiap entry adalah marker template (misal `◀5▶`) yang di-resolve dari row data |
| `table` | `String` | yes | Nama tabel Firestore (authenium-encoded) |
| `conditions` | `String` | yes | Filter untuk menemukan row yang tepat. Format: `[◀fieldIdx▶◼<named_marker>]`. Named markers di-resolve dari transactionStore |
| `status` | `String` | no | Template marker untuk resolve status dari row |
| `reason` | `String` | no | Template marker untuk menampilkan alasan request |
| `image` | `String` | no | Template marker untuk URL gambar. Multiple URL dipisah `◇` |
| `role` | `String` | no | Fallback role jika transactionStore kosong (tapi utamanya dari transactionStore) |
| `vidtable` | `String` | no | Fallback table VID |
| `indexStart` | `int` | no | Base index untuk `replaceMarker`, default `1` |

## Component JSON Example

```json
{
  "type": "approval_detail",
  "text": "◆Izin/Cuti◆◀2▶◆Submitted by ◀3▶◆Tanggal Mulai◆Tanggal Selesai◆Durasi◆Kategori◆ALASAN◆DATA PENDUKUNG",
  "content": "◆◀5▶◆◀6▶◆◀7▶ hari◆◀8▶",
  "table": "<authenium_encoded_table_name>",
  "conditions": "<authenium_encoded: [◀0▶◼<request_doc_t>]>",
  "status": "◀9▶",
  "reason": "◀10▶",
  "image": "◀11▶"
}
```

## State / Dependencies

- **State management:** GetX (`Obx` reactive) untuk `tableContent`, `RxString` untuk `currentStatus`
- **Repository:** `table_repository.dart` — `subscribeToTable()`
- **Redux:** `transactionStore` — membaca data approval yang di-dispatch oleh `Approval` list
- **Global:** `stickyOverlaysHidden` (dari `bottom_sticky_slot.dart`) untuk hide overlay saat image viewer aktif
- **Side effects:**
  - `subscribeToTable` pada `initState` — mulai listen Firestore table
  - `ApprovalDetail.currentStatus.value = status` — update static RxString (dibungkus `addPostFrameCallback`)

## Data Flow

### Initialization

```
initState
  ├── _initConfig()
  │   ├── Parse text → _textArray (diamond-separated labels)
  │   ├── Parse content → _contentArray (diamond-separated value templates)
  │   ├── Read _role dari transactionStore['approval_role']
  │   │   └── Fallback ke component['role']
  │   ├── Read _tabs dari transactionStore['approval_tabs']
  │   └── Read _myApprovalLevel dari transactionStore['approval_level']
  │
  └── _subscribeTable()
      ├── Decode + normalize table name → _tableCode
      ├── Read tableVid: transactionStore['approval_vidtable']
      │   └── Fallback ke component['vidtable']
      │   └── Fallback ke appCodeController.applicationTableVid
      └── subscribeToTable(_tableCode, tableVid) → listen Firestore
```

### Data Resolution (pada setiap Obx rebuild)

```
tableContent[_tableCode] (semua row)
  │
  ├── _applyConditions(allData)
  │   ├── Decode conditions string
  │   ├── _resolveNamedMarkers() → replace <key> dengan transactionStore[key]
  │   │   Contoh: "◀0▶◼<request_doc_t>" → "◀0▶◼DOC_12345"
  │   ├── Parse field patterns: ◀fieldIdx▶◼value
  │   └── Filter: row[fieldIdx] == value (OR between groups, AND within group)
  │
  ├── Take allData[0] → single row
  │
  ├── Resolve display values:
  │   ├── typeLabel = _resolveText(_textArray[0], row)
  │   ├── titleText = _resolveText(_textArray[1], row)
  │   ├── submittedText = _resolveText(_textArray[2], row)
  │   ├── status:
  │   │   ├── Base: _resolveText(component['status'], row)
  │   │   └── APPROVER override: _getChainStatus(row) → chain[_myApprovalLevel]
  │   ├── progress = _getChainProgress(row) → "(done/total)"
  │   ├── details = zip(_textArray[3..n-2], _contentArray) → key-value pairs
  │   ├── reason = _resolveText(component['reason'], row)
  │   └── imageUrl = _resolveText(component['image'], row)
  │
  └── Update currentStatus (via addPostFrameCallback)
      → ApproverStickyBar observes this to show/hide buttons
```

### Conditions Filtering Detail

Conditions mendukung named markers yang di-resolve dari transactionStore:

```
Conditions config: "[◀0▶◼<request_doc_t>]"
                          ↑ named marker

transactionStore['request_doc_t'] = "DOC_12345"

After resolve: "[◀0▶◼DOC_12345]"

→ Filter: row[0] == "DOC_12345"
```

Multiple groups (OR logic):

```
"[◀0▶◼<request_doc_t>], [◀1▶◼<no_request>]"

→ Show row if row[0]==DOC_12345 OR row[1]==REQ_001
```

### currentStatus → Sticky Bar Visibility

```
ApprovalDetail.currentStatus.value = "PENDING"
         │
         ▼
build_display_component.dart (RBT section):
  Obx(() {
    String s = ApprovalDetail.currentStatus.value;
    if (s.isNotEmpty && s != defaultStatus) {
      return SizedBox.shrink();  // HIDE buttons
    }
    return FtzRowOfButton2(...);  // SHOW buttons
  })

Result:
  - status == "PENDING" → show approve/reject buttons
  - status == "APPROVED" → hide buttons (sudah diproses)
  - status == "REJECTED" → hide buttons (sudah diproses)
  - status == "" → show buttons (initial/loading state)
```

### Image Gallery

```
component['image'] = "◀11▶"
row[11] = "https://url1.jpg◇https://url2.jpg◇https://url3.jpg"
                              ↑ separator: ◇ (white diamond)

→ Split by ◇ → filter startsWith('http') → take(5) → horizontal scroll
→ Tap image → _showFullImage() → PageView with InteractiveViewer (pinch-to-zoom)
→ stickyOverlaysHidden = true (hide sticky buttons while viewing)
```

## UI Structure

```
Padding
  └── Container (white, rounded 16, bordered)
      ├── Accent bar (3px, colored by status)
      └── Padding (18px)
          └── Column
              ├── Header row
              │   ├── Type icon (36x36, gray bg, rounded 10)
              │   ├── Type label (uppercase, gray, letter-spacing)
              │   └── Status badge (pill shape, colored bg + dot + text + progress)
              │
              ├── Title text (17px, bold)
              ├── Submitted text (13px, gray)
              │
              ├── Divider
              ├── Detail rows (key-value pairs)
              │   ├── Label (flex 2, left-aligned, gray)
              │   └── Value (flex 3, right-aligned, bold)
              │
              ├── Divider
              ├── Reason section
              │   ├── Header (uppercase, gray, letter-spacing)
              │   └── Reason text (14px, height 1.5)
              │
              ├── Divider
              └── Image gallery section
                  ├── Header (uppercase, gray, letter-spacing)
                  └── Horizontal ListView (90x90 thumbnails, rounded 8)
```

## Important Behavior

1. **`currentStatus` is static RxString**: Shared state antara `ApprovalDetail` dan `ApproverStickyBar`/`build_display_component.dart`. Ini memungkinkan button visibility dikontrol berdasarkan status request saat ini

2. **`addPostFrameCallback` untuk currentStatus update**: Perubahan `currentStatus.value` HARUS dibungkus `addPostFrameCallback` untuk menghindari setState-during-build crash. Tanpa ini, chain: Obx rebuild → set currentStatus → trigger sticky bar Obx → Duplicate GlobalKey error

3. **TransactionStore sebagai data bridge**: Semua config approval (role, tabs, level, table, vidtable, status_field) di-passing dari `Approval` list ke `ApprovalDetail` melalui transactionStore. Detail page membaca ini di `_initConfig()`. Ini karena detail page component JSON TIDAK mengandung field-field tersebut

4. **Named marker resolution**: `_resolveNamedMarkers` mengganti `<key>` pattern (huruf/underscore) dalam conditions string dengan value dari transactionStore. Ini berbeda dari `replaceMarker` yang mengganti `◀index▶` pattern dengan row data

5. **APPROVER status override**: Jika role = APPROVER, status yang ditampilkan adalah chain status di level approver tersebut, BUKAN overall status. Misal: overall PENDING tapi chain level 2 sudah APPROVED → badge menampilkan "Approved"

6. **Image viewer hides overlays**: Saat full-screen image viewer dibuka, `stickyOverlaysHidden.value = true` menyembunyikan semua sticky overlay (termasuk approval buttons). Reset ke `false` saat viewer ditutup

7. **Date formatting**: Field yang label-nya mengandung "date" akan di-format otomatis: `2024-03-15` → `15 Mar 2024`

8. **Empty data handling**: Jika setelah filtering tidak ada row, widget return `SizedBox.shrink()` — halaman tetap render tapi tanpa card detail

## Approval Chain Display

### Chain Progress

```
Chain: [[1, APPROVED, ...], [2, APPROVED, ...], [3, PENDING, ...]]
                                                          
_tabs = [PENDING, APPROVED, REJECTED]
continueStatus = APPROVED

done = 2 (count of APPROVED in chain)
total = 3

→ Progress: "(2/3)"
→ Status badge: "Pending (2/3)"
```

### Chain Status per Level

```
For APPROVER with _myApprovalLevel = 2:

Chain: [[1, APPROVED, ...], [2, PENDING, ...], [3, PENDING, ...]]
                                    ↑ my level

→ Status displayed: "PENDING" (chain[2] = PENDING)
```

## Full Page Architecture

Halaman detail approval terdiri dari beberapa widget yang bekerja sama:

```
Screen (from gotoRoute)
  │
  ├── ApprovalDetail widget (this)
  │   ├── Card with status, details, reason, images
  │   └── Sets ApprovalDetail.currentStatus
  │
  ├── CommentDetail widget (optional, dari JSON config)
  │   └── Comment input field di bagian bawah
  │
  └── RBT widget (dari build_display_component.dart)
      │
      ├── Detection: children.any(btn.containsKey('actions'))
      │   → true:  wrap in ApproverStickyBar
      │   → false: regular FtzRowOfButton2
      │
      └── ApproverStickyBar
          ├── Mode detection:
          │   ├── Has CommentDetail? → slot mode (stickyApproverSlot)
          │   └── No CommentDetail? → overlay mode (OverlayEntry)
          │
          ├── Visibility control:
          │   ├── stickyOverlaysHidden (image viewer)
          │   ├── keyboard visible (viewInsets.bottom > 0)
          │   └── Obx: currentStatus != defaultStatus → hide
          │
          └── FtzRowOfButton2
              ├── onPressed → switch(action) → standard flow
              └── After switch → _updateApprovalChain()
                  ├── Read approval config from transactionStore
                  ├── Find row by request_doc_t
                  ├── Parse chain → find PENDING step → apply actions
                  ├── Re-encode chain → updateTableRow
                  └── (same logic as Approval._onActionPressed)
```

## Relationship: TransactionStore Keys

Data yang di-dispatch oleh `Approval._onCardTap` dan dibaca oleh `ApprovalDetail._initConfig`:

| TransactionStore Key | Set by | Read by | Purpose |
|---|---|---|---|
| `no_request` | Approval | ApprovalDetail (conditions) | Nomor request |
| `request_vid` | Approval | — | VID request |
| `request_doc_t` | Approval | FtzRowOfButton2 | Document timestamp (row identifier) |
| `approval_status` | Approval | — | Overall status saat tap |
| `approval_role` | Approval | ApprovalDetail, FtzRowOfButton2 | MAKER/APPROVER |
| `approval_tabs` | Approval | ApprovalDetail, FtzRowOfButton2, build_display_component | toDo array [PENDING, APPROVED, REJECTED] |
| `approval_level` | Approval | ApprovalDetail, FtzRowOfButton2 | Level approval user |
| `approval_buttons` | Approval | — | Button configs |
| `approval_table` | Approval | FtzRowOfButton2 | Table name untuk updateTableRow |
| `approval_vidtable` | Approval | ApprovalDetail, FtzRowOfButton2 | Table VID |
| `approval_status_field` | Approval | FtzRowOfButton2 | Index field overall status |

## Supporting Widgets

### ApproverStickyBar

- **File:** [lib/widget/approver_sticky_bar.dart](../../lib/widget/approver_sticky_bar.dart)
- Wraps `FtzRowOfButton2` sebagai sticky bottom bar
- **Two modes:**
  - **Overlay mode** (default): Creates `OverlayEntry` positioned above bottom nav bar
  - **Slot mode** (if CommentDetail present): Registers builder to `stickyApproverSlot` ValueNotifier
- **Positioning:** `bottom = navBarHeight(66) + safeBottom + commentInputOffset(76 if applicable)`
- **AutomaticKeepAliveClientMixin:** Prevents rebuild when scrolling

### BottomStickySlot

- **File:** [lib/widget/bottom_sticky_slot.dart](../../lib/widget/bottom_sticky_slot.dart)
- Two ValueNotifiers:
  - `stickyApproverSlot` — WidgetBuilder for slot mode rendering
  - `stickyOverlaysHidden` — global flag to hide all sticky overlays

## See Also

- [approval.md](approval.md) — List page yang menavigasi ke detail ini
- [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — Button handler dengan `_updateApprovalChain` method
