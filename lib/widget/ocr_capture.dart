// lib/widget/ocr_capture.dart
//
// SDUI component `ocr_capture` -- photograph a document/meter, run Google ML Kit
// Latin text recognition ON-DEVICE, and write the recognised values into OTHER
// form positions listed in `ocrTargets`. This widget's own `position` holds the
// PHOTO URL, so existing `addToTable` patterns (`i◼◁4▷`) keep working unchanged.
//
// Variants:
//   auto -- the machine picks one value from inside the guide box; the agent
//           confirms by editing the target field. Never auto-submits.
//   tap  -- the agent taps TextElements on the captured photo; each tap fills
//           the active chip's target and auto-advances.
//
// Design decisions, all deliberate:
//  * The CAMERA is the repo's existing PhotoCamera via acquireCamera. Three
//    documented fatal classes live in that file; a second camera screen would
//    re-inherit all of them.
//  * READ FIRST, SHRINK AFTER. ML Kit gets the original-resolution capture; the
//    imageParameter-sized copy is produced afterwards for upload, so agent quota
//    and Storage cost are unchanged (spec 6).
//  * The decode/crop/resize run in compute(). Flutter 3.44 merged the UI thread
//    into main, so heavy pure-Dart work on the main isolate is an ANR.
//  * Failure is NEVER an error: no dialog, no retry button. Field left empty,
//    text[3] shown, photo STILL uploads, form still submittable.
//  * ZERO hardcoded user-visible Indonesian: every string comes from `text`
//    ◆-segments; every fallback is either "render nothing" or a ◁pos▷ marker.

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // SchedulerPhase
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart';
import '../global2.dart';
import '../model/input_controller.dart';
import '../screen_session.dart';
import '../sdui_spec.dart';
import 'digit_pad_support.dart'; // digitPadSerialState -- ONE serial rule
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs
import 'ocr_capture_support.dart';
import 'panel_card_support.dart'; // TablePath, parseTablePath
import 'photo_camera.dart';

/// Flatten a ML Kit result to plain [OcrElement]s.
///
/// Lives HERE and not in ocr_capture_support.dart on purpose: that file is
/// imported by photo_camera.dart (for ocrGuideRect), which is the capture path
/// for EVERY page in the app. Keeping the only ML-Kit-typed function on this
/// side means an ML Kit resolution failure breaks OCR alone, never the camera
/// app-wide.
///
/// NO DECISION LIVES HERE -- a dumb mapper, and the one function in this feature
/// a unit test cannot reach (constructing ML Kit types in a test would couple
/// the suite to plugin-internal constructors for zero coverage).
///
/// Granularity is TextElement (word level), per spec 6.1.2.
List<OcrElement> ocrFlattenElements(RecognizedText recognized) {
  final List<OcrElement> out = <OcrElement>[];
  for (final TextBlock block in recognized.blocks) {
    for (final TextLine line in block.lines) {
      for (final TextElement element in line.elements) {
        final Rect r = element.boundingBox;
        out.add((
          text: element.text,
          box: <double>[r.left, r.top, r.right, r.bottom],
        ));
      }
    }
  }
  return out;
}

/// [value] unless it is one of the repo's two "there is no image" sentinels, in
/// which case `''`.
///
/// ★ `.isEmpty` ALONE IS NOT A CANCEL TEST. `acquireCamera` returns
/// `emptyString` (`'--'`, global.dart:213) on EVERY cancel exit --
/// photo_camera.dart:742 seeds `[emptyString]`, :762 returns it, and the accept
/// button at :697 is the ONLY writer of a real path -- and `'--'.isEmpty` is
/// FALSE. `prepareImageAsLocal` turns that same `'--'` into `emptyImageUrl`
/// (`'aum__--__mua'`, global.dart:228), the canonical no-image value every other
/// image consumer in the repo already guards (otq_get_images_2.dart:102,
/// timeline.dart:1015, attendance_qr_selfie_gps_verify.dart:805).
///
/// ONE helper for every path/URL emptiness test in this file so the sites cannot
/// drift apart (code-review-r2 C-1 + W-6). Returns [value] UNTRIMMED: the trim
/// is for the comparison only, a real path is never rewritten.
String _usablePath(String value) {
  final String v = value.trim();
  return (v.isEmpty || v == emptyString || v == emptyImageUrl) ? '' : value;
}

/// One position's capture state. Plain mutable data -- the store is a PLAIN Map
/// (see OcrCapture.resetRev for why it must not be reactive).
class OcrCaptureEntry {
  /// `aum__<path>__mua` written to this widget's own position.
  String photoUrl = '';

  /// ML Kit returned nothing, or nothing matched. A RENDER flag only.
  bool failed = false;

  /// Everything ML Kit saw, for the `raw` meta column.
  String rawSummary = '';

  /// targetPosition -> the exact controller text WE wrote. The edit-watch
  /// compares against this so our own write never trips it.
  final Map<int, String> written = <int, String>{};

  /// One-shot: the agent has edited an OCR-written field.
  bool edited = false;

  /// The serial the LAST capture read for the compared target ('' when it read
  /// nothing for it, or when the compare is not configured).
  ///
  /// Parked here and not in a static, so clearState/clearAll wipe it with the
  /// rest of the capture state on navigation. It exists for ONE reason: with
  /// `blockOnMismatch:"TRUE"` the value never reaches the slot, and `{value}`
  /// in the warning still has to name what the photo actually said.
  String compareRead = '';
}

