# Stepper Widget — Dev Spec

Spec lengkap widget stepper (`STEPPER`) untuk Consteon/VTL platform. 1 base widget cover 4 use case (default counter, with unit & helper, long-press, compact + boundary-disabled). Dipakai untuk semua skenario numeric stepper di mobile app.

**Widget tab name:** `stepper`
**Type code:** `STEPPER`
**Base template row:** `Widget!J190` (next free row, append after `textSearch`@189)
**Master index entry:** `◆stepper▶Widget!J190` (append to `Widget!G1`)

---

## 1. Konsep

Widget numerik dengan 3 kontrol: `[−]` decrement, value display, `[+]` increment. Optional helper text di bawah row untuk computed feedback (e.g. "X tersisa setelah pengambilan").

**Konsep utama:**

- 4 variant visual di-handle 1 widget — beda hanya di params
- Boundary disabled (`−` di `min`, `+` di `max`) = **implicit** dari `min`/`max` field, BUKAN param terpisah
- Helper text optional, support runtime token `<remain>` untuk computed value
- Unit (`pcs`, `orang`, dll.) optional, tampil inline di samping value
- Long-press accelerate = flag di payload, app handle gesture

---

## 2. Base JSON Template

`Widget!J190`:

```json
{"type":"STEPPER","variant":"[VARIANT]","icon":"[ICON]","currentValue":"[INITIAL]","min":[MIN],"max":[MAX],"step":[STEP],"longPress":"[LONGPRESS]","stockAvailable":[STOCKAVAILABLE],"position":[POSITION],"text":"[LABEL]◆[SUBTITLE]◆[UNIT]◆[HELPERTEMPLATE]"}
```

**Demo resolved (variant default), `Widget!G190`:**

```json
{"type":"STEPPER","variant":"default","icon":"","currentValue":"1","min":0,"max":99,"step":1,"longPress":"FALSE","stockAvailable":0,"position":3,"text":"Jumlah item◆Range 0-99◆◆"}
```

---

## 3. Placeholder Catalog

| Placeholder | Type | Required | Default | Notes |
|-------------|------|----------|---------|-------|
| `[VARIANT]` | string | YES | `default` | Enum: `default` \| `withUnit` \| `longPress` \| `compact` |
| `[ICON]` | int/string | NO | `""` | Material icon code or name, empty = no icon |
| `[INITIAL]` | int (as string) | YES | `"0"` | Starting value, must be within `min`-`max` |
| `[MIN]` | int | YES | `0` | Floor — `−` button disabled when `currentValue == min` |
| `[MAX]` | int | YES | `99` | Ceiling — `+` button disabled when `currentValue == max` |
| `[STEP]` | int | NO | `1` | Increment/decrement amount per tap |
| `[LONGPRESS]` | bool string | NO | `"FALSE"` | `"TRUE"` = hold-to-accelerate enabled |
| `[STOCKAVAILABLE]` | int | NO | `0` | Source for `<remain>` token; `0` = no stock constraint |
| `[POSITION]` | int | YES | — | Form field index (1-based) for `◁N▷` reference |
| `[LABEL]` | string | YES | — | Row title, ◆ segment 1 |
| `[SUBTITLE]` | string | NO | `""` | Secondary line (range/hint/stock), ◆ segment 2 |
| `[UNIT]` | string | NO | `""` | Inline unit next to value (`pcs`, `orang`), ◆ segment 3 |
| `[HELPERTEMPLATE]` | string | NO | `""` | Helper text below row, ◆ segment 4, supports `<remain>` |

---

## 4. Text Mapping (`◆`-delimited)

Single `text` field, 4 segments separated by `◆`:

```
"[LABEL]◆[SUBTITLE]◆[UNIT]◆[HELPERTEMPLATE]"
```

| Segment | Index | Empty form |
|---------|-------|------------|
| Label | 0 | required |
| Subtitle | 1 | `""` (trailing `◆` retained) |
| Unit | 2 | `""` |
| Helper | 3 | `""` |

**Empty trailing segments tetap di-encode dengan `◆`** — renderer count segments by `◆` index, bukan length.

Contoh empty subtitle/unit/helper: `"Jumlah item◆◆◆"`

---

## 5. Runtime Tokens

Token yang TIDAK di-resolve di build-time, di-handle app runtime:

| Token | Resolution | Scope |
|-------|------------|-------|
| `<remain>` | `stockAvailable - currentValue` | Inside `[HELPERTEMPLATE]` |
| `◁[POSITION]▷` | Current stepper value | Used in sibling sendButton's `addToTable` |

**Runtime helper resolution:**

```
helperText = HELPERTEMPLATE.replace("<remain>", stockAvailable - currentValue)
```

If `stockAvailable == 0`, render `<remain>` as raw or hide helper (renderer choice).

---

## 6. Variant Behavior

### 6.1 `default`

Plain counter, no unit, no helper. Visual: standard pill `[−] N [+]`.

**Visual:**
```
Jumlah item
Range 0-99                   [−] 1 [+]
```

