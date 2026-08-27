// lib/widget/checklist_dynamic.dart
//
// CHECKLIST_DYNAMIC -- a DB-driven cleaning checklist.
//
// One component renders N task rows pulled from a Firestore sub-collection and
// fans them out across a CONTIGUOUS RUN of form slots -- one slot per task,
// starting at the component's own `position`. It replaces N static TASKLIST
// components (lib/widget/tasklist.dart), which stays untouched: spec §8 keeps
// the 5 static per-category pages as a fallback.
//
// ── contracts a future editor must not break ─────────────────────────────────
//
//  * ONE TASK = ONE SLOT (D1). Task k (0-based, AFTER sorting) is written to
//    txfController[scrName][position + k].finalData as '<title> | <status>'.
//    saveSend iterates EVERY txfController entry and writes each to
//    row[position + sheetSystemLength - 1] (api.dart:4815-4860), so a widget
//    may claim as many slots as it likes -- group_picker.dart:520-551 claims
//    three. The visit-doc FIELD NAMES (ck1..ckN) are assigned sheet-side by the
//    close button's updateEventRow (`ck1◼◁12▷⭘ck2◼◁13▷…`); `◁N▷` resolves to
//    form position N, with NO +1 (parseEventString -> ref[1][N-1] == row[N+14];
//    saveSend writes position P to row[P+14]).
//
//  * `output` IS INERT. The spec's contract JSON carries `"output":"ck"`;
//    NOTHING in this app reads it (`grep -rn "\['output'\]" lib/widget/` -> 0).
//    This app has no mechanism for a widget to name a submitted field, and
//    building one was explicitly rejected because it would touch saveSend.
//
//  * THE SLOT BLOCK IS RESERVED. `slots` (config) declares the block size.
//    Positions `position .. position + slots - 1` must belong to NO other
//    component on the page -- nothing in the app can detect a collision.
//    N < slots -> the tail is blanked ('') on every build.
//    N > slots -> a visible warning row, and NOTHING outside the block is
//    written; the excess rows render inert (Opacity + IgnorePointer) so an
//    officer's tap can never silently vanish.
//    slots absent/0/negative -> claim exactly N: no tail-blanking, no warning.
//    The block is also clamped to form slot 100, because saveSend only submits
//    1 <= position <= 100 (api.dart:4834) and a longer block would be dropped
//    in silence.
//
//  * DELIMITER. Within a task `|`, emitted spaced (' | '). `~` is NO LONGER
//    structural (it was, in round 1, when all tasks shared one slot) and is no
//    longer stripped from titles. `◆` was the dev spec's proposal and CANNOT be
//    used: it is forbiddenCharacter[0] (global.dart:385) and stringCleanUp
//    (global.dart:1212) replaces every forbiddenCharacter entry except
//    separator[5] with a SPACE, over BOTH controller.text and finalData, inside
//    saveSend (api.dart:4840, 4844, 4852, 4856). `|` and the spaces survive --
//    confirmed by production visit docs written by round 1 of this widget.
//    `|` is stripped from BOTH operands, so a tenant title cannot inject one.
//    The READER splits on the FIRST `|` and trims both sides, so the round-1
//    bare `a|b` and the round-2 `a | b` both re-hydrate.
//
//  * finalData IS THE SINGLE SOURCE OF TRUTH for the N statuses, re-parsed from
//    the whole block and re-written on EVERY build. Two reasons, both
//    load-bearing:
//      1. SDUI rows live in AnyPage's ListView.builder with no keep-alive
//         (page/any_page.dart:168), so a row scrolled off screen is DISPOSED and
//         remounts with a fresh State. Holding statuses in State would reset an
//         officer's ticks mid-visit.
//      2. saveSend falls back to controller.text whenever finalData still holds
//         the '--' sentinel that txfControllerCheck gives every fresh slot
//         (global2.dart:1017 births the InputController with emptyString, which
//         is '--' at global.dart:213; api.dart:4839). Writing finalData on every
//         build closes that path by construction.
//    clearData already resets finalData to initialValue on navigation
//    (api.dart:4680), so a fresh visit starts all-pending for free -- no static
//    store, no ScreenSession entry, no rev signal. The dispatch chain's own seed
//    block only touches component['position'] and only re-seeds a slot that is
//    still isFieldUntouched (build_display_component_support.dart:28), so once
//    this widget's first build has written a composed value the seed block
//    PRESERVES it; the fan-out slots it never evaluates at all.
//
//  * ★ PARSE THE WHOLE BLOCK BEFORE WRITING ANY OF IT (D8). The re-hydration
//    source IS the block about to be overwritten, and a task can MOVE slot when
//    the admin deletes an earlier task. Interleaving read and write loses the
//    moved task's status.
//
//  * ★ AN EMPTY TASK LIST WRITES TO NO SLOT AT ALL (D8) -- not even ''. A
//    remount that precedes the Firestore snapshot renders zero titles; blanking
//    the block there would erase the officer's ticks. An unresolved {template},
//    a template with zero seeded docs, and a pre-snapshot build all take this
//    path. The cost, accepted deliberately: if a template's docs are ALL deleted
//    mid-visit, the previously written slots survive into the submitted row.
//
//  * READS MUST NOT CREATE CONTROLLERS. _readBlock uses
//    `txfController[scrName]?[slot]?.finalData ?? ''` and never calls
//    txfControllerCheck: in the over-capacity case the write phase may never
//    reach a slot, and an empty-but-existing entry becomes a real '' cell in the
//    submitted row and inflates saveSend's maxPosition.
//
//  * controller.text IS DELIBERATELY NOT WRITTEN. Assigning .text notifies its
//    listeners; mid-build that is a setState-during-build. Nothing reads it for
//    these slots once finalData is non-'--'.
//
//  * THE Obx READ IS THE FIRST STATEMENT OF _docs(), unconditionally. An Obx
//    that registers zero observables is a documented fatal in this repo. RxMap
//    .operator[] goes through the `value` getter, which registers the dependency
//    even for a MISSING key -- so no _code guard is needed, and adding one
//    reintroduces the crash.
//
//  * A BLANK `options` LABEL MUST STILL ROUND-TRIP. See checklistLabelForKey /
//    checklistLabelToKey: a blank configured label is emitted as the status KEY,
//    never as '', or the officer's tap would be discarded silently on the next
//    build.
//
//  * ★ SORT MUST BE STABLE. Dart's List.sort is a dual-pivot quicksort
//    (dart-sdk lib/internal/sort.dart) and is stable only below its
//    insertion-sort threshold of 32. Production HAS ties: two Restroom docs at
//    value 3, and every doc still missing `ord` coerces to 0. An unstable tie
//    order moves a task between slots build-to-build, so a status re-hydrated by
//    title appears to jump rows. checklistSortDocs decorates with the incoming
//    index to make the comparator a total order; the incoming order is
//    Firestore's default document-id-ascending snapshot order.
//
//  * DEFAULTS FOLLOW THE LIVE DB (D5/D9). taskField -> 'tsk', sortField ->
//    'ord'. SduiSpec.str treats a BLANK sheet cell as "use the default"
//    (sdui_spec.dart:47-51), so a stale default silently reads a field that does
//    not exist. Both live in ONE named constant each, below.
//
// ponytail: no progress bar (spec §5.4 marks it optional). TaskProgressStore is
// keyed (scrName, position); wiring it to a block of positions needs a new store
// shape. Add when a progress bar is actually specified.
// ponytail: no isEnabled gate -- TASKLIST has none; add when a read-only
// checklist is actually specified.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // mapTableContent, emptyString, marginArray, devPrint
import '../global2.dart'; // txfController, txfControllerCheck, WidgetUpdateController
import '../model/input_controller.dart';
import '../sdui_spec.dart';
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs, coerceNum
import 'panel_card_support.dart'; // TablePath, parseTablePath

