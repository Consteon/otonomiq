# LocationDetector

GPS-based location widget that detects the user's position, determines inside/outside status relative to registered reference points, and displays address with accuracy info.

- **File:** [lib/widget/location_detector.dart](../../lib/widget/location_detector.dart)
- **Class:** `LocationDetector` (StatefulWidget)
- **Status:** done
- **Widget version:** v1
- **Dependencies:** `geolocator`, `geocoding`

## Purpose

Provides a location detection card that:
1. Acquires the device's GPS position via Geolocator.
2. Determines whether the device is **inside** or **outside** a registered site by comparing distance to LQR (Location Query Reference) points stored in `transactionStore.state.screenTx['#LQR_LIST']`.
3. Resolves a human-readable address via reverse geocoding (or uses the LQR location name when inside a site).
4. Displays status indicator, address, accuracy, and optional "View Map" / "Refresh" buttons.

Use this widget when the screen needs to show the user's current location status (e.g. attendance verification, site check-in).

## Signature / Constructor

```dart
const LocationDetector({
  required Key key,
  required dynamic component,
  required String scrName,
  required bool single,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `single` | `bool` | yes | — | Standard flag from the v2 component family |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `text` | `String` | Diamond-separated (`◆`) bundle of label strings — see text parts table below. |
| `gps` | `Map?` | GPS configuration. Currently reads `gps['status']` as fallback status string. |
| `showViewMap` | `String/bool?` | Whether to show the "View Map" button. Accepts `"TRUE"`/`"FALSE"`. Default `TRUE`. |
| `showRefresh` | `String/bool?` | Whether to show the "Refresh" button. Accepts `"TRUE"`/`"FALSE"`. Default `TRUE`. |
| `borderRadius` | `num?` | Card corner radius in px. Default `10`. |

### `text` parts

`component['text']` is split by `◆` into up to 11 parts:

| Index | Purpose | Default |
|---|---|---|
| `0` | Header label (uppercased) | `"LOCATION"` |
| `1` | "Inside" status label | `"Inside Site"` |
| `2` | "Outside" status label | `"Outside Site"` |
| `3` | "Near Boundary" / "Last Known" status label | `"Near Boundary"` or `"Last Known"` |
| `4` | High accuracy label | `"High Accuracy"` |
| `5` | Low accuracy label | `"Low Accuracy"` |
| `6` | Accuracy prefix symbol | `"±"` |
| `7` | Accuracy unit suffix | `"m"` |
| `8` | "View Map" button label | `"View Map"` |
| `9` | "Refresh" button label | `"Refresh"` |
| `10` | Fallback address when location not found | `"Location not found"` |

## GPS Status Logic

The widget determines status by checking `transactionStore.state.screenTx['#LQR_LIST']` — a map of registered location reference points.

### LQR List Structure

Each entry in `#LQR_LIST` is a `List`:
```
[locationName, latitude, longitude, toleranceMeters]
```

### Status Derivation (`_deriveGpsStatus`)

```
for each LQR entry:
  zone2 = tolerance + (position.accuracy × 2)
  distance = distanceBetween(target, current)
  if distance ≤ zone2 → "inside"

if no match → "outside"
if #LQR_LIST is null/empty → fallback to gps['status'] or "last_known"
```

### Status Display

| Status | Color | Description |
|---|---|---|
| `inside` | Green (`#22C55E`) | Device is within zone2 of at least one LQR point |
| `outside` | Red (`#EF4444`) | Device is beyond zone2 of all LQR points |
| `near_boundary` | Amber (`#F59E0B`) | (Reserved — not currently derived, only via server config) |
| `last_known` | Gray (`#6B7280`) | Default / fallback when LQR list unavailable |

### Accuracy Levels

| Level | Condition | Meaning |
|---|---|---|
| `high` | accuracy ≤ 15m | Reliable GPS fix |
| `medium` | accuracy ≤ 30m | Acceptable but less precise |
| `stale` | accuracy > 30m | Poor signal or cached position |

## Address Resolution

- **Inside a site**: Uses the LQR entry's `locationName` (index 0) directly — no geocoding API call.
- **Outside**: Calls `placemarkFromCoordinates()` and formats: `subLocality, locality, administrativeArea, postalCode`. The `Kecamatan` prefix is stripped from `locality`.
- **Fallback**: Uses `text[10]` or `"Location not found"` on any error.

## Usage Example (Screen JSON)

```json
{
  "type": "LOCATION_DETECTOR",
  "text": "Lokasi◆Di Dalam Area◆Di Luar Area◆Terakhir Diketahui◆Akurasi Tinggi◆Akurasi Rendah◆±◆m◆Lihat Peta◆Segarkan◆Lokasi tidak ditemukan",
  "gps": { "status": "last_known" },
  "showViewMap": "TRUE",
  "showRefresh": "TRUE",
  "borderRadius": 12
}
```

### Minimal config (all defaults)

```json
{
  "type": "LOCATION_DETECTOR",
  "text": "Location"
}
```

## State / Bloc / Dependencies

- **Store:** `transactionStore.state.screenTx['#LQR_LIST']` — read-only access to registered location reference points.
- **Packages:** `geolocator` (GPS acquisition, distance calculation), `geocoding` (reverse geocoding).
- **Navigation:** Opens [`MapPage`](../../lib/page/map_page.dart) when "View Map" is tapped.
- **No `txfController` access** — this widget is display-only and does not write to any form state.

## Important Behavior

- **Auto-fetches on init** — calls `_fetchLocationData()` in `initState`. No user action needed to get initial position.
- **Permission handling** — requests location permission if denied; shows fallback address if permission denied forever.
- **zone2 formula** — `tolerance + (accuracy × 2)` provides a buffer that accounts for GPS inaccuracy, reducing false "outside" readings at site boundaries.
- **Inside → skip geocoding** — when inside a registered site, the LQR name is used directly. This avoids unnecessary geocoding API calls and provides a more meaningful label (site name vs street address).
- **Updated-at display** — shows relative time ("just now", "30s ago", "2 min ago", "1 hr ago") since last successful fix.
- **Mounted checks** — all async callbacks verify `mounted` before calling `setState` to prevent errors on widget disposal.

## UI Layout

```
┌─────────────────────────────────────────┐
│ 📍 LOCATION                             │  ← header (text[0])
│                                         │
│ ● Inside Site                           │  ← status dot + label
│ Warehouse A, Building 3                 │  ← address or LQR name
│ ⚡ High Accuracy ±8m · Updated just now │  ← accuracy row
│ ─────────────────────────────────────── │
│ [ 🗺 View Map ]  [ 🔄 Refresh ]        │  ← action buttons
└─────────────────────────────────────────┘
```

## See Also

- [MapPage](../../lib/page/map_page.dart) — full-screen map opened by "View Map" button
- [attendance_qr_selfie_gps_verify.dart](../../lib/widget/attendance_qr_selfie_gps_verify.dart) — attendance widget that also uses GPS verification