**Resolved JSON:**
```json
{"type":"STEPPER","variant":"default","icon":"","currentValue":"1","min":0,"max":99,"step":1,"longPress":"FALSE","stockAvailable":0,"position":3,"text":"Jumlah item◆Range 0-99◆◆"}
```

### 6.2 `withUnit`

Value displayed with unit suffix (`12 pcs`). Helper text below.

**Visual:**
```
Galon 19L
Stok tersedia: 48          [−] 12 pcs [+]
                           36 tersisa setelah pengambilan
```

**Resolved JSON:**
```json
{"type":"STEPPER","variant":"withUnit","icon":"","currentValue":"12","min":0,"max":48,"step":1,"longPress":"FALSE","stockAvailable":48,"position":4,"text":"Galon 19L◆Stok tersedia: 48◆pcs◆<remain> tersisa setelah pengambilan"}
```

**Runtime:** `<remain>` = 48 - 12 = 36.

### 6.3 `longPress`

Long-press on `[−]` / `[+]` accelerates increment (step × N per second). For large-quantity inputs.

**Visual:**
```
Botol kosong dikembalikan
Tahan tombol untuk cepat     [−] 0 [+]
```

**Resolved JSON:**
```json
{"type":"STEPPER","variant":"longPress","icon":"","currentValue":"0","min":0,"max":999,"step":1,"longPress":"TRUE","stockAvailable":0,"position":5,"text":"Botol kosong dikembalikan◆Tahan tombol untuk cepat◆◆"}
```

### 6.4 `compact`

Smaller height, denser layout. Boundary-disabled behavior identical to other variants (auto from `min`/`max`).

**Visual (current=1, min=1 → `−` disabled):**
```
Tim cleaner
Min 1, max 8 orang           [−] 1 [+]
                              ↑ disabled (currentValue == min)
```

**Resolved JSON:**
```json
{"type":"STEPPER","variant":"compact","icon":"","currentValue":"1","min":1,"max":8,"step":1,"longPress":"FALSE","stockAvailable":0,"position":6,"text":"Tim cleaner◆Min 1, max 8 orang◆orang◆"}
```

---

## 7. Renderer Contract (Flutter/React Native)

### 7.1 Init

1. Parse JSON
2. Initialize internal state: `currentValue = parseInt(json.currentValue)`
3. Set field handler at `position` → expose `currentValue` to form bus

### 7.2 Render

1. Parent row container (variant-driven height: `compact` = smaller)
2. Top row: Label (bold) → Subtitle (muted) — left side
3. Right side: Stepper control
   - `[−]` button — disabled if `currentValue <= min`
   - Value display: `currentValue` + (` ${unit}` if unit non-empty)
   - `[+]` button — disabled if `currentValue >= max`
4. Below row (if `helperTemplate` non-empty AND segment 3 of text non-empty):
   - Replace `<remain>` with `(stockAvailable - currentValue)`
   - Render as muted helper line

### 7.3 Interactions

- Single tap `[−]` / `[+]` → `currentValue ± step`, clamp to `[min, max]`
- If `longPress == "TRUE"`:
  - Hold `[−]` / `[+]` → repeat every 100ms after 500ms initial delay
  - Accelerate after 2s hold (interval → 50ms)
- Update binding emit on every change

### 7.4 Boundary States

| Condition | Effect |
|-----------|--------|
| `currentValue == min` | `[−]` disabled (greyed, no tap) |
| `currentValue == max` | `[+]` disabled |
| `currentValue == min == max` | Both disabled |
| `min > max` (config bug) | Render error: `Invalid range` |
| `currentValue` outside range | Clamp to nearest bound, log warning |

### 7.5 Variant-specific styling

| Variant | Height | Stepper size | Helper visible |
|---------|--------|--------------|----------------|
| `default` | 64dp | normal | no |
| `withUnit` | 80dp (with helper) | normal | yes (if template) |
| `longPress` | 64dp | normal | no |
| `compact` | 48dp | small | no |

---

## 8. Integration with `addToTable`

Stepper value diakses via `◁[POSITION]▷` di sibling sendButton's `addToTable` payload.

**Contoh page dengan 3 stepper:**

```
position 3 → Jumlah item (stepper variant default)
position 4 → Galon 19L (stepper variant withUnit)
position 5 → Botol kosong (stepper variant longPress)
position 7 → sendButtonGpsAddTable
```

`addToTable` di position 7 button:

```
$test/inventory//vtl.stock-take⭘retention◼4320⭘tablevid◼20342033315492⭘flag◼stock-take⭘<1>◼stock-take⭘<2>◼◀2|T7|Ddd MMM yyyy HH:mm▶⭘<3>◼87544551624342⭘<4>◼Agenia Demo-7⭘<5>◼◁3▷⭘<6>◼◁4▷⭘<7>◼◁5▷
```

Mapping:
- `<5>` = jumlah item dari stepper position 3
- `<6>` = galon count dari stepper position 4
- `<7>` = botol kosong dari stepper position 5

