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
| `pasteEnabled` | String | no | absent = OFF | `"TRUE"` shows a "paste a Google Maps link" field on the fullscreen map |
| `noteEnabled` | String | no | absent = OFF | `"TRUE"` shows an optional note field under the compact card. Requires `addressPosition` |
| `text` | String | no | `''` | Diamond-separated labels (15 segments) |

## Text segments

0=placeholder, 1=GPS button, 2=map button, 3=change button,
4=search hint, 5=confirm button, 6=loading, 7=GPS error, 8=network error,
9=clear button (`Hapus`).

v2 appended, read only when the matching gate is on:
10=paste field label, 11=paste field hint, 12=link-has-no-coordinates error,
13=note field label, 14=note field hint.

Segments are append-only — 9 is `Hapus` and must never be renumbered. Segment 8
is currently **never read** by the renderer; it is kept only to hold the
positions of everything after it. Every segment is read through
`mapPickerSlot()`, which falls back on both out-of-range and empty, so a
10-segment v1 config renders unchanged.

## Clearing

Selected state shows a red **Hapus** button next to **Ganti Lokasi**. It
resets the widget to empty and blanks the main slot plus
`latPosition`/`lngPosition`/`addressPosition`, so submit sees no stale value.
When `noteEnabled` is on, **Hapus** also blanks the note.

## Paste a Google Maps link (`pasteEnabled`)

A field on the fullscreen map screen accepts a Google Maps link pasted from
WhatsApp, or bare `lat, lng` text. Coordinates are read straight out of the
text — **no Google API, zero cost**. Recognised, most precise first: the
`!3d/!4d` data pair, `?q=lat,lng` (incl. `q=loc:`), `?api=1&query=lat,lng`
(Google's own Maps-URLs share format, comma may be `%2C`),
`/maps/place/lat,lng`, the `@lat,lng` viewport, and bare `lat, lng`.

`maps.app.goo.gl` / `goo.gl/maps` short links are expanded first with a plain
GET that reads the `location` redirect header (max 3 hops, 8 s total). The URL
is pulled out of the surrounding message text first, so pasting a whole
WhatsApp message works, not just a bare link.

The allowlist is matched on the **parsed host**, never as a substring, and it
is re-checked **before every hop** — so neither a pasted URL that merely
mentions `maps.app.goo.gl` in its query string, nor a `location` header
returned by the first response, can aim a GET at an arbitrary host.

Results outside Indonesia (lat −11..6, lng 95..141) are rejected. Every failure
— no coordinates, out of range, offline, timeout — shows text segment 12 and
leaves the picker fully usable by hand.

When `pasteEnabled` is on, the **search** field also accepts coordinates: it
tries extraction first and falls through to Nominatim otherwise, because the
two fields sit next to each other and get confused.

## Note (`noteEnabled`)

An optional free-text field under the compact card, always visible when
enabled. Its value is appended to the reverse-geocoded address with ` — `
(U+2014) and written to **`addressPosition`** — there is no separate slot and
no new DB field, so the driver card and the invoice pick it up for free.

- Empty note → `addressPosition` is the plain address, no dangling separator.
- Note typed before a point is picked → held, then joined when the point lands.
- Note edited after a point is picked → the output updates immediately.
- The note is kept out of the display name (which the card splits on its first
  comma) and survives rebuilds via the position's `stateObject`, not by
  splitting the address back apart.

## Dependencies

- `flutter_map` (OSM tiles)
- `latlong2` (LatLng type)
- `geolocator` (GPS)
- `http` (Nominatim API + Google short-link expansion)

All already in `pubspec.yaml`.

## See Also

- `location_detector.dart` — read-only GPS display card (opens `map_page.dart`)
- `map_page.dart` — read-only map viewer (fixed marker, no pick)
