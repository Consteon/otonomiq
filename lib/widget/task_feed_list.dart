import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'admin_create_task_support.dart'; // AdminCreateTaskSupport.setCustomer
import 'admin_home_support.dart'; // evaluateGate
import 'driver_home_support.dart';
import 'panel_card_support.dart';
import 'receipt_doc.dart'; // formatThousands, formatReceiptDate
import 'task_item_builder.dart'; // TaskItemBuilder.draftRev

/// TASK_FEED_LIST — grouped task card list for P10 TaskFeed.
///
/// Reads task docs (same search as RouteFeedHeader), groups by tst
/// (assigned+on_delivery → failed → completed), renders per-card layout with
/// state-specific styling, drop/pickup badges, and per-state footer.
///
/// allDone (no assigned/on_delivery tasks) shows an emerald banner + sticky
/// "Kembali ke Gudang" button.
///
/// MODE FLAT (groupField empty): self-contained search bar + count header +
/// avatar cards + empty state. Config: iconField, searchHint, countLabel,
/// emptyText. No status grouping, no delivery badges, no return-gate
/// evaluation. Used for customer-picker in Admin P1.
///
/// Read-only: no txfController, no saveSend, no history.
class TaskFeedList extends StatefulWidget {
  const TaskFeedList({
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

  /// Per-scrName search controllers for FLAT mode local search bar.
  /// Cached SDUI widgets persist across nav; text cleared on route change
  /// via [clearFlatSearch] (called from buildPage in ui_component.dart).
  ///
  /// This map OWNS the controllers — [_TaskFeedListState] must never dispose
  /// them (overlapping States for one scrName share an instance).
  static final Map<String, TextEditingController> _flatSearchControllers = {};

  /// Clear FLAT-mode search text for [scrName]. Called from buildPage
  /// (ui_component.dart) on route change / screen reload.
  static void clearFlatSearch(String scrName) {
    _flatSearchControllers[scrName]?.clear();
  }

  /// Aggregate badge data for a single row in FLAT mode.
  ///
  /// SUMs [sumField] across [docs] matching [rawSearch] (with per-row token
  /// `{idField}` replaced by [rowId]). Returns `({int rows, int sum})`:
  /// - rows == 0: no matching docs (client not seeded).
  /// - rows > 0, sum == 0: seeded but zero outstanding.
  /// - rows > 0, sum > 0: outstanding count.
  ///
  /// Mirrors [PickerList.countForRow] shape: autheniumDecode, token substitution,
  /// unresolved-token guard. Adds numeric summation via [coerceNum].
  static ({int rows, int sum}) aggregateForRow(
    List<Map<String, dynamic>> docs,
    String rawSearch,
    String idField,
    String rowId,
    String sumField,
  ) {
    final String trimmed = rawSearch.trim();
    if (trimmed.isEmpty) return (rows: 0, sum: 0);
    final String decoded = autheniumDecode(trimmed) ?? trimmed;
    final String resolved = decoded.replaceAll('{$idField}', rowId);
    // Unresolved row token (or empty rowId) -> bail.
    if (resolved.contains('{') || rowId.isEmpty) return (rows: 0, sum: 0);
    int matchedRows = 0;
    int total = 0;
    for (final Map<String, dynamic> d in docs) {
      if (evaluateGate(d, resolved)) {
        matchedRows++;
        total += coerceNum(d[sumField]).toInt();
      }
    }
    return (rows: matchedRows, sum: total);
  }

  @override
  State<TaskFeedList> createState() => _TaskFeedListState();
}

class _TaskFeedListState extends State<TaskFeedList> {
  List<String> _textArray = [];
  String _taskCode = '';
  String _returnGateCode =
      ''; // return-CTA gate (vehicle_check rt) subscription
  String _badgeCode =
      ''; // badge-table (asset_cache) subscription for FLAT mode
  TextEditingController? _searchController;

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
    // Create search controller for FLAT mode (groupField empty).
    // GROUPED screens skip this — controller stays null.
    final String gf = (widget.component['groupField'] ?? 'tst').toString();
    if (gf.isEmpty) {
      _searchController = TaskFeedList._flatSearchControllers.putIfAbsent(
        widget.scrName,
        () => TextEditingController(),
      );
    }
  }

  // No dispose of _searchController: the static _flatSearchControllers map owns
  // it, not this State. Two States for the same scrName can overlap during an
  // SDUI page rebuild (new initState runs before old dispose) and share one
  // controller instance — disposing here left the live State holding a disposed
  // controller ("A TextEditingController was used after being disposed").
  // ponytail: one controller per FLAT screen name, never freed — same lifetime
  // as the cached widget in linkElement[scrName]. Bounded by screen count.

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (15 slots):
  ///  [0]  "Stop Berikutnya"
  ///  [1]  "Pilih sesuai kondisi lapangan"
  ///  [2]  "Dilaporkan Gagal"
  ///  [3]  "Sudah Selesai"
  ///  [4]  "Pickup Only"
  ///  [5]  "drop"
  ///  [6]  "pickup"
  ///  [7]  "Mulai Eksekusi"
  ///  [8]  "✓ Selesai"
  ///  [9]  "Customer confirmed" (HIDDEN)
  ///  [10] "! Dilaporkan gagal — menunggu admin reschedule"
  ///  [11] "🎉"
  ///  [12] "Semua Stop Selesai"
  ///  [13] "Lo bisa kembali ke gudang untuk closing check."
  ///  [14] "Kembali ke Gudang"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }

    // Return-CTA gate table (vehicle_check) — spec (4).md §OPEN 3 option (a):
    // self-gate the "Kembali ke Gudang" entry-point on rt=pending so it hides
    // after handover (rt=returned). Mirrors navActionCard's gate subscription.
    final String rawReturnGateTable =
        (widget.component['returnGateTable'] ?? '').toString().trim();
    if (rawReturnGateTable.isNotEmpty) {
      final TablePath gtp = parseTablePath(rawReturnGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        _returnGateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
        subscribeToMapCollection(
          appVid,
          gtp.tableDocId,
          gtp.subColl,
          _returnGateCode,
        );
      }
    }

    // Badge table (asset_cache for outstanding/seed badge in FLAT mode).
    final String rawBadgeTable = (widget.component['badgeTable'] ?? '')
        .toString()
        .trim();
    if (rawBadgeTable.isNotEmpty) {
      final TablePath btp = parseTablePath(rawBadgeTable);
      if (btp.tableDocId.isNotEmpty) {
        _badgeCode = '$appVid/${btp.tableDocId}/${btp.subColl}';
        subscribeToMapCollection(
          appVid,
          btp.tableDocId,
          btp.subColl,
          _badgeCode,
        );
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredTasks() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final List<Map<String, dynamic>> filtered = rawSearch.isEmpty
        ? docs
        : filterDriverHomeDocs(docs, rawSearch, widget.scrName);

    // Sort by sortField when configured (FLAT walkin-history: t desc).
    // Empty sortField (customer-list, driver P10) = no sort = current order.
    final String sortField = (widget.component['sortField'] ?? '')
        .toString()
        .trim();
    if (sortField.isNotEmpty) {
      final bool desc =
          (widget.component['sortDir'] ?? '').toString().trim().toLowerCase() ==
          'desc';
      filtered.sort((a, b) {
        final num va = coerceNum(a[sortField]);
        final num vb = coerceNum(b[sortField]);
        return desc ? vb.compareTo(va) : va.compareTo(vb);
      });
    }

    // Unconditionally exclude load_rejected tasks. Raw state-field compare,
    // NOT stopStatusOf (load_rejected normalizes to pending). Key on the
    // configured groupField so the exclusion reads the same field as the
    // bucket split; fall back to 'tst' in FLAT mode (groupField empty),
    // because excludeByStatus short-circuits only on an empty excludeStatus,
    // never on an empty statusField.
    final String groupField = (widget.component['groupField'] ?? 'tst')
        .toString();
    return excludeByStatus(
      filtered,
      kDefaultExcludeStatus,
      statusField: groupField.isEmpty ? 'tst' : groupField,
    );
  }

  void _onCardTap(Map<String, dynamic> task) {
    final String route = (widget.component['route'] ?? '').toString().trim();
    if (route.isEmpty) return;

    // Dispatch the tapped task's VID into #ACTIVE_TASK so P11 widgets
    // can resolve {activeTaskVid} in their search strings.
    final String idField = (widget.component['idField'] ?? 'tnm').toString();
    final String taskVid = (task[idField] ?? '').toString().trim();
    if (taskVid.isNotEmpty) {
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#ACTIVE_TASK': taskVid})),
      );
    }

    // Dead-route silent skip (P11 DeliveryWorkspace may not be built).
    routeStack.push(route);
    gotoRoute(route);
  }

  void _onReturnTap() {
    final String returnRoute = (widget.component['returnRoute'] ?? '')
        .toString()
        .trim();
    if (returnRoute.isEmpty) return;
    // Dead-route silent skip (P12 ReturnVehicle not built yet).
    routeStack.push(returnRoute);
    gotoRoute(returnRoute);
  }

  /// Flat-mode card tap handler. When wizardKey is configured, captures
  /// customer fields (kl/kn/al) into the wizard draft and dispatches kl into
  /// screenTx for P2 _republishClient. When wizardKey is absent, delegates
  /// to the original _onCardTap for backward-compat.
  void _onFlatCardTap(Map<String, dynamic> task) {
    final String route = (widget.component['route'] ?? '').toString().trim();
    if (route.isEmpty) return;

    final String wizardKey = (widget.component['wizardKey'] ?? '')
        .toString()
        .trim();
    final String idField = (widget.component['idField'] ?? 'tnm').toString();
    final String titleField = (widget.component['titleField'] ?? 'kn')
        .toString();
    final String addressField = (widget.component['addressField'] ?? 'al')
        .toString();
    final String picField = (widget.component['picField'] ?? 'pic').toString();

    if (wizardKey.isNotEmpty) {
      // Admin wizard: capture customer into draft
      final String kl = (task[idField] ?? '').toString().trim();
      final String kn = (task[titleField] ?? '').toString().trim();
      final String al = (task[addressField] ?? '').toString().trim();
      final String pic = (task[picField] ?? '').toString().trim();
      // If the user picked a DIFFERENT customer (or this is the first pick),
      // wipe stale items + vehicle from the previous customer's draft.
      // Same-customer re-tap preserves in-progress items (resume).
      final String priorKl =
          (AdminCreateTaskSupport.getCustomer(wizardKey)?['kl'] ?? '')
              .toString()
              .trim();
      if (priorKl != kl) {
        AdminCreateTaskSupport.clearDraft(wizardKey);
        // Also wipe the stale screenTx vehicle token ('vv') so a customer
        // switch cannot carry the prior vehicle into the P3 pre-highlight or
        // the submit fallback. Symmetric with the kl re-dispatch below.
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'vv': ''})),
        );
      }
      AdminCreateTaskSupport.setCustomer(
        wizardKey,
        kl: kl,
        kn: kn,
        al: al,
        pic: pic,
      );
      // Dispatch kl into screenTx bare key for P2 _republishClient
      if (kl.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'kl': kl})),
        );
      }
      TaskItemBuilder.draftRev.value++;
    } else {
      // Non-wizard flat mode: publish the tapped row's id into #ACTIVE_TASK
      // (backward-compat) AND a bare screenTx key named after idField, so the
      // destination page's {idField} token resolves (e.g. walk-in history →
      // PRN keyed search "nno◼{nno}"). Mirrors NOTA_CREATE_SUBMIT, which
      // injects bare 'nno' on the transaction-flow route to the SAME page;
      // without this the history-flow reprint fails "unresolved token".
      final String taskVid = (task[idField] ?? '').toString().trim();
      if (taskVid.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(
            ScreenTransaction({'#ACTIVE_TASK': taskVid, idField: taskVid}),
          ),
        );
      }
    }

    routeStack.push(route);
    gotoRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch vehicleId to register Obx dependency (search uses {vehicleId}).
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;
      dhState.activeTrip.value; // register activeTrip dependency (GAP B fix)

      final List<Map<String, dynamic>> tasks = _getFilteredTasks();

      // Component field overrides
      final String groupField = (widget.component['groupField'] ?? 'tst')
          .toString();
      final String idField = (widget.component['idField'] ?? 'tnm').toString();
      final String titleField = (widget.component['titleField'] ?? 'kn')
          .toString();
      final String addressField = (widget.component['addressField'] ?? 'al')
          .toString();
      final String iconField = (widget.component['iconField'] ?? '').toString();
      final String searchHint = (widget.component['searchHint'] ?? '')
          .toString();
      final String countLabel = (widget.component['countLabel'] ?? '')
          .toString();
      final String emptyText = (widget.component['emptyText'] ?? '').toString();

      // ── FLAT mode (groupField empty) ─────────────────────────────────
      // When groupField is present but empty in JSON, render a simple
      // ungrouped card list with no status grouping, no delivery badges,
      // no return-gate evaluation. Absent groupField defaults to 'tst'
      // (GROUPED, backward-compatible with driver P10).
      if (groupField.isEmpty) {
        // Badge config (FLAT-only: per-row outstanding / seed chip).
        final List<Map<String, dynamic>> badgeDocs = _badgeCode.isNotEmpty
            ? List<Map<String, dynamic>>.from(
                mapTableContent[_badgeCode] ?? const [],
              )
            : const [];
        final String badgeSearch = (widget.component['badgeSearch'] ?? '')
            .toString()
            .trim();
        final String badgeField = (widget.component['badgeField'] ?? '')
            .toString()
            .trim();
        final String badgeLabel = (widget.component['badgeLabel'] ?? '')
            .toString()
            .trim();
        final String seedLabel = (widget.component['seedLabel'] ?? '')
            .toString()
            .trim();
        final String dateField = (widget.component['dateField'] ?? '')
            .toString()
            .trim();
        final String amountField = (widget.component['amountField'] ?? '')
            .toString()
            .trim();
        final String addressEmpty = (widget.component['addressEmpty'] ?? '')
            .toString()
            .trim();

        return _buildFlatList(
          tasks,
          idField: idField,
          titleField: titleField,
          addressField: addressField,
          iconField: iconField,
          searchHint: searchHint,
          countLabel: countLabel,
          emptyText: emptyText,
          badgeDocs: badgeDocs,
          badgeSearch: badgeSearch,
          badgeField: badgeField,
          badgeLabel: badgeLabel,
          seedLabel: seedLabel,
          dateField: dateField,
          amountField: amountField,
          addressEmpty: addressEmpty,
        );
      }

      final String typeField = (widget.component['typeField'] ?? 'tty')
          .toString();
      final String itemsField = (widget.component['itemsField'] ?? 'it')
          .toString();
      final String dropField = (widget.component['dropField'] ?? 'pd')
          .toString();
      final String pickupField = (widget.component['pickupField'] ?? 'pp')
          .toString();
      final String actualDropField =
          (widget.component['actualDropField'] ?? 'ad').toString();
      final String actualPickupField =
          (widget.component['actualPickupField'] ?? 'ap').toString();

      // Group tasks by normalized state + assign global stopNumber
      final List<_TaskEntry> pendingTasks = [];
      final List<_TaskEntry> failedTasks = [];
      final List<_TaskEntry> completedTasks = [];
      int globalIndex = 0;

      for (final doc in tasks) {
        globalIndex++;
        final String status = stopStatusOf(doc, tstField: groupField);
        final _TaskEntry entry = _TaskEntry(
          doc: doc,
          stopNumber: globalIndex,
          status: status,
        );
        if (status == 'failed') {
          failedTasks.add(entry);
        } else if (status == 'done') {
          completedTasks.add(entry);
        } else {
          // pending (assigned, on_delivery, active, unknown)
          pendingTasks.add(entry);
        }
      }

      final bool allDone = pendingTasks.isEmpty;

      // Return-CTA gate (spec (4).md §OPEN 3 option a): opt-in. With
      // returnGateSearch (+ table) configured, the "Kembali ke Gudang"
      // entry-point shows ONLY while the gate matches (rt=pending); after
      // handover (rt=returned) it stops matching -> CTA hidden so the driver
      // can't re-return. Unconfigured -> always shown (backward-compatible).
      // evaluateGateSearch reads mapTableContent[_returnGateCode], registering
      // the reactive dependency so the CTA drops live when rt flips.
      final String rawReturnGateSearch =
          (widget.component['returnGateSearch'] ?? '').toString().trim();
      final bool returnGated =
          rawReturnGateSearch.isNotEmpty && _returnGateCode.isNotEmpty;
      final bool returnGateOpen =
          !returnGated ||
          evaluateGateSearch(
            _returnGateCode,
            rawReturnGateSearch,
            widget.scrName,
          );

      // Text slots
      final String assignedLabel = _t(0, 'Stop Berikutnya');
      final String assignedSubtitle = _t(1, 'Pilih sesuai kondisi lapangan');
      final String failedLabel = _t(2, 'Dilaporkan Gagal');
      final String completedLabel = _t(3, 'Sudah Selesai');

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
            // ── Assigned section ───────────────────────────────────
            if (pendingTasks.isNotEmpty) ...[
              _buildSectionHeader(
                '$assignedLabel \u{00B7} ${pendingTasks.length}',
                const Color(0xFF374151), // gray-700
                subtitle: assignedSubtitle,
              ),
              const SizedBox(height: 8),
              for (final entry in pendingTasks)
                _buildTaskCard(
                  entry: entry,
                  idField: idField,
                  titleField: titleField,
                  addressField: addressField,
                  typeField: typeField,
                  itemsField: itemsField,
                  dropField: dropField,
                  pickupField: pickupField,
                  actualDropField: actualDropField,
                  actualPickupField: actualPickupField,
                ),
            ],

            // ── Failed section ────────────────────────────────────
            if (failedTasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(
                '$failedLabel \u{00B7} ${failedTasks.length}',
                const Color(0xFFD97706), // amber-600
              ),
              const SizedBox(height: 8),
              for (final entry in failedTasks)
                _buildTaskCard(
                  entry: entry,
                  idField: idField,
                  titleField: titleField,
                  addressField: addressField,
                  typeField: typeField,
                  itemsField: itemsField,
                  dropField: dropField,
                  pickupField: pickupField,
                  actualDropField: actualDropField,
                  actualPickupField: actualPickupField,
                ),
            ],

            // ── Completed section ─────────────────────────────────
            if (completedTasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(
                '$completedLabel \u{00B7} ${completedTasks.length}',
                const Color(0xFF6B7280), // textDim
              ),
              const SizedBox(height: 8),
              for (final entry in completedTasks)
                _buildTaskCard(
                  entry: entry,
                  idField: idField,
                  titleField: titleField,
                  addressField: addressField,
                  typeField: typeField,
                  itemsField: itemsField,
                  dropField: dropField,
                  pickupField: pickupField,
                  actualDropField: actualDropField,
                  actualPickupField: actualPickupField,
                ),
            ],

            // ── allDone banner + return CTA (gated: hidden after handover) ──
            if (allDone && tasks.isNotEmpty && returnGateOpen) ...[
              const SizedBox(height: 16),
              _buildAllDoneBanner(),
              const SizedBox(height: 12),
              _buildReturnButton(),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildSectionHeader(String label, Color color, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: color,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Color(0xFF9CA3AF), // textDim
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTaskCard({
    required _TaskEntry entry,
    required String idField,
    required String titleField,
    required String addressField,
    required String typeField,
    required String itemsField,
    required String dropField,
    required String pickupField,
    required String actualDropField,
    required String actualPickupField,
  }) {
    final Map<String, dynamic> doc = entry.doc;
    final String status = entry.status;
    final bool isDone = status == 'done';
    final bool isFailed = status == 'failed';
    final bool isPending = !isDone && !isFailed;

    // Field reads
    final String taskId = (doc[idField] ?? '').toString().trim();
    final String customer = (doc[titleField] ?? '').toString().trim();
    final String address = (doc[addressField] ?? '').toString().trim();
    final String taskType = (doc[typeField] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    // Per-task drop/pickup (actual-over-plan: resolveItemQty is self-gating --
    // pre-execution items carry ad:null/ap:null from toItMap(), so the null
    // check falls back to plan).
    final dynamic rawItems = doc[itemsField];
    int dropCount = 0;
    int pickupCount = 0;
    if (rawItems is List) {
      for (final dynamic item in rawItems) {
        if (item is! Map) continue;
        dropCount += resolveItemQty(item, dropField, actualDropField);
        pickupCount += resolveItemQty(item, pickupField, actualPickupField);
      }
    }

    // Card styling per state
    Color cardBg;
    double cardOpacity;
    Color borderLeftColor;
    if (isFailed) {
      cardBg = const Color(0xFFFFFBEB); // amber-50
      cardOpacity = 0.75;
      borderLeftColor = const Color(0xFFD97706); // amber-600
    } else if (isDone) {
      cardBg = Colors.white;
      cardOpacity = 0.75;
      borderLeftColor = const Color(0xFF10B981); // emerald-500
    } else {
      cardBg = Colors.white;
      cardOpacity = 1.0;
      borderLeftColor = const Color(0xFF4338CA); // indigo-700
    }

    // State chip
    final _StateChip stateChip = _stateChipFor(status, taskType);

    // Text slots for footer
    final String ctaLabel = _t(7, 'Mulai Eksekusi');
    final String completedFooter = _t(8, '\u{2713} Selesai');
    final String failedFooter = _t(
      10,
      '! Dilaporkan gagal \u{2014} menunggu admin reschedule',
    );
    final String dropLabel = _t(5, 'drop');
    final String pickupLabel = _t(6, 'pickup');
    final String pickupOnlyLabel = _t(4, 'Pickup Only');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isPending ? () => _onCardTap(doc) : null,
        child: Opacity(
          opacity: cardOpacity,
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left 3px border
                  Container(width: 3, color: borderLeftColor),
                  // Card content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header row: avatar + id/chip/customer + stateChip ──
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar
                              _buildAvatar(entry),
                              const SizedBox(width: 10),
                              // Center: id + optional pickup chip + customer
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // ID row + pickup chip
                                    Row(
                                      children: [
                                        Text(
                                          taskId,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                        if (taskType == 'pickup_return') ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFFF5F3FF,
                                              ), // violet-50
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              pickupOnlyLabel,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Color(
                                                  0xFF7C3AED,
                                                ), // violet-600
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      customer,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1F2937),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // State chip
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: stateChip.bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  stateChip.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: stateChip.fg,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // ── Body (indent 42px = 32 avatar + 10 gap) ──
                          Padding(
                            padding: const EdgeInsets.only(left: 42),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Address
                                if (address.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    address,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                // Distance line: HIDDEN per decision 1

                                // Drop/pickup badges
                                if (dropCount > 0 || pickupCount > 0) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (dropCount > 0)
                                        _buildBadge(
                                          '\u{2193} $dropCount $dropLabel',
                                          isDone
                                              ? const Color(
                                                  0xFFDCFCE7,
                                                ) // emerald-100
                                              : const Color(
                                                  0xFFEEF2FF,
                                                ), // indigo-50
                                          isDone
                                              ? const Color(
                                                  0xFF16A34A,
                                                ) // emerald-600
                                              : const Color(
                                                  0xFF4338CA,
                                                ), // indigo-700
                                        ),
                                      if (dropCount > 0 && pickupCount > 0)
                                        const SizedBox(width: 6),
                                      if (pickupCount > 0)
                                        _buildBadge(
                                          '\u{2191} $pickupCount $pickupLabel',
                                          const Color(0xFFF5F3FF), // violet-50
                                          const Color(0xFF7C3AED), // violet-600
                                        ),
                                    ],
                                  ),
                                ],

                                // ── Per-state footer ──────────────────────
                                const SizedBox(height: 8),
                                if (isPending) ...[
                                  // CTA banner "MULAI EKSEKUSI"
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF4338CA,
                                      ), // indigo-700
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      ctaLabel.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ] else if (isDone) ...[
                                  Text(
                                    completedFooter,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF10B981), // emerald-500
                                    ),
                                  ),
                                  // customerConfirmed: HIDDEN per decision 3
                                ] else if (isFailed) ...[
                                  Text(
                                    failedFooter,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFD97706), // amber-600
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(_TaskEntry entry) {
    if (entry.status == 'done') {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7), // emerald-100
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text(
          '\u{2713}', // ✓
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF10B981), // emerald-500
          ),
        ),
      );
    }
    if (entry.status == 'failed') {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7), // amber-100
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text(
          '!',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFD97706), // amber-600
          ),
        ),
      );
    }
    // Assigned / on_delivery: stopNumber
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // slate-100
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '${entry.stopNumber}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569), // slate-600
        ),
      ),
    );
  }

  _StateChip _stateChipFor(String status, String taskType) {
    switch (status) {
      case 'done':
        return const _StateChip(
          'SELESAI',
          Color(0xFFDCFCE7), // green-100
          Color(0xFF16A34A), // green-600
        );
      case 'failed':
        return const _StateChip(
          'GAGAL',
          Color(0xFFFEF3C7), // amber-100
          Color(0xFFD97706), // amber-600
        );
      default:
        // Pending/active: derive from taskType
        if (taskType == 'pickup_return') {
          return const _StateChip(
            'AMBIL',
            Color(0xFFF5F3FF), // violet-50
            Color(0xFF7C3AED), // violet-600
          );
        }
        return const _StateChip(
          'KIRIM',
          Color(0xFFF3F4F6), // gray-100
          Color(0xFF6B7280), // gray-500
        );
    }
  }

  Widget _buildBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _buildAllDoneBanner() {
    final String emoji = _t(11, '\u{1F389}');
    final String title = _t(12, 'Semua Stop Selesai');
    final String body = _t(
      13,
      'Lo bisa kembali ke gudang untuk closing check.',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7), // emerald-100
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF065F46), // emerald-800
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF047857), // emerald-700
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReturnButton() {
    final String label = _t(14, 'Kembali ke Gudang');
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _onReturnTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4338CA), // indigo-700
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ── FLAT mode rendering ──────────────────────────────────────────────

  Widget _buildFlatList(
    List<Map<String, dynamic>> tasks, {
    required String idField,
    required String titleField,
    required String addressField,
    required String iconField,
    required String searchHint,
    required String countLabel,
    required String emptyText,
    List<Map<String, dynamic>> badgeDocs = const [],
    String badgeSearch = '',
    String badgeField = '',
    String badgeLabel = '',
    String seedLabel = '',
    String dateField = '',
    String amountField = '',
    String addressEmpty = '',
  }) {
    // Lazy-init: handles edge case where State persisted from GROUPED to FLAT
    // (JSON changed without rebuilding State — initState skipped controller).
    final TextEditingController ctrl = _searchController ??= TaskFeedList
        ._flatSearchControllers
        .putIfAbsent(widget.scrName, () => TextEditingController());

    // Local search filter (plain user text — NOT a server search field,
    // so NO autheniumDecode). Config search was already decoded upstream
    // by filterDriverHomeDocs.
    final String query = ctrl.text.trim().toLowerCase();
    final List<Map<String, dynamic>> filtered = query.isEmpty
        ? tasks
        : tasks.where((task) {
            final String title = (task[titleField] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final String address = (task[addressField] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            return title.contains(query) || address.contains(query);
          }).toList();

    final int count = filtered.length;

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
          // ── Search bar ────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6), // gray-100 (surfaceAlt)
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)), // border
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Text(
                  '\u{1F50D}', // magnifying glass emoji
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9CA3AF), // textDim
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1F2937), // text
                    ),
                    decoration: InputDecoration(
                      hintText: searchHint.isNotEmpty ? searchHint : 'Cari...',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9CA3AF), // textDim
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Count header ──────────────────────────────────────
          if (countLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '$count $countLabel'.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF), // textDim
                  letterSpacing: 0.7,
                ),
              ),
            ),

          // ── Cards or empty state ──────────────────────────────
          if (count == 0)
            _buildFlatEmptyState(emptyText)
          else
            for (final task in filtered)
              _buildFlatCard(
                task,
                titleField: titleField,
                addressField: addressField,
                iconField: iconField,
                idField: idField,
                badgeDocs: badgeDocs,
                badgeSearch: badgeSearch,
                badgeField: badgeField,
                badgeLabel: badgeLabel,
                seedLabel: seedLabel,
                dateField: dateField,
                amountField: amountField,
                addressEmpty: addressEmpty,
              ),
        ],
      ),
    );
  }

  Widget _buildFlatCard(
    Map<String, dynamic> task, {
    required String titleField,
    required String addressField,
    required String iconField,
    String idField = '',
    List<Map<String, dynamic>> badgeDocs = const [],
    String badgeSearch = '',
    String badgeField = '',
    String badgeLabel = '',
    String seedLabel = '',
    String dateField = '',
    String amountField = '',
    String addressEmpty = '',
  }) {
    final String title = (task[titleField] ?? '').toString().trim();
    final String rawAddress = (task[addressField] ?? '').toString().trim();
    final String address = rawAddress.isNotEmpty ? rawAddress : addressEmpty;

    // Avatar content: iconField doc value -> first letter of title -> empty
    String avatarContent = '';
    if (iconField.isNotEmpty) {
      avatarContent = (task[iconField] ?? '').toString().trim();
    }
    if (avatarContent.isEmpty && title.isNotEmpty) {
      avatarContent = title[0].toUpperCase();
    }

    // Badge chip (outstanding or seed) -- only when badgeSearch configured.
    Widget? badgeChip;
    if (badgeSearch.isNotEmpty && idField.isNotEmpty) {
      final String rowId = (task[idField] ?? '').toString().trim();
      final ({int rows, int sum}) agg = TaskFeedList.aggregateForRow(
        badgeDocs,
        badgeSearch,
        idField,
        rowId,
        badgeField,
      );
      if (agg.rows == 0 && seedLabel.isNotEmpty) {
        // No matched docs = not seeded (amber chip).
        badgeChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7), // amber-100
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            seedLabel,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB45309), // amber-700
            ),
          ),
        );
      } else if (agg.rows > 0) {
        // Matched docs = seeded; show sum (violet chip).
        badgeChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF), // violet-50
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '\u{2191} ${agg.sum} $badgeLabel'.trim(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6D28D9), // violet-700
            ),
          ),
        );
      }
    }

    // ── Right column: amount + date (FLAT walkin-history) ──────────
    Widget? rightCol;
    if (amountField.isNotEmpty || dateField.isNotEmpty) {
      final List<Widget> rightChildren = [];

      if (amountField.isNotEmpty) {
        final int amt = coerceNum(task[amountField]).toInt();
        rightChildren.add(
          Text(
            'Rp ${formatThousands(amt)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937), // text
            ),
          ),
        );
      }

      if (dateField.isNotEmpty) {
        final dynamic rawDate = task[dateField];
        String dateStr = '';
        if (rawDate != null) {
          final num numVal = coerceNum(rawDate);
          if (numVal != 0) {
            dateStr = formatReceiptDate(numVal.toInt());
          } else {
            dateStr = rawDate.toString().trim();
          }
        }
        if (dateStr.isNotEmpty) {
          if (rightChildren.isNotEmpty) {
            rightChildren.add(const SizedBox(height: 2));
          }
          rightChildren.add(
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF9CA3AF), // textDim
              ),
            ),
          );
        }
      }

      if (rightChildren.isNotEmpty) {
        rightCol = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: rightChildren,
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _onFlatCardTap(task),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, // surface
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)), // border
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar: 40x40, radius 10, slate-100 bg
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9), // slate-100
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  avatarContent,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              // Middle: title + subtitle (flex, minWidth 0 via Expanded)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937), // text
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        address,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280), // textMid
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (badgeChip != null) ...[
                      const SizedBox(height: 6),
                      badgeChip,
                    ],
                  ],
                ),
              ),
              // Right column: amount + date (only when configured)
              if (rightCol != null) ...[const SizedBox(width: 8), rightCol],
              const SizedBox(width: 12),
              // Chevron
              const Text(
                '\u{203A}', // single right-pointing angle quotation mark
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF9CA3AF), // textDim
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlatEmptyState(String emptyText) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '\u{1F50D}', // magnifying glass emoji
              style: TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 12),
            Text(
              emptyText.isNotEmpty ? emptyText : 'Tidak ada data',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280), // textMid
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Coba kata kunci lain',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF), // textDim
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Internal: one entry in the grouped task list.
class _TaskEntry {
  final Map<String, dynamic> doc;
  final int stopNumber;
  final String status; // normalized: 'done', 'failed', 'pending', 'active'
  const _TaskEntry({
    required this.doc,
    required this.stopNumber,
    required this.status,
  });
}

/// Internal: state chip display config.
class _StateChip {
  final String label;
  final Color bg;
  final Color fg;
  const _StateChip(this.label, this.bg, this.fg);
}