// ─── constants ───────────────────────────────────────────────────────────────

/// Separator between a task title and its status label.
///
/// `~` is NOT a delimiter any more: round 1 joined all tasks into one slot and
/// needed one, round 2 gives each task its own slot and does not. A tenant task
/// title containing `~` now submits verbatim.
const String checklistPairSep = '|';

/// The implicit status of a task nobody has touched.
const String checklistStatusPending = 'pending';

/// Status keys in `options` order. Index i of `options` drives key i.
const List<String> checklistStatusKeys = <String>[
  'done',
  'not_available',
  'skipped',
  'issue',
];

/// D5/D9. The doc field holding the task text. `tsk` is confirmed present on
/// every document in the live `//checklist_template`.
///
/// ★ THE ONE PLACE THIS DEFAULT LIVES. A blank sheet cell selects it
/// (SduiSpec.str, sdui_spec.dart:47-51), so a stale value here means a blank
/// cell silently reads a field that does not exist.
const String checklistDefaultTaskField = 'tsk';

/// D5/D9. The doc field the list is ordered by. Spec §2.1 says `ord`.
///
/// ★ THE ONE PLACE THIS DEFAULT LIVES. Changing the whole app's ordering field
/// is a one-line edit here. There is deliberately NO `order` fallback: a second,
/// undocumented field name is the kind of dead config this repo has been burned
/// by. A doc missing this field coerces to 0 (coerceNum), so it sorts first and
/// still renders and still gets a slot -- it is never dropped.
const String checklistDefaultSortField = 'ord';

/// The label written into a slot for a task nobody has touched. NOT '': the
/// report reader must be able to tell "template has no task here" ('') from
/// "task exists and was left undone" ('… | belum').
const String checklistDefaultPendingLabel = 'belum';

/// saveSend only submits form slots 1..100 (api.dart:4834). A block running past
/// this would be dropped in silence, so it is clamped instead.
const int checklistMaxSlot = 100;

const String checklistDefaultEmptyMessage = 'Belum ada task untuk kategori ini.';
const String checklistDefaultCompletedPrefix = 'Completed at';
const String checklistDefaultSheetHeader = 'Change Status';

// ─── pure seams (unit-testable with no harness) ──────────────────────────────

/// One `icon ◆ label ◆ description` triplet from `component['options']`.
class ChecklistOption {
  const ChecklistOption({
    required this.icon,
    required this.label,
    required this.description,
  });

  final String icon;
  final String label;
  final String description;
}

