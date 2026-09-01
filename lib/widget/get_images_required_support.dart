// lib/widget/get_images_required_support.dart
//
// Pure helpers for the GET_IMAGES `optional:"FALSE"` submit gate
// (spec: get-images-required-dev-spec, §2 / §3 / §6).
//
// EVERY decision this feature makes lives here as a top-level function with no
// Flutter, no Firebase and no GetX, so `flutter test` can drive all of it
// without a binding. ftz_row_of_button_2.dart contributes only the
// txfController read and the AlertDialog; otq_get_images_2.dart contributes
// only the chip.
//
// NOT a new component type and NOT a new dispatch branch: `optional` is one
// extra field on the existing GET_IMAGES component.

import '../global.dart'; // emptyString ('--'), emptyImageUrl, separator
import '../sdui_spec.dart';

/// Dialog title used when the offending component ships no usable `label`.
const String getImagesRequiredDefaultTitle = 'Foto belum diambil';

/// Dialog body used when `text` carries no usable ◆ segment 1.
///
/// Reaching this default does NOT unblock the submit. A missing message is a
/// sheet-config gap, not permission to save a meter reading without evidence
/// (spec §1, §9). Fail CLOSED on the message, never on the gate.
const String getImagesRequiredDefaultMessage =
    'Foto wajib diambil sebelum menyimpan.';

/// What the RBT must show when a required GET_IMAGES slot is empty.
class GetImagesRequirement {
  const GetImagesRequirement(this.title, this.message);

  final String title;
  final String message;

  @override
  String toString() => 'GetImagesRequirement($title | $message)';
}

/// The value `saveSend` would put in the record slot for this position.
///
/// Mirrors api.dart:4839 (and its duplicate at :4851) exactly: `finalData`
/// wins UNLESS it is still the untouched InputController birth sentinel '--'
/// (global2.dart:1018), in which case `controller.text` wins.
///
/// Kept as its own named function so the two cannot silently drift: if the
/// record composer's selection rule ever changes, this is the one line that
/// has to change with it.
String getImagesSlotValue(String finalData, String controllerText) =>
    finalData == emptyString ? controllerText : finalData;

/// A snapshot of one record slot, read at press time.
///
/// Deliberately holds the RAW InputController fields rather than a
/// pre-selected value, so the api.dart-mirroring selection lives here (where
/// `flutter test` can drive it) instead of in the RBT closure (where it cannot).
/// The caller does nothing but transcribe three fields.
///
/// No Flutter / GetX / global2 import is needed to build one — that is what
/// keeps this file bindingless.
class GetImagesSlot {
  const GetImagesSlot({
    required this.finalData,
    required this.controllerText,
    required this.enabled,
  });

  /// `InputController.finalData`.
  final String finalData;

  /// `InputController.controller.text`.
  final String controllerText;

  /// `InputController.isEnabled` AT PRESS TIME — not a cached build-time copy.
  final bool enabled;

  /// What `saveSend` would submit for this slot.
  String get value => getImagesSlotValue(finalData, controllerText);

  @override
  String toString() =>
      'GetImagesSlot(finalData: "$finalData", '
      'controllerText: "$controllerText", enabled: $enabled)';
}

/// Reads the record slot for [position]. Returns `null` when NO slot exists.
///
/// `null` and "a disabled slot" must stay distinguishable: a slot that does not
/// exist has never been disabled by anyone (the ordinary first-render case on a
/// page the officer just opened), and must still be gated. Collapsing the two
/// would silently disarm the whole feature.
typedef GetImagesSlotReader = GetImagesSlot? Function(int position);

/// True when [slotValue] holds at least ONE real photo reference.
///
/// FIVE values all mean "no photo" here and a bare `.isEmpty` catches only one
/// of them:
///   * ''             — delete-last writes processData([]) -> ''; a page
///                      shipping `currentValue:""` seeds processData(['']) -> ''
///                      (init_values.dart:118).
///   * '   '          — whitespace-only cell.
///   * '--'           — `emptyString`. **'--'.isEmpty is FALSE.**
///   * 'aum__--__mua' — `emptyImageUrl` (global.dart:228), the
///                      "capture produced nothing" sentinel.
///   * 'null'         — getInitialValue (init_values.dart:11) gates on
///                      `component['currentValue'].toString().trim().isNotEmpty`
///                      and `null.toString()` is the four-character string
///                      "null", which passes. It flows through
///                      getImageInitValue -> processData into finalData and is
///                      submitted verbatim. That is a KNOWN repo-wide bug this
///                      guard DEFENDS against; this spec does not fix it.
///
/// Multi-photo slots are `separator[5]`-joined (◇, processData), so the slot
/// counts as filled when ANY segment survives the sentinel test — spec §8:
/// required means "at least one", never "up to `max`".
bool getImagesSlotHasPhoto(String slotValue) {
  for (final String part in slotValue.split(separator[5])) {
    final String v = part.trim();
    if (v.isEmpty) continue;
    if (v == emptyString) continue;
    if (v == emptyImageUrl) continue;
    if (v == 'null') continue;
    return true;
  }
  return false;
}

