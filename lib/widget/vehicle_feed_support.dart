import 'package:intl/intl.dart';

import 'driver_home_support.dart'; // stopStatusOf, todayEpochMidnightWib
import 'dsl_eq.dart';

/// The only task status that contributes to the category summary (load
/// preview). Tasks with any other status (completed, failed, load_rejected,
/// etc.) are excluded from the summary count.
///
/// Compared against the RAW `tst` field value (trimmed), NOT the normalized
/// `stopStatusOf` result -- stopStatusOf folds both `assigned` and
/// `load_rejected` into `'pending'`, so using it would leak rejected tasks
/// into the summary.
///
/// See: warehouse-feed-summary-status dev spec section 2/3.
const String kLoadableStatus = 'assigned';

// ─── Tier enum ────────────────────────────────────────────────────────────────

/// Vehicle tier in the H1 feed. Evaluation order matters (see [deriveVehicleTier]).
enum VehicleTier { loading, custodyPending, inRoute, returning, completed }

// ─── Feed entry ───────────────────────────────────────────────────────────────

/// One row in the H1 vehicle feed: a stock_location doc enriched with its
/// derived tier and supporting data.
class VehicleFeedEntry {
  /// stock_location doc id (`lv`).
  final String lv;

  /// License plate (`ln`).
  final String plate;

  /// Driver VID (`dv`); empty = unassigned.
  final String driverVid;

  /// Driver display name (`dn`); empty when dv empty.
  final String driverName;

  /// Derived tier.
  final VehicleTier tier;

  /// Opening doc (first match `cty=opening, vv=lv`), or null.
  final Map<String, dynamic>? openingDoc;

  /// Closing doc (first match `cty=closing, vv=lv`), or null.
  final Map<String, dynamic>? closingDoc;

  /// Task docs for this vehicle + today.
  final List<Map<String, dynamic>> tasks;

  /// Category summary string ("3 returnable . 1 consumable").
  final String categorySummary;

  /// Stop progress: done/total (for in_route tier).
  final int stopsDone;
  final int stopsTotal;

  const VehicleFeedEntry({
    required this.lv,
    required this.plate,
    required this.driverVid,
    required this.driverName,
    required this.tier,
    this.openingDoc,
    this.closingDoc,
    this.tasks = const [],
    this.categorySummary = '',
    this.stopsDone = 0,
    this.stopsTotal = 0,
  });
}

// ─── Snapshot counts ──────────────────────────────────────────────────────────

/// Snapshot counts for the header's 3 boxes.
class VehicleSnapshot {
  /// returning + custody_pending.
  final int perluTindakan;

  /// loading.
  final int openingCheck;

  /// Total feed rows.
  final int hariIni;

  const VehicleSnapshot({
    required this.perluTindakan,
    required this.openingCheck,
    required this.hariIni,
  });
}

/// Compute snapshot counts from a list of feed entries.
VehicleSnapshot computeSnapshot(List<VehicleFeedEntry> entries) {
  int perluTindakan = 0;
  int openingCheck = 0;
  for (final e in entries) {
    if (e.tier == VehicleTier.returning ||
        e.tier == VehicleTier.custodyPending) {
      perluTindakan++;
    } else if (e.tier == VehicleTier.loading) {
      openingCheck++;
    }
  }
  return VehicleSnapshot(
    perluTindakan: perluTindakan,
    openingCheck: openingCheck,
    hariIni: entries.length,
  );
}

// ─── Tier derivation ──────────────────────────────────────────────────────────

