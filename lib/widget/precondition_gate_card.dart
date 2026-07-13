import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// PRECONDITION_GATE_CARD — custody confirmation card (DriverHome P4).
///
/// Four-state custody confirmation card: hidden (no opening doc today),
/// pending (amber "Perlu Aksi" + item list + CTA), confirmed (green "Muatan
/// dikonfirmasi"), or confirmed-with-discrepancy (green + amber warn sub-bar
/// when dp[] non-empty). Publishes confirmed/pending into DriverHomeState so
/// downstream widgets (TXT label, Phase 2 gated cards) react.
class PreconditionGateCard extends StatefulWidget {
  const PreconditionGateCard({
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
  State<PreconditionGateCard> createState() => _PreconditionGateCardState();
}

class _PreconditionGateCardState extends State<PreconditionGateCard> {
  List<String> _textArray = [];
  String _gateCode = ''; // vehicle_check subscription code
  String _itemsCode = ''; // task subscription code
  String _itemCode = ''; // item collection subscription code (name FK for ip[])
  String _existGateCode = ''; // existence gate subscription code (gateTable)

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

  /// text slot accessors (9 slots per spec §3.3):
  ///  [0] "Perlu Aksi"
  ///  [1] "Konfirmasi Penerimaan Muatan"
  ///  [2] "Muat dari <2>. Cek & konfirmasi sebelum berangkat."
  ///  [3] "Konfirmasi Penerimaan"
  ///  [4] "membuka layar..."
  ///  [5] "Muatan dikonfirmasi"
  ///  [6] "{confirmedSummary} · jumlah aktual"
  ///  [7] "! Ada selisih dari catatan gudang"
  ///  [8] "udah dilaporkan, Supervisor lagi review. Kerjaan tetap jalan."
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Gate table: vehicle_check
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String mainTableDocId = tp.tableDocId;
    if (mainTableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _gateCode = '$appVid/$mainTableDocId/${tp.subColl}';
      subscribeToMapCollection(appVid, mainTableDocId, tp.subColl, _gateCode);
    }

    // Items table: task.
    // R2-4: `itemsTable:"task"` is a BARE name (no `//`) → parseTablePath would
    // give docId='task' (wrong path `.../tables/task/content`). When bare, the
    // items live as a SUBCOLLECTION under the MAIN gate table's docId, so
    // subscribe `MobileTable/<vid>/tables/<mainTableDocId>/task`. If the value
    // DOES contain `//`, honor the explicit parseTablePath path instead.
    final String rawItemsTable = (widget.component['itemsTable'] ?? '')
        .toString()
        .trim();
    if (rawItemsTable.isNotEmpty) {
      if (!rawItemsTable.contains('//') && mainTableDocId.isNotEmpty) {
        _itemsCode = '$appVid/$mainTableDocId/$rawItemsTable';
        subscribeToMapCollection(
          appVid,
          mainTableDocId,
          rawItemsTable,
          _itemsCode,
        );
      } else {
        final TablePath itp = parseTablePath(rawItemsTable);
        if (itp.tableDocId.isNotEmpty) {
          _itemsCode = '$appVid/${itp.tableDocId}/${itp.subColl}';
          subscribeToMapCollection(
            appVid,
            itp.tableDocId,
            itp.subColl,
            _itemsCode,
          );
        }
      }
    }

    // Item collection (name FK for ip[] -> display names in {confirmedSummary}).
    // Same bare-name pattern as itemsTable above.
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

    // Existence gate table (gateTable/gateSearch) -- date-scoped hide/show.
    // Mirrors INVENTORY_BUCKET_CARD (inventory_bucket_card.dart:142-151) and
    // DRIVER_STOP_CARD (driver_stop_card.dart:89-98). The `gateTable` value
    // carries `//` (e.g. "84214220504259//vehicle_check"), so parseTablePath
    // handles it directly. If the parsed code collides with _gateCode,
    // subscribeToMapCollection deduplicates (same Firestore stream, same
    // reactive mapTableContent entry) -- that is intentional and correct.
    final String rawGateTable = (widget.component['gateTable'] ?? '')
        .toString()
        .trim();
    if (rawGateTable.isNotEmpty) {
      final TablePath gtp = parseTablePath(rawGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        _existGateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
        subscribeToMapCollection(
          appVid,
          gtp.tableDocId,
          gtp.subColl,
          _existGateCode,
        );
      }
    }
  }

  /// Find the first vehicle_check doc matching the gate search.
  ///
  /// Returns the matched doc Map, or null if no match / empty search / no data.
  /// The gate is "confirmed" iff this returns non-null; `build` reads the
  /// returned doc's `ip[]` for the {confirmedSummary} in _buildConfirmed.
  Map<String, dynamic>? _matchedGateDoc() {
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return null;
    final List<Map<String, dynamic>> gateDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_gateCode] ?? const [],
    );
    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      gateDocs,
      rawSearch,
      widget.scrName,
    );
    if (matched.isEmpty) return null;
    // Multi-trip: prefer newest non-closed opening (defensive; the live
    // `search` config includes cst which already disambiguates, but this
    // guards against future config changes that drop the cst clause).
    return pickActiveOpening(matched) ?? matched.first;
  }

  /// Find the first vehicle_check OPENING doc matching gateSearch.
  ///
  /// Unlike [_matchedGateDoc] (which uses `search` on `_gateCode` and matches
  /// confirmed docs by `cst`), this reads from `_existGateCode` using
  /// `gateSearch` (which omits `cst` -- existence only, not status). This
  /// finds the opening doc regardless of whether custody is confirmed, so the
  /// ie[] manifest is available in PENDING state.
  ///
  /// Returns the matched doc Map, or null if no match / empty gateSearch / no
  /// data. Used by `_itemsFromIe` to read `ie[]` from the opening doc.
  Map<String, dynamic>? _matchedOpeningDoc() {
    final String rawGateSearch = (widget.component['gateSearch'] ?? '')
        .toString()
        .trim();
    if (rawGateSearch.isEmpty) return null;
    if (_existGateCode.isEmpty) return null;
    final List<Map<String, dynamic>> gateDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_existGateCode] ?? const [],
    );
    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      gateDocs,
      rawGateSearch,
      widget.scrName,
    );
    if (matched.isEmpty) return null;
    // Multi-trip: prefer newest non-closed opening (same pattern as
    // custody_count_list._findCheckDoc:174).
    return pickActiveOpening(matched) ?? matched.first;
  }

  /// Get the cargo manifest for the pending card display.
  ///
  /// Config-gated: when `itemsField == "ie"`, reads the opening doc's ie[]
  /// array (spec section 9). Otherwise, falls back to the existing task
  /// aggregation path (spec sections 1-3, unchanged).
  List<Map<String, dynamic>> _getItems() {
    final String itemsField = (widget.component['itemsField'] ?? 'it')
        .toString()
        .trim();
    if (itemsField == 'ie') return _itemsFromIe();
    return _itemsFromTaskAggregation();
  }

  /// ie[] manifest path (spec section 9).
  ///
  /// Reads `ie[]` from the opening vehicle_check doc (found via
  /// `_matchedOpeningDoc`), groups by item id summing qty across conditions,
  /// resolves names via item collection FK, optionally hides zero-qty rows.
  List<Map<String, dynamic>> _itemsFromIe() {
    final Map<String, dynamic>? openingDoc = _matchedOpeningDoc();
    if (openingDoc == null) return const [];

    final String itemsField = (widget.component['itemsField'] ?? 'ie')
        .toString()
        .trim();
    final dynamic ieArray = openingDoc[itemsField];
    if (ieArray is! List) return const [];

    // Build item-name FK map from the item collection (same as _buildConfirmed).
    final List<Map<String, dynamic>> itemDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_itemCode] ?? const [],
    );
    final Map<String, String> itemNameMap = buildItemNameMap(itemDocs);

    final String labelField = (widget.component['labelField'] ?? 'in')
        .toString()
        .trim();
    final String qtyField = (widget.component['qtyField'] ?? 'qt')
        .toString()
        .trim();
    final bool hideZero = hideZeroEnabled(widget.component);

    return aggregateManifestFromIe(
      ieArray,
      itemNameMap,
      idField: 'ii',
      qtyField: qtyField,
      labelField: labelField,
      hideZero: hideZero,
    );
  }

  /// Legacy task aggregation path (spec sections 1-3, back-compat).
  ///
  /// Tx-aware: sums deliver (pd) + sale (ps) + refill (pr) per item.
  /// Excludes tasks whose tst matches excludeStatus (e.g. load_rejected).
  /// Drops zero-qty items when hideZero is "TRUE".
  /// Optionally scopes task docs via itemsSearch before aggregating.
  List<Map<String, dynamic>> _itemsFromTaskAggregation() {
    List<Map<String, dynamic>> itemDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_itemsCode] ?? const [],
    );
    if (itemDocs.isEmpty) return const [];

    // Optional scoping: filter task docs by itemsSearch if configured.
    // When empty (current default), stays unscoped — preserves existing behavior
    // (R2-3 rationale: on-device data had unresolved tokens, scoping yielded empty).
    final String itemsSearch = (widget.component['itemsSearch'] ?? '')
        .toString()
        .trim();
    if (itemsSearch.isNotEmpty) {
      itemDocs = filterDriverHomeDocs(itemDocs, itemsSearch, widget.scrName);
      if (itemDocs.isEmpty) return const [];
    }

    final String itemsField = (widget.component['itemsField'] ?? 'it')
        .toString()
        .trim();
    final String labelField = (widget.component['labelField'] ?? 'in')
        .toString()
        .trim();
    final String qtyField = (widget.component['qtyField'] ?? 'pd')
        .toString()
        .trim();
    final String saleField = (widget.component['saleField'] ?? 'ps')
        .toString()
        .trim();
    final String refillField = (widget.component['refillField'] ?? 'pr')
        .toString()
        .trim();
    final String excludeStatus = (widget.component['excludeStatus'] ?? '')
        .toString()
        .trim();
    final bool hideZero = hideZeroEnabled(widget.component);

    return aggregateManifestItems(
      itemDocs,
      itemsField: itemsField,
      labelField: labelField,
      deliverField: qtyField,
      saleField: saleField,
      refillField: refillField,
      excludeStatus: excludeStatus,
      hideZero: hideZero,
    );
  }

  void _onCtaTap() {
    final String route = (widget.component['route'] ?? '').toString().trim();
    if (route.isEmpty) return;
    if (routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    } else {
      // Route not yet built (custodyConfirm is a placeholder page)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Layar belum tersedia'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Publish [value] to DriverHomeState.confirmed if it changed.
  ///
  /// Uses addPostFrameCallback to avoid setState-during-build warnings.
  /// Guarded by `mounted` for safety. Shared by the existence-gate hide
  /// path and the normal render path (DRY: single publish site).
  void _publishConfirmed(DriverHomeState dhState, bool value) {
    if (dhState.confirmed.value != value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        dhState.confirmed.value = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Re-read reactive mapTableContent + DriverHomeState.vehicleId to
      // trigger rebuild when vehicleId publishes or gate data arrives.
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      // Touch vehicleId.value to register Obx dependency.
      dhState.vehicleId.value;

      // ── Vehicle scope gate (scope-leak prevention) ──────────────────
      // When the driver has no assigned vehicle, hide the card entirely.
      // Belt-and-suspenders with filterByMultiClause's fail-closed guard.
      if (dhState.vehicleIdResolved.value && dhState.vehicleId.value.isEmpty) {
        _publishConfirmed(dhState, false);
        return const SizedBox.shrink();
      }

      // ── Existence gate (spec section 8 item 1) ───────────────────────
      // When gateSearch is configured (non-empty), hide the card entirely
      // if no opening doc exists for today. This separates "no load today"
      // from "load exists but pending confirmation." Backward-compat:
      // empty gateSearch = no gate = always render (opt-in, same as
      // excludeStatus).
      final String rawGateSearch = (widget.component['gateSearch'] ?? '')
          .toString()
          .trim();
      if (rawGateSearch.isNotEmpty) {
        final bool existsToday = evaluateGateSearch(
          _existGateCode,
          rawGateSearch,
          widget.scrName,
        );
        if (!existsToday) {
          // No opening doc today -> truthfully publish not-confirmed
          // (nothing to confirm), then hide.
          _publishConfirmed(dhState, false);
          return const SizedBox.shrink();
        }
      }

      // ── Status gate (existing) ──────────────────────────────────────
      final Map<String, dynamic>? matchedDoc = _matchedGateDoc();
      final bool isConfirmed = matchedDoc != null;

      // Publish state change (via shared helper)
      _publishConfirmed(dhState, isConfirmed);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: isConfirmed ? _buildConfirmed(matchedDoc) : _buildPending(),
      );
    });
  }

  // ── Pending state (amber card) ───────────────────────────────────────────

  Widget _buildPending() {
    final String badgeText = _t(0, 'Perlu Aksi');
    final String headline = _t(1, 'Konfirmasi Penerimaan Muatan');
    final String bodyTemplate = _t(2, '');
    final String ctaLabel = _t(3, 'Konfirmasi Penerimaan');

    // W6: warehouse name is static for now. <2> renders a fixed label.
    final String body = bodyTemplate.replaceAll('<2>', 'Gudang Pusat');

    final List<Map<String, dynamic>> items = _getItems();
    // R2-3: aggregated rows are keyed by the SAME label/qty fields _getItems
    // passed to aggregateItems — defaults `in` (label) / `pd` (qty).
    final String labelField = (widget.component['labelField'] ?? 'in')
        .toString()
        .trim();
    final String qtyField = (widget.component['qtyField'] ?? 'pd')
        .toString()
        .trim();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // amber-50
        border: Border.all(
          color: const Color(0xFFF59E0B),
          width: 1,
        ), // amber-500
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge + headline row
          Row(
            children: [
              // Amber pill badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7), // amber-100
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '● ',
                      style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B)),
                    ),
                    Text(
                      badgeText.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Headline
          Text(
            headline,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD97706), // amber-600
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E), // amber-800
                height: 1.4,
              ),
            ),
          ],
          // Item list
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              (items[i][labelField] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                          Text(
                            (items[i][qtyField] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // CTA button
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onCtaTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4338CA), // indigo-700
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text('$ctaLabel →'), // →
            ),
          ),
        ],
      ),
    );
  }

  // ── Confirmed state (green card) ─────────────────────────────────────────

  Widget _buildConfirmed(Map<String, dynamic> gateDoc) {
    final String confirmedLabel = _t(5, 'Muatan dikonfirmasi');
    final String summaryTemplate = _t(6, '');

    // Compute {confirmedSummary} from vehicle_check.ip[] (actual physical count).
    String summaryText = summaryTemplate;
    if (summaryTemplate.contains('{confirmedSummary}')) {
      // Build item-name FK map from the item collection.
      final List<Map<String, dynamic>> itemDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );
      final Map<String, String> itemNameMap = buildItemNameMap(itemDocs);

      // Read ip[] from the matched gate doc and aggregate.
      final String ipField = (widget.component['ipField'] ?? 'ip')
          .toString()
          .trim();
      final dynamic ipArray = gateDoc[ipField];
      final String computed = aggregateActualSummary(ipArray, itemNameMap);
      summaryText = summaryTemplate.replaceAll('{confirmedSummary}', computed);

      // W2: when the computed summary is empty (empty/absent/malformed ip[]),
      // the substitution leaves a dangling leading middle-dot separator
      // (e.g. " · jumlah aktual"). Strip a leading middle-dot + surrounding
      // whitespace so the suffix renders cleanly ("jumlah aktual"). Only fires
      // when the substituted value was empty; a non-empty summary is untouched.
      if (computed.isEmpty) {
        // Non-raw string: \u{00B7} -> the literal middle-dot char, \\s -> regex
        // whitespace. (A raw r'...\u{00B7}...' would NOT match without the
        // RegExp unicode flag, leaving the dangling dot.)
        summaryText = summaryText
            .replaceFirst(RegExp('^\\s*\u{00B7}\\s*'), '')
            .trim();
      }
    }

    // ── State-4 discrepancy detection (spec section 10) ──────────────────
    // Read dp[] from the confirmed gate doc. Non-empty = discrepancy present.
    final String dpField = (widget.component['dpField'] ?? 'dp')
        .toString()
        .trim();
    final dynamic dpArray = gateDoc[dpField];
    final bool showDiscrepancy = hasLoadDiscrepancy(dpArray);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // green-50
        border: Border.all(
          color: const Color(0xFF16A34A),
          width: 1,
        ), // green-600
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Confirmed row (states 3 + 4: always rendered) ────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF16A34A),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      confirmedLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                    if (summaryText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summaryText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF166534), // green-800
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // ── Discrepancy sub-bar (state 4 only) ───────────────────────
          if (showDiscrepancy) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB), // amber-50
                border: Border.all(
                  color: const Color(0xFFFCD34D),
                  width: 1,
                ), // amber-300
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ), // amber-600
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _t(7, '! Ada selisih dari catatan gudang'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E), // amber-800
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            8,
                            'udah dilaporkan, Supervisor lagi review. Kerjaan tetap jalan.',
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFB45309), // amber-700
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
