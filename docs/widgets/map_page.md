# MapPage

`lib/page/map_page.dart` · helpers in `lib/page/map_page_support.dart`

A full-screen map pushed with the **real Flutter Navigator**. It is not an SDUI
component — no `type` dispatches to it. Its only caller is the "Lihat Peta"
button on [LocationDetector](location_detector.md).

## Sheet config

Nothing new to author. The screen is turned on by the **one cell** that already
carries the card's variant — `op1Screen!K132` (the `[VARIANT]` substituted into
the `locationDetector` builder row), `v4` → `v6`. It propagates
`K132 → D132 → E132 → B128 (CONCATENATE E129:E192) → B126` on its own, and the
page is already registered in `Plug!D`, so no registry row is needed.

The geofence radius the map draws is the site's own **Tolerance (meter)** from
`op1!M12:M211` — already populated live (30 / 100 / 200 m). A blank there would
draw a zero-radius ring, so a new site needs that column filled.

## Parameters

| Param | Type | Default | Description |
|---|---|---|---|
| `lat` / `lng` | `double` | required | The position to open on. Asserted in range. |
| `title` | `String` | required | AppBar title (classic) / bar title (v6). |
| `variant` | `String` | `''` | `v6` (trimmed, case-folded) selects the v6 layout. Anything else — absent, blank, `v4` — keeps the classic screen. |
| `accuracy` | `double?` | `null` | The caller's last accuracy reading, in metres. **v6 only.** Null means "no fix yet" and the sheet opens searching. |

## Classic

`AppBar` with the plain title, an OSM map, one red `Icons.location_pin`, and a
`FloatingActionButton` that re-acquires the position. Unchanged; every caller
that does not pass `variant: "v6"` still gets exactly this.

## `variant: "v6"` — the Vertika v6 location screen

Opted into by setting `variant: "v6"` on the `LOCATION_DETECTOR` component.
That single cell also keeps the v4 card (`_isV4` accepts `v4` **or** `v6`), so
a tenant moving `v4` → `v6` keeps the home panel it already approved and gains
this screen; a tenant left on `v4` sees nothing change.

The screen answers one question — *am I inside the area, and how sure is that?*
It never submits attendance: the Masuk/Pulang context does not exist here, so
the block on Beranda keeps that job.

**Bar** — navy (`Theme.of(context).primaryColor`, the same source the app bar
is painted with). Title 16/500, subtitle 12/500 white @ 86 %: `"<site> · area
absen"`, or just `"area absen"` when no site matched.

**Two objects, two visual languages.** The old screen had one red pin that could
equally have been the user or the site.

