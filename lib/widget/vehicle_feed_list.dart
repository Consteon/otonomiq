import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';
import 'vehicle_feed_support.dart';

/// VEHICLE_FEED_LIST -- tier-grouped vehicle card list for H1 VehicleFeed.
///
/// Subscribes: stock_location, vehicle_check, task, item.
/// Groups vehicles into sections (Perlu Tindakan / Pengecekan Pembukaan /
/// Dalam Perjalanan / Selesai Hari Ini), renders per-card layout with
/// state-specific styling + action buttons for opening/closing check.
///
/// Read-only: no txfController, no saveSend, no history.
class VehicleFeedList extends StatefulWidget {
  const VehicleFeedList({
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
  State<VehicleFeedList> createState() => _VehicleFeedListState();
}

class _VehicleFeedListState extends State<VehicleFeedList> {
  List<String> _textArray = [];
  String _stockLocationCode = '';
  String _vehicleCheckCode = '';
  String _taskCode = '';
  String _itemCode = '';

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

  /// text slot accessors (7 slots):
  ///  [0] "Perlu Tindakan"
  ///  [1] "Pengecekan Pembukaan"
  ///  [2] "Dalam Perjalanan"
  ///  [3] "Selesai Hari Ini"
  ///  [4] "Pengecekan Penutupan" (closing button label)
  ///  [5] "Pengecekan Pembukaan" (opening button label)
  ///  [6] "Pengemudi belum ditentukan" (no-driver fallback)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Stock_location
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _stockLocationCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
          appVid,
          tp.tableDocId,
          tp.subColl,
          _stockLocationCode,
        );
      }
    }

    // Vehicle_check (whole collection, filter in-memory)
    final String rawOpeningGate = (widget.component['openingGate'] ?? '')
        .toString()
        .trim();
    if (rawOpeningGate.isNotEmpty) {
      final String decoded = autheniumDecode(rawOpeningGate) ?? rawOpeningGate;
      final String tablePart = decoded.split('\u{2B58}').first.trim();
      final TablePath vtp = parseTablePath(tablePart);
      if (vtp.tableDocId.isNotEmpty) {
        _vehicleCheckCode = '$appVid/${vtp.tableDocId}/${vtp.subColl}';
        subscribeToMapCollection(
          appVid,
          vtp.tableDocId,
          vtp.subColl,
          _vehicleCheckCode,
        );
      }
    }

    // Task
    final String rawTaskTable = (widget.component['taskTable'] ?? '')
        .toString()
        .trim();
    if (rawTaskTable.isNotEmpty) {
      final TablePath ttp = parseTablePath(rawTaskTable);
      if (ttp.tableDocId.isNotEmpty) {
        _taskCode = '$appVid/${ttp.tableDocId}/${ttp.subColl}';
        subscribeToMapCollection(
          appVid,
          ttp.tableDocId,
          ttp.subColl,
          _taskCode,
        );
      }
    }

    // Item (category map)
    if (rawTable.isNotEmpty) {
      final TablePath sltp = parseTablePath(rawTable);
      if (sltp.tableDocId.isNotEmpty) {
        _itemCode = '$appVid/${sltp.tableDocId}/item';
        subscribeToMapCollection(appVid, sltp.tableDocId, 'item', _itemCode);
      }
    }
  }

  void _onCardTap(VehicleFeedEntry entry) {
    String route = '';
    if (entry.tier == VehicleTier.loading) {
      route = (widget.component['openingRoute'] ?? '').toString().trim();
    } else if (entry.tier == VehicleTier.returning) {
      route = (widget.component['closingRoute'] ?? '').toString().trim();
    }
    if (route.isEmpty) return;

    // Write #ACTIVE_VEHICLE so O1/C1 can resolve {activeVehicle}
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#ACTIVE_VEHICLE': entry.lv})),
    );

    // routeStack.push BEFORE gotoRoute (invariant 1)
    routeStack.push(route);
    gotoRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Register Obx dependencies
      mapTableContent[_stockLocationCode];
      mapTableContent[_vehicleCheckCode];
      mapTableContent[_taskCode];
      mapTableContent[_itemCode];

      // Read collections
      final List<Map<String, dynamic>> stockDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_stockLocationCode] ?? const [],
          );
      final String rawSearch = (widget.component['search'] ?? '')
          .toString()
          .trim();
      final List<Map<String, dynamic>> filteredStock = rawSearch.isNotEmpty
          ? filterDriverHomeDocs(stockDocs, rawSearch, widget.scrName)
          : stockDocs;

      final List<Map<String, dynamic>> checkDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_vehicleCheckCode] ?? const [],
          );
      final List<Map<String, dynamic>> taskDocsAll =
          List<Map<String, dynamic>>.from(
            mapTableContent[_taskCode] ?? const [],
          );
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );

      final Map<String, String> categoryMap = buildItemCategoryMap(itemDocs);
      final String todayEpoch = todayEpochMidnightWib();

      final List<VehicleFeedEntry> feed = buildVehicleFeed(
        stockDocs: filteredStock,
        vehicleCheckDocs: checkDocs,
        taskDocs: taskDocsAll,
        categoryMap: categoryMap,
        todayEpoch: todayEpoch,
        cstField: (widget.component['cstField'] ?? 'cst').toString(),
        tstField: (widget.component['taskStateField'] ?? 'tst').toString(),
        itemsField: (widget.component['itemsField'] ?? 'it').toString(),
        plateField: (widget.component['plateField'] ?? 'ln').toString(),
        executorField: (widget.component['executorField'] ?? 'dv').toString(),
        executorNameField: (widget.component['executorNameField'] ?? 'dn')
            .toString(),
      );

      // Section labels from text slots
      final List<String> sectionLabels = [
        _t(0, 'Perlu Tindakan'),
        _t(1, 'Pengecekan Pembukaan'),
        _t(2, 'Dalam Perjalanan'),
        _t(3, 'Selesai Hari Ini'),
      ];

      final sections = groupFeedBySections(feed, sectionLabels);

      // Fallback labels
      final String noDriverLabel = _t(6, 'Pengemudi belum ditentukan');
      final String closingBtnLabel = _t(4, 'Pengecekan Penutupan');
      final String openingBtnLabel = _t(5, 'Pengecekan Pembukaan');

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
            for (int s = 0; s < sections.length; s++) ...[
              if (s > 0) const SizedBox(height: 16),
              _buildSectionHeader(sections[s].label, sections[s].entries),
              const SizedBox(height: 8),
              for (final entry in sections[s].entries)
                _buildVehicleCard(
                  entry: entry,
                  noDriverLabel: noDriverLabel,
                  openingBtnLabel: openingBtnLabel,
                  closingBtnLabel: closingBtnLabel,
                ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildSectionHeader(String label, List<VehicleFeedEntry> entries) {
    // Determine color: Perlu Tindakan = amber, Pengecekan Pembukaan = teal,
    // others = textDim
    final bool isPerlu =
        entries.isNotEmpty &&
        (entries.first.tier == VehicleTier.returning ||
            entries.first.tier == VehicleTier.custodyPending);
    final bool isOpening =
        entries.isNotEmpty && entries.first.tier == VehicleTier.loading;

    Color labelColor;
    Color? dotColor;
    if (isPerlu) {
      labelColor = const Color(0xFFB45309); // amber-700
      dotColor = const Color(0xFFF59E0B); // amber-400
    } else if (isOpening) {
      labelColor = const Color(0xFF0D9488); // teal-600
      dotColor = null;
    } else {
      labelColor = const Color(0xFF6B7280); // textDim
      dotColor = null;
    }

    return Row(
      children: [
        if (dotColor != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        // Issue W1: render ONLY the uppercased label (the amber dot above
        // distinguishes Perlu Tindakan). No "· N" count suffix -- counts live
        // in the header's snapshot boxes, per the design mockup.
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: labelColor,
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleCard({
    required VehicleFeedEntry entry,
    required String noDriverLabel,
    required String openingBtnLabel,
    required String closingBtnLabel,
  }) {
    // Per-tier styling
    Color borderLeftColor;
    Color cardBg;
    double cardOpacity;
    _ChipStyle chip;
    String executorSuffix;
    String? buttonLabel;
    Color? buttonColor;

    switch (entry.tier) {
      case VehicleTier.loading:
        borderLeftColor = const Color(0xFF14B8A6); // teal-500
        cardBg = Colors.white;
        cardOpacity = 1.0;
        chip = const _ChipStyle(
          'OPENING CHECK',
          Color(0xFFCCFBF1),
          Color(0xFF0D9488),
        ); // teal
        executorSuffix = ''; // dv empty -> noDriverLabel
        buttonLabel = openingBtnLabel;
        buttonColor = const Color(0xFF0D9488); // teal-600
        break;
      case VehicleTier.custodyPending:
        borderLeftColor = const Color(0xFFFBBF24); // amber-400
        cardBg = const Color(0xFFFFFBEB); // amber-50
        cardOpacity = 1.0;
        chip = const _ChipStyle(
          'CUSTODY PENDING',
          Color(0xFFFEF3C7),
          Color(0xFFD97706),
        ); // amber
        final String time = formatEpochTime(entry.openingDoc?['ldt']);
        executorSuffix = time.isNotEmpty ? ' \u{00B7} tiba $time' : '';
        buttonLabel = null; // read-only
        buttonColor = null;
        break;
      case VehicleTier.inRoute:
        borderLeftColor = Colors.transparent;
        cardBg = Colors.white;
        cardOpacity = 1.0;
        chip = const _ChipStyle(
          'IN ROUTE',
          Color(0xFFDBEAFE),
          Color(0xFF2563EB),
        ); // blue
        executorSuffix =
            ' \u{00B7} stop ${entry.stopsDone}/${entry.stopsTotal}';
        buttonLabel = null;
        buttonColor = null;
        break;
      case VehicleTier.returning:
        borderLeftColor = const Color(0xFFFBBF24); // amber-400
        cardBg = const Color(0xFFFFFBEB); // amber-50
        cardOpacity = 1.0;
        chip = const _ChipStyle(
          'CLOSING CHECK',
          Color(0xFFFEF3C7),
          Color(0xFFD97706),
        ); // amber
        final String time = formatEpochTime(entry.openingDoc?['ldt']);
        executorSuffix = time.isNotEmpty ? ' \u{00B7} tiba $time' : '';
        buttonLabel = closingBtnLabel;
        buttonColor = const Color(0xFFD97706); // amber-600
        break;
      case VehicleTier.completed:
        borderLeftColor = Colors.transparent;
        cardBg = Colors.white;
        cardOpacity = 0.65;
        chip = const _ChipStyle(
          'SELESAI',
          Color(0xFFDCFCE7),
          Color(0xFF16A34A),
        ); // green
        // Selesai time: closing doc 't', fallback opening doc 't'
        final String closingTime = formatEpochTime(entry.closingDoc?['t']);
        final String openingTime = formatEpochTime(entry.openingDoc?['t']);
        final String time = closingTime.isNotEmpty ? closingTime : openingTime;
        executorSuffix = time.isNotEmpty ? ' \u{00B7} selesai $time' : '';
        buttonLabel = null;
        buttonColor = null;
        break;
    }

    // Executor line
    final String executorText = entry.driverVid.isEmpty
        ? noDriverLabel
        : entry.driverName.isNotEmpty
        ? '${entry.driverName}$executorSuffix'
        : entry.driverVid; // vid fallback

    // Summary line
    String summaryText = entry.categorySummary;
    if (entry.tier == VehicleTier.inRoute) {
      // Issue I1: collapsed dead ternary (both branches were identical) to a
      // single assignment.
      summaryText =
          'Mid-route \u{00B7} Stop ${entry.stopsDone}/${entry.stopsTotal}';
    } else if (entry.tier == VehicleTier.completed) {
      // Check for discrepancy in closing doc
      final String rs = (entry.closingDoc?['rs'] ?? '').toString().trim();
      if (rs == 'discrepancy_detected') {
        summaryText = 'Discrepancy detected';
      } else {
        summaryText = summaryText.isNotEmpty ? summaryText : 'Clean validation';
      }
    }

    final bool tappable =
        entry.tier == VehicleTier.loading ||
        entry.tier == VehicleTier.returning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: tappable ? () => _onCardTap(entry) : null,
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
                          // ── Identity row: plate + chip ──────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.plate.isNotEmpty ? entry.plate : entry.lv,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: chip.bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  chip.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: chip.fg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // ── Executor line ──────────────────────────
                          Text(
                            executorText,
                            style: TextStyle(
                              fontSize: 13,
                              color: entry.driverVid.isEmpty
                                  ? const Color(0xFF9CA3AF) // textDim
                                  : const Color(0xFF374151), // gray-700
                              fontStyle: entry.driverVid.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // ── Summary line ───────────────────────────
                          if (summaryText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              summaryText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280), // textMid
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          // ── Action button ──────────────────────────
                          if (buttonLabel != null && buttonColor != null) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _onCardTap(entry),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: buttonColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  buttonLabel.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
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
        ),
      ),
    );
  }
}

/// Internal: chip display config per tier.
class _ChipStyle {
  final String label;
  final Color bg;
  final Color fg;
  const _ChipStyle(this.label, this.bg, this.fg);
}
