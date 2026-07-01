import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // saveSend, getRealTime, getLocationString, getNowMillisecondFromEpoch, defaultVid
import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // transactionStore (dynamic), mapTableContent, devPrint
import '../model/otq_state.dart'; // OtqState
import 'custody_count_list.dart';
import 'do_chain.dart';
import 'driver_home_support.dart';
import 'executor_designate_card.dart';
import 'panel_card_support.dart'; // parseTablePath, TablePath

/// CUSTODY_COUNT_SUBMIT -- send-button shared by P6 CustodyCount and O1
/// WarehouseOpeningCheck. Reads [CustodyCountList.countStore] (Obx via the
/// [CustodyCountList.countRev] signal).
///
/// ## P6 mode (default, `mode != 'opening'`)
///
/// Replaces the plain RBT for P6. Behavior is BYTE-IDENTICAL to the original
/// CustodyCountSubmit (before the O1 additive gate):
/// - Show "HITUNG SEMUA ITEM (n/N)" when any rendered item has count == 0.
/// - Show "LIHAT CATATAN WAREHOUSE ->" (indigo) when ALL items > 0.
/// - On tap: build `ip[]` -> native write via [writeNativeFields] -> nav to
///   custodyReveal.
///
/// ## O1 mode (`mode == 'opening'`)
///
/// Creates the opening vehicle_check doc + `ie[]` in ONE native Firestore set
/// (via [createNativeDocAutoId], offline-safe), then designates the chosen driver
/// (`dv`/`dn` on stock_location) via `updateEventRow` + `saveSend` (history
/// queue; updates an EXISTING row, no ordering dependency). Enable gate:
/// a driver must be chosen on the ExecutorDesignateCard (#CHOSEN_DRIVER_VID
/// non-empty). The submit Obx-reads [ExecutorDesignateCard.chosenRev] so the
/// gate updates live when the driver is picked.
///
/// Converted to StatefulWidget so the O1 variant can subscribe to the
/// workforce collection (to resolve `{checkerName}` locally). The P6 path does
/// NOT subscribe (`_subscribeO1` early-returns when mode != 'opening').
class CustodyCountSubmit extends StatefulWidget {
  const CustodyCountSubmit({
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

  /// Per-scrName writing-in-progress flag to prevent double taps.
  static final Map<String, bool> _writing = {};

  @override
  State<CustodyCountSubmit> createState() => _CustodyCountSubmitState();
}

class _CustodyCountSubmitState extends State<CustodyCountSubmit> {
  String _workforceCode = ''; // O1: workforce subscription code
  List<String> _textArray = [];

  bool get _isOpening =>
      (widget.component['mode'] ?? '').toString().trim() == 'opening';

  bool get _isClosing =>
      (widget.component['mode'] ?? '').toString().trim() == 'closing';

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribeWorkforce();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (O1):
  ///  [0] enabled label    (e.g. "Simpan Pengecekan")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  /// Subscribe to the workforce collection to resolve the checker's name.
  /// O1 + C1 only: early-returns when mode is neither 'opening' nor 'closing'
  /// (no spurious P6 sub).
  void _subscribeWorkforce() {
    if (!_isOpening && !_isClosing) return;
    final String rawTable =
        (widget.component['workforceTable'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final String appVid = resolveAppVid(widget.component);
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      _workforceCode = '${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
          appVid, tp.tableDocId, tp.subColl, _workforceCode);
    }
  }

  /// Resolve the logged-in checker's name from workforce where VID == #VID.
  /// Returns empty string if not found (degrade-safe: gn will be empty).
  String _resolveCheckerName() {
    if (_workforceCode.isEmpty) return '';
    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String checkerVid = (screenTx['#VID'] ?? '').toString().trim();
    if (checkerVid.isEmpty) return '';
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(
            mapTableContent[_workforceCode] ?? const []);
    final String vidField =
        (widget.component['vidField'] ?? 'VID').toString().trim();
    final String nameField =
        (widget.component['nameField'] ?? 'n').toString().trim();
    for (final Map<String, dynamic> doc in docs) {
      final String vid = (doc[vidField] ?? '').toString().trim();
      if (vid == checkerVid) {
        return (doc[nameField] ?? '').toString().trim();
      }
    }
    return '';
  }

  /// Generate the deterministic opening doc id: CHK-{vehicleId}-{yyyyMMdd(WIB)}.
  String _generateCnm(String vehicleId) {
    const int wibOffsetMs = 25200000; // UTC+7
    final int nowMs = getNowMillisecondFromEpoch();
    final DateTime wibNow =
        DateTime.fromMillisecondsSinceEpoch(nowMs + wibOffsetMs, isUtc: true);
    final String dateStr =
        '${wibNow.year}${wibNow.month.toString().padLeft(2, '0')}${wibNow.day.toString().padLeft(2, '0')}';
    return 'CHK-$vehicleId-$dateStr';
  }

  /// Resolve the vehicle id for warehouse opening/closing doc writes (O1/C1).
  ///
  /// O1/C1 have NO vehicleId publisher: the warehouse vehicle's `dv` is empty,
  /// so the driver publishers' `lt==vehicle && dv==driverVid` seed never matches
  /// it. H1 hands the vehicle off via `#ACTIVE_VEHICLE` (vehicle_feed_list writes
  /// `lv` on card tap) -- the SAME source the O1/C1 list widgets resolve through
  /// `{activeVehicle}`. Prefer a per-screen published vehicleId when present
  /// (driver-session reuse / forward-compat), else fall back to the H1 hand-off
  /// so the doc `vv` AND the deterministic `cnm` (`CHK-{vv}-{date}`) are non-empty.
  ///
  /// Without this the opening doc wrote `vv:""` + `cnm:"CHK--{date}"`, which H1's
  /// openingGate (`vv◼{lv}`) could not match -> vehicle stuck in `loading`.
  String _resolveWarehouseVehicleId(Map<String, dynamic> screenTx) {
    final String published =
        getDriverHomeState(widget.scrName).vehicleId.value.trim();
    if (published.isNotEmpty) return published;
    return (screenTx['#ACTIVE_VEHICLE'] ?? '').toString().trim();
  }

  /// Resolve O1 curly tokens in a DSL string. Delegates shared tokens to
  /// [resolveDriverCurlyTokens] ({chosenVid}, {chosenName}, {warehouseId},
  /// {checkerVid}, {vehicleId}, {today}, {now}, ...), then resolves the
  /// widget-local {checkerName} and {genCnm}.
  String _resolveO1Tokens(String raw, String checkerName, String genCnm) {
    if (!raw.contains('{')) return raw;
    String result = resolveDriverCurlyTokens(raw, widget.scrName);
    if (result.contains('{checkerName}')) {
      result = result.replaceAll(
          '{checkerName}', checkerName.isNotEmpty ? checkerName : '{checkerName}');
    }
    if (result.contains('{genCnm}')) {
      result = result.replaceAll(
          '{genCnm}', genCnm.isNotEmpty ? genCnm : '{genCnm}');
    }
    return result;
  }

  // ── P6 path (BYTE-IDENTICAL to the original CustodyCountSubmit._onTap) ─────

  Future<void> _onTapP6(BuildContext context) async {
    if (CustodyCountSubmit._writing[widget.scrName] == true) return; // debounce

    // 1. Build ip[]
    final Map<String, CountEntry> countMap =
        CustodyCountList.getCountMap(widget.scrName);
    final List<Map<String, dynamic>> ipArray = <Map<String, dynamic>>[];
    for (final entry in countMap.values) {
      ipArray.add(entry.toIpMap());
    }

    if (ipArray.isEmpty) return; // safety

    // 2. Read table + search from component
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final String rawSearch =
        (widget.component['search'] ?? '').toString().trim();
    final String writeField =
        (widget.component['writeField'] ?? 'ip').toString().trim();

    if (rawTable.isEmpty || rawSearch.isEmpty) {
      _showSnackBar(context, 'Konfigurasi tidak lengkap');
      return;
    }

    // 3. Write natively
    CustodyCountSubmit._writing[widget.scrName] = true;
    // Trigger rebuild to show spinner
    CustodyCountList.countRev.value++;

    try {
      final bool success = await writeNativeFields(
        component: widget.component,
        rawTable: rawTable,
        rawSearch: rawSearch,
        scrName: widget.scrName,
        patch: {writeField: ipArray},
      );

      if (!success) {
        if (context.mounted) {
          _showSnackBar(context, 'Gagal menyimpan data');
        }
        return;
      }

      // 4. Navigate to custodyReveal
      final String rawRoute =
          (widget.component['route'] ?? '').toString().trim();
      final String route = stripRouteWrapper(rawRoute);
      if (route.isEmpty) return;

      if (routeExist(route)) {
        routeStack.push(route);
        gotoRoute(route);
      } else {
        if (context.mounted) {
          _showSnackBar(context, 'Layar belum tersedia');
        }
      }
    } finally {
      CustodyCountSubmit._writing[widget.scrName] = false;
      CustodyCountList.countRev.value++;
    }
  }

  // ── O1 path (native-create opening doc + designate via saveSend) ──────────

  Future<void> _onTapO1(BuildContext context) async {
    if (CustodyCountSubmit._writing[widget.scrName] == true) return;

    CustodyCountSubmit._writing[widget.scrName] = true;
    CustodyCountList.countRev.value++; // show spinner
    ExecutorDesignateCard.chosenRev.value++; // force rebuild

    try {
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;

      // 1. Resolve identities
      // vehicleId from the H1 hand-off (#ACTIVE_VEHICLE); O1/C1 have no
      // publisher, so a direct dhState.vehicleId read here was always empty.
      final String vehicleId = _resolveWarehouseVehicleId(screenTx);
      final String checkerVid = (screenTx['#VID'] ?? '').toString().trim();
      final String checkerName = _resolveCheckerName();
      final String genCnm = _generateCnm(vehicleId);
      final String warehouseId =
          (screenTx['#ACTIVE_WAREHOUSE'] ?? '').toString().trim();
      // NOTE: #CHOSEN_DRIVER_VID / #CHOSEN_DRIVER_NAME are NOT read into locals
      // here -- the designate `updateEventRow` DSL resolves {chosenVid} /
      // {chosenName} from screenTx directly via _resolveO1Tokens (step 5).
      final String today = todayEpochMidnightWib();
      final int nowMs = getNowMillisecondFromEpoch();

      // W1: warn if warehouseId is empty (no tasks today)
      if (warehouseId.isEmpty) {
        devPrint('[O1 submit] WARNING: warehouseId empty (no tasks today for '
            'vehicle $vehicleId). Opening doc gl will be empty.');
      }

      // 2. Build ie[] from the count store (BOTH count-list instances share
      //    the same per-scrName store).
      final Map<String, CountEntry> countMap =
          CustodyCountList.getCountMap(widget.scrName);
      final String writeCond =
          (widget.component['writeCond'] ?? 'full').toString().trim();
      final List<Map<String, dynamic>> ieArray = <Map<String, dynamic>>[];
      for (final entry in countMap.values) {
        ieArray.add({
          'ii': entry.ii,
          'cd': writeCond.isNotEmpty ? writeCond : entry.cd,
          'qt': entry.qty,
        });
      }

      if (ieArray.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, 'Tidak ada item untuk disimpan');
        }
        return;
      }

      // 3. Build the FULL opening doc map (scalars + ie[] array).
      //    Phase B: `cdt`/`ldt` are Number (epoch-ms) per the runtime type
      //    contract (eq-match {today}); `t` is int (chronological sort).
      final String rawCheckTable =
          (widget.component['checkTable'] ?? '').toString().trim();
      // I3: envelope tablevid so the native opening doc matches the shape of
      //     DSL-created vehicle_check docs (vidtable override, else docId).
      final String tableVid = (widget.component['vidtable'] ?? '')
          .toString()
          .trim()
          .isNotEmpty
          ? (widget.component['vidtable'] ?? '').toString().trim()
          : parseTablePath(rawCheckTable).tableDocId;
      final Map<String, dynamic> openingDoc = <String, dynamic>{
        'cnm': genCnm,
        'cty': 'opening',
        'vv': vehicleId,
        'gl': warehouseId,
        'cdt': int.parse(today), // Phase B: Number (epoch-ms WIB midnight)
        'cst': 'awaiting_custody',
        'gv': checkerVid,
        'gn': checkerName,
        'ldt': nowMs, // Phase B: Number (epoch-ms now)
        't': nowMs,
        'ie': ieArray,
        'tablevid': tableVid,
        'search': 'cnm\u{2605}$genCnm',
      };

      // 4. Write opening doc natively (ONE set, offline-safe)
      if (rawCheckTable.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, 'Konfigurasi checkTable tidak lengkap');
        }
        return;
      }

