import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import '../screen_session.dart';
import 'custody_stepper.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_COUNT_LIST -- blind stepper list for P6 CustodyCount.
///
/// Subscribes vehicle_check (for the opening doc's `ie[]` manifest) and item
/// (for name + category JOIN). For each `ie[]` entry whose joined category
/// matches [filter], renders a row: item name + compact -/value/+ stepper.
///
/// `blind == TRUE` means `ie[].qt` (warehouse expected qty) is NOT displayed.
///
/// Driver-entered counts are held in a per-scrName static map keyed by
/// `ii__cd` (item id + condition). P7/P8 will read this store to build `ip[]`.
/// The store is cleared on route change via [clearCountStore], which is called
/// from the buildPage clear hook in ui_component.dart.
///
/// Read-only for Firestore: no txfController, no saveSend, no history.
class CustodyCountList extends StatefulWidget {
  const CustodyCountList({
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

  // ── Per-screen count store (reactive) ──────────────────────────────────

  /// Per-scrName count store: `{scrName: {ii__cd: CountEntry}}`.
  /// Written by stepper taps. Read by CustodyCountSubmit to build `ip[]`.
  /// Cleared on route change via [clearCountStore].
  ///
  /// Plain Map (mutated in build without notifying). The SEPARATE
  /// CustodyCountSubmit widget (Obx) rebuilds via the [countRev] signal when
  /// any stepper changes -- cross-widget reactivity via GetX.
  static final Map<String, Map<String, CountEntry>> countStore =
      <String, Map<String, CountEntry>>{};

  /// Revision counter: bumped whenever a cross-widget Obx rebuild is needed.
  /// Obx reads this instead of the now-plain countStore.
  static final RxInt countRev = 0.obs;

  /// Get or create the count map for a screen.
  static Map<String, CountEntry> getCountMap(String scrName) {
    registerScreenSession();
    return countStore.putIfAbsent(scrName, () => <String, CountEntry>{});
  }

  static void registerScreenSession() {
    ScreenSession.ensure(
      'CustodyCountList.countStore',
      CustodyCountList.clearCountStore,
    );
  }

  /// Clear count store for a screen. Called from buildPage alongside
  /// clearDriverHomeState.
  static void clearCountStore(String scrName) {
    countStore.remove(scrName);
    countRev.value++;
  }

  /// Compute seed values for a recount pass.
  ///
  /// Returns a record with:
  /// - [seeds]: `{ii__cd: seedQty}` for each ie entry.
  /// - [cleared]: set of countKeys that were CLEARED (need recount).
  ///
  /// If [ipEntries] is empty (first-time blind count), returns empty maps --
  /// the caller uses the default qty 0 for all rows (byte-identical to today).
  ///
  /// Seed rule per `ii__cd` key:
  /// - ip absent from map -> seed 0, mark cleared (never counted).
  /// - ip.qt == ie.qt -> seed ip.qt (KEEP -- driver does not recount).
  /// - ip.qt != ie.qt -> seed 0, mark cleared (CLEAR -- driver recounts).
  static ({Map<String, int> seeds, Set<String> cleared}) computeRecountSeeds({
    required List<Map<String, dynamic>> ieEntries,
    required List<Map<String, dynamic>> ipEntries,
  }) {
    if (ipEntries.isEmpty) {
      return (seeds: const <String, int>{}, cleared: const <String>{});
    }
    // Build ip lookup: {ii__cd: qt}
    final Map<String, int> ipMap = <String, int>{};
    for (final Map<String, dynamic> entry in ipEntries) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      final String cd = (entry['cd'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final int qt = int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
      ipMap['${ii}__$cd'] = qt;
    }
    final Map<String, int> seeds = <String, int>{};
    final Set<String> cleared = <String>{};
    for (final Map<String, dynamic> entry in ieEntries) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      final String cd = (entry['cd'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final int ieQt =
          int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
      final String key = '${ii}__$cd';
      if (!ipMap.containsKey(key)) {
        seeds[key] = 0;
        cleared.add(key);
      } else if (ipMap[key] == ieQt) {
        seeds[key] = ipMap[key]!;
      } else {
        seeds[key] = 0;
        cleared.add(key);
      }
    }
    return (seeds: seeds, cleared: cleared);
  }

  /// Per-scrName flag: whether #ACTIVE_WAREHOUSE was published for this screen.
  /// Static map (not instance field) so clearData can reset it even though
  /// linkElement caches the widget State across navigations.
  static final Map<String, bool> _warehousePublished = {};

  /// Reset the warehouse-published flag for a screen. Called from
  /// ExecutorDesignateCard.clearO1State on route change so reopen re-reads gl.
  static void resetWarehousePublished(String scrName) {
    _warehousePublished.remove(scrName);
  }

  @override
  State<CustodyCountList> createState() => _CustodyCountListState();
}

class _CustodyCountListState extends State<CustodyCountList> {
  String _checkCode = ''; // vehicle_check subscription code
  String _itemCode = ''; // item subscription code
  String _taskCode = ''; // O1: task subscription code
  String _assetCacheCode = ''; // C1: asset_cache subscription code

  @override
  void initState() {
    super.initState();
    CustodyCountList.registerScreenSession();
    _subscribe();
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // vehicle_check subscription (source of ie[] manifest)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }

    // item subscription (JOIN for name + category)
    final String rawJoinTable = (widget.component['joinTable'] ?? '')
        .toString()
        .trim();
    if (rawJoinTable.isNotEmpty) {
      final TablePath jtp = parseTablePath(rawJoinTable);
      if (jtp.tableDocId.isNotEmpty) {
        _itemCode = '$appVid/${jtp.tableDocId}/${jtp.subColl}';
        subscribeToMapCollection(
          appVid,
          jtp.tableDocId,
          jtp.subColl,
          _itemCode,
        );
      }
    }

    // O1: task subscription (source of aggregate plan items).
    // Gated by the `aggregate` config field -- absent for P6 (no task sub).
    final String aggregate = (widget.component['aggregate'] ?? '')
        .toString()
        .trim();
    if (aggregate.isNotEmpty) {
      final String rawTaskTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
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

    // C1: asset_cache subscription (source of expected cargo remaining).
    // Gated by `source == 'asset_cache'` config -- absent for P6 and O1.
    // For C1, the `table` config field points to asset_cache (not
    // vehicle_check ie[], not task). We use a SEPARATE _assetCacheCode so the
    // C1 path never conflates with the P6 vehicle_check subscription on
    // _checkCode (C1 needs no ie[] extraction).
    final String source = (widget.component['source'] ?? '').toString().trim();
    if (source == 'asset_cache') {
      final String rawAcTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
      if (rawAcTable.isNotEmpty) {
        final TablePath actp = parseTablePath(rawAcTable);
        if (actp.tableDocId.isNotEmpty) {
          _assetCacheCode = '$appVid/${actp.tableDocId}/${actp.subColl}';
          subscribeToMapCollection(
            appVid,
            actp.tableDocId,
            actp.subColl,
            _assetCacheCode,
          );
        }
      }
    }
  }

  /// Find the best matching vehicle_check opening doc.
  ///
  /// Multi-trip: when the config search matches multiple same-day openings,
  /// [pickActiveOpening] provides a deterministic tie-break (newest non-closed
  /// by `t` desc). Non-opening docs fall back to matched.first.
  Map<String, dynamic>? _findCheckDoc() {
    if (_checkCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_checkCode] ?? const [],
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
    if (matched.isEmpty) return null;
    // Deterministic tie-break for opening docs (newest non-closed).
    // Falls back to matched.first when no opening-shaped docs are present
    // (non-vehicle_check table — preserves old behavior).
    final Map<String, dynamic>? activeOpening = pickActiveOpening(matched);
    return activeOpening ?? matched.first;
  }

  /// Extract the ie[] items array from the check doc.
  List<Map<String, dynamic>> _extractIeEntries(Map<String, dynamic>? checkDoc) {
    if (checkDoc == null) return const [];
    final String itemsField = (widget.component['itemsField'] ?? 'ie')
        .toString()
        .trim();
    final dynamic rawItems = checkDoc[itemsField];
    if (rawItems is! List) return const [];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      out.add(Map<String, dynamic>.from(entry));
    }
    return out;
  }

  /// Parse the filter field: "ic◼returnable" -> (filterField, filterValue).
  /// Returns null if malformed.
  _FilterPair? _parseFilter() {
    final String raw = (widget.component['filter'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    // autheniumDecode in case server sent _25FC_ escapes
    final String decoded = autheniumDecode(raw) ?? raw;
    final int sep = decoded.indexOf('\u{25FC}');
    if (sep < 0) return null;
    final String field = decoded.substring(0, sep).trim();
    final String value = decoded.substring(sep + 1).trim();
    if (field.isEmpty || value.isEmpty) return null;
    return _FilterPair(field, value);
  }

  /// Build the filtered item rows: ie[] entries whose joined category matches
  /// the filter.
  List<_CountRow> _buildRows(
    List<Map<String, dynamic>> ieEntries,
    Map<String, ItemDetail> itemDetailMap,
    _FilterPair? filter, {
    ({Map<String, int> seeds, Set<String> cleared})? recountResult,
  }) {
    final List<_CountRow> rows = <_CountRow>[];
    final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
      widget.scrName,
    );
    // W1: detect whether the row set grew this build (e.g. cold/async data
    // load). If it did, schedule a one-shot post-frame countRev bump so the
    // SEPARATE CustodyCountSubmit (Obx on countRev) updates its n/N denominator
    // even when no stepper has been tapped yet.
    final int sizeBefore = countMap.length;
    for (final Map<String, dynamic> entry in ieEntries) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final String cd = (entry['cd'] ?? '').toString().trim();

      // JOIN: look up the item detail for this ii
      final ItemDetail? detail = itemDetailMap[ii];

      // FILTER: if a filter is set, only include entries whose joined category
      // matches the filter value.
      if (filter != null) {
        if (detail == null) continue; // unknown item -> exclude
        // Read the filter field from the joined detail
        final String categoryValue = filter.field == 'ic'
            ? detail.category
            : ''; // only 'ic' filter is currently defined
        if (categoryValue != filter.value) continue;
      }

      // Item name from the join
      final String name = (detail != null && detail.name.isNotEmpty)
          ? detail.name
          : ii;

      // Composite count-store key
      final String countKey = '${ii}__$cd';

      rows.add(
        _CountRow(
          ii: ii,
          cd: cd,
          name: name,
          category: detail?.category ?? '',
          countKey: countKey,
          needsRecount: recountResult?.cleared.contains(countKey) ?? false,
        ),
      );

      // Register in count store. On recount, seed matched rows with their
      // previous ip.qt; cleared rows seed 0 (driver recounts those).
      final int seedQty = recountResult?.seeds[countKey] ?? 0;
      countMap.putIfAbsent(
        countKey,
        () => CountEntry(ii: ii, cd: cd, qty: seedQty),
      );
    }

    // W1: only refresh if the row set actually grew, scheduled post-frame to
    // avoid refresh-during-build re-entrancy (which would loop infinitely).
    if (countMap.length > sizeBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CustodyCountList.countRev.value++;
      });
    }
    return rows;
  }

  /// O1 path: aggregate plan items from task docs using the shared
  /// aggregatePlanByItem helper (driver_home_support.dart).
  List<_CountRow> _buildAggregateRows(
    Map<String, ItemDetail> itemDetailMap,
    _FilterPair? filter,
  ) {
    if (_taskCode.isEmpty) return const [];

    // 1. Get and filter task docs
    final List<Map<String, dynamic>> taskDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_taskCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final List<Map<String, dynamic>> filtered = rawSearch.isNotEmpty
        ? filterDriverHomeDocs(taskDocs, rawSearch, widget.scrName)
        : taskDocs;

    // 2. Exclude by status
    final String excludeStatus = (widget.component['excludeStatus'] ?? '')
        .toString()
        .trim();
    final List<Map<String, dynamic>> tasks = excludeByStatus(
      filtered,
      excludeStatus,
    );

    // Publish #ACTIVE_WAREHOUSE once per scrName (from first task's gl field)
    if (CustodyCountList._warehousePublished[widget.scrName] != true &&
        tasks.isNotEmpty) {
      final String gl = (tasks.first['gl'] ?? '').toString().trim();
      if (gl.isNotEmpty) {
        CustodyCountList._warehousePublished[widget.scrName] = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#ACTIVE_WAREHOUSE': gl})),
          );
        });
      }
    }

