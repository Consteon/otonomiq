import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// WORKSPACE_HEADER -- top-bar for P11 DeliveryWorkspace.
///
/// Reads the active task doc via `search:"tnm◼{activeTaskVid}"`. Renders:
///   - Back arrow -> backRoute (routeStack.push + gotoRoute)
///   - Mono "{tnm} · Stop {stopNumber}" + bold customer "{kn}"
///   - "BERJALAN" chip (right)
///   - Address band below: "📍 {al}" on light-indigo bg
///
/// stopNumber is derived by ordering ALL task docs in the subscription with the
/// SAME vehicle+today filter P10 uses (`listSearch`, default
/// `vv◼{vehicleId}⭘tdt◼{today}`), then finding the 1-based doc-order position of
/// the active task within THAT filtered list. This keeps the P11 stop number in
/// lock-step with the card the driver tapped in P10 (mirrors
/// task_feed_list.dart's `_getFilteredTasks()` + `globalIndex`).
///
/// Renders its title/chip UNCONDITIONALLY even with no data (diagnostic:
/// blank top-bar on device = header absent from JSON, not data bug).
///
/// NOT a vehicleId publisher -- P11 reuses the DriverHomeState.vehicleId
/// published by P10's RouteFeedHeader (it persists across route changes
/// because DriverHomeState is keyed by scrName, and P11 has its own scrName
/// with vehicleId propagated from the shared driver session).
///
/// Read-only: no txfController, no saveSend, no history.
class WorkspaceHeader extends StatefulWidget {
  const WorkspaceHeader({
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
  State<WorkspaceHeader> createState() => _WorkspaceHeaderState();
}

class _WorkspaceHeaderState extends State<WorkspaceHeader> {
  // ── Driver palette tokens (shared with P10 task_feed_list) ──────────────
  static const Color _ink = Color(0xFF1F2937); // gray-800 (customer)
  static const Color _mono = Color(0xFF6B7280); // gray-500 (mono id line)
  static const Color _hair = Color(0xFFE5E7EB); // gray-200 (card border)
  static const Color _accent = Color(
    0xFF4338CA,
  ); // indigo-700 (chip/address fg)
  static const Color _accentBg = Color(0xFFEEF2FF); // indigo-50 (chip/band bg)

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

  /// text slot accessors (2 slots):
  ///  driver-stop: [0] "Stop" (stopNumber prefix) · [1] "Berjalan" (chip label)
  ///  step variant: [0] title (bold) · [1] step subtitle (grey)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  /// Config-driven variant: 'step' for admin wizard step header.
  String get _variant =>
      (widget.component['variant'] ?? '').toString().trim().toLowerCase();

  void _subscribe() {
    if (_variant == 'step') return; // step header reads no collection
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final String appVid = resolveAppVid(widget.component);
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }
  }

  /// Find the single active task doc via the component's search filter.
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

  /// Derive the 1-based stop number for the active task.
  ///
  /// W1: order ALL task docs with the SAME vehicle+today filter P10 uses
  /// (`listSearch`, default `vv◼{vehicleId}⭘tdt◼{today}`), then find the
  /// position of the doc whose idField matches the activeTaskVid WITHIN that
  /// filtered list. This guarantees the P11 stop number matches the P10 card
  /// the driver tapped (P10 `task_feed_list._getFilteredTasks()` + `globalIndex`).
  ///
  /// Returns 0 if not found (or list unresolved/empty).
  int _deriveStopNumber(String activeTaskVid) {
    if (_taskCode.isEmpty || activeTaskVid.isEmpty) return 0;
    final String idField = (widget.component['idField'] ?? 'tnm').toString();
    final String listSearch =
        (widget.component['listSearch'] ??
                'vv\u{25FC}{vehicleId}\u{2B58}tdt\u{25FC}{today}')
            .toString();
    final List<Map<String, dynamic>> allDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
    );
    // Order via the same filter pipeline P10 uses (decode + tokens + AND).
    final List<Map<String, dynamic>> ordered = filterDriverHomeDocs(
      allDocs,
      listSearch,
      widget.scrName,
    );
    for (int i = 0; i < ordered.length; i++) {
      final String docId = (ordered[i][idField] ?? '').toString().trim();
      if (docId == activeTaskVid) return i + 1;
    }
    return 0;
  }

  /// Step-header variant for admin wizard pages.
  /// Renders title (bold) + step subtitle (grey). Back navigation is handled by
  /// the app bar (pops routeStack) -- no in-header back arrow.
  Widget _buildStepHeader(BuildContext context) {
    final String title = _t(0, '');
    final String step = _t(1, '');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE8EAED))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (step.isNotEmpty) ...[
              if (title.isNotEmpty) const SizedBox(height: 2),
              Text(
                step,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_variant == 'step') return _buildStepHeader(context);
    return Obx(() {
      // Touch vehicleId to register Obx dependency (search uses {vehicleId}).
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;

      // Touch mapTableContent to register Obx dependency for task data.
      mapTableContent[_taskCode];

      // Find the active task doc.
      final Map<String, dynamic>? taskDoc = _findActiveTask();

      // Read fields from the task doc.
      final String idField = (widget.component['idField'] ?? 'tnm').toString();
      final String titleField = (widget.component['titleField'] ?? 'kn')
          .toString();
      final String addressField = (widget.component['addressField'] ?? 'al')
          .toString();

      final String taskId = (taskDoc?[idField] ?? '').toString().trim();
      final String customer = (taskDoc?[titleField] ?? '').toString().trim();
      final String address = (taskDoc?[addressField] ?? '').toString().trim();

      // Derive stopNumber (W1: P10-scoped ordering).
      final int stopNumber = _deriveStopNumber(taskId);

      // Text slots.
      final String stopLabel = _t(0, 'Stop');
      final String chipLabel = _t(1, 'Berjalan');

      // Build mono subtitle: "{taskId} · Stop {N}" or just taskId.
      final String monoText = taskId.isNotEmpty && stopNumber > 0
          ? '$taskId \u{00B7} $stopLabel $stopNumber'
          : taskId.isNotEmpty
          ? taskId
          : '';

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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hair),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000), // ~4% black -- subtle field lift
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top bar: center content + chip ──────────
              // (back nav handled by main AppBar; no in-body back arrow)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Center: mono id/stop + bold customer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (monoText.isNotEmpty)
                            Text(
                              monoText,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                letterSpacing: 0.2,
                                color: _mono,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (customer.isNotEmpty) ...[
                            if (monoText.isNotEmpty) const SizedBox(height: 2),
                            Text(
                              customer,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                                color: _ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          // Render title unconditionally for diagnostic.
                          // Uses text slot [0] -- slot [1] belongs to the chip
                          // on the right; reusing it here printed the same
                          // string on both sides.
                          if (monoText.isEmpty && customer.isEmpty)
                            Text(
                              stopLabel.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Chip: "BERJALAN" (pulse dot + label)
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: _accentBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            chipLabel.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Address band ──────────────────────────────────
              if (address.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: const BoxDecoration(
                    color: _accentBg,
                    border: Border(
                      top: BorderSide(color: Color(0xFFE0E7FF)), // indigo-100
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 15,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: _accent,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
