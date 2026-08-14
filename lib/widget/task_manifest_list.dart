import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../screen_session.dart';
import 'admin_create_task_support.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// TASK_MANIFEST_LIST -- per-task accordion list + aggregate badges (P5).
///
/// Reads the task collection for this vehicle+today. Displays a header
/// with total task/item-line counts, then per-task rows with numbered badges,
/// customer name, address, and drop/pickup pills. Tapping a row toggles an
/// inline item-line accordion. The [ROUTE:taskDetail] nav is PARKED (detail
/// page unbuilt); chevron is local expand only.
///
/// Read-only: no txfController, no saveSend, no history.
class TaskManifestList extends StatefulWidget {
  const TaskManifestList({
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

  // Per-screen accordion state: set of expanded task tnm values.
  // Keyed by scrName. Cleared on route change via clearExpandState.
  static final Map<String, Set<String>> _expandedTasks = {};

  // Per-screen "seeded once" flag. Prevents re-seeding the first task after
  // the user manually collapses it. Cleared alongside _expandedTasks.
  static final Map<String, bool> _seeded = {};

  static void registerScreenSession() {
    ScreenSession.ensure(
      'TaskManifestList.expandState',
      TaskManifestList.clearExpandState,
      nav: NavPolicy.none,
    );
  }

  /// Whether the component is configured for tx-aware display.
  ///
  /// Arms on ANY of txField / saleField / buyField / refillField being
  /// non-empty in the component map. When armed, the caller defaults
  /// txField to 'tx' if absent (safe: buildItemAnnotations default: case
  /// falls back to drop/pickup for items without a tx value).
  ///
  /// Mirrors [CirculationSummary.isPerTxConfig] pattern.
  static bool isTxAwareConfig(dynamic component) {
    if (component is! Map) return false;
    const List<String> keys = <String>[
      'txField',
      'saleField',
      'buyField',
      'refillField',
    ];
    for (final String key in keys) {
      if ((component[key] ?? '').toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Clear expand state for a screen (e.g. on route change).
  static void clearExpandState(String scrName) {
    _expandedTasks.remove(scrName);
    _seeded.remove(scrName);
  }

  /// Build item-line annotation strings from a single it[] entry.
  ///
  /// Tx-aware when [txField] is non-empty: reads the tx type from the entry
  /// and selects the right qty field per type. Legacy mode (txField empty):
  /// reads drop/pickup only (P5/P10 backward-compat).
  ///
  /// The sale/purchase/refill labels are config-driven via [saleLabel],
  /// [buyLabel], [refillLabel] (mirrors the drop/pickup label pattern). They
  /// default to '' so legacy callers are unaffected.
  ///
  /// Returns a list of annotation strings (e.g. ["↓ 10 drop", "↑ 5 pickup"]).
  /// Empty list when all quantities are zero.
  static List<String> buildItemAnnotations(
    Map entry, {
    required String dropField,
    required String pickupField,
    required String dropLabel,
    required String pickupLabel,
    String txField = '',
    String saleField = '',
    String buyField = '',
    String refillField = '',
    String saleLabel = '',
    String buyLabel = '',
    String refillLabel = '',
    String actualDropField = 'ad',
    String actualPickupField = 'ap',
    String actualSaleField = 'as',
    String actualBuyField = 'ab',
    String actualRefillField = 'ar',
  }) {
    final List<String> annotations = [];
    if (txField.isNotEmpty) {
      final String tx = (entry[txField] ?? '').toString().trim();
      switch (tx) {
        case 'deliver':
          final int pd = resolveItemQty(entry, dropField, actualDropField);
          final int pp = resolveItemQty(entry, pickupField, actualPickupField);
          if (pd > 0) annotations.add('\u{2193} $pd $dropLabel');
          if (pp > 0) annotations.add('\u{2191} $pp $pickupLabel');
          break;
        case 'sale':
          if (saleField.isNotEmpty) {
            final int ps = resolveItemQty(entry, saleField, actualSaleField);
            if (ps > 0) annotations.add('\u{2192} $ps $saleLabel');
          }
          break;
        case 'purchase':
          if (buyField.isNotEmpty) {
            final int pb = resolveItemQty(entry, buyField, actualBuyField);
            if (pb > 0) annotations.add('\u{2192} $pb $buyLabel');
          }
          break;
        case 'refill':
          if (refillField.isNotEmpty) {
            final int pr = resolveItemQty(
              entry,
              refillField,
              actualRefillField,
            );
            if (pr > 0) annotations.add('\u{2192} $pr $refillLabel');
          }
          break;
        default:
          // Unknown tx: fall through to drop/pickup display.
          final int pd = resolveItemQty(entry, dropField, actualDropField);
          final int pp = resolveItemQty(entry, pickupField, actualPickupField);
          if (pd > 0) annotations.add('\u{2193} $pd $dropLabel');
          if (pp > 0) annotations.add('\u{2191} $pp $pickupLabel');
      }
    } else {
      // Legacy mode: drop/pickup only.
      final int pd = resolveItemQty(entry, dropField, actualDropField);
      final int pp = resolveItemQty(entry, pickupField, actualPickupField);
      if (pd > 0) annotations.add('\u{2193} $pd $dropLabel');
      if (pp > 0) annotations.add('\u{2191} $pp $pickupLabel');
    }
    return annotations;
  }

  @override
  State<TaskManifestList> createState() => _TaskManifestListState();
}

class _TaskManifestListState extends State<TaskManifestList> {
  List<String> _textArray = [];
  String _dataCode = '';
  String _source = '';

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'admin_create_task').toString().trim();

  @override
  void initState() {
    super.initState();
    TaskManifestList.registerScreenSession();
    _parseText();
    _source = (widget.component['source'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    // Skip Firestore subscription in draft mode -- P4 review reads the
    // in-memory wizard draft, not a collection.
    if (_source != 'draft') {
      _subscribe();
    }
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (6 slots):
  ///  [0] "Task Manifest"              (card title)
  ///  [1] "task"                       (count unit)
  ///  [2] "item line"                  (count unit)
  ///  [3] "drop"                       (pill label)
  ///  [4] "pickup"                     (pill label)
  ///  [5] "tap untuk lihat detail"     (hint)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  /// Like [_t] but also falls back to [def] when the slot exists but is empty
  /// (draft text slots may be trailing-empty under diamondTextToList).
  String _tOr(int i, String def) {
    final String v = _t(i, def);
    return v.isEmpty ? def : v;
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _dataCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _dataCode);
    }
  }

  List<Map<String, dynamic>> _getFilteredTasks() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_dataCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final String excludeStatus = (widget.component['excludeStatus'] ?? '')
        .toString()
        .trim();

    final List<Map<String, dynamic>> filtered = rawSearch.isEmpty
        ? docs
        : filterDriverHomeDocs(docs, rawSearch, widget.scrName);

    // Drop tasks with excluded status (e.g. load_rejected). Opt-in: empty
    // excludeStatus = no exclusion. Raw tst compare, NOT stopStatusOf.
    return excludeByStatus(filtered, excludeStatus);
  }

  Set<String> _getExpandSet() {
    return TaskManifestList._expandedTasks.putIfAbsent(
      widget.scrName,
      () => <String>{},
    );
  }

  void _toggleExpand(String tnm) {
    setState(() {
      final Set<String> expandSet = _getExpandSet();
      if (expandSet.contains(tnm)) {
        expandSet.remove(tnm);
      } else {
        expandSet.add(tnm);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_source == 'draft') {
      return _buildDraftMode();
    }
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value; // register dependency
      dhState.activeTrip.value; // register activeTrip dependency (GAP B fix)

      final List<Map<String, dynamic>> tasks = _getFilteredTasks();

      // O1 variant flags (absent for P10 -> unchanged behavior).
      // hideQty: suppress the drop/pickup qty pills on each task row.
      // collapsible: do NOT auto-expand the first task (start all collapsed).
      final bool hideQty =
          (widget.component['hideQty'] ?? '').toString().toUpperCase() ==
          'TRUE';
      final bool collapsible =
          (widget.component['collapsible'] ?? '').toString().toUpperCase() ==
          'TRUE';

      // Tx-aware config (sale/buy/refill). Armed when ANY of the four
      // keys is present; txField defaults to 'tx' when armed so tenants
      // that set only saleField/buyField/refillField get the tx branch.
      final bool txAware = TaskManifestList.isTxAwareConfig(widget.component);
      final String rawTx = (widget.component['txField'] ?? '')
          .toString()
          .trim();
      final String txField = txAware ? (rawTx.isEmpty ? 'tx' : rawTx) : '';
      final String saleField = txAware
          ? (widget.component['saleField'] ?? '').toString().trim()
          : '';
      final String buyField = txAware
          ? (widget.component['buyField'] ?? '').toString().trim()
          : '';
      final String refillField = txAware
          ? (widget.component['refillField'] ?? '').toString().trim()
          : '';

      // Collection-mode text slots [6][7][8]: sale/buy/refill labels.
      final String saleLabel = _tOr(6, 'Jual');
      final String buyLabel = _tOr(7, 'Beli');
      final String refillLabel = _tOr(8, 'Tukar');

      // Compute aggregates for header
      int totalItemLines = 0;
      final List<TaskAggregate> aggregates = [];
      for (final doc in tasks) {
        final agg = aggregateTaskDropPickup(
          doc,
          itemsField: (widget.component['itemsField'] ?? 'it').toString(),
          dropField: (widget.component['dropField'] ?? 'pd').toString(),
          pickupField: (widget.component['pickupField'] ?? 'pp').toString(),
          txField: txField,
          saleField: saleField,
          buyField: buyField,
          refillField: refillField,
        );
        aggregates.add(agg);
        totalItemLines += agg.itemLineCount;
      }

      // Seed expand set with first task ONCE per scrName (gated by _seeded flag).
      // After seeding, the flag is set and never re-checked, so the user can
      // collapse task 1 without it springing back open.
      final String idField = (widget.component['idField'] ?? 'tnm').toString();
      final Set<String> expandSet = _getExpandSet();
      if (!collapsible &&
          TaskManifestList._seeded[widget.scrName] != true &&
          tasks.isNotEmpty) {
        final String firstTnm = (tasks.first[idField] ?? '').toString().trim();
        if (firstTnm.isNotEmpty) {
          expandSet.add(firstTnm);
        }
        TaskManifestList._seeded[widget.scrName] = true;
      }

      // Labels from text slots
      final String title = _t(0, 'Task Manifest');
      final String taskUnit = _t(1, 'task');
      final String itemLineUnit = _t(2, 'item line');
      final String dropLabel = _t(3, 'drop');
      final String pickupLabel = _t(4, 'pickup');
      final String hint = _t(5, 'tap untuk lihat detail');

      // Header summary: "N task . M item line . tap untuk lihat detail"
      final String headerSummary =
          '${tasks.length} $taskUnit \u{00B7} $totalItemLines $itemLineUnit \u{00B7} $hint';

      final String titleField = (widget.component['titleField'] ?? 'kn')
          .toString();
      final String subtitleField = (widget.component['subtitleField'] ?? 'al')
          .toString();
      final String itemsField = (widget.component['itemsField'] ?? 'it')
          .toString();
      final String dropField = (widget.component['dropField'] ?? 'pd')
          .toString();
      final String pickupField = (widget.component['pickupField'] ?? 'pp')
          .toString();

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.list_alt,
                    size: 20,
                    color: Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          headerSummary,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Task rows
              if (tasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (int i = 0; i < tasks.length; i++)
                  _buildTaskRow(
                    tasks[i],
                    i,
                    aggregates[i],
                    idField: idField,
                    titleField: titleField,
                    subtitleField: subtitleField,
                    itemsField: itemsField,
                    dropField: dropField,
                    pickupField: pickupField,
                    dropLabel: dropLabel,
                    pickupLabel: pickupLabel,
                    isFirst: i == 0,
                    expandSet: expandSet,
                    hideQty: hideQty,
                    txField: txField,
                    saleField: saleField,
                    buyField: buyField,
                    refillField: refillField,
                    saleLabel: saleLabel,
                    buyLabel: buyLabel,
                    refillLabel: refillLabel,
                  ),
              ],
            ],
          ),
        ),
      );
    });
  }

