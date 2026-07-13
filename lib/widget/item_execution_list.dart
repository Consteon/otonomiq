import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'custody_count_list.dart';
import 'custody_stepper.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ITEM_EXECUTION_LIST -- per-item drop/pickup stepper list for P11.
///
/// Mirrors CustodyCountList (P6): subscribes to the task table, finds the
/// active task doc via {activeTaskVid}, iterates it[]. Per item: name, type
/// chip (returnable if pp>0, else consumable), DROP stepper (plan=pd),
/// PICKUP stepper (plan=pp, returnable only).
///
/// Per-cell status state-machine:
///   actual < plan  -> "Partial · N kurang" (amber)
///   actual == plan -> "✓ Sesuai" (emerald)
///   pickup actual > plan -> "Opportunistic · N" (violet)
///   drop actual > plan   -> "+N extra" (violet)
///
/// Count state is per-scrName, LOCAL ONLY (no write this round).
/// Store shape: plain Map + RxInt signal (Prior Correction #3).
///
/// Read-only for Firestore: no txfController, no saveSend, no history.
class ItemExecutionList extends StatefulWidget {
  const ItemExecutionList({
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

  // ── Per-screen execution store (reactive) ──────────────────────────────

  /// Per-scrName execution store: `{scrName: {itemIndex: ExecutionEntry}}`.
  /// Written by stepper taps. LOCAL ONLY -- no write to Firestore this round.
  /// Cleared on route change via [clearExecutionStore].
  ///
  /// Plain Map (not RxMap -- mutated in build via putIfAbsent without
  /// notifying). Cross-widget/internal reactivity via [executionRev] signal.
  static final Map<String, Map<String, ExecutionEntry>> executionStore =
      <String, Map<String, ExecutionEntry>>{};

  /// Revision counter: bumped on stepper taps (off build phase).
  static final RxInt executionRev = 0.obs;

  /// Per-scrName drop cap map: `{scrName: {itemId: capQty}}`.
  /// Built from asset_cache docs filtered by dropCapSearch.
  /// Plain Map (not RxMap -- rebuilt inside Obx from mapTableContent).
  /// Cleared alongside executionStore on route change.
  static final Map<String, Map<String, int>> capStore =
      <String, Map<String, int>>{};

  /// Guards one-shot devPrint per scrName when cap mode is active but
  /// unresolved. Cleared on route change via [clearExecutionStore].
  static final Set<String> _capUnresolvedLogged = <String>{};

  /// Per-scrName LIST component reference for the saveSend actual-write hook.
  /// The saveSend RBT reads this to decide whether actual-write is needed
  /// and to source the table/search/field config. Registered in build (and
  /// initState for first paint); cleared on route change via [clearExecutionStore].
  static final Map<String, dynamic> submitComponentByScr = <String, dynamic>{};

  /// Get or create the execution map for a screen.
  static Map<String, ExecutionEntry> getExecMap(String scrName) {
    return executionStore.putIfAbsent(
      scrName,
      () => <String, ExecutionEntry>{},
    );
  }

  /// Clear execution store and cap store for a screen.
  static void clearExecutionStore(String scrName) {
    executionStore.remove(scrName);
    capStore.remove(scrName);
    _capUnresolvedLogged.remove(scrName);
    submitComponentByScr.remove(scrName);
    executionRev.value++;
  }

  @override
  State<ItemExecutionList> createState() => _ItemExecutionListState();
}

class _ItemExecutionListState extends State<ItemExecutionList> {
  // ── Driver palette tokens ───────────────────────────────────────────────
  static const Color _ink = Color(0xFF1E293B); // slate-800 (item name)
  static const Color _hair = Color(0xFFE5E7EB); // gray-200 (card border)
  static const Color _planMuted = Color(0xFF9CA3AF); // gray-400 (plan mono)
  static const Color _caption = Color(0xFF94A3B8); // slate-400 (hints)
  // chip palette
  static const Color _accent = Color(0xFF4338CA); // indigo-700 (returnable fg)
  static const Color _accentBg = Color(0xFFEEF2FF); // indigo-50 (returnable bg)
  static const Color _neutralFg = Color(
    0xFF64748B,
  ); // slate-500 (consumable fg)
  static const Color _neutralBg = Color(
    0xFFF1F5F9,
  ); // slate-100 (consumable bg)
  // drop / pickup label fg
  static const Color _dropFg = Color(0xFF16A34A); // green-600
  static const Color _pickupFg = Color(0xFF7C3AED); // violet-600
  // ── Read-only tx card palette ──────────────────────────────────────────
  static const Color _tealFg = Color(0xFF0D9488); // teal-600
  static const Color _tealBg = Color(0xFFCCFBF1); // teal-50
  static const Color _tealBorder = Color(0xFF5EEAD4); // teal-300
  static const Color _emeraldFg = Color(0xFF059669); // emerald-600
  static const Color _emeraldBg = Color(0xFFECFDF5); // emerald-50
  static const Color _emeraldBorder = Color(0xFF6EE7B7); // emerald-300

  List<String> _textArray = [];
  String _taskCode = '';
  String _capCode = ''; // dropCapTable subscription code ('' = no-cap mode)
  String _pivotCode =
      ''; // pivot variant: table (asset_cache) subscription code
  String _joinCode = ''; // pivot variant: joinTable (item) subscription code

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
    // Register for saveSend actual-write hook (fields variant only).
    // Pivot uses CustodyCountSubmit, not the actual-write hook.
    final String initVariant = (widget.component['variant'] ?? 'fields')
        .toString()
        .trim();
    if (initVariant != 'pivot') {
      ItemExecutionList.submitComponentByScr[widget.scrName] = widget.component;
    }
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (24 slots, 0-based):
  ///  [0]  hint caption
  ///  [1]  "Drop"
  ///  [2]  "Pickup"
  ///  [3]  partial template "Partial · `<kurang>` kurang"
  ///  [4]  complete label "✓ Sesuai"
  ///  [5]  opportunistic template "Opportunistic · `<value>`"
  ///  [6]  extra template "+`<extra>` extra"
  ///  [7]  plan label "plan"
  ///  [8]  "Returnable"
  ///  [9]  "Consumable"
  ///  [10] pickupHint
  ///  ---- TX-DELTA slots (11-23) ----
  ///  [11] sale chip label "Jual"
  ///  [12] sale line "Jual ke customer"
  ///  [13] sale desc "Kepemilikan pindah · tanpa pickup"
  ///  [14] purchase chip label "Beli"
  ///  [15] purchase line "Beli dari customer"
  ///  [16] purchase desc "Kepemilikan ke operator · naik ke kendaraan"
  ///  [17] refill chip label "Refill"
  ///  [18] refill line "Tukar galon customer"
  ///  [19] refill desc "Kosong masuk · isi keluar · galon milik customer"
  ///  [20] condition: kosong "Kosong"
  ///  [21] condition: penuh "Penuh"
  ///  [22] water: RO "RO"
  ///  [23] water: isi ulang "Isi Ulang"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String variant = (widget.component['variant'] ?? 'fields')
        .toString()
        .trim();
    if (variant == 'pivot') {
      _subscribePivot(appVid);
      return;
    }
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }

    // Cap table subscription (asset_cache for drop stock-cap)
    final String rawCapTable = (widget.component['dropCapTable'] ?? '')
        .toString()
        .trim();
    if (rawCapTable.isNotEmpty) {
      final TablePath ctp = parseTablePath(rawCapTable);
      if (ctp.tableDocId.isNotEmpty) {
        _capCode = '$appVid/${ctp.tableDocId}/${ctp.subColl}';
        subscribeToMapCollection(appVid, ctp.tableDocId, ctp.subColl, _capCode);
      }
    }
  }

