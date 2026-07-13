import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// INVENTORY_BUCKET_CARD — "Isi Kendaraan Sekarang" (DriverHome P4).
///
/// Shows vehicle stock per item (grouped by item-id, resolved to item name
/// via FK to item collection). HIDDEN when pending (!confirmed). Reads
/// asset_cache docs, groups by `ii`, sums `qt` per `cd` (condition) bucket.
class InventoryBucketCard extends StatefulWidget {
  const InventoryBucketCard({
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
  State<InventoryBucketCard> createState() => _InventoryBucketCardState();
}

class _InventoryBucketCardState extends State<InventoryBucketCard> {
  List<String> _textArray = [];
  String _dataCode = ''; // asset_cache subscription code
  String _gateCode = ''; // vehicle_check gate subscription code
  String _itemCode = ''; // item collection subscription code (name FK)
  List<BucketDef> _buckets = const [];

  /// Maps a raw category (`cd`) value -> bucket label. Built once from the
  /// component config (W2: configurable, not hardcoded English positionals).
  Map<String, String> _catToLabel = const {};

  @override
  void initState() {
    super.initState();
    _parseText();
    _parseBuckets();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (2 slots per spec §3.4):
  ///  [0] "Isi Kendaraan Sekarang"
  ///  [1] "Update otomatis tiap serah-terima (kirim isi, ambil kosong)."
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _parseBuckets() {
    final String raw = (widget.component['buckets'] ?? '').toString().trim();
    // autheniumDecode: server may send _25FC_/_2B58_ escapes in the buckets field
    final String decoded = autheniumDecode(raw) ?? raw;
    _buckets = parseBuckets(decoded);
    _catToLabel = _buildCategoryMap();
  }

  /// W2: build the `cd` value -> bucket label lookup. Robust + configurable —
  /// does NOT hardcode only English `full`/`empty` positionally.
  ///
  /// Resolution order:
  ///   1. Explicit `component['categoryMap']` override, format
  ///      `"cdValue◼bucketLabel⭘cdValue◼bucketLabel"` (same encoding as
  ///      `buckets`; autheniumDecode applied). Highest priority.
  ///   2. Identity: a `cd` value that already equals a bucket label maps to
  ///      itself (covers data where `cd` == "isi"/"kosong" directly).
  ///   3. Positional fallback for the two common English conventions
  ///      (`full` -> bucket[0], `empty` -> bucket[1]). Last resort only; the
  ///      explicit override (1) and identity (2) take precedence.
  ///
  /// OPEN ITEM: verify cd values on-device. The real asset_cache `cd` codes
  /// are unconfirmed; if they are neither `full`/`empty` nor equal to a bucket
  /// label, supply `component['categoryMap']` from the server JSON.
  Map<String, String> _buildCategoryMap() {
    final Map<String, String> map = {};

    // (1) explicit override
    final String rawMap = (widget.component['categoryMap'] ?? '')
        .toString()
        .trim();
    if (rawMap.isNotEmpty) {
      final String decoded = autheniumDecode(rawMap) ?? rawMap;
      // Reuse the bucket parser shape: label◼status entries, where here
      // "label" is the cd value and "status" is the target bucket label.
      for (final BucketDef def in parseBuckets(decoded)) {
        map[def.label.toLowerCase()] = def.status;
      }
    }

    // (2) identity: cd value == bucket label
    for (final BucketDef b in _buckets) {
      map.putIfAbsent(b.label.toLowerCase(), () => b.label);
    }

    // (3) positional fallback for English full/empty convention
    if (_buckets.isNotEmpty) {
      map.putIfAbsent('full', () => _buckets[0].label);
    }
    if (_buckets.length > 1) {
      map.putIfAbsent('empty', () => _buckets[1].label);
    }

    return map;
  }

  /// Look up the [BucketDef] for a bucket label (for status-driven styling).
  BucketDef? _bucketDefFor(String label) {
    for (final BucketDef b in _buckets) {
      if (b.label == label) return b;
    }
    return null;
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Primary data table (asset_cache)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String mainTableDocId = tp.tableDocId;
    if (mainTableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _dataCode = '$appVid/$mainTableDocId/${tp.subColl}';
      subscribeToMapCollection(appVid, mainTableDocId, tp.subColl, _dataCode);
    }

    // Gate table (vehicle_check) — for self-gating visibility
    final String rawGateTable = (widget.component['gateTable'] ?? '')
        .toString()
        .trim();
    if (rawGateTable.isNotEmpty) {
      final TablePath gtp = parseTablePath(rawGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        _gateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
        subscribeToMapCollection(
          appVid,
          gtp.tableDocId,
          gtp.subColl,
          _gateCode,
        );
      }
    }

    // Item collection (name FK for display)
    // component['itemTable'] = "84214220504259//item" or bare "item".
    // When bare (no //), subscribe as a subcollection under the main table's
    // docId — mirrors the gate card's R2-4 bare-itemsTable handling.
    final String rawItemTable = (widget.component['itemTable'] ?? '')
        .toString()
        .trim();
    if (rawItemTable.isNotEmpty) {
      if (!rawItemTable.contains('//') && mainTableDocId.isNotEmpty) {
        _itemCode = '$appVid/$mainTableDocId/$rawItemTable';
        subscribeToMapCollection(
          appVid,
          mainTableDocId,
          rawItemTable,
          _itemCode,
        );
      } else {
        final TablePath itp = parseTablePath(rawItemTable);
        if (itp.tableDocId.isNotEmpty) {
          _itemCode = '$appVid/${itp.tableDocId}/${itp.subColl}';
          subscribeToMapCollection(
            appVid,
            itp.tableDocId,
            itp.subColl,
            _itemCode,
          );
        }
      }
    }
  }

  /// Group filtered asset_cache docs by item-id (`ii`), sum qty per category
  /// bucket (`cd`), and resolve the display name via the item collection FK.
  ///
  /// Each asset_cache doc: `{ii: "2000000000031", cd: "full", qt: 34, ...}`.
  ///
  /// Groups by `component['itemField'] ?? 'ii'` (the item-id field), sums
  /// `component['qtyField'] ?? 'qt'` per `cd` value mapped through _catToLabel.
  /// Display name = `itemNameMap[ii] ?? ii` (raw id fallback when no item doc).
  ///
  /// Returns a list of `_TypeBucketRow` where `typeName` is the resolved item
  /// name (not the raw group key). Preserves first-seen order.
  List<_TypeBucketRow> _computeInventory(
    List<Map<String, dynamic>> docs,
    Map<String, String> itemNameMap,
  ) {
    final String catField = (widget.component['categoryField'] ?? 'cd')
        .toString()
        .trim();
    final String itemField = (widget.component['itemField'] ?? 'ii')
        .toString()
        .trim();
    final String qtyField = (widget.component['qtyField'] ?? 'qt')
        .toString()
        .trim();
    final bool hideZero = hideZeroEnabled(widget.component);

    // Group by item-id. grouped[ii][bucketLabel] = summed qty.
    final Map<String, Map<String, int>> grouped = {};
    final List<String> order = []; // preserve first-seen order

    for (final doc in docs) {
      final String itemId = (doc[itemField] ?? '').toString().trim();
      if (itemId.isEmpty) continue;
      final String catValue = (doc[catField] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final int qty =
          int.tryParse((doc[qtyField] ?? '0').toString().trim()) ?? 0;

      // W2: map cd value -> bucket label via the configurable lookup. Falls
      // back to the raw category value (so unmapped categories still surface
      // as their own column rather than being silently dropped).
      final String bucketLabel = _catToLabel[catValue] ?? catValue;

      if (!grouped.containsKey(itemId)) {
        order.add(itemId);
        grouped[itemId] = {};
      }
      grouped[itemId]![bucketLabel] =
          (grouped[itemId]![bucketLabel] ?? 0) + qty;
    }

    final List<_TypeBucketRow> result = [];
    for (final String itemId in order) {
      final Map<String, int> qtys = grouped[itemId]!;
      // hideZero: drop items whose every bucket is 0 (all conditions depleted
      // this vehicle). A single non-zero bucket (e.g. 0 full / 1 empty) still
      // renders — that is valid info (bring empties). Spec §2/§3.
      if (hideZero && qtys.values.every((v) => v == 0)) continue;
      // Resolve display name: item doc's `in` field, or raw id fallback.
      final String displayName = itemNameMap[itemId]?.isNotEmpty == true
          ? itemNameMap[itemId]!
          : itemId;
      result.add(_TypeBucketRow(typeName: displayName, bucketQty: qtys));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      // Touch confirmed + vehicleId to register Obx dependency (search uses
      // vehicleId; confirmed kept reactive even though gating is self-driven).
      dhState.confirmed.value;
      dhState.vehicleId.value;

      // ── Vehicle scope gate (scope-leak prevention) ──────────────────
      // When the driver has no assigned vehicle, hide the card entirely.
      if (dhState.vehicleIdResolved.value && dhState.vehicleId.value.isEmpty) {
        return const SizedBox.shrink();
      }

      // Fix 2: self-gate on own gateTable/gateSearch, not DriverHomeState.confirmed
      final String rawGateSearch = (widget.component['gateSearch'] ?? '')
          .toString()
          .trim();
      final bool gateConfirmed = evaluateGateSearch(
        _gateCode,
        rawGateSearch,
        widget.scrName,
      );

      // HIDDEN when gate not confirmed
      if (!gateConfirmed) return const SizedBox.shrink();

      // Item name map (FK: ii -> in from item collection).
      // Read inside Obx to register reactive dependency on mapTableContent.
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final Map<String, String> itemNameMap = buildItemNameMap(itemDocs);

      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_dataCode] ?? const [],
      );
      final String rawSearch = (widget.component['search'] ?? '')
          .toString()
          .trim();
      final List<Map<String, dynamic>> filtered = rawSearch.isNotEmpty
          ? filterDriverHomeDocs(docs, rawSearch, widget.scrName)
          : docs;
      final List<_TypeBucketRow> inventory = _computeInventory(
        filtered,
        itemNameMap,
      );

      final String title = _t(0, 'Isi Kendaraan Sekarang');
      final String caption = _t(1, '');

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
              // Header row
              Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
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
              if (inventory.isNotEmpty) ...[
                const SizedBox(height: 14),
                // 2-column grid of types
                _buildGrid(inventory),
              ],
              if (inventory.isEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Belum ada data stok.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
              ],
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
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

  Widget _buildGrid(List<_TypeBucketRow> rows) {
    // 2-column layout
    final List<Widget> cells = [];
    for (final row in rows) {
      cells.add(_buildTypeCell(row));
    }
    return Wrap(spacing: 16, runSpacing: 12, children: cells);
  }

  Widget _buildTypeCell(_TypeBucketRow row) {
    // For each bucket, show qty. Primary bucket (isi) big, secondary (kosong) muted.
    final String primaryLabel = _buckets.isNotEmpty ? _buckets[0].label : 'isi';
    final int primaryQty = row.bucketQty[primaryLabel] ?? 0;

    // W2: drive the primary qty color off BucketDef.status (ok/warn/danger)
    // rather than leaving status parsed-but-unused. ok -> neutral dark,
    // warn -> amber, danger -> red.
    final BucketDef? primaryDef = _bucketDefFor(primaryLabel);
    final Color primaryColor = _statusColor(primaryDef?.status);

    // Build secondary summaries
    final List<String> secondaryParts = [];
    for (int i = 1; i < _buckets.length; i++) {
      final int q = row.bucketQty[_buckets[i].label] ?? 0;
      secondaryParts.add('$q ${_buckets[i].label}');
    }
    final String secondaryText = secondaryParts.isNotEmpty
        ? secondaryParts.join(' · ')
        : '';

    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            row.typeName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$primaryQty',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                primaryLabel,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          if (secondaryText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              secondaryText,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ],
      ),
    );
  }

  /// W2: bucket-status -> accent color. Centralizes the ok/warn/danger ->
  /// color decision so BucketDef.status is wired to styling.
  Color _statusColor(String? status) {
    switch ((status ?? 'ok').toLowerCase()) {
      case 'warn':
        return const Color(0xFFD97706); // amber-600
      case 'danger':
        return const Color(0xFFDC2626); // red-600
      case 'ok':
      default:
        return const Color(0xFF1F2937); // neutral dark
    }
  }
}

/// Internal model: one asset type's summed quantities per bucket.
class _TypeBucketRow {
  final String typeName;
  final Map<String, int> bucketQty; // bucketLabel -> summed qty
  const _TypeBucketRow({required this.typeName, required this.bucketQty});
}