/// Parse `component['options']` ◆-parts into triplets. A partial trailing group
/// is dropped. Identical grouping rule to Tasklist (tasklist.dart:107).
List<ChecklistOption> checklistParseOptions(List<String> parts) {
  final List<ChecklistOption> out = <ChecklistOption>[];
  for (int i = 0; i + 2 < parts.length; i += 3) {
    out.add(ChecklistOption(
      icon: parts[i],
      label: parts[i + 1],
      description: parts[i + 2],
    ));
  }
  return out;
}

/// Remove the structural delimiter from an operand, replacing it with a space --
/// the same repair idiom stringCleanUp uses for a forbidden char.
///
/// `~` is deliberately NOT stripped: it stopped being structural when the widget
/// moved to one slot per task, and mutilating a legitimate tilde in a tenant
/// task title would be a silent data change.
String checklistSanitize(String s) => s.replaceAll(checklistPairSep, ' ');

/// The ONE normalised form used BOTH as the emitted title operand AND as the
/// status-map key. Sanitize-then-trim, because sanitizing a title that ENDS in
/// `|` leaves a trailing space; without the trim the writer and the reader would
/// disagree and re-hydration would silently fail for that task.
String checklistTitleKey(String title) => checklistSanitize(title).trim();

/// The value written into ONE slot: `'<title> | <label>'` (spec §5.5).
///
/// ★ The title operand is [checklistTitleKey] itself, not raw sanitize, so the
/// stored title is byte-identical to the key the reader will compute from it.
/// Round 1 used un-trimmed sanitize; with the spaced join that would have
/// produced a double space for a title ending in the delimiter.
/// ★★ BOTH operands go through checklistTitleKey -- the ONE normaliser. It is
/// sanitize-THEN-trim, which is what `checklistSanitize(label).trim()` spelled
/// out inline; that inline copy was a SECOND definition of the same rule, and
/// checklistLabelToKey builds its reverse map with checklistTitleKey. Adding a
/// step to checklistTitleKey later would have moved only the reader, so every
/// label lookup would miss and every task would snap back to pending, silently.
String checklistSerialize(String title, String label) =>
    '${checklistTitleKey(title)} $checklistPairSep '
    '${checklistTitleKey(label)}';

/// Whether a slot holds no value.
///
/// Three sentinels, all of them real:
///   * `''`          -- clearData restores finalData to a fan-out slot's
///                      initialValue, which is '' (api.dart:4680).
///   * `'--'`        -- emptyString; txfControllerCheck births EVERY slot with
///                      it (global2.dart:1017). NOTE `'--'.isEmpty` is FALSE.
///   * `'null'`      -- getInitialValue does component['currentValue'].toString(),
///                      and with the key absent that is the 4-char string "null",
///                      which passes its own non-empty gate (init_values.dart:11).
/// Mirrors digitPadNormalizeSeed (digit_pad_support.dart:36) and
/// getImagesSlotHasPhoto (get_images_required_support.dart:115).
bool checklistSlotIsEmpty(String v) {
  final String t = v.trim();
  return t.isEmpty || t == emptyString || t == 'null';
}

/// One slot value -> `[titleKey, statusLabel]`, or null when the slot holds no
/// usable pair.
///
/// Splits on the FIRST `|` and trims both sides, so `'a | b'` (round 2) and
/// `'a|b'` (round 1, and what live visit docs contain) both re-hydrate. A value
/// with no `|`, an empty title, or any of the three empty sentinels yields null
/// rather than a crash. A round-1 joined blob `'a|X~b|Y'` yields `['a','X~b|Y']`,
/// whose label matches no configured status and is therefore dropped downstream.
List<String>? checklistParsePair(String stored) {
  if (checklistSlotIsEmpty(stored)) return null;
  final int i = stored.indexOf(checklistPairSep);
  if (i < 0) return null;
  final String key = checklistTitleKey(stored.substring(0, i));
  if (key.isEmpty) return null;
  return <String>[key, stored.substring(i + 1).trim()];
}

/// Every slot of the block -> `{titleKey: statusLabel}`.
///
/// Duplicate titles across slots: the later slot wins. That is a config error
/// (two docs with the same task text), and merge-by-title already documents that
/// such rows move together.
Map<String, String> checklistParseSlots(List<String> slotValues) {
  final Map<String, String> out = <String, String>{};
  for (final String v in slotValues) {
    final List<String>? p = checklistParsePair(v);
    if (p == null) continue;
    out[p[0]] = p[1];
  }
  return out;
}

/// Reverse map: sanitized+trimmed status LABEL -> status key.
///
/// The pending label is inserted FIRST so that a real status label which happens
/// to equal it overwrites the entry and wins -- a task the officer actively
/// marked must not read back as untouched.
///
/// A BLANK configured label registers the status KEY as its own label, because
/// checklistLabelForKey emits that key rather than `''`. Skipping it (the
/// obvious `if (l.isEmpty) continue;`) is the W1 defect: the stored `title | `
/// re-parses to `''`, finds no entry here, is dropped by checklistStatusByTitle,
/// and the row snaps back to pending on the very next build -- silently, because
/// _content rewrites unconditionally.
///
/// A DUPLICATED label is a config error: the later index overwrites the earlier
/// one here, so picking the earlier status reads back as the later one.
Map<String, String> checklistLabelToKey(
    List<String> labels, String pendingLabel) {
  final Map<String, String> out = <String, String>{};
  final String p = checklistTitleKey(pendingLabel);
  if (p.isNotEmpty) out[p] = checklistStatusPending;
  for (int i = 0; i < labels.length && i < checklistStatusKeys.length; i++) {
    final String l = checklistTitleKey(labels[i]);
    out[l.isEmpty ? checklistStatusKeys[i] : l] = checklistStatusKeys[i];
  }
  return out;
}

