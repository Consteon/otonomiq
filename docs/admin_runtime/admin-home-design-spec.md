# Admin Home (H1) — Visual Design Spec

Implementation-ready design SSOT extracted from the 4 reference mockups, cross-checked with `ui-ux-pro-max` (Data-Dense Dashboard style; status green/amber/red; ≥44pt touch; vector icons not emoji; 8dp rhythm). Drives the Flutter coder. Indonesian labels. `theme.primaryColor` ≈ blue below.

> **Icons:** mockups show emoji (🚚 📍 👤 ⛔). Per `no-emoji-icons` + existing widgets → use **Material vector icons** (`Icons.local_shipping_outlined`, `Icons.place_outlined`, `Icons.assignment_return_outlined`, `Icons.person_off_outlined`, `Icons.block_outlined`, `Icons.directions_car_outlined`). Already the pattern in the built signal list.

---

## 1. Color tokens

| Token | Hex | Use |
|---|---|---|
| `primaryBlue` | `#2563EB` | header bg, normal action button, blue text buttons, "+ Tugaskan Kendaraan", "Jadwalkan", "Lihat di Gudang" outline |
| `dangerAmberFill` | `#FFF7E6` | URGENT/cross card BACKGROUND (cream) |
| `dangerAmberBorder` | `#F59E0B` | URGENT/cross card border (1.5px) |
| `amberSolid` | `#F59E0B` | solid amber button (urgent Tugaskan / Assign Ulang / Tunjuk di Gudang), on=white |
| `amberText` | `#B45309` | danger age pill text; KRITIS badge text |
| `greyAgeText` | `#64748B` | normal age/time pill text |
| `violet` | `#7C3AED` | genesis notice text, PERHATIAN badge text |
| `violetBg` | `#EDE9FE` | PERHATIAN badge bg, notice bg |
| `gudangGreenText` | `#16A34A` | GUDANG badge, BERJALAN badge text |
| `gudangGreenBg` | `#DCFCE7` | GUDANG badge, BERJALAN badge bg |
| `tierKritisBg`/`Text` | `#FEF3C7` / `#B45309` | KRITIS badge (outstanding) |
| `tierNormalBg`/`Text` | `#F1F5F9` / `#475569` | NORMAL badge |
| `pageBg` | `#F1F5F9` | scroll body background |
| `cardWhite` | `#FFFFFF` | normal card bg |
| `cardBorder` | `#E5E7EB` | normal card border (1px) |
| `iconTileBg` | `#EAF1FF` | rounded icon tile behind card glyph |
| `titleText` | `#1F2937` | card titles, cluster headers |
| `subText` | `#6B7280` | summary / subline |
| `mutedText` | `#9CA3AF` | address |
| `sectionCaps` | `#94A3B8` | section header caps text |

Map existing helpers: signal-card tier → reuse `statusColor`/`statusBgColor` ONLY where they already match; otherwise use the explicit tokens above (the tier treatment is card-bg-driven, not just icon color — see §3).

## 2. Spacing / radius / type

- **Radius:** header 0 (full-bleed top), cards 12, icon tile 10, pills/badges full (or 8), buttons 10.
- **Spacing (8dp rhythm):** section horizontal pad 16; card inner pad 14; vertical gap between cards 10; icon tile 40×40; chip/badge pad (h10,v4).
- **Touch:** every action button full-width min-height **44**; inline pill buttons (Jadwalkan / + Tugaskan) min tap 44 (use padding/hitarea); 8px+ between adjacent taps.
- **Type scale:**
  - section caps: 12 / w700 / letterSpacing 0.8 / UPPERCASE / `sectionCaps`
  - cluster header (e.g. "2 order menunggu kendaraan"): 14 / w700 / `titleText`
  - card title (customer): 15 / w700 / `titleText`
  - plate title ("B 1234 XY"): 16 / w700 / **monospace-feel** (letterSpacing 1.0, tabular figures)
  - summary / subline: 13 / w400 / `subText`
  - address: 12 / w400 / `mutedText`
  - badge / age / time pill: 11–12 / w700
  - button label: 14 / w700

## 3. Per-widget spec

### 3.1 adminCoordinationHeader — [BUILT, restyle to match]
Blue (`primaryBlue`) full-bleed bar. Row1: map icon + "Koordinasi" (w700 white) + right "⇄ Ganti" translucent-outline pill (white54 border, white text). Row2: **"{adminName} · {plate}"** white70 (plate optional → show name alone if absent). Row3: 2 pills = **translucent-white on blue** (`Colors.white.withOpacity(0.18)` bg, white text) "N berjalan" / "N sinyal" — NOT green/red.
**Divergence from built:** built shows name only + green/red chip bg below. Fix → add `{plate}` line (optional) + chips become translucent-white-on-blue.

