import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../sdui_spec.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_CONFIRMED_LIST -- read-only list of driver-confirmed items.
///
/// Used by BOTH the driver P7 "Custody Confirmed" screen and the VTL
/// WarehouseClosingMatch screen. Subscribes vehicle_check (the count doc) +
/// item (name + category JOIN). Reads `ip[]` (the recount) and renders per
/// item: name, category chip, qty, green checkmark. No edits, no store.
///
/// OPTIONAL movement-badge layer (`flow*` keys): a recount knows CONDITION
/// (isi/kosong), never DIRECTION. When `flowTable` + `flowSearch` are both
/// configured, the widget additionally subscribes the task table, sums each
/// item's ACTUAL drop / pickup (`ad` / `ap`, never the plan `pd` / `pp`) over
/// the scoped tasks, and renders two small chips beside the category chip:
/// `Antar {sum}` and `Ambil {sum}`. A chip whose sum is 0 is hidden. With the
/// `flow*` keys absent the widget renders EXACTLY as before -- P7 depends on
/// that.
///
/// Component JSON fields:
///   `table`      -- vehicle_check path (e.g. `84214220504259//vehicle_check`)
///   `search`     -- count-doc search (`cty◼closing⭘vv◼{activeVehicle}⭘cdt◼{today}`)
///   `joinTable`  -- item table path (e.g. `84214220504259//item`)
///   `text`       -- diamond-separated label slots
///   `actualField`-- field name for ip[] (default `ip`)
///   `vidtable`   -- explicit appVid override
///   `com`        -- tenant container (`con`)
///
/// Movement-badge fields (all optional; omit ALL to keep legacy behaviour):
///   `flowTable`      -- movement source table (e.g. `84214220504259//task`)
///   `flowSearch`     -- trip/vehicle/day filter
///                       (e.g. `vv◼{activeVehicle}⭘tdt◼{today}`). REQUIRED
///                       alongside `flowTable`: an empty search would make
///                       filterDriverHomeDocs return every task doc unfiltered.
///   `flowItemsField` -- items array in the task doc (default `it`)
///   `flowKeyField`   -- item key joining to a list row (default `ii`; `in` works)
///   `dropField`      -- actual drop qty per item (default `ad`)
///   `pickupField`    -- actual pickup qty per item (default `ap`)
///   `flowText`       -- ◆-separated badge labels (default `Antar◆Ambil`)
class CustodyConfirmedList extends StatefulWidget {
  const CustodyConfirmedList({
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
  State<CustodyConfirmedList> createState() => _CustodyConfirmedListState();
}

class _CustodyConfirmedListState extends State<CustodyConfirmedList> {
  String _checkCode = '';
  String _itemCode = '';
  String _flowCode = '';

  /// Decoded / ◆-split / index-guarded accessor for the NEW `flow*` config
  /// only. The legacy `_t()` reads below stay as-is: SduiSpec adoption is
  /// on-touch, never a sweep, and this widget is shared with driver P7.
  late final SduiSpec _spec;
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    _spec = SduiSpec(widget.component);
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

  /// Text slot accessor.
  ///  [0] "Yang Dikonfirmasi"  (section title)
  ///  [1] "returnable"         (category label: returnable)
  ///  [2] "consumable"         (category label: consumable)
  ///  [3] hint label            (e.g. "Selanjutnya")
  ///  [4] hint body             (e.g. "Mulai eksekusi task hari ini, ...")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // vehicle_check
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _checkCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _checkCode);
    }

    // item (JOIN)
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