/// Every slot of the block -> `{titleKey: statusKey}`.
///
/// A label with no entry in [labelToKey] is DROPPED, so the task falls back to
/// pending. That is how an edited `options` config -- and a round-1 joined blob
/// left in a slot -- degrade instead of crashing.
Map<String, String> checklistStatusByTitle(
    List<String> slotValues, Map<String, String> labelToKey) {
  final Map<String, String> out = <String, String>{};
  checklistParseSlots(slotValues).forEach((String title, String label) {
    final String? key = labelToKey[label];
    if (key == null) return;
    out[title] = key;
  });
  return out;
}

/// Status key -> the label written into the slot and shown on the badge.
///
/// Out of range (a short `options` config) -> [pendingLabel], never a throw:
/// that status genuinely does not exist in this config.
///
/// A BLANK configured label -> the status KEY itself. A key is never blank, so
/// the stored value always round-trips; returning `''` here would store
/// `title | `, which re-parses to nothing and discards the officer's tap.
String checklistLabelForKey(
    String key, List<ChecklistOption> options, String pendingLabel) {
  if (key == checklistStatusPending) return pendingLabel;
  final int i = checklistStatusKeys.indexOf(key);
  if (i < 0 || i >= options.length) return pendingLabel;
  final String label = options[i].label;
  if (label.trim().isEmpty) return key;
  return label;
}

/// The ONE colour source, used by both the row and the status sheet.
/// Values are TASKLIST's, verbatim (tasklist.dart:139/145/151/157/158).
Color checklistStatusColor(String key) {
  switch (key) {
    case 'done':
      return const Color(0xFF22C55E);
    case 'not_available':
      return const Color(0xFF9CA3AF);
    case 'skipped':
      return const Color(0xFFF59E0B);
    case 'issue':
      return const Color(0xFFEF4444);
    default:
      return const Color(0xFFD1D5DB);
  }
}

/// D3. The block size the config asks for.
///
/// `slots` absent / 0 / negative -> claim exactly [taskCount]: today's shape
/// extended, with no tail-blanking and no warning. `slots` is STRONGLY
/// RECOMMENDED because without it a template that SHRINKS mid-visit leaves stale
/// values in the freed tail slots, and the parse phase can no longer see a status
/// that moved out of the shortened block.
int checklistBlockSize(int slots, int taskCount) =>
    slots > 0 ? slots : taskCount;

/// D3. [block] clamped so it never runs past form slot [checklistMaxSlot].
///
/// saveSend only submits `1 <= position <= 100` (api.dart:4834); a longer block
/// would be dropped in silence. Clamping instead makes the loss visible through
/// [checklistOverflowCount] and the warning row. A position outside 1..100
/// yields 0 -- there is no legal block at all.
int checklistEffectiveBlock(int position, int block) {
  if (position < 1 || position > checklistMaxSlot || block <= 0) return 0;
  final int room = checklistMaxSlot - position + 1;
  return block > room ? room : block;
}

/// D3. How many tasks the block cannot hold. 0 means everything fits.
int checklistOverflowCount(int taskCount, int effectiveBlock) {
  final int over = taskCount - effectiveBlock;
  return over > 0 ? over : 0;
}

/// D3. The officer-facing over-capacity warning.
///
/// Deliberately NOT configurable: a warning a tenant can blank out is a warning
/// the officer never sees, and this one reports silent data loss.
String checklistOverflowMessage(int overflow, int capacity) =>
    'Perhatian: $overflow task terakhir TIDAK akan terkirim. '
    'Halaman ini hanya menampung $capacity task. Hubungi admin.';

/// D1/D3/D4. The exact values to write into slots
/// `position .. position + block - 1`, in that order.
///
/// Length is ALWAYS [block]:
///   * index k < titles.length  -> `'<title> | <label>'`
///   * index k >= titles.length -> `''` (the template has no task here)
/// Titles beyond [block] are NOT represented -- the caller renders them inert
/// and shows the warning row. This function is the single guarantee that nothing
/// outside the block is ever written.
List<String> checklistSlotValues(
  List<String> titles,
  Map<String, String> statusByTitle,
  List<ChecklistOption> options,
  String pendingLabel,
  int block,
) {
  final List<String> out = <String>[];
  for (int k = 0; k < block; k++) {
    if (k < titles.length) {
      final String key =
          statusByTitle[checklistTitleKey(titles[k])] ?? checklistStatusPending;
      out.add(checklistSerialize(
          titles[k], checklistLabelForKey(key, options, pendingLabel)));
    } else {
      out.add('');
    }
  }
  return out;
}

