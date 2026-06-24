import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// TASK_FEED_LIST — grouped task card list for P10 TaskFeed.
///
/// Reads task docs (same search as RouteFeedHeader), groups by tst
/// (assigned+on_delivery → failed → completed), renders per-card layout with
/// state-specific styling, drop/pickup badges, and per-state footer.
///
/// allDone (no assigned/on_delivery tasks) shows an emerald banner + sticky
/// "Kembali ke Gudang" button.
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

  @override
  State<TaskFeedList> createState() => _TaskFeedListState();
}

class _TaskFeedListState extends State<TaskFeedList> {
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

  List<Map<String, dynamic>> _getFilteredTasks() {
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(
            mapTableContent[_taskCode] ?? const []);
    final String rawSearch =
        (widget.component['search'] ?? '').toString().trim();
    if (rawSearch.isEmpty) return docs;
    return filterDriverHomeDocs(docs, rawSearch, widget.scrName);
  }

  void _onCardTap(Map<String, dynamic> task) {
    final String route =
        (widget.component['route'] ?? '').toString().trim();
    if (route.isEmpty) return;

    // Dispatch the tapped task's VID into #ACTIVE_TASK so P11 widgets
    // can resolve {activeTaskVid} in their search strings.
    final String idField =
        (widget.component['idField'] ?? 'tnm').toString();
    final String taskVid = (task[idField] ?? '').toString().trim();
    if (taskVid.isNotEmpty) {
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#ACTIVE_TASK': taskVid})));
    }

    // Dead-route silent skip (P11 DeliveryWorkspace may not be built).
    routeStack.push(route);
    gotoRoute(route);
  }

  void _onReturnTap() {
    final String returnRoute =
        (widget.component['returnRoute'] ?? '').toString().trim();
    if (returnRoute.isEmpty) return;
    // Dead-route silent skip (P12 ReturnVehicle not built yet).
    routeStack.push(returnRoute);
    gotoRoute(returnRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch vehicleId to register Obx dependency (search uses {vehicleId}).
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;

      final List<Map<String, dynamic>> tasks = _getFilteredTasks();

      // Component field overrides
      final String groupField =
          (widget.component['groupField'] ?? 'tst').toString();
      final String idField =
          (widget.component['idField'] ?? 'tnm').toString();
      final String titleField =
          (widget.component['titleField'] ?? 'kn').toString();
      final String addressField =
          (widget.component['addressField'] ?? 'al').toString();
      final String typeField =
          (widget.component['typeField'] ?? 'tty').toString();
      final String itemsField =
          (widget.component['itemsField'] ?? 'it').toString();
      final String dropField =
          (widget.component['dropField'] ?? 'pd').toString();
      final String pickupField =
          (widget.component['pickupField'] ?? 'pp').toString();
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

      // Text slots
      final String assignedLabel = _t(0, 'Stop Berikutnya');
      final String assignedSubtitle =
          _t(1, 'Pilih sesuai kondisi lapangan');
      final String failedLabel = _t(2, 'Dilaporkan Gagal');
      final String completedLabel = _t(3, 'Sudah Selesai');

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
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

            // ── allDone banner ────────────────────────────────────
            if (allDone && tasks.isNotEmpty) ...[
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

  Widget _buildSectionHeader(String label, Color color,
      {String? subtitle}) {
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
    final String taskType = (doc[typeField] ?? '').toString().trim().toLowerCase();

    // Per-task drop/pickup
    final dynamic rawItems = doc[itemsField];
    int dropCount = 0;
    int pickupCount = 0;
    if (rawItems is List) {
      for (final dynamic item in rawItems) {
        if (item is! Map) continue;
        if (isDone) {
          // Completed: show actual drop/pickup
          dropCount +=
              int.tryParse((item[actualDropField] ?? '0').toString().trim()) ?? 0;
          pickupCount +=
              int.tryParse((item[actualPickupField] ?? '0').toString().trim()) ?? 0;
        } else {
          // Assigned/failed: show planned
          dropCount +=
              int.tryParse((item[dropField] ?? '0').toString().trim()) ?? 0;
          pickupCount +=
              int.tryParse((item[pickupField] ?? '0').toString().trim()) ?? 0;
        }
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
        10, '! Dilaporkan gagal \u{2014} menunggu admin reschedule');
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
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F3FF), // violet-50
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              pickupOnlyLabel,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF7C3AED), // violet-600
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
                                    horizontal: 8, vertical: 3),
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
                                              ? const Color(0xFFDCFCE7) // emerald-100
                                              : const Color(0xFFEEF2FF), // indigo-50
                                          isDone
                                              ? const Color(0xFF16A34A) // emerald-600
                                              : const Color(0xFF4338CA), // indigo-700
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
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4338CA), // indigo-700
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildAllDoneBanner() {
    final String emoji = _t(11, '\u{1F389}');
    final String title = _t(12, 'Semua Stop Selesai');
    final String body =
        _t(13, 'Lo bisa kembali ke gudang untuk closing check.');

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