/// Derive the tier for a single stock_location vehicle.
///
/// [dv] -- driver vid (empty = unassigned).
/// [openingDoc] -- first vehicle_check with cty=opening, vv=lv (null = absent).
/// [closingDoc] -- first vehicle_check with cty=closing, vv=lv (null = absent).
/// [taskDocs] -- task docs for this vehicle + today.
/// [cstField] -- field name for the custody status on the opening doc.
/// [tstField] -- field name for task state.
VehicleTier deriveVehicleTier({
  required String dv,
  Map<String, dynamic>? openingDoc,
  Map<String, dynamic>? closingDoc,
  List<Map<String, dynamic>> taskDocs = const [],
  String cstField = 'cst',
  String tstField = 'tst',
}) {
  // 1. dv empty -> loading (backlog, no date filter)
  if (dv.isEmpty) return VehicleTier.loading;

  // Trip-sequence: closing-doc-exists or cst=='closed' no longer maps to
  // completed. Closed vehicles return to backlog immediately (dv/dn cleared
  // on close -> dv.isEmpty guard above returns VehicleTier.loading).
  // If dv/dn clear races (dv still set when cst is already closed), fall
  // through to the default loading fallback below.
  //
  // NOTE for coder: VehicleTier.completed remains in the enum but is now
  // never emitted by this function. groupFeedBySections still has a
  // `case VehicleTier.completed:` that adds to the `selesai` list, but
  // that list will always be empty. The `if (selesai.isNotEmpty)` guard
  // (vehicle_feed_support.dart:467) prevents the "Selesai Hari Ini"
  // section header from rendering. Verify during manual testing that no
  // empty section appears. Leave the enum value in place (removal has wider
  // blast radius across grouping, computeSnapshot, card-tap routing,
  // card rendering in vehicle_feed_list.dart).
  final String cst = openingDoc != null
      ? (openingDoc[cstField] ?? '').toString().trim()
      : '';
  if (cst == 'closed') return VehicleTier.loading;

  // 2. cst == awaiting_custody -> custody_pending
  if (cst == 'awaiting_custody') return VehicleTier.custodyPending;

  // 3 & 4: cst == custody_confirmed -> check tasks
  if (cst == 'custody_confirmed') {
    // Check if ANY task is NOT done/failed
    bool anyOpen = false;
    for (final doc in taskDocs) {
      final String status = stopStatusOf(doc, tstField: tstField);
      if (status != 'done' && status != 'failed') {
        anyOpen = true;
        break;
      }
    }
    // Also: if there are no tasks at all, treat as returning (all done vacuously)
    if (anyOpen) return VehicleTier.inRoute;

    // 4. All tasks done/failed + no closing doc -> returning
    return VehicleTier.returning;
  }

  // Fallback: loading (shouldn't happen with well-formed data)
  return VehicleTier.loading;
}

// ─── Per-vehicle category summary ─────────────────────────────────────────────

/// Count distinct items per category across a vehicle's task docs.
///
/// [taskDocs] -- task docs for this vehicle.
/// [itemsField] -- key for the nested items array (default `it`).
/// [idField] -- key for item id inside each item entry (default `ii`).
/// [categoryMap] -- `Map<String, String>` from item id to category (e.g. from
///   item master docs: ii -> ic). Items not in the map are counted under
///   'unknown'.
///
/// Returns a `Map<String, int>` of category -> distinct item count.
/// Convention #7: dynamic guards throughout.
Map<String, int> countDistinctItemsByCategory(
  List<Map<String, dynamic>> taskDocs,
  Map<String, String> categoryMap, {
  String itemsField = 'it',
  String idField = 'ii',
}) {
  // Collect distinct item ids across all tasks
  final Set<String> seenIds = <String>{};
  for (final doc in taskDocs) {
    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue;
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      final String id = (entry[idField] ?? '').toString().trim();
      if (id.isNotEmpty) seenIds.add(id);
    }
  }

  // Group by category
  final Map<String, int> result = <String, int>{};
  for (final id in seenIds) {
    final String cat = categoryMap[id] ?? 'unknown';
    result[cat] = (result[cat] ?? 0) + 1;
  }
  return result;
}