### 3.2 coordinationSignalList — [BUILT, significant restyle]
- **Section header:** "PERLU TINDAKAN" = section caps.
- **Cluster header:** dark bold `titleText` (e.g. "2 order menunggu kendaraan"); cross clusters append a **GUDANG** green badge (`gudangGreenBg`/`Text`) right of the text ("1 mobil belum ada pengantar GUDANG", "1 mobil belum bisa berangkat GUDANG").
- **Card by tier/type:**
  - **danger (urgent admin)** → bg `dangerAmberFill`, border `dangerAmberBorder` 1.5px, action = **solid amber** (`amberSolid`).
  - **normal admin** → bg white, border `cardBorder`, action = **solid blue** (`primaryBlue`).
  - **no_executor (cross)** → bg `dangerAmberFill` + amber border, action = **solid amber** "Tunjuk di Gudang ⇄".
  - **blocked_departure (cross, soft)** → bg white + border, action = **outline blue** "Lihat di Gudang ⇄".
- **Card body:** icon tile (40×40, `iconTileBg`, vector glyph per type) + title (customer = title type; plate = plate type) + age pill top-right (`amberText` on faint amber for danger, `greyAgeText` for normal) + summary `subText` + 📍→`Icons.place_outlined` address `mutedText` + full-width action button (44h).
**Divergence from built:** built = always-white card, tier color only on icon+pill, blue/outline button, grey-caps cluster header, no GUDANG badge, no icon tile. Restyle to the above.

### 3.3 displayStatisticCard "BERJALAN" — [NEW]
White card, border `cardBorder`. Plate title (plate type, big). Subline "{driver} · Stop {x} dari {y}" `subText`. 2nd subline "{lastStopName} selesai" `mutedText`. Top-right **BERJALAN** badge (`gudangGreenBg`/`Text`). Read-only (no action). Section caps header "BERJALAN".
Data: vehicle_check `cst=custody_confirmed` `cdt={today}` (or task `tst=on_delivery`); progress {x}/{y} = completed/total task per vehicle ({dev}); driver = workforce/dv denorm (degrade: hide if absent).

### 3.4 displayStatisticCard "AKAN DATANG" — [NEW]
White cards. Title = customer (`kn`). Top-right **time pill** ("13:00" from `tdt` formatted HH:mm, grey pill). Summary line = item roll-up from `it[]` ("Pickup 5 Gas 3kg" / "Drop 6 · Pickup 5 Gas 12kg" — Σpd/Σpp {dev}). Footer: if `vv` set → vector truck + plate (`subText`); if `vv` null → inline **"+ Tugaskan Kendaraan"** blue text-pill button → launches vehiclePicker(assign,{taskVid}). Section caps "AKAN DATANG".
Data: task `tst=assigned` `tdt={today}` (exclude `load_rejected`).

### 3.5 displayStatisticCard "PRIORITAS PENGAMBILAN" (outstanding) — [NEW, collapsible]
Single white card containing a **collapsible** section: header row "PRIORITAS PENGAMBILAN" (section caps) + chevron (rotates; default **expanded**). Rows (inset dividers between): **tier badge** + customer name (`titleText`) + sub "{item} · {n} pcs · {hari} hari" (`subText`) + right **outline-blue "Jadwalkan"** button.
- tier by aging days: KRITIS (`tierKritis*`) / PERHATIAN (`violet*`) / NORMAL (`tierNormal*`).
- aging = now − `asset_cache.t` (days, {dev}). `hideZero` (skip net-0).
Data: asset_cache `lt=client` grouped by `lv`; CF-gated → empty until seed. "Jadwalkan" → vehiclePicker(schedule) **DEFERRED** (needs create-with-array) → dead-route/disabled in this slice (per H1 contract); render button but no-op/snackbar until wizard.

## 4. Quality gates (ui-ux-pro-max)
- Touch ≥44pt every action; 8px spacing. · Loading: vehiclePicker confirm already shows spinner. · Empty state: each stat-list collapses (SizedBox.shrink) when 0 rows (no blank frame). · Contrast: amberText/violet/green on their light bg + titleText on white all ≥4.5:1. · No emoji-as-icon → vector. · Vector icon family consistent (outlined set). · prefers-reduced-motion: chevron rotate ≤200ms, respect. · Plate uses tabular/mono figures (no layout shift).