    // 3. Aggregate using shared pure helper
    final String itemsField = (widget.component['aggregate'] ?? 'it')
        .toString()
        .trim();
    final String planField = (widget.component['planField'] ?? 'pd')
        .toString()
        .trim();
    final String saleField = (widget.component['saleField'] ?? 'ps')
        .toString()
        .trim();
    final String refillField = (widget.component['refillField'] ?? 'pr')
        .toString()
        .trim();

    final PlanAggregate agg = aggregatePlanByItem(
      tasks,
      itemsField: itemsField,
      deliverField: planField,
      saleField: saleField,
      refillField: refillField,
      excludeStatus: '', // already excluded above
    );

    // 4-5-6. Build count rows with filter + JOIN
    final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
      widget.scrName,
    );
    final int sizeBefore = countMap.length;
    final String writeCond = (widget.component['writeCond'] ?? '')
        .toString()
        .trim();
    final List<_CountRow> rows = <_CountRow>[];

    for (final String ii in agg.iiOrder) {
      final ItemDetail? detail = itemDetailMap[ii];

      // Filter by category
      if (filter != null) {
        if (detail == null) continue;
        final String categoryValue = filter.field == 'ic'
            ? detail.category
            : '';
        if (categoryValue != filter.value) continue;
      }

      final String name = (detail != null && detail.name.isNotEmpty)
          ? detail.name
          : ii;
      final String cd = writeCond.isNotEmpty ? writeCond : 'full';
      final String countKey = '${ii}__$cd';
      final int planQty = agg.totals[ii] ?? 0;

      rows.add(
        _CountRow(
          ii: ii,
          cd: cd,
          name: name,
          category: detail?.category ?? '',
          countKey: countKey,
          planQty: planQty,
        ),
      );

      countMap.putIfAbsent(countKey, () => CountEntry(ii: ii, cd: cd, qty: 0));
    }

    if (countMap.length > sizeBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CustodyCountList.countRev.value++;
      });
    }
    return rows;
  }

  /// C1 path: build count rows from asset_cache docs.
  ///
  /// Each asset_cache doc has ii (item id), cd (condition: full/empty),
  /// qt (expected quantity). The checker counts physical items; each row
  /// gets planQty = asset_cache qt, count start 0.
  ///
  /// Sets CountEntry.planQty so the C1 submit can build the reconciliation
  /// expected map from the count store without re-subscribing.
  List<_CountRow> _buildAssetCacheRows(
    Map<String, ItemDetail> itemDetailMap,
    _FilterPair? filter,
  ) {
    if (_assetCacheCode.isEmpty) return const [];

    // 1. Get and filter asset_cache docs
    final List<Map<String, dynamic>> acDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_assetCacheCode] ?? const <Map<String, dynamic>>[],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final List<Map<String, dynamic>> filtered = rawSearch.isNotEmpty
        ? filterDriverHomeDocs(acDocs, rawSearch, widget.scrName)
        : acDocs;

    // 2. Read config field names
    final String condField = (widget.component['condField'] ?? 'cd')
        .toString()
        .trim();
    final String qtyField = (widget.component['qtyField'] ?? 'qt')
        .toString()
        .trim();

    // 3. Build count rows
    final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
      widget.scrName,
    );
    final int sizeBefore = countMap.length;
    final List<_CountRow> rows = <_CountRow>[];

    for (final Map<String, dynamic> doc in filtered) {
      final String ii = (doc['ii'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final String cd = (doc[condField] ?? '').toString().trim();
      final int expectedQty = coerceNum(doc[qtyField]).toInt();

      // JOIN: item detail for name + category
      final ItemDetail? detail = itemDetailMap[ii];

      // FILTER: by category if configured
      if (filter != null) {
        if (detail == null) continue;
        final String categoryValue = filter.field == 'ic'
            ? detail.category
            : '';
        if (categoryValue != filter.value) continue;
      }

      final String name = (detail != null && detail.name.isNotEmpty)
          ? detail.name
          : ii;
      final String countKey = '${ii}__$cd';

      rows.add(
        _CountRow(
          ii: ii,
          cd: cd,
          name: name,
          category: detail?.category ?? '',
          countKey: countKey,
          planQty: expectedQty,
        ),
      );

      // Register in count store with planQty for reconcile at submit.
      final CountEntry existing = countMap.putIfAbsent(
        countKey,
        () => CountEntry(ii: ii, cd: cd, qty: 0, planQty: expectedQty),
      );
      // Update planQty even if the entry exists (asset_cache may reload).
      existing.planQty = expectedQty;
    }

    if (countMap.length > sizeBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CustodyCountList.countRev.value++;
      });
    }
    return rows;
  }

  void _onCountChanged(String countKey, int newValue, String ii, String cd) {
    final Map<String, CountEntry> map = CustodyCountList.getCountMap(
      widget.scrName,
    );
    final CountEntry entry = map.putIfAbsent(
      countKey,
      () => CountEntry(ii: ii, cd: cd),
    );
    entry.qty = newValue;
    // Trigger cross-widget Obx rebuild (CustodyCountSubmit reads countRev).
    CustodyCountList.countRev.value++;
    // Local rebuild for this widget's stepper display.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch vehicleId to register Obx dependency (search uses {vehicleId}).
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;

      // Gate: O1 task-aggregate path when `aggregate` config is non-empty;
      // otherwise the existing P6 single-doc ie[] path (UNCHANGED).
      final String aggregate = (widget.component['aggregate'] ?? '')
          .toString()
          .trim();
      final bool isAggregate = aggregate.isNotEmpty;

      // Build item detail map from the item collection (shared by both paths)
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final String joinKey = (widget.component['joinKey'] ?? 'ii')
          .toString()
          .trim();
      final String labelField = (widget.component['labelField'] ?? 'in')
          .toString()
          .trim();
      final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
        itemDocs,
        idField: joinKey,
        nameField: labelField,
      );

      final _FilterPair? filter = _parseFilter();

      // C1 gate: asset_cache source path when `source == 'asset_cache'`.
      final String source = (widget.component['source'] ?? '')
          .toString()
          .trim();
      final bool isAssetCache = source == 'asset_cache';

      final List<_CountRow> rows;
      if (isAssetCache) {
        // C1 path: asset_cache source
        mapTableContent[_assetCacheCode]; // register Obx dependency
        rows = _buildAssetCacheRows(itemDetailMap, filter);
      } else if (isAggregate) {
        // O1 path: task-aggregate (UNCHANGED)
        mapTableContent[_taskCode]; // register Obx dependency on task data
        rows = _buildAggregateRows(itemDetailMap, filter);
      } else {
        // P6 path: find the vehicle_check opening doc + ie[] + ip[] for recount
        final Map<String, dynamic>? checkDoc = _findCheckDoc();
        final List<Map<String, dynamic>> ieEntries = _extractIeEntries(
          checkDoc,
        );
        // Extract ip[] for recount seeding (same doc, 'ip' field).
        // Mirrors custody_reveal.dart _extractArray pattern (lines 179-190).
        List<Map<String, dynamic>> ipEntries = const [];
        if (checkDoc != null) {
          final String actualField = (widget.component['actualField'] ?? 'ip')
              .toString()
              .trim();
          final dynamic rawIp = checkDoc[actualField];
          if (rawIp is List) {
            ipEntries = <Map<String, dynamic>>[
              for (final dynamic e in rawIp)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          }
        }
        final recountResult = CustodyCountList.computeRecountSeeds(
          ieEntries: ieEntries,
          ipEntries: ipEntries,
        );
        rows = _buildRows(
          ieEntries,
          itemDetailMap,
          filter,
          recountResult: recountResult,
        );
      }

      // Read count store (reactive: touch revision signal for Obx)
      CustodyCountList
          .countRev
          .value; // register Obx dependency (revision signal)
      final Map<String, CountEntry> countMap = CustodyCountList.getCountMap(
        widget.scrName,
      );

      if (rows.isEmpty) {
        return const SizedBox.shrink();
      }

      // O1 shows the plan ("Ekspektasi: N") when blind == FALSE.
      final bool showPlan =
          (widget.component['blind'] ?? 'TRUE').toString().toUpperCase() ==
          'FALSE';

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildItemRow(rows[i], countMap, showPlan: showPlan),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildItemRow(
    _CountRow row,
    Map<String, CountEntry> countMap, {
    bool showPlan = false,
  }) {
    final int currentValue = countMap[row.countKey]?.qty ?? 0;

    // O1 delta (fisik - plan), only when the plan is visible (showPlan).
    // P6 path (showPlan == false) leaves statusLine null + no Ekspektasi label,
    // keeping the existing render byte-identical.
    final int delta = currentValue - row.planQty;
    Widget? statusLine;
    if (showPlan) {
      final String deltaLabel;
      final Color deltaColor;
      if (delta == 0) {
        deltaLabel = '\u{2713} Pas';
        deltaColor = const Color(0xFF0F766E); // teal-700 (match)
      } else if (delta > 0) {
        deltaLabel = 'Lebih: +$delta';
        deltaColor = const Color(0xFF6D28D9); // violet-700 (over)
      } else {
        deltaLabel = 'Kurang: $delta';
        deltaColor = const Color(0xFFB45309); // amber-700 (under)
      }
      statusLine = Text(
        deltaLabel,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: deltaColor,
        ),
      );
    }

    // Recount marker for P6: cleared rows show amber hint.
    // Only when showPlan is false (P6 blind mode) and the row was cleared
    // by the recount seed rule. O1/C1 paths never enter _buildRows, so
    // their _CountRow.needsRecount is always false.
    if (!showPlan && row.needsRecount) {
      statusLine = Text(
        '\u{26A0} Perlu hitung ulang',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB45309), // amber-700 (same as "Kurang:" branch)
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Item name + optional category chip (+ O1 "Ekspektasi: N" when shown)
        Row(
          children: [
            Flexible(
              child: Text(
                row.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B), // slate-800
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (row.category.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6), // gray-100
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  row.category.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280), // gray-500
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
            if (showPlan) ...[
              const SizedBox(width: 8),
              Text(
                'Ekspektasi: ${row.planQty}',
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8), // slate-400
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Full-width neutral stepper (statusLine null for P6 -> identical)
        CustodyStepper(
          value: currentValue,
          onDecrement: currentValue > 0
              ? () => _onCountChanged(
                  row.countKey,
                  currentValue - 1,
                  row.ii,
                  row.cd,
                )
              : null,
          onIncrement: () =>
              _onCountChanged(row.countKey, currentValue + 1, row.ii, row.cd),
          min: 0,
          enabled: true,
          // neutral: no frameBg/frameBorder/numberColor (defaults to white/slate)
          statusLine: statusLine,
        ),
      ],
    );
  }
}

// ── Internal helpers ─────────────────────────────────────────────────────

/// Parsed filter: (field, value) from "ic◼returnable".
class _FilterPair {
  final String field;
  final String value;
  const _FilterPair(this.field, this.value);
}

/// One row in the count list.
class _CountRow {
  final String ii;
  final String cd;
  final String name;
  final String category; // from joined item detail
  final String countKey; // "ii__cd"
  final int planQty; // 0 for P6 blind mode, >0 for O1 visible plan
  final bool needsRecount; // true for cleared rows in P6 recount
  const _CountRow({
    required this.ii,
    required this.cd,
    required this.name,
    required this.category,
    required this.countKey,
    this.planQty = 0,
    this.needsRecount = false,
  });
}