  /// Draft-mode rendering: reads the in-memory wizard draft and renders
  /// item lines through the shared [_buildItemLines] path.
  ///
  /// No Firestore subscription, no Obx, no per-task card grouping. The draft
  /// represents a SINGLE task's items; they are shown as a flat item list
  /// inside the standard manifest card shell (header + item lines).
  Widget _buildDraftMode() {
    final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
    final List<Map<String, dynamic>> itArray =
        AdminCreateTaskSupport.draftToItArray(draft);

    // Build a synthetic task doc from the draft items.
    final String itemsField = (widget.component['itemsField'] ?? 'it')
        .toString();
    final Map<String, dynamic> syntheticTask = <String, dynamic>{
      itemsField: itArray,
    };

    // Draft-mode text slots (different mapping from collection mode):
    //  [0] "Item Order"   (card title)
    //  [1] "item line"    (count unit)
    //  [2] "drop"         (drop annotation label)
    //  [3] "pickup"       (pickup annotation label)
    //  [4] "Jual"         (sale annotation label)
    //  [5] "Beli"         (purchase annotation label)
    //  [6] "Refill"       (refill annotation label)
    final String title = _t(0, 'Item Order');
    final String countUnit = _t(1, 'item line');
    final String dropLabel = _t(2, 'drop');
    final String pickupLabel = _t(3, 'pickup');
    final String saleLabel = _tOr(4, 'Jual');
    final String buyLabel = _tOr(5, 'Beli');
    final String refillLabel = _tOr(6, 'Refill');

    final String headerSummary = '${itArray.length} $countUnit';

    // Read tx-aware field names for draft rendering.
    final String dropField = (widget.component['dropField'] ?? 'pd').toString();
    final String pickupField = (widget.component['pickupField'] ?? 'pp')
        .toString();
    final String txField = (widget.component['txField'] ?? '').toString();
    final String saleField = (widget.component['saleField'] ?? '').toString();
    final String buyField = (widget.component['buyField'] ?? '').toString();
    final String refillField = (widget.component['refillField'] ?? '')
        .toString();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header (reuses the same visual structure as collection mode)
            Row(
              children: [
                const Icon(Icons.list_alt, size: 20, color: Color(0xFF4338CA)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headerSummary,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Item lines (always expanded, no accordion, no per-task grouping)
            if (itArray.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildItemLines(
                syntheticTask,
                itemsField,
                dropField,
                pickupField,
                dropLabel,
                pickupLabel,
                txField: txField,
                saleField: saleField,
                buyField: buyField,
                refillField: refillField,
                saleLabel: saleLabel,
                buyLabel: buyLabel,
                refillLabel: refillLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskRow(
    Map<String, dynamic> task,
    int index,
    TaskAggregate agg, {
    required String idField,
    required String titleField,
    required String subtitleField,
    required String itemsField,
    required String dropField,
    required String pickupField,
    required String dropLabel,
    required String pickupLabel,
    required bool isFirst,
    required Set<String> expandSet,
    bool hideQty = false,
    String txField = '',
    String saleField = '',
    String buyField = '',
    String refillField = '',
    String saleLabel = '',
    String buyLabel = '',
    String refillLabel = '',
  }) {
    final String tnm = (task[idField] ?? '').toString().trim();
    final String name = (task[titleField] ?? '').toString().trim();
    final String address = (task[subtitleField] ?? '').toString().trim();
    final bool isExpanded = tnm.isNotEmpty && expandSet.contains(tnm);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Task header row (tappable)
        InkWell(
          onTap: tnm.isNotEmpty ? () => _toggleExpand(tnm) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isExpanded
                  ? const Color(0xFFEEF2FF) // indigo-50
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Number circle
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst
                        ? const Color(0xFF4338CA) // indigo for first/active
                        : const Color(0xFFF3F4F6), // gray-100
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isFirst ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Name + address + "T-tnm" label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tnm.isNotEmpty)
                        Text(
                          'T-$tnm',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF), // gray-400
                          ),
                        ),
                      Text(
                        name.isNotEmpty ? name : '...',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Drop/pickup/sale/buy/refill pills (O1 hideQty suppresses all)
                if (!hideQty) ...[
                  if (agg.totalDrop > 0)
                    _pill(
                      '\u{2193}${agg.totalDrop}',
                      const Color(0xFFDCFCE7),
                      const Color(0xFF16A34A),
                    ),
                  if (agg.totalPickup > 0) ...[
                    const SizedBox(width: 4),
                    _pill(
                      '\u{2191}${agg.totalPickup}',
                      const Color(0xFFEEF2FF),
                      const Color(0xFF4338CA),
                    ),
                  ],
                  if (agg.totalSale > 0) ...[
                    const SizedBox(width: 4),
                    _pill(
                      '\u{2192}${agg.totalSale}',
                      const Color(0xFFFEF3C7),
                      const Color(0xFFD97706),
                    ),
                  ],
                  if (agg.totalBuy > 0) ...[
                    const SizedBox(width: 4),
                    _pill(
                      '\u{2190}${agg.totalBuy}',
                      const Color(0xFFDBEAFE),
                      const Color(0xFF2563EB),
                    ),
                  ],
                  if (agg.totalRefill > 0) ...[
                    const SizedBox(width: 4),
                    _pill(
                      '\u{21BB}${agg.totalRefill}',
                      const Color(0xFFE0E7FF),
                      const Color(0xFF6366F1),
                    ),
                  ],
                ],
                const SizedBox(width: 4),
                // Chevron (rotates on expand)
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 20,
                  color: const Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
        // Expanded item lines (accordion)
        if (isExpanded)
          _buildItemLines(
            task,
            itemsField,
            dropField,
            pickupField,
            dropLabel,
            pickupLabel,
            txField: txField,
            saleField: saleField,
            buyField: buyField,
            refillField: refillField,
            saleLabel: saleLabel,
            buyLabel: buyLabel,
            refillLabel: refillLabel,
          ),
      ],
    );
  }

  Widget _buildItemLines(
    Map<String, dynamic> task,
    String itemsField,
    String dropField,
    String pickupField,
    String dropLabel,
    String pickupLabel, {
    String txField = '',
    String saleField = '',
    String buyField = '',
    String refillField = '',
    String saleLabel = '',
    String buyLabel = '',
    String refillLabel = '',
  }) {
    final dynamic rawItems = task[itemsField];
    if (rawItems is! List) return const SizedBox.shrink();

    final List<Widget> rows = [];
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      final String itemName = (entry['in'] ?? '').toString().trim();
      if (itemName.isEmpty) continue;

      final List<String> annotations = TaskManifestList.buildItemAnnotations(
        entry,
        dropField: dropField,
        pickupField: pickupField,
        dropLabel: dropLabel,
        pickupLabel: pickupLabel,
        txField: txField,
        saleField: saleField,
        buyField: buyField,
        refillField: refillField,
        saleLabel: saleLabel,
        buyLabel: buyLabel,
        refillLabel: refillLabel,
      );

      rows.add(
        Padding(
          padding: const EdgeInsets.only(
            left: 42,
            right: 10,
            top: 4,
            bottom: 4,
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFD1D5DB), // gray-300
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  itemName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4B5563), // gray-600
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (annotations.isNotEmpty)
                Text(
                  annotations.join('  '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280), // gray-500
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
