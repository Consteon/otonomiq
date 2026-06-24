import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
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

  /// Get or create the execution map for a screen.
  static Map<String, ExecutionEntry> getExecMap(String scrName) {
    return executionStore.putIfAbsent(
        scrName, () => <String, ExecutionEntry>{});
  }

  /// Clear execution store for a screen.
  static void clearExecutionStore(String scrName) {
    executionStore.remove(scrName);
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
  static const Color _neutralFg = Color(0xFF64748B); // slate-500 (consumable fg)
  static const Color _neutralBg = Color(0xFFF1F5F9); // slate-100 (consumable bg)
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

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
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
    final String rawTable =
        (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        _taskCode = '${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }
  }

  /// Find the active task doc.
  Map<String, dynamic>? _findActiveTask() {
    if (_taskCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(
            mapTableContent[_taskCode] ?? const []);
    final String rawSearch =
        (widget.component['search'] ?? '').toString().trim();
    if (rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
    final List<Map<String, dynamic>> matched =
        filterDriverHomeDocs(docs, rawSearch, widget.scrName);
    return matched.isNotEmpty ? matched.first : null;
  }

  /// Extract the it[] items array from the task doc.
  List<Map<String, dynamic>> _extractItems(Map<String, dynamic>? taskDoc) {
    if (taskDoc == null) return const [];
    final String itemsField =
        (widget.component['itemsField'] ?? 'it').toString().trim();
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
  List<_ItemRow> _buildRows(List<Map<String, dynamic>> items) {
    final String labelField =
        (widget.component['labelField'] ?? 'in').toString().trim();
    final String planDropField =
        (widget.component['planDropField'] ?? 'pd').toString().trim();
    final String planPickupField =
        (widget.component['planPickupField'] ?? 'pp').toString().trim();
    // TX-DELTA config fields
    final String txField =
        (widget.component['txField'] ?? 'tx').toString().trim();
    final String saleField =
        (widget.component['saleField'] ?? 'ps').toString().trim();
    final String buyField =
        (widget.component['buyField'] ?? 'pb').toString().trim();
    final String refillField =
        (widget.component['refillField'] ?? 'pr').toString().trim();
    final String condOutField =
        (widget.component['condOutField'] ?? 'cdo').toString().trim();
    final String condInField =
        (widget.component['condInField'] ?? 'cdi').toString().trim();
    final String waterFieldKey =
        (widget.component['waterField'] ?? 'wt').toString().trim();

    // Text-slot labels for condition / water mapping
    final String kosongSlot = _t(20, 'Kosong');
    final String penuhSlot = _t(21, 'Penuh');
    final String roSlot = _t(22, 'RO');
    final String isiUlangSlot = _t(23, 'Isi Ulang');

    final Map<String, ExecutionEntry> execMap =
        ItemExecutionList.getExecMap(widget.scrName);
    final int sizeBefore = execMap.length;
    final List<_ItemRow> rows = <_ItemRow>[];

    for (int i = 0; i < items.length; i++) {
      final Map<String, dynamic> item = items[i];
      final String name =
          (item[labelField] ?? '').toString().trim();
      final String key = '$i';
      final String txKind =
          classifyTxKind((item[txField] ?? '').toString().trim().toLowerCase());

      if (txKind == 'deliver') {
        // ── Deliver: existing path (seed execution store) ──
        final int planDrop =
            int.tryParse((item[planDropField] ?? '0').toString().trim()) ?? 0;
        final int planPickup =
            int.tryParse((item[planPickupField] ?? '0').toString().trim()) ?? 0;
        final bool isReturnable = planPickup > 0;

        // Seed execution store (putIfAbsent -- once per item per session).
        execMap.putIfAbsent(
            key,
            () => ExecutionEntry(
                  dropActual: planDrop,
                  pickupActual: planPickup,
                  dropPlan: planDrop,
                  pickupPlan: planPickup,
                ));

        rows.add(_ItemRow(
          index: i,
          key: key,
          name: name.isNotEmpty ? name : 'Item $i',
          txKind: 'deliver',
          isReturnable: isReturnable,
          planDrop: planDrop,
          planPickup: planPickup,
        ));
      } else {
        // ── Sale / Purchase / Refill: read-only, NO execution store ──
        final int txQty;
        final String subLabel;

        if (txKind == 'sale') {
          txQty = int.tryParse(
                  (item[saleField] ?? '0').toString().trim()) ??
              0;
          subLabel = conditionLabel(
            (item[condOutField] ?? '').toString(),
            kosongSlot: kosongSlot,
            penuhSlot: penuhSlot,
          );
        } else if (txKind == 'purchase') {
          txQty = int.tryParse(
                  (item[buyField] ?? '0').toString().trim()) ??
              0;
          subLabel = conditionLabel(
            (item[condInField] ?? '').toString(),
            kosongSlot: kosongSlot,
            penuhSlot: penuhSlot,
          );
        } else {
          // refill
          txQty = int.tryParse(
                  (item[refillField] ?? '0').toString().trim()) ??
              0;
          subLabel = waterLabel(
            (item[waterFieldKey] ?? '').toString(),
            roSlot: roSlot,
            isiUlangSlot: isiUlangSlot,
          );
        }

        rows.add(_ItemRow(
          index: i,
          key: key,
          name: name.isNotEmpty ? name : 'Item $i',
          txKind: txKind,
          txQty: txQty,
          subLabel: subLabel,
        ));
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
    final Map<String, ExecutionEntry> map =
        ItemExecutionList.getExecMap(widget.scrName);
    final ExecutionEntry? entry = map[key];
    if (entry != null) {
      entry.dropActual = newValue;
      ItemExecutionList.executionRev.value++;
      setState(() {});
    }
  }

  void _onPickupChanged(String key, int newValue) {
    final Map<String, ExecutionEntry> map =
        ItemExecutionList.getExecMap(widget.scrName);
    final ExecutionEntry? entry = map[key];
    if (entry != null) {
      entry.pickupActual = newValue;
      ItemExecutionList.executionRev.value++;
      setState(() {});
    }
  }

  /// Derive per-cell status.
  _CellStatus _cellStatus(int actual, int plan, bool isPickup) {
    if (actual < plan) {
      final int kurang = plan - actual;
      final String template = _t(3, 'Partial \u{00B7} <kurang> kurang');
      final String label =
          template.replaceAll('<kurang>', '$kurang');
      return _CellStatus('partial', label);
    } else if (actual == plan) {
      return _CellStatus('complete', _t(4, '\u{2713} Sesuai'));
    } else {
      // actual > plan
      if (isPickup) {
        final int extra = actual - plan;
        final String template =
            _t(5, 'Opportunistic \u{00B7} <value>');
        final String label =
            template.replaceAll('<value>', '$extra');
        return _CellStatus('opportunistic', label);
      } else {
        final int extra = actual - plan;
        final String template = _t(6, '+<extra> extra');
        final String label =
            template.replaceAll('<extra>', '$extra');
        return _CellStatus('extra', label);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch vehicleId + executionRev for Obx dependency.
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;
      ItemExecutionList.executionRev.value;

      // Touch mapTableContent for reactive rebuild.
      mapTableContent[_taskCode];

      // Find active task and extract items.
      final Map<String, dynamic>? taskDoc = _findActiveTask();
      final List<Map<String, dynamic>> items = _extractItems(taskDoc);
      final List<_ItemRow> rows = _buildRows(items);
      final Map<String, ExecutionEntry> execMap =
          ItemExecutionList.getExecMap(widget.scrName);

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
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
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

    final _CellStatus dropStatus =
        _cellStatus(dropActual, row.planDrop, false);
    final _CellStatus pickupStatus = row.isReturnable
        ? _cellStatus(pickupActual, row.planPickup, true)
        : _CellStatus('complete', '');

    // Type chip
    final String chipLabel =
        row.isReturnable ? returnableLabel : consumableLabel;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    onDecrement: dropActual > 0
                        ? () => _onDropChanged(row.key, dropActual - 1)
                        : null,
                    onIncrement: () =>
                        _onDropChanged(row.key, dropActual + 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStepperCell(
                    label:
                        '\u{2191} ${pickupLabel.toUpperCase()}', // ↑ PICKUP
                    planValue: row.planPickup,
                    actualValue: pickupActual,
                    status: pickupStatus,
                    planLabel: planLabel,
                    isPickup: true,
                    onDecrement: pickupActual > 0
                        ? () =>
                            _onPickupChanged(row.key, pickupActual - 1)
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
              onDecrement: dropActual > 0
                  ? () => _onDropChanged(row.key, dropActual - 1)
                  : null,
              onIncrement: () => _onDropChanged(row.key, dropActual + 1),
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
        descText = _t(16,
            'Kepemilikan ke operator \u{00B7} naik ke kendaraan');
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
        descText = _t(19,
            'Kosong masuk \u{00B7} isi keluar \u{00B7} galon milik customer');
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            style: const TextStyle(
              fontSize: 11,
              color: _caption,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),

          // ── Qty frame (read-only, no stepper) ─────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
