# Admin Create Task -- op1Screen page JSON (config reference)

**Routes:** P2 (ItemBuilder), P4 (TaskSummary/Submit)
**Source spec:** `docs/admin_runtime/admin-create-task-dev-spec.md`
**Status:** server config artifact -- NOT deployable from the repo.

> P1 (CustomerPicker), P3 (VehicleAssignment), P5 (Success) are FULL REUSE
> of existing widgets. See the spec for their component layouts.

---

## FILL-IN tokens

- `84214220504259` -- tableDocId
- `20342033315492` -- vidtable (appVid)
- Route names are tenant-prefixed (e.g. `vertikaTeknoLokaciptaItemBuilder`)

---

## screenTx bare-key contract

P1 deposits `kl` (customer id) via routeParams. taskItemBuilder (P2) resolves
`kl` -> `kn`/`al` from stock_location and republishes all three.
P3 deposits `vv` (vehicle id) via routeParams.
P4 reads `kl`, `kn`, `al`, `vv` from screenTx (CONFIGURABLE key names).

---

## P2 -- ItemBuilder page children (5)

### 1 -- WORKSPACE_HEADER
{"type":"WORKSPACE_HEADER","text":"Langkah 2/4◆Pilih Item◆{kn}◆{al}"}

### 2 -- NOTICE_BAR (genesis guard, conditional)
{"type":"NOTICE_BAR","variant":"amber","label":"SETUP","title":"Saldo awal belum tercatat","text":"Outstanding belum tersedia. Saran jumlah pickup tidak aktif."}

### 3 -- TASK_ITEM_BUILDER
{"type":"TASK_ITEM_BUILDER","vidtable":"20342033315492","itemTable":"84214220504259//item","clientTable":"84214220504259//stock_location","outstandingTable":"84214220504259//asset_cache","wizardKey":"admin_create_task","clientIdField":"lv","clientNameField":"ln","clientAddrField":"al","itemIdField":"ii","itemNameField":"in","itemCatField":"ic","text":"Tambah Item◆◆Refill◆Jual◆Beli◆Kosong◆Penuh◆Air RO◆Isi Ulang◆Pilih Produk◆Drop◆Pickup◆Hapus◆saran"}

### 4 -- NOTICE_BAR (outstanding hint, conditional)
{"type":"NOTICE_BAR","variant":"violet","label":"INFO","title":"Outstanding aktif","text":"Ada barang customer yang belum dikembalikan."}

### 5 -- RBT "Lanjut - Pilih Kendaraan"
{"type":"RBT","alignment":"center","children":[{"text":"Lanjut -> Pilih Kendaraan","action":"route","route":"[ROUTE:vehicleAssignment]","routeParams":""}]}

---

## P4 -- TaskSummary/Submit page children (6)

### 1 -- WORKSPACE_HEADER
{"type":"WORKSPACE_HEADER","text":"Langkah 4/4◆Review & Submit◆{kn}◆{al}"}

### 2 -- TXT (customer card)
{"type":"TXT","data":"Customer: {kn}","bold":true,"size":14}

### 3 -- TASK_DRAFT_SUMMARY
{"type":"TASK_DRAFT_SUMMARY","wizardKey":"admin_create_task","text":"Item◆Drop◆Pickup◆Jual◆Beli◆Refill◆Belum ada item"}

### 4 -- TXT (vehicle card)
{"type":"TXT","data":"Kendaraan: {vv}","bold":true,"size":14}

### 5 -- NOTICE_BAR (doctrine)
{"type":"NOTICE_BAR","variant":"slate","label":"INFO","title":"Setelah submit","text":"Task langsung masuk ke gudang. Tunggu proses loading."}

### 6 -- TASK_CREATE_SUBMIT
{"type":"TASK_CREATE_SUBMIT","vidtable":"20342033315492","table":"84214220504259//task","wizardKey":"admin_create_task","originWarehouse":"WH-DEFAULT","route":"[ROUTE:taskSuccess]","text":"Buat Task & Assign◆Lengkapi data dulu◆Gagal membuat task◆Data item kosong"}
