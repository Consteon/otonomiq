// lib/widget/build_display_component_support.dart
//
// Pure decision helper extracted from buildDisplayComponent's per-field seed
// block (lib/widget/build_display_component.dart) so it can be unit-tested
// without the full widget / global bootstrap. Keep this file dependency-light:
// it must import only ../global.dart (for the emptyString sentinel).
//
// See test/build_display_component_preserve_input_test.dart.

import '../global.dart';

/// Whether buildDisplayComponent may (re)seed a field's [finalData] from its
/// freshly computed initial value.
///
/// Returns `true` (seed / refresh) when the field is effectively untouched:
///   * [exists] is false — a brand-new controller that must be seeded;
///   * [currentFinalData] == [currentInitialValue] — the value has not diverged
///     from the last seeded baseline, so a legit server display-refresh is safe;
///   * [currentFinalData] == [emptyString] (`'--'`) — the controller still holds
///     the uninitialised sentinel that txfControllerCheck installs, so it has
///     never really been seeded (e.g. pre-created by the RBT-child branch).
///
/// Returns `false` (preserve) only when the user — or a widget action handler —
/// has written a real value that differs from both the seeded initialValue and
/// the '--' sentinel. This is what stops the Firestore proxy rebuild
/// (main_page.dart ~1277 -> constructAllPageElements -> buildPage) from wiping
/// in-progress form input mid-session.
bool isFieldUntouched(
  bool exists,
  String currentFinalData,
  String currentInitialValue,
) {
  if (!exists) return true;
  if (currentFinalData == currentInitialValue) return true;
  if (currentFinalData == emptyString) return true;
  return false;
}
