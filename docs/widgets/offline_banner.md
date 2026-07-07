# OfflineBannerHost

Global offline strip above the MainPage body; visible on every page while the app is offline.

- **File:** [lib/widget/offline_banner.dart](../../lib/widget/offline_banner.dart)
- **Class:** `OfflineBannerHost` (StatelessWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** offline-native-writes
- **Dispatch type:** NONE — structural shell widget, wraps the Scaffold `body:` in `lib/page/main_page.dart` (like `otq_bottom_nav_bar.dart`). Not a `build_display_component` branch, not in the `all_widget.dart` barrel.

## Purpose

With the native-write helpers (`writeNativeFields` / `createNativeDoc*` / `executeUpdateEventRow`) now fire-and-forget, offline submits succeed instantly and queue in the Firestore SDK cache. This banner is the single Dart-level (no JSON deploy) signal that the device is offline and that changes are stored and auto-synced.

## Signature / Constructor

```dart
OfflineBannerHost({
  Key? key,
  required Widget child, // the original Scaffold body content
})
```

## State / Bloc / Dependencies

- **State used:** reads the existing app-wide `internetConnectionFlag` (RxBool, `global.dart:263`) via a single `Obx`. Maintained by the connectivity listener (`global.dart:753`). No new state anywhere; nothing added to `global.dart`.
- **Side effects:** none (pure display).

## Important Behavior

- Online (`flag == true`): renders `SizedBox.shrink()` — zero height, body layout byte-identical.
- Offline: a slate-700 strip ("Offline — perubahan disimpan & dikirim otomatis") pushes the body down (Column + Expanded), so it never overlaps content.
- Applies to ALL body branches of MainPage: unauthenticated login, SDUI ListView, and the `byPass == 1` NotificationList.

## See Also

- [notice_bar.md](notice_bar.md) — per-screen SDUI callout (server-driven); this banner is the app-shell (Dart-driven) counterpart.