class OcrCapture extends StatefulWidget {
  const OcrCapture({
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

  /// Per-screen, per-position capture state.
  ///
  /// Outer key scrName so ScreenSession can drop a whole screen; inner key
  /// position so two OCR_CAPTUREs on ONE screen never collide. STATIC, not on
  /// the State: an AnyPage in-place reconciliation can reuse a State, so State
  /// lifetime is not a reset guarantee -- ScreenSession.navReset is.
  static final Map<String, Map<int, OcrCaptureEntry>> _store =
      <String, Map<int, OcrCaptureEntry>>{};

  /// Repaint signal. The store above stays a PLAIN Map (mutated during build
  /// via putIfAbsent); only this counter is reactive, so a reset can never
  /// notify mid-build. Mirrors GroupPicker.resetRev.
  static final RxInt resetRev = 0.obs;

  /// ★★★ NavPolicy.all is REQUIRED -- do NOT "simplify" it to `screen`.
  ///
  /// Navigation is gotoRoute -> reloadPage (global.dart:1530-1532), which
  /// returns the CACHED linkElement[scrName] and schedules clearData POST-frame,
  /// i.e. AFTER the re-entered page has already painted. With NavPolicy.screen
  /// only the ENTERING screen's slice is dropped, so leaving screen A never
  /// clears A and A's crop + chips are still in the store when A's build() reads
  /// them on the next visit -- the PREVIOUS capture's values, live and tappable,
  /// writing straight into record slots. NavPolicy.all wipes the whole store on
  /// the nav AWAY, off-screen, before the next visit's first paint.
  ///
  /// SignaturePad's NavPolicy.screen precedent does NOT transfer: its store
  /// holds a filename consumed by submit, not content that is RENDERED. Only
  /// rendered state can paint stale. Copy GroupPicker (group_picker.dart:66-109).
  ///
  /// RebuildPolicy.none: a background readSettings page rebuild must NOT throw
  /// away a capture the agent is still working with.
  static void registerScreenSession() {
    ScreenSession.ensure(
      'OcrCapture.store',
      OcrCapture.clearState,
      nav: NavPolicy.all,
      clearAllFn: OcrCapture.clearAll,
      rebuild: RebuildPolicy.none,
    );
  }

  /// Drop one screen's capture state.
  static void clearState(String scrName) {
    _store.remove(scrName);
    resetRev.value++;
  }

  /// Wipe EVERY screen's capture state. This is what clearData calls.
  static void clearAll() {
    _store.clear();
    resetRev.value++;
  }

  /// The entry for [scrName]/[position], creating it if needed.
  static OcrCaptureEntry entryOf(String scrName, int position) => _store
      .putIfAbsent(scrName, () => <int, OcrCaptureEntry>{})
      .putIfAbsent(position, () => OcrCaptureEntry());

  /// The entry for [scrName]/[position] WITHOUT creating one. Used by build()
  /// so a paint never mutates the store.
  static OcrCaptureEntry? peek(String scrName, int position) =>
      _store[scrName]?[position];

  @override
  State<OcrCapture> createState() => OcrCaptureState();
}

/// PUBLIC (the `FtzAutoNumberState` precedent) so a widget test can reach
/// [applyCaptureResult]: the camera and ML Kit are both unreachable under
/// flutter_test, so that method is the only seam the capture branch can be
/// driven through.
class OcrCaptureState extends State<OcrCapture> {
  static const Color _ink = Color(0xFF1E293B);
  static const Color _muted = Color(0xFF94A3B8);
  static const Color _accent = Color(0xFF3B82F6);
  static const Color _danger = Color(0xFFDC2626);

  /// Banner ink. NOT _danger: measured 4.41:1 on the _dangerBg tint below,
  /// which fails WCAG AA for 12sp body text. This one measures 5.91:1.
  static const Color _dangerInk = Color(0xFFB91C1C);
  static const Color _dangerBg = Color(0xFFFEF2F2);
  static const Color _dangerBorder = Color(0xFFFECACA);

  /// D5's check. green-700, 4.61:1 on the chip's blue-50 fill (green-600 is
  /// 3.03:1 -- over the 3:1 non-text bar, but with no margin).
  static const Color _okInk = Color(0xFF15803D);

  late final SduiSpec _spec;
  late final int? _position;
  late final String _variant;
  late final List<int> _targets;
  late final List<String> _patterns;
  late final List<String> _types;
  late final List<int> _metaTargets;
  late final double? _guide;
  late final int _maxSide;
  late final String _source;
  late final String _folder;
  late final String _fileBase;
  late final int _uploadMaxSize;
  late final int _uploadQuality;
  late final double _previewSize;
  late final String _lens;

  /// Doc field carrying the reference serial (`msn` on a meter). BLANK = the
  /// whole compare is off: no subscription, no fetch, nothing rendered, and the
  /// values written exactly as before.
  ///
  /// Read with NO SduiSpec default on purpose. `str(key, def)` returns `def`
  /// for an absent key, a blank cell AND a whitespace-only cell alike, so a
  /// DEFAULTED key can never be blank and every `.isEmpty` guard on it would be
  /// dead code that is always false.
  late final String _compareField;

  /// `TRUE` = a mismatching read is not handed to the compared target.
  late final bool _blockOnMismatch;

  final Map<int, VoidCallback> _listeners = <int, VoidCallback>{};
  bool _busy = false;
  double _h = 0;
  double _w = 0;

  /// Drop this widget's OWN position from a target list.
  ///
  /// Slot [_position] holds the PHOTO URL. Anything else written there replaces
  /// the evidence with a string `displayImage` reads as a network url -- a
  /// broken preview on screen, and no photo at all in the submitted record. Not
  /// hypothetical: `_attachEditWatch` fires `_setMeta('ocr_edit', null)` on the
  /// first manual correction, so a `metaTargets` pointing here writes the four
  /// characters `ocr_edit` over the url.
  ///
  /// Filtering at PARSE time covers every write site at once -- `_setMeta`, the
  /// `fills.forEach` loop, the withheld-target clear and `_compareTarget` all
  /// draw their positions from these two lists and nowhere else.
  ///
  /// Cost, on an already-misconfigured sheet only: `_targets` shrinks, so the
  /// chip labels (`text[5 + i]`) and the compare banner (`text[5 + n]` /
  /// `text[6 + n]`) shift down one slot. Those come out of the `text` ◆-list,
  /// which is addressed by ABSOLUTE slot number and cannot be renumbered from
  /// here. The per-target `ocrPattern` / `ocrType` do NOT shift: they are
  /// addressed by ordinal, and [_alignToTargets] drops the same ordinals from
  /// both, so every surviving target keeps the pattern and the type the sheet
  /// declared for it. Losing the evidence photo is worse than a label shift.
  List<int> _dropOwnPosition(List<int> raw, String key) {
    final int? own = _position;
    if (own == null || !raw.contains(own)) return raw;
    // Dead SDUI config fails SILENTLY here -- no crash, no analyzer finding.
    // Name what was dropped or nobody can diagnose it.
    devPrint(
      'OCR_CAPTURE: $key drops own position $own '
      '(that slot holds the photo url)',
    );
    return raw.where((int p) => p != own).toList();
  }

  /// Re-index a per-target config list -- `ocrPattern` or `ocrType` -- the same
  /// way [_dropOwnPosition] just re-indexed [raw]. Both are addressed by the
  /// ORDINAL of the target inside `ocrTargets`: auto reads index 0
  /// (`ocrPickAuto`), the tap screen reads `_active` (`_tapElement`). A dropped
  /// target must therefore take its pattern and its type with it, or
  /// `ocrTargets:'4,7'` + `ocrPattern:'A◆B'` + `ocrType:'text◆number'` validates
  /// the surviving slot 7 with `A` and writes it as `text`. Nothing throws --
  /// [ocrPatternAt] and [ocrTypeAt] are both length-guarded -- the value just
  /// silently lands in the wrong shape.
  ///
  /// [cfg] is routinely SHORTER than [raw] on a lean sheet. An ordinal past its
  /// end is simply not carried over, so the result never grows and those two
  /// accessors keep answering their own default for it -- exactly what they
  /// answered for that ordinal before the drop.
  ///
  /// NO diagnostic here: [_dropOwnPosition] already logged the drop, and the
  /// own-position fixtures assert that log as an exact ONE-element list.
  List<String> _alignToTargets(List<int> raw, List<String> cfg) {
    final int? own = _position;
    if (own == null || !raw.contains(own)) return cfg;
    final List<String> out = <String>[];
    for (int i = 0; i < raw.length; i++) {
      if (raw[i] != own && i < cfg.length) out.add(cfg[i]);
    }
    return out;
  }

  /// The SINGLE SOURCE OF TRUTH for per-target validation config: the `ocrType`
  /// and the compiled `ocrPattern` applied to the i-th SURVIVING target.
  ///
  /// The auto path below calls this -- do NOT "simplify" it back to two inline
  /// `ocrTypeAt(_types, 0)` / `ocrPatternAt(_patterns, 0)` calls. The tests can
  /// only reach this expression (the auto path itself sits behind the camera
  /// and ML Kit), so an inline copy there would be a SECOND expression that can
  /// drift away from the pinned one with the suite still green.
  ///
  /// `OcrTapScreen` deliberately does not use it: that widget is handed
  /// `_patterns` / `_types` wholesale and indexes them by its own `_active`
  /// chip, which [_alignToTargets] already keeps aligned.
  ({String type, RegExp? pattern}) validationForTarget(int i) =>
      (type: ocrTypeAt(_types, i), pattern: ocrPatternAt(_patterns, i));

  @override
  void initState() {
    super.initState();
    OcrCapture.registerScreenSession();
    _spec = SduiSpec(widget.component);
    // int.tryParse, NOT getPosition(): getPosition does `inp!` and THROWS on a
    // missing position (global2.dart:448-451).
    _position = int.tryParse((widget.component['position'] ?? '').toString());
    _variant = _spec.str('variant', 'auto').toLowerCase() == 'tap'
        ? 'tap'
        : 'auto';
    final List<int> rawTargets = ocrParsePositions(_spec.str('ocrTargets'));
    _targets = _dropOwnPosition(rawTargets, 'ocrTargets');
    // Same ordinals out of all three lists, or the surviving target is checked
    // against the dropped one's pattern and normalised as its type.
    _patterns = _alignToTargets(rawTargets, _spec.list('ocrPattern'));
    _types = _alignToTargets(rawTargets, _spec.list('ocrType'));
    _metaTargets = _dropOwnPosition(
      ocrParsePositions(_spec.str('metaTargets')),
      'metaTargets',
    );
    _guide = ocrParseRatio(_spec.str('guide'));
    _maxSide = ocrMaxSideOf(_spec);
    _source = _spec.str('source').toLowerCase();
    _folder = _spec.str('folder', 'default');
    _fileBase = _spec.str('filename', 'file');
    final ({int maxSize, int quality}) ip = ocrImageParameter(_spec);
    _uploadMaxSize = ip.maxSize;
    _uploadQuality = ip.quality;
    _previewSize = _spec.intOr('previewSize', 120).toDouble();
    _lens = _spec.intOr('camera', 1) == 0 ? 'front' : 'back';
    // ── serial compare (ocr-serial-instant-check) ──
    _compareField = _spec.str('compareField');
    _blockOnMismatch = _spec.str('blockOnMismatch').toUpperCase() == 'TRUE';

    final int? position = _position;
    if (position != null) {
      // INSIDE the position guard: build() bails to the "position missing" text
      // without one, so a misconfigured component would otherwise open a
      // Firestore listener whose result it can never render (code-review-r1
      // I-6).
      _subscribe();
      txfControllerCheck(widget.scrName, position);
      // Show a server-supplied currentValue on first paint. buildDisplayComponent
      // seeds finalData/initialValue but never touches controller.text.
      final InputController ic = txfController[widget.scrName]![position]!;
      // Neither sentinel is a photo: a stored record whose capture was
      // cancelled carries emptyImageUrl, and seeding it here would write it to
      // finalData AND entry.photoUrl, painting a permanent bogus filled zone
      // (code-review-r2 W-6).
      final String seed = _usablePath(_spec.str('currentValue'));
      if (ic.controller.text.isEmpty && seed.isNotEmpty) {
        ic.controller.text = seed;
        ic.finalData = seed;
        OcrCapture.entryOf(widget.scrName, position).photoUrl = seed;
      }
    }
  }

  @override
  void dispose() {
    // ★ A leaked listener on a SHARED TextEditingController outlives this
    // widget and keeps flipping a meta column on a screen that no longer exists.
    _detachListeners();
    _detachCompareWatch();
    super.dispose();
  }

  // ── reference doc for the serial compare ────────────────────────────────
  //
  // Copied SHAPE, never the RULE, from digit_pad.dart: parseTablePath FIRST and
  // resolveAppVid SECOND. resolveAppVid falls through to getTableVid, which
  // reads the `late` global appCodeController and throws
  // LateInitializationError outside globalInit -- short-circuiting on an empty
  // docId keeps a table-less component (and every widget test) away from it.
  //
  // FAIL OPEN throughout: no doc -> no verdict -> no warning, never an error
  // and never a blocked field. That is the RATIFIED product decision (spec 10
  // "Not Doing": digitPad stays the hard gate, the officer always wins), not an
  // oversight -- do not "fix" it into a fail-closed gate.

  /// mapTableContent key; '' when the compare is not configured.
  String _code = '';

  void _subscribe() {
    // Zero-config regression (acceptance 11 line 1): with no compareField this
    // widget must not subscribe, must not fetch and must render nothing new.
    if (_compareField.isEmpty) return;
    try {
      final TablePath tp = parseTablePath(_spec.str('table'));
      if (tp.tableDocId.isEmpty) return;
      final String appVid = resolveAppVid(widget.component);
      if (appVid.isEmpty) return;
      // vid-scoped: mapTableContent keys omit the vid, so another tenant's same
      // docId/subColl would dedup our stream away.
      _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
    } catch (e) {
      devPrint('OCR_CAPTURE subscribe: $e');
      _code = '';
    }
  }

  /// The reference docs. Called from _content, i.e. INSIDE the Obx -- that read
  /// is what makes a late-landing snapshot repaint this card without a second
  /// capture (D3).
  List<Map<String, dynamic>> _docs() {
    // Not configured: read NOTHING. Deliberately unlike digit_pad, which reads
    // mapTableContent[''] -- a key its own tests seed.
    if (_code.isEmpty) return const <Map<String, dynamic>>[];
    // mapTableContent is dynamic-sourced: build the typed list explicitly. A
    // `.map().toList()` off a dynamic infers List<dynamic> at runtime and fails
    // to assign.
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
      devPrint('OCR_CAPTURE search: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// D2: the compared value is the one written to `ocrTargets[0]`. There is NO
  /// separate config key for it -- the spec never named one, and inventing an
  /// operator-facing name is how a previous round shipped permanently dead
  /// config.
  int? get _compareTarget =>
      (_compareField.isEmpty || _targets.isEmpty) ? null : _targets[0];

  /// Whether this card can say WHY a serial was rejected: at least one of the
  /// two ◆-segments the banner renders is non-blank.
  ///
  /// The banner AND the withhold both hang off this ONE term, so they cannot
  /// drift apart. A block with nothing to render would empty the officer's
  /// serial field with no reason and no instruction: showCmp is false, the
  /// withheld target is deliberately absent from entry.written so the chip loop
  /// draws nothing for it either, and text[3] stays quiet because a fill DID
  /// exist. Blank segments therefore mean this whole line is OFF -- the same
  /// ratified "a blank segment renders nothing" reading every other text slot
  /// gets, and it loses no data (code-review-r1 C-1).
  bool get _cmpVoiced =>
      _spec.text(5 + _targets.length).trim().isNotEmpty ||
      _spec.text(6 + _targets.length).trim().isNotEmpty;

  /// The serial RECORDED on the reference doc. '' when the compare is off, when
  /// the snapshot has not landed yet, and when the unit has no alias (spec 4.5)
  /// -- all three then answer `off` through the ONE rule below, with no extra
  /// branch to keep in sync.
  String _recordedSerial() {
    if (_compareField.isEmpty) return '';
    final List<Map<String, dynamic>> docs = _docs();
    if (docs.isEmpty) return '';
    // Firestore values are dynamic and flip String/num per tenant: stringify,
    // never cast.
    //
    // Seed-normalised, unlike the digit_pad twin: digitPadSerialState runs
    // digitPadNormalizeSeed on its `read` side ONLY, so a doc field literally
    // holding the string "null" -- getInitialValue's seed for an absent value,
    // which has reached Firestore through a form slot before -- survives
    // digitPadNormalizeSerial as "NULL" and warns about a meter that simply has
    // no serial on file. The `?? ''` catches a Dart null and nothing else.
    // Fixing it once inside digitPadSerialState is the right shape, but
    // digit_pad is out of this plan's scope, so the two sides now disagree on
    // exactly that one input: this card goes silent, digitPad still reports a
    // mismatch (code-review-r1 W-1, owed as a separate ticket).
    return digitPadNormalizeSeed(
      (docs.first[_compareField] ?? '').toString().trim(),
    );
  }

  /// The live verdict for THIS build.
  ///
  /// DERIVED every build, never latched. That is what makes a manual correction
  /// re-compare live (spec 4.6) and what lets a doc that lands AFTER the photo
  /// surface the warning with no second capture (D3). A stored verdict would go
  /// stale in both directions.
  ///
  /// The comparison rule itself is digitPadSerialState -- the SAME function
  /// digitPad and the CF use. Spec 2 and 10: one rule, not a second one.
  ({DigitPadSerialState state, String read, String recorded}) _compareNow(
    OcrCaptureEntry? entry,
  ) {
    final int? target = _compareTarget;
    if (target == null) {
      return (state: DigitPadSerialState.off, read: '', recorded: '');
    }
    final String recorded = _recordedSerial();
    final String slot = txfController[widget.scrName]?[target]?.finalData ?? '';
    // The SLOT wins whenever it holds something -- the officer's own typing is
    // the truth, and a parked read must never outrank it. The park is the
    // fallback for exactly one situation: blockOnMismatch withheld the value,
    // so the slot is empty and `{value}` would have nothing to name.
    //
    // Emptiness runs through the repo's sentinel-aware pair: '', 'null' and
    // '--' all mean empty here and a bare .isEmpty catches only the first.
    final String read =
        digitPadNormalizeSerial(digitPadNormalizeSeed(slot)).isEmpty
        ? entry?.compareRead ?? ''
        : slot;
    return (
      state: digitPadSerialState(recorded: recorded, read: read),
      read: read,
      recorded: recorded,
    );
  }

  // ── the compared target is an INPUT slot once we have written it (4.6) ───
  //
  // Nothing else rebuilds this widget when a SIBLING slot's text changes:
  // ocrWriteToPosition and otq_txf_2 each repaint only their OWN
  // '$scrName-$pos' id, and our GetBuilder id is our own. Without this listener
  // the officer corrects the serial by hand and the warning never clears.
  //
  // This is NOT _attachEditWatch. That one is a ONE-SHOT provenance watch that
  // detaches itself after the first edit; this one has to survive every edit.
  // Two listeners on one controller is fine -- different callbacks, different
  // lifetimes. Do not merge them.

  /// The controller we are currently listening to, held by REFERENCE.
  ///
  /// ★ Held, never re-looked-up at detach time: buildPage(clear:true) re-mints
  /// txfController[scrName], so the map entry at dispose() time can be a
  /// DIFFERENT controller and the listener would survive on the old one.
  TextEditingController? _compareCtl;
  bool _compareDirty = false;
  bool _watchPending = false;

  /// Attach AFTER the frame: the compared component may sit anywhere in the
  /// page's `children`, so its InputController may not exist while we build.
  /// Called from _content, so we are always already inside a frame -- which is
  /// why addPostFrameCallback (which does NOT schedule one) is enough here.
  void _scheduleCompareWatch() {
    if (_watchPending || _compareTarget == null) return;
    _watchPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _watchPending = false;
      if (!mounted) return;
      _ensureCompareWatch();
    });
  }

  void _ensureCompareWatch() {
    final int? target = _compareTarget;
    if (target == null) return;
    final InputController? ic = txfController[widget.scrName]?[target];
    // Slot not minted yet: the next build's post-frame tries again. Do NOT
    // txfControllerCheck it into existence here -- buildDisplayComponent owns
    // the seeding of initialValue/isEnabled for that slot.
    if (ic == null) return;
    if (identical(_compareCtl, ic.controller)) return;
    _detachCompareWatch();
    _compareCtl = ic.controller;
    ic.controller.addListener(_onCompareChanged);
  }

  void _detachCompareWatch() {
    final TextEditingController? c = _compareCtl;
    _compareCtl = null;
    if (c == null) return;
    try {
      // removeListener is documented safe on an already-disposed ChangeNotifier
      // ("allowed to be called on disposed instances for usability reasons").
      c.removeListener(_onCompareChanged);
    } catch (e) {
      devPrint('OCR_CAPTURE compare watch detach: $e');
    }
  }

  /// The compared slot changed -- rebuild so _content re-derives the verdict.
  ///
  /// ★ Deferred ONLY during SchedulerPhase.persistentCallbacks: marking an
  /// already-built element dirty inside the build phase is a "setState() called
  /// during build" assertion. Every other phase is safe, and setState is what
  /// SCHEDULES the frame -- addPostFrameCallback only appends to a list, so
  /// deferring unconditionally would DROP the rebuild at idle, which is the
  /// normal case here (a keystroke callback).
  void _onCompareChanged() {
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_compareDirty) return;
      _compareDirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _compareDirty = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  // ── target writing ──────────────────────────────────────────────────────

  void _detachListeners() {
    _listeners.forEach((int pos, VoidCallback fn) {
      try {
        txfController[widget.scrName]?[pos]?.controller.removeListener(fn);
      } catch (_) {}
    });
    _listeners.clear();
  }

  void _attachEditWatch(OcrCaptureEntry entry) {
    _detachListeners();
    if (_metaTargets.isEmpty || entry.written.isEmpty) return;
    for (final int pos in entry.written.keys.toList()) {
      try {
        txfControllerCheck(widget.scrName, pos);
        final TextEditingController c =
            txfController[widget.scrName]![pos]!.controller;
        final String baseline = entry.written[pos] ?? '';
        void fn() {
          if (entry.edited) return;
          if (c.text == baseline) return; // our own write, or a revert
          entry.edited = true;
          _setMeta('ocr_edit', null);
          _detachListeners(); // one-shot
        }

        c.addListener(fn);
        _listeners[pos] = fn;
      } catch (e) {
        errorReport(e);
      }
    }
  }

  /// Write the meta columns (D6). [raw] null leaves the raw column untouched.
  void _setMeta(String src, String? raw) {
    if (_metaTargets.isEmpty) return;
    ocrWriteToPosition(
      widget.scrName,
      _metaTargets[0],
      display: src,
      finalData: src,
    );
    if (raw != null && _metaTargets.length > 1) {
      ocrWriteToPosition(
        widget.scrName,
        _metaTargets[1],
        display: raw,
        finalData: raw,
      );
    }
  }

  // ── acquisition ─────────────────────────────────────────────────────────

  Future<String> _pickFromGallery() async {
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Capped at ocrMaxSide, NOT imageParameter: ML Kit reads this file.
      maxWidth: _maxSide.toDouble(),
      maxHeight: _maxSide.toDouble(),
      imageQuality: ocrCaptureQuality,
    );
    return picked?.path ?? '';
  }

  Future<String> _pickFromCamera() async {
    final List<CameraDescription> cams = await ensureCams();
    if (cams.isEmpty) return '';
    // text[1] is the camera-screen hint and becomes the dialog title; fall back
    // to the widget label, then to nothing. No hardcoded string.
    final String hint = _spec.text(1).trim().isNotEmpty
        ? _spec.text(1)
        : _spec.text(0);
    return acquireCamera(
      cams,
      hint,
      _lens,
      _maxSide, // NOT imageParameter -- read first, shrink after (spec 6)
      ocrCaptureQuality,
      _h,
      _w,
      preset: ResolutionPreset.high,
      guideRatio: _variant == 'auto' ? _guide : null,
    );
  }

  /// `source:"both"` -- a two-ICON chooser, zero strings. `Get.back()` only:
  /// Get.dialog takes a WIDGET, so `context` inside it is this State's context
  /// and Navigator.of(context).pop() there is a stale-context fatal.
  Future<String> _chooseSource() async {
    String choice = '';
    await Get.dialog(
      AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.camera_alt_outlined, color: _accent),
              onPressed: () {
                choice = 'camera';
                Get.back();
              },
            ),
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.photo_library_outlined, color: _accent),
              onPressed: () {
                choice = 'gallery';
                Get.back();
              },
            ),
          ],
        ),
      ),
    );
    return choice;
  }

  Future<String> _acquireOriginal() async {
    if (_source == 'gallery') return _pickFromGallery();
    if (_source == 'both') {
      final String choice = await _chooseSource();
      if (choice == 'gallery') return _pickFromGallery();
      if (choice == 'camera') return _pickFromCamera();
      return ''; // dismissed
    }
    return _pickFromCamera();
  }

  // ── the capture flow ────────────────────────────────────────────────────

  /// Apply ONE capture result to the record: write every fill into its target
  /// slot, set the meta columns, and re-arm the edit-watch. Returns the entry so
  /// the caller can hang the thumbnail and the photo URL off it.
  ///
  /// ★ [_attachEditWatch] runs on BOTH branches, not only the success one. It
  /// begins with `_detachListeners()` and returns early when `written` is empty,
  /// so a capture that read NOTHING becomes "detach and stop". Attaching inside
  /// the `else` left the PREVIOUS capture's listener armed after a FAILED
  /// RETAKE: the agent's manual retype then tripped it and overwrote `manual`
  /// with `ocr_edit`, corrupting the very accuracy column spec 13 exists to
  /// build (code-review-r1 W-1).
  ///
  /// Public only for the test seam -- see [OcrCaptureState].
  @visibleForTesting
  OcrCaptureEntry applyCaptureResult(
    int position,
    Map<int, OcrFill> fills,
    String rawSummary,
  ) {
    final OcrCaptureEntry entry = OcrCapture.entryOf(widget.scrName, position);
    entry.written.clear();
    entry.edited = false;
    entry.rawSummary = rawSummary;

    // ── serial compare: the ONE point-in-time decision (D6) ──
    //
    // blockOnMismatch is honoured HERE and NOWHERE ELSE. It must never become
    // "keep the slot cleared while mismatched": that would wipe the officer's
    // manual correction on every rebuild and produce a gate nobody can clear --
    // a shape this codebase has already shipped three times. Once withheld, the
    // officer's typing always wins.
    final int? cmpTarget = _compareTarget;
    final OcrFill? cmpFill = cmpTarget == null ? null : fills[cmpTarget];
    // Parked even when nothing was withheld, and RESET to '' when this capture
    // read nothing for the compared target -- a stale park must not outlive the
    // photo that produced it.
    entry.compareRead = cmpFill?.display ?? '';
    // ★ Mirrors digitPad's serialSourceEnabled doctrine (digit_pad.dart): the
    // verdict still computes and the banner still WARNS, but a value is
    // withheld only when the officer can actually retype it. On an
    // isEnabled:"FALSE" compared target a withheld serial could never be
    // entered by the one action that clears the gate -- a brick, and the exact
    // shape this codebase has shipped three times (code-review-r1 W-2).
    // Map.[] takes Object?, so a null cmpTarget simply misses and answers
    // false -- no block, which is where fail-open already points.
    final bool cmpTargetEnabled =
        txfController[widget.scrName]?[cmpTarget]?.isEnabled ?? false;
    final bool withheld =
        cmpFill != null &&
        _blockOnMismatch &&
        // No banner configured, no block: see _cmpVoiced. A silent withhold is
        // indistinguishable from an OCR failure in the field.
        _cmpVoiced &&
        cmpTargetEnabled &&
        digitPadSerialState(
              recorded: _recordedSerial(),
              read: cmpFill.display,
            ) ==
            DigitPadSerialState.mismatch;

    fills.forEach((int pos, OcrFill f) {
      // D6: ONLY the compared target is held back. Every other ocrTargets entry
      // is written normally, and the photo still lands in this widget's own
      // position and still uploads -- withholding data nobody suspects only
      // makes the officer retype what was already right.
      if (withheld && pos == cmpTarget) return;
      ocrWriteToPosition(
        widget.scrName,
        pos,
        display: f.display,
        finalData: f.finalData,
      );
      entry.written[pos] = f.display;
    });
    if (withheld && cmpTarget != null) {
      // Spec 4.4, "field seri tetap kosong". Clearing is not cosmetic: a
      // PREVIOUS capture's matching serial left in the slot would outrank the
      // parked read in _compareNow and paint a green check over a photo of the
      // wrong meter.
      ocrWriteToPosition(widget.scrName, cmpTarget, display: '', finalData: '');
    }
    entry.failed = fills.isEmpty;

    if (fills.isEmpty) {
      _setMeta('manual', rawSummary);
    } else {
      _setMeta(
        'ocr',
        fills.values.map((OcrFill f) => f.raw).join(separator[4]),
      );
    }
    _attachEditWatch(entry);
    return entry;
  }

  /// Drive [_capture] with a path the plugins cannot produce under
  /// flutter_test: the camera and the gallery are BOTH plugin-backed, so this
  /// is the only way to exercise the cancel guard on a real `'--'` sentinel.
  ///
  /// Public only for the test seam -- see [OcrCaptureState].
  @visibleForTesting
  Future<void> captureForTest(String path) => _capture(pathOverride: path);

  /// [pathOverride] is the [captureForTest] seam and is ALWAYS null in
  /// production; the `onTap` tear-off still satisfies `void Function()` because
  /// the parameter is optional.
  Future<void> _capture({String? pathOverride}) async {
    final int? position = _position;
    if (position == null || _busy) return;
    setState(() => _busy = true);

    String rawPath = '';
    String cropPath = '';
    String shrunkPath = '';
    bool rawWasMoved = false;
    TextRecognizer? recognizer;

    try {
      rawPath = pathOverride ?? await _acquireOriginal();
      // ★ NOT `rawPath.isEmpty`: a cancelled camera returns '--', not ''
      // (see _usablePath). Letting it through ran the whole OCR pipeline on a
      // nonexistent file -- overwriting the previous capture's meta provenance
      // and depositing emptyImageUrl in the record slot (code-review-r2 C-1).
      if (_usablePath(rawPath).isEmpty) {
        return; // cancelled -- finally still cleans up
      }

      final Directory tmpDir = await getTemporaryDirectory();
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      // No OTQC artifact in these names: renamePath must NOT auto-move them.
      final String wantCrop = (_variant == 'auto' && _guide != null)
          ? '${tmpDir.path}/ocrcrop$stamp.jpg'
          : '';

      final OcrPrepResult prep = await compute(ocrPrepareSync, (
        imagePath: rawPath,
        cropPath: wantCrop,
        guideRatio: _variant == 'auto' ? _guide : null,
      ));
      cropPath = prep.cropPath;

      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognized = await recognizer.processImage(
        InputImage.fromFilePath(cropPath.isNotEmpty ? cropPath : rawPath),
      );
      final List<OcrElement> els = ocrFlattenElements(recognized);
      final String rawSummary = ocrRawSummary(els);

      final Map<int, OcrFill> fills = <int, OcrFill>{};
      if (_variant == 'tap') {
        if (_targets.isNotEmpty && els.isNotEmpty && prep.width > 0) {
          final OcrTapResult out = OcrTapResult();
          await Get.dialog(
            Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: Colors.black,
              child: OcrTapScreen(
                imagePath: rawPath,
                imageWidth: prep.width,
                imageHeight: prep.height,
                elements: els,
                targets: _targets,
                labels: ocrTargetLabels(_spec, _targets),
                patterns: _patterns,
                types: _types,
                hint: _spec.text(2),
                rejectMessage: _spec.text(3),
                components: <dynamic>[
                  for (final int p in _targets)
                    ocrSiblingComponent(widget.scrName, p),
                ],
                out: out,
              ),
            ),
            barrierDismissible: false,
          );
          fills.addAll(out.filled);
        }
      } else {
        if (_targets.isNotEmpty) {
          final int target = _targets[0]; // spec 3.2: auto uses index 0 only
          final ({String type, RegExp? pattern}) cfg = validationForTarget(0);
          final String type = cfg.type;
          final OcrFill? pick = ocrPickAuto(els, cfg.pattern, type);
          if (pick != null) {
            final ({String display, String finalData})? df = ocrDisplayAndFinal(
              pick.raw,
              type,
              ocrSiblingComponent(widget.scrName, target),
            );
            if (df != null) {
              fills[target] = (
                display: df.display,
                finalData: df.finalData,
                raw: pick.raw,
                box: pick.box,
              );
            }
          }
        }
      }

      // Write the values (D8: a retake OVERWRITES).
      final OcrCaptureEntry entry = applyCaptureResult(
        position,
        fills,
        rawSummary,
      );

      final String outPath = '${tmpDir.path}/ocrup$stamp.jpg';
      final OcrFinishResult fin = await compute(ocrFinishSync, (
        imagePath: rawPath,
        outPath: outPath,
        maxSize: _uploadMaxSize,
        quality: _uploadQuality,
        // D7 (revised): the form preview shows the WHOLE captured frame. The
        // guide box picks the VALUE, it never decides what the agent may see --
        // a crop preview hides whether the photo is even of the right meter.
        thumbBox: const <double>[],
      ));
      shrunkPath = fin.uploadPath;

      // Fail open: a failed shrink uploads the ORIGINAL rather than losing the
      // photo. Bigger, but the evidence survives.
      final String uploadSource = shrunkPath.isNotEmpty ? shrunkPath : rawPath;
      rawWasMoved = shrunkPath.isEmpty;
      final String fileName =
          '${_fileBase}_${const Uuid().v4().replaceAll('-', '').substring(2, 7)}';
      final String url = await prepareImageAsLocal(
        imagePath: uploadSource,
        folder: _folder,
        // forceRename: our temp file carries no OTQC artifact, so without this
        // renamePath leaves it in the OS cache and the aum__ history wedges.
        fileName: fileName,
        forceRename: true,
      );
      // Registers the imageMap entry; the Storage upload inside is
      // safeUnawaited -- this never awaits the network (offline-first).
      await saveImagePutInImageMap(url);

      entry.photoUrl = url;
      ocrWriteToPosition(
        widget.scrName,
        position,
        display: url,
        finalData: url,
      );
    } catch (e) {
      errorReport(e);
      final int? position2 = _position;
      if (position2 != null) {
        OcrCapture.entryOf(widget.scrName, position2).failed = true;
      }
    } finally {
      try {
        await recognizer?.close();
      } catch (e) {
        devPrint('OCR_CAPTURE: recognizer close failed: $e');
      }
      await _deleteQuietly(cropPath);
      if (!rawWasMoved) await _deleteQuietly(rawPath);
      if (shrunkPath.isNotEmpty) {
        // prepareImageAsLocal MOVED it; if the move fell back to a copy the
        // original may still be there.
        await _deleteQuietly(shrunkPath);
      }
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteQuietly(String path) async {
    // The finally runs on the cancel path too, where rawPath is the '--'
    // sentinel -- never a file to stat (sentinel sweep, code-review-r2 C-1).
    if (_usablePath(path).isEmpty) return;
    try {
      final File f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      devPrint('OCR_CAPTURE: temp delete failed: $e');
    }
  }

  /// D8: `×` removes the PHOTO only. The human-approved numbers stay; src flips
  /// to `manual` because the photo that justified them is gone.
  void _deletePhoto() {
    final int? position = _position;
    if (position == null) return;
    final OcrCaptureEntry entry = OcrCapture.entryOf(widget.scrName, position);
    entry.photoUrl = '';
    entry.failed = false;
    // The parked read is the PHOTO's number: with the photo gone the banner must
    // not keep naming it. entry.written stays (D8 -- the human-approved numbers
    // survive the photo), so this only silences the case where the compared slot
    // is empty and the park was the last thing left to compare (code-review-r1
    // I-4).
    entry.compareRead = '';
    _detachListeners();
    _setMeta('manual', null);
    ocrWriteToPosition(widget.scrName, position, display: '', finalData: '');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _h = MediaQuery.of(context).size.height;
    _w = MediaQuery.of(context).size.width;
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

    // GetBuilder: clearData(thisScreen) repaints us AFTER ScreenSession.navReset
    // has cleared the store (api.dart:4638 then :4681, id = '$scrName-$pos').
    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$position',
      builder: (_) => Obx(() {
        // Obx: clearData(SOME OTHER screen) also runs clearAll() and wipes our
        // slice, but sends US no update -- without this read the crop would stay
        // painted and tappable over a store that no longer holds it.
        // Hoisted to the FIRST statement: an Obx that registers ZERO observables
        // is a documented fatal in this repo.
        // ignore: unused_local_variable
        final int rev = OcrCapture.resetRev.value;
        return _content(pad, position);
      }),
    );
  }

  Widget _content(EdgeInsets pad, int position) {
    txfControllerCheck(widget.scrName, position);
    final InputController ic = txfController[widget.scrName]![position]!;

    // Normalise the "null" seed HERE, not in initState:
    // build_display_component.dart:93 re-assigns initialValue on EVERY rebuild
    // and the Firestore proxy rebuilds every screen on any UI push, so an
    // initState-only fix is overwritten and then restored by the next clearData.
    // Idempotent. The '--' sentinel is left alone (api.dart:4827 needs it).
    ic.finalData = ocrNormalizeSeed(ic.finalData);
    ic.initialValue = ocrNormalizeSeed(ic.initialValue);

    final bool enabled = ic.isEnabled;
    final OcrCaptureEntry? entry = OcrCapture.peek(widget.scrName, position);
    final String label = _spec.text(0);
    final String failMsg = _spec.text(3);
    final String badge = _spec.text(4);
    // The store is the PRESENTATION layer; the RECORD SLOT is the truth.
    // clearAll() wipes the store on ANY clearData (NavPolicy.all) while
    // clearData then restores the slot from initialValue (api.dart:4646-4647),
    // so a store-only read paints the "+ add photo" empty zone over a slot that
    // still holds -- and still SUBMITS -- the old URL, with no × to clear it
    // (code-review-r1 W-3). Thumbnail BYTES legitimately stay store-only.
    // BOTH sentinels are filtered on BOTH reads: '--' deliberately survives
    // ocrNormalizeSeed above (api.dart:4827 needs it) and emptyImageUrl is what
    // a degraded prepareImageAsLocal writes to slot AND store together, so
    // either one would otherwise paint a filled zone over no photo at all
    // (code-review-r2 W-6).
    final String storeUrl = _usablePath(entry?.photoUrl ?? '');
    final String slotUrl = _usablePath(ic.finalData);
    final String photoUrl = storeUrl.isNotEmpty ? storeUrl : slotUrl;
    final bool hasPhoto = photoUrl.isNotEmpty;

    // ── serial compare (ocr-serial-instant-check) ──
    // Derived here on EVERY build, never latched. Cheap: one map read plus two
    // string normalisations, and a no-op when _compareField is blank.
    _scheduleCompareWatch();
    final ({DigitPadSerialState state, String read, String recorded}) cmp =
        _compareNow(entry);
    final bool cmpOk = cmp.state == DigitPadSerialState.ok;
    // D4: ONLY `mismatch` warns here. A capture that read nothing already shows
    // text[3]; a second red line saying the same thing teaches officers to
    // dismiss both. `missing` stays digitPad's business (its segment 16), which
    // is the spec's own "dua lapis".
    final bool cmpMismatch = cmp.state == DigitPadSerialState.mismatch;
    // D1: anchored to the TARGET COUNT, so these can never collide with the
    // open-ended chip-label region (text[5..5+n-1], ocrTargetLabels). With one
    // target that is text[6] and text[7], exactly the spec's example. Both are
    // blank-tolerant: SduiSpec.text is a length guard, and a blank segment
    // renders nothing at all -- zero hardcoded Indonesian.
    final String cmpMessage = cmpMismatch
        ? ocrFillCompareTokens(
            _spec.text(5 + _targets.length),
            <String, String>{'value': cmp.read, 'expected': cmp.recorded},
          )
        : '';
    final String cmpHint = cmpMismatch ? _spec.text(6 + _targets.length) : '';
    // ONE term, two consumers (see _cmpVoiced): cmpMessage is the token-filled
    // form of the SAME segment, so this is byte-for-byte the gate the withhold
    // now applies at capture time.
    final bool showCmp = cmpMismatch && _cmpVoiced;
    // D5's tick belongs to the value the PHOTO produced. After a manual
    // correction the chip still shows what OCR read, and a tick there would
    // claim the photo agreed with the record when the agreement is the
    // officer's own typing. Baseline is the one _attachEditWatch already uses:
    // controller.text against the exact string we wrote.
    final int? cmpTarget = _compareTarget;
    final bool cmpTick =
        cmpOk &&
        cmpTarget != null &&
        entry != null &&
        entry.written.containsKey(cmpTarget) &&
        (txfController[widget.scrName]?[cmpTarget]?.controller.text ?? '') ==
            entry.written[cmpTarget];

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
            if (label.trim().isNotEmpty) ...<Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.document_scanner_outlined,
                    size: 16,
                    color: _ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (!hasPhoto)
              _emptyZone(enabled)
            else
              _filledZone(photoUrl, enabled),
            if ((entry?.failed ?? false) &&
                failMsg.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                failMsg,
                style: const TextStyle(fontSize: 12, color: _danger),
              ),
            ],
            if (showCmp) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: _dangerBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _dangerBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: _dangerInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (cmpMessage.trim().isNotEmpty)
                            Text(
                              cmpMessage,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _dangerInk,
                              ),
                            ),
                          if (cmpHint.trim().isNotEmpty) ...<Widget>[
                            if (cmpMessage.trim().isNotEmpty)
                              const SizedBox(height: 4),
                            Text(
                              cmpHint,
                              style: const TextStyle(fontSize: 12, color: _ink),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if ((entry?.written.isNotEmpty ?? false)) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (int i = 0; i < _targets.length; i++)
                    if (entry!.written.containsKey(_targets[i]))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        // D5: `ok` is a small check on the chip that already
                        // exists -- no new widget, no new string, no new
                        // ◆-slot. Flexible, not a bare Text: a Row lays a
                        // non-flex child out with UNBOUNDED width, so a long
                        // chip label that used to soft-wrap would overflow.
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (cmpTick &&
                                _targets[i] == cmpTarget) ...<Widget>[
                              const Icon(Icons.check, size: 12, color: _okInk),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                badge.trim().isEmpty
                                    ? '${ocrTargetLabels(_spec, _targets)[i]}: ${entry.written[_targets[i]]}'
                                    : '$badge · ${ocrTargetLabels(_spec, _targets)[i]}: ${entry.written[_targets[i]]}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyZone(bool enabled) {
    return GestureDetector(
      onTap: (enabled && !_busy) ? _capture : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _source == 'gallery'
                      ? Icons.photo_library_outlined
                      : Icons.add_a_photo_outlined,
                  size: 30,
                  color: enabled ? _accent : _muted,
                ),
        ),
      ),
    );
  }

  /// [photoUrl] is supplied by the caller, NOT read off the store entry: the
  /// entry is null whenever the store was wiped while the record slot still
  /// holds the URL (W-3).
  ///
  /// BoxFit.contain, never cover: the whole photographed page must be visible
  /// so the agent can tell WHICH document was shot. The value still comes from
  /// the guide box -- that is a read decision, not a display one.
  Widget _filledZone(String photoUrl, bool enabled) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Tapping the preview = RETAKE (D8): re-runs OCR and OVERWRITES.
        Expanded(
          child: GestureDetector(
            onTap: (enabled && !_busy) ? _capture : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: _previewSize,
                width: double.infinity,
                // Letterbox ground: a contained photo does not fill the strip,
                // and white-on-white would hide the photo's edges.
                color: const Color(0xFFF1F5F9),
                child: _busy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : displayImage(
                        imageUrl: photoUrl,
                        cached: true,
                        fit: BoxFit.contain,
                      ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: null,
          onPressed: (enabled && !_busy) ? _deletePhoto : null,
          icon: Icon(Icons.cancel_outlined, color: enabled ? _danger : _muted),
        ),
      ],
    );
  }
}

