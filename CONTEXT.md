# CONTEXT.md — domain glossary

Terms with a precise meaning in this codebase. Architecture vocabulary (module, interface, seam, depth, leverage, locality) comes from `.claude/skills/codebase-design`; this file holds the *domain* terms.

## ScreenSession

The per-screen (`scrName`-keyed) UI state a widget accumulates while the user works on a screen — search text, picker ticks, expanded rows, in-flight `_writing` guards, publish trackers. Owned by `ScreenSession` (`lib/screen_session.dart`), the single registry both reset paths call. Replaces the two hand-maintained clear lists that used to live in `clearData` (api.dart) and `buildPage(clear:true)` (ui_component.dart).

Two distinct **events** end or refresh screen session state — they are not interchangeable:

- **navigated** (`ScreenSession.navReset(scrName)`) — user moved via `gotoRoute → reloadPage`, which runs **post-frame** and returns the **cached** `linkElement[page]`; `buildPage` does not re-run. Called from `clearData`, *above* its `txfController == null` early-return.
- **rebuilt** (`ScreenSession.pageBuild(scrName)`) — the screen definition was (re)built: cold boot **and every background `readSettings` refresh**, pre-paint. A store holding in-flight user input (wizard drafts, a signature mid-draw) must NOT clear on this event.

Per-store policy is declared at registration (`ensure(name, clearOne, {nav: screen|all|none, rebuild: screen|none, clearAllFn, persistent})`). `nav: all` exists because navigated fires post-frame: clearing only the entering screen flashes one frame of stale state (the GroupPicker case). `persistent` entries (AdminCreateTask wizard drafts) are registered for auditability but only cleared explicitly at flow boundaries. Registration is idempotent and sits on the store's access path — Dart statics are lazy, so a bare `static final _reg = …` would never run.

Known exception, by design: `ApproverStickyBar` keeps its own `#CURRENT_ROUTE` listener (approver_sticky_bar.dart) for `activeBarScreen` — its `_configs` must survive navigated (the renderer reads them on cached pages) and are refilled by `buildPage(clear:false)` re-entries on Redux changes. Do not migrate it to navigated-clearing.