/// Doc list -> trimmed task titles in the list's current order.
/// A blank or missing [taskField] drops the row: it has nothing to render and
/// would serialize as a bare `|status`.
List<String> checklistTitles(
    List<Map<String, dynamic>> docs, String taskField) {
  final List<String> out = <String>[];
  final String f = taskField.trim();
  if (f.isEmpty) return out;
  for (final Map<String, dynamic> d in docs) {
    final String t = (d[f] ?? '').toString().trim();
    if (t.isEmpty) continue;
    out.add(t);
  }
  return out;
}

/// In-place, numeric-coerced, STABLE sort. Sort key idiom from ListCard
/// (list_card.dart:271-277); the stability is this widget's own requirement.
///
/// `ord` arrives as `1` from a typed writer and as `"1"` from a sheet; coerceNum
/// is why `"10"` sorts after `"9"` instead of before it. A doc MISSING the sort
/// field coerces to 0, so it sorts first ascending -- it may lose its ordering,
/// it is NEVER dropped. (Three of the four live `//checklist_template` docs are
/// in exactly that state until the seed is normalised.)
///
/// ★ STABILITY IS LOAD-BEARING, NOT COSMETIC. Dart's List.sort is a dual-pivot
/// quicksort (dart-sdk lib/internal/sort.dart) with an insertion-sort fallback
/// below 32 elements, so it is stable for small lists BY ACCIDENT and unstable
/// above (measured on Flutter 3.44.4: n=33 stable, n=40 not). Production HAS
/// ties -- two Restroom docs at value 3, plus every doc still missing `ord`
/// tying at 0. Under fan-out an unstable tie order moves a task between SLOTS
/// build-to-build, so a status re-hydrated by title appears to jump rows.
/// Decorating with the incoming index makes the comparator a total order; the
/// incoming order is Firestore's default document-id-ascending snapshot order.
/// `desc` flips the PRIMARY key only -- ties keep incoming order either way.
void checklistSortDocs(
    List<Map<String, dynamic>> docs, String sortField, bool desc) {
  final String f = sortField.trim();
  if (f.isEmpty) return;
  final List<MapEntry<int, Map<String, dynamic>>> decorated =
      <MapEntry<int, Map<String, dynamic>>>[
    for (int i = 0; i < docs.length; i++)
      MapEntry<int, Map<String, dynamic>>(i, docs[i]),
  ];
  decorated.sort((MapEntry<int, Map<String, dynamic>> a,
      MapEntry<int, Map<String, dynamic>> b) {
    final num va = coerceNum(a.value[f]);
    final num vb = coerceNum(b.value[f]);
    final int c = desc ? vb.compareTo(va) : va.compareTo(vb);
    if (c != 0) return c;
    return a.key.compareTo(b.key);
  });
  for (int i = 0; i < decorated.length; i++) {
    docs[i] = decorated[i].value;
  }
}

/// Blank-aware `text` slot read.
///
/// ★ SduiSpec.text() guards LENGTH ONLY (sdui_spec.dart:40) while
/// SduiSpec.str() is blank-aware (sdui_spec.dart:47-51). The spec's own `text`
/// starts with `◆`, so slot 0 EXISTS and is `''` -- `spec.text(0, def)` returns
/// `''`, not `def`. Any slot whose contract is "blank part => default" must go
/// through this wrapper.
String checklistText(SduiSpec spec, int i, String def) {
  final String v = spec.text(i);
  return v.trim().isEmpty ? def : v;
}

/// The D4 empty-state message: `text` slot 0, blank-aware.
String checklistEmptyMessage(SduiSpec spec) =>
    checklistText(spec, 0, checklistDefaultEmptyMessage);

// ─── widget ──────────────────────────────────────────────────────────────────

