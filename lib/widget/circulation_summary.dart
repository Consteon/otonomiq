import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CIRCULATION_SUMMARY -- total per-item circulation across all tasks (P5).
///
/// Reads the same task collection as taskManifestList (idempotent subscription).
/// Groups all tasks' it[] entries by item name, sums planned_drop and
/// planned_pickup per item. Displays a per-item table with Muat/Drop/Pickup
/// columns, a footer with grand totals, and an italic note.
///
/// Per spec: "Muat awal = jumlah drop total" -- Muat == Drop for each item.
///
/// Column headers "Item"/"↓Drop"/"↑Pick" are intentionally hardcoded (not
/// server-overridable); only the "Muat" column header comes from text slot 1.
/// Slots 2/3 are footer labels, not column headers.
///
/// Read-only: no txfController, no saveSend, no history.
class CirculationSummary extends StatefulWidget {
  const CirculationSummary({
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

  @override
  State<CirculationSummary> createState() => _CirculationSummaryState();
}

class _CirculationSummaryState extends State<CirculationSummary> {
  List<String> _textArray = [];
  String _dataCode = '';

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

  /// text slot accessors (5 slots):
  ///  [0] "Total Circulation"    (card title)
  ///  [1] "Muat"                 (column header)
  ///  [2] "Total drop"           (footer drop label)
  ///  [3] "Total pickup"         (footer pickup label)
  ///  [4] "Muat awal = ..."      (italic note)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

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

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value; // register dependency
      dhState.activeTrip.value; // register activeTrip dependency (GAP B fix)

      final List<Map<String, dynamic>> tasks = _getFilteredTasks();

      // Opsi A (spec (2).md §3): per-item, tx-driven metrics (deliver->Drop+
      // Pickup, sale->Jual, refill->Tukar, purchase->Beli) so sale/purchase
      // items stop rendering 0/0/0. Opt-in: enabled when the config carries
      // `nameField` (the denormalised it[].in). Without it, the legacy
      // drop/pickup totals table renders unchanged (P5 1016).
      final bool perTx = (widget.component['nameField'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
      final String actualDropField =
          (widget.component['actualDropField'] ?? 'ad').toString();
      final String actualPickupField =
          (widget.component['actualPickupField'] ?? 'ap').toString();
      if (perTx) return _buildPerTx(tasks);

      final CirculationResult result = aggregateItemCirculation(
        tasks,
        itemsField: (widget.component['itemsField'] ?? 'it').toString(),
        labelField: 'in',
        dropField: (widget.component['dropField'] ?? 'pd').toString(),
        pickupField: (widget.component['pickupField'] ?? 'pp').toString(),
        actualDropField: actualDropField,
        actualPickupField: actualPickupField,
      );

      // Labels from text slots
      final String title = _t(0, 'Total Circulation');
      final String muatLabel = _t(1, 'Muat');
      final String dropFooterLabel = _t(2, 'Total \u{2193} drop');
      final String pickupFooterLabel = _t(3, 'Total \u{2191} pickup');
      final String note = _t(4, '');

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
              // Title
              Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Column header row
              _buildColumnHeader(muatLabel),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              // Per-item rows
              if (result.items.isNotEmpty)
                for (final item in result.items) _buildItemRow(item),
              // Divider before footer
              if (result.items.isNotEmpty)
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
              // Footer totals
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      dropFooterLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${result.grandDrop}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16A34A), // green-600
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      pickupFooterLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${result.grandPickup}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4338CA), // indigo-700
                      ),
                    ),
                  ),
                ],
              ),
              // Italic note
              if (note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF9CA3AF), // gray-400
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildColumnHeader(String muatLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'Item',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              muatLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          const Expanded(
            flex: 1,
            child: Text(
              '\u{2193}Drop',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          const Expanded(
            flex: 1,
            child: Text(
              '\u{2191}Pick',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(ItemCirculation item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              item.itemName,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4B5563), // gray-600
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${item.totalDrop}', // Muat == Drop per spec
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${item.totalDrop}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF16A34A), // green-600
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${item.totalPickup}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4338CA), // indigo-700
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Opsi A: per-item tx-driven render ───────────────────────────────────
  // text 7-seg: title◆Drop◆Pickup◆Jual◆Tukar◆Beli◆caption. Labels come ONLY
  // from the segments (owner-reworded), never hardcoded (spec (2).md §3).

  Widget _buildPerTx(List<Map<String, dynamic>> tasks) {
    final String actualDropField = (widget.component['actualDropField'] ?? 'ad')
        .toString();
    final String actualPickupField =
        (widget.component['actualPickupField'] ?? 'ap').toString();
    final String actualSaleField = (widget.component['actualSaleField'] ?? 'as')
        .toString();
    final String actualRefillField =
        (widget.component['actualRefillField'] ?? 'ar').toString();
    final String actualBuyField = (widget.component['actualBuyField'] ?? 'ab')
        .toString();
    final TxCirculationResult result = aggregateTxCirculation(
      tasks,
      itemsField: (widget.component['itemsField'] ?? 'it').toString(),
      labelField: (widget.component['nameField'] ?? 'in').toString(),
      txField: (widget.component['txField'] ?? 'tx').toString(),
      dropField: (widget.component['dropField'] ?? 'pd').toString(),
      pickupField: (widget.component['pickupField'] ?? 'pp').toString(),
      saleField: (widget.component['saleField'] ?? 'ps').toString(),
      refillField: (widget.component['refillField'] ?? 'pr').toString(),
      buyField: (widget.component['buyField'] ?? 'pb').toString(),
      actualDropField: actualDropField,
      actualPickupField: actualPickupField,
      actualSaleField: actualSaleField,
      actualRefillField: actualRefillField,
      actualBuyField: actualBuyField,
    );

    final String title = _t(0, 'Total Circulation');
    final String dropLabel = _t(1, 'Drop');
    final String pickupLabel = _t(2, 'Pickup');
    final String saleLabel = _t(3, 'Jual');
    final String refillLabel = _t(4, 'Tukar');
    final String buyLabel = _t(5, 'Beli');
    final String caption = _t(6, '');

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
            // Title
            Row(
              children: [
                const Icon(
                  Icons.swap_horiz,
                  size: 20,
                  color: Color(0xFF4338CA),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Per-item rows (each shows only the flows it actually has)
            if (result.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Belum ada sirkulasi hari ini.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              for (int i = 0; i < result.items.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F1F3),
                  ),
                _buildPerTxRow(
                  result.items[i],
                  dropLabel,
                  pickupLabel,
                  saleLabel,
                  refillLabel,
                  buyLabel,
                ),
              ],
            // Caption
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                caption,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF9CA3AF), // gray-400
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPerTxRow(
    TxItemCirculation item,
    String dropLabel,
    String pickupLabel,
    String saleLabel,
    String refillLabel,
    String buyLabel,
  ) {
    // Build the metric chips for the flows this item actually has (non-zero).
    final List<Widget> chips = <Widget>[];
    void addChip(String label, int value, Color color) {
      if (value == 0) return;
      chips.add(_metricChip(label, value, color));
    }

    addChip(dropLabel, item.drop, const Color(0xFF16A34A)); // green-600
    addChip(pickupLabel, item.pickup, const Color(0xFF4338CA)); // indigo-700
    addChip(saleLabel, item.sale, const Color(0xFFD97706)); // amber-600
    addChip(refillLabel, item.refill, const Color(0xFF7C3AED)); // violet-600
    addChip(buyLabel, item.buy, const Color(0xFFE11D48)); // rose-600

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              item.itemName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151), // gray-700
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: chips.isEmpty
                ? const Text(
                    '—', // em dash
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 6,
                    children: chips,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }
}