      final bool created = await createNativeDocAutoId(
        component: widget.component,
        rawTable: rawCheckTable,
        docMap: openingDoc,
      );

      if (!created) {
        if (context.mounted) {
          _showSnackBar(context, 'Gagal membuat data pengecekan');
        }
        return; // NO nav on failure
      }

      // 5. Designate driver + audit Event via saveSend. When action is
      //    'savesend', the component's addToEvent is preserved so saveSend
      //    writes an Event audit row (evidence) + GPS. When action is absent,
      //    addToEvent is stripped (legacy byte-identical behavior).
      final Map<String, dynamic> saveSendComponent =
          Map<String, dynamic>.from(widget.component as Map);
      final bool hasSaveSendAction =
          (widget.component['action'] ?? '').toString().trim().toLowerCase() ==
              'savesend';
      if (!hasSaveSendAction) {
        // Legacy: strip addToEvent (existing behavior before savesend plug)
        saveSendComponent.remove('addToEvent');
      }
      // Pre-resolve curly tokens in updateEventRow
      final String rawUER =
          (saveSendComponent['updateEventRow'] ?? '').toString();
      if (rawUER.isNotEmpty) {
        saveSendComponent['updateEventRow'] =
            _resolveO1Tokens(rawUER, checkerName, genCnm);
      }
      // Pre-resolve {checkerName} in addToEvent. This token is widget-local
      // (workforce lookup), NOT handled by resolveDriverCurlyTokens.
      if (hasSaveSendAction) {
        final String rawATE =
            (saveSendComponent['addToEvent'] ?? '').toString();
        if (rawATE.isNotEmpty) {
          saveSendComponent['addToEvent'] =
              _resolveO1Tokens(rawATE, checkerName, genCnm);
        }
      }