| Object | Drawn as |
|---|---|
| Geofence | `CircleMarker`, radius in **metres** from `#LQR_LIST`, fill `primary` @ 10 %, border 2 dp `primary`; navy pin + 11/600 label at the centre |
| Geofence, outside | Fill switches to `dangerMark` @ 6 % and the ring is redrawn as a **dashed** `Polyline` (`CircleMarker` has no dash pattern, so the outside state draws a 72-segment ring instead — the circle marker's own border is turned off so there is only ever one ring) |
| You | 16 dp `v6Secondary` dot, 3 dp white ring |
| Your accuracy | `CircleMarker`, radius = accuracy in metres, teal @ 14 % — **amber** above `kCoarseAccuracyMeters` |

A two-chip legend sits top-left, `ExcludeSemantics` because the sheet says the
same thing in sentences.

**Controls** — two 44 dp round buttons top-right, both with accessibility
labels: *Pusatkan ke posisi saya* (carries `Semantics(selected:)`, and the map
drops out of follow on any hand pan) and *Tampilkan seluruh area absen*, which
re-runs the initial fit. `Perbarui lokasi` is a labelled 48 dp full-width tonal
button in the sheet, not a FAB — a floating icon in the corner of a map is the
control most easily mistaken for part of the map.

### The status rule

One rule, in `map_page_support.dart` — the card's own test, reported in three
parts instead of two:

```
inside  : distance <= radius                     ← inside the ring that is DRAWN
outside : distance >  radius + accuracy * 2      ← past the card's own tolerance
unsure  : everything between the two
```

`LocationDetector` calls you inside for the whole `radius + accuracy * 2` zone,
deliberately generous so a shaky fix does not lock anyone out. On a card that
draws no map that is invisible. On a map it is not: **live tolerances are as
low as 30 m** (`op1!M12:M211`), so a 20 m fix stretches the accepted zone to
70 m — and a green "Di dalam area" over a picture of the user plainly outside
the ring is exactly the dishonesty this redesign exists to remove.

So the middle band reports `unsure` — *"Tepat di luar batas area, masih dalam
toleransi GPS ±N m"*. The two screens still never contradict each other:
card-inside covers `inside` + `unsure`, card-outside is `outside` exactly.
Accuracy only widens the middle band; it never flips an answer. Locked by an
exhaustive sweep in the tests.

Two accuracy thresholds, and neither decides the status:

| Constant | Value | Drives |
|---|---|---|
| `kLowAccuracyMeters` | 30 m | The amber **number** + the warning callout. Same 30 m the card's "Akurasi Rendah" chip already uses. |
| `kCoarseAccuracyMeters` | 75 m | The amber accuracy **circle** only. |

**States the sheet owns** — five:

| State | Dot | Word | Sentence |
|---|---|---|---|
| searching | `borderStrong` | Mencari lokasi… | Biasanya kurang dari 10 detik di luar ruangan |
| inside | `successMark` | Di dalam area | Absen GPS bisa dilakukan dari posisi ini |
| outside | `dangerMark` | Di luar area | Mendekatlah ±N m ke arah `<site>` …, atau gunakan QR/Selfie |
| unsure | `borderStrong` | Belum bisa dipastikan | Tepat di luar batas area, masih dalam toleransi GPS ±N m |
| no site | `borderStrong` | Posisi Anda | Tidak ada area absen terdaftar untuk akun ini |

Below it, three tabular figures — **Ke batas / Akurasi / Radius** — each
rendering `—` (never `0 m`) when the value is unknown. "Ke batas" is unsigned;
the status word says which side it is measured from.

**Location off / permission denied** — the whole body is replaced by the same
empty state the v6 QR screen uses for a denied camera: 72 dp muted icon, 20/600
title, 15 body, one filled accent CTA, a text link back. Services-off opens
`Geolocator.openLocationSettings()`, denied permission opens
`openAppSettings()`. Both are re-tested on `AppLifecycleState.resumed`, because
Settings is exactly where the user just went to change them.

**Coming back** — v6 re-reads the fix when the map pops, so the card cannot go
on showing a status the map already contradicted. Classic keeps its old
behaviour (no re-read).

### Contrast

| Element | Ratio | Bar |
|---|---|---|
| Status word, success `#047857` on white | 5.48:1 | 4.5:1 ✔ |
| Status word, danger `#B91C1C` on white | 6.47:1 | 4.5:1 ✔ |
| Status dot `#059669` / `#DC2626` / `#7B869F` | 3.77 / 4.83 / 3.65:1 | 3:1 non-text ✔ |
| Stat value `#0F172A` on `#EEF0F4` | 15.65:1 | 4.5:1 ✔ |
| Stat label `#475569` on `#EEF0F4` | 6.64:1 | 4.5:1 ✔ |
| Warning text `#854D0E` on `#FEF9E3` | 6.48:1 | 4.5:1 ✔ |
| "You" dot `#0F9AB0` on white | 3.35:1 | 3:1 non-text ✔ |
| Accent CTA `#F08118` on `#1A1206` | 6.94:1 | 4.5:1 ✔ |

The teal is a mark and never a label — the same rule `theme_tokens.dart` states
for every `*OnDark` and `*Mark` colour.

## Deviations from the mock

- **No grab handle on the sheet.** The mock draws one; the sheet does not drag,
  and a handle that does nothing is a promise the screen cannot keep. The
  sheet scrolls internally instead, which is what stops it overflowing in
  landscape.
- **The fit padding is estimated, not measured** (250 dp, 300 dp with the
  warning box). It only ever costs a slightly loose frame; a `GlobalKey`
  measurement is the upgrade if that ever shows.
- **Microcopy is hardcoded Indonesian**, not sheet-driven — same call as the v6
  QR screen. Eight instructional strings that no tenant varies; the site name
  and the screen title still come from the sheet and `#LQR_LIST`.

## Tests

`test/map_page_v6_test.dart` — 16 tests over `map_page_support.dart`:
`nearestLqrSite` (nearest of several, null/empty/malformed `#LQR_LIST`,
String-typed coordinates), the status rule at both edges of the `unsure` band,
on the mock's three drawn frames and under an exhaustive sweep that asserts it
can never contradict the card, and the `—` formatting. The screen itself is not pumped:
`FlutterMap` reaches for tiles and `Geolocator` for a channel. The look is
checked on a device.

## See Also

- [location_detector.md](location_detector.md) — the only caller
- [ftz_scanner_screen.md](ftz_scanner_screen.md) — the v6 QR camera, same
  empty-state skeleton
- [map_point_picker.md](map_point_picker.md) — the coordinate *picker* (a
  different widget: it writes a form value, this one only looks)