class ChecklistDynamic extends StatefulWidget {
  const ChecklistDynamic({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  /// Server JSON. Loosely typed BY DESIGN -- read through [SduiSpec].
  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  @override
  State<ChecklistDynamic> createState() => _ChecklistDynamicState();
}

class _ChecklistDynamicState extends State<ChecklistDynamic> {
  late final SduiSpec _spec;

  /// vid-scoped mapTableContent / subscription key. '' when unusable.
  String _code = '';

  int _position = 0;
  String _rawSearch = '';
  String _sortField = checklistDefaultSortField;
  bool _sortDesc = false;
  String _taskField = checklistDefaultTaskField;
  String _pendingLabel = checklistDefaultPendingLabel;

  /// D3. Size of the contiguous slot block this component claims, starting at
  /// [_position]. 0 (absent / blank / negative in config) means "claim exactly
  /// the task count".
  int _slots = 0;

  String _category = '';
  String _emptyMessage = checklistDefaultEmptyMessage;
  String _completedPrefix = checklistDefaultCompletedPrefix;
  String _sheetHeader = checklistDefaultSheetHeader;
  double _borderRadius = 10;
  List<double> _margin = <double>[0, 0, 0, 0];
  List<ChecklistOption> _options = const <ChecklistOption>[];
  Map<String, String> _labelToKey = const <String, String>{};

  /// COSMETIC ONLY, per title key. The slots store task+status and never a
  /// timestamp, so this is empty again after a ListView recycle and the
  /// "completed at HH:MM" line simply does not render until the task is
  /// re-ticked. Deliberate: persisting it would need a second block of slots.
  final Map<String, DateTime> _completedAt = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _spec = SduiSpec(widget.component);
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    _position = _spec.intOr('position', 0);
    // `search` is read RAW, NOT through SduiSpec.str: filterDriverHomeDocs owns
    // the autheniumDecode (step 1 of its 4-step pipeline,
    // driver_home_support.dart:705) and reading it decoded here would decode
    // twice.
    _rawSearch = (widget.component['search'] ?? '').toString().trim();
    // D5/D9: a BLANK sheet cell selects the DEFAULT (sdui_spec.dart:47-51), so
    // these two defaults must match the live DB field codes.
    _sortField = _spec.str('sortField', checklistDefaultSortField);
    _sortDesc = _spec.str('sortDir').toLowerCase() == 'desc';
    _taskField = _spec.str('taskField', checklistDefaultTaskField);
    _pendingLabel = _spec.str('pendingLabel', checklistDefaultPendingLabel);
    // D3. intOr returns the default for a missing / blank / non-numeric cell,
    // so 0 covers "absent" and "0" alike -- both mean "claim exactly N".
    _slots = _spec.intOr('slots', 0);
    _category = _spec.str('category');
    _borderRadius = _spec.intOr('borderRadius', 10).toDouble();
    // marginArray always returns exactly 4 doubles: its per-index inner try
    // yields 0.0 for a missing segment (global.dart:1442-1447). No length guard
    // needed -- this is NOT a diamondTextToList result.
    _margin = marginArray(_spec.str('margin', '0,0,0,0'));
    _options = checklistParseOptions(_spec.list('options'));
    _labelToKey = checklistLabelToKey(
      <String>[for (final ChecklistOption o in _options) o.label],
      _pendingLabel,
    );
    _emptyMessage = checklistEmptyMessage(_spec);
    _completedPrefix =
        checklistText(_spec, 1, checklistDefaultCompletedPrefix);
    _sheetHeader = checklistText(_spec, 5, checklistDefaultSheetHeader);
  }

  void _subscribe() {
    try {
      // parseTablePath FIRST, resolveAppVid SECOND. resolveAppVid falls through
      // to getTableVid, which reads the `late` global appCodeController and
      // throws LateInitializationError outside globalInit. Short-circuiting on
      // an empty docId keeps a table-less component (and every widget test)
      // away from it entirely.
      final TablePath tp = parseTablePath(_spec.str('table'));
      if (tp.tableDocId.isEmpty) return;
      final String appVid = resolveAppVid(widget.component);
      if (appVid.isEmpty) return;
      // vid-scoped: subscribeToMapCollection uses `code` as BOTH the dedup key
      // and the mapTableContent storage key, and the vid is not inherently in
      // it -- an unscoped code collides across tenants and silently serves the
      // first subscriber's docs. The same string is used for the read-back.
      _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    } catch (e) {
      devPrint('ChecklistDynamic subscribe: $e');
      _code = '';
    }
  }

  List<Map<String, dynamic>> _docs() {
    // ★ FIRST STATEMENT, UNCONDITIONAL. Reading the RxMap is what registers the
    // Obx dependency; RxMap.operator[] goes through the `value` getter, which
    // registers even for a missing key -- so an empty _code is safe here and a
    // `if (_code.isEmpty) return ...` guard ABOVE this line would reintroduce
    // the "[Get] the improper use of a GetX has been detected" fatal.
    // The explicit List.from is also required: mapTableContent is dynamic-fed,
    // and a `.map().toList()` off a dynamic infers List<dynamic> at runtime.
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
        mapTableContent[_code] ?? const <Map<String, dynamic>>[]);
    if (_rawSearch.isEmpty) return all;
    try {
      return filterDriverHomeDocs(all, _rawSearch, widget.scrName);
    } catch (e) {
      devPrint('ChecklistDynamic search: $e');
      // FAIL CLOSED. A search that cannot be evaluated must show nothing, not
      // every template's tasks. Same contract as filterByMultiClause, which
      // already returns [] for an unresolved {template}.
      return <Map<String, dynamic>>[];
    }
  }

  // ── status writes ─────────────────────────────────────────────────────────

  /// Set [title] to [newStatus] and rewrite the WHOLE slot block.
  ///
  /// Re-parses the block rather than trusting any in-State copy, so a snapshot
  /// that landed between builds cannot be clobbered. [titles] is the display
  /// order captured by the build that rendered the tapped row; if the template
  /// changed while a sheet was open the next build self-heals from the fresh
  /// title list.
  void _apply(List<String> titles, String title, String newStatus) {
    final int block = checklistEffectiveBlock(
        _position, checklistBlockSize(_slots, titles.length));
    if (block <= 0) return;
    final Map<String, String> statusByTitle =
        checklistStatusByTitle(_readBlock(block), _labelToKey);
    final String key = checklistTitleKey(title);
    if (newStatus == checklistStatusPending) {
      statusByTitle.remove(key);
      _completedAt.remove(key);
    } else {
      statusByTitle[key] = newStatus;
      if (newStatus == 'done') {
        _completedAt[key] = DateTime.now();
      } else {
        _completedAt.remove(key);
      }
    }
    // UNCONDITIONAL: finalData is the single source of truth and must land even
    // if this State was disposed while the sheet -- a route that outlives its
    // opener -- was open.
    _writeBlock(checklistSlotValues(
        titles, statusByTitle, _options, _pendingLabel, block));
    // Only the repaint is guarded: setState after dispose throws.
    if (mounted) setState(() {});
  }

