# AdminCoordinationHeader

Pinned identity bar for the Admin "Koordinasi" home (H1): admin name and two summary chips (N berjalan / N sinyal). (Role label + map icon + "Ganti" runtime-switch button were removed per design — see Important Behavior.)

- **File:** [lib/widget/admin_coordination_header.dart](../../lib/widget/admin_coordination_header.dart)
- **Class:** `AdminCoordinationHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** admin-home slice 1

## Purpose

Shows the logged-in admin's identity and two live counts at the top of the Admin Koordinasi screen. The `N sinyal` chip uses the SAME `deriveAdminSignals` helper as `CoordinationSignalList`, so the chip count is guaranteed to equal the number of signal cards rendered below (single source of truth). The `N berjalan` chip counts today's confirmed-custody vehicle checks.

Read-only: no `txfController` slot, no `position`, no write. Pinned (not scrollable) at the top of the page body.

## Signature / Constructor

```dart
AdminCoordinationHeader({
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
| `key` | `Key` | yes | — | Unique key per instance (the dispatch chain passes `txfKey`) |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Left/top/right/bottom padding |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | appVid (Firestore container) for the subscriptions. Falls back to `getTableVid(component['com'])` via `resolveAppVid`. |
| `taskTable` | `String` | `"<tableDocId>//task"` — task subcollection. |
| `vehicleTable` | `String` | `"<tableDocId>//stock_location"` — stock_location subcollection. |
| `checkTable` | `String` | `"<tableDocId>//vehicle_check"` — vehicle_check subcollection (drives `N berjalan`). |
| `evidenceTable` | `String` | `"<tableDocId>//evidence"` — evidence subcollection (reject reasons for signal derive). |
| `switchRoute` | `String` | *Ignored — the "Ganti" button was removed. Harmless if still present in JSON.* |
| `text` | `String` | `◆`-separated label slots (see Text slots). |

### Text slots (`◆`-separated, length-guarded)

| Index | Meaning | Default |
|---|---|---|
| 0 | Role label — **not rendered** (removed) | `Koordinasi` |
| 1 | Switch button label — **not rendered** (removed) | `Ganti` |
| 2 | Berjalan chip suffix | `berjalan` |
| 3 | Sinyal chip suffix | `sinyal` |

> Slots 0 and 1 are parsed but no longer drawn — only slots 2 and 3 (the chip suffixes) affect the rendered header.

Each slot uses `_t(i, def)` = `arr.length > i ? arr[i] : def` (out-of-range safe; never `arr[i] ?? def`).

## Usage Examples

Server op1Screen child (see [admin-home-op1screen.md](../admin_runtime/admin-home-op1screen.md)):

```json
{"type":"ADMIN_COORDINATION_HEADER","vidtable":"20342033315492","taskTable":"84214220504259//task","vehicleTable":"84214220504259//stock_location","checkTable":"84214220504259//vehicle_check","evidenceTable":"84214220504259//evidence","switchRoute":"vertikaTeknoLokaciptaRuntimeSwitch","text":"Koordinasi◆Ganti◆berjalan◆sinyal"}
```

## State / Bloc / Dependencies

- **State used:** none persisted. Reactive from GetX `mapTableContent` (4 collections) inside one `Obx`. Admin name read from Redux `transactionStore.state.screenTx['#NAME']`.
- **Repository:** `subscribeToMapCollection` (table_repository) for live subcollection reads.
- **Helpers:** `admin_home_support.dart` (`deriveAdminSignals`, `countBerjalan`), `driver_home_support.dart` (`resolveAppVid`, `todayEpochMidnightWib`), `panel_card_support.dart` (`parseTablePath`).
- **Side effects:** none — the "Ganti" switch button and its `_onSwitchTap` handler were removed.
- **Writes:** none.

## Important Behavior

- Subscribes to task + stock_location + vehicle_check + evidence in `initState`. Subscriptions are idempotent per code (`subscribeToMapCollection`), so co-mounting with `CoordinationSignalList` adds no duplicate listeners.
- **Row 1 removed (map icon + role label + "Ganti" button):** the header now starts at the admin name, followed by the two chips. `switchRoute` and text slots 0/1 are ignored. To restore the runtime-switch affordance later, re-add the Row 1 widget tree + `_onSwitchTap` (was `routeStack.push(route)` before `gotoRoute(route)`, dead-route silent-skip via `routeExist`).
- Admin name row is hidden when `#NAME` is empty.
- The two summary chips use hardcoded hex (berjalan green; sinyal red when > 0 else green). The 3-tier *signal cards* in `CoordinationSignalList` use the theme-derived `statusColor`/`statusBgColor`; only these two header chips are literal.
- White-label: renders only where the page JSON provisions it; a tenant without the runtime collections shows `0 berjalan / 0 sinyal` (no crash).

## See Also

- [coordination_signal_list.md](coordination_signal_list.md) — the signal list body that shares `deriveAdminSignals`.
- [admin-home-op1screen.md](../admin_runtime/admin-home-op1screen.md) — paste-ready server page JSON.