/// Mutable out-parameter for [OcrTapScreen] -- the same holder idiom
/// `acquireCamera` uses (photo_camera.dart:704), so the caller never has to
/// reason about a nullable Get.dialog result type.
class OcrTapResult {
  final Map<int, OcrFill> filled = <int, OcrFill>{};
}

/// The `tap` screen (spec 4c): the captured photo with every TextElement drawn
/// as a tappable box, plus one chip per target.
///
/// D9: EVERY element stays tappable. `ocrPattern` validates ON TAP -- a rejected
/// tap keeps the chip active, does not advance, and shows text[3]. Elements are
/// NEVER dimmed or disabled: spec 4d forbids stranding the agent.
class OcrTapScreen extends StatefulWidget {
  const OcrTapScreen({
    super.key,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.elements,
    required this.targets,
    required this.labels,
    required this.patterns,
    required this.types,
    required this.hint,
    required this.rejectMessage,
    required this.components,
    required this.out,
  });

  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final List<OcrElement> elements;
  final List<int> targets;
  final List<String> labels;
  final List<String> patterns;
  final List<String> types;
  final String hint;
  final String rejectMessage;
  final List<dynamic> components;
  final OcrTapResult out;

  @override
  State<OcrTapScreen> createState() => _OcrTapScreenState();
}

