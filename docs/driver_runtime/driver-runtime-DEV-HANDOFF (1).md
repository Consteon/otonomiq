# Driver Runtime — DEV HANDOFF (kirim ini ke dev)

**Konteks:** semua **config sheet (op1Screen page + Widget template + DSL) = SELESAI** dan resolving. Yang tinggal = **renderer (Flutter)** baca config-nya, + **CF (backend)** derive data. App belum nampilin sebagian fitur karena renderer-nya belum dibangun (bukan karena config kurang).

**Start here (baca dulu, urutan):**
1. `docs/driver-runtime-widgets-MASTER-handoff.md` — peta flow P4→P12 + reject + failed, page→widget→spec.
2. `docs/consteon-runtime-knowledge-base.md` — arsitektur op1Screen + DSL token + data model.
3. `docs/driver-runtime-field-dictionary.md` — semua field + arti.

---

## ⚡ UPDATE 2026-06-25 — movement/custody LIVE, sisa renderer

**CF: 5 fn, semua CODED; movement/custody udah jalan di prod (otq-01).** `asset_cache` SEKARANG **di-derive CF dari movement** (BUKAN hand-seed lagi — abaikan §B note lama).
- `OnMovementCreated` (movement→asset_cache), `ReconcileAssetCache` (HTTP rebuild dari ledger), `OnTaskRejected` (reject unload + rebuild ie[]), `OnTaskCompleted` (delivery emit, `qt=actual??plan`), **`OnCustodyConfirmed`** (custody mismatch → ADJUSTMENT mobil = hitungan driver `ip`). Detail: `../cloud-function/docs/CF-SESSION-HANDOFF.md`.

**Sisa RENDERER (Flutter) dari sesi ini — config + CF udah beres, tinggal app:**
| # | fitur | spec | kenapa |
|---|---|---|---|
| 1 | **ITEM_EXECUTION_LIST actual-write** | `item-execution-actual-write-dev-spec.md` | submit deliver tulis aktual (`ad/ap/as/ab/ar`) ke `task.it[]` (native array, atomik + `tst=completed`). **Tanpa ini: deliver maksa pake plan → stok mobil bisa minus** kalo custody selisih. Config `actual*Field` UDAH live. |
| 2 | **preconditionGateCard** 3 fix | `precondition-gate-card-manifest-dev-spec.md` §8/§9/§10 | §8 existence gate (hide kalo no opening-today). §9 item dari `vehicle_check.ie[]` (BUKAN asset_cache). §10 notice selisih in-card dari `dp[]`. Config UDAH live. |

> Reset testing (biar gak salah angka): **hapus DULU** 4 koleksi (`movement`, `asset_cache`, `asset_cache_applied`, `asset_cache_monthly`) **BARU re-seed**. Hapus asset_cache doang = ledger lama gak ke-apply ulang → stok salah. Lihat `driver-runtime-test-scenarios.md` §2.

---

## A. RENDERER (Flutter) — config udah ada, app harus implement

> **Prinsip global (semua widget):** label/teks tampilan dibaca dari config `text` ◆-segment (by index), **JANGAN hardcode di Flutter.** Owner atur kata/bahasa via spreadsheet, tanpa deploy. Mockup `src/component/Driverruntime*.jsx` hardcode label = prototype doang; renderer produksi wajib config-driven.

### A1. Yang bikin fitur BELUM jalan sekarang (prioritas)
| widget / fitur | spec | catatan |
|---|---|---|
| **routeParams** (kirim data antar-route) | `rbt-route-params-dev-spec.md` | buat reject (driverStopCard Tolak: `rejectTaskVid◼{tnm}`) + failed (rbtCta P11: `activeTaskVid◼{activeTaskVid}`). Token login = session-global, BUKAN routeParams |
| **PRECONDITION_GATE_CARD** agregasi manifest | `precondition-gate-card-manifest-dev-spec.md` | 3 perilaku: sum `pd+ps+pr`, exclude `load_rejected`, `hideZero`. **Ini penyebab manifest masih nampil 0** untuk item jual/tukar |
| **DRIVER_STOP_CARD** Tolak + state | `driver-stop-card-dev-spec.md` | tombol Tolak (nav + routeParams), handle `tst=load_rejected` (drop/relabel dari route) |
| **ITEM_EXECUTION_LIST** tx branch | `driver-delivery-workspace-p11-dev-spec.md` + `driver-runtime-transaction-delta.md` | sale/purchase/refill read-only |
| **TASK_MANIFEST_LIST** + **CIRCULATION_SUMMARY** tx+exclude | `driver-custody-notification-p5-dev-spec.md` + `driver-runtime-transaction-delta.md` | sum tx + exclude load_rejected |

