import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../model/general_get_controller.dart';
import '../model/input_controller.dart';
import '../model/otq_state.dart';
import 'do_chain.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_EVENT_SUBMIT -- pre-resolving submit button for P7 and P8.
///
/// Replaces the plain RBT for custody outcome pages because `saveSend` does
/// NOT resolve `{curly}` tokens (`{vehicleId}`, `{today}`, `{cnm}`,
/// `{driverVid}`, `{driverName}`). This widget pre-resolves them before
/// calling `saveSend`.
///
/// **P7 mode (ungated):** always enabled. updateEventRow only.
/// **P8 mode (gated):** disabled until note >= 10 chars AND photo attached.
///   updateEventRow + addToEvent.
///
/// Mode is auto-detected: if `gateNotePosition` is set in component JSON,
/// the widget operates in gated mode (P8); otherwise ungated (P7).
///
/// ## Reactivity (SINGLE COMMITTED APPROACH)
///
/// Note: `StatefulWidget.setState` driven by a `TextEditingController` listener
/// attached in `initState` via `addPostFrameCallback` (deferred because
/// `txfController` entries are populated during page build, not before).
///
/// Photo: `GetBuilder<GeneralGetXController>(id: photoWidgetId)` tagged to the
/// photo position. `OtqGetImages2` calls `GeneralGetXController.to.redraw()`
/// on add (otq_get_images_2:105-107) and `deleteWidgetAt` on delete (:409),
/// both of which call `update([getWidgetId(scrName, position)])`, rebuilding
/// only the GetBuilder with the matching `id`.
///
/// NO Obx, NO periodic timer, NO Rx mutation during build.
///
/// Component JSON fields:
///   `table`             -- vehicle_check path (for checkDoc / cnm read)
///   `search`            -- opening doc search
///   `updateEventRow`    -- DSL string with curly tokens
///   `addToEvent`        -- DSL string with curly tokens (P8 only)
///   `route`             -- navigation target after submit
///   `text`              -- diamond-separated label slots:
///                          [0] enabled label, [1] disabled label, [2] disabled hint
///   `gateNotePosition`  -- txf position of note widget (int, P8 only)
///   `gatePhotoPosition` -- get_images position of photo widget (int, P8 only)
///   `minNoteLength`     -- min note char count (default 10, P8 only)
///   `cnmField`          -- field name for custody event name (default `cnm`)
///   `vidtable`          -- explicit appVid override
///   `com`               -- tenant container
///   `chain`             -- optional; when present, shown via doChain after
///                          submit instead of direct route navigation. Typically
///                          a DO_DIALOG confirmation. The chain's own RBT
///                          handles final navigation (routeStack.push + gotoRoute).
class CustodyEventSubmit extends StatefulWidget {
  const CustodyEventSubmit({
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

  /// Per-scrName writing-in-progress flag.
  static final Map<String, bool> _writing = {};

  /// Clear state for a screen. Called from buildPage.
  static void clearState(String scrName) {
    _writing.remove(scrName);
  }

  @override
  State<CustodyEventSubmit> createState() => _CustodyEventSubmitState();
}

class _CustodyEventSubmitState extends State<CustodyEventSubmit> {
  String _checkCode = '';
  List<String> _textArray = [];

  // Gate positions (null = ungated = P7 mode).
  int? _notePos;
  int? _photoPos;
  int _minNoteLength = 10;

  // Listener cleanup
  VoidCallback? _noteListener;
  InputController? _noteController;

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
    _parseGate();
    // Deferred: attach note listener after txfController is populated.
    // txfController entries are created by buildDisplayComponent during page
    // construction; the note widget's position may not exist yet at this point.
    if (_notePos != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attachNoteListener();
      });
    }
  }

  @override
  void dispose() {
    _detachNoteListener();
    super.dispose();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Text slots:
  ///  [0] enabled label  (e.g. "Lapor Selesai" / "Kirim Laporan Selisih")
  ///  [1] disabled label (e.g. "Kirim Laporan Selisih")
  ///  [2] disabled hint  (e.g. "isi alasan min 10 + foto dulu")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }
  }

  void _parseGate() {
    final dynamic np = widget.component['gateNotePosition'];
    final dynamic pp = widget.component['gatePhotoPosition'];
    if (np != null) {
      _notePos = np is int ? np : int.tryParse(np.toString());
    }
    if (pp != null) {
      _photoPos = pp is int ? pp : int.tryParse(pp.toString());
    }
    final dynamic ml = widget.component['minNoteLength'];
    if (ml != null) {
      _minNoteLength = ml is int ? ml : (int.tryParse(ml.toString()) ?? 10);
    }
  }

  /// Attach a listener to the note field's TextEditingController.
  ///
  /// Called from a post-frame callback (txfController entries are not
  /// guaranteed to exist at initState time). The listener calls setState
  /// on every text change so the gate predicate re-evaluates.
  void _attachNoteListener() {
    if (!mounted || _notePos == null) return;
    try {
      txfControllerCheck(widget.scrName, _notePos!);
      _noteController = txfController[widget.scrName]?[_notePos!];
      if (_noteController != null) {
        _noteListener = () {
          if (mounted) setState(() {});
        };
        _noteController!.controller.addListener(_noteListener!);
      }
    } catch (_) {
      // txfController not ready yet; gate stays disabled until next rebuild.
    }
  }

  void _detachNoteListener() {
    if (_noteListener != null && _noteController != null) {
      try {
        _noteController!.controller.removeListener(_noteListener!);
      } catch (_) {}
    }
    _noteListener = null;
    _noteController = null;
  }

  /// Find the opening doc from the widget's own vehicle_check subscription.
  ///
  /// This is the SAME pattern used by CustodyConfirmedList and
  /// CustodyDiscrepancyList. CustodyEventSubmit subscribes independently
  /// so it can read `checkDoc['cnm']` for the `{cnm}` token at submit time,
  /// without relying on another widget's subscription being active.
  Map<String, dynamic>? _findCheckDoc() {
    if (_checkCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_checkCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      docs,
      rawSearch,
      widget.scrName,
    );
    return matched.isNotEmpty ? matched.first : null;
  }

  /// Evaluate the gate: note >= minLength AND photo attached.
  /// Returns true if ungated (P7) or if both conditions met (P8).
  bool _evaluateGate() {
    if (_notePos == null && _photoPos == null) return true; // ungated

    bool noteOk = _notePos == null; // if no note gate, pass
    bool photoOk = _photoPos == null; // if no photo gate, pass

    if (_notePos != null) {
      try {
        txfControllerCheck(widget.scrName, _notePos!);
        final InputController c = txfController[widget.scrName]![_notePos!]!;
        final String text = c.finalData == emptyString
            ? c.controller.text
            : c.finalData;
        noteOk = text.trim().length >= _minNoteLength;
      } catch (_) {}
    }

    if (_photoPos != null) {
      try {
        txfControllerCheck(widget.scrName, _photoPos!);
        final InputController c = txfController[widget.scrName]![_photoPos!]!;
        final String data = c.finalData;
        photoOk = data != emptyString && data.isNotEmpty;
      } catch (_) {}
    }

    return noteOk && photoOk;
  }

  /// Resolve custody-specific curly tokens in a DSL string.
  ///
  /// Delegates to [resolveDriverCurlyTokens] for shared tokens
  /// ({vehicleId}, {today}, {driverVid}, {driverName}, {activeTaskVid}, {tnm}),
  /// then resolves the widget-local {cnm} from the checkDoc.
  String _resolveCustodyTokens(String raw, String cnm) {
    if (!raw.contains('{')) return raw;

    // 1. Delegate shared tokens to the canonical resolver.
    String result = resolveDriverCurlyTokens(raw, widget.scrName);

    // 2. Resolve {cnm} locally (widget-specific; requires checkDoc access).
    if (result.contains('{cnm}')) {
      result = result.replaceAll('{cnm}', cnm.isNotEmpty ? cnm : '{cnm}');
    }

    return result;
  }

  Future<void> _onTap(BuildContext context) async {
    if (CustodyEventSubmit._writing[widget.scrName] == true) return;

    CustodyEventSubmit._writing[widget.scrName] = true;
    setState(() {}); // show spinner

    try {
      // 1. Read cnm from checkDoc (own vehicle_check subscription)
      final Map<String, dynamic>? checkDoc = _findCheckDoc();
      final String cnmField = (widget.component['cnmField'] ?? 'cnm')
          .toString();
      final String cnm = (checkDoc?[cnmField] ?? '').toString().trim();

      // 2. Deep-copy component and pre-resolve curly tokens
      final Map<String, dynamic> resolved = Map<String, dynamic>.from(
        widget.component as Map,
      );

      final String rawUER = (resolved['updateEventRow'] ?? '').toString();
      if (rawUER.isNotEmpty) {
        resolved['updateEventRow'] = _resolveCustodyTokens(rawUER, cnm);
      }

      final String rawATE = (resolved['addToEvent'] ?? '').toString();
      if (rawATE.isNotEmpty) {
        resolved['addToEvent'] = _resolveCustodyTokens(rawATE, cnm);
      }

      // 3. Timestamp + locString via getLocationString helper (api.dart:727).
      //    Construct a minimal OtqState with the submit timestamp and default
      //    no-GPS values (latitude/longitude = invalidLocation,
      //    locationStatus = "No Gps", isoCountryCode = "88").
      //    Using the canonical helper guarantees the 15-diamond-slot format
      //    matches what saveSend/historySync parsers expect.
      final int timeStamp = await getRealTime();
      final OtqState locSensor = OtqState();
      locSensor.nowTime = DateTime.fromMillisecondsSinceEpoch(timeStamp);
      final String locString = getLocationString('', '', '', locSensor);

      // 4. Call saveSend with resolved component
      saveSend(timeStamp, widget.scrName, resolved, locString, defaultVid());

      // 5. Navigate (chain-aware)
      final dynamic chain = widget.component['chain'];
      if (chain != null && chain.toString().trim().isNotEmpty) {
        // Chain present: show DO_DIALOG (or bottom sheet) instead of
        // direct navigation. The chain's own RBT handles final route nav.
        if (context.mounted) {
          await doChain(context, widget.scrName, chain);
        }
      } else {
        // No chain: direct navigation (P7/P8 existing behavior).
        final String rawRoute = (widget.component['route'] ?? '')
            .toString()
            .trim();
        final String route = stripRouteWrapper(rawRoute);
        if (route.isNotEmpty && routeExist(route)) {
          routeStack.push(route);
          gotoRoute(route);
        }
      }
    } catch (e) {
      errorReport(e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengirim: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      CustodyEventSubmit._writing[widget.scrName] = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // In gated mode (P8), wrap the button in a GetBuilder tagged to the
    // photo position so it rebuilds when OtqGetImages2 adds/removes a photo.
    // OtqGetImages2 calls GeneralGetXController.to.redraw(scrName, position)
    // on add (otq_get_images_2:105-107) and deleteWidgetAt on delete (:409),
    // both of which call update([getWidgetId(scrName, position)]).
    //
    // In ungated mode (P7), return the button directly (no photo gate).
    if (_photoPos != null) {
      final String photoWidgetId = GeneralGetXController.to.getWidgetId(
        widget.scrName,
        _photoPos!,
      );
      return GetBuilder<GeneralGetXController>(
        id: photoWidgetId,
        builder: (_) => _buildButton(context),
      );
    }
    return _buildButton(context);
  }

  Widget _buildButton(BuildContext context) {
    final bool isWriting = CustodyEventSubmit._writing[widget.scrName] ?? false;
    final bool gateOk = _evaluateGate();
    final bool enabled = gateOk && !isWriting;

    // Labels
    final String enabledLabel = _t(0, 'Lapor Selesai');
    final String disabledLabel = _t(1, _t(0, 'Lapor Selesai'));
    final String disabledHint = _t(2, '');

    final String label = enabled ? enabledLabel : disabledLabel;

    // Colors: ungated (P7) = indigo; gated enabled (P8) = amber;
    // disabled = gray.
    final bool isGated = _notePos != null || _photoPos != null;
    final Color bgEnabled = isGated
        ? const Color(0xFFF59E0B) // amber-500
        : const Color(0xFF4338CA); // indigo-700
    final Color bgColor = enabled
        ? bgEnabled
        : const Color(0xFFD1D5DB); // gray-300
    final Color textColor = enabled
        ? Colors.white
        : const Color(0xFF6B7280); // gray-500

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: enabled ? () => _onTap(context) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: bgColor,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                foregroundColor: textColor,
                disabledForegroundColor: const Color(0xFF6B7280),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isWriting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          // Disabled hint text below button (P8 gated mode only)
          if (!enabled && disabledHint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                disabledHint,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF), // gray-400
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
