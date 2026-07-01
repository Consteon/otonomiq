import 'dart:convert';

/// Pure decision helper for the logout instant-restore path.
///
/// Given the two guest-UI snapshot strings (`@guestScreenUI` / `@guestSystemUI`
/// from SharedPreferences, both nullable), returns `true` only when BOTH are
/// present, non-empty, AND JSON-decode to a `Map`. When `true`, `signOut()`
/// takes the instant warm-cache restore path; otherwise it falls back to the
/// cold/corrupt path (network re-fetch behind a "logging out…" spinner).
///
/// Kept in this small pure file (no Firebase / no secrets imports) so the same
/// function `signOut()` calls is unit-testable from `test/logout_transition_test.dart`.
bool shouldRestoreGuestSnapshot(String? guestScreenUI, String? guestSystemUI) {
  if (guestScreenUI == null || guestSystemUI == null) return false;
  if (guestScreenUI.isEmpty || guestSystemUI.isEmpty) return false;
  // Validate the JSON decode won't throw — signOut must never crash — and that
  // each snapshot is a Map (the shape screenUIComponent/systemUIComponent need),
  // not a primitive or list.
  try {
    final screen = jsonDecode(guestScreenUI);
    final system = jsonDecode(guestSystemUI);
    return screen is Map && system is Map;
  } catch (_) {
    return false;
  }
}

/// Pure gate for the cache-first authed navbar restore.
///
/// Returns `true` when [cachedAuthedSystemUI] is a non-null, non-empty string
/// that JSON-decodes to a `Map` containing a `'Mobile'` key whose value is a
/// `Map` with a `'bottomBar'` key whose value is a non-empty `List`.
/// When `true`, the caller restores `systemUIComponent` from this cache so
/// the navbar renders all items on the first authenticated frame (no stagger).
bool shouldRestoreAuthedSystemUI(String? cachedAuthedSystemUI) {
  if (cachedAuthedSystemUI == null || cachedAuthedSystemUI.isEmpty)
    return false;
  try {
    final decoded = jsonDecode(cachedAuthedSystemUI);
    if (decoded is! Map) return false;
    final mobile = decoded['Mobile'];
    if (mobile is! Map) return false;
    final bottomBar = mobile['bottomBar'];
    return bottomBar is List && bottomBar.isNotEmpty;
  } catch (_) {
    return false;
  }
}