---

## 9. Op1Screen Integration

### 9.1 Widget row in op1Screen

| Col | Value |
|-----|-------|
| A | (auto from header ARRAYFORMULA) |
| B | `stepper` |
| C | (empty) |
| D | Resolved JSON (full, no leading comma) |
| E | `,` + resolved JSON |
| F | `TRUE` |

### 9.2 Param columns (G onwards, sibling convention)

Order ditentukan saat 1st instantiation di op1Screen. Recommended convention:

| Col | Param |
|-----|-------|
| G | `VARIANT` |
| H | `INITIAL` |
| I | `MIN` |
| J | `MAX` |
| K | `STEP` |
| L | `LONGPRESS` |
| M | `STOCKAVAILABLE` |
| N | `POSITION` |
| O | `LABEL` |
| P | `SUBTITLE` |
| Q | `UNIT` |
| R | `HELPERTEMPLATE` |
| S | `ICON` |

`widget-placeholder-resolver` agent akan map by this convention saat substitusi.

---

## 10. Validation Rules

Saat write ke op1Screen, agent + QA wajib validate:

1. `MIN <= INITIAL <= MAX`
2. `STEP >= 1`
3. `POSITION` unique di page (no collision dengan widget lain)
4. `STOCKAVAILABLE >= INITIAL` jika `<remain>` ada di helper template
5. `LONGPRESS` ∈ `{"TRUE", "FALSE"}` (string, bukan boolean)
6. `VARIANT` ∈ `{default, withUnit, longPress, compact}`
7. `text` segments count == 4 (3× `◆`)
8. `currentValue` di-encode as string in JSON (per existing widget convention)

---

## 11. Edge Cases

| Case | Behavior |
|------|----------|
| `MAX < MIN` | Renderer error, log + fallback to single static value |
| `INITIAL` di luar `[MIN, MAX]` | Clamp di init, emit binding |
| `STEP` > `MAX - MIN` | Step capped at range — single tap = goes to bound |
| Empty `UNIT` + `withUnit` variant | Render as `default` style (no unit shown) |
| `<remain>` di template tapi `STOCKAVAILABLE == 0` | Render `<remain>` literal or hide helper (impl choice) |
| `POSITION` di-reuse dari widget non-numeric | Binding error — STEPPER expects integer field |

---

## 12. Add Widget to Spreadsheet (1-time)

**Step 1:** Append row di Widget tab:

| Cell | Value |
|------|-------|
| `A190` | `stepper` |
| `G190` | Demo resolved JSON (variant default) |
| `I190` | `stepper` |
| `J190` | Base template dari section 2 |

**Step 2:** Update `Widget!G1` master index — append `◆stepper▶Widget!J190` at end of string.

**Step 3:** Verify Widget!G190 renders correctly (no `[X]` leftover in demo).

---

## 13. Reference Checklist

Before declaring widget ready:

- [ ] Widget!J190 base template written
- [ ] Widget!G1 master index updated
- [ ] Widget!G190 demo renders OK
- [ ] Renderer implementation for 4 variants done
- [ ] Boundary disable logic verified (currentValue at min/max)
- [ ] `<remain>` runtime token computed correctly
- [ ] Long-press timing (500ms initial, 100ms repeat, accelerate to 50ms) implemented
- [ ] addToTable integration tested via `◁[POSITION]▷`
- [ ] Sibling-page param column convention documented in op1Screen page
- [ ] QA agent (`widget-qa`) sign-off

---

## 14. Test Cases

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Tap `[+]` on `default` at value 5 | value=6, `[−]` enabled |
| 2 | Tap `[−]` on `compact` at min=1, current=1 | No change, `[−]` greyed |
| 3 | Long-press `[+]` on `longPress` for 3s | Value accelerates to ~30+ |
| 4 | `withUnit` value change | Helper `<remain>` updates live |
| 5 | Empty UNIT + variant=`withUnit` | Renders without unit suffix |
| 6 | `STEP=5`, range 0-99, tap `[+]` 3× from 0 | value=15 |
| 7 | `INITIAL="invalid"` | Init falls back to MIN, log warning |
| 8 | `MIN=0, MAX=0` | Both buttons disabled, value stuck at 0 |

---

## 15. Future Extensions

Out-of-scope tapi possible:

- **Decimal step:** `STEP=0.5`, `currentValue` as float. Need `decimals` param.
- **Custom display formatter:** template like `Rp <value>` di samping value (tapi conflict with current `[UNIT]` concept)
- **Programmatic disable:** explicit `[ISENABLED]` placeholder override (current spec: implicit only)
- **Range slider variant:** dual-thumb min/max range (different widget type, NOT same STEPPER)

Tambah nanti dengan new variant tag atau new placeholder, **tanpa break existing 4 variants**.

---

## 16. Versi & History

- v1.0 (2026-05-26) — Initial spec, 4 variants, runtime `<remain>` token, boundary-implicit disable
