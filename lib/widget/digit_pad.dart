// lib/widget/digit_pad.dart
//
// SDUI component `DIGIT_PAD` — N locked digit boxes shaped like a mechanical
// water-meter face, filled ONLY by this widget's own numpad, with an inline
// 3-tier verdict computed against the last reading on the `meter` doc.
//
// Spec: digit-pad-widget-dev-spec (Indonesian). v1 = §7.1-7.6.
//
// ── §7.8 IS CANCELLED; §7.7 IS THE SERIAL CHECK ─────────────────────────────
// The old plan was "OCR reads the DIGITS and compares them to what the officer
// typed". meter-serial-verify §1 cancelled it on 2026-08-25: a typo is already
// caught twice, more cheaply, by the backward and spike verdicts. Do not
// resurrect it from memory.
//
// OCR was re-tasked to check IDENTITY instead — the one thing the two numeric
// verdicts are structurally blind to is an officer standing at the WRONG METER,
// where the number is right but belongs to another unit. `serialField` names a
// field on the `meter` doc (`msn`); ML Kit reads the photo in the
// `photoPosition` slot and looks for that serial inside it. Blank serialField,
// blank doc value, or no usable photo -> ZERO ML Kit calls and a silent screen.
//
// `ocrPattern` is RETIRED (§3.2). It was only ever §7.8's, this widget never
// read it, and SduiSpec ignores keys nobody asks for — so a sheet that still
// carries the column is ignored silently with no code doing the ignoring.
// `text` segment 6 changed MEANING in place ({ocr} -> {serial}); segments 0-14
// did not shift, so older config still resolves correctly.
//
// ── Deliberate design points ────────────────────────────────────────────────
//  * NO TextField / TextFormField anywhere in this tree. That is the only way
//    spec §11's "the system keyboard never appears / there is no way to enter
//    a comma, dot or minus" is STRUCTURALLY guaranteed instead of validated.
//  * The verdict FAILS OPEN. Product decision #17 ("petugas selalu menang") and
//    §7.5 ("nol pembanding = diam"): a throw, a missing doc or an unreadable
//    comparator must leave the submit button ALIVE. This is the OPPOSITE of the
//    usual permission-gate rule in this repo and is intentional.
//  * ZERO hardcoded user-visible text. Every string is a `text` ◆-segment; every
//    number inside one arrives through the CLOSED token list of §3.1.
//  * NO new state store. The digit buffer lives in the slot's
//    TextEditingController.text and the submitted value in finalData, so
//    clearData already resets both (and the submit gate) on navigation.
//  * ★ LOAD-BEARING, DO NOT "SIMPLIFY": _content writes `ic.finalData` on EVERY
//    build, unconditionally. controller.text holds the raw hole-buffer
//    ("01_2_"), and saveSend's record composer falls back to controller.text
//    whenever finalData holds the '--' sentinel — which is the value
//    txfControllerCheck gives every freshly created slot. Making that write
//    conditional ("only when it changed", "only on tap") re-opens a path that
//    submits "01_2_" as a meter reading. The buffer and finalData are therefore
//    allowed to disagree; finalData is the one that is always correct.
//  * Growing the box count back resurrects digits an earlier shrink truncated
//    (5 -> 3 -> 5 shows "12345" again), because the refit is derived per build
//    and only persisted on the next tap. Deliberate — see the widget doc.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // SchedulerPhase
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // mapTableContent, screenUIComponent, devPrint
import '../global2.dart'; // txfController, txfControllerCheck, WidgetUpdateController
import '../model/input_controller.dart';
import '../screen_session.dart';
import '../sdui_spec.dart';
import 'digit_pad_support.dart';
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs
// ocrWriteToPosition — the repo's ONE cross-position writer (controller.text +
// selection + finalData + the GeneralGetXController mirror + the
// WidgetUpdateController repaint, all inside a try/catch). ocr_capture_support
// imports NO ML Kit (its own header states this), so reusing it does not drag
// the deferred §7.8 dependency in. A second copy here would be a second thing
// to keep in sync with clearData.
import 'ocr_capture_support.dart'; // ocrWriteToPosition
import 'panel_card_support.dart'; // TablePath, parseTablePath

/// Test seam: ML Kit cannot run under `flutter test` (the plugin is a
/// MethodChannel and throws MissingPluginException there, as
/// lib/dev/ocr_spike_main.dart's header already records), so widget tests
/// replace this with a counting fake. That is also what makes acceptance §11's
/// "nol ML Kit dipanggil" a countable assertion instead of a claim.
Future<String> Function(String path) digitPadOcrRead = _digitPadMlKitRead;

/// Spec §3.1 step 1: OCR the whole photo and take ALL recognised text.
///
/// `RecognizedText.text` is the plugin's own "string containing all the text
/// identified in an image", so there is nothing to flatten — ocr_capture's
/// `ocrFlattenElements` answers a different question (per-element boxes) and is
/// deliberately not reused.
///
/// Throws are NOT caught here: _applySerial owns the fail-open decision and
/// needs to see the cause to devPrint it. The `finally` only releases the
/// native recogniser.
Future<String> _digitPadMlKitRead(String path) async {
  TextRecognizer? recognizer;
  try {
    recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText out = await recognizer.processImage(
      InputImage.fromFilePath(path),
    );
    return out.text;
  } finally {
    try {
      await recognizer?.close();
    } catch (e) {
      devPrint('DigitPad ocr close: $e');
    }
  }
}

/// One position's serial verdict: the key it was computed from and its answer.
///
/// ONE object rather than two parallel maps, deliberately: DigitPadState's
/// _memoRecord writes both fields together and is the memo's ONLY writer, so
/// "the verdict always belongs to the key next to it" is structural instead of
/// a rule someone has to keep.
///
/// ★ TERMINAL. An instance means an ANSWER, never a pass in flight: a
/// non-empty [ocrKey] always has a real [match] beside it. An entry carrying a
/// key with no answer is exactly what made the check unrepeatable in r2 (W4) —
/// what is in flight is tracked per-State, never here.
class _DigitPadSerialMemo {
  String ocrKey = '';
  bool? match;
}

