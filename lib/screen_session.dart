/// Policy for when [ScreenSession.navReset] fires (post-frame on gotoRoute).
enum NavPolicy {
  /// Clear only the entering scrName.
  screen,

  /// Clear ALL screens (GroupPicker flash-fix: post-frame means the cached
  /// page paints one stale frame if only the entering screen is cleared).
  all,

  /// Do not clear on nav. Used by rebuild-only stores.
  none,
}

/// Policy for when [ScreenSession.pageBuild] fires (buildPage(clear:true)).
enum RebuildPolicy {
  /// Clear for the screen being (re)built.
  screen,

  /// Do not clear on rebuild. Used by in-flight user input (signatures, scans)
  /// that must survive background readSettings refreshes.
  none,
}

class ScreenSession {
  ScreenSession._();

  /// Registry: name -> entry. Idempotent by name.
  static final Map<String, _Entry> _registry = {};

  /// Register a per-screen store. Idempotent: second call with same [name] is
  /// a no-op (does NOT overwrite). Place on the store's access path (accessor
  /// getter or widget initState) so it runs before the store can hold data.
  ///
  /// [clearOne] receives a scrName and clears that screen's slice of the store.
  /// [clearAllFn] is required when [nav] is [NavPolicy.all] -- it clears every
  /// screen's slice (the GroupPicker/TablePicker flash-fix pattern).
  /// [persistent] entries are registered for audit but never auto-cleared.
  static void ensure(
    String name,
    void Function(String scrName) clearOne, {
    NavPolicy nav = NavPolicy.screen,
    RebuildPolicy rebuild = RebuildPolicy.screen,
    void Function()? clearAllFn,
    bool persistent = false,
  }) {
    if (_registry.containsKey(name)) return;
    assert(
      nav != NavPolicy.all || clearAllFn != null,
      'NavPolicy.all requires clearAllFn',
    );
    _registry[name] = _Entry(
      name: name,
      clearOne: clearOne,
      nav: nav,
      rebuild: rebuild,
      clearAllFn: clearAllFn,
      persistent: persistent,
    );
  }

  /// Called by clearData (api.dart). Iterates all registered entries whose
  /// nav policy matches and fires their clear function. One throwing entry
  /// must not block the rest (mirrors today's independent-call behavior).
  static void navReset(String scrName) {
    // Snapshot: a clearOne callback may trigger ensure() on a not-yet-
    // registered peer, which mutates _registry mid-iteration.
    for (final e in List.of(_registry.values)) {
      if (e.persistent) continue;
      if (e.nav == NavPolicy.none) continue;
      try {
        if (e.nav == NavPolicy.all) {
          e.clearAllFn!();
        } else {
          e.clearOne(scrName);
        }
      } catch (_) {}
    }
  }

  /// Called by buildPage(clear:true) (ui_component.dart). Iterates all
  /// registered entries whose rebuild policy is [RebuildPolicy.screen] and
  /// fires their clear function.
  static void pageBuild(String scrName) {
    // Snapshot: a clearOne callback may trigger ensure() on a not-yet-
    // registered peer, which mutates _registry mid-iteration.
    for (final e in List.of(_registry.values)) {
      if (e.persistent) continue;
      if (e.rebuild == RebuildPolicy.none) continue;
      try {
        e.clearOne(scrName);
      } catch (_) {}
    }
  }

  /// Deep-wrapper factory for new widgets: returns a per-scrName map that
  /// ScreenSession owns and clears automatically. NOT used in Phase 1/2 --
  /// documented here for future widgets.
  ///
  /// Usage (in a new widget):
  /// ```dart
  /// static final _store = ScreenSession.map<String, MyEntry>(
  ///   'MyWidget.store',
  ///   onEvict: (scrName, map) { /* optional cleanup */ },
  /// );
  /// ```
  static Map<String, Map<K, V>> map<K, V>(
    String name, {
    void Function(String scrName, Map<K, V> evicted)? onEvict,
    NavPolicy nav = NavPolicy.screen,
    RebuildPolicy rebuild = RebuildPolicy.screen,
  }) {
    final Map<String, Map<K, V>> store = {};
    ensure(
      name,
      (scrName) {
        final evicted = store.remove(scrName);
        if (evicted != null && onEvict != null) onEvict(scrName, evicted);
      },
      nav: nav,
      rebuild: rebuild,
    );
    return store;
  }

  // ── Test support ──────────────────────────────────────────────────────

  /// Read-only snapshot of registry names and their policies. Used by the
  /// pinning matrix test. Returns a new map each call.
  static Map<String, ({NavPolicy nav, RebuildPolicy rebuild, bool persistent})>
  get registrySnapshot {
    return {
      for (final e in _registry.entries)
        e.key: (
          nav: e.value.nav,
          rebuild: e.value.rebuild,
          persistent: e.value.persistent,
        ),
    };
  }

  /// Clear the registry. Test-only -- never call in production.
  static void resetForTest() => _registry.clear();
}

class _Entry {
  const _Entry({
    required this.name,
    required this.clearOne,
    required this.nav,
    required this.rebuild,
    this.clearAllFn,
    required this.persistent,
  });
  final String name;
  final void Function(String scrName) clearOne;
  final NavPolicy nav;
  final RebuildPolicy rebuild;
  final void Function()? clearAllFn;
  final bool persistent;
}