/// True when this GET_IMAGES component is configured as required.
///
/// The contract is a STRING `"TRUE"`/`"FALSE"`, matching SIGNATURE_PAD
/// (signature_pad.dart:350) — never a bool, never renamed to `required`. Only a
/// literal FALSE (any case, surrounding blanks tolerated) arms the gate:
///   * key absent, or a blank cell -> SduiSpec.str returns the 'TRUE' default
///     (sdui_spec.dart:49) -> not required -> today's behavior byte-for-byte.
///   * an unresolved `[OPTIONAL]` placeholder -> not 'FALSE' -> not required.
///     DELIBERATE fail-open: spec §5 ships the sheet template AFTER the
///     renderer, so a half-swept workbook must not brick every live page.
///
/// A JSON bool is tolerated for free (`false.toString()` -> 'false'), which is
/// the same tolerance SIGNATURE_PAD has.
///
/// Kept as a standalone one-argument predicate so otq_get_images_2.dart's
/// `wajib` chip can reuse the EXACT same required-test instead of forking it.
bool getImagesIsRequired(dynamic component) =>
    SduiSpec(component).str('optional', 'TRUE').toUpperCase() == 'FALSE';

/// The first GET_IMAGES component on this page that is required and whose
/// record slot blocks the submit, resolved into the title/message the RBT
/// shows. `null` means nothing blocks the submit.
///
/// [children] is `screenUIComponent[scrName]['children']` — a FLAT List of page
/// components. [slotOf] returns the record slot for a position; the caller
/// supplies the txfController read so this function stays pure and bindingless.
///
/// Chain children (DO_BOTTOM_SHEET / DO_DIALOG) are deliberately NOT descended
/// into. The sheet is built with the SAME `scrName`
/// (do_otq_bottom_sheet.dart:10 -> buildPage(..., scrName, dialog: true,
/// clear: false)), so its savesend RBT runs this same gate against the
/// PAGE-level photo field — which is exactly what spec §3.1 asks for. A
/// GET_IMAGES living inside a sheet is out of scope this round.
///
/// Both dispatch spellings are accepted (build_display_component.dart:192
/// builds on `get_images` OR `getimages`) so this scan cannot diverge from what
/// the renderer actually rendered.
///
/// TWO skips exist, and both are there to guarantee the gate has a reachable
/// exit — a requirement the officer cannot possibly satisfy is a dead end, not
/// a requirement:
///
///   * NO PARSEABLE POSITION. The component writes to no record slot, so no
///     action could ever satisfy it. Same reasoning, same idiom as
///     digit_pad_support.dart:257-258.
///   * SLOT PRESENT AND DISABLED. A disabled GET_IMAGES cannot be tapped — in
///     otq_get_images_2.dart `_buildContent` gates the empty-state tap with
///     `onTap: canAddMore && isEnabled ? … : null` and hides the add button
///     behind `if (canAddMore && isEnabled) ...[` — so the officer has no way
///     to produce a photo. Nothing is cached: the flag is read at PRESS TIME,
///     which means it reflects any `run:` command on the SAME button that has
///     already executed, because that block runs before the `action` switch.
///     Consequence, stated plainly: a same-button `run:"N:disable"` on the
///     photo slot disarms the gate for that press even though the officer was
///     looking at an enabled field; `run:"N:enable"` conversely arms it.
///
/// A MISSING slot (`slotOf` returns null) is NOT treated as disabled: it has
/// never been disabled by anyone, and its value reads as '' -> no photo -> it
/// still blocks. That is the ordinary first-render case; collapsing it into the
/// disabled skip would silently disarm the feature.
///
/// The loop stops at the first BLOCKING component, not the first REQUIRED one:
/// a required field that is filled — or one that is disabled — must not mask an
/// empty enabled one further down.
GetImagesRequirement? getImagesRequiredBlock(
  dynamic children,
  GetImagesSlotReader slotOf,
) {
  if (children is! List) return null;
  for (final dynamic comp in children) {
    if (comp is! Map) continue;
    final String tip = (comp['type'] ?? '').toString().trim().toLowerCase();
    if (tip != 'get_images' && tip != 'getimages') continue;
    if (!getImagesIsRequired(comp)) continue;
    final int? pos = int.tryParse((comp['position'] ?? '').toString().trim());
    if (pos == null) continue;
    final GetImagesSlot? slot = slotOf(pos);
    if (slot != null && !slot.enabled) continue;
    if (getImagesSlotHasPhoto(slot?.value ?? '')) continue;
    final SduiSpec spec = SduiSpec(comp);
    final String message = spec.text(1, getImagesRequiredDefaultMessage);
    return GetImagesRequirement(
      spec.str('label', getImagesRequiredDefaultTitle),
      message.trim().isEmpty ? getImagesRequiredDefaultMessage : message,
    );
  }
  return null;
}
