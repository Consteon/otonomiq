import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
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
    return countStore.putIfAbsent(scrName, () => <String, CountEntry>{});
  }

  /// Clear count store for a screen. Called from buildPage alongside
  /// clearDriverHomeState.
  static void clearCountStore(String scrName) {
    countStore.remove(scrName);
    countRev.value++;
  }

  @override
  State<CustodyCountList> createState() => _CustodyCountListState();
}

class _CustodyCountListState extends State<CustodyCountList> {
  String _checkCode = ''; // vehicle_check subscription code
  String _itemCode = ''; // item subscription code

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // vehicle_check subscription (source of ie[] manifest)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      _checkCode = '${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }

    // item subscription (JOIN for name + category)
    final String rawJoinTable =
        (widget.component['joinTable'] ?? '').toString().trim();
    if (rawJoinTable.isNotEmpty) {
      final TablePath jtp = parseTablePath(rawJoinTable);
      if (jtp.tableDocId.isNotEmpty) {
        _itemCode = '${jtp.tableDocId}/${jtp.subColl}';
        subscribeToMapCollection(
            appVid, jtp.tableDocId, jtp.subColl, _itemCode);
      }
    }
  }

  /// Find the first matching vehicle_check opening doc.
  Map<String, dynamic>? _findCheckDoc() {
    if (_checkCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(
            mapTableContent[_checkCode] ?? const []);
    final String rawSearch =
        (widget.component['search'] ?? '').toString().trim();
    if (rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
    final List<Map<String, dynamic>> matched =
        filterDriverHomeDocs(docs, rawSearch, widget.scrName);
    return matched.isNotEmpty ? matched.first : null;
  }

  /// Extract the ie[] items array from the check doc.
  List<Map<String, dynamic>> _extractIeEntries(Map<String, dynamic>? checkDoc) {
    if (checkDoc == null) return const [];
    final String itemsField =
        (widget.component['itemsField'] ?? 'ie').toString().trim();
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
    _FilterPair? filter,
  ) {
    final List<_CountRow> rows = <_CountRow>[];
    final Map<String, CountEntry> countMap =
        CustodyCountList.getCountMap(widget.scrName);
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
      final String name =
          (detail != null && detail.name.isNotEmpty) ? detail.name : ii;

      // Composite count-store key
      final String countKey = '${ii}__$cd';

      rows.add(_CountRow(
        ii: ii,
        cd: cd,
        name: name,
        category: detail?.category ?? '',
        countKey: countKey,
      ));

      // Register in count store (putIfAbsent qty 0) so the submit button
      // knows the total N even for untouched rows.
      countMap.putIfAbsent(
          countKey, () => CountEntry(ii: ii, cd: cd, qty: 0));
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

  void _onCountChanged(String countKey, int newValue, String ii, String cd) {
    final Map<String, CountEntry> map =
        CustodyCountList.getCountMap(widget.scrName);
    final CountEntry entry = map.putIfAbsent(
        countKey, () => CountEntry(ii: ii, cd: cd));
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

      // Step 1: Find the vehicle_check opening doc
      final Map<String, dynamic>? checkDoc = _findCheckDoc();

      // Step 2: Extract ie[] entries
      final List<Map<String, dynamic>> ieEntries = _extractIeEntries(checkDoc);

      // Step 3: Build item detail map from the item collection
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
              mapTableContent[_itemCode] ?? const []);
      final String joinKey =
          (widget.component['joinKey'] ?? 'ii').toString().trim();
      final String labelField =
          (widget.component['labelField'] ?? 'in').toString().trim();
      final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
        itemDocs,
        idField: joinKey,
        nameField: labelField,
      );

      // Step 4: Parse filter and build filtered rows
      final _FilterPair? filter = _parseFilter();
      final List<_CountRow> rows =
          _buildRows(ieEntries, itemDetailMap, filter);

      // Step 5: Read count store (reactive: touch revision signal for Obx)
      CustodyCountList.countRev.value; // register Obx dependency (revision signal)
      final Map<String, CountEntry> countMap =
          CustodyCountList.getCountMap(widget.scrName);

      if (rows.isEmpty) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildItemRow(rows[i], countMap),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildItemRow(_CountRow row, Map<String, CountEntry> countMap) {
    final int currentValue = countMap[row.countKey]?.qty ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Item name + optional category chip
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ],
        ),
        const SizedBox(height: 6),
        // Full-width neutral stepper
        CustodyStepper(
          value: currentValue,
          onDecrement: currentValue > 0
              ? () => _onCountChanged(row.countKey, currentValue - 1,
                  row.ii, row.cd)
              : null,
          onIncrement: () => _onCountChanged(
              row.countKey, currentValue + 1, row.ii, row.cd),
          min: 0,
          enabled: true,
          // neutral: no frameBg/frameBorder/numberColor (defaults to white/slate)
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
  const _CountRow({
    required this.ii,
    required this.cd,
    required this.name,
    required this.category,
    required this.countKey,
  });
}
