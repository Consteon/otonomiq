import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart'; // diamondTextToList
import 'admin_create_task_support.dart';
import 'task_item_builder.dart'; // TaskItemBuilder.draftRev

/// TASK_DRAFT_SUMMARY -- read-only P4 item preview for the Admin create-task
/// wizard.
///
/// Reads [AdminCreateTaskSupport.draftItems] via the shared [wizardKey] and
/// renders per-line rows with tx chips and aggregate totals. Obx-rebuilds via
/// [TaskItemBuilder.draftRev] (the same signal the builder bumps on every edit).
///
/// Pure display: no Firestore subscription, no saveSend, no write path.
class TaskDraftSummary extends StatefulWidget {
  const TaskDraftSummary({
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
  State<TaskDraftSummary> createState() => _TaskDraftSummaryState();
}

class _TaskDraftSummaryState extends State<TaskDraftSummary> {
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Text slot accessors:
  ///  [0] "Item"          (section header)
  ///  [1] "Drop"          (total label)
  ///  [2] "Pickup"        (total label)
  ///  [3] "Jual"          (total label)
  ///  [4] "Beli"          (total label)
  ///  [5] "Refill"        (total label)
  ///  [6] "Belum ada item" (empty state)
  ///  [7] "Total"         (total Rp label)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'admin_create_task').toString().trim();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch revision signal for cross-widget reactivity
      TaskItemBuilder.draftRev.value;

      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);

      if (draft.isEmpty) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: Text(
            _t(6, 'Belum ada item'),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8), // slate-400
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }

      final TaskTotals totals = AdminCreateTaskSupport.computeTotals(draft);

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
            border: Border.all(color: const Color(0xFFE2E8F0)), // slate-200
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Section header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '${_t(0, 'Item')} (${draft.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B), // slate-800
                  ),
                ),
              ),
              const Divider(height: 1),
              // Per-line rows
              for (int i = 0; i < draft.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _buildLineRow(draft[i]),
              ],
              const Divider(height: 1),
              // Aggregate totals footer
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (totals.totalDrop > 0)
                          _totalPill(
                            '${_t(1, 'Drop')} ${totals.totalDrop}',
                            const Color(0xFF3B82F6),
                          ), // blue-500
                        if (totals.totalPickup > 0)
                          _totalPill(
                            '${_t(2, 'Pickup')} ${totals.totalPickup}',
                            const Color(0xFF8B5CF6),
                          ), // violet-500
                        if (totals.totalSale > 0)
                          _totalPill(
                            '${_t(3, 'Jual')} ${totals.totalSale}',
                            const Color(0xFFF59E0B),
                          ), // amber-500
                        if (totals.totalPurchase > 0)
                          _totalPill(
                            '${_t(4, 'Beli')} ${totals.totalPurchase}',
                            const Color(0xFF8B5CF6),
                          ),
                        if (totals.totalRefill > 0)
                          _totalPill(
                            '${_t(5, 'Refill')} ${totals.totalRefill}',
                            const Color(0xFF0D9488),
                          ), // teal-600
                      ],
                    ),
                    // Total sale price (Rp)
                    if (totals.totalSalePrice > 0) ...[
                      const SizedBox(height: 6),
                      _totalPill(
                        '${_t(7, 'Total')} ${AdminCreateTaskSupport.formatRupiah(totals.totalSalePrice)}',
                        const Color(0xFFF59E0B), // amber, matches Jual
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildLineRow(DraftItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Item name + price annotation for sale rows
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.itemName.isNotEmpty ? item.itemName : item.ii,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Price annotation for sale rows (hg > 0)
                if (item.tx == 'sale' && item.hg > 0)
                  Text(
                    '${AdminCreateTaskSupport.formatRupiah(item.hg)} x ${item.ps} = ${AdminCreateTaskSupport.formatRupiah(item.hg * item.ps)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8), // slate-400
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Tx chip
          _txChip(item.tx),
          const SizedBox(width: 8),
          // Primary qty
          Text(
            '${item.primaryQty}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          // Deliver also shows pickup
          if (item.tx == 'deliver' && item.pp > 0) ...[
            const SizedBox(width: 4),
            Text(
              '/ ${item.pp}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8), // slate-400
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _txChip(String tx) {
    final String label;
    final Color bg;
    switch (tx) {
      case 'deliver':
        label = 'ANTAR';
        bg = const Color(0xFF3B82F6);
        break;
      case 'sale':
        label = 'JUAL';
        bg = const Color(0xFFF59E0B);
        break;
      case 'purchase':
        label = 'BELI';
        bg = const Color(0xFF8B5CF6);
        break;
      case 'refill':
        label = 'REFILL';
        bg = const Color(0xFF0D9488);
        break;
      default:
        label = tx.toUpperCase();
        bg = const Color(0xFF6B7280);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: bg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _totalPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
