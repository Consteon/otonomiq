// test/build_display_component_preserve_input_test.dart
//
// Unit tests for the patrol-report field-loss fix in buildDisplayComponent's
// per-field seed block. See lib/widget/build_display_component_support.dart and
// .claude/plans/build-display-component-preserve-user-input.md.
//
// isFieldUntouched(exists, finalData, initialValue) decides whether the seed
// block may overwrite finalData with a freshly computed initial value (true =
// seed/refresh) or must preserve the user's in-progress input (false).

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/build_display_component_support.dart';

void main() {
  group('isFieldUntouched', () {
    test('new field (no controller yet) -> seed', () {
      // exists == false: value args are irrelevant, must seed.
      expect(isFieldUntouched(false, emptyString, ''), isTrue);
      expect(isFieldUntouched(false, 'anything', 'whatever'), isTrue);
    });

    test('untouched field (finalData == initialValue) -> seed/refresh', () {
      expect(isFieldUntouched(true, '', ''), isTrue);
      expect(isFieldUntouched(true, 'Aman kondusif', 'Aman kondusif'), isTrue);
      expect(isFieldUntouched(true, '100', '100'), isTrue);
    });

    test('edited field (finalData != initialValue) -> preserve', () {
      // The core bug: server initValue empty, user typed a value.
      expect(isFieldUntouched(true, 'Aman kondusif', ''), isFalse);
      expect(isFieldUntouched(true, 'test ya', ''), isFalse);
      // User changed a prefilled value.
      expect(isFieldUntouched(true, 'new', 'old'), isFalse);
    });

    test('edited-back-to-initial -> seed (identical value, harmless)', () {
      // If the user edits then restores the exact seeded value, finalData once
      // again equals initialValue and is treated as untouched. Re-seeding writes
      // the same value, so behaviour is identical either way.
      expect(isFieldUntouched(true, 'kembali', 'kembali'), isTrue);
    });

    test('uninitialised sentinel (finalData == emptyString) -> seed', () {
      // txfControllerCheck installs finalData='--', initialValue=''. A controller
      // pre-created by the RBT-child branch before the seed block runs lands
      // here; it must still be seeded, not frozen at '--'.
      expect(isFieldUntouched(true, emptyString, ''), isTrue);
      expect(isFieldUntouched(true, '--', ''), isTrue);
      // Sentinel against a non-empty server default is still uninitialised.
      expect(isFieldUntouched(true, emptyString, 'prefilled'), isTrue);
    });

    test('deliberately-cleared field ("" vs "--") -> preserve', () {
      // A user who cleared a prefilled field holds finalData='' (real empty),
      // distinct from the '--' sentinel; that divergence must be preserved.
      expect(isFieldUntouched(true, '', 'prefilled'), isFalse);
    });

    test('server currentValue itself is the sentinel -> seed', () {
      // Both finalData and initialValue seeded to '--'.
      expect(isFieldUntouched(true, emptyString, emptyString), isTrue);
    });
  });
}
