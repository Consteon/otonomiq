import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // getNowMillisecondFromEpoch
import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // transactionStore, routeStack, gotoRoute, routeExist, errorReport, diamondTextToList, autheniumDecode, mapTableContent
import '../global2.dart'; // txfController, txfControllerCheck, generateAutoNumber, addToTxfController, WidgetUpdateController
import '../screen_session.dart';
import 'admin_create_task_support.dart';
import 'admin_home_support.dart'; // AdminTierColors
import 'do_chain.dart';
import 'driver_home_support.dart'; // todayEpochMidnightWib, createNativeDoc, createNativeDocAutoId, stripRouteWrapper
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'task_item_builder.dart'; // TaskItemBuilder.draftRev

/// TASK_CREATE_SUBMIT -- P4 submit button for the Admin create-task wizard.
///
/// Reads the draft from AdminCreateTaskSupport, assembles the full task doc
/// (scalars from screenTx bare keys + it[] from draft), and writes via
/// createNativeDoc (one native Firestore set, offline-safe).
///
/// On success: clears draft, navigates to P5 (chain-aware).
/// On failure: snackbar, no nav, no draft clear.
///
/// ScreenTx key names are CONFIGURABLE via component fields (degrade-safe
/// defaults). This allows the op1Screen config to map different bare key
/// names if needed.
///
/// When component['action'] == 'savesend' (savesend mode):
///   - Processes run field to trigger generate_number (counter-based tnm)
///   - Reads generated tnm from numberPos position
///   - Writes doc with Firestore auto-generated id (createNativeDocAutoId)
/// When action is absent or not 'savesend' (legacy mode):
///   - Generates tnm from kl + timestamp (generateTnm)
///   - Writes doc with tnm as doc-id (createNativeDoc)
class TaskCreateSubmit extends StatefulWidget {
  const TaskCreateSubmit({
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

  /// Reset the writing-in-progress flag for a screen. Called from
  /// ui_component.dart clearData so a disposed-mid-await widget (whose
  /// _onSubmit `finally` never ran) cannot leave the button permanently
  /// disabled. Mirrors [TaskItemBuilder.resetClientPublished].
  static void registerScreenSession() {
    // Phase 2: flipped to nav:screen (stuck-flag after mid-await dispose).
    ScreenSession.ensure(
      'TaskCreateSubmit.writing',
      TaskCreateSubmit.resetWriting,
    );
  }

  static void resetWriting(String scrName) {
    _writing.remove(scrName);
  }

  /// Resolve the wizard vehicle id from the draft (SSOT when [wizardKey] is
  /// configured) with a screenTx fallback for non-wizard configs.
  ///
  /// D2 (round 3): when [wizardKey] is non-empty, the wizard draft is the
  /// sole source of truth. Bare screenTx keys merge for the whole session
  /// (DeleteAll is never dispatched), so a stale vv from a prior wizard run
  /// would silently point the next task at the WRONG vehicle. The fallback
  /// to screenTx only fires for legacy non-wizard configs.
  ///
  /// Pure; both [_onSubmit] and [build] route through this so they can
  /// never disagree about whether a vehicle exists.
  static String resolveWizardVehicle({
    required Map<String, String>? draftVeh,
    required String wizardKey,
    required Map<String, dynamic> screenTx,
    required String vvKey,
  }) {
    if (draftVeh != null && (draftVeh['vv'] ?? '').isNotEmpty) {
      return draftVeh['vv']!;
    }
    if (wizardKey.isNotEmpty) return '';
    return (screenTx[vvKey] ?? '').toString().trim();
  }

  /// Resolve the customer id (`kl`) exactly as [_onSubmit] does: wizard draft
  /// first, screenTx bare key as fallback.
  ///
  /// Round 4 (spec (2) §3.2 #3): the enable-gate routes through this so the
  /// button cannot light up on a submit that would write `kl: ''` --
  /// `generateTnm('')` yields `TASK--<date>-<time>` and the task carries no
  /// customer link.
  ///
  /// Deliberately NOT wizardKey-gated, unlike [resolveWizardVehicle]: a gate
  /// stricter than the write would block a submit that writes fine. The write's
  /// customer fallback is unconditional, so a stale screenTx `kl` from a prior
  /// wizard run still resolves here -- the same class of bug D2 closed for
  /// `vv`, left alone because fixing it changes what gets WRITTEN, not just
  /// what the button does.
  ///
  /// Pure; both [_onSubmit] and [build] route through this so they can never
  /// disagree about whether a customer exists.
  static String resolveCustomerKl({
    required Map<String, String>? draftCust,
    required Map<String, dynamic> screenTx,
    required String klKey,
  }) {
    if (draftCust != null && (draftCust['kl'] ?? '').isNotEmpty) {
      return draftCust['kl']!;
    }
    return (screenTx[klKey] ?? '').toString().trim();
  }

  /// Component param `adhocSkipTdt` (spec (6) section 3.2b REVISI). Only has an
  /// effect on the adhoc path (`adhocNoVehicle`); a normal task always gets its
  /// `tdt`.
  ///
  /// FALSE / absent (the default, and today's live behavior): adhoc writes
  /// `tdt:{today}` like any other task. TRUE: adhoc writes no `tdt` at all --
  /// "adhoc = task with no date yet" -- and the `OnTaskAssigned` CF is expected
  /// to stamp `tdt` server-side on the `unassigned -> assigned` transition.
  ///
  /// Why this is config and not a hardcoded model: `tdt`-on-adhoc has now
  /// flipped four times across specs (3) -> (5) -> (6), and spec (6) itself
  /// argues BOTH ways (sections 2 / 3.1 / 3.2b-line-70 / 12 say WRITE; sections
  /// 3.2 / 3.2b-heading / 9 / 11 say SKIP). Making the VALUE configurable is the
  /// same move that made the MODEL A -> MODEL C flip cost zero Dart -- see
  /// [_TaskCreateSubmitState._unassignedStatus]. Flip five is one config cell,
  /// not a release.
  ///
  /// Why the default is WRITE and not SKIP: the two failure directions are not
  /// symmetric. Writing `tdt` when it should have been skipped only dates an
  /// unscheduled task early, and assign overwrites it. Skipping `tdt` when it
  /// should have been written is the live 2026-08-04 bug -- the warehouse
  /// opening manifest sums `it[]` over tasks matching `(vv, tdt)`, so the task
  /// is invisible at load time -- and it is NOT backfillable from the app
  /// (`{today}` resolves only in an RBT savesend, not in the
  /// COORDINATION_SIGNAL_LIST inline vehiclePicker; test-confirmed, reverted).
  /// So SKIP is only safe once the CF exists. It does not yet:
  /// `docs/task-tdt-on-assign-cf-dev-spec.md` is not in the repo. Set this to
  /// `"true"` on D804 the day that CF ships.
  ///
  /// Truthy spellings mirror `picker_list.dart` `_titleMono`: `true` or `1`.
  ///
  /// Pure + static so it is reachable from a test -- `_onSubmit` itself is not
  /// (it calls `internetConnected`, `generateTnm` and Firestore), which is why
  /// the round-3/5/6 tdt flips all shipped with zero automated coverage.
  static bool resolveAdhocSkipTdt(dynamic component) {
    final String raw = (component['adhocSkipTdt'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return raw == 'true' || raw == '1';
  }

  /// The `tdt` a new task doc gets. `null` means "omit the field entirely" --
  /// [AdminCreateTaskSupport.assembleTaskDoc] drops a null `tdt`, so the doc
  /// has no `tdt` key at all rather than a zero.
  ///
  /// Both conjuncts are load-bearing. Dropping [adhocSkipTdt] hardcodes one
  /// side of a decision that has flipped four times. Dropping [adhocNoVehicle]
  /// is worse and quieter: it would strip `tdt` from EVERY task the moment the
  /// param is switched on, blinding the warehouse for normal scheduled work,
  /// not just adhoc. Extracted purely so a test can pin that -- inside
  /// `_onSubmit` the same expression is unreachable from `flutter_test`.
  static int? resolveTaskTdt({
    required bool adhocNoVehicle,
    required bool adhocSkipTdt,
    required int tdt,
  }) => (adhocNoVehicle && adhocSkipTdt) ? null : tdt;

  @override
  State<TaskCreateSubmit> createState() => _TaskCreateSubmitState();
}

class _TaskCreateSubmitState extends State<TaskCreateSubmit> {
  List<String> _textArray = [];

  /// stock_location subscription code (`<container>/stock_location`).
  /// Populated by [_subscribeStockLocation] in initState so the origin-
  /// warehouse fallback (single `lt=='warehouse'` doc -> `lv`) can resolve at
  /// submit time. Instance field (recreated per widget) -> no clear hook needed.
  String _stockLocationCode = '';

  @override
  void initState() {
    super.initState();
    TaskCreateSubmit.registerScreenSession();
    _parseText();
    _subscribeStockLocation();
  }

  /// Subscribe to the `stock_location` collection so [_onSubmit] can resolve
  /// the origin warehouse `gl` from the single `lt=='warehouse'` doc when both
  /// the config `originWarehouse` and `#ACTIVE_WAREHOUSE` are empty (the admin
  /// create-task flow, spec §256). Mirrors
  /// custody_count_submit._subscribeStockLocation (O1) and reuses the O1
  /// helpers resolveWarehouseId / lookupWarehouseLv.
  ///
  /// Table path: optional `warehouseTable` config override, else derived from
  /// the task `table`'s container id + the `stock_location` subcollection (same
  /// container as the task table). Idempotent (subscribeToMapCollection dedups
  /// via _mapSubscribed), so this reuses any live stock_location subscription
  /// (e.g. H1 VehicleFeedList) rather than opening a duplicate. Deploy-free:
  /// no new config field is required.
  void _subscribeStockLocation() {
    final String appVid = resolveAppVid(widget.component);
    final String rawWhTable = (widget.component['warehouseTable'] ?? '')
        .toString()
        .trim();
    TablePath? tp;
    if (rawWhTable.isNotEmpty) {
      tp = parseTablePath(rawWhTable);
    } else {
      final String rawTaskTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
      final String docId = parseTablePath(rawTaskTable).tableDocId;
      if (docId.isNotEmpty) tp = TablePath(docId, 'stock_location');
    }
    if (tp != null && tp.tableDocId.isNotEmpty && tp.subColl.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _stockLocationCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
        appVid,
        tp.tableDocId,
        tp.subColl,
        _stockLocationCode,
      );
    }
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Text slot accessors:
  ///  [0] "Buat Task & Assign"          (enabled label, assigned path)
  ///  [1] "Lengkapi data dulu"          (disabled label)
  ///  [2] "Gagal membuat task"          (error snackbar)
  ///  [3] "Data item kosong"            (empty items snackbar)
  ///  [4] "Simpan Tanpa Kendaraan"      (enabled label, unassigned path;
  ///       absent slot degrades to [0] -- byte-identical on existing configs)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'admin_create_task').toString().trim();

  /// Component param `unassignedStatus` (spec (5) section 3.2 #2, MODEL C).
  /// Empty/absent = today's behavior (vehicle REQUIRED). Non-empty = "vehicle is
  /// optional on this instance" -- it enables the adhoc path, and its value is
  /// what lands in `tst` when no vehicle was picked. Live config (D804) sets it
  /// to `"unassigned"`: under MODEL C an adhoc task carries a status DISTINCT
  /// from `assigned`, so AdminTaskList `groupBy:"tst"` can split "Belum
  /// Dijadwalkan" from "Terjadwal", and home COORDINATION_SIGNAL_LIST matches it
  /// with `unassignedGate:"tst◼unassigned"`. Assign later rewrites `tst` to
  /// `assigned` and the task moves group on its own.
  ///
  /// History: MODEL A (spec (3)) briefly set this to `"assigned"` and dropped the
  /// distinct status; spec (5) section 2 cancelled that, because two identical
  /// statuses cannot be grouped apart. The widget stayed generic across both
  /// models -- only the config VALUE changed. Submit computes
  /// `adhocNoVehicle = unassignedStatus.isNotEmpty && vv.isEmpty` to decide.
  String get _unassignedStatus =>
      (widget.component['unassignedStatus'] ?? '').toString().trim();

  /// See [TaskCreateSubmit.resolveAdhocSkipTdt].
  bool get _adhocSkipTdt =>
      TaskCreateSubmit.resolveAdhocSkipTdt(widget.component);

  Future<void> _onSubmit(BuildContext context) async {
    if (TaskCreateSubmit._writing[widget.scrName] == true) return;

    // Offline gate (decision 5): task creation needs the ONLINE counter
    // transaction (generate_number -> getNumber runTransaction) and must
    // never enqueue a create with a forged tnm. Short-circuit BEFORE
    // _processRunCommands so the counter is untouched. The wizard/draft
    // stays fully editable offline; only this final CTA blocks.
    if (!internetConnected()) {
      _showSnackBar(context, 'Butuh koneksi untuk membuat task');
      return;
    }

    TaskCreateSubmit._writing[widget.scrName] = true;
    final String unassignedStatus = _unassignedStatus;
    TaskItemBuilder.draftRev.value++; // trigger rebuild to show spinner

    try {
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;

      // ── Savesend mode gate (spec section 9 rollback) ──────────────────
      final bool savesendMode = AdminCreateTaskSupport.isSavesendMode(
        widget.component['action'],
      );

      // 1. Read CONFIGURABLE screenTx key names from component (degrade-safe)
      final String klKey = (widget.component['klKey'] ?? 'kl')
          .toString()
          .trim();
      final String knKey = (widget.component['knKey'] ?? 'kn')
          .toString()
          .trim();
      final String alKey = (widget.component['alKey'] ?? 'al')
          .toString()
          .trim();
      final String vvKey = (widget.component['vvKey'] ?? 'vv')
          .toString()
          .trim();

      // Draft-carry: when the wizard draft holds a customer (kl set), it is the
      // AUTHORITATIVE source -- read kl/kn/al from it as a UNIT. Mixing draft kl
      // with a screenTx kn/al that belongs to a previously-picked customer would
      // write a cross-customer doc (review C-1). P2 _republishClient backfills
      // the draft's kn/al from stock_location, so the draft is complete.
      // Only when no draft customer exists (legacy wizardKey-absent path) do we
      // fall back to the screenTx bare keys -- all three from the same source.
      final Map<String, String>? draftCust = AdminCreateTaskSupport.getCustomer(
        _wizardKey,
      );
      final bool hasDraftCust =
          draftCust != null && (draftCust['kl'] ?? '').isNotEmpty;
      final String kl = TaskCreateSubmit.resolveCustomerKl(
        draftCust: draftCust,
        screenTx: screenTx,
        klKey: klKey,
      );
      final String kn = hasDraftCust
          ? (draftCust['kn'] ?? '')
          : (screenTx[knKey] ?? '').toString().trim();
      final String al = hasDraftCust
          ? (draftCust['al'] ?? '')
          : (screenTx[alKey] ?? '').toString().trim();

      final Map<String, String>? draftVeh = AdminCreateTaskSupport.getVehicle(
        _wizardKey,
      );
      final String vv = TaskCreateSubmit.resolveWizardVehicle(
        draftVeh: draftVeh,
        wizardKey: _wizardKey,
        screenTx: screenTx,
        vvKey: vvKey,
      );

      final String vn = (draftVeh != null && (draftVeh['vn'] ?? '').isNotEmpty)
          ? draftVeh['vn']!
          : '';

      // D1 (round 3): CONDITIONAL. Take the adhoc path only when the param is
      // set AND the wizard resolved no vehicle. When a vehicle IS selected, the
      // normal assigned path fires -- even if this TASK_CREATE_SUBMIT instance
      // carries unassignedStatus. This closes the round-1 regression where
      // EVERY task from the shared submit component skipped its vehicle.
      final bool adhocNoVehicle = unassignedStatus.isNotEmpty && vv.isEmpty;

      // 2. gl (origin warehouse). Precedence mirrors O1 (custody_count_submit
      //    _onTapO1, spec §256): config `originWarehouse` >
      //    screenTx['#ACTIVE_WAREHOUSE'] > single stock_location lt=='warehouse'
      //    -> lv. Reuses resolveWarehouseId / lookupWarehouseLv
      //    (driver_home_support.dart). The previous glKey (bare 'gl') tier is
      //    dropped: nothing dispatches a bare 'gl' key in the admin create-task
      //    flow (always empty), and the documented origin-warehouse store key is
      //    '#ACTIVE_WAREHOUSE' (documentation.md:272).
      final String rawWhCfg = (widget.component['originWarehouse'] ?? '')
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
      final String gl = resolveWarehouseId(
        configResolved: cfgResolved,
        fromStore: whFromStore,
        stockDocs: stockDocs,
      );

      // 3. Creator (admin, NOT driver)
      final String cv = (screenTx['#VID'] ?? '').toString().trim();
      final String cn = (screenTx['#NAME'] ?? '').toString().trim();

      // 4. Read draft + validate (BEFORE generate -- counter must not
      //    increment on empty draft, per spec section 7)
      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final List<Map<String, dynamic>> itArray =
          AdminCreateTaskSupport.draftToItArray(draft);

      if (itArray.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, _t(3, 'Data item kosong'));
        }
        return;
      }

      // ── Branch: tnm generation + write method ─────────────────────────
      final String tnm;
      final bool useAutoId;

      if (savesendMode) {
        // 5a. Re-seed the read slot to the empty-marker BEFORE generate, so a
        //     skipped/no-op generate (config drift: numberPos != the run
        //     position, or the NUMBER widget not deployed / not yet built) can
        //     never leave a STALE prior-submit tnm behind. Without this, a
        //     second submit whose generate silently no-ops would read the
        //     previous run's value and write a duplicate tnm (review R2 Info).
        //     In correct config the generate below overwrites this immediately,
        //     so the happy path is unaffected.
        final int numPos = AdminCreateTaskSupport.parseNumberPos(
          widget.component['numberPos'],
        );
        txfControllerCheck(widget.scrName, numPos);
        addToTxfController(numPos, widget.scrName, emptyString);

        // 5b. Process run field (trigger generate_number at the run position)
        await _processRunCommands(widget.scrName);

        // 5c. Read generated tnm from numberPos
        final String generatedTnm =
            txfController[widget.scrName]?[numPos]?.finalData ?? '';

        // 5d. Validate generated tnm (spec section 7: fail -> no write)
        if (!AdminCreateTaskSupport.isGeneratedTnmValid(generatedTnm)) {
          if (context.mounted) {
            _showSnackBar(context, _t(2, 'Gagal membuat task'));
          }
          return;
        }

        tnm = generatedTnm;
        useAutoId = true;
      } else {
        // 5. Legacy: generate tnm from kl + timestamp
        tnm = AdminCreateTaskSupport.generateTnm(kl);
        useAutoId = false;
      }

      // 6. Time
      final int nowMs = getNowMillisecondFromEpoch();
      // Canonical: tdt is a Number (epoch-ms WIB midnight), mirroring O1's
      // `cdt: int.parse(today)` (custody_count_submit.dart:378).
      // todayEpochMidnightWib() returns int.toString() -> always parseable.
      // Write-safe: reads are type-tolerant (dsl-eq-type-tolerance) and there
      // is no server-side where('tdt') query.
      final int tdt = int.parse(todayEpochMidnightWib());

      // 7. tableVid
      final String tableVid =
          (widget.component['vidtable'] ?? '').toString().trim().isNotEmpty
          ? (widget.component['vidtable'] ?? '').toString().trim()
          : parseTablePath(
              (widget.component['table'] ?? '').toString().trim(),
            ).tableDocId;

      // 8. Assemble doc
      final Map<String, dynamic>
      taskDoc = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: tnm,
        kl: kl,
        kn: kn,
        al: al,
        // adhocNoVehicle implies vv.isEmpty (it is part of the condition),
        // so this is always the resolved vv -- no ternary needed.
        vv: vv,
        gl: gl,
        cv: cv,
        cn: cn,
        // Adhoc tdt is CONFIGURABLE and defaults to written -- see
        // [TaskCreateSubmit.resolveAdhocSkipTdt] for why it is a param at all
        // and why that default is the safe direction.
        tdt: TaskCreateSubmit.resolveTaskTdt(
          adhocNoVehicle: adhocNoVehicle,
          adhocSkipTdt: _adhocSkipTdt,
          tdt: tdt,
        ),
        t: nowMs,
        itArray: itArray,
        tableVid: tableVid,
        // D1 (round 3): CONDITIONAL. Use the param's status only when it is set
        // AND the resolved vehicle is empty. The stale-vv problem (bare
        // screenTx keys never cleared) is closed by resolveWizardVehicle:
        // wizard-scoped configs never fall back to screenTx.
        // MODEL C (spec (5) section 2): the live param D804 = "unassigned", a
        // status DISTINCT from `assigned` -- the two arms genuinely differ. Do
        // NOT collapse this ternary. (Under the cancelled MODEL A both arms were
        // "assigned", which made it look decorative.)
        tst: adhocNoVehicle ? unassignedStatus : 'assigned',
        ln: adhocNoVehicle ? '' : vn,
      );

      // 9. Write
      final String rawTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
      if (rawTable.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, _t(2, 'Gagal membuat task'));
        }
        return;
      }

      final bool created;
      if (useAutoId) {
        // Auto-id write (savesendMode): doc-id is Firestore-generated
        created = await createNativeDocAutoId(
          component: widget.component,
          rawTable: rawTable,
          docMap: taskDoc,
        );
      } else {
        // Legacy write: doc-id = tnm
        created = await createNativeDoc(
          component: widget.component,
          rawTable: rawTable,
          docId: tnm,
          docMap: taskDoc,
        );
      }

      if (!created) {
        if (context.mounted) {
          _showSnackBar(context, _t(2, 'Gagal membuat task'));
        }
        return;
      }

      // 9b. Stash snapshot for success screen (before draft is cleared).
      // Only fires on the success path (after created==true). Failure paths
      // return above and never reach here.
      final TaskTotals totals = AdminCreateTaskSupport.computeTotals(draft);
      AdminCreateTaskSupport.setLastCreated(
        _wizardKey,
        tnm: tnm,
        kn: kn,
        vn: adhocNoVehicle ? '' : vn,
        totalDrop: totals.totalDrop,
        totalPickup: totals.totalPickup,
      );

      // 10. Clear draft
      AdminCreateTaskSupport.clearDraft(_wizardKey);

      // 11. Navigate (chain-aware, mirrors custody_count_submit.dart:356)
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
        _showSnackBar(context, '${_t(2, 'Gagal membuat task')}: $e');
      }
    } finally {
      TaskCreateSubmit._writing[widget.scrName] = false;
      TaskItemBuilder.draftRev.value++;
    }
  }

  /// Process the `run` config field: parse and execute run commands.
  ///
  /// Replicates the pattern from ftz_row_of_button_2.dart:553-636.
  /// Format: "pos:action" commands separated by diamond (◆).
  /// Only `generate_number` action is processed (others are no-ops here).
  Future<void> _processRunCommands(String scrName) async {
    final String runField =
        (autheniumDecode((widget.component['run'] ?? '').toString()) ?? '')
            .trim()
            .toLowerCase();
    if (runField.isEmpty) return;

    final List<String> commands = runField.split('\u{25C6}'); // ◆
    final List<String> widgetsToUpdate = [];

    for (final String cmd in commands) {
      final List<String> parts = cmd.split(':');
      if (parts.length != 2) continue;

      final int? targetPosition = int.tryParse(parts[0].trim());
      final String action = parts[1].trim().toLowerCase();

      if (targetPosition == null) continue;
      if (action != 'generate_number') continue;

      txfControllerCheck(scrName, targetPosition);
      final controller = txfController[scrName]?[targetPosition];
      if (controller == null) continue;

      // Find the 'generate_number' entries registered by FtzAutoNumber initState
      final List<dynamic> execute1Actions =
          controller.execute1
              ?.where(
                (item) =>
                    item != null &&
                    item.length >= 2 &&
                    item[1].toString().toLowerCase() == 'generate_number',
              )
              .toList() ??
          [];

      for (final actionItem in execute1Actions) {
        if (actionItem != null && actionItem.length >= 3) {
          final String template = actionItem[2] as String;
          final String generatedString = await generateAutoNumber(
            template,
            scrName,
          );
          addToTxfController(targetPosition, scrName, generatedString);
          widgetsToUpdate.add('$scrName-$targetPosition');
        }
      }
    }

    // Update all affected NUMBER widgets so they show the generated value
    if (widgetsToUpdate.isNotEmpty) {
      Get.find<WidgetUpdateController>().update(widgetsToUpdate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch revision signal for cross-widget reactivity
      TaskItemBuilder.draftRev.value;

      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final bool hasItems = draft.isNotEmpty;

      // Read vehicle via the same resolution as _onSubmit (single source of
      // truth: resolveWizardVehicle). D2: wizard-scoped configs never fall
      // back to stale screenTx bare keys.
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
      final String vvKey = (widget.component['vvKey'] ?? 'vv')
          .toString()
          .trim();
      final String klKey = (widget.component['klKey'] ?? 'kl')
          .toString()
          .trim();
      final Map<String, String>? draftVeh = AdminCreateTaskSupport.getVehicle(
        _wizardKey,
      );
      final bool hasVehicle = TaskCreateSubmit.resolveWizardVehicle(
        draftVeh: draftVeh,
        wizardKey: _wizardKey,
        screenTx: screenTx,
        vvKey: vvKey,
      ).isNotEmpty;
      final bool hasCustomer = TaskCreateSubmit.resolveCustomerKl(
        draftCust: AdminCreateTaskSupport.getCustomer(_wizardKey),
        screenTx: screenTx,
        klKey: klKey,
      ).isNotEmpty;

      // Round 4 (spec (2) §3.2 #3): vehicle is OPTIONAL when unassignedStatus is
      // set, customer is required either way. An empty kl writes generateTnm('')
      // -> "TASK--<date>-<time>" and a task with no customer link, so the gate
      // blocks before the write rather than after it.
      // The gate mirrors the WRITE exactly: same param, same vehicle resolver.
      final bool vehicleOptional = _unassignedStatus.isNotEmpty;
      final bool enabled =
          hasCustomer &&
          (vehicleOptional ? hasItems : (hasItems && hasVehicle));
      final bool isWriting = TaskCreateSubmit._writing[widget.scrName] ?? false;

      // Slot [4] is the adhoc (no-vehicle) label; absent slot degrades to [0],
      // so configs without it are byte-identical to today.
      final String enabledLabel = (vehicleOptional && !hasVehicle)
          ? _t(4, _t(0, 'Buat Task & Assign'))
          : _t(0, 'Buat Task & Assign');
      final String label = enabled ? enabledLabel : _t(1, 'Lengkapi data dulu');

      final Color bgColor = enabled && !isWriting
          ? AdminTierColors
                .okAction // #2563EB (admin blue)
          : const Color(0xFFD1D5DB); // gray-300
      final Color textColor = enabled && !isWriting
          ? Colors.white
          : const Color(0xFF6B7280);

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
                ? () => _onSubmit(context)
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