### A2. Page/widget renderer lain
| widget / page | spec |
|---|---|
| ROUTE_PROGRESS_HEADER | `driver-route-progress-header-dev-spec.md` |
| DriverHome (P4) + state machine | `driverhome-p4-dev-spec.md`, `driver-home-state-machine-dev-spec.md` |
| Custody P5/P6 + reveal | `driver-custody-notification-p5-dev-spec.md`, `driver-custody-count-p6-dev-spec.md`, `driver-custody-reveal-dev-spec.md` |
| Custody P7/P8/P9 (success/mismatch) | `driver-custody-p7p8p9-dev-spec.md` |
| TaskFeed (P10) | `driver-task-feed-p10-dev-spec.md` |
| DeliveryWorkspace (P11) | `driver-delivery-workspace-p11-dev-spec.md` |
| ReturnVehicle (P12) — RETURN_HEADER, VEHICLE_CARGO_SUMMARY (rebuild: per-item nama+satuan, fix `ii` mentah + "Tabung" hardcoded), CIRCULATION_SUMMARY (reuse, jual/beli) | `driver-return-vehicle-p12-dev-spec.md` §2/§3 |
| RejectTask | `driver-reject-task-sheet-dev-spec.md` |
| **FailedDelivery** (baru) — SELECTABLE_BTN positioned-input, evidence `ec` | `driver-failed-delivery-sheet-dev-spec.md` |
| evidence / addToEvent | `driver-evidence-addToEvent-dev-spec.md` |
| noticeBar / scanner (udah dibangun, verify) | `notice-bar-widget-dev-spec.md`, `scanner-widget-dev-spec.md` |
| submit confirm sheet / stepper | `driver-submit-confirm-sheet-dev-spec.md`, `execution-stepper-dev-spec.md`, `stepper-widget-dev-spec.md` |

---

## B. CF (Go / backend)
| fitur | spec |
|---|---|
| **asset_cache** CF (movement → stok per lokasi) | `driver-runtime-movement-cf-handoff.md`, `driver-runtime-movement-cf-dev-spec.md` |
| **movement** derive task `it[].ad/ap` (DROP/PICKUP/SALE/PURCHASE/REFILL) | sama ↑ |

Status CF (UPDATE 2026-06-25): **5 fn CODED, udah jalan di prod otq-01** (movement→asset_cache, delivery emit, reject unload, custody adjustment). `asset_cache` **di-derive CF** (gak hand-seed lagi). Full daftar + deploy: `../cloud-function/docs/CF-SESSION-HANDOFF.md`. Tambahan custody adjustment: `../cloud-function/docs/oncustodyconfirmed-cf-spec.md`.

---

## C. Schema / reference (buat dev paham, bukan dibangun)
- `driver-runtime-field-dictionary.md` — field + arti.
- `driver-runtime-tables-dev-spec.md` — collection + struktur.
- `driver-runtime-transaction-delta.md` — model tx v2 (pd/ps/pr/pb, jual/beli/tukar/refill).
- `driver-runtime-schema-changes.md` — perubahan schema.
- evidence `ec` (Evidence Category) — field baru di dict, buat alasan failed/reject (schemaless, no code driver).

---

## D. JANGAN dikerjain dulu (draft / nunggu approval)
- `redesign-movement-cache-item-techlead.md` — **DRAFT**, nunggu review tech-lead (double-entry movement, cache auto-id, dll). JANGAN implement sebelum diketok.
- `op1screen-widget-refactor-handoff.md` — internal sheet refactor (gak ngubah output app), bukan kerjaan dev Flutter.
- `asset-cache-reseed-startofday-spec.md` — buat seed/agent, bukan dev.

---

## Ringkas prioritas (deadline)
1. **routeParams** + **DRIVER_STOP_CARD Tolak** → reject & failed bisa di-trigger.
2. **PRECONDITION_GATE_CARD** + **TASK_MANIFEST_LIST/CIRCULATION_SUMMARY** + **ITEM_EXECUTION_LIST** tx aggregation → angka muatan & sirkulasi bener (sekarang masih pd-only / 0).
3. Sisa page renderer (custody, return, feed) + CF deploy.