  void _showStatusSheet(List<String> titles, String title, String current) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) => _ChkStatusSheet(
        options: _options,
        currentStatus: current,
        header: _sheetHeader,
        onSelect: (String newStatus) {
          _apply(titles, title, newStatus);
          // Pop with the SHEET's own context, not this State's: the sheet is a
          // route that outlives its opener, and the State may already be gone.
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  // ── per-row display helpers ───────────────────────────────────────────────

  _ChkStatusConfig _statusConfigForKey(String key) => _ChkStatusConfig(
        color: checklistStatusColor(key),
        label: checklistLabelForKey(key, _options, _pendingLabel),
      );

  IconData? _circleIcon(String status) {
    switch (status) {
      case 'done':
        return Icons.check;
      case 'not_available':
        return Icons.close;
      case 'skipped':
        return Icons.chevron_right;
      case 'issue':
        return Icons.priority_high;
      default:
        return null;
    }
  }

  /// Blank slot here means "render no subtitle" -- a DIFFERENT contract from
  /// checklistText's "blank => default", so this reads spec.text directly.
  String? _subtitleText(String status) {
    final int i;
    switch (status) {
      case 'not_available':
        i = 2;
        break;
      case 'skipped':
        i = 3;
        break;
      case 'issue':
        i = 4;
        break;
      default:
        return null;
    }
    final String v = _spec.text(i);
    return v.trim().isEmpty ? null : v;
  }

  String _completedAtLabel(String titleKey) {
    final DateTime? t = _completedAt[titleKey];
    if (t == null) return '';
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '$_completedPrefix $h:$m';
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = EdgeInsets.fromLTRB(
        widget.lPad, widget.tPad, widget.rPad, widget.bPad);

    if (_position <= 0) {
      // Visible marker, never a silent blank: a component with no position
      // submits nothing, and an officer must be able to see that it is broken.
      return Padding(
        padding: pad,
        child: Text('--${widget.component['type']}-- Error: position missing'),
      );
    }

    // GetBuilder: clearData resets finalData / isEnabled and then repaints every
    // '$scrName-$position' id it touched (api.dart:4693).
    // Obx: the Firestore snapshot lands asynchronously in mapTableContent.
    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$_position',
      builder: (_) => Obx(() {
        final List<Map<String, dynamic>> docs = _docs();
        return _content(pad, docs);
      }),
    );
  }

  /// The current value of every slot in the block, in slot order.
  ///
  /// ★ READ-ONLY: txfControllerCheck is deliberately NOT called. In the
  /// over-capacity case the write phase may never reach a slot, and an
  /// empty-but-existing txfController entry becomes a real '' cell in the
  /// submitted row (api.dart:4815 iterates EVERY entry) and inflates
  /// maxPosition. A slot this widget does not write must not exist because of
  /// this widget.
  List<String> _readBlock(int block) {
    final Map<int, InputController>? screen = txfController[widget.scrName];
    return <String>[
      for (int k = 0; k < block; k++) screen?[_position + k]?.finalData ?? '',
    ];
  }

  /// Write [values] into slots `_position .. _position + values.length - 1`.
  ///
  /// [values] comes from checklistSlotValues, whose length is exactly the block
  /// size -- that is the single guarantee that nothing outside the block is
  /// touched. controller.text is never written (a mid-build listener notify is
  /// a setState-during-build).
  void _writeBlock(List<String> values) {
    for (int k = 0; k < values.length; k++) {
      final int slot = _position + k;
      txfControllerCheck(widget.scrName, slot);
      txfController[widget.scrName]![slot]!.finalData = values[k];
    }
  }

  /// D3. Officer-facing over-capacity banner. Not configurable on purpose --
  /// see checklistOverflowMessage.
  Widget _warningRow(int overflow, int capacity) {
    return Padding(
      padding: EdgeInsets.only(
        top: _margin[0],
        bottom: _margin[1],
        left: _margin[2],
        right: _margin[3],
      ),
      child: Container(
        key: const ValueKey<String>('chkOverflow'),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(_borderRadius),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                checklistOverflowMessage(overflow, capacity),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB91C1C),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(EdgeInsets pad, List<Map<String, dynamic>> docs) {
    final List<Map<String, dynamic>> sorted =
        List<Map<String, dynamic>>.from(docs);
    checklistSortDocs(sorted, _sortField, _sortDesc);
    final List<String> titles = checklistTitles(sorted, _taskField);

    final int block = checklistEffectiveBlock(
        _position, checklistBlockSize(_slots, titles.length));

    // ★ PARSE PHASE -- read EVERY slot of the block BEFORE writing ANY of it.
    // The re-hydration source IS the block about to be overwritten, and a task
    // MOVES slot when the admin deletes an earlier task, so an interleaved
    // read/write would lose the moved task's status.
    final Map<String, String> statusByTitle =
        checklistStatusByTitle(_readBlock(block), _labelToKey);

    if (titles.isEmpty) {
      // ★ D8. WRITE NOTHING -- not even ''. A remount that precedes the
      // Firestore snapshot renders zero titles (AnyPage's ListView.builder has
      // no keep-alive, page/any_page.dart:168), and blanking the block there
      // would erase the officer's ticks. Same path for an unresolved
      // {template} (filterByMultiClause is fail-closed) and for a template with
      // zero seeded docs.
      return Padding(
        padding: pad,
        child: Center(
          child: Text(
            _emptyMessage,
            key: const ValueKey<String>('chkEmpty'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ),
      );
    }

    // ★ WRITE PHASE. Unconditional, every build: it survives ListView recycling
    // and it stops saveSend falling back to controller.text on the '--' birth
    // sentinel (api.dart:4839).
    _writeBlock(checklistSlotValues(
        titles, statusByTitle, _options, _pendingLabel, block));

    final int overflow = checklistOverflowCount(titles.length, block);

    return Padding(
      padding: pad,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (overflow > 0) _warningRow(overflow, block),
          for (int i = 0; i < titles.length; i++)
            if (i < block)
              _row(
                titles,
                i,
                titles[i],
                statusByTitle[checklistTitleKey(titles[i])] ??
                    checklistStatusPending,
              )
            else
              // D3. Beyond the block: rendered so the officer can SEE the task
              // exists, inert so a tap can never silently vanish. An excess row
              // that accepted taps would write into statusByTitle, be dropped by
              // checklistSlotValues, and snap back to pending on the next build.
              Opacity(
                opacity: 0.45,
                child: IgnorePointer(
                  child: _row(titles, i, titles[i], checklistStatusPending),
                ),
              ),
        ],
      ),
    );
  }

  /// One task card. Markup mirrors Tasklist.build (tasklist.dart:246-401) so the
  /// two render identically; the differences are the title source (doc, not
  /// text slot 0) and the ValueKeys, which exist so widget tests can address a
  /// specific row without a text finder that also matches the badge or the
  /// sheet.
  Widget _row(List<String> titles, int index, String title, String status) {
    final _ChkStatusConfig config = _statusConfigForKey(status);
    final bool isActive = status != checklistStatusPending;
    final bool isDone = status == 'done';
    final String key = checklistTitleKey(title);
    final IconData? circle = _circleIcon(status);
    final String? subtitle = _subtitleText(status);
    final String completed = _completedAtLabel(key);

    return Padding(
      padding: EdgeInsets.only(
        top: _margin[0],
        bottom: _margin[1],
        left: _margin[2],
        right: _margin[3],
      ),
      child: GestureDetector(
        onTap: () => _showStatusSheet(titles, title, status),
        child: Container(
          key: ValueKey<String>('chkRow-$index'),
          decoration: BoxDecoration(
            color:
                isActive ? config.color.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(_borderRadius),
            border: Border.all(
              color: isActive
                  ? config.color.withValues(alpha: 0.4)
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              GestureDetector(
                key: ValueKey<String>('chkToggle-$index'),
                onTap: () => _apply(
                    titles, title, isDone ? checklistStatusPending : 'done'),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? config.color : Colors.transparent,
                    border: Border.all(
                      color: isActive ? config.color : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                  ),
                  child: circle != null
                      ? Icon(circle, size: 14, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_category.isNotEmpty) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF3B82F6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _category,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDone
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF374151),
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: const Color(0xFF9CA3AF),
                      ),
                    ),
                    if (isDone && completed.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        completed,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isActive) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: config.color.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        config.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: config.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  GestureDetector(
                    key: ValueKey<String>('chkMore-$index'),
                    onTap: () => _showStatusSheet(titles, title, status),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status picker sheet. A COPY of Tasklist's `_StatusSheet`
/// (tasklist.dart:404-527), not an extraction: this round must not touch
/// tasklist.dart (the 5 static pages stay as a fallback per spec §8). The two
/// collapse into one when those pages retire.
class _ChkStatusSheet extends StatelessWidget {
  const _ChkStatusSheet({
    required this.options,
    required this.currentStatus,
    required this.header,
    required this.onSelect,
  });

  final List<ChecklistOption> options;
  final String currentStatus;
  final String header;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            Text(
              header,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const Divider(),
            ...List<Widget>.generate(options.length, (int i) {
              // A config with more than 4 triplets has no key to bind to.
              if (i >= checklistStatusKeys.length) {
                return const SizedBox.shrink();
              }
              final ChecklistOption opt = options[i];
              final String key = checklistStatusKeys[i];
              final Color color = checklistStatusColor(key);
              final bool isSelected = currentStatus == key;
              return InkWell(
                key: ValueKey<String>('chkOpt-$key'),
                onTap: () => onSelect(key),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: isSelected
                      ? BoxDecoration(
                          color: color.withValues(alpha: 0.05),
                          border:
                              Border.all(color: color.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            opt.icon,
                            style: TextStyle(
                              fontSize: 16,
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              opt.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                            Text(
                              opt.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: color, size: 20),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ChkStatusConfig {
  const _ChkStatusConfig({required this.color, required this.label});

  final Color color;
  final String label;
}