class DigitPad extends StatefulWidget {
  const DigitPad({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  /// Which submitted value the verdict sheet has already risen for, per screen
  /// per position.
  ///
  /// ★ static, NOT a State field. AnyPage renders through a ListView.builder
  /// with no keep-alive (any_page.dart) and buildPage(clear:true) re-mints
  /// linkElement[scrName] on a background readSettings refresh — both destroy
  /// DigitPadState. A State-local latch would therefore let the sheet re-rise
  /// unprompted while the officer is doing something else, which is exactly the
  /// failure §4c rule 3 exists to prevent.
  ///
  /// Keyed per screen (CLAUDE.md: never a single static value) and registered
  /// with ScreenSession below. It ALSO self-clears: _applySheet drops the entry
  /// whenever the submitted value is empty, which is what makes segment 12
  /// ("Perbaiki angkanya") and clearData-on-navigation both re-arm the raise
  /// with no extra hook.
  ///
  /// On the WIDGET class rather than the State class because
  /// screen_session_entries.dart reaches the two statics below through
  /// `DigitPad.` and Dart does not forward statics from a State.
  static final Map<String, Map<int, String>> _sheetRaised =
      <String, Map<int, String>>{};

  /// nav:screen + rebuild:none — the SignaturePad.writeState pair, for the same
  /// reason: in-flight user state must survive a background readSettings
  /// rebuild but must not survive navigation.
  static void registerScreenSession() {
    ScreenSession.ensure(
      'DigitPad.sheetRaised',
      DigitPad.clearSheetRaised,
      rebuild: RebuildPolicy.none,
    );
    // ensure() is idempotent by NAME, so registering both from the same call
    // site costs one map lookup after the first pad on the first screen.
    ScreenSession.ensure(
      'DigitPad.serialMemo',
      DigitPad.clearSerialMemo,
      rebuild: RebuildPolicy.none,
    );
  }

  static void clearSheetRaised(String scrName) {
    _sheetRaised.remove(scrName);
  }

  /// The serial verdict already computed for a position: its
  /// `'<photo slot value>|<doc serial>'` key and the answer.
  ///
  /// ★ static for the SAME reason _sheetRaised is — and it was a defect that it
  /// was not (r1 W2). AnyPage's ListView.builder destroys DigitPadState on
  /// scroll, so while this memo lived on the State, scrolling the pad away and
  /// back (a) re-ran ML Kit on every return, and (b) handed _applySheet an
  /// empty sheet key, whose re-arm branch DELETED the latch and let the
  /// dismissed sheet rise again unprompted — §4c rule 3, from the other side.
  ///
  /// Same policies as _sheetRaised: nav:screen (a different meter is a
  /// different verdict) plus rebuild:none (a background readSettings refresh
  /// must not re-run the OCR).
  static final Map<String, Map<int, _DigitPadSerialMemo>> _serialMemo =
      <String, Map<int, _DigitPadSerialMemo>>{};

  static void clearSerialMemo(String scrName) {
    _serialMemo.remove(scrName);
  }

  @override
  State<DigitPad> createState() => DigitPadState();
}

/// PUBLIC (the `FtzAutoNumberState` / `OcrCaptureState` precedent) so a widget
/// test can reach the state if it ever needs to.
class DigitPadState extends State<DigitPad> {
  static const Color _ink = Color(0xFF1E293B);
  static const Color _muted = Color(0xFF94A3B8);
  static const Color _boxOn = Color(0xFF1E293B);
  static const Color _boxOff = Color(0xFF64748B);
  static const Color _caret = Color(0xFF60A5FA);
  static const Color _keyBg = Color(0xFFF1F5F9);
  static const Color _keyBorder = Color(0xFFCBD5E1);
  static const Color _saneFg = Color(0xFF15803D);
  static const Color _saneBg = Color(0xFFDCFCE7);
  static const Color _spikeFg = Color(0xFFB45309);
  static const Color _spikeBg = Color(0xFFFEF3C7);
  static const Color _backFg = Color(0xFFB91C1C);
  static const Color _backBg = Color(0xFFFEE2E2);

  /// The red (litre) drum group. Spec §2.1: red is not decoration — it is the
  /// only signal that tells the officer where the m³ boundary sits.
  static const Color _boxRedOn = Color(0xFFB91C1C);
  static const Color _chipOnBg = Color(0xFF1E293B);
  static const Color _chipOffBg = Color(0xFFF1F5F9);
  static const Color _warnFg = Color(0xFFB45309);

  late final SduiSpec _spec;
  late final int? _position;
  late final int? _digitsPosition;
  late final int? _digitsRedPosition;
  late final int? _digitsSourcePosition;
  late final String _digitsField;
  late final String _digitsRedField;
  late final String _digitsMode;
  late final List<int> _blackOptions;
  late final List<int> _redOptions;
  late final String _compareField;
  late final String _avgField;
  late final num _spikeMultiplier;
  late final bool _blockOnBackward;

  // ── meter-serial-verify ──
  /// `getImages` slot whose photo the serial check reads. NULLED when it names
  /// this pad's own position — see the assignment in initState.
  late final int? _photoPosition;

  /// Name of the serial field on the `meter` doc. Blank = the whole serial
  /// check is dead, and ZERO ML Kit calls are made (acceptance §11).
  late final String _serialField;

  /// `TRUE` = a serial mismatch kills the page's save button.
  late final bool _blockOnSerialMismatch;

  /// mapTableContent key; '' when no `table` is configured (= no doc, no verdict).
  String _code = '';

  /// Caret box. State-local ON PURPOSE, and therefore NOT durable: AnyPage's
  /// list has no keep-alive, so scrolling the pad off-screen and back disposes
  /// this State and the caret returns to box 0. The BUFFER survives (it lives in
  /// controller.text), so nothing the officer typed is lost — only the caret
  /// moves. Promoting it to the slot would mean encoding two values in one
  /// String for a cosmetic gain.
  int _cursor = 0;

  /// "The inline picker is showing." Set by the segment-10 link in
  /// `digitsMode:"editable"` AND latched true by _pickBlack/_pickRed, because
  /// the first pick resolves the count and would otherwise make the picker
  /// vanish before the officer reaches the RED row.
  ///
  /// State-local and therefore NOT durable, for the same reason as _cursor:
  /// AnyPage's ListView.builder has no keep-alive. Scrolling the pad away
  /// closes the picker; the PICKED VALUES survive, because they live in the
  /// digitsPosition / digitsRedPosition slots, not in element state.
  bool _pickerOpen = false;

  /// The gate state this widget currently WANTS. Read inside the post-frame
  /// callback instead of capturing the argument at schedule time, so a verdict
  /// that flips twice in one frame applies the LAST value, not the first.
  ///
  /// There is deliberately NO memo of the state already APPLIED — see
  /// _scheduleGate.
  bool _gateWanted = false;
  bool _gatePending = false;

  @override
  void initState() {
    super.initState();
    _spec = SduiSpec(widget.component);
    // digitPadParsePosition, NOT getPosition(): getPosition does `int.parse(inp!)`
    // and THROWS on a missing/garbage position.
    _position = digitPadParsePosition(
      (widget.component['position'] ?? '').toString(),
    );
    _digitsPosition = digitPadParsePosition(_spec.str('digitsPosition'));
    _digitsRedPosition = digitPadParsePosition(_spec.str('digitsRedPosition'));
    _digitsSourcePosition = digitPadParsePosition(
      _spec.str('digitsSourcePosition'),
    );
    _digitsField = _spec.str('digitsField');
    _digitsRedField = _spec.str('digitsRedField');
    // str() IS blank-aware (unlike text()), so a blank cell yields 'auto' —
    // spec §8's documented default.
    _digitsMode = _spec.str('digitsMode', 'auto');
    // SduiSpec.list(), never a hand-rolled split: diamondTextToList('') returns
    // [''] , not [], and list() short-circuits that.
    _blackOptions = digitPadParseOptions(
      _spec.list('digitsOptions'),
      allowZero: false,
    );
    // allowZero: a '0' entry in digitsRedOptions is the MEANINGFUL choice
    // "no red digits" (Kawasan Ruko), not an empty value.
    _redOptions = digitPadParseOptions(
      _spec.list('digitsRedOptions'),
      allowZero: true,
    );
    _compareField = _spec.str('compareField');
    _avgField = _spec.str('avgField');
    _spikeMultiplier = num.tryParse(_spec.str('spikeMultiplier')) ?? 4;
    _blockOnBackward = _spec.str('blockOnBackward').toUpperCase() == 'TRUE';
    _serialField = _spec.str('serialField');
    _blockOnSerialMismatch =
        _spec.str('blockOnSerialMismatch').toUpperCase() == 'TRUE';
    // ★ NEVER this pad's own position. That slot holds the digit buffer, and
    // watching it would make every keypress re-enter our own setState — the
    // self-notifying loop rev d removed the digitsPosition listener for. Same
    // doctrine as _writeSlot, which refuses our own position for its own
    // reasons. `_position` is already assigned above, so this comparison is
    // safe here and nowhere earlier.
    final int? photoSlot = digitPadParsePosition(_spec.str('photoPosition'));
    _photoPosition = (photoSlot != null && photoSlot == _position)
        ? null
        : photoSlot;
    DigitPad.registerScreenSession();
    _subscribe();
  }

  // ── doc subscription ──────────────────────────────────────────────────────

  void _subscribe() {
    try {
      // parseTablePath FIRST, resolveAppVid SECOND. resolveAppVid falls through
      // to getTableVid, which reads the `late` global appCodeController and
      // throws LateInitializationError outside globalInit. Short-circuiting on an
      // empty docId keeps a table-less component (and every widget test) away
      // from it entirely.
      final TablePath tp = parseTablePath(_spec.str('table'));
      if (tp.tableDocId.isEmpty) return;
      final String appVid = resolveAppVid(widget.component);
      if (appVid.isEmpty) return;
      // vid-scoped: mapTableContent/_mapSubscribed keys omit vid, so another
      // tenant's same docId/subColl would dedup our stream away.
      _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    } catch (e) {
      // FAIL OPEN: no doc -> no verdict -> no block. Never an error dialog.
      devPrint('DigitPad subscribe: $e');
      _code = '';
    }
  }

  List<Map<String, dynamic>> _docs() {
    // firestoreDb and mapTableContent are dynamic-sourced: build the typed list
    // explicitly. A `.map().toList()` off a dynamic infers List<dynamic> at
    // runtime and fails to assign.
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const <Map<String, dynamic>>[],
    );
    // `search` is read RAW, not through SduiSpec.str: filterDriverHomeDocs owns
    // the autheniumDecode (step 1 of its 4-step pipeline) and reading it decoded
    // here would decode twice.
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return all;
    try {
      return filterDriverHomeDocs(all, rawSearch, widget.scrName);
    } catch (e) {
      devPrint('DigitPad search: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  // ── digitsPosition is an OUTPUT slot now (rev d) ──────────────────────────
  //
  // rev b watched the digitsPosition slot's TextEditingController so an
  // external picker could change the box count. rev d inverts the direction:
  // this widget WRITES those slots and the widget doc now forbids pointing any
  // other input widget at them, so there is nothing left to watch — and a
  // listener would fire on our own post-frame write and setState on ourselves.
  //
  // Rebuilds still arrive from all three real sources: the Obx on
  // mapTableContent (the meter doc landing), the GetBuilder id
  // '$scrName-$position' (clearData and isEnabled writes), and setState (taps).

  // ── photoPosition IS an input slot, and it DOES need a listener ───────────
  //
  // This is not a walk-back of the paragraph above. rev d removed a listener on
  // digitsPosition — a slot this widget WRITES, where a listener fires on our
  // own post-frame write and setStates on ourselves. photoPosition is the
  // opposite: an INPUT slot owned by otq_get_images_2, which this widget never
  // writes. No loop is possible.
  //
  // It is REQUIRED because none of the three rebuild sources above can see a
  // photo being taken: otq_get_images_2 repaints only its OWN position, and our
  // GetBuilder id is our own. Without this listener the officer takes the photo
  // and nothing here ever runs again — the exact silent-nothing shape the
  // digitsPosition/SELECTABLE_BTN field failure had (§12).
  //
  // Attached from the _scheduleSide POST-FRAME callback, never from initState:
  // the getImages component may sit anywhere in the page's `children`, so its
  // InputController may not exist yet while we are building. By the end of the
  // first frame every component on the page has been built, so one post-frame
  // pass is enough — and re-checking each build costs one map lookup and
  // survives buildPage(clear:true) re-minting txfController[scrName].

  /// The controller we are currently listening to, held by REFERENCE.
  ///
  /// ★ Held, never re-looked-up at detach time: buildPage(clear:true) re-mints
  /// txfController[scrName], so the map entry at dispose() time can be a
  /// DIFFERENT controller and the listener would survive on the old one.
  TextEditingController? _photoCtl;
  bool _photoDirty = false;

  void _ensurePhotoWatch() {
    final int? photoPosition = _photoPosition;
    // Feature off, or nothing to watch: attach nothing at all. Acceptance §11
    // measures "nol delay tambahan" for serialField:"" — a listener that never
    // fires would still be a thing to keep in sync with dispose.
    if (photoPosition == null || _serialField.isEmpty) return;
    final InputController? ic = txfController[widget.scrName]?[photoPosition];
    // Slot not minted yet: the next build's post-frame tries again. Do NOT
    // txfControllerCheck it into existence here — buildDisplayComponent owns
    // the seeding of initialValue/isEnabled for that slot and creating it early
    // would race that.
    if (ic == null) return;
    if (identical(_photoCtl, ic.controller)) return;
    _detachPhotoWatch();
    _photoCtl = ic.controller;
    ic.controller.addListener(_onPhotoChanged);
  }

  void _detachPhotoWatch() {
    final TextEditingController? c = _photoCtl;
    _photoCtl = null;
    if (c == null) return;
    try {
      // removeListener is explicitly documented safe on an already-disposed
      // ChangeNotifier ("This method is allowed to be called on disposed
      // instances for usability reasons"), so no liveness check is needed.
      c.removeListener(_onPhotoChanged);
    } catch (e) {
      devPrint('DigitPad photo watch detach: $e');
    }
  }

  /// The photo slot changed — rebuild so _content can restage the serial key.
  ///
  /// ★ Deferred ONLY during SchedulerPhase.persistentCallbacks. otq_get_images_2
  /// assigns controller.text from its own initState, which runs inside the
  /// build phase; marking an already-built element dirty there is a "setState()
  /// called during build" assertion. Every other phase is safe, and setState is
  /// what SCHEDULES the frame — addPostFrameCallback only appends to a list and
  /// does not schedule one, so deferring unconditionally would drop the rebuild
  /// whenever the write arrives at idle (a plain tap callback, which is the
  /// normal case).
  void _onPhotoChanged() {
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_photoDirty) return;
      _photoDirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _photoDirty = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _detachPhotoWatch();
    super.dispose();
  }

  // ── submit gate (spec §7.6) ───────────────────────────────────────────────

  /// Push the gate OFF the build phase.
  ///
  /// Writing another controller's isEnabled and calling
  /// WidgetUpdateController.update() from inside build() marks the RBT's
  /// GetBuilder dirty mid-frame — a "setState() called during build". Post-frame
  /// is the seam.
  ///
  /// ★ There is deliberately NO memo of the state already applied. `isEnabled`
  /// is one flag with SEVERAL writers, and the ambient one is not optional:
  /// buildDisplayComponent's `rbt` else-branch rewrites every positioned RBT
  /// child's isEnabled (and initialIsEnabled) straight from config, with no
  /// isFieldUntouched-style guard, and constructAllPageElements runs that for
  /// EVERY screen on any server UI push. A form page is not repainted by
  /// rePaintScreen (that is home-only), so this State survives with its memo
  /// intact while the flag underneath it has been reset to enabled. A widget
  /// that remembered "I already blocked" would then never re-assert, and the
  /// ONLY blocking path in the system (product #21 / spec §7.6) would
  /// un-latch silently. Re-asserting every build is cheap and cannot loop:
  /// _applyGate diffs against the OBSERVED ic.isEnabled and calls update()
  /// only when something actually changed, and that update() marks the RBT's
  /// GetBuilder dirty — never this widget.
  void _scheduleGate(bool block) {
    _gateWanted = block;
    if (_gatePending) return;
    _gatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gatePending = false;
      if (!mounted) return;
      // Read the FIELD, not a captured argument: _content may have run again
      // with an opposing verdict since this callback was queued.
      _applyGate(_gateWanted);
    });
  }

  /// Idempotent: safe to run on every frame. Never throws.
  void _applyGate(bool block) {
    try {
      final List<int> positions = digitPadSaveSendPositions(
        screenUIComponent[widget.scrName]?['children'],
      );
      // Nothing gateable on this page (e.g. a savesend button with no
      // position). Nothing to record either — the next build re-runs this.
      if (positions.isEmpty) return;
      final List<String> ids = <String>[];
      for (final int pos in positions) {
        final InputController? ic = txfController[widget.scrName]?[pos];
        if (ic == null) continue;
        // Restore to initialIsEnabled, NOT a hardcoded true: a savesend button
        // the page config ships disabled must stay disabled.
        final bool next = block ? false : ic.initialIsEnabled;
        if (ic.isEnabled == next) continue;
        ic.isEnabled = next;
        ids.add('${widget.scrName}-$pos');
      }
      if (ids.isNotEmpty) {
        Get.find<WidgetUpdateController>().update(ids);
      }
    } catch (e) {
      // FAIL OPEN by design (product #17). A gate that throws must never leave
      // the submit button dead. Swallowing here does not lose the attempt: with
      // no memo, the next build schedules the gate again.
      devPrint('DigitPad gate: $e');
    }
  }

  // ── output slots + sheet (post-frame, spec §2.2 rules 1-2 / §4c) ──────────

  /// What the sheet will render, refreshed every build. Read in the post-frame
  /// callback rather than captured at schedule time, so a verdict that flips
  /// twice in one frame uses the LAST value — the same rule as _gateWanted.
  String _sheetMessage = '';
  Color _sheetFg = _spikeFg;
  Color _sheetBg = _spikeBg;
  IconData _sheetIcon = Icons.warning_amber_outlined;
  bool _sheetBlocked = false;

  int? _wantBlack;
  int _wantRed = 0;
  String _wantSource = '';
  bool _wantSheet = false;

  /// The composite raise-once key for THIS build — see digitPadSheetKey.
  /// '' means "there is no reason to raise the sheet at all", which is also the
  /// signal _applySheet uses to RE-ARM the latch.
  String _wantSheetKey = '';
  bool _sidePending = false;

  // ── meter-serial-verify: the async seam ──
  //
  // _content stays FULLY SYNCHRONOUS — there is deliberately no Future
  // anywhere in build. The OCR runs in the existing _scheduleSide post-frame
  // callback and publishes its answer through setState, exactly like the meter
  // doc landing does through the Obx.

  /// `'<raw photo slot value>|<raw doc serial>'` the verdict below was computed
  /// from — the key of an ANSWER, never of a read in flight.
  ///
  /// ★ This memo IS the "photo replaced ⇒ recompute" rule of spec §7.7: a new
  /// photo mints a new key, and no stored answer carries it.
  ///
  /// ★★ Backed by DigitPad._serialMemo, NOT by a State field (r1 W2). A scroll
  /// destroys this State; a State-local memo would therefore re-run ML Kit and
  /// re-raise the dismissed sheet every time the pad came back on screen.
  ///
  /// ★★★ TERMINAL ONLY (r2 W4). r2 claimed the key here BEFORE the await and
  /// wrote the answer after it, so a pass abandoned in between — an unmount, or
  /// a throw — left a claimed key with no answer, and every later pass then
  /// returned at the guard below. The serial check, and with
  /// blockOnSerialMismatch:"TRUE" its gate, went silently dead for that photo
  /// until a new photo or a navigation. What is in flight now lives in
  /// [_dispatchedOcrKey], which is per-State and dies with it.
  String get _ocrKey => _memoRead()?.ocrKey ?? '';

  /// null = never answered, or not applicable. false = the serial was NOT found.
  ///
  /// Only honoured while its key still matches — see `serialMismatch` in
  /// _content, which is what kills a stale verdict in the SAME frame the photo
  /// changes.
  ///
  /// Stored alongside [_ocrKey] in ONE object, so the pair cannot drift apart.
  bool? get _serialMatch => _memoRead()?.match;

  /// This position's memo, or null when there is none yet.
  ///
  /// A null [_position] cannot reach here — build() renders the
  /// "position missing" marker and returns before _content — so the null branch
  /// is a guard, not a state the feature runs in.
  _DigitPadSerialMemo? _memoRead() {
    final int? position = _position;
    if (position == null) return null;
    return DigitPad._serialMemo[widget.scrName]?[position];
  }

  /// Records the TERMINAL verdict for [key] — both halves together, and the
  /// only write the memo ever takes.
  ///
  /// [scrName] and [position] are handed in rather than read off `widget` and
  /// the State because this has to work after this State is disposed. That is
  /// the whole point of the memo: an answer must outlive the State that asked
  /// for it, or an officer who scrolls during the OCR loses the check.
  ///
  /// [live] is the caller's `mounted`. A live State always writes — it owns this
  /// slot. A DEAD one still records its answer (that IS the W4 fix) but never
  /// over an entry holding a DIFFERENT key: a newer State has since answered
  /// for a newer photo, and overwriting that would make an on-screen mismatch,
  /// and its gate, disappear.
  static void _memoRecord(
    String scrName,
    int? position,
    String key,
    bool match, {
    required bool live,
  }) {
    if (position == null) return;
    final _DigitPadSerialMemo? answered =
        DigitPad._serialMemo[scrName]?[position];
    if (!live && answered != null && answered.ocrKey != key) return;
    final _DigitPadSerialMemo memo =
        answered ??
        (DigitPad._serialMemo[scrName] ??= <int, _DigitPadSerialMemo>{})
            .putIfAbsent(position, () => _DigitPadSerialMemo());
    memo.ocrKey = key;
    memo.match = match;
  }

  /// Staged by _content for the post-frame pass, same idiom as _wantBlack.
  String _wantSerial = '';
  String _wantPhotoRaw = '';
  String _wantOcrKey = '';

  /// The key this State has already DISPATCHED a read for. Per-State, and
  /// never cleared.
  ///
  /// ★ Deliberately NOT in the memo. A State that dies holding an
  /// "in flight" mark in a STATIC map poisons that key for every State after it
  /// (r2 W4); a State that dies holding it here takes it to the grave, which is
  /// precisely what "the next State may try once more" means.
  String _dispatchedOcrKey = '';

  /// Spec §3.1 + §7.1-4. NEVER throws, NEVER blocks on failure.
  Future<void> _applySerial() async {
    final String key = _wantOcrKey;
    // ★★★ TWO facts, TWO fields (r2 W4). "An answer exists for this key" is
    // the memo, which is static and outlives this State. "A read is in flight
    // for this key" is _dispatchedOcrKey, which is per-State. r2 kept both in
    // the memo, so a pass abandoned mid-flight left a key with no answer under
    // it and no later pass could get past this line.
    if (key == _ocrKey) return; // answered already, by this State or another
    // One attempt per key per State lifetime — the semantics r1 got for free by
    // being State-local. It carries two jobs: re-entrancy (a second post-frame
    // pass in the same State cannot start a second read, since _sidePending
    // dedupes per FRAME and not per key), and, because a throw leaves the memo
    // untouched on purpose, it is the only thing between a build with no ML Kit
    // plugin and one native call per keystroke.
    if (key == _dispatchedOcrKey) return;
    _dispatchedOcrKey = key;
    // Nothing invalidates the previous answer here any more, deliberately: the
    // terminal write below replaces both halves at once, and _content's
    // `ocrKey == _ocrKey` term already stops a verdict rendering for a photo
    // that has left the slot — one frame EARLIER than this pass could. r2
    // nulled `match` while leaving `ocrKey` set, which is the very shape W4 is
    // about: let the photo come back to that key and the entry would match with
    // nothing in it, blocking the recompute for good.
    //
    // Captured BEFORE the await: the write at the bottom has to work when this
    // State is already gone, and reaching through `widget` then is not a thing
    // to depend on.
    final String scrName = widget.scrName;
    final int? position = _position;
    // ── the four TOTAL-SILENCE conditions (spec §7.1-2, acceptance §11) ──
    // Each returns BEFORE digitPadOcrRead, which is what makes the ML Kit call
    // count provably zero rather than merely quiet.
    if (_serialField.isEmpty) return; // feature never requested
    if (digitPadNormalizeSerial(_wantSerial).isEmpty) {
      return; // no serial recorded on this meter -> nothing to compare
    }
    final List<String> paths = digitPadPhotoPaths(_wantPhotoRaw);
    if (paths.isEmpty) {
      // ★ The ONE silence on this path that is not "the feature was never
      // requested": serialField is set, a serial IS recorded and the slot is
      // NOT empty — the check was asked for and simply cannot run. Reachable on
      // an EDIT page (currentValue seeds the slot with a plain https Storage
      // URL) and after a cancelled camera (emptyImageUrl); ML Kit can open
      // neither from a file path. Logged so the field can tell this apart from
      // an unconfigured serialField, which is silent by design.
      devPrint('DigitPad serial: no local photo path in the slot');
      return;
    }
    bool match = false;
    try {
      // ★ Per photo, NEVER concatenated. Joining the texts first would let a
      // serial that straddles two photos' texts read as a match on neither
      // photo — a FALSE match on the one thing this check exists to catch.
      for (final String path in paths) {
        final String text = await digitPadOcrRead(path);
        if (digitPadSerialSatisfied(ocrText: text, serial: _wantSerial)) {
          match = true;
          break;
        }
      }
    } catch (e) {
      // FAIL OPEN, and this one is a RATIFIED product decision rather than the
      // repo's usual gate rule: spec §10 lists "blokir waktu OCR gagal baca apa
      // pun" under Not Doing, and product #17 says the officer always wins. A
      // missing file, a MissingPluginException on a build without the plugin,
      // or an ML Kit model resolution failure all land here and leave
      // _serialMatch null -> no sheet, no gate, nothing on screen.
      //
      // ★ Deliberate (r2 W4 asked for this decision to be made, not
      // inherited): the memo is left UNTOUCHED, so nothing here can block a
      // later attempt, while _dispatchedOcrKey stops THIS State retrying. A new
      // State — a scroll back, a navigation — tries once more, which is r1's
      // behaviour and the right one for the transient half of this branch (an
      // ML Kit first-call model init). A permanent cause simply fails again,
      // once per State, silently.
      devPrint('DigitPad serial OCR: $e');
      return;
    }
    // The photo was replaced again while we were awaiting: a newer pass in this
    // same State owns the slot and has already started its own read.
    if (key != _dispatchedOcrKey) return;
    // ★★★ Recorded BEFORE the mounted check, and that ordering IS the W4 fix.
    // A scroll during the 100-500 ms ML Kit round-trip disposes this State, but
    // the answer it just computed is still the right answer for a photo that is
    // still in the slot: discarding it is what left the check permanently dead.
    // It saves an ML Kit call on the way back, too.
    _memoRecord(scrName, position, key, match, live: mounted);
    if (!mounted) return;
    setState(() {});
  }

  /// finalData of another slot ('' when that slot does not exist yet).
  String _slotValue(int? position) {
    if (position == null) return '';
    return txfController[widget.scrName]?[position]?.finalData ?? '';
  }

  void _scheduleSide() {
    if (_sidePending) return;
    _sidePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sidePending = false;
      if (!mounted) return;
      // ★ Attach FIRST: without the photo-slot listener nothing here ever runs
      // again after the officer takes the photo (see the photoPosition section
      // above). Cheap and idempotent — one map lookup plus an identity check.
      _ensurePhotoWatch();
      _applyOutputs();
      _applySheet();
      // Unawaited on purpose: the post-frame callback must stay synchronous.
      // _applySerial owns its own mounted/staleness re-checks after the await
      // and never throws out of itself.
      _applySerial();
    });
  }

  /// §2.2 rule 1: the three slots are written ALWAYS — from config as much as
  /// from the picker — because the CF needs them to make the choice permanent.
  /// Nothing resolved yet -> write nothing at all (an empty write would tell
  /// the CF "0 digits", which is worse than telling it nothing).
  void _applyOutputs() {
    final int? black = _wantBlack;
    if (black == null) return;
    _writeSlot(_digitsPosition, black.toString());
    _writeSlot(_digitsRedPosition, _wantRed.toString());
    _writeSlot(_digitsSourcePosition, _wantSource);
  }

  /// Diff-guarded cross-slot write.
  ///
  /// The guard is not cosmetic: ocrWriteToPosition ends in
  /// WidgetUpdateController.update(['$scrName-$position']), so an unguarded
  /// write would repaint the target slot's widget on EVERY build of this pad.
  ///
  /// Never writes our own position — that slot holds the reading, not a count.
  void _writeSlot(int? position, String value) {
    if (position == null || value.isEmpty) return;
    if (position == _position) return;
    final InputController? ic = txfController[widget.scrName]?[position];
    if (ic != null && ic.finalData == value && ic.controller.text == value) {
      return;
    }
    ocrWriteToPosition(
      widget.scrName,
      position,
      display: value,
      finalData: value,
    );
  }

  void _applySheet() {
    final int? position = _position;
    if (position == null) return;
    // ★ The latch remembers the TWO axes INDEPENDENTLY — see
    // digitPadNextSheetLatch. r1 stored the whole composite and compared it
    // whole, so a change on either axis wiped the other's memory: with a serial
    // mismatch live, every complete/incomplete transition of the digit buffer
    // re-raised the serial sheet, and correcting one digit cost two modal
    // sheets. §4c rule 1 is the first thing that breaks when that happens.
    //
    // Re-arm is per-axis too. An empty NUMERIC half means the next COMPLETE
    // value is a new value and deserves a fresh raise — which is what makes
    // segment 12 ("Perbaiki angkanya") and clearData-on-navigation work with no
    // extra hook, byte for byte as rev e did. The SERIAL half only ever changes
    // when the photo does (§7.7). An entry empty on BOTH axes is removed, so
    // '' stays the single re-arm signal digitPadSheetKey documents.
    final String next = digitPadNextSheetLatch(
      previous: DigitPad._sheetRaised[widget.scrName]?[position] ?? '',
      sheetKey: _wantSheetKey,
      raised: _wantSheet,
    );
    if (next.isEmpty) {
      DigitPad._sheetRaised[widget.scrName]?.remove(position);
    } else {
      // Stored BEFORE showing: showModalBottomSheet is async and this pad
      // rebuilds while the sheet is up. DigitPad.clearSheetRaised still drops
      // the whole per-screen map, so the ScreenSession registration is
      // unaffected.
      (DigitPad._sheetRaised[widget.scrName] ??= <int, String>{})[position] =
          next;
    }
    if (!_wantSheet) return;
    _wantSheet = false;
    _openSheet(position);
  }

  // ── interaction ───────────────────────────────────────────────────────────

  void _apply(DigitPadEntry e, int position) {
    try {
      final InputController ic = txfController[widget.scrName]![position]!;
      ic.controller.text = e.buffer;
      ic.finalData = digitPadSubmitValue(e.buffer);
    } catch (err) {
      devPrint('DigitPad apply: $err');
    }
    setState(() {
      _cursor = e.cursor;
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = EdgeInsets.fromLTRB(
      widget.lPad,
      widget.tPad,
      widget.rPad,
      widget.bPad,
    );

    final int? position = _position;
    if (position == null) {
      return Padding(
        padding: pad,
        child: Text('--${widget.component['type']}-- Error: position missing'),
      );
    }

    // GetBuilder: clearData resets finalData / controller.text / isEnabled and
    // then repaints every '$scrName-$position' id it touched.
    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$position',
      builder: (_) => Obx(() {
        // FIRST statement, unconditional: reading the RxMap is what registers the
        // Obx dependency. An Obx that registers ZERO observables is a documented
        // fatal in this repo.
        final List<Map<String, dynamic>> docs = _docs();
        return _content(pad, position, docs);
      }),
    );
  }

  Widget _content(
    EdgeInsets pad,
    int position,
    List<Map<String, dynamic>> docs,
  ) {
    txfControllerCheck(widget.scrName, position);
    final InputController ic = txfController[widget.scrName]![position]!;

    // ── box count (spec §2.2 / §7.2) ──
    //
    // Precedence is SLOT first, doc second — unchanged from rev b, and now
    // load-bearing in a SECOND way: rev d makes this widget WRITE the slot, so
    // whichever source resolves FIRST latches. A `meter` doc that lands late
    // must never make the boxes jump and silently wipe a partly typed reading.
    //
    // Two calls into the UNCHANGED digitPadResolveCount instead of one: that
    // keeps its precedence and its digitPadMaxBoxes cap byte-for-byte while
    // still telling us WHICH source answered (needed for digitsSourcePosition).
    final Map<String, dynamic>? doc = docs.isNotEmpty ? docs.first : null;
    final String blackSlot = _slotValue(_digitsPosition);
    final int? blackFromSlot = digitPadResolveCount(
      slotValue: blackSlot,
      docValue: null,
    );
    final int? black =
        blackFromSlot ??
        digitPadResolveCount(
          slotValue: '',
          docValue: (_digitsField.isNotEmpty && doc != null)
              ? doc[_digitsField]
              : null,
        );
    final bool fromDoc = black != null && blackFromSlot == null;

    final int red = digitPadResolveRedCount(
      slotValue: _slotValue(_digitsRedPosition),
      docValue: (_digitsRedField.isNotEmpty && doc != null)
          ? doc[_digitsRedField]
          : null,
    );
    final DigitPadLayout layout = black == null
        ? const DigitPadLayout(0, 0)
        : digitPadLayout(black, red);

    final DigitPadPickerState picker = digitPadPickerState(
      hasCount: black != null,
      mode: _digitsMode,
      hasOptions: _blackOptions.isNotEmpty,
      // ★ A pick needs somewhere to land. _writeSlot refuses a null position,
      // an unparseable one, and our own position — and _applyOutputs returns
      // early while `black` is null. Without this term the officer would face a
      // forced picker whose every chip tap is a no-op, with the submit gate
      // engaged and no memo to un-latch it: a permanently dead page.
      canPersist: _digitsPosition != null && _digitsPosition != _position,
    );

    if (black == null && picker != DigitPadPickerState.forced) {
      // Nothing resolves AND nothing is pickable. Block nothing — one bad
      // config cell must not lock the officer out of the page (product #17;
      // interview decision 5) — but do NOT render nothing either.
      //
      // rev f / §12: rendering nothing is what the field build did, and the
      // officer saw a blank gap with no title, no boxes and NO ERROR, so a
      // broken config survived a whole trip. Same visible-marker idiom as
      // `position missing` above and as buildDisplayComponent's unknown-type
      // fallback: silence is what makes a config bug expensive.
      //
      // ★ Both writes happen on BOTH exits below. finalData clears the '--'
      // birth sentinel (saveSend's composer falls back to controller.text while
      // it survives), and the gate must never leave an officer locked out by a
      // config cell he cannot fix. Neither is conditional on the marker being
      // painted.
      ic.finalData = '';
      _scheduleGate(false);
      // ★ The doc is still in flight: that is LOADING, not a broken cell.
      // subscribeToMapCollection assigns mapTableContent[_code] only inside its
      // snapshot listener (table_repository.dart:2180), so every build before
      // the first snapshot sees zero docs. Without this the primary config shape
      // (`table` + `digitsField`, count from the doc, no `digitsOptions`
      // fallback) shows the error marker on every cold entry, accusing healthy
      // config. Spec (5).md:186 calls a not-yet-existing meter doc "perilaku
      // yang benar, bukan error".
      //
      // ⚠ This closes the ONLINE cold-entry window only. main.dart:63-64 sets
      // persistenceEnabled:true, so offline the listener still fires once from
      // cache and table_repository.dart:2180 writes the key unconditionally —
      // an empty CACHED result is indistinguishable here from a server-confirmed
      // absent doc. A first-ever offline visit to a meter whose doc was never
      // cached therefore still shows the marker. Telling the two apart needs
      // snapshot.metadata.isFromCache plumbed through subscribeToMapCollection,
      // a shared-repository change and out of this widget's scope.
      //
      // containsKey, NOT docs.isEmpty: only the key's PRESENCE separates "no
      // snapshot yet" from "snapshot landed, doc genuinely absent". docs.isEmpty
      // is true for both and would suppress the marker forever on a real empty
      // collection. _code.isNotEmpty keeps a table-less component (it never
      // subscribes, so the key never appears) out of a permanent loading state;
      // _digitsField.isNotEmpty keeps the marker loud for a config that names a
      // table but no field to read from it — no snapshot can resolve that one.
      if (_digitsField.isNotEmpty &&
          _code.isNotEmpty &&
          !mapTableContent.containsKey(_code)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: pad,
        child: Text(
          '--${widget.component['type']}-- Error: no digit count '
          '(digitsField/doc empty, and no pickable '
          'digitsOptions + digitsPosition)',
        ),
      );
    }

    final bool hasBoxes = black != null;

    // Re-establish the buffer from the slot on EVERY build. clearData wipes
    // controller.text back to initialValue on navigation, and SDUI widgets are
    // cached in linkElement so initState runs once per app lifetime and is NOT a
    // reset hook. Idempotent, and it never writes back during build (assigning
    // .text notifies listeners, which mid-frame is a setState-during-build).
    final String buffer = hasBoxes
        ? digitPadNormalizeBuffer(ic.controller.text, layout.total)
        : '';
    final int holes = digitPadHoleCount(buffer);
    if (_cursor > layout.total) _cursor = layout.total;
    if (_cursor < 0) _cursor = 0;
    if (holes == layout.total) _cursor = 0; // fully cleared -> caret home

    // ★ finalData is written UNCONDITIONALLY, every build. The record composer in
    // saveSend falls back to controller.text when finalData holds the '--'
    // sentinel (the InputController birth value), which would submit the raw
    // hole-buffer as the meter reading. Writing a digit string or '' here closes
    // that by construction. NOTE this is the opposite of ocr_capture's
    // ocrNormalizeSeed, which preserves '--' because that widget WANTS the
    // fallback.
    // ★ Still UNCONDITIONAL, and now on BOTH paths — including the forced
    // picker, where there are no boxes at all. digitPadSubmitValue('') is '',
    // so an officer who never picks submits nothing rather than the '--'
    // sentinel that would make saveSend fall back to controller.text.
    final String submit = digitPadSubmitValue(buffer);
    ic.finalData = submit;

    final bool enabled = ic.isEnabled;

    // ── verdict (spec §7.5) — FAILS OPEN ──
    DigitPadVerdict verdict = DigitPadVerdict.none;
    num? prev;
    num? avg;
    num? value;
    try {
      value = submit.isEmpty ? null : num.tryParse(submit);
      if (_compareField.isNotEmpty && docs.isNotEmpty) {
        prev = digitPadNum(docs.first[_compareField]);
        if (_avgField.isNotEmpty) avg = digitPadNum(docs.first[_avgField]);
      }
      verdict = digitPadVerdict(
        value: value,
        prev: prev,
        avg: avg,
        spikeMultiplier: _spikeMultiplier,
      );
    } catch (e) {
      // Product #17: a verdict failure NEVER blocks and NEVER surfaces.
      devPrint('DigitPad verdict: $e');
      verdict = DigitPadVerdict.none;
    }

    // THREE booleans, deliberately NOT the same one.
    //
    //  * `verdictBlock` — "the backward gate is engaged". Drives the card's
    //    segment-5 footer and, through _sheetBlocked, the sheet's segment-13
    //    suppression.
    //  * `block` — the combined submit gate (backward OR unfilled picker).
    //  * the argument actually passed to _scheduleGate.
    //
    // An unfilled picker is not a backward reading, which is why `block` and
    // `verdictBlock` differ: segment 5's copy ("kamu sedang berdiri di meter
    // unit lain") would be misleading on a picker. The picker's own warning is
    // segment 11.
    //
    // ★ `&& enabled` on verdictBlock, for the SAME reason the gate call carries
    // it: on a disabled pad every key, box and chip is inert, so the backward
    // gate is not engaged — nothing is being demanded of the officer because
    // nothing is possible. Without this term the sheet rises saying "fix it",
    // hides the acknowledge button that is his only exit, and the card repeats
    // the same demand in the footer, all while the save button is alive: a
    // modal demanding a correction he cannot make. Applied HERE at the
    // definition rather than at its readers, because the boolean's MEANING is
    // wrong on a disabled pad, not just its use.
    //
    // `block` deliberately does NOT carry the term — _scheduleGate(block &&
    // enabled) below applies it once, at the only place `block` is consumed.
    // ── meter-serial-verify (spec §3.1/§7) ──
    //
    // Resolved HERE and not in the post-frame pass so that _content stays the
    // single place that decides what is on screen this frame.
    //
    // `photoRaw` is read only when the feature is on: with serialField blank
    // this whole feature costs one String.isEmpty per build and nothing else.
    final String photoRaw = _serialField.isEmpty
        ? ''
        : _slotValue(_photoPosition);
    // Firestore values are dynamic and flip between String and num per tenant:
    // stringify, never cast. A null field yields '' and silences the check.
    final String serialRaw = (_serialField.isNotEmpty && doc != null)
        ? (doc[_serialField] ?? '').toString().trim()
        : '';
    final String ocrKey = (photoRaw.isEmpty || serialRaw.isEmpty)
        ? ''
        : '$photoRaw|$serialRaw';
    // ★ The SYNCHRONOUS staleness guard. _serialMatch belongs to the photo it
    // was computed from; the moment the officer retakes the photo `ocrKey`
    // changes and the old verdict stops rendering IN THIS FRAME — one frame
    // before _applySerial's post-frame pass can null it. Without this term a
    // dismissed "wrong meter" warning could flash back over a corrected photo.
    final bool serialMismatch =
        _serialMatch == false && ocrKey.isNotEmpty && ocrKey == _ocrKey;
    // Who gets the sheet when both have something to say — the NUMERIC verdict
    // wins (see digitPadSerialOwnsSheet for why).
    final bool serialOwns = digitPadSerialOwnsSheet(
      verdict: verdict,
      serialMismatch: serialMismatch,
    );
    // ★ `&& enabled` for the SAME reason the two gates below carry it, and it
    // is the conservative direction here: on a disabled pad the whole page is
    // normally read-only, so the retake that would clear this gate is not
    // available either. See the widget doc for the residual — with the pad
    // ENABLED and blockOnSerialMismatch:"TRUE" the officer's only exit is
    // retaking the photo in a DIFFERENT widget, which is why spec §10 mandates
    // FALSE for v1.
    final bool serialBlock =
        _blockOnSerialMismatch && serialMismatch && enabled;

    final bool verdictBlock =
        (digitPadShouldBlock(verdict, _blockOnBackward) && enabled) ||
        serialBlock;
    final bool block = digitPadBlockSubmit(
      verdict: verdict,
      blockOnBackward: _blockOnBackward,
      picker: picker,
    );
    // ★ `&& enabled` — a gate the officer cannot clear is not a gate, it is a
    // brick. When the pad is disabled he can neither pick a count nor retype a
    // digit: every numpad key, the backspace, every box and both chip rows are
    // inert under `!enabled`. So no block this widget raises could ever be
    // lifted, and §2.6's deliberate lack of a gate memo makes it re-assert on
    // every build — permanent, not transient. The whole page goes down with it
    // (its photos, its GPS, its other fields all become unsubmittable). Same
    // doctrine as `canPersist` above and product #17: fail open.
    //
    // Two reachable shapes this closes:
    //  * isEnabled:"FALSE" + digitsOptions set + no resolvable count -> a
    //    `forced` picker whose chips are inert (rev d introduced this one);
    //  * isEnabled:"FALSE" + a seeded backward reading + blockOnBackward:"TRUE"
    //    -> inert keys and boxes, so the blocking number cannot be corrected
    //    (pre-existing since rev b).
    // `|| serialBlock` — the serial gate is the SECOND blocking path in the
    // system (product #21 owned the first). serialBlock already carries its own
    // `&& enabled`, so this OR keeps the "one place where `block` is consumed"
    // structure the comment above describes and does not open a fifth
    // gate-the-officer-cannot-clear shape.
    _scheduleGate((block && enabled) || serialBlock);

    // ── token values (spec §3.1, CLOSED list) ──
    final Map<String, String> tokens = <String, String>{
      if (value != null) 'value': digitPadFmt(value),
      if (prev != null) 'prev': digitPadFmt(prev),
      if (value != null && prev != null) 'delta': digitPadFmt(value - prev),
      if (avg != null) 'avg': digitPadFmt(avg),
      'n': holes.toString(),
      // §11: {serial} shows the serial that is RECORDED on the doc, never what
      // OCR read off the photo. Omitted when blank so the pending-safe dialect
      // leaves it literal instead of printing "()".
      if (serialRaw.isNotEmpty) 'serial': serialRaw,
      // 'ocr' is RETIRED by meter-serial-verify §3.2, not merely unbuilt: with
      // §3.1's substring rule there is no single "OCR value" to display. It was
      // removed from _digitPadToken too, so {ocr} stays literal either way.
    };

    // Segments 8-14 are OPTIONAL (§3.1 "segmen kosong = fitur itu diam"), so
    // none of them gets a default — each is guarded by .isNotEmpty at its
    // render site. NOTE SduiSpec.text() is a LENGTH guard only, not blank-aware;
    // that is exactly the semantics wanted here.
    final String title = _spec.text(0);
    final String hint = _spec.text(1);
    final String incomplete = _spec.text(7);
    final String footer = _spec.text(5);
    final String pickerLink = _spec.text(10);

    String verdictText = '';
    Color verdictFg = _saneFg;
    Color verdictBg = _saneBg;
    IconData verdictIcon = Icons.check_circle_outline;
    switch (verdict) {
      case DigitPadVerdict.sane:
        verdictText = _spec.text(2);
        break;
      case DigitPadVerdict.spike:
        verdictText = _spec.text(3);
        verdictFg = _spikeFg;
        verdictBg = _spikeBg;
        verdictIcon = Icons.warning_amber_outlined;
        break;
      case DigitPadVerdict.backward:
        verdictText = _spec.text(4);
        verdictFg = _backFg;
        verdictBg = _backBg;
        verdictIcon = Icons.error_outline;
        break;
      case DigitPadVerdict.none:
        break;
    }

    // ── staged for the post-frame seam (spec §2.2 rules 1-2, §4c rules 1-3) ──
    // Writing another slot's controller.text notifies its listeners, and
    // pushing a modal route re-enters the navigator — both are
    // setState-during-build if done here. Same seam _scheduleGate uses.
    _wantBlack = black;
    _wantRed = hasBoxes ? layout.red : 0;
    _wantSource = hasBoxes
        ? digitPadResolveSource(
            _slotValue(_digitsSourcePosition),
            fromDoc: fromDoc,
          )
        : '';
    // ★ The inline card banner and the bottom sheet are no longer the same
    // string. Spec §5 gives the serial verdict the sheet and NOTHING else
    // ("nol elemen baru ... numpang bottom sheet yang sudah ada"), so the
    // banner keeps rendering the NUMERIC verdict exactly as it did before this
    // feature existed — zero regression on §4b/§4c.
    final String bannerMessage = verdictText.isEmpty
        ? ''
        : digitPadFillTokens(verdictText, tokens);
    final String sheetText = serialOwns ? _spec.text(6) : verdictText;
    _sheetMessage = sheetText.isEmpty
        ? ''
        : digitPadFillTokens(sheetText, tokens);
    // Segment 6 borrows the spike palette: it is a warning, not a hard error.
    _sheetFg = serialOwns ? _spikeFg : verdictFg;
    _sheetBg = serialOwns ? _spikeBg : verdictBg;
    _sheetIcon = serialOwns ? Icons.warning_amber_outlined : verdictIcon;
    _sheetBlocked = verdictBlock;
    _wantSerial = serialRaw;
    _wantPhotoRaw = photoRaw;
    _wantOcrKey = ocrKey;
    _wantSheetKey = digitPadSheetKey(
      submitValue: submit,
      ocrKey: ocrKey,
      serialOwns: serialOwns,
    );
    _wantSheet = digitPadShouldRaiseAnySheet(
      verdict: verdict,
      submitValue: submit,
      sheetText: _sheetMessage,
      serialOwns: serialOwns,
      sheetKey: _wantSheetKey,
      alreadyRaisedFor: DigitPad._sheetRaised[widget.scrName]?[position],
    );
    _scheduleSide();

    return Padding(
      padding: pad,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            if (hint.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(hint, style: const TextStyle(fontSize: 12.5, color: _muted)),
            ],
            if (picker == DigitPadPickerState.link &&
                pickerLink.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              GestureDetector(
                key: const ValueKey<String>('digitPadPickerLink'),
                onTap: () => setState(() {
                  _pickerOpen = !_pickerOpen;
                }),
                child: Text(
                  pickerLink,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: _caret,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
            // ONE picker, one code path. `forced` shows it because there is no
            // config; _pickerOpen shows the SAME widget because the officer
            // asked for it — via the segment-10 link, or by having just tapped
            // a chip (§2.2 rule 3).
            //
            // ★ _pickerOpen is ORed, NOT ANDed with `link`, and that is
            // load-bearing: the FIRST black pick resolves the count, which
            // flips picker from `forced` to `hidden` on the very next build. If
            // the picker vanished there, the officer could never reach the RED
            // row — acceptance §11 "Setelah memilih 5+2" would be unreachable
            // in `auto` mode. _pickBlack/_pickRed therefore latch _pickerOpen
            // true, and the picker stays on screen (also letting a mis-tap be
            // corrected, which matters when a wrong count is a 10x-100x billing
            // error). In `editable` mode the link toggles it back off; after a
            // forced pick it stays until navigation, by design.
            if (picker == DigitPadPickerState.forced ||
                _pickerOpen) ...<Widget>[
              const SizedBox(height: 10),
              _picker(position, enabled),
            ],
            if (hasBoxes) ...<Widget>[
              const SizedBox(height: 12),
              _boxes(buffer, enabled, position, layout),
              if (holes > 0 &&
                  holes < layout.total &&
                  incomplete.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  digitPadFillTokens(incomplete, tokens),
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
              ],
              const SizedBox(height: 12),
              _numpad(buffer, enabled, position),
            ],
            // The "baris ringkas" of §4b/§4c. For sane it is the whole feature
            // (the sheet never rises). For spike/backward it is what survives a
            // dismissed sheet, and tapping it re-opens the sheet (§4c rule 3).
            if (verdictText.isNotEmpty)
              _banner(
                bannerMessage,
                verdictFg,
                verdictBg,
                verdictIcon,
                onTap:
                    (verdict == DigitPadVerdict.spike ||
                        verdict == DigitPadVerdict.backward)
                    ? () => _openSheet(position)
                    : null,
              ),
            if (verdictBlock && footer.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                digitPadFillTokens(footer, tokens),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _backFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  /// N dark boxes, a VISIBLE comma, then M red boxes (spec §2.1).
  ///
  /// The comma is the only thing on screen that tells the officer where the m³
  /// boundary sits, and getting that boundary wrong is the number-one risk in
  /// the whole feature (§2.1: every unit in a site fails in the SAME direction,
  /// so nothing looks wrong). It is a structural glyph, not copy — the one
  /// character in this widget that does not come from a `text` segment, exactly
  /// like the digits themselves.
  ///
  /// [i] stays the GLOBAL buffer index in the box ValueKey, so
  /// 'digitPadBox-<i>' addresses the same box before and after the split.
  Widget _boxes(
    String buffer,
    bool enabled,
    int position,
    DigitPadLayout layout,
  ) {
    final int n = buffer.length;
    if (n == 0) return const SizedBox.shrink();
    final int black = layout.black > n ? n : layout.black;
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        const double gap = 6;
        const double commaW = 14;
        final double avail = cons.maxWidth.isFinite ? cons.maxWidth : 320;
        // A Wrap of k children has k-1 gaps. k is n (+1 for the comma), so the
        // reservation is gap*(n-1), plus commaW+gap when the comma is drawn.
        final double reserved =
            gap * (n - 1) + (layout.hasComma ? commaW + gap : 0);
        double w = (avail - reserved) / n;
        if (w > 52) w = 52;
        if (w < 22) w = 22;
        final double h = w * 1.35;
        final int caret = _cursor >= n ? n - 1 : _cursor;
        final List<Widget> kids = <Widget>[];
        for (int i = 0; i < n; i++) {
          if (i == black && layout.hasComma) {
            kids.add(
              SizedBox(
                key: const ValueKey<String>('digitPadComma'),
                width: commaW,
                height: h,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    ',',
                    style: TextStyle(
                      fontSize: w * 0.8,
                      fontWeight: FontWeight.w700,
                      color: enabled ? _ink : _muted,
                    ),
                  ),
                ),
              ),
            );
          }
          final String ch = buffer[i];
          final bool filled = ch != digitPadHole;
          final bool isRed = i >= black;
          kids.add(
            GestureDetector(
              // Stable key so a test can address a BOX unambiguously. Without
              // it a filled box and a numpad key are both
              // `Container > ... > Text('0')`, and a text-based finder resolves
              // to whichever comes first in tree order — the box.
              //
              // Element identity across a box-count change is harmless here: the
              // buffer lives in controller.text, not in element state, so
              // Flutter rebuilding or discarding a box element loses nothing.
              key: ValueKey<String>('digitPadBox-$i'),
              onTap: enabled
                  ? () => _apply(digitPadTapBox(buffer, i), position)
                  : null,
              child: Container(
                width: w,
                height: h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled ? (isRed ? _boxRedOn : _boxOn) : _boxOff,
                  borderRadius: BorderRadius.circular(6),
                  // Border.all + borderRadius. A ONE-SIDED Border(left: ...)
                  // together with borderRadius is an assertion failure in
                  // Flutter — do not "improve" this into a left rail.
                  border: Border.all(
                    color: (enabled && i == caret)
                        ? _caret
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Text(
                  filled ? ch : '',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: w * 0.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }
        return Wrap(spacing: gap, runSpacing: gap, children: kids);
      },
    );
  }

  /// §2.2 rule 3: a fixed set of sensible counts, NOT a free dropdown and NOT a
  /// numeric input. The thing being prevented is an implausible number.
  ///
  /// ONE picker widget for both entry points — `forced` (no config) and the
  /// segment-10 link in `editable` mode both render this.
  Widget _picker(int position, bool enabled) {
    final String warn = _spec.text(11);
    final String blackLabel = _spec.text(8);
    final String redLabel = _spec.text(9);
    final int? currentBlack = digitPadResolveCount(
      slotValue: _slotValue(_digitsPosition),
      docValue: null,
    );
    final int? currentRed = int.tryParse(
      digitPadNormalizeSeed(_slotValue(_digitsRedPosition)).trim(),
    );

    Widget chip(String keyId, int value, bool selected, VoidCallback? onTap) =>
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('digitPadOpt$keyId'),
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _chipOnBg : _chipOffBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _keyBorder),
              ),
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : _ink,
                ),
              ),
            ),
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (warn.isNotEmpty) ...<Widget>[
            Text(
              warn,
              style: const TextStyle(
                fontSize: 12.5,
                color: _warnFg,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (blackLabel.isNotEmpty) ...<Widget>[
            Text(
              blackLabel,
              style: const TextStyle(fontSize: 12.5, color: _ink),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int v in _blackOptions)
                chip(
                  'Black-$v',
                  v,
                  currentBlack == v,
                  enabled ? () => _pickBlack(v, position) : null,
                ),
            ],
          ),
          // ★ The red-row guard is not belt-and-braces. _pickRed
          // routes through the same _writeSlot, which refuses a null position —
          // so without this the red chips would render, absorb taps, do
          // nothing, and never highlight (currentRed can never match). Silent
          // dead UI is the worst possible outcome in a widget whose whole
          // premise is that a wrong digit count is invisible. Red simply falls
          // to 0 instead, which is a complete, correct configuration.
          // `!= _position` for the same reason: _writeSlot also refuses our own
          // slot, which holds the reading rather than a count.
          if (_redOptions.isNotEmpty &&
              _digitsRedPosition != null &&
              _digitsRedPosition != _position) ...<Widget>[
            const SizedBox(height: 12),
            if (redLabel.isNotEmpty) ...<Widget>[
              Text(
                redLabel,
                style: const TextStyle(fontSize: 12.5, color: _ink),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int v in _redOptions)
                  chip(
                    'Red-$v',
                    v,
                    currentRed == v,
                    enabled ? () => _pickRed(v, position) : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// §2.2 rules 1, 2 and 4 in one tap.
  ///
  /// ★ `_pickerOpen = true` is not cosmetic. This very pick resolves the count,
  /// so digitPadPickerState flips from `forced` to `hidden` on the next build —
  /// and if the picker disappeared there, the RED row would be unreachable and
  /// acceptance §11 "Setelah memilih 5+2" could never be satisfied in `auto`
  /// mode. It also lets a mis-tap be corrected, which matters when a wrong
  /// count is a 10x-100x billing error (§2.1). Assigned before _clearBuffer,
  /// whose setState publishes both.
  void _pickBlack(int value, int position) {
    _writeSlot(_digitsPosition, value.toString());
    _markPickedByField();
    _pickerOpen = true;
    _clearBuffer(position);
  }

  void _pickRed(int value, int position) {
    _writeSlot(_digitsRedPosition, value.toString());
    _markPickedByField();
    _pickerOpen = true;
    _clearBuffer(position);
  }

  /// ★ Writes `field` DIRECTLY, bypassing digitPadResolveSource's latch.
  ///
  /// The latch protects an already-recorded provenance from MACHINE overwrites
  /// (a doc landing late). An officer tapping a chip is an explicit HUMAN
  /// override, and it is precisely the case the office must review: in
  /// `editable` mode the slot already holds `config`, and without this write it
  /// would keep saying `config` after the officer changed the count — hiding the
  /// one row that needs a second pair of eyes (§2.2 rule 2).
  void _markPickedByField() {
    _writeSlot(_digitsSourcePosition, digitPadSourceField);
  }

  /// §2.2 rule 4 / §4c rule 4: the buffer is EMPTIED, never right-truncated.
  /// A truncated number still looks like a valid number, and that is exactly the
  /// failure this widget exists to prevent.
  ///
  /// Writing '' (rather than a fresh hole string) means the NEXT build's
  /// digitPadNormalizeBuffer pads to whatever the new box count turns out to be
  /// — no need to predict it here.
  void _clearBuffer(int position) {
    try {
      final InputController ic = txfController[widget.scrName]![position]!;
      ic.controller.text = '';
      ic.finalData = '';
    } catch (e) {
      devPrint('DigitPad clear: $e');
    }
    if (!mounted) return;
    setState(() {
      _cursor = 0;
    });
  }

  Widget _numpad(String buffer, bool enabled, int position) {
    // [id] becomes ValueKey('digitPadKey-$id') on the InkWell — the actual tap
    // target, and the only way a test can address a KEY rather than a digit BOX
    // showing the same character. The backspace key is icon-only and has no Text
    // at all, so without a key it is unaddressable.
    Widget padKey(
      String id,
      String label,
      VoidCallback? onTap, {
      IconData? icon,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: _keyBg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey<String>('digitPadKey-$id'),
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _keyBorder),
              ),
              child: icon != null
                  ? Icon(icon, size: 20, color: enabled ? _ink : _muted)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: enabled ? _ink : _muted,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );

    Widget digitKey(String d) => padKey(
      d,
      d,
      enabled
          ? () => _apply(digitPadPressDigit(buffer, _cursor, d), position)
          : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(children: <Widget>[digitKey('1'), digitKey('2'), digitKey('3')]),
        Row(children: <Widget>[digitKey('4'), digitKey('5'), digitKey('6')]),
        Row(children: <Widget>[digitKey('7'), digitKey('8'), digitKey('9')]),
        Row(
          children: <Widget>[
            const Expanded(child: SizedBox()),
            digitKey('0'),
            padKey(
              'back',
              '',
              enabled
                  ? () => _apply(
                      digitPadPressBackspace(buffer, _cursor),
                      position,
                    )
                  : null,
              icon: Icons.backspace_outlined,
            ),
          ],
        ),
      ],
    );
  }

  /// The "baris ringkas" of §4b/§4c.
  ///
  /// For `sane` it IS the whole feature — the sheet never rises and [onTap] is
  /// null (interview decision 2; an existing test pins segment 2's literal
  /// text here). For `spike`/`backward` it is what survives a dismissed sheet,
  /// and tapping it re-opens the sheet (§4c rule 3).
  Widget _banner(
    String message,
    Color fg,
    Color bg,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final Widget body = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: fg, height: 1.35),
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: fg),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(
      key: const ValueKey<String>('digitPadVerdictRow'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
    );
  }

  /// §4c. The sheet is MODAL, so the officer cannot retype while it is up — its
  /// content is a snapshot of the last build and cannot go stale under him.
  ///
  /// ★ Closes through the BUILDER's [ctx], never this State's `context`. A
  /// captured-context pop is a documented fatal in this repo (Null check
  /// operator used on a null value, _InkResponseState.handleTap). Precedent:
  /// list_action_card.dart's _showNoteSheet.
  void _openSheet(int position) {
    final String message = _sheetMessage;
    if (message.isEmpty) return;
    final String fixLabel = _spec.text(12);
    final String acceptLabel = _spec.text(13);
    final String foot = _spec.text(14);
    final String blockedFoot = _spec.text(5);
    final bool blocked = _sheetBlocked;
    final Color fg = _sheetFg;
    final Color bg = _sheetBg;
    final IconData icon = _sheetIcon;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fg.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(fontSize: 14, color: fg, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            if (fixLabel.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const ValueKey<String>('digitPadSheetFix'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // Clearing makes `submit` empty, which drops the raise
                    // latch — so the NEXT complete value earns a fresh sheet.
                    _clearBuffer(position);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    fixLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
            // §4c rule 5 — the ONE place the officer does not win. Keyed on
            // `blocked` (backward AND blockOnBackward), NOT on blockOnBackward
            // alone: a spike under blockOnBackward:"TRUE" is not blocked, so
            // hiding the acknowledge button there would be wrong.
            if (!blocked && acceptLabel.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const ValueKey<String>('digitPadSheetAccept'),
                  // Closes the sheet and NOTHING else. Spec §3/§5 define no
                  // slot for the "ditandai untuk ditinjau kantor" mark, so
                  // there is deliberately no output wire here — see the spec
                  // gap in docs/widgets/digit_pad.md.
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: _keyBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    acceptLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            if (blocked && blockedFoot.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                blockedFoot,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _backFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (foot.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(foot, style: const TextStyle(fontSize: 12, color: _muted)),
            ],
          ],
        ),
      ),
    );
  }
}