/// Format category counts into a display string: "3 returnable . 1 consumable".
/// Empty map -> empty string. Only non-zero categories appear. Order:
/// returnable first, then consumable, then any others alphabetically.
///
/// Issue W3: if the ONLY contributing category is `unknown` (returnable == 0
/// AND consumable == 0 AND every non-zero entry is `unknown`), return '' so the
/// card degrades to NO summary line rather than showing "N unknown". Known
/// categories (returnable/consumable) always render as before.
String formatCategorySummary(Map<String, int> categoryCounts) {
  if (categoryCounts.isEmpty) return '';

  final List<String> parts = <String>[];

  // Returnable first
  final int ret = categoryCounts['returnable'] ?? 0;
  if (ret > 0) parts.add('$ret returnable');

  // Consumable second
  final int con = categoryCounts['consumable'] ?? 0;
  if (con > 0) parts.add('$con consumable');

  // Any other categories alphabetically
  final List<String> others =
      categoryCounts.keys
          .where((k) => k != 'returnable' && k != 'consumable')
          .toList()
        ..sort();
  for (final k in others) {
    final int v = categoryCounts[k]!;
    if (v > 0) parts.add('$v $k');
  }

  // Issue W3: suppress an all-unknown summary. If no known category
  // contributed (ret == 0 && con == 0) and the only non-zero parts are
  // 'unknown', degrade to no summary line.
  if (ret <= 0 && con <= 0) {
    final bool onlyUnknown = others.every((k) => k == 'unknown');
    if (onlyUnknown) return '';
  }

  return parts.join(' \u{00B7} '); // middle dot
}

// ─── Time formatting ──────────────────────────────────────────────────────────

/// Format an epoch-ms value to "HH:mm". Returns empty string if [epochMs] is
/// null, empty, 0, or not parseable.
String formatEpochTime(dynamic epochMs) {
  if (epochMs == null) return '';
  final int? ms = epochMs is int
      ? epochMs
      : int.tryParse(epochMs.toString().trim());
  if (ms == null || ms <= 0) return '';
  try {
    return DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
  } catch (_) {
    return '';
  }
}

// ─── Stop progress for in_route ───────────────────────────────────────────────

/// Count done (done+failed) and total tasks.
/// Returns (done, total).
({int done, int total}) countStopProgress(
  List<Map<String, dynamic>> taskDocs, {
  String tstField = 'tst',
}) {
  int done = 0;
  for (final doc in taskDocs) {
    final String status = stopStatusOf(doc, tstField: tstField);
    if (status == 'done' || status == 'failed') done++;
  }
  return (done: done, total: taskDocs.length);
}

// ─── Full feed builder ────────────────────────────────────────────────────────

