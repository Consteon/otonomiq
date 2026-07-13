import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // saveSend, getRealTime, getLocationString, getNowMillisecondFromEpoch, defaultVid
import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // transactionStore (dynamic), mapTableContent, devPrint
import '../model/otq_state.dart'; // OtqState
import '../redux/screen_transaction.dart'; // UpdateScreenTxAction, ScreenTransaction
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
  String _stockLocationCode = ''; // O1: stock_location subscription code
  String _vehicleCheckCode = ''; // C1: vehicle_check subscription code
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
    _subscribeStockLocation();
    _subscribeVehicleCheck();
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
    final String rawTable = (widget.component['workforceTable'] ?? '')
        .toString()
        .trim();
    if (rawTable.isEmpty) return;
    final String appVid = resolveAppVid(widget.component);
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _workforceCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
        appVid,
        tp.tableDocId,
        tp.subColl,
        _workforceCode,
      );
    }
  }

  /// Subscribe to the `stock_location` collection so O1 submit can resolve
  /// `{warehouseId}` from the single `lt=='warehouse'` doc when
  /// `#ACTIVE_WAREHOUSE` (task.gl) is empty. O1 only: early-returns for P6/C1.
  ///
  /// Table path: optional `warehouseTable` config override, else derived from
  /// `checkTable`'s tableDocId + the `stock_location` subcollection (same
  /// container as vehicle_check; mirrors vehicle_feed_list `_itemCode`).
  /// Idempotent per code (subscribeToMapCollection dedups via _mapSubscribed),
  /// so this reuses H1 VehicleFeedList's live subscription when present.
  void _subscribeStockLocation() {
    if (!_isOpening) return;
    final String appVid = resolveAppVid(widget.component);
    final String rawWhTable = (widget.component['warehouseTable'] ?? '')
        .toString()
        .trim();
    TablePath? tp;
    if (rawWhTable.isNotEmpty) {
      tp = parseTablePath(rawWhTable);
    } else {
      final String rawCheckTable = (widget.component['checkTable'] ?? '')
          .toString()
          .trim();
      final String docId = parseTablePath(rawCheckTable).tableDocId;
      if (docId.isNotEmpty) tp = TablePath(docId, 'stock_location');
    }
    if (tp != null && tp.tableDocId.isNotEmpty && tp.subColl.isNotEmpty) {
      _stockLocationCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
        appVid,
        tp.tableDocId,
        tp.subColl,
        _stockLocationCode,
      );
    }
  }

  /// Subscribe to the vehicle_check collection so C1 close can resolve the
  /// active opening doc-id and count existing openings for cnm suffix.
  /// C1 only: early-returns for O1/P6.
  void _subscribeVehicleCheck() {
    if (!_isClosing) return;
    final String rawCheckTable = (widget.component['checkTable'] ?? '')
        .toString()
        .trim();
    if (rawCheckTable.isEmpty) return;
    final String appVid = resolveAppVid(widget.component);
    final TablePath tp = parseTablePath(rawCheckTable);
    if (tp.tableDocId.isNotEmpty) {
      _vehicleCheckCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
        appVid,
        tp.tableDocId,
        tp.subColl,
        _vehicleCheckCode,
      );
    }
  }

  /// Resolve the logged-in checker's name from workforce where VID == #VID.
  /// Returns empty string if not found (degrade-safe: gn will be empty).
  String _resolveCheckerName() {
    if (_workforceCode.isEmpty) return '';
    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String checkerVid = (screenTx['#VID'] ?? '').toString().trim();
    if (checkerVid.isEmpty) return '';
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_workforceCode] ?? const [],
    );
    final String vidField = (widget.component['vidField'] ?? 'VID')
        .toString()
        .trim();
    final String nameField = (widget.component['nameField'] ?? 'n')
        .toString()
        .trim();
    for (final Map<String, dynamic> doc in docs) {
      final String vid = (doc[vidField] ?? '').toString().trim();
      if (vid == checkerVid) {
        return (doc[nameField] ?? '').toString().trim();
      }
    }
    return '';
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
    final String published = getDriverHomeState(
      widget.scrName,
    ).vehicleId.value.trim();
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
        '{checkerName}',
        checkerName.isNotEmpty ? checkerName : '{checkerName}',
      );
    }
    if (result.contains('{genCnm}')) {
      result = result.replaceAll(
        '{genCnm}',
        genCnm.isNotEmpty ? genCnm : '{genCnm}',
      );
    }
    return result;
  }

  // ── P6 path (BYTE-IDENTICAL to the original CustodyCountSubmit._onTap) ─────

  Future<void> _onTapP6(BuildContext context) async {
    if (CustodyCountSubmit._writing[widget.scrName] == true) return; // debounce

    // 1. Build ip[]
    final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
      widget.scrName,
    );
    final List<Map<String, dynamic>> ipArray = <Map<String, dynamic>>[];
    for (final entry in countMap.values) {
      ipArray.add(entry.toIpMap());
    }

    if (ipArray.isEmpty) return; // safety

    // 2. Read table + search from component
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final String writeField = (widget.component['writeField'] ?? 'ip')
        .toString()
        .trim();

    if (rawTable.isEmpty || rawSearch.isEmpty) {
      _showSnackBar(context, 'Konfigurasi tidak lengkap');
      return;
    }

    // 3. Resolve target doc-id from the same subscription the count-list
    //    populates (mapTableContent). Write by doc-id when available;
    //    fall back to search-based writeNativeFields for single-trip /
    //    pre-trip data.
    CustodyCountSubmit._writing[widget.scrName] = true;
    // Trigger rebuild to show spinner
    CustodyCountList.countRev.value++;

    try {
      // 3a. Doc-id resolution (byte-identical to custody_count_list._findCheckDoc)
      String docId = '';
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty && tp.subColl.isNotEmpty) {
        // vid-scoped: must match custody_count_list's scoped _checkCode key,
        // else this read-back misses the vehicle_check doc for the P6 write.
        final String appVid = resolveAppVid(widget.component);
        final String checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
          mapTableContent[checkCode] ?? const [],
        );
        if (rawSearch.isNotEmpty && docs.isNotEmpty) {
          final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
            docs,
            rawSearch,
            widget.scrName,
          );
          if (matched.isNotEmpty) {
            final Map<String, dynamic>? picked = pickActiveOpening(matched);
            final Map<String, dynamic> target = picked ?? matched.first;
            docId = (target['__docId'] ?? '').toString().trim();
          }
        }
      }

      // 3b. Write: prefer doc-id (createNativeDoc), fall back to search
      bool success = false;
      if (docId.isNotEmpty) {
        success = await createNativeDoc(
          component: widget.component,
          rawTable: rawTable,
          docId: docId,
          docMap: {writeField: ipArray},
        );
      }
      if (!success) {
        // Fallback: search-based write (single-trip / no subscription data)
        success = await writeNativeFields(
          component: widget.component,
          rawTable: rawTable,
          rawSearch: rawSearch,
          scrName: widget.scrName,
          patch: {writeField: ipArray},
        );
      }

      if (!success) {
        print(
          '[CustodyCountSubmit] native write failed: table=$rawTable, '
          'search=$rawSearch, field=$writeField, '
          'path=${docId.isNotEmpty ? "docid($docId)" : "search"}',
        );
        if (context.mounted) {
          _showSnackBar(context, 'Gagal menyimpan data');
        }
        return;
      }

      // Offline: write is queued locally (SDK persistence) -- tell the user.
      if (!internetConnected() && context.mounted) {
        _showSnackBar(
          context,
          'Tersimpan offline — dikirim otomatis saat online',
        );
      }

      // 4. Navigate to custodyReveal
      final String rawRoute = (widget.component['route'] ?? '')
          .toString()
          .trim();
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
      // genCnm uses the seq from the opening count (computed below after
      // today/nowMs). Moved to after the count resolution.
      // Resolve warehouseId with precedence (config override > #ACTIVE_WAREHOUSE
      // [task.gl-derived] > stock_location lt=='warehouse' fallback, spec §2.1).
      final String rawWhCfg = (widget.component['warehouseId'] ?? '')
          .toString()
          .trim();
      final String cfgResolved = rawWhCfg.isEmpty
          ? ''
          : resolveDriverCurlyTokens(rawWhCfg, widget.scrName);
      final String whFromStore = (screenTx['#ACTIVE_WAREHOUSE'] ?? '')
          .toString()
          .trim();
      final List<Map<String, dynamic>> stockDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_stockLocationCode] ?? const [],
          );
      final String warehouseId = resolveWarehouseId(
        configResolved: cfgResolved,
        fromStore: whFromStore,
        stockDocs: stockDocs,
      );
      // Forward-compat: when the value came from the fallback (store was empty),
      // publish it so the {warehouseId} token + any DSL field resolved later in
      // THIS submit (step 5) stay consistent with the native gl write. Cleared
      // on route change by ExecutorDesignateCard.clearO1State (no stale leak).
      if (whFromStore.isEmpty && warehouseId.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(
            ScreenTransaction({'#ACTIVE_WAREHOUSE': warehouseId}),
          ),
        );
      }
      // NOTE: #CHOSEN_DRIVER_VID / #CHOSEN_DRIVER_NAME are NOT read into locals
      // here -- the designate `updateEventRow` DSL resolves {chosenVid} /
      // {chosenName} from screenTx directly via _resolveO1Tokens (step 5).
      final String today = todayEpochMidnightWib();
      final int nowMs = getNowMillisecondFromEpoch();

      // Trip sequence: count existing same-day openings for this vehicle
      // to determine the cnm suffix (seq). First opening = 1 (no suffix).
      final String rawCheckTable = (widget.component['checkTable'] ?? '')
          .toString()
          .trim();
      final openingState = await fetchOpeningState(
        component: widget.component,
        rawTable: rawCheckTable,
        vehicleId: vehicleId,
        today: today,
      );
      final int seq = openingState.todayCount + 1;
      final String genCnm = genOpeningCnm(vehicleId, nowMs: nowMs, seq: seq);

      // W1: warn if warehouseId is empty (no tasks today)
      if (warehouseId.isEmpty) {
        devPrint(
          '[O1 submit] WARNING: warehouseId empty (no tasks today for '
          'vehicle $vehicleId). Opening doc gl will be empty.',
        );
      }

      // 2. Build ie[] from the count store (BOTH count-list instances share
      //    the same per-scrName store).
      final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
        widget.scrName,
      );
      final String writeCond = (widget.component['writeCond'] ?? 'full')
          .toString()
          .trim();
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
      // rawCheckTable already declared above (trip sequence count).
      // I3: envelope tablevid so the native opening doc matches the shape of
      //     DSL-created vehicle_check docs (vidtable override, else docId).
      final String tableVid =
          (widget.component['vidtable'] ?? '').toString().trim().isNotEmpty
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

      // 4b. Designate driver DIRECTLY on the stock_location row (dv/dn),
      //     bypassing the offline history queue. The config's
      //     `updateEventRow`->saveSend->historySync path does NOT sync this
      //     record on-device (historySync reports "no history sent"), so the
      //     designation never landed. A direct `writeNativeFields` merge onto
      //     the EXISTING stock_location row is offline-safe (Firestore SDK
      //     persistence), type-agnostic on `lv`, and mirrors the opening-doc
      //     `createNativeDocAutoId` above that already lands.
      //     (See memory: project_warehouse_o1_designation_no_sync.)
      final String chosenVid = (screenTx['#CHOSEN_DRIVER_VID'] ?? '')
          .toString()
          .trim();
      final String chosenName = (screenTx['#CHOSEN_DRIVER_NAME'] ?? '')
          .toString()
          .trim();
      if (chosenVid.isEmpty) {
        // Submit is gated on a chosen driver; guard defensively so an empty
        // vid can never blank an existing dv/dn.
        if (context.mounted) {
          _showSnackBar(context, 'Pilih pengemudi dulu');
        }
        return;
      }
      // stock_location lives in the same container as checkTable
      // (vehicle_check), subcollection `stock_location`; honor the optional
      // `warehouseTable` override (mirrors _subscribeStockLocation).
      final String rawWhTable = (widget.component['warehouseTable'] ?? '')
          .toString()
          .trim();
      final String stockDocId = rawWhTable.isNotEmpty
          ? parseTablePath(rawWhTable).tableDocId
          : parseTablePath(rawCheckTable).tableDocId;
      final bool designated = await writeNativeFields(
        component: widget.component,
        rawTable: '$stockDocId//stock_location',
        rawSearch: 'lv\u{25FC}$vehicleId',
        scrName: widget.scrName,
        patch: {'dv': chosenVid, 'dn': chosenName},
      );
      if (!designated) {
        if (context.mounted) {
          _showSnackBar(context, 'Gagal menetapkan pengemudi');
        }
        return; // NO nav on failure
      }

      // Offline: both native writes (opening doc + dv/dn) are queued locally
      // (SDK persistence) -- tell the user before saveSend/navigation.
      if (!internetConnected() && context.mounted) {
        _showSnackBar(
          context,
          'Tersimpan offline — dikirim otomatis saat online',
        );
      }

      // 5. Audit Event via saveSend (evidence + GPS). Designation is now done
      //    directly above; the component's `updateEventRow` still rides
      //    saveSend but is a harmless idempotent no-op (writes the same dv/dn
      //    if/when the history queue is ever fixed). When action is
      //    'savesend', the component's addToEvent is preserved so saveSend
      //    writes an Event audit row (evidence) + GPS. When action is absent,
      //    addToEvent is stripped (legacy byte-identical behavior).
      final Map<String, dynamic> saveSendComponent = Map<String, dynamic>.from(
        widget.component as Map,
      );
      final bool hasSaveSendAction =
          (widget.component['action'] ?? '').toString().trim().toLowerCase() ==
          'savesend';
      if (!hasSaveSendAction) {
        // Legacy: strip addToEvent (existing behavior before savesend plug)
        saveSendComponent.remove('addToEvent');
      }
      // Pre-resolve curly tokens in updateEventRow
      final String rawUER = (saveSendComponent['updateEventRow'] ?? '')
          .toString();
      if (rawUER.isNotEmpty) {
        saveSendComponent['updateEventRow'] = _resolveO1Tokens(
          rawUER,
          checkerName,
          genCnm,
        );
      }
      // Pre-resolve {checkerName} in addToEvent. This token is widget-local
      // (workforce lookup), NOT handled by resolveDriverCurlyTokens.
      if (hasSaveSendAction) {
        final String rawATE = (saveSendComponent['addToEvent'] ?? '')
            .toString();
        if (rawATE.isNotEmpty) {
          saveSendComponent['addToEvent'] = _resolveO1Tokens(
            rawATE,
            checkerName,
            genCnm,
          );
        }
      }

      // GPS capture: real GPS when gpsPosition > 0 (mirrors
      // ftz_row_of_button_2 pattern), else dummy/time-only locString.
      late int timeStamp;
      late String locString;
      final int gpsPos;
      if (widget.component['gpsPosition'] is String) {
        gpsPos = int.tryParse(widget.component['gpsPosition'].toString()) ?? 0;
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

      saveSend(
        timeStamp,
        widget.scrName,
        saveSendComponent,
        locString,
        defaultVid(),
      );

      // 6. Navigate (chain-aware, mirrors custody_event_submit)
      final dynamic chain = widget.component['chain'];
      if (chain != null && chain.toString().trim().isNotEmpty) {
        if (context.mounted) {
          await doChain(context, widget.scrName, chain);
        }
      } else {
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
      final String warehouseId = (screenTx['#ACTIVE_WAREHOUSE'] ?? '')
          .toString()
          .trim();
      final String today = todayEpochMidnightWib();
      final int nowMs = getNowMillisecondFromEpoch();

      // Trip sequence: single Firestore query resolves active opening doc-id
      // for targeted close AND count of today's openings for cnm suffix.
      final String rawCheckTable = (widget.component['checkTable'] ?? '')
          .toString()
          .trim();
      final openingState = await fetchOpeningState(
        component: widget.component,
        rawTable: rawCheckTable,
        vehicleId: vehicleId,
        today: today,
      );
      final String activeDocId = openingState.activeDocId;
      // seq: the seq of the trip being CLOSED (= the active opening).
      // If we can identify which seq this opening is, use the count of
      // today's openings. Fallback: seq=1.
      final int seq = openingState.todayCount > 0 ? openingState.todayCount : 1;

      // Deterministic doc numbers (cnm/vnm field values; same nowMs ->
      // same WIB date stamp). Docs themselves use Firestore auto-ids.
      final String closingCnm = genClosingCnm(
        vehicleId,
        nowMs: nowMs,
        seq: seq,
      );
      final String investigationVnm = genInvestigationVnm(
        vehicleId,
        nowMs: nowMs,
        seq: seq,
      );

      // I3: #ACTIVE_WAREHOUSE is published by O1's count-list earlier in the
      // SAME trip and reused here. If empty (degrade-safe), gl stays empty:
      // a native single-doc Firestore .get() to backfill gl from the opening
      // doc would add a network round-trip on the offline-first submit path,
      // so we leave it empty per the plan's degrade-safe judgment.
      if (warehouseId.isEmpty) {
        devPrint(
          '[C1 submit] WARNING: warehouseId empty for '
          'vehicle $vehicleId. Closing doc gl will be empty.',
        );
      }

      // 2. Build ip[] from count store
      final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
        widget.scrName,
      );
      final List<Map<String, dynamic>> ipArray = <Map<String, dynamic>>[];
      for (final entry in countMap.values) {
        ipArray.add(entry.toIpMap());
      }

      if (ipArray.isEmpty) {
        // Empty vehicle: confirm with checker before proceeding.
        // Guard the async-gap context use (after the earlier await) before
        // showDialog; finally still releases the writing lock on this return.
        if (!context.mounted) return;
        final bool? confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: const Text('Mobil Kosong?'),
              content: const Text(
                'Tidak ada item untuk diturunkan. '
                'Konfirmasi tutup penutupan?',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Ya, Tutup'),
                ),
              ],
            );
          },
        );
        if (confirmed != true) {
          // Cancelled or dismissed: abort, release writing lock via finally.
          return;
        }
        if (!context.mounted) return;
        // Confirmed: fall through to reconciliation + closing doc write.
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
      // rawCheckTable already declared above (trip sequence resolution).
      // I3 pattern (from O1): envelope tablevid
      final String tableVid =
          (widget.component['vidtable'] ?? '').toString().trim().isNotEmpty
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

      // Offline: closing doc is queued locally (SDK persistence); the
      // cst-close + investigation writes below queue the same way.
      if (!internetConnected() && context.mounted) {
        _showSnackBar(
          context,
          'Tersimpan offline — dikirim otomatis saat online',
        );
      }

      // 6. Close the SPECIFIC active opening doc `cst` -> 'closed'.
      //    Multi-trip: the old search (cty+vv+cdt) matches ALL same-day
      //    openings -> writeNativeFields refuses (>1 match). Use the resolved
      //    activeDocId to write directly by doc-id via createNativeDoc
      //    (set-merge: only patches 'cst', leaves other fields intact).
      //    Fallback: if activeDocId resolution failed, attempt old search.
      bool closed = false;
      if (activeDocId.isNotEmpty) {
        closed = await createNativeDoc(
          component: widget.component,
          rawTable: rawCheckTable,
          docId: activeDocId,
          docMap: <String, dynamic>{'cst': 'closed'},
        );
      }
      if (!closed) {
        // Fallback: search-based close (single-trip / pre-trip data)
        final String closeSearch =
            'cty\u{25FC}opening\u{2B58}vv\u{25FC}$vehicleId\u{2B58}cdt\u{25FC}$today';
        closed = await writeNativeFields(
          component: widget.component,
          rawTable: rawCheckTable,
          rawSearch: closeSearch,
          scrName: widget.scrName,
          patch: <String, dynamic>{'cst': 'closed'},
        );
        if (!closed) {
          devPrint(
            '[C1 submit] WARNING: opening doc cst-close failed. '
            'Proceeding (closing doc already written).',
          );
        }
      }

      // 6b. Clear dv/dn on the stock_location row (designation reset).
      //     Mirrors how O1 designates at line 445: same table/search shape
      //     (lv◼vehicleId on stock_location), empty-string values.
      //     Non-blocking: failure is logged only.
      final String rawWhTable = (widget.component['warehouseTable'] ?? '')
          .toString()
          .trim();
      final String stockDocId = rawWhTable.isNotEmpty
          ? parseTablePath(rawWhTable).tableDocId
          : parseTablePath(rawCheckTable).tableDocId;
      final bool dvCleared = await writeNativeFields(
        component: widget.component,
        rawTable: '$stockDocId//stock_location',
        rawSearch: 'lv\u{25FC}$vehicleId',
        scrName: widget.scrName,
        patch: <String, dynamic>{'dv': '', 'dn': ''},
      );
      if (!dvCleared) {
        devPrint(
          '[C1 submit] WARNING: dv/dn clear failed for $vehicleId. '
          'Proceeding (closing doc already written).',
        );
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
            devPrint(
              '[C1 submit] WARNING: investigation doc creation failed '
              'for $investigationVnm. Proceeding to R2 anyway.',
            );
            // Proceed to R2 -- the closing doc is already written; the
            // investigation failure is not user-blocking (supervisor can
            // manually create from the discrepancy data).
          }
        } else {
          devPrint(
            '[C1 submit] WARNING: investigationTable config empty. '
            'Skipping investigation doc creation.',
          );
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
          final String rawATE = (saveSendComponent['addToEvent'] ?? '')
              .toString();
          if (rawATE.isNotEmpty) {
            saveSendComponent['addToEvent'] = _resolveO1Tokens(
              rawATE,
              checkerName,
              '',
            );
          }
          // Mirror O1: pre-resolve the widget-local {checkerName} in
          // updateEventRow too. C1's current config has none, but a future
          // search-bearing updateEventRow with {checkerName} would otherwise
          // inject the literal token into a Firestore query (silent 0-match).
          final String rawUER = (saveSendComponent['updateEventRow'] ?? '')
              .toString();
          if (rawUER.isNotEmpty) {
            saveSendComponent['updateEventRow'] = _resolveO1Tokens(
              rawUER,
              checkerName,
              '',
            );
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
            locSensor.nowTime = DateTime.fromMillisecondsSinceEpoch(saveSendTs);
            saveSendLoc = getLocationString('', '', '', locSensor);
          }
          saveSend(
            saveSendTs,
            widget.scrName,
            saveSendComponent,
            saveSendLoc,
            defaultVid(),
          );
        } catch (saveSendErr) {
          // Best-effort: log only, do NOT cancel navigation or native write.
          devPrint('[C1 submit] saveSend audit failed: $saveSendErr');
        }
      }

      // 8. Nav by rs: matched -> matchRoute (R1), discrepancy -> mismatchRoute
      final String matchRoute = (widget.component['matchRoute'] ?? '')
          .toString()
          .trim();
      final String mismatchRoute = (widget.component['mismatchRoute'] ?? '')
          .toString()
          .trim();
      final String targetRoute = reconcile.rs == 'matched'
          ? matchRoute
          : mismatchRoute;
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

      final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
        widget.scrName,
      );

      final int total = countMap.length;
      final int n = countMap.values.where((e) => e.qty > 0).length;
      final bool isWriting =
          CustodyCountSubmit._writing[widget.scrName] ?? false;

      final bool enabled;
      final String label;
      final Color bgColor;
      final Color textColor;

      if (_isClosing) {
        // C1: always enabled — empty vehicle (all zero / hideZero) is a valid
        // closing state; the confirm dialog in _onTapClosing guards the empty
        // case instead of disabling the button.
        enabled = true;
        label = _t(0, 'Simpan Penutupan');
        // C1 teal palette (custody closing semantics).
        bgColor = enabled && !isWriting
            ? const Color(0xFF0D9488) // teal-600
            : const Color(0xFFD1D5DB); // gray-300
        textColor = enabled && !isWriting
            ? Colors.white
            : const Color(0xFF6B7280);
      } else if (_isOpening) {
        // O1: gate on driver chosen (#CHOSEN_DRIVER_VID non-empty).
        final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
        final String chosenVid = (screenTx['#CHOSEN_DRIVER_VID'] ?? '')
            .toString()
            .trim();
        enabled = chosenVid.isNotEmpty;
        label = enabled
            ? _t(0, 'Simpan Pengecekan')
            : 'TENTUKAN PENGEMUDI DULU';
        // O1 teal palette (custody opening semantics).
        bgColor = enabled && !isWriting
            ? const Color(0xFF0D9488) // teal-600
            : const Color(0xFFD1D5DB); // gray-300
        textColor = enabled && !isWriting
            ? Colors.white
            : const Color(0xFF6B7280);
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
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
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
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