    // task (movement source for the optional drop/pickup badges).
    // Skipped entirely when flowTable is absent -- no extra Firestore
    // listener on screens that do not configure the badge layer (P7).
    //
    // BOTH keys are required here, mirroring _buildFlowMap()'s own guards.
    // With flowSearch blank that method returns an empty map (fail-closed),
    // so gating on flowTable ALONE would open a permanent listener streaming
    // the ENTIRE task subcollection while rendering zero badges. Do not
    // "simplify" this back to a single-key check.
    //
    // _flowCode deliberately stays '' in the half-configured case: the Obx
    // leading block still reads mapTableContent[''] and registers the RxMap
    // dependency, exactly as it does when joinTable is absent.
    final String rawFlowTable = _spec.str('flowTable');
    if (rawFlowTable.isNotEmpty && _spec.str('flowSearch').isNotEmpty) {
      final TablePath ftp = parseTablePath(rawFlowTable);
      if (ftp.tableDocId.isNotEmpty) {
        // Same `$appVid/` prefix as the two subscriptions above: the
        // mapTableContent/_mapSubscribed key omits vid, so another tenant's
        // identical tableDocId/subColl would dedup our stream away.
        _flowCode = '$appVid/${ftp.tableDocId}/${ftp.subColl}';
        subscribeToMapCollection(
          appVid,
          ftp.tableDocId,
          ftp.subColl,
          _flowCode,
        );
      }
    }
  }

  /// Aggregate the scoped task docs into a per-item drop/pickup lookup.
  ///
  /// Returns an EMPTY map -- i.e. zero badges, the exact acceptance-§1 render
  /// -- when either `flowTable` or `flowSearch` is missing.
  ///
  /// The `flowSearch` guard is FAIL-CLOSED and load-bearing:
  /// filterDriverHomeDocs returns docs UNCHANGED when the search is empty
  /// (driver_home_support.dart, `if (rawSearch.trim().isEmpty) return docs;`),
  /// so an unscoped flowSearch would silently sum the ENTIRE task collection
  /// across every vehicle and every day. A wrong number rendered confidently
  /// is worse than no badge.
  Map<String, ItemCirculation> _buildFlowMap() {
    if (_flowCode.isEmpty) return const <String, ItemCirculation>{};
    final String flowSearch = _spec.str('flowSearch');
    if (flowSearch.isEmpty) return const <String, ItemCirculation>{};

    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_flowCode] ?? const [],
    );
    // filterDriverHomeDocs handles autheniumDecode (◼/⭘ arrive as _25FC_ etc.)
    // and {activeVehicle}/{today}/screenTx token resolution before filtering.
    final List<Map<String, dynamic>> filtered = filterDriverHomeDocs(
      docs,
      flowSearch,
      widget.scrName,
    );

    // Unconditional load_rejected exclusion -- NOT config-driven. The spec
    // defines no excludeStatus key and an undefined key ships silently dead.
    // `statusField` is passed EXPLICITLY: excludeByStatus short-circuits only
    // on an empty excludeStatus, never on an empty statusField, so a blank
    // field name would read doc[''] and fail OPEN.
    final List<Map<String, dynamic>> live = excludeByStatus(
      filtered,
      kDefaultExcludeStatus,
      statusField: 'tst',
    );

    final String dropField = _spec.str('dropField', 'ad');
    final String pickupField = _spec.str('pickupField', 'ap');
    // ACTUAL-ONLY: pass the SAME field name as both plan and actual so
    // resolveItemQty can never fall back to pd/pp. A present-but-null `ad`
    // (toItMap writes literal null at task creation) then resolves through
    // `(e['ad'] ?? '0')` to 0 -- not a crash, not a "null" parse.
    final CirculationResult result = aggregateItemCirculation(
      live,
      itemsField: _spec.str('flowItemsField', 'it'),
      labelField: _spec.str('flowKeyField', 'ii'),
      dropField: dropField,
      actualDropField: dropField,
      pickupField: pickupField,
      actualPickupField: pickupField,
    );

    // Explicitly typed map -- never `.map().toList()` off dynamic data.
    final Map<String, ItemCirculation> map = <String, ItemCirculation>{};
    for (final ItemCirculation ic in result.items) {
      map[ic.itemName] = ic;
    }
    return map;
  }

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
    return pickNewestDoc(matched);
  }

  List<Map<String, dynamic>> _extractArray(
    Map<String, dynamic>? doc,
    String fieldName,
  ) {
    if (doc == null) return const [];
    final dynamic raw = doc[fieldName];
    if (raw is! List) return const [];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic entry in raw) {
      if (entry is! Map) continue;
      out.add(Map<String, dynamic>.from(entry));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).primaryColor;
    final Color pillBg = HSLColor.fromColor(
      primary,
    ).withLightness(0.92).withSaturation(0.35).toColor();
    final Color pillText = HSLColor.fromColor(
      primary,
    ).withLightness(0.35).withSaturation(0.8).toColor();
    // Hint tints (same HSL pattern; all lightness/saturation in [0,1]).
    final Color hintBg = HSLColor.fromColor(
      primary,
    ).withLightness(0.97).withSaturation(0.35).toColor();
    final Color hintBorder = HSLColor.fromColor(
      primary,
    ).withLightness(0.90).withSaturation(0.35).toColor();
    final Color hintIconBg = HSLColor.fromColor(
      primary,
    ).withLightness(0.90).withSaturation(0.40).toColor();
    final Color hintAccent = HSLColor.fromColor(
      primary,
    ).withLightness(0.40).withSaturation(0.70).toColor();

    return Obx(() {
      // Touch reactive source to register Obx dependency.
      mapTableContent[_checkCode];
      mapTableContent[_itemCode];
      // Third reactive source. MUST stay in this leading touch block -- a read
      // buried inside a conditional would leave the Obx with no observable on
      // the frame that takes the other branch (the documented zero-observable
      // crash class). `_flowCode` may be '' when the badge layer is off; the
      // lookup still registers the RxMap dependency, exactly like _itemCode
      // does when joinTable is absent.
      mapTableContent[_flowCode];

      final Map<String, dynamic>? checkDoc = _findCheckDoc();
      if (checkDoc == null) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      final String actualField = (widget.component['actualField'] ?? 'ip')
          .toString();
      final List<Map<String, dynamic>> ipEntries = _extractArray(
        checkDoc,
        actualField,
      );

      // Build item detail map for JOIN.
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
        itemDocs,
      );

      // ── Grouping config ──
      final bool grouped = sduiBool(_spec.str('groupByItem'));
      final Map<String, String> condLabels = parseCondLabels(
        _spec.str('condLabels'),
      );
      final String condField = _spec.str('condField', 'cd');

      // Build display rows (shared pure helper -- see driver_home_support.dart).
      // flowMap is const {} whenever the badge layer is off, which makes every
      // row's drop/pickup 0 and reproduces the pre-badge render exactly.
      // When grouped is false (P7, or any screen without groupByItem), the
      // helper takes the non-grouped branch and ignores condLabels / condField /
      // consumableCategory entirely.
      final List<ConfirmedRow> rows = buildConfirmedRows(
        ipEntries,
        itemDetailMap,
        flowMap: _buildFlowMap(),
        groupByItem: grouped,
        condLabels: condLabels,
        condField: condField,
        consumableCategory: _t(2),
      );

      // Badge labels: ◆-split via SduiSpec (which short-circuits empty ->
      // const [], avoiding the diamondTextToList('') == [''] trap), then
      // index-guarded -- `arr[N] ?? def` still throws RangeError.
      final List<String> flowText = _spec.list('flowText');
      final String dropLabel = flowText.isNotEmpty ? flowText[0] : 'Antar';
      final String pickupLabel = flowText.length > 1 ? flowText[1] : 'Ambil';

      if (rows.isEmpty) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: const Text('--'),
        );
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Eyebrow row: section title + summary count pill ──
            if (_t(0).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text(
                      _t(0, 'Yang Dikonfirmasi'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${rows.length} item',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: pillText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // ── Grouped card ──
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0F1F3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    _buildRow(
                      rows[i],
                      dropLabel,
                      pickupLabel,
                      grouped: grouped,
                    ),
                    if (i < rows.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF1F2F4),
                        indent: 50, // 16 pad + 22 icon + 12 gap
                        endIndent: 16,
                      ),
                  ],
                ],
              ),
            ),
            // ── Optional next-step hint footer ──
            if (_t(3).isNotEmpty || _t(4).isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildHint(hintBg, hintBorder, hintIconBg, hintAccent),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildRow(
    ConfirmedRow r,
    String dropLabel,
    String pickupLabel, {
    bool grouped = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Green checkmark
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF16A34A),
            size: 22,
          ),
          const SizedBox(width: 12),
          // Name + category + conditions + badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                if (grouped) ...[
                  // ── Grouped layout: each element on its own line ──
                  if (r.category.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _categoryChip(r.category),
                    ),
                  // Condition breakdown (e.g. "Penuh 0 · Kosong 5").
                  // Empty for consumable items (suppressed by D-A) and
                  // when condLabels is absent (no conditions collected).
                  if (r.conditions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        r.conditions
                            .map((c) => '${c.label} ${c.qty}')
                            .join(' \u{00B7} '),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  // Badges on their own line.
                  if (r.drop > 0 || r.pickup > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (r.drop > 0)
                            _flowBadge(
                              icon: Icons.arrow_upward_rounded,
                              label: dropLabel,
                              value: r.drop,
                              bg: const Color(0xFFFEF3C7),
                              fg: const Color(0xFF92400E),
                            ),
                          if (r.pickup > 0)
                            _flowBadge(
                              icon: Icons.arrow_downward_rounded,
                              label: pickupLabel,
                              value: r.pickup,
                              bg: const Color(0xFFDBEAFE),
                              fg: const Color(0xFF1E40AF),
                            ),
                        ],
                      ),
                    ),
                ] else ...[
                  // ── Non-grouped layout (unchanged from round 1) ──
                  // Category chip + optional movement badges share ONE row.
                  // With the badge layer off, drop == pickup == 0 for every row,
                  // so this condition reduces to the original
                  // `if (r.category.isNotEmpty)` and the Wrap holds exactly one
                  // child -- the unchanged chip, at the same top-4 offset (the
                  // chip's own `margin` simply moved out to this Padding).
                  if (r.category.isNotEmpty || r.drop > 0 || r.pickup > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (r.category.isNotEmpty) _categoryChip(r.category),
                          // Hide-zero (spec section 3): a 0 sum renders NO badge.
                          if (r.drop > 0)
                            _flowBadge(
                              icon: Icons.arrow_upward_rounded,
                              label: dropLabel,
                              value: r.drop,
                              bg: const Color(0xFFFEF3C7),
                              fg: const Color(0xFF92400E),
                            ),
                          if (r.pickup > 0)
                            _flowBadge(
                              icon: Icons.arrow_downward_rounded,
                              label: pickupLabel,
                              value: r.pickup,
                              bg: const Color(0xFFDBEAFE),
                              fg: const Color(0xFF1E40AF),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Qty (sum of qt across conditions when grouped)
          Text(
            '${r.qty}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }

  /// Neutral gray category chip. Extracted to avoid duplicating the Container
  /// across the grouped and non-grouped branches of [_buildRow].
  Widget _categoryChip(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  /// One movement badge (Antar / Ambil).
  ///
  /// Typography deliberately matches the neutral category chip above
  /// (fontSize 11, w600, radius 6, padding h8/v2) so the three chips read as
  /// one family and the row height does not grow.
  ///
  /// Literal colours, NOT AdminTierColors: that palette's `warn*` is violet
  /// and `danger*` is amber -- a documented naming trap in this repo.
  Widget _flowBadge({
    required IconData icon,
    required String label,
    required int value,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(
    Color hintBg,
    Color hintBorder,
    Color hintIconBg,
    Color hintAccent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: hintBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hintBorder, width: 1),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon chip
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: hintIconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(
                Icons.arrow_forward_rounded,
                color: hintAccent,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Label + body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_t(3).isNotEmpty)
                  Text(
                    _t(3).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: hintAccent,
                    ),
                  ),
                if (_t(3).isNotEmpty && _t(4).isNotEmpty)
                  const SizedBox(height: 4),
                if (_t(4).isNotEmpty)
                  Text(
                    _t(4),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: Color(0xFF374151),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
