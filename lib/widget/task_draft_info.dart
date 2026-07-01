import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart'; // diamondTextToList
import 'admin_create_task_support.dart';
import 'task_item_builder.dart'; // TaskItemBuilder.draftRev

/// TASK_DRAFT_INFO -- customer + vehicle info display for the Admin create-task
/// wizard, with three rendering variants:
///
///   - **card** (default, P4): bordered white card with customer section
///     (avatar + name + address + pic) + divider + vehicle section.
///   - **strip** (P2): compact full-width adminAccentBg strip showing
///     avatar + customer name + pic. No vehicle section.
///   - **stripTotals** (P3): compact full-width adminAccentBg strip showing
///     customer name + dot + totalDrop + totalPickup. No vehicle section.
///
/// Reads [AdminCreateTaskSupport.draftCustomer] and [draftVehicle] via the
/// shared [wizardKey] and renders info sections. Obx-rebuilds via
/// [TaskItemBuilder.draftRev] (the same signal the capture sites bump on
/// every selection).
///
/// Pure display: no Firestore subscription, no saveSend, no write path.
class TaskDraftInfo extends StatefulWidget {
  const TaskDraftInfo({
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
  State<TaskDraftInfo> createState() => _TaskDraftInfoState();
}

class _TaskDraftInfoState extends State<TaskDraftInfo> {
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
  ///  [0] "Customer"         (customer section label, card variant)
  ///  [1] "Kendaraan"        (vehicle section label, card variant)
  ///  [2] "Belum dipilih"    (customer empty state, card variant)
  ///  [3] "Belum dipilih"    (vehicle empty state, card variant)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'admin_create_task').toString().trim();

  /// Config: rendering variant. Values: 'card' (default), 'strip', 'stripTotals'.
  String get _variant =>
      (widget.component['variant'] ?? 'card').toString().trim().toLowerCase();

  /// Config: optional fixed avatar icon (e.g. "🏪"). When empty, a letter-avatar
  /// is derived from the customer name's first character.
  String get _avatarIcon =>
      (widget.component['avatarIcon'] ?? '').toString().trim();

  /// Build a letter-avatar string from customer name. Returns first char
  /// uppercased, or '' if name is empty.
  String _letterAvatar(String kn) {
    if (kn.isEmpty) return '';
    return kn[0].toUpperCase();
  }

  /// Resolve avatar content: config avatarIcon -> first letter of kn -> ''.
  String _resolveAvatar(String kn) {
    if (_avatarIcon.isNotEmpty) return _avatarIcon;
    return _letterAvatar(kn);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch revision signal for cross-widget reactivity
      TaskItemBuilder.draftRev.value;

      final Map<String, String>? customer = AdminCreateTaskSupport.getCustomer(
        _wizardKey,
      );

      final String variant = _variant;

      // ── strip variant (P2) ────────────────────────────────────────────
      if (variant == 'strip') {
        return _buildStrip(customer);
      }

      // ── stripTotals variant (P3) ──────────────────────────────────────
      if (variant == 'striptotals') {
        return _buildStripTotals(customer);
      }

      // ── card variant (P4, default) ────────────────────────────────────
      return _buildCard(customer);
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  // STRIP variant (P2): adminAccentBg, avatar + name + pic
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildStrip(Map<String, String>? customer) {
    final String kn = customer?['kn'] ?? '';
    final String pic = customer?['pic'] ?? '';

    // Empty-state: no customer picked yet -> invisible (P2 is only reached
    // after P1 picks a customer, so this is a defensive no-op path).
    if (customer == null || kn.isEmpty) {
      return const SizedBox.shrink();
    }

    final String avatar = _resolveAvatar(kn);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFEFF6FF), // adminAccentBg
          border: Border(
            bottom: BorderSide(color: Color(0xFFE8EAED)), // border
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar: 28x28, radius 6, slate-100 bg, fontSize 16
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), // slate100
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(avatar, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    kn,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A), // text
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pic.isNotEmpty)
                    Text(
                      pic,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF475569), // textMid
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // STRIP TOTALS variant (P3): adminAccentBg, name + drop/pickup totals
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildStripTotals(Map<String, String>? customer) {
    final String kn = customer?['kn'] ?? '';

    // Empty-state: no customer -> invisible
    if (customer == null || kn.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
    final TaskTotals totals = AdminCreateTaskSupport.computeTotals(draft);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFEFF6FF), // adminAccentBg
          border: Border(
            bottom: BorderSide(color: Color(0xFFE8EAED)), // border
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Customer name
            Flexible(
              child: Text(
                kn,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E40AF), // adminAccentDark
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Dot separator
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '\u{00B7}', // middle dot
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8), // textDim
                ),
              ),
            ),
            // Drop total
            Text(
              '\u{2193} ${totals.totalDrop}', // down arrow
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1E40AF), // adminAccentDark
              ),
            ),
            const SizedBox(width: 8),
            // Pickup total
            Text(
              '\u{2191} ${totals.totalPickup}', // up arrow
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1E40AF), // adminAccentDark
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // CARD variant (P4, default): bordered card with customer + vehicle
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildCard(Map<String, String>? customer) {
    final Map<String, String>? vehicle = AdminCreateTaskSupport.getVehicle(
      _wizardKey,
    );

    final String customerLabel = _t(0, 'Customer');
    final String vehicleLabel = _t(1, 'Kendaraan');
    final String customerEmpty = _t(2, 'Belum dipilih');
    final String vehicleEmpty = _t(3, 'Belum dipilih');

    final bool customerIsEmpty =
        customer == null || (customer['kn'] ?? '').isEmpty;

    // ---- Build the card (unchanged structure) ----
    final Widget card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)), // border
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Customer section ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Label "CUSTOMER"
                Text(
                  customerLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0xFF94A3B8), // textDim
                  ),
                ),
                const SizedBox(height: 6),
                if (customerIsEmpty)
                  Text(
                    customerEmpty,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8), // textDim
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  _buildCardCustomerContent(customer),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Vehicle section ──────────────────────────────────
          _buildSection(
            label: vehicleLabel,
            icon: Icons.local_shipping_outlined,
            isEmpty: vehicle == null || (vehicle['vv'] ?? '').isEmpty,
            emptyText: vehicleEmpty,
            child: vehicle != null ? _buildVehicleContent(vehicle) : null,
          ),
        ],
      ),
    );

    // ---- Pickup breakdown (aggregate over deliver items) ----
    final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
    int totalExchange = 0;
    int totalClearing = 0;
    for (final DraftItem item in draft) {
      if (item.tx != 'deliver') continue;
      totalExchange += TaskItemBuilder.pickupExchange(item.pd, item.pp);
      totalClearing += TaskItemBuilder.pickupClearing(item.pd, item.pp);
    }
    final int totalPickup = totalExchange + totalClearing;

    // No breakdown when totalPickup is zero -- return just the card.
    if (totalPickup <= 0) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: card,
      );
    }

    // Card + breakdown box in a Column.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          const SizedBox(height: 12),
          _buildPickupBreakdown(totalExchange, totalClearing, totalPickup),
        ],
      ),
    );
  }

  /// Card variant: customer content with avatar + name + address + pic.
  /// Mockup: TaskSummaryScreen L1648-1667 (avatar 24, name 14 w700,
  /// address 11 textMid, pic 11 textMid mt2).
  Widget _buildCardCustomerContent(Map<String, String> customer) {
    final String kn = customer['kn'] ?? '';
    final String al = customer['al'] ?? '';
    final String pic = customer['pic'] ?? '';
    final String avatar = _resolveAvatar(kn);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar: 36x36, radius 8, slate-100 bg, fontSize 24
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9), // slate100
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(avatar, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kn.isNotEmpty)
                Text(
                  kn,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A), // text
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (al.isNotEmpty)
                Text(
                  al,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569), // textMid
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (pic.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  pic,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569), // textMid
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Generic section builder for the card variant's vehicle section.
  /// Reused from the prior implementation (unchanged in shape).
  Widget _buildSection({
    required String label,
    required IconData icon,
    required bool isEmpty,
    required String emptyText,
    required Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF64748B)), // slate-500
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0xFF94A3B8), // slate-400
                  ),
                ),
                const SizedBox(height: 4),
                if (isEmpty)
                  Text(
                    emptyText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8), // slate-400
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  ?child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleContent(Map<String, String> vehicle) {
    final String vn = vehicle['vn'] ?? '';
    final String vv = vehicle['vv'] ?? '';
    // Show display name (plate/title) if available, fall back to id
    final String displayText = vn.isNotEmpty ? vn : vv;
    return Text(
      displayText,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E293B), // slate-800
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // PICKUP BREAKDOWN box (P4 card variant only, totalPickup > 0)
  // ════════════════════════════════════════════════════════════════════════

  /// Violet accent-bar callout showing aggregate exchange/clearing breakdown.
  /// Follows the notice_bar left-accent pattern (ClipRRect + Row +
  /// IntrinsicHeight). Colors: violet-50 bg, violet-400 accent, violet-700
  /// text, textMid for parenthetical notes.
  Widget _buildPickupBreakdown(int exchange, int clearing, int totalPickup) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF), // violet-50
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 3, minWidth: 3),
                color: const Color(0xFFA78BFA), // violet-400
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Pickup Breakdown:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6D28D9), // violet-700
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (exchange > 0)
                              _breakdownLine(
                                exchange,
                                'exchange',
                                '(kosong dari delivery hari ini)',
                              ),
                            if (clearing > 0)
                              _breakdownLine(
                                clearing,
                                'clearing',
                                '(outstanding lama)',
                              ),
                            const SizedBox(height: 4),
                            Text(
                              '= $totalPickup total expected pickup',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6D28D9), // violet-700
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (clearing > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Outstanding customer akan berkurang sebanyak '
                          '$clearing kalau pickup berhasil sesuai plan.',
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF6D28D9), // violet-700
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One bullet line in the pickup breakdown: "* {count} {label} {note}".
  Widget _breakdownLine(int count, String label, String note) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: '\u{2022} '), // bullet
            TextSpan(
              text: '$count',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: ' $label '),
            TextSpan(
              text: note,
              style: const TextStyle(
                color: Color(0xFF475569), // textMid
              ),
            ),
          ],
        ),
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF6D28D9), // violet-700
        ),
      ),
    );
  }
}
