import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
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

  /// Clear expand state for a screen (e.g. on route change).
  static void clearExpandState(String scrName) {
    _expandedTasks.remove(scrName);
    _seeded.remove(scrName);
  }

  @override
  State<TaskManifestList> createState() => _TaskManifestListState();
}

class _TaskManifestListState extends State<TaskManifestList> {
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

  /// text slot accessors (6 slots):
  ///  [0] "Task Manifest"              (card title)
  ///  [1] "task"                       (count unit)
  ///  [2] "item line"                  (count unit)
  ///  [3] "drop"                       (pill label)
  ///  [4] "pickup"                     (pill label)
  ///  [5] "tap untuk lihat detail"     (hint)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      _dataCode = '${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _dataCode);
    }
  }

  List<Map<String, dynamic>> _getFilteredTasks() {
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(
            mapTableContent[_dataCode] ?? const []);
    final String rawSearch =
        (widget.component['search'] ?? '').toString().trim();
    final String excludeStatus =
        (widget.component['excludeStatus'] ?? '').toString().trim();

    final List<Map<String, dynamic>> filtered =
        rawSearch.isEmpty ? docs : filterDriverHomeDocs(docs, rawSearch, widget.scrName);

    // Drop tasks with excluded status (e.g. load_rejected). Opt-in: empty
    // excludeStatus = no exclusion. Raw tst compare, NOT stopStatusOf.
    return excludeByStatus(filtered, excludeStatus);
  }

  Set<String> _getExpandSet() {
    return TaskManifestList._expandedTasks.putIfAbsent(
        widget.scrName, () => <String>{});
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
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value; // register dependency

      final List<Map<String, dynamic>> tasks = _getFilteredTasks();

      // Compute aggregates for header
      int totalItemLines = 0;
      final List<TaskAggregate> aggregates = [];
      for (final doc in tasks) {
        final agg = aggregateTaskDropPickup(doc,
            itemsField:
                (widget.component['itemsField'] ?? 'it').toString(),
            dropField:
                (widget.component['dropField'] ?? 'pd').toString(),
            pickupField:
                (widget.component['pickupField'] ?? 'pp').toString());
        aggregates.add(agg);
        totalItemLines += agg.itemLineCount;
      }

      // Seed expand set with first task ONCE per scrName (gated by _seeded flag).
      // After seeding, the flag is set and never re-checked, so the user can
      // collapse task 1 without it springing back open.
      final String idField =
          (widget.component['idField'] ?? 'tnm').toString();
      final Set<String> expandSet = _getExpandSet();
      if (TaskManifestList._seeded[widget.scrName] != true &&
          tasks.isNotEmpty) {
        final String firstTnm =
            (tasks.first[idField] ?? '').toString().trim();
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

      final String titleField =
          (widget.component['titleField'] ?? 'kn').toString();
      final String subtitleField =
          (widget.component['subtitleField'] ?? 'al').toString();
      final String itemsField =
          (widget.component['itemsField'] ?? 'it').toString();
      final String dropField =
          (widget.component['dropField'] ?? 'pd').toString();
      final String pickupField =
          (widget.component['pickupField'] ?? 'pp').toString();

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
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
                  const Icon(Icons.list_alt,
                      size: 20, color: Color(0xFF4338CA)),
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
                  ),
              ],
            ],
          ),
        ),
      );
    });
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
                      color: isFirst
                          ? Colors.white
                          : const Color(0xFF6B7280),
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
                // Drop/pickup pills
                if (agg.totalDrop > 0)
                  _pill('\u{2193}${agg.totalDrop}',
                      const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
                if (agg.totalPickup > 0) ...[
                  const SizedBox(width: 4),
                  _pill('\u{2191}${agg.totalPickup}',
                      const Color(0xFFEEF2FF), const Color(0xFF4338CA)),
                ],
                const SizedBox(width: 4),
                // Chevron (rotates on expand)
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.chevron_right,
                  size: 20,
                  color: const Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
        // Expanded item lines (accordion)
        if (isExpanded)
          _buildItemLines(task, itemsField, dropField, pickupField,
              dropLabel, pickupLabel),
      ],
    );
  }

  Widget _buildItemLines(
    Map<String, dynamic> task,
    String itemsField,
    String dropField,
    String pickupField,
    String dropLabel,
    String pickupLabel,
  ) {
    final dynamic rawItems = task[itemsField];
    if (rawItems is! List) return const SizedBox.shrink();

    final List<Widget> rows = [];
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      final String itemName = (entry['in'] ?? '').toString().trim();
      if (itemName.isEmpty) continue;
      final int pd =
          int.tryParse((entry[dropField] ?? '0').toString().trim()) ?? 0;
      final int pp =
          int.tryParse((entry[pickupField] ?? '0').toString().trim()) ?? 0;

      // Build qty annotations
      final List<String> annotations = [];
      if (pd > 0) annotations.add('\u{2193} $pd $dropLabel');
      if (pp > 0) annotations.add('\u{2191} $pp $pickupLabel');

      rows.add(Padding(
        padding: const EdgeInsets.only(left: 42, right: 10, top: 4, bottom: 4),
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
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