  /// Subscribe to pivot-variant data sources (asset_cache + item table).
  ///
  /// Keeps _taskCode and _capCode empty so the fields-path reactive touches
  /// in build() are no-ops.
  void _subscribePivot(String appVid) {
    // Pivot data source (asset_cache)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        _pivotCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _pivotCode);
      }
    }

    // JOIN table (item names + categories)
    final String rawJoinTable = (widget.component['joinTable'] ?? '')
        .toString()
        .trim();
    if (rawJoinTable.isNotEmpty) {
      final TablePath jtp = parseTablePath(rawJoinTable);
      if (jtp.tableDocId.isNotEmpty) {
        _joinCode = '$appVid/${jtp.tableDocId}/${jtp.subColl}';
        subscribeToMapCollection(
          appVid,
          jtp.tableDocId,
          jtp.subColl,
          _joinCode,
        );
      }
    }
  }

  /// Find the active task doc.
  Map<String, dynamic>? _findActiveTask() {
    if (_taskCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
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

  /// Extract the it[] items array from the task doc.
  List<Map<String, dynamic>> _extractItems(Map<String, dynamic>? taskDoc) {
    if (taskDoc == null) return const [];
    final String itemsField = (widget.component['itemsField'] ?? 'it')
        .toString()
        .trim();
    final dynamic rawItems = taskDoc[itemsField];
    if (rawItems is! List) return const [];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      out.add(Map<String, dynamic>.from(entry));
    }
    return out;
  }

  /// Build item rows from the it[] array, seeding the execution store.
  ///
  /// Never-blank: deliver rows always seed (at plan when the drop-cap is
  /// unresolved, so the widget never hides during loading). Once the cap
  /// resolves, the post-putIfAbsent clamp-down lowers any stored value that
  /// exceeds the cap, so the once-only putIfAbsent seed can never lock in an
  /// uncapped value.
  List<_ItemRow> _buildRows(
    List<Map<String, dynamic>> items,
    Map<String, dynamic>? taskDoc,
  ) {
    final String labelField = (widget.component['labelField'] ?? 'in')
        .toString()
        .trim();
    final String planDropField = (widget.component['planDropField'] ?? 'pd')
        .toString()
        .trim();
    final String planPickupField = (widget.component['planPickupField'] ?? 'pp')
        .toString()
        .trim();
    // TX-DELTA config fields
    final String txField = (widget.component['txField'] ?? 'tx')
        .toString()
        .trim();
    final String saleField = (widget.component['saleField'] ?? 'ps')
        .toString()
        .trim();
    final String buyField = (widget.component['buyField'] ?? 'pb')
        .toString()
        .trim();
    final String refillField = (widget.component['refillField'] ?? 'pr')
        .toString()
        .trim();
    final String condOutField = (widget.component['condOutField'] ?? 'cdo')
        .toString()
        .trim();
    final String condInField = (widget.component['condInField'] ?? 'cdi')
        .toString()
        .trim();
    final String waterFieldKey = (widget.component['waterField'] ?? 'wt')
        .toString()
        .trim();

    // Text-slot labels for condition / water mapping
    final String kosongSlot = _t(20, 'Kosong');
    final String penuhSlot = _t(21, 'Penuh');
    final String roSlot = _t(22, 'RO');
    final String isiUlangSlot = _t(23, 'Isi Ulang');

    // ── Drop-cap resolution ────────────────────────────────────────────
    // Cap config fields (read by NAME from component, never hardcoded).
    final String capKeyField = (widget.component['dropCapKey'] ?? 'ii')
        .toString()
        .trim();
    final String capValueField = (widget.component['dropCapField'] ?? 'qt')
        .toString()
        .trim();
    final String rawCapSearch = (widget.component['dropCapSearch'] ?? '')
        .toString()
        .trim();

    final bool capModeActive = _capCode.isNotEmpty;

    // Resolve cap predicate:
    //   capModeActive AND task.vv present AND cap snapshot arrived.
    // (vehicle id comes from the task doc's vv field, NOT the session
    // {vehicleId} token -- P11 has no vehicleId publisher.)
    // Until all three hold, rowCap stays null -> rows seed at plan (no-cap)
    // and clamp-down re-corrects once the cap resolves.
    bool capResolved = false;
    Map<String, int> capMap = const <String, int>{};

    if (capModeActive) {
      // Resolve vehicle id from the active task doc (not session {vehicleId}
      // publisher -- P11 has no publisher; task.vv IS the vehicle id).
      final String vehicleField = (widget.component['vehicleField'] ?? 'vv')
          .toString()
          .trim();
      final String taskVv = (taskDoc?[vehicleField] ?? '').toString().trim();

      final bool snapshotArrived = mapTableContent[_capCode] != null;
      capResolved = taskVv.isNotEmpty && snapshotArrived;

      if (capResolved) {
        // Build cap map from filtered docs.
        final List<Map<String, dynamic>> allCapDocs =
            List<Map<String, dynamic>>.from(
              mapTableContent[_capCode] ?? const [],
            );
        final String resolvedCapSearch = rawCapSearch.replaceAll(
          '{vehicleId}',
          taskVv,
        );
        final List<Map<String, dynamic>> filteredCapDocs =
            resolvedCapSearch.isNotEmpty
            ? filterDriverHomeDocs(
                allCapDocs,
                resolvedCapSearch,
                widget.scrName,
              )
            : allCapDocs;
        capMap = buildDropCapMap(
          filteredCapDocs,
          capKeyField: capKeyField,
          capValueField: capValueField,
        );
        // Store for access by _buildItemCard (per-row cap lookup).
        ItemExecutionList.capStore[widget.scrName] = capMap;
      }
      if (!capResolved &&
          !ItemExecutionList._capUnresolvedLogged.contains(widget.scrName)) {
        ItemExecutionList._capUnresolvedLogged.add(widget.scrName);
        devPrint(
          'ITEM_EXECUTION_LIST: cap unresolved for ${widget.scrName}'
          ' -> rendering no-cap (plan) until task.vv'
          ' + asset_cache snapshot ready',
        );
      }
    }

    final Map<String, ExecutionEntry> execMap = ItemExecutionList.getExecMap(
      widget.scrName,
    );
    final int sizeBefore = execMap.length;
    final List<_ItemRow> rows = <_ItemRow>[];

    for (int i = 0; i < items.length; i++) {
      final Map<String, dynamic> item = items[i];
      final String name = (item[labelField] ?? '').toString().trim();
      final String key = '$i';
      final String txKind = classifyTxKind(
        (item[txField] ?? '').toString().trim().toLowerCase(),
      );

      if (txKind == 'deliver') {
        // ── Deliver: seed execution store with cap-aware seed ──
        // When cap is unresolved, rowCap=null -> seed at plan (never blank).
        // Clamp-down re-corrects once cap resolves.

        final int planDrop =
            int.tryParse((item[planDropField] ?? '0').toString().trim()) ?? 0;
        final int planPickup =
            int.tryParse((item[planPickupField] ?? '0').toString().trim()) ?? 0;
        final bool isReturnable = planPickup > 0;

        // Resolve per-item cap: non-null ONLY when cap mode is active AND
        // resolved. null -> no-cap behavior (seed at plan, [+] free).
        final String itemIi = (item[capKeyField] ?? '').toString().trim();
        final int? rowCap = (capModeActive && capResolved)
            ? (capMap[itemIi] ?? 0)
            : null;
        final int seedDrop = (rowCap == null)
            ? planDrop
            : (planDrop < rowCap ? planDrop : rowCap);

        // Seed execution store (putIfAbsent -- once per item per session).
        execMap.putIfAbsent(
          key,
          () => ExecutionEntry(
            dropActual: seedDrop,
            pickupActual: planPickup,
            dropPlan: planDrop,
            pickupPlan: planPickup,
          ),
        );

        // Clamp-down: re-correct a stale plan-seed once cap is known.
        // putIfAbsent seeds once. On the first (unresolved) build it seeds
        // at plan; when cap later resolves, putIfAbsent no-ops but
        // clamp-down lowers the stored value to cap.
        // Plain-Map mutate; value is read later THIS build; NO
        // executionRev bump, NO setState (Prior Correction #3).
        final ExecutionEntry? seeded = execMap[key];
        if (seeded != null && rowCap != null && seeded.dropActual > rowCap) {
          seeded.dropActual = rowCap;
        }

        rows.add(
          _ItemRow(
            index: i,
            key: key,
            name: name.isNotEmpty ? name : 'Item $i',
            txKind: 'deliver',
            isReturnable: isReturnable,
            planDrop: planDrop,
            planPickup: planPickup,
            itemIi: itemIi,
            dropCap: rowCap,
          ),
        );
      } else {
        // ── Sale / Purchase / Refill: read-only, NO execution store ──
        final int txQty;
        final String subLabel;

        if (txKind == 'sale') {
          txQty = int.tryParse((item[saleField] ?? '0').toString().trim()) ?? 0;
          subLabel = conditionLabel(
            (item[condOutField] ?? '').toString(),
            kosongSlot: kosongSlot,
            penuhSlot: penuhSlot,
          );
        } else if (txKind == 'purchase') {
          txQty = int.tryParse((item[buyField] ?? '0').toString().trim()) ?? 0;
          subLabel = conditionLabel(
            (item[condInField] ?? '').toString(),
            kosongSlot: kosongSlot,
            penuhSlot: penuhSlot,
          );
        } else {
          // refill
          txQty =
              int.tryParse((item[refillField] ?? '0').toString().trim()) ?? 0;
          subLabel = waterLabel(
            (item[waterFieldKey] ?? '').toString(),
            roSlot: roSlot,
            isiUlangSlot: isiUlangSlot,
          );
        }

        rows.add(
          _ItemRow(
            index: i,
            key: key,
            name: name.isNotEmpty ? name : 'Item $i',
            txKind: txKind,
            txQty: txQty,
            subLabel: subLabel,
          ),
        );
      }
    }

    // Schedule post-frame rev bump if rows grew (mirrors CustodyCountList W1).
    if (execMap.length > sizeBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ItemExecutionList.executionRev.value++;
      });
    }
    return rows;
  }

  void _onDropChanged(String key, int newValue) {
    final Map<String, ExecutionEntry> map = ItemExecutionList.getExecMap(
      widget.scrName,
    );
    final ExecutionEntry? entry = map[key];
    if (entry != null) {
      // Defense-in-depth: clamp to cap if cap mode is active.
      int clamped = newValue;
      if (_capCode.isNotEmpty) {
        final Map<String, int> capMap =
            ItemExecutionList.capStore[widget.scrName] ?? const <String, int>{};
        // Derive the item's ii from the current task doc.
        final String capKeyField = (widget.component['dropCapKey'] ?? 'ii')
            .toString()
            .trim();
        final Map<String, dynamic>? taskDoc = _findActiveTask();
        final List<Map<String, dynamic>> items = _extractItems(taskDoc);
        final int idx = int.tryParse(key) ?? -1;
        if (idx >= 0 && idx < items.length) {
          final String itemIi = (items[idx][capKeyField] ?? '')
              .toString()
              .trim();
          final int? cap = capMap[itemIi];
          if (cap != null && clamped > cap) {
            clamped = cap;
          }
        }
      }
      entry.dropActual = clamped;
      ItemExecutionList.executionRev.value++;
      setState(() {});
    }
  }

  void _onPickupChanged(String key, int newValue) {
    final Map<String, ExecutionEntry> map = ItemExecutionList.getExecMap(
      widget.scrName,
    );
    final ExecutionEntry? entry = map[key];
    if (entry != null) {
      entry.pickupActual = newValue;
      ItemExecutionList.executionRev.value++;
      setState(() {});
    }
  }

  /// Stepper tap callback for pivot variant.
  ///
  /// Updates CustodyCountList.countStore (the submit contract), bumps countRev
  /// for cross-widget Obx reactivity, and calls setState for local rebuild.
  void _onPivotCountChanged(
    String countKey,
    int newValue,
    String ii,
    String cd,
  ) {
    final Map<String, CountEntry> map = CustodyCountList.getCountMap(
      widget.scrName,
    );
    final CountEntry? entry = map[countKey];
    if (entry != null) {
      entry.qty = newValue;
    } else {
      // Defensive: seed if somehow missing (should never happen -- seeded in
      // _buildPivotVariant before render).
      map[countKey] = CountEntry(ii: ii, cd: cd, qty: newValue);
    }
    CustodyCountList.countRev.value++;
    setState(() {});
  }

  /// Derive per-cell status.
  _CellStatus _cellStatus(int actual, int plan, bool isPickup) {
    if (actual < plan) {
      final int kurang = plan - actual;
      final String template = _t(3, 'Partial \u{00B7} <kurang> kurang');
      final String label = template.replaceAll('<kurang>', '$kurang');
      return _CellStatus('partial', label);
    } else if (actual == plan) {
      return _CellStatus('complete', _t(4, '\u{2713} Sesuai'));
    } else {
      // actual > plan
      if (isPickup) {
        final int extra = actual - plan;
        final String template = _t(5, 'Opportunistic \u{00B7} <value>');
        final String label = template.replaceAll('<value>', '$extra');
        return _CellStatus('opportunistic', label);
      } else {
        final int extra = actual - plan;
        final String template = _t(6, '+<extra> extra');
        final String label = template.replaceAll('<extra>', '$extra');
        return _CellStatus('extra', label);
      }
    }
  }

  /// Derive per-cell status for pivot variant.
  ///
  /// delta == 0 -> emerald ('complete', text[2] "Sesuai").
  /// delta < 0 -> amber ('partial', text[3] with signed delta).
  /// delta > 0 -> violet ('extra', text[3] with signed delta).
  _CellStatus _pivotCellStatus(int counted, int expected) {
    final int delta = counted - expected;
    if (delta == 0) {
      return _CellStatus('complete', _t(2, '\u{2713} Sesuai'));
    }
    // Non-zero delta: signed string (e.g. "+3" or "-2").
    final String sign = delta > 0 ? '+$delta' : '$delta';
    final String template = _t(3, 'Selisih \u{00B7} <delta>');
    final String label = template.replaceAll('<delta>', sign);
    if (delta < 0) {
      return _CellStatus('partial', label); // amber
    }
    return _CellStatus('extra', label); // violet
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // ── Variant dispatch ─────────────────────────────────────────────
      final String variant = (widget.component['variant'] ?? 'fields')
          .toString()
          .trim();
      if (variant == 'pivot') return _buildPivotVariant();

      // Re-register for the saveSend actual-write hook on EVERY build, not just
      // initState. saveSend -> clearData -> clearExecutionStore removes this
      // entry on every submit (api.dart:4309 -> 3985 ->
      // item_execution_list.dart:85), and the cached widget's initState does
      // not re-run on re-visit, so an initState-only registration is wiped
      // after stop #1 and the hook guard goes false -> ad/ap null on every
      // later stop. Idempotent re-register here (plain Map assignment, no
      // setState) keeps the hook live for every stop, mirroring
      // executionStore's re-seed-in-build self-healing.
      ItemExecutionList.submitComponentByScr[widget.scrName] = widget.component;

      // ── EXISTING fields variant (below is unchanged) ─────────────────
      // Touch vehicleId + executionRev for Obx dependency.
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;
      ItemExecutionList.executionRev.value;

      // Touch mapTableContent for reactive rebuild.
      mapTableContent[_taskCode];

      // Touch cap subscription for reactive rebuild (no-op if _capCode empty).
      if (_capCode.isNotEmpty) {
        mapTableContent[_capCode];
      }

      // Find active task and extract items.
      final Map<String, dynamic>? taskDoc = _findActiveTask();
      final List<Map<String, dynamic>> items = _extractItems(taskDoc);
      final List<_ItemRow> rows = _buildRows(items, taskDoc);
      final Map<String, ExecutionEntry> execMap = ItemExecutionList.getExecMap(
        widget.scrName,
      );

      if (rows.isEmpty) return const SizedBox.shrink();

      // Text slots
      final String hintCaption = _t(0, '');
      final String dropLabel = _t(1, 'Drop');
      final String pickupLabel = _t(2, 'Pickup');
      final String planLabel = _t(7, 'plan');
      final String returnableLabel = _t(8, 'Returnable');
      final String consumableLabel = _t(9, 'Consumable');
      final String pickupHint = _t(10, '');

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hint caption
            if (hintCaption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  hintCaption.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: _caption,
                  ),
                ),
              ),

            // Item cards
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              if (rows[i].txKind == 'deliver')
                _buildItemCard(
                  rows[i],
                  execMap,
                  dropLabel: dropLabel,
                  pickupLabel: pickupLabel,
                  planLabel: planLabel,
                  returnableLabel: returnableLabel,
                  consumableLabel: consumableLabel,
                )
              else
                _buildReadOnlyTxCard(rows[i]),
            ],

            // Pickup hint
            if (pickupHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  pickupHint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _caption,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  /// Build the complete pivot variant UI.
  ///
  /// Called from Obx in build() when variant == 'pivot'. Groups asset_cache
  /// docs by [groupKey], pivots [valueField] into N stepper cells per distinct
  /// [pivotField] value listed in [slots]. Writes counted values to
  /// CustodyCountList.countStore for submit integration.
  Widget _buildPivotVariant() {
    // ── Touch reactive deps for Obx tracking ───────────────────────────
    final DriverHomeState dhState = getDriverHomeState(widget.scrName);
    dhState.vehicleId.value; // {activeVehicle} token resolution
    CustodyCountList.countRev.value; // cross-widget stepper reactivity

    if (_pivotCode.isNotEmpty) mapTableContent[_pivotCode];
    if (_joinCode.isNotEmpty) mapTableContent[_joinCode];

    // ── Parse pivot config ─────────────────────────────────────────────
    final String groupKey = (widget.component['groupKey'] ?? '')
        .toString()
        .trim();
    final String pivotField = (widget.component['pivotField'] ?? '')
        .toString()
        .trim();
    final String valueField = (widget.component['valueField'] ?? '')
        .toString()
        .trim();
    final String rawSlots = (widget.component['slots'] ?? '').toString().trim();
    final List<PivotSlot> slots = parsePivotSlots(rawSlots);
    final bool hideZero = hideZeroEnabled(widget.component); // spec §2b

    if (groupKey.isEmpty || pivotField.isEmpty || slots.isEmpty) {
      return const SizedBox.shrink();
    }

    // ── Get and filter pivot docs (asset_cache) ────────────────────────
    final List<Map<String, dynamic>> pivotDocs =
        List<Map<String, dynamic>>.from(
          mapTableContent[_pivotCode] ?? const <Map<String, dynamic>>[],
        );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final List<Map<String, dynamic>> filtered = rawSearch.isNotEmpty
        ? filterDriverHomeDocs(pivotDocs, rawSearch, widget.scrName)
        : pivotDocs;

    // ── Build item detail map (JOIN for name + category) ───────────────
    final String joinKey = (widget.component['joinKey'] ?? 'ii')
        .toString()
        .trim();
    final String labelField = (widget.component['labelField'] ?? 'in')
        .toString()
        .trim();
    final String catField = (widget.component['catField'] ?? 'ic')
        .toString()
        .trim();
    final List<Map<String, dynamic>> joinDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_joinCode] ?? const <Map<String, dynamic>>[],
    );
    final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
      joinDocs,
      idField: joinKey,
      nameField: labelField,
      categoryField: catField,
    );

    // ── Group filtered docs by groupKey ────────────────────────────────
    final Map<String, List<Map<String, dynamic>>> groups = groupDocsByKey(
      filtered,
      groupKey,
    );

    if (groups.isEmpty) return const SizedBox.shrink();

    // ── Seed CustodyCountList.countStore for submit integration ────────
    final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
      widget.scrName,
    );
    final int sizeBefore = countMap.length;

    final List<_PivotCardData> cards = <_PivotCardData>[];
    for (final MapEntry<String, List<Map<String, dynamic>>> entry
        in groups.entries) {
      final String ii = entry.key;
      final List<Map<String, dynamic>> group = entry.value;

      // Expected per slot up front, so hideZero can skip BEFORE seeding
      // countStore (skipped items must not enter ip[] -- spec §2b).
      final List<int> expecteds = <int>[
        for (final PivotSlot slot in slots)
          pivotExpected(group, pivotField, slot.value, valueField),
      ];
      // ponytail: skips items all-zero AT LOAD (the flood case). An
      // already-seeded item that transitions to all-zero mid-session is NOT
      // pruned from countMap -- asset_cache is stable during a closing count,
      // and pruning would risk discarding a checker's entered discrepancy.
      // Add a prune pass only if that transition is ever observed.
      if (hideZero && expecteds.every((v) => v == 0)) continue;

      final ItemDetail? detail = itemDetailMap[ii];
      final String name = (detail != null && detail.name.isNotEmpty)
          ? detail.name
          : ii;
      final String category = detail?.category ?? '';

      final List<_PivotSlotData> slotData = <_PivotSlotData>[];
      for (int s = 0; s < slots.length; s++) {
        final PivotSlot slot = slots[s];
        final int expected = expecteds[s];
        final String countKey = '${ii}__${slot.value}';

        // Seed count store (putIfAbsent for once-only seed at qty 0).
        final CountEntry ce = countMap.putIfAbsent(
          countKey,
          () => CountEntry(ii: ii, cd: slot.value, qty: 0, planQty: expected),
        );
        // Always update planQty (asset_cache may reload with new data).
        ce.planQty = expected;

        slotData.add(
          _PivotSlotData(slot: slot, expected: expected, countKey: countKey),
        );
      }

      cards.add(
        _PivotCardData(ii: ii, name: name, category: category, slots: slotData),
      );
    }

    // Bump countRev post-frame if store grew (avoids build-time notification).
    if (countMap.length > sizeBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CustodyCountList.countRev.value++;
      });
    }

    // ── Render ──────────────────────────────────────────────────────────
    final String hintCaption = _t(0, '');
    final String planLabel = _t(1, 'Ekspektasi');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hint caption
          if (hintCaption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                hintCaption.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: _caption,
                ),
              ),
            ),

          // Item cards
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildPivotCard(cards[i], countMap, planLabel: planLabel),
          ],
        ],
      ),
    );
  }

  /// Build a single pivot card: item name (once) + category chip + N stepper
  /// cells (one per pivot slot).
  ///
  /// Mirrors [_buildItemCard] layout (white rounded card, header row, stepper
  /// cells). For exactly 2 slots, renders side-by-side Row of Expanded cells
  /// (matching DROP|PICKUP layout). For other counts, renders a vertical Column.
  Widget _buildPivotCard(
    _PivotCardData card,
    Map<String, CountEntry> countMap, {
    required String planLabel,
  }) {
    // Category chip.
    final bool isReturnable = card.category.toLowerCase() == 'returnable';
    final String chipLabel = isReturnable
        ? _t(4, 'Returnable')
        : _t(5, 'Consumable');
    final Color chipBg = isReturnable ? _accentBg : _neutralBg;
    final Color chipFg = isReturnable ? _accent : _neutralFg;

    // ── Build stepper layout ─────────────────────────────────────────
    Widget stepperLayout;

    if (card.slots.length == 2) {
      // Side-by-side: mirrors the DROP|PICKUP Row in _buildItemCard.
      final _PivotSlotData s0 = card.slots[0];
      final _PivotSlotData s1 = card.slots[1];
      final int counted0 = countMap[s0.countKey]?.qty ?? 0;
      final int counted1 = countMap[s1.countKey]?.qty ?? 0;

      stepperLayout = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildStepperCell(
              label: s0.slot.label.toUpperCase(),
              planValue: s0.expected,
              actualValue: counted0,
              status: _pivotCellStatus(counted0, s0.expected),
              planLabel: planLabel,
              isPickup: false,
              onDecrement: counted0 > 0
                  ? () => _onPivotCountChanged(
                      s0.countKey,
                      counted0 - 1,
                      card.ii,
                      s0.slot.value,
                    )
                  : null,
              onIncrement: () => _onPivotCountChanged(
                s0.countKey,
                counted0 + 1,
                card.ii,
                s0.slot.value,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStepperCell(
              label: s1.slot.label.toUpperCase(),
              planValue: s1.expected,
              actualValue: counted1,
              status: _pivotCellStatus(counted1, s1.expected),
              planLabel: planLabel,
              isPickup: false,
              onDecrement: counted1 > 0
                  ? () => _onPivotCountChanged(
                      s1.countKey,
                      counted1 - 1,
                      card.ii,
                      s1.slot.value,
                    )
                  : null,
              onIncrement: () => _onPivotCountChanged(
                s1.countKey,
                counted1 + 1,
                card.ii,
                s1.slot.value,
              ),
            ),
          ),
        ],
      );
    } else {
      // Vertical stack for 1 or 3+ slots.
      stepperLayout = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int s = 0; s < card.slots.length; s++) ...[
            if (s > 0) const SizedBox(height: 10),
            Builder(
              builder: (_) {
                final _PivotSlotData sd = card.slots[s];
                final int counted = countMap[sd.countKey]?.qty ?? 0;
                return _buildStepperCell(
                  label: sd.slot.label.toUpperCase(),
                  planValue: sd.expected,
                  actualValue: counted,
                  status: _pivotCellStatus(counted, sd.expected),
                  planLabel: planLabel,
                  isPickup: false,
                  onDecrement: counted > 0
                      ? () => _onPivotCountChanged(
                          sd.countKey,
                          counted - 1,
                          card.ii,
                          sd.slot.value,
                        )
                      : null,
                  onIncrement: () => _onPivotCountChanged(
                    sd.countKey,
                    counted + 1,
                    card.ii,
                    sd.slot.value,
                  ),
                );
              },
            ),
          ],
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hair),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000), // ~3% black -- subtle card lift
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: name + category chip ──────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  card.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: _ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chipLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: chipFg,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Stepper cells ────────────────────────────────────
          stepperLayout,
        ],
      ),
    );
  }

  Widget _buildItemCard(
    _ItemRow row,
    Map<String, ExecutionEntry> execMap, {
    required String dropLabel,
    required String pickupLabel,
    required String planLabel,
    required String returnableLabel,
    required String consumableLabel,
  }) {
    final ExecutionEntry? entry = execMap[row.key];
    final int dropActual = entry?.dropActual ?? row.planDrop;
    final int pickupActual = entry?.pickupActual ?? row.planPickup;

    // ── Drop cap resolution ──────────────────────────────────────────
    // Resolved-aware: null during loading (unresolved) or no-cap mode,
    // non-null (possibly 0) once cap is known. Threaded from _buildRows.
    final int? dropCap = row.dropCap;

    // capLabel config (read from component, with default).
    final String rawCapLabel = (widget.component['capLabel'] ?? 'Maks <max>')
        .toString();

    // ── Status derivation ────────────────────────────────────────────
    // Cap status overrides plan-relative status when value == cap.
    final _CellStatus dropStatus;
    if (dropCap != null && dropActual == dropCap) {
      final String resolvedCapLabel = rawCapLabel.replaceAll(
        '<max>',
        '$dropCap',
      );
      dropStatus = _CellStatus('capped', resolvedCapLabel);
    } else {
      dropStatus = _cellStatus(dropActual, row.planDrop, false);
    }
    final _CellStatus pickupStatus = row.isReturnable
        ? _cellStatus(pickupActual, row.planPickup, true)
        : _CellStatus('complete', '');

    // ── Drop stepper callbacks ───────────────────────────────────────
    // [+] disabled when cap != null && dropActual >= cap.
    final bool dropIncrementDisabled = dropCap != null && dropActual >= dropCap;
    final VoidCallback? dropOnIncrement = dropIncrementDisabled
        ? null
        : () => _onDropChanged(row.key, dropActual + 1);
    final VoidCallback? dropOnDecrement = dropActual > 0
        ? () => _onDropChanged(row.key, dropActual - 1)
        : null;

    // Type chip
    final String chipLabel = row.isReturnable
        ? returnableLabel
        : consumableLabel;
    final Color chipBg = row.isReturnable ? _accentBg : _neutralBg;
    final Color chipFg = row.isReturnable ? _accent : _neutralFg;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hair),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000), // ~3% black -- subtle card lift
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: name + type chip ────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  row.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: _ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chipLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: chipFg,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Stepper cells ──────────────────────────────────
          if (row.isReturnable)
            // Two side-by-side cells: DROP | PICKUP
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildStepperCell(
                    label: '\u{2193} ${dropLabel.toUpperCase()}', // ↓ DROP
                    planValue: row.planDrop,
                    actualValue: dropActual,
                    status: dropStatus,
                    planLabel: planLabel,
                    isPickup: false,
                    onDecrement: dropOnDecrement,
                    onIncrement: dropOnIncrement,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStepperCell(
                    label: '\u{2191} ${pickupLabel.toUpperCase()}', // ↑ PICKUP
                    planValue: row.planPickup,
                    actualValue: pickupActual,
                    status: pickupStatus,
                    planLabel: planLabel,
                    isPickup: true,
                    onDecrement: pickupActual > 0
                        ? () => _onPickupChanged(row.key, pickupActual - 1)
                        : null,
                    onIncrement: () =>
                        _onPickupChanged(row.key, pickupActual + 1),
                  ),
                ),
              ],
            )
          else
            // Single full-width DROP cell (consumable)
            _buildStepperCell(
              label: '\u{2193} ${dropLabel.toUpperCase()}', // ↓ DROP
              planValue: row.planDrop,
              actualValue: dropActual,
              status: dropStatus,
              planLabel: planLabel,
              isPickup: false,
              onDecrement: dropOnDecrement,
              onIncrement: dropOnIncrement,
            ),
        ],
      ),
    );
  }

  Widget _buildStepperCell({
    required String label,
    required int planValue,
    required int actualValue,
    required _CellStatus status,
    required String planLabel,
    required bool isPickup,
    VoidCallback? onDecrement,
    VoidCallback? onIncrement,
  }) {
    // Colors per status
    Color frameBg;
    Color frameBorder;
    Color numberColor;
    Color statusColor;

    switch (status.type) {
      case 'partial':
        frameBg = const Color(0xFFFFFBEB); // amber-50
        frameBorder = const Color(0xFFFCD34D); // amber-300
        numberColor = const Color(0xFFB45309); // amber-700
        statusColor = const Color(0xFFD97706); // amber-600
        break;
      case 'capped':
        frameBg = const Color(0xFFFFF7ED); // orange-50
        frameBorder = const Color(0xFFFDBA74); // orange-300
        numberColor = const Color(0xFFC2410C); // orange-700
        statusColor = const Color(0xFFEA580C); // orange-600
        break;
      case 'opportunistic':
      case 'extra':
        frameBg = const Color(0xFFF5F3FF); // violet-50
        frameBorder = const Color(0xFFC4B5FD); // violet-300
        numberColor = const Color(0xFF6D28D9); // violet-700
        statusColor = const Color(0xFF7C3AED); // violet-600
        break;
      case 'complete':
      default:
        frameBg = const Color(0xFFECFDF5); // emerald-50
        frameBorder = const Color(0xFF6EE7B7); // emerald-300
        numberColor = const Color(0xFF047857); // emerald-700
        statusColor = const Color(0xFF10B981); // emerald-500
        break;
    }

    // Label color: drop = emerald/green, pickup = violet
    final Color labelFgLeft = isPickup ? _pickupFg : _dropFg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top row: label + plan
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: labelFgLeft,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '$planLabel $planValue',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: _planMuted,
                ),
              ),
            ],
          ),
        ),
        // Stepper
        CustodyStepper(
          value: actualValue,
          onDecrement: onDecrement,
          onIncrement: onIncrement,
          min: 0,
          enabled: true,
          frameBg: frameBg,
          frameBorder: frameBorder,
          numberColor: numberColor,
          statusLine: status.label.isNotEmpty
              ? Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                    letterSpacing: 0.3,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  /// Build a read-only card for sale/purchase/refill items.
  ///
  /// Layout: item name + tx chip | direction arrow + line + desc | qty frame
  /// + optional sub-label (condition or water).
  Widget _buildReadOnlyTxCard(_ItemRow row) {
    // Per-tx config: chip label, line, desc, direction arrow, colors.
    final String chipLabel;
    final String dirArrow;
    final String lineText;
    final String descText;
    final Color cardBg;
    final Color cardBorder;
    final Color chipFg;
    final Color chipBg;
    final Color qtyFrameBg;
    final Color qtyFrameBorder;

    switch (row.txKind) {
      case 'sale':
        chipLabel = _t(11, 'Jual');
        dirArrow = '\u{2192}'; // →
        lineText = _t(12, 'Jual ke customer');
        descText = _t(13, 'Kepemilikan pindah \u{00B7} tanpa pickup');
        cardBg = Colors.white;
        cardBorder = _tealBorder;
        chipFg = _tealFg;
        chipBg = _tealBg;
        qtyFrameBg = _tealBg;
        qtyFrameBorder = _tealBorder;
        break;
      case 'purchase':
        chipLabel = _t(14, 'Beli');
        dirArrow = '\u{2190}'; // ←
        lineText = _t(15, 'Beli dari customer');
        descText = _t(16, 'Kepemilikan ke operator \u{00B7} naik ke kendaraan');
        cardBg = Colors.white;
        cardBorder = _tealBorder;
        chipFg = _tealFg;
        chipBg = _tealBg;
        qtyFrameBg = _tealBg;
        qtyFrameBorder = _tealBorder;
        break;
      case 'refill':
        chipLabel = _t(17, 'Refill');
        dirArrow = '\u{21C4}'; // ⇄
        lineText = _t(18, 'Tukar galon customer');
        descText = _t(
          19,
          'Kosong masuk \u{00B7} isi keluar \u{00B7} galon milik customer',
        );
        cardBg = Colors.white;
        cardBorder = _emeraldBorder;
        chipFg = _emeraldFg;
        chipBg = _emeraldBg;
        qtyFrameBg = _emeraldBg;
        qtyFrameBorder = _emeraldBorder;
        break;
      default:
        // Should not reach here (classifyTxKind returns 'deliver' for unknowns).
        return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000), // ~3% black -- subtle card lift
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: name + tx chip ────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  row.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: _ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chipLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: chipFg,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Direction line + description ───────────────────
          Text(
            '$dirArrow $lineText',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: chipFg,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            descText,
            style: const TextStyle(fontSize: 11, color: _caption, height: 1.3),
          ),
          const SizedBox(height: 10),

          // ── Qty frame (read-only, no stepper) ─────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: qtyFrameBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: qtyFrameBorder),
                ),
                child: Text(
                  '${row.txQty}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: chipFg,
                  ),
                ),
              ),
              // Sub-label (condition or water)
              if (row.subLabel.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: qtyFrameBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    row.subLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: chipFg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Internal helpers ─────────────────────────────────────────────────────

/// One entry in the execution store.
class ExecutionEntry {
  int dropActual;
  int pickupActual;
  final int dropPlan;
  final int pickupPlan;

  ExecutionEntry({
    required this.dropActual,
    required this.pickupActual,
    required this.dropPlan,
    required this.pickupPlan,
  });
}

/// One row in the item list.
class _ItemRow {
  final int index;
  final String key;
  final String name;
  final String txKind; // 'deliver', 'sale', 'purchase', 'refill'
  // deliver-specific
  final bool isReturnable;
  final int planDrop;
  final int planPickup;
  final String itemIi; // item id for cap lookup
  final int? dropCap; // resolved cap (null = no cap / unresolved)
  // sale/purchase/refill-specific (read-only qty + sub-label)
  final int txQty; // ps/pb/pr depending on txKind
  final String subLabel; // condition or water display label (may be '')
  const _ItemRow({
    required this.index,
    required this.key,
    required this.name,
    required this.txKind,
    this.isReturnable = false,
    this.planDrop = 0,
    this.planPickup = 0,
    this.itemIi = '',
    this.dropCap,
    this.txQty = 0,
    this.subLabel = '',
  });
}

/// Per-cell status result.
class _CellStatus {
  final String type; // partial, complete, opportunistic, extra
  final String label;
  const _CellStatus(this.type, this.label);
}

/// Classify a raw tx field value into a known transaction kind.
///
/// Returns 'deliver' for empty, absent, 'deliver', or any unrecognized value
/// (backward-compat: old docs without tx field render as deliver).
/// Returns 'sale', 'purchase', 'refill' for those exact lowercase strings.
///
/// Best-guess mapping -- when the server sends new tx types, add them here.
/// Caller is responsible for pre-lowercasing input (see _buildRows).
String classifyTxKind(String rawTx) {
  switch (rawTx) {
    case 'sale':
      return 'sale';
    case 'purchase':
      return 'purchase';
    case 'refill':
      return 'refill';
    case 'deliver':
    case '':
    default:
      return 'deliver';
  }
}

/// Map a raw condition field value to a display label.
///
/// Best-guess mapping (schema/CF not yet defined):
///   'full'  -> [penuhSlot] (text slot 21)
///   'empty' -> [kosongSlot] (text slot 20)
///   other   -> raw value as-is (degrade-safe fallback)
///   ''      -> '' (omit)
String conditionLabel(
  String rawValue, {
  required String kosongSlot,
  required String penuhSlot,
}) {
  final String v = rawValue.trim().toLowerCase();
  if (v.isEmpty) return '';
  if (v == 'full') return penuhSlot;
  if (v == 'empty') return kosongSlot;
  // Unknown value -- show raw string (degrade-safe).
  return rawValue.trim();
}

/// Map a raw water field value to a display label.
///
/// Best-guess mapping:
///   'ro'        -> [roSlot] (text slot 22)
///   other !empty -> [isiUlangSlot] (text slot 23)
///   ''          -> '' (omit)
String waterLabel(
  String rawValue, {
  required String roSlot,
  required String isiUlangSlot,
}) {
  final String v = rawValue.trim().toLowerCase();
  if (v.isEmpty) return '';
  if (v == 'ro') return roSlot;
  // Any other non-empty value -> isi ulang (degrade-safe).
  return isiUlangSlot;
}

/// Build a per-item drop cap map from filtered asset_cache docs.
///
/// Iterates [capDocs] (already filtered by dropCapSearch via
/// filterDriverHomeDocs), reads [capKeyField] (item id, e.g. 'ii') and
/// [capValueField] (cap quantity, e.g. 'qt') from each doc, and builds
/// a `{itemId -> capQty}` map.
///
/// Duplicate item ids: last-write-wins (asset_cache docs are unique per
/// lv+ii+cd by doc-id convention, so duplicates are unexpected; last-write
/// is a safe degrade).
///
/// Pure function for testability -- no Rx, no global state.
Map<String, int> buildDropCapMap(
  List<Map<String, dynamic>> capDocs, {
  required String capKeyField,
  required String capValueField,
}) {
  final Map<String, int> result = <String, int>{};
  for (final Map<String, dynamic> doc in capDocs) {
    final String itemId = (doc[capKeyField] ?? '').toString().trim();
    if (itemId.isEmpty) continue;
    final int qty =
        int.tryParse((doc[capValueField] ?? '0').toString().trim()) ?? 0;
    result[itemId] = qty;
  }
  return result;
}

/// Intermediate data for one pivot card (one grouped item).
class _PivotCardData {
  final String ii;
  final String name;
  final String category;
  final List<_PivotSlotData> slots;
  const _PivotCardData({
    required this.ii,
    required this.name,
    required this.category,
    required this.slots,
  });
}

/// Intermediate data for one slot within a pivot card.
class _PivotSlotData {
  final PivotSlot slot;
  final int expected;
  final String countKey;
  const _PivotSlotData({
    required this.slot,
    required this.expected,
    required this.countKey,
  });
}

/// One slot in a pivot variant's stepper layout.
///
/// Parsed from the component's `slots` config string.
/// Format: `value^Label` entries separated by `~`.
/// Example: `"full^Penuh~empty^Kosong"` -> two PivotSlots.
///
/// Public for testability (imported by test/item_execution_list_test.dart).
class PivotSlot {
  /// The raw value matched against the pivot field (e.g. `"full"`, `"empty"`).
  final String value;

  /// The display label for this slot (e.g. `"Penuh"`, `"Kosong"`).
  final String label;

  const PivotSlot({required this.value, required this.label});
}

/// Parse a pivot `slots` config string into a list of [PivotSlot].
///
/// Format: `value^Label` entries separated by `~`.
/// Malformed entries (no `^`, empty value) are skipped.
/// Empty/whitespace-only input returns an empty list.
///
/// Pure function for testability.
List<PivotSlot> parsePivotSlots(String raw) {
  if (raw.trim().isEmpty) return const <PivotSlot>[];
  final List<PivotSlot> result = <PivotSlot>[];
  final List<String> entries = raw.split('~');
  for (final String entry in entries) {
    final String trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    final int caret = trimmed.indexOf('^');
    if (caret < 0) continue; // malformed: no ^ separator
    final String value = trimmed.substring(0, caret).trim();
    final String label = trimmed.substring(caret + 1).trim();
    if (value.isEmpty) continue; // value is required
    result.add(PivotSlot(value: value, label: label));
  }
  return result;
}

/// Group a list of docs by a key field, preserving insertion order.
///
/// Docs with an empty/absent key are skipped. Returns a plain `Map` (Dart maps
/// are insertion-ordered by default).
///
/// Pure function for testability.
Map<String, List<Map<String, dynamic>>> groupDocsByKey(
  List<Map<String, dynamic>> docs,
  String groupKey,
) {
  final Map<String, List<Map<String, dynamic>>> result =
      <String, List<Map<String, dynamic>>>{};
  for (final Map<String, dynamic> doc in docs) {
    final String key = (doc[groupKey] ?? '').toString().trim();
    if (key.isEmpty) continue;
    result.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(doc);
  }
  return result;
}

/// Resolve the expected quantity for one pivot slot within a group of docs.
///
/// Finds the first doc where `doc[pivotField] == slotValue` and returns
/// `coerceNum(doc[valueField]).toInt()`. Returns 0 if no matching doc exists.
///
/// Pure function for testability.
int pivotExpected(
  List<Map<String, dynamic>> group,
  String pivotField,
  String slotValue,
  String valueField,
) {
  for (final Map<String, dynamic> doc in group) {
    final String pv = (doc[pivotField] ?? '').toString().trim();
    if (pv == slotValue) {
      return coerceNum(doc[valueField]).toInt();
    }
  }
  return 0;
}