      // GPS capture: real GPS when gpsPosition > 0 (mirrors
      // ftz_row_of_button_2 pattern), else dummy/time-only locString.
      late int timeStamp;
      late String locString;
      final int gpsPos;
      if (widget.component['gpsPosition'] is String) {
        gpsPos =
            int.tryParse(widget.component['gpsPosition'].toString()) ?? 0;
      } else {
        gpsPos = widget.component['gpsPosition'] ?? 0;
      }
      if (gpsPos > 0) {
        final OtqState allOtqData = await OtqState().setAllDataAsync();
        timeStamp = allOtqData.nowTime.millisecondsSinceEpoch;
        locString = getLocationString('', '', '', allOtqData);
      } else {
        timeStamp = await getRealTime();
        final OtqState locSensor = OtqState();
        locSensor.nowTime = DateTime.fromMillisecondsSinceEpoch(timeStamp);
        locString = getLocationString('', '', '', locSensor);
      }

      saveSend(timeStamp, widget.scrName, saveSendComponent, locString,
          defaultVid());

      // 6. Navigate (chain-aware, mirrors custody_event_submit)
      final dynamic chain = widget.component['chain'];
      if (chain != null && chain.toString().trim().isNotEmpty) {
        if (context.mounted) {
          await doChain(context, widget.scrName, chain);
        }
      } else {
        final String rawRoute =
            (widget.component['route'] ?? '').toString().trim();
        final String route = stripRouteWrapper(rawRoute);
        if (route.isNotEmpty && routeExist(route)) {
          routeStack.push(route);
          gotoRoute(route);
        }
      }
    } catch (e) {
      errorReport(e);
      if (context.mounted) {
        _showSnackBar(context, 'Gagal mengirim: $e');
      }
    } finally {
      CustodyCountSubmit._writing[widget.scrName] = false;
      CustodyCountList.countRev.value++;
      ExecutorDesignateCard.chosenRev.value++;
    }
  }

  // ── C1 path (closing multi-write + reconcile + 2-route branch) ────────────

  Future<void> _onTapClosing(BuildContext context) async {
    if (CustodyCountSubmit._writing[widget.scrName] == true) return;

    CustodyCountSubmit._writing[widget.scrName] = true;
    CustodyCountList.countRev.value++; // show spinner

    try {
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;

      // 1. Resolve identities
      // vehicleId from the H1 hand-off (#ACTIVE_VEHICLE); O1/C1 have no
      // publisher, so a direct dhState.vehicleId read here was always empty.
      final String vehicleId = _resolveWarehouseVehicleId(screenTx);
      final String checkerVid = (screenTx['#VID'] ?? '').toString().trim();
      final String checkerName = _resolveCheckerName();
      final String warehouseId =
          (screenTx['#ACTIVE_WAREHOUSE'] ?? '').toString().trim();
      final String today = todayEpochMidnightWib();
      final int nowMs = getNowMillisecondFromEpoch();

      // Deterministic doc numbers (cnm/vnm field values; same nowMs ->
      // same WIB date stamp). Docs themselves use Firestore auto-ids.
      final String closingCnm = genClosingCnm(vehicleId, nowMs: nowMs);
      final String investigationVnm =
          genInvestigationVnm(vehicleId, nowMs: nowMs);

      // I3: #ACTIVE_WAREHOUSE is published by O1's count-list earlier in the
      // SAME trip and reused here. If empty (degrade-safe), gl stays empty:
      // a native single-doc Firestore .get() to backfill gl from the opening
      // doc would add a network round-trip on the offline-first submit path,
      // so we leave it empty per the plan's degrade-safe judgment.
      if (warehouseId.isEmpty) {
        devPrint('[C1 submit] WARNING: warehouseId empty for '
            'vehicle $vehicleId. Closing doc gl will be empty.');
      }

      // 2. Build ip[] from count store
      final Map<String, CountEntry> countMap =
          CustodyCountList.getCountMap(widget.scrName);
      final List<Map<String, dynamic>> ipArray = <Map<String, dynamic>>[];
      for (final entry in countMap.values) {
        ipArray.add(entry.toIpMap());
      }

      if (ipArray.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, 'Tidak ada item untuk disimpan');
        }
        return;
      }

      // 3. Reconcile: build expected/actual maps from count store
      final Map<String, int> expectedMap = <String, int>{};
      final Map<String, int> actualMap = <String, int>{};
      for (final entry in countMap.entries) {
        expectedMap[entry.key] = entry.value.planQty;
        actualMap[entry.key] = entry.value.qty;
      }
      final ReconciliationResult reconcile = buildReconciliation(
        expected: expectedMap,
        actual: actualMap,
      );

      // 4. Build closing doc map (scalars + ip[] + dp[] + rs)
      final String rawCheckTable =
          (widget.component['checkTable'] ?? '').toString().trim();
      // I3 pattern (from O1): envelope tablevid
      final String tableVid = (widget.component['vidtable'] ?? '')
              .toString()
              .trim()
              .isNotEmpty
          ? (widget.component['vidtable'] ?? '').toString().trim()
          : parseTablePath(rawCheckTable).tableDocId;

      // I2: `ldt` (load datetime) is an OPENING concept; the closing doc uses
      // `t` (int, sort) only. `t` is int (sort); `cdt` is Number (epoch-ms).
      final Map<String, dynamic> closingDoc = <String, dynamic>{
        'cnm': closingCnm,
        'cty': 'closing',
        'vv': vehicleId,
        'gl': warehouseId,
        'cdt': int.parse(today), // Phase B: Number (epoch-ms WIB midnight)
        'cv': checkerVid,
        'cn': checkerName,
        't': nowMs,
        'ip': ipArray,
        'dp': reconcile.dp,
        'rs': reconcile.rs,
        'tablevid': tableVid,
        'search': 'cnm\u{2605}$closingCnm',
      };

      // 5. Write closing doc natively (ONE set, offline-safe)
      if (rawCheckTable.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, 'Konfigurasi checkTable tidak lengkap');
        }
        return;
      }

      final bool created = await createNativeDocAutoId(
        component: widget.component,
        rawTable: rawCheckTable,
        docMap: closingDoc,
      );

      if (!created) {
        if (context.mounted) {
          _showSnackBar(context, 'Gagal membuat data penutupan');
        }
        return; // NO nav on failure
      }

      // 6. Close the opening doc `cst` -> 'closed' via field search.
      //    After Phase B (auto-id), the opening doc's Firestore doc id is
      //    unknown; find it by (cty=opening, vv=vehicleId, cdt=today).
      //    writeNativeFields is type-agnostic (whereIn:[String, Number])
      //    so it finds the doc whether cdt was stored as String (legacy)
      //    or Number (Phase B). Non-blocking: failure is logged only.
      final String closeSearch =
          'cty\u{25FC}opening\u{2B58}vv\u{25FC}$vehicleId\u{2B58}cdt\u{25FC}$today';
      final bool closed = await writeNativeFields(
        component: widget.component,
        rawTable: rawCheckTable,
        rawSearch: closeSearch,
        scrName: widget.scrName,
        patch: <String, dynamic>{'cst': 'closed'},
      );
      if (!closed) {
        devPrint('[C1 submit] WARNING: opening doc cst-close failed via '
            'search ($closeSearch). Proceeding (closing doc already written).');
      }

      // 7. R2 only: create investigation doc
      if (reconcile.rs == 'discrepancy_detected') {
        final String rawInvestTable =
            (widget.component['investigationTable'] ?? '').toString().trim();
        if (rawInvestTable.isNotEmpty) {
          final Map<String, dynamic> investDoc = <String, dynamic>{
            'vnm': investigationVnm,
            'vst': 'pending_review',
            'vrf': closingCnm,
            'vpt': 'check',
            'cv': checkerVid,
            'cn': checkerName,
            't': nowMs,
            'tablevid': tableVid,
            'search': 'vnm\u{2605}$investigationVnm',
          };
          final bool investCreated = await createNativeDocAutoId(
            component: widget.component,
            rawTable: rawInvestTable,
            docMap: investDoc,
          );
          if (!investCreated) {
            devPrint('[C1 submit] WARNING: investigation doc creation failed '
                'for $investigationVnm. Proceeding to R2 anyway.');
            // Proceed to R2 -- the closing doc is already written; the
            // investigation failure is not user-blocking (supervisor can
            // manually create from the discrepancy data).
          }
        } else {
          devPrint('[C1 submit] WARNING: investigationTable config empty. '
              'Skipping investigation doc creation.');
        }
      }

      // 7b. Audit Event + GPS via saveSend (Phase A: savesend plug).
      //     Best-effort: native write already succeeded; addToEvent failure
      //     must NOT cancel the count or block navigation.
      final bool hasSaveSendAction =
          (widget.component['action'] ?? '').toString().trim().toLowerCase() ==
              'savesend';
      if (hasSaveSendAction) {
        try {
          final Map<String, dynamic> saveSendComponent =
              Map<String, dynamic>.from(widget.component as Map);
          // Pre-resolve {checkerName} in addToEvent (widget-local token)
          final String rawATE =
              (saveSendComponent['addToEvent'] ?? '').toString();
          if (rawATE.isNotEmpty) {
            saveSendComponent['addToEvent'] =
                _resolveO1Tokens(rawATE, checkerName, '');
          }
          // Mirror O1: pre-resolve the widget-local {checkerName} in
          // updateEventRow too. C1's current config has none, but a future
          // search-bearing updateEventRow with {checkerName} would otherwise
          // inject the literal token into a Firestore query (silent 0-match).
          final String rawUER =
              (saveSendComponent['updateEventRow'] ?? '').toString();
          if (rawUER.isNotEmpty) {
            saveSendComponent['updateEventRow'] =
                _resolveO1Tokens(rawUER, checkerName, '');
          }
          // GPS capture: real GPS when gpsPosition > 0
          late int saveSendTs;
          late String saveSendLoc;
          final int gpsPos;
          if (widget.component['gpsPosition'] is String) {
            gpsPos =
                int.tryParse(widget.component['gpsPosition'].toString()) ?? 0;
          } else {
            gpsPos = widget.component['gpsPosition'] ?? 0;
          }
          if (gpsPos > 0) {
            final OtqState allOtqData = await OtqState().setAllDataAsync();
            saveSendTs = allOtqData.nowTime.millisecondsSinceEpoch;
            saveSendLoc = getLocationString('', '', '', allOtqData);
          } else {
            saveSendTs = await getRealTime();
            final OtqState locSensor = OtqState();
            locSensor.nowTime =
                DateTime.fromMillisecondsSinceEpoch(saveSendTs);
            saveSendLoc = getLocationString('', '', '', locSensor);
          }
          saveSend(saveSendTs, widget.scrName, saveSendComponent,
              saveSendLoc, defaultVid());
        } catch (saveSendErr) {
          // Best-effort: log only, do NOT cancel navigation or native write.
          devPrint('[C1 submit] saveSend audit failed: $saveSendErr');
        }
      }

      // 8. Nav by rs: matched -> matchRoute (R1), discrepancy -> mismatchRoute
      final String matchRoute =
          (widget.component['matchRoute'] ?? '').toString().trim();
      final String mismatchRoute =
          (widget.component['mismatchRoute'] ?? '').toString().trim();
      final String targetRoute =
          reconcile.rs == 'matched' ? matchRoute : mismatchRoute;
      final String route = stripRouteWrapper(targetRoute);
      if (route.isNotEmpty && routeExist(route)) {
        routeStack.push(route);
        gotoRoute(route);
      } else if (route.isNotEmpty) {
        if (context.mounted) {
          _showSnackBar(context, 'Layar hasil belum tersedia');
        }
      }
    } catch (e) {
      errorReport(e);
      if (context.mounted) {
        _showSnackBar(context, 'Gagal mengirim: $e');
      }
    } finally {
      CustodyCountSubmit._writing[widget.scrName] = false;
      CustodyCountList.countRev.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch the revision signal to register Obx dependency.
      CustodyCountList.countRev.value;
      // O1: also touch the chosen-driver revision so the enable gate updates
      // live when a driver is picked on the ExecutorDesignateCard.
      ExecutorDesignateCard.chosenRev.value;

      final Map<String, CountEntry> countMap =
          CustodyCountList.getCountMap(widget.scrName);

      final int total = countMap.length;
      final int n = countMap.values.where((e) => e.qty > 0).length;
      final bool isWriting = CustodyCountSubmit._writing[widget.scrName] ?? false;

      final bool enabled;
      final String label;
      final Color bgColor;
      final Color textColor;

      if (_isClosing) {
        // C1: enabled once items are rendered (count starts at 0, which is a
        // valid blind-count value; no driver-choose gate).
        enabled = total > 0;
        label = enabled ? _t(0, 'Simpan Penutupan') : 'TUNGGU DATA ITEM';
        // C1 teal palette (custody closing semantics).
        bgColor = enabled && !isWriting
            ? const Color(0xFF0D9488) // teal-600
            : const Color(0xFFD1D5DB); // gray-300
        textColor =
            enabled && !isWriting ? Colors.white : const Color(0xFF6B7280);
      } else if (_isOpening) {
        // O1: gate on driver chosen (#CHOSEN_DRIVER_VID non-empty).
        final Map<String, dynamic> screenTx =
            transactionStore.state.screenTx;
        final String chosenVid =
            (screenTx['#CHOSEN_DRIVER_VID'] ?? '').toString().trim();
        enabled = chosenVid.isNotEmpty;
        label = enabled
            ? _t(0, 'Simpan Pengecekan')
            : 'TENTUKAN PENGEMUDI DULU';
        // O1 teal palette (custody opening semantics).
        bgColor = enabled && !isWriting
            ? const Color(0xFF0D9488) // teal-600
            : const Color(0xFFD1D5DB); // gray-300
        textColor =
            enabled && !isWriting ? Colors.white : const Color(0xFF6B7280);
      } else {
        // P6 path (UNCHANGED).
        enabled = total > 0 && n == total;
        label = enabled
            ? 'LIHAT CATATAN WAREHOUSE \u{2192}' // right arrow
            : 'HITUNG SEMUA ITEM ($n/$total)';
        bgColor = enabled && !isWriting
            ? const Color(0xFF4338CA) // indigo-700
            : const Color(0xFFD1D5DB); // gray-300
        textColor = enabled && !isWriting
            ? Colors.white
            : const Color(0xFF6B7280); // gray-500
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (enabled && !isWriting)
                ? () {
                    if (_isClosing) {
                      _onTapClosing(context);
                    } else if (_isOpening) {
                      _onTapO1(context);
                    } else {
                      _onTapP6(context);
                    }
                  }
                : null,
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
      );
    });
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