/// Build the complete feed from raw collection data.
///
/// This is the SINGLE source of truth for:
/// 1. Filtering stock_location to vehicles.
/// 2. Looking up opening/closing docs per lv.
/// 3. Looking up task docs per lv + today.
/// 4. Deriving tier.
/// 5. Building the category summary.
/// 6. Computing stop progress.
///
/// Pure function -- no Rx, no Obx, no side effects. The widget calls this
/// inside its Obx and gets back a typed `List<VehicleFeedEntry>`.
///
/// [stockDocs] -- all stock_location docs from mapTableContent.
/// [vehicleCheckDocs] -- all vehicle_check docs from mapTableContent.
/// [taskDocs] -- all task docs from mapTableContent.
/// [categoryMap] -- item id -> category (from item master).
/// [todayEpoch] -- epoch-ms-string of today's midnight WIB.
/// [cstField] -- field name for custody status on vehicle_check.
/// [tstField] -- field name for task state.
/// [itemsField] -- field name for items array on task docs.
/// [plateField] -- field name for plate on stock_location.
/// [executorField] -- field name for driver vid on stock_location.
/// [executorNameField] -- field name for driver name on stock_location.
List<VehicleFeedEntry> buildVehicleFeed({
  required List<Map<String, dynamic>> stockDocs,
  required List<Map<String, dynamic>> vehicleCheckDocs,
  required List<Map<String, dynamic>> taskDocs,
  required Map<String, String> categoryMap,
  required String todayEpoch,
  String cstField = 'cst',
  String tstField = 'tst',
  String itemsField = 'it',
  String plateField = 'ln',
  String executorField = 'dv',
  String executorNameField = 'dn',
}) {
  // Pre-index vehicle_check docs by vv (vehicle vid)
  // openingByVv[lv] = list of opening docs for that vehicle
  // closingByVv[lv] = list of closing docs for that vehicle
  final Map<String, List<Map<String, dynamic>>> openingByVv = {};
  final Map<String, List<Map<String, dynamic>>> closingByVv = {};
  for (final doc in vehicleCheckDocs) {
    final String cty = (doc['cty'] ?? '').toString().trim();
    final String vv = (doc['vv'] ?? '').toString().trim();
    if (vv.isEmpty) continue;
    if (cty == 'opening') {
      openingByVv.putIfAbsent(vv, () => []).add(doc);
    } else if (cty == 'closing') {
      closingByVv.putIfAbsent(vv, () => []).add(doc);
    }
  }

  // Pre-index task docs by vv AND tdt==today
  final Map<String, List<Map<String, dynamic>>> tasksByVv = {};
  for (final doc in taskDocs) {
    final String vv = (doc['vv'] ?? '').toString().trim();
    final String tdt = (doc['tdt'] ?? '').toString().trim();
    if (vv.isEmpty) continue;
    if (eq(tdt, todayEpoch)) {
      tasksByVv.putIfAbsent(vv, () => []).add(doc);
    }
  }

  final List<VehicleFeedEntry> entries = [];

  for (final slDoc in stockDocs) {
    final String lv = (slDoc['lv'] ?? '').toString().trim();
    if (lv.isEmpty) continue;

    final String plate = (slDoc[plateField] ?? '').toString().trim();
    final String dv = (slDoc[executorField] ?? '').toString().trim();
    final String dn = (slDoc[executorNameField] ?? '').toString().trim();

    // Find opening/closing docs for this vehicle
    final List<Map<String, dynamic>> openings = openingByVv[lv] ?? const [];
    final List<Map<String, dynamic>> closings = closingByVv[lv] ?? const [];

    // Pick the NEWEST opening doc (sort by t desc). Multi-trip: the newest
    // non-closed opening is the active trip; if all are closed, the newest
    // closed one is used (tier derives loading via dv-empty or cst-closed).
    Map<String, dynamic>? openingDoc;
    if (openings.isNotEmpty) {
      final List<Map<String, dynamic>> sorted =
          List<Map<String, dynamic>>.from(openings)..sort((a, b) {
            final int tA = int.tryParse((a['t'] ?? '0').toString().trim()) ?? 0;
            final int tB = int.tryParse((b['t'] ?? '0').toString().trim()) ?? 0;
            return tB.compareTo(tA); // desc
          });
      // Prefer a non-closed opening (active trip) over a closed one.
      openingDoc = sorted.firstWhere(
        (d) => (d['cst'] ?? '').toString().trim() != 'closed',
        orElse: () => sorted.first,
      );
    }
    // Closing doc: not used for tier anymore (completed branch removed).
    // Kept for VehicleFeedEntry.closingDoc (display/future use).
    final Map<String, dynamic>? closingDoc = closings.isNotEmpty
        ? closings.first
        : null;

    // Task docs for this vehicle: scoped by trip (task.tr == opening doc-id)
    // ONLY when the picked opening is non-closed (an active trip). A closed
    // opening is a finished trip -- scoping to its docId would show the old
    // trip's stamped tasks and hide new-trip tasks created before the next
    // opening exists. Unstamped tasks (tr empty: admin-created, not yet
    // executed) belong to the active trip, so they pass the scope too.
    final List<Map<String, dynamic>> allVvTasks = tasksByVv[lv] ?? const [];
    final bool openingActive =
        openingDoc != null &&
        (openingDoc[cstField] ?? '').toString().trim() != 'closed';
    final String activeOpeningId = openingActive
        ? (openingDoc['__docId'] ?? '').toString()
        : '';
    List<Map<String, dynamic>> lvTasks;
    if (activeOpeningId.isNotEmpty) {
      final List<Map<String, dynamic>> trScoped = allVvTasks.where((t) {
        final String tr = (t['tr'] ?? '').toString().trim();
        return tr.isEmpty || tr == activeOpeningId;
      }).toList();
      // Fallback: if no tasks match tr (pre-CF), use all (vv, today) tasks.
      // ponytail: fallback removed when CF stamping is confirmed live.
      lvTasks = trScoped.isNotEmpty ? trScoped : allVvTasks;
    } else {
      lvTasks = allVvTasks;
    }

    // Derive tier
    final VehicleTier tier = deriveVehicleTier(
      dv: dv,
      openingDoc: openingDoc,
      closingDoc: closingDoc,
      taskDocs: lvTasks,
      cstField: cstField,
      tstField: tstField,
    );

    // (Completed-tier cdt filter removed: completed branch no longer emitted.)

    // Category summary -- scoped to loadable (assigned) tasks only.
    // Tier (line 365) and stop-progress (line 388) deliberately keep the full
    // lvTasks. See: warehouse-feed-summary-status spec section 3/4.
    final List<Map<String, dynamic>> summaryTasks = lvTasks
        .where((t) => (t[tstField] ?? '').toString().trim() == kLoadableStatus)
        .toList();
    final Map<String, int> catCounts = countDistinctItemsByCategory(
      summaryTasks,
      categoryMap,
      itemsField: itemsField,
    );
    final String catSummary = formatCategorySummary(catCounts);

    // Stop progress
    final ({int done, int total}) progress = countStopProgress(
      lvTasks,
      tstField: tstField,
    );

    entries.add(
      VehicleFeedEntry(
        lv: lv,
        plate: plate,
        driverVid: dv,
        driverName: dn,
        tier: tier,
        openingDoc: openingDoc,
        closingDoc: closingDoc,
        tasks: lvTasks,
        categorySummary: catSummary,
        stopsDone: progress.done,
        stopsTotal: progress.total,
      ),
    );
  }

  return entries;
}