class _OcrTapScreenState extends State<OcrTapScreen> {
  int _active = 0;

  int _nextEmpty(int from) {
    final int n = widget.targets.length;
    if (n == 0) return from;
    for (int k = 1; k <= n; k++) {
      final int idx = (from + k) % n;
      if (!widget.out.filled.containsKey(widget.targets[idx])) return idx;
    }
    return from;
  }

  void _reject() {
    final String msg = widget.rejectMessage;
    if (msg.trim().isEmpty) return; // config says nothing -> say nothing
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _tapElement(OcrElement e) {
    final int i = _active;
    if (i < 0 || i >= widget.targets.length) return;
    final String type = ocrTypeAt(widget.types, i);
    final String? norm = ocrNormalizeValue(e.text, type);
    final RegExp? rx = ocrPatternAt(widget.patterns, i);
    if (norm == null || norm.isEmpty || !ocrAccepts(rx, e.text, norm)) {
      _reject();
      return; // chip stays active, no auto-advance (D9)
    }
    final ({String display, String finalData})? df = ocrDisplayAndFinal(
      e.text,
      type,
      widget.components.length > i ? widget.components[i] : null,
    );
    if (df == null) {
      _reject();
      return;
    }
    setState(() {
      widget.out.filled[widget.targets[i]] = (
        display: df.display,
        finalData: df.finalData,
        raw: e.text,
        box: e.box,
      );
      _active = _nextEmpty(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (widget.hint.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Text(
                  widget.hint,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext ctx, BoxConstraints c) {
                  final double dispW = c.maxWidth;
                  final double scale = widget.imageWidth > 0
                      ? dispW / widget.imageWidth
                      : 1.0;
                  final double dispH = widget.imageHeight * scale;
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 6,
                    child: Center(
                      child: SizedBox(
                        width: dispW,
                        height: dispH,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.fill,
                                // No errorBuilder = FATAL on any load failure.
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Colors.black),
                              ),
                            ),
                            for (final OcrElement e in widget.elements)
                              if (ocrBoxOk(e.box))
                                Positioned(
                                  left: e.box[0] * scale,
                                  top: e.box[1] * scale,
                                  width: (e.box[2] - e.box[0]) * scale,
                                  height: (e.box[3] - e.box[1]) * scale,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _tapElement(e),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0x223B82F6),
                                        border: Border.all(
                                          color: const Color(0xCC3B82F6),
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          for (int i = 0; i < widget.targets.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => setState(() => _active = i),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i == _active
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      if (widget.out.filled.containsKey(
                                        widget.targets[i],
                                      )) ...<Widget>[
                                        const Icon(
                                          Icons.check,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        widget.labels.length > i
                                            ? widget.labels[i]
                                            : '◁${widget.targets[i]}▷',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    // Cancel: drop every fill, then close.
                    onPressed: () {
                      widget.out.filled.clear();
                      Get.back();
                    },
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: Color(0xFFDC2626),
                      size: 30,
                    ),
                  ),
                  IconButton(
                    // Done -- allowed even with empty chips (spec 4c): the rest
                    // is typed manually in the form.
                    onPressed: () => Get.back(),
                    icon: const Icon(
                      Icons.check_circle,
                      color: Color(0xFF22C55E),
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
