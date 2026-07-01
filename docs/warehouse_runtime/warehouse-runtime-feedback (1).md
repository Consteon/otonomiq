# Warehouse Runtime — AS-BUILT Corrections (2026-06-24)

**What this is:** a standalone errata + as-built record for the 4 warehouse-runtime specs in this folder. All three pages were implemented end-to-end and are **review-clean** (full test suite **1091 pass**); during the build the implementation diverged from the specs in the ways recorded below. The original specs are left **unchanged** (design intent + history); this document is the authoritative delta.

**SSOT going forward:** the shipped **code** + the implementation plans **`.claude/plans/{vehicle-feed-h1, warehouse-opening-check-o1, warehouse-closing-check-c1}.md`** + their walkthrough/review reports under `.claude/reports/`. When this doc and a spec disagree, this doc wins.

> Scope note: this is errata, not a redesign. The handshake model, tier gate, field dictionary, and most reuse anchors in the specs are correct and were built as written.

---

## Build status

| Page | Route | Renderer | Server config sheet | Tests |
|---|---|---|---|---|
| H1 Feed | `vertikaTeknoLokaciptaWarehouseFeed` | ✅ built, review-clean | ✅ LIVE (rows 1101–1105) | on-device testable |
| O1 Opening (+O2 picker) | `vertikaTeknoLokaciptaWarehouseOpeningCheck` | ✅ built, review-clean | ⬜ pending | unit-tested; QA blocked on config |
| C1 Closing | `vertikaTeknoLokaciptaWarehouseClosingCheck` | ✅ built, review-clean | ⬜ pending | unit-tested; QA blocked on config |
| R1/R2 Result | `…WarehouseClosingResult` (two routes) | ✅ built (reuse) | ⬜ pending | — |

All changes are currently **UNCOMMITTED** and commingled with prior slugs in shared files (`driver_home_support.dart`, `custody_count_list.dart`, `custody_count_submit.dart`, `build_display_component.dart`, `all_widget.dart`) — any commit must be path/hunk-scoped (`git add -p`).

---

## C1 — THE CRITICAL CORRECTION (applies to handoff §A4, O1 §6, C1 §4)

**Spec says:** create the doc via DSL `addToEvent`, *then* write the array (`ie[]`/`ip[]`/`dp[]`) natively to that doc.

**This is broken — do NOT do it.** `saveSend`/`addToEvent` is `void` and **asynchronous** — it enqueues the offline history queue and returns immediately; the doc reaches Firestore *later* (next `historySync`). A native array write that queries the just-"created" doc by `cnm` runs **before the doc exists** → it matches 0 docs → **the array is silently lost**. The driver P5/P6 custody handshake (which reads `ie[]`) then breaks. This fails on essentially every submit, not just offline.

**As-built fix — `createNativeDoc` (in `lib/widget/driver_home_support.dart`):** write the FULL document — all scalars **and** the array(s) — in ONE native Firestore `set(docMap, SetOptions(merge:true))` keyed by a **deterministic doc id**. Firestore's offline persistence queues + syncs it, so it is offline-safe and has no create-then-query race.

```
createNativeDoc(component, rawTable, docId: <deterministic cnm>, docMap: {scalars... , <arrayField>: [...]})
```

Rules that follow from this:
- **Create-with-array → native `createNativeDoc`** (O1 opening doc + `ie[]`; C1 closing doc + `ip[]`+`dp[]`+`rs`; C1 R2 investigation doc).
- **Scalar UPDATE to an EXISTING doc → DSL `updateEventRow` + `saveSend` is fine** (no ordering race; the row already exists). Used for O1's `dv`/`dn` designate on `stock_location`.
- **C1 opening `cst◼closed` is the exception — close it natively, by id.** The opening doc's `search` field is `cnm★{openingCnm}` only (that's all O1 wrote), so a `cty/vv/cdt` `updateEventRow` search would never match it. Regenerate `openingCnm` deterministically (`CHK-{vv}-{YYYYMMDD}` — the opening formula) and `createNativeDoc(docId: openingCnm, {cst:'closed'})` set-merge.
- **Deterministic ids:** opening `CHK-{vv}-{YYYYMMDD}`; closing `CHK-{vv}-{YYYYMMDD}-C` (the `-C` suffix avoids colliding with the opening on the same vehicle+date); investigation `INV-{vv}-{YYYYMMDD}`.

---