/// Group feed entries into the 4 display sections (in render order).
/// Returns a list of non-empty (label, entries) pairs. Empty sections omitted.
List<({String label, List<VehicleFeedEntry> entries})> groupFeedBySections(
  List<VehicleFeedEntry> feed,
  List<String> sectionLabels,
) {
  // sectionLabels: [0] Perlu Tindakan, [1] Pengecekan Pembukaan,
  //                [2] Dalam Perjalanan, [3] Selesai Hari Ini

  final List<VehicleFeedEntry> perluTindakan = [];
  final List<VehicleFeedEntry> openingCheck = [];
  final List<VehicleFeedEntry> dalamPerjalanan = [];
  final List<VehicleFeedEntry> selesai = [];

  for (final e in feed) {
    switch (e.tier) {
      case VehicleTier.returning:
      case VehicleTier.custodyPending:
        perluTindakan.add(e);
        break;
      case VehicleTier.loading:
        openingCheck.add(e);
        break;
      case VehicleTier.inRoute:
        dalamPerjalanan.add(e);
        break;
      case VehicleTier.completed:
        selesai.add(e);
        break;
    }
  }

  final String l0 = sectionLabels.isNotEmpty
      ? sectionLabels[0]
      : 'Perlu Tindakan';
  final String l1 = sectionLabels.length > 1
      ? sectionLabels[1]
      : 'Pengecekan Pembukaan';
  final String l2 = sectionLabels.length > 2
      ? sectionLabels[2]
      : 'Dalam Perjalanan';
  final String l3 = sectionLabels.length > 3
      ? sectionLabels[3]
      : 'Selesai Hari Ini';

  final List<({String label, List<VehicleFeedEntry> entries})> sections = [];
  if (perluTindakan.isNotEmpty)
    sections.add((label: l0, entries: perluTindakan));
  if (openingCheck.isNotEmpty) sections.add((label: l1, entries: openingCheck));
  if (dalamPerjalanan.isNotEmpty)
    sections.add((label: l2, entries: dalamPerjalanan));
  if (selesai.isNotEmpty) sections.add((label: l3, entries: selesai));

  return sections;
}

// ─── Item category map builder ────────────────────────────────────────────────

/// Build a `Map<String,String>` of item id -> category from item collection docs.
///
/// [itemDocs] -- docs from the item subcollection.
/// [idField] -- field name for item id (default `ii`).
/// [categoryField] -- field name for category (default `ic`).
///
/// Convention #7: dynamic guards on field reads.
Map<String, String> buildItemCategoryMap(
  List<Map<String, dynamic>> itemDocs, {
  String idField = 'ii',
  String categoryField = 'ic',
}) {
  final Map<String, String> map = <String, String>{};
  for (final doc in itemDocs) {
    final String id = (doc[idField] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final String cat = (doc[categoryField] ?? '').toString().trim();
    if (cat.isNotEmpty) map[id] = cat;
  }
  return map;
}
