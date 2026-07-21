# MAP_POINT_PICKER

**Status:** draft
**Source:** `lib/widget/map_point_picker.dart`
**Dispatch:** `build_display_component.dart` — `tip == 'map_point_picker'`

## Purpose

Form-field widget that lets the user pick geographic coordinates (lat,long)
via GPS one-tap or a fullscreen drag-to-pick map screen. Final value is a
locale-independent string `"lat,long"` (dot decimal, 6 dp). Designed to
replace manual spreadsheet coordinate entry that corrupts decimals under
id_ID locale.

## Config

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `position` | int/String | yes | — | Main value slot: `"lat,long"` |
| `label` | String | yes | `''` | Field label |
| `addressPosition` | String | no | `''` | Optional slot for geocoded display name |
| `latPosition` | String | no | `''` | Optional slot for latitude only |
| `lngPosition` | String | no | `''` | Optional slot for longitude only |
| `initialCenter` | String | no | `''` | `"lat,long"` initial map center |
| `zoom` | num | no | `17` | Initial zoom level |
| `searchEnabled` | String | no | `TRUE` | Show search bar on map |
| `searchCountry` | String | no | `''` | Nominatim country bias |
| `text` | String | no | `''` | Diamond-separated labels (10 segments) |

## Text segments

0=placeholder, 1=GPS button, 2=map button, 3=change button,
4=search hint, 5=confirm button, 6=loading, 7=GPS error, 8=network error,
9=clear button (`Hapus`).

## Clearing

Selected state shows a red **Hapus** button next to **Ganti Lokasi**. It
resets the widget to empty and blanks the main slot plus
`latPosition`/`lngPosition`/`addressPosition`, so submit sees no stale value.

## Dependencies

- `flutter_map` (OSM tiles)
- `latlong2` (LatLng type)
- `geolocator` (GPS)
- `http` (Nominatim API)

All already in `pubspec.yaml`.

## See Also

- `location_detector.dart` — read-only GPS display card (opens `map_page.dart`)
- `map_page.dart` — read-only map viewer (fixed marker, no pick)