## Handoff (`warehouse-runtime-DEV-HANDOFF.md`) corrections

- **§A4** — superseded by the CRITICAL CORRECTION above.
- **"Net widget baru: 2" → actually 4.** The design mockups required two more widgets than the reuse map allowed: O1 `executor_designate_card` and C1 `closing_context_rail` (see O1 #2 / C1 #2 below). Full list: `vehicle_feed_header`, `vehicle_feed_list`, `executor_designate_card`, `closing_context_rail`.
- **§A2 "variant" undersells it.** `CUSTODY_COUNT_LIST` has **3 distinct data sources**, each a separate load path (additive-gated, driver P6 byte-identical): P6 single-doc `ie[]` (blind) / O1 task-aggregate `Σ(pd+ps+pr)` (gate `aggregate`) / C1 `asset_cache` (gate `source:asset_cache`). `CUSTODY_COUNT_SUBMIT` has 3 modes: P6 single-write / O1 `mode:opening` / C1 `mode:closing`.
- **"Start here" dead/wrong pointers:**
  - `docs/consteon-runtime-knowledge-base.md` — **does not exist** in the repo. The equivalent knowledge is the shipped driver-runtime code + `.claude/plans/`.
  - Field dictionary is at `docs/driver_runtime/driver-runtime-field-dictionary.md` (not `docs/driver-runtime-field-dictionary.md`).
  - Per-page specs live under `docs/warehouse_runtime/` (not `docs/`).
- **Token mechanic** — added to `resolveDriverCurlyTokens`: `{checkerVid}`→`#VID`, `{activeVehicle}`→`#ACTIVE_VEHICLE`, `{chosenVid}`→`#CHOSEN_DRIVER_VID`, `{chosenName}`→`#CHOSEN_DRIVER_NAME`, `{warehouseId}`→`#ACTIVE_WAREHOUSE`, `{now}`. `{checkerName}`/`{genCnm}`/`{closingCnm}`/`{openingCnm}`/`{genVnm}` are resolved locally at submit (generated/looked-up), not resolver cases.

---

## H1 (`vehicle-feed-h1-dev-spec.md`) — spec was accurate; minor deltas

- `{checkerVid}` = `screenTx['#VID']` (logged-in checker). The header resolves the checker via a direct `#VID` workforce loop; the `checkerSearch` config field is vestigial for H1.
- Section headers render the **label only** — the trailing "· {count}" was dropped (the count lives in the snapshot boxes, per the mockup).
- `custody_pending` card = **read-only, no button**. The mockup's "Konfirmasi Penerimaan" is a DRIVER P5/P6 action; it still counts toward the "Perlu Tindakan" snapshot.
- Card tap (loading→opening / returning→closing) writes the tapped `lv` to a new `#ACTIVE_VEHICLE` key (consumed by O1/C1 as `{activeVehicle}`/`{vehicleId}`); `routeStack.push` before `gotoRoute`.
- Tier derivation is an in-memory filter over subscribed collections (no N+1). Executor name = denorm `dn` (no per-row workforce lookup).
- Category summary joins a derived `{docId}/item` collection; if `item` lives in a different container it degrades to a blank summary (verify on-device).

---

## O1 (`warehouse-opening-check-o1-dev-spec.md`) corrections

1. **§6 submit** — superseded by the CRITICAL CORRECTION. As-built: build the full opening doc map (`cnm/cty:opening/vv/gl/cdt/cst:awaiting_custody/gv/gn/ldt/t/tablevid/search` + `ie[]`) and write in ONE `createNativeDoc(docId: CHK-{vv}-{YYYYMMDD})`. Step 3 designate `dv`/`dn` stays `updateEventRow`+`saveSend` (existing-row update). `ldt`=string, `t`=int (intentional: string-eq vs sort).
2. **§1/§2 executor is a NEW widget, not "0 baru".** `searchFromTableConsteon` (OtqTxf2 `variant:searchtable`) renders an *inline* search field — it does NOT match the mockup's amber `ExecutorCard` + bottom-sheet `ExecutorPickerSheet`. Built NEW `executor_designate_card` (amber UNSET / teal SET card + `showModalBottomSheet` picker) that REUSES the workforce-subscribe + `getTableVid(com)` routing + vid/name capture internally. On pick → dispatches `#CHOSEN_DRIVER_VID`/`#CHOSEN_DRIVER_NAME` + bumps a static `chosenRev` RxInt; submit Obx-reads it for the enable gate (enabled once a driver is chosen). `clearO1State` resets these in `clearData`.
3. **§4 count-list** = real source mode (gate `aggregate` non-empty; P6 path byte-identical). Expected plan stored in `CountEntry.planQty`.
4. **§8 OPENs resolved:** `{warehouseId}` = task `gl` (→ `#ACTIVE_WAREHOUSE`; empty if no tasks = degrade-safe) · designate @ submit · opening discrepancy = implicit (checker note TXF, no flag field) · `cnm` = `CHK-{vv}-{YYYYMMDD}` · AD-HOC/role chips DROPPED (role gone since Delta 9; the design showed them but there's no backing field) · submit enabled when a driver is chosen (counts default 0).

---

## C1 (`warehouse-closing-check-c1-dev-spec.md`) corrections

1. **§4 submit — ALL writes native (no `addToEvent`/`updateEventRow`).** Closing doc + `ip[]`+`dp[]`+`rs` in ONE `createNativeDoc(docId: CHK-{vv}-{YYYYMMDD}-C)`; opening `cst◼closed` closed natively by deterministic `openingCnm` (see CRITICAL CORRECTION); R2 investigation by `createNativeDoc(docId: INV-…)`, failure non-blocking. `ldt` is NOT written on the closing doc (vestigial — load-time concept; closing uses `t`).
2. **§1 context rail is a NEW widget, not "TXT reuse".** TXT is static; the rail shows live data. Built NEW `closing_context_rail` (green strip: driver name from the opening doc + "N returnable · M consumable" from asset_cache; renders chrome unconditionally; "tiba" time DROPPED — no clean P12-handover-time source).
3. **§2 count-list** = real 3rd source mode (`source:asset_cache`, gated; P6 + O1 byte-identical). Expected `qt` → `CountEntry.planQty`; submit reconciles `planQty` vs counted `qty`.
4. **Reconcile is a shared pure helper.** `buildReconciliation(expected, actual) → {dp[], rs}` extracted into `driver_home_support.dart`; `custody_reveal._buildDpArray` refactored to delegate (byte-identical incl. dp[] order — uses a LinkedHashSet, not a raw Set). C1 submit calls it.
5. **§3 R1/R2 = TWO routes** (`matchRoute`/`mismatchRoute`, branched at submit by `rs` — the custodyReveal pattern). Each is pure reuse: R1 = NOTICE_BAR success + `CUSTODY_CONFIRMED_LIST`; R2 = NOTICE_BAR warn + `CUSTODY_DISCREPANCY_LIST` + NOTICE_BAR info + escalate/back RBT.
6. **§6 OPENs resolved:** closing = visible · investigation actor = checker `#VID` · R2 still sets opening `cst◼closed` · expected = asset_cache via `CountEntry.planQty` · `{openingCnm}` = deterministic regen (no lookup).

---

## Resolved OPENs (summary)

| OPEN (spec) | Resolution |
|---|---|
| `{warehouseId}` source | task `gl` → `#ACTIVE_WAREHOUSE` (empty if no tasks = degrade-safe) |
| closing blind vs visible | **visible** (shows "Ekspektasi: N") |
| executor picker | NEW `executor_designate_card` (reuses the search mechanism inside) |
| AD-HOC / "Driver tetap" chips | **dropped** — `role` field gone since Delta 9 |
| designate timing | at submit (atomic) |
| opening discrepancy flag | implicit (Admin compares; checker note TXF) |
| `cnm` collision (opening vs closing) | closing gets `-C` suffix |
| investigation actor | checker `#VID` |
| R2 `cst` | opening still set `closed` (investigation runs in parallel) |
| C1 "tiba" time | dropped (no clean P12-handover-time source) |
| H1 `{checkerVid}` | `#VID` (logged-in user) |

## Still genuinely OPEN (not built)

- **Deploy the O1 / C1 / R1/R2 op1Screen config sheets** — the renderers are built + unit-tested, but on-device QA is blocked until the sheets exist (only H1's config is live).
- **CF / movement — P12↔C1 INTERNAL emitter** (handoff §C): who emits the mobil→gudang INTERNAL movement (C1 vs CF) is still open; tracked separately (`docs/driver-runtime-movement-cf-handoff.md`). Until CF is live, `asset_cache` (C1's expected) is hand-seeded; on a device without it, C1 expected shows 0 (degrade-safe).
