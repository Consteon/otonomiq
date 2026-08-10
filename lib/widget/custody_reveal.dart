import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../screen_session.dart';
import 'custody_stepper.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// CUSTODY_REVEAL -- STEP 2/2: reveal warehouse qty, compare vs driver,
/// then branch (match -> P7, mismatch -> P8, recount -> P6).
///
/// Subscribes vehicle_check (opening doc) + item (name + category JOIN).
/// Reads `expectedField` (ie[], warehouse) and `actualField` (ip[], driver).
/// Groups by category (`ic`), renders per-item comparison, overall callout,
/// and computed branch buttons.
///
/// Native writes (rs / dp[]) bypass the history queue (Firestore SDK offline
/// persistence). Uses [writeNativeFields] from driver_home_support.dart.
class CustodyReveal extends StatefulWidget {
  const CustodyReveal({
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

  /// Per-scrName writing-in-progress flag to prevent double taps.
  static final Map<String, bool> _writing = {};

  // -- Per-screen editable count state ------------------------------------

  /// Per-scrName editable count store: `{scrName: {ii__cd: CountEntry}}`.
  /// Seeded ONCE from the opening doc's `ip[]`; subsequent Firestore snapshot
  /// re-emits do NOT overwrite (seed-once guard via [_seeded]).
  /// Edits mutate the local state; `_compare` reads this instead of raw ip[].
  /// Cleared on route change via [clearEditState].
  static final Map<String, Map<String, CountEntry>> _editStore =
      <String, Map<String, CountEntry>>{};

  /// Revision counter: bumped when clearEditState forces a re-seed rebuild.
  /// Obx reads this instead of the now-plain _editStore.
  static final RxInt editRev = 0.obs;

  /// Per-scrName flag: true after the FIRST successful seed from ip[].
  /// Mirrors TaskManifestList._seeded pattern.
  static final Map<String, bool> _seeded = {};

  /// Get or create the edit map for a screen.
  static Map<String, CountEntry> getEditMap(String scrName) {
    registerScreenSession();
    return _editStore.putIfAbsent(scrName, () => <String, CountEntry>{});
  }

  static void registerScreenSession() {
    ScreenSession.ensure(
      'CustodyReveal.editState',
      CustodyReveal.clearEditState,
    );
  }

  /// Clear edit state for a screen. Called from buildPage alongside
  /// clearDriverHomeState and CustodyCountList.clearCountStore.
  static void clearEditState(String scrName) {
    _editStore.remove(scrName);
    _seeded.remove(scrName);
    _writing.remove(scrName);
    editRev.value++;
  }

  @override
  State<CustodyReveal> createState() => _CustodyRevealState();
}

class _CustodyRevealState extends State<CustodyReveal> {
  String _checkCode = ''; // vehicle_check subscription code
  String _itemCode = ''; // item subscription code
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    CustodyReveal.registerScreenSession();
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

  /// text slot accessor (9 slots):
  ///  [0] "RETURNABLE"     [1] "CONSUMABLE"
  ///  [2] "warehouse"      [3] "hitungan lo"
  ///  [4] "Match"          [5] "Ada selisih..."
  ///  [6] "Konfirmasi..."  [7] "Lanjut..."
  ///  [8] "Hitung Ulang"
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

    // item
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
  }

  /// Seed the editable count store from the doc's ip[] entries.
  /// Guarded: only runs ONCE per scrName (the _seeded flag).
  void _seedEditStore(List<Map<String, dynamic>> ipEntries) {
    if (CustodyReveal._seeded[widget.scrName] == true) return;
    final Map<String, CountEntry> editMap = CustodyReveal.getEditMap(
      widget.scrName,
    );
    for (final entry in ipEntries) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      final String cd = (entry['cd'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final int qt = int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
      final String key = '${ii}__$cd';
      editMap.putIfAbsent(key, () => CountEntry(ii: ii, cd: cd, qty: qt));
    }
    CustodyReveal._seeded[widget.scrName] = true;
  }

  /// Handle a stepper -/+ tap on the reveal page.
  void _onRevealCountChanged(String key, int newValue, String ii, String cd) {
    final Map<String, CountEntry> editMap = CustodyReveal.getEditMap(
      widget.scrName,
    );
    final CountEntry entry = editMap.putIfAbsent(
      key,
      () => CountEntry(ii: ii, cd: cd),
    );
    entry.qty = clampStepperValue(newValue, 0);
    setState(() {});
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

  /// Extract an array field from the check doc.
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

  /// Build comparison data from ie[] (expected/warehouse) and the EDITABLE
  /// count store (driver's current values).
  ///
  /// Unlike the prior read-only version that compared ie[] vs the doc's raw
  /// ip[], this compares ie[] vs _editStore[scrName] so the driver's inline
  /// edits are reflected in real-time.
  _CompareResult _compare(
    List<Map<String, dynamic>> ie,
    Map<String, CountEntry> editMap,
    Map<String, ItemDetail> itemDetailMap,
  ) {
    // Build ie lookup
    final Map<String, int> ieMap = {};
    final Map<String, Map<String, dynamic>> ieRaw = {};
    for (final entry in ie) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      final String cd = (entry['cd'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final int qt = int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
      final String key = '${ii}__$cd';
      ieMap[key] = qt;
      ieRaw[key] = entry;
    }

    // Union of all keys, preserving ie order first then editMap-only
    final List<String> allKeys = <String>[];
    for (final k in ieMap.keys) {
      allKeys.add(k);
    }
    for (final k in editMap.keys) {
      if (!ieMap.containsKey(k)) allKeys.add(k);
    }

    bool isMatch = true;
    final List<_CompareItem> items = [];
    for (final key in allKeys) {
      final int expected = ieMap[key] ?? 0;
      final int actual = editMap[key]?.qty ?? 0;
      final int delta = actual - expected;
      if (delta != 0) isMatch = false;

      // Parse ii and cd from key
      final int sep = key.indexOf('__');
      final String ii = sep >= 0 ? key.substring(0, sep) : key;
      final String cd = sep >= 0 ? key.substring(sep + 2) : '';

      // Resolve name + category from item detail map
      final ItemDetail? detail = itemDetailMap[ii];
      final String name = (detail != null && detail.name.isNotEmpty)
          ? detail.name
          : ii;
      final String category = (detail != null && detail.category.isNotEmpty)
          ? detail.category
          : '';

      items.add(
        _CompareItem(
          ii: ii,
          cd: cd,
          name: name,
          category: category,
          expected: expected,
          actual: actual,
          delta: delta,
        ),
      );
    }

    return _CompareResult(isMatch: isMatch, items: items);
  }

  /// Build dp[] array from comparison items (only differing items).
  ///
  /// Delegates to the shared [buildReconciliation] helper. Output is
  /// byte-identical to the prior inline implementation: for each item whose
  /// delta != 0, emits `{ii, cd, ex, ac, dl}`. The `items`-order insertion of
  /// the expected/actual maps + the helper's stable (insertion-order) key
  /// iteration preserves the prior dp[] ordering.
  ///
  /// NOTE: the match/mismatch ROUTE decision still reads `_compare`'s own
  /// `isMatch` (build method, line ~393); this helper's `rs` is intentionally
  /// NOT used here -- only its dp[] output.
  List<Map<String, dynamic>> _buildDpArray(List<_CompareItem> items) {
    final Map<String, int> expectedMap = <String, int>{};
    final Map<String, int> actualMap = <String, int>{};
    for (final item in items) {
      final String key = '${item.ii}__${item.cd}';
      expectedMap[key] = item.expected;
      actualMap[key] = item.actual;
    }
    final ReconciliationResult result = buildReconciliation(
      expected: expectedMap,
      actual: actualMap,
    );
    return result.dp;
  }

  /// Navigate to a route, stripping [ROUTE:...] wrapper if present.
  void _navigateTo(String rawRoute) {
    final String route = stripRouteWrapper(rawRoute);
    if (route.isEmpty) return;
    if (routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Layar belum tersedia'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Write fields natively then navigate. Shows snackbar on failure.
  Future<void> _writeAndNavigate(
    Map<String, dynamic> patch,
    String rawRoute,
  ) async {
    if (CustodyReveal._writing[widget.scrName] == true) return;
    CustodyReveal._writing[widget.scrName] = true;
    setState(() {});

    try {
      final String rawTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
      final String rawSearch = (widget.component['search'] ?? '')
          .toString()
          .trim();

      // R2-A: Direct cst flip -- bypass broken history queue (BUG2).
      // The updateEventRow DSL on P7/P8 CustodyEventSubmit was supposed
      // to flip cst via saveSend -> historySync -> writeUpdateEventRow,
      // but historySync never sends the record ("no history sent" every
      // cycle, proven on-device). Folding cst into this existing patch
      // targets the SAME opening doc that already receives ip/dp/rs.
      // writeNativeFields is type-agnostic (whereIn:[String, Number]) so
      // no eq() needed. Mirrors C1 close (custody_count_submit.dart:660-668).
      patch['cst'] = 'custody_confirmed';

      // Doc-id resolution: reuse _findCheckDoc (the same read-path picker
      // that selected the opening doc the user just reviewed). Write by
      // doc-id to avoid the >1 match refusal on multi-trip same-day.
      final String docId = (_findCheckDoc()?['__docId'] ?? '')
          .toString()
          .trim();

      bool success = false;
      if (docId.isNotEmpty) {
        success = await createNativeDoc(
          component: widget.component,
          rawTable: rawTable,
          docId: docId,
          docMap: patch,
        );
      }
      if (!success) {
        // Fallback: search-based write (single-trip / no subscription data)
        success = await writeNativeFields(
          component: widget.component,
          rawTable: rawTable,
          rawSearch: rawSearch,
          scrName: widget.scrName,
          patch: patch,
        );
      }

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal menyimpan data'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Offline: write is queued locally (SDK persistence) -- tell the user.
      // internetConnectionFlag read directly (global.dart:263); this file
      // does not import api.dart.
      if (!internetConnectionFlag.value && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tersimpan offline — dikirim otomatis saat online'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      _navigateTo(rawRoute);
    } finally {
      CustodyReveal._writing[widget.scrName] = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch reactive stores to register Obx dependencies.
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      dhState.vehicleId.value;
      CustodyReveal
          .editRev
          .value; // revision signal dep: rebuild on clearEditState

      // 1. Find the opening doc
      final Map<String, dynamic>? checkDoc = _findCheckDoc();

      // 2. Loading state: no data yet.
      // CRITICAL (C2): this guard MUST run BEFORE _seedEditStore.
      // On cold entry the first build has checkDoc == null / ipEntries == [].
      // If _seedEditStore([]) ran here it would set _seeded = true with an
      // empty store, permanently poisoning the edit state.
      if (checkDoc == null) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      }

      // 3. Extract ie[] and ip[] (ip[] used for SEEDING only, not comparison)
      final String expectedField = (widget.component['expectedField'] ?? 'ie')
          .toString()
          .trim();
      final String actualField = (widget.component['actualField'] ?? 'ip')
          .toString()
          .trim();
      final List<Map<String, dynamic>> ieEntries = _extractArray(
        checkDoc,
        expectedField,
      );
      final List<Map<String, dynamic>> ipEntries = _extractArray(
        checkDoc,
        actualField,
      );

      // 4. Seed edit store ONCE from ip[] (safe: checkDoc is non-null here)
      _seedEditStore(ipEntries);
      final Map<String, CountEntry> editMap = CustodyReveal.getEditMap(
        widget.scrName,
      );

      // 5. Build item detail map
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
      final String categoryField = (widget.component['categoryField'] ?? 'ic')
          .toString()
          .trim();
      final Map<String, ItemDetail> itemDetailMap = buildItemDetailMap(
        itemDocs,
        idField: joinKey,
        nameField: labelField,
        categoryField: categoryField,
      );

      // 6. Compare ie[] vs EDITED state
      final _CompareResult result = _compare(ieEntries, editMap, itemDetailMap);
      final bool isMatch = result.isMatch;
      final bool isWriting = CustodyReveal._writing[widget.scrName] ?? false;

      // 7. Group by category
      final String returnableLabel = _t(0, 'RETURNABLE');
      final String consumableLabel = _t(1, 'CONSUMABLE');
      final List<_CompareItem> returnableItems = result.items
          .where((i) => i.category == 'returnable')
          .toList();
      final List<_CompareItem> consumableItems = result.items
          .where((i) => i.category == 'consumable')
          .toList();
      final List<_CompareItem> ungroupedItems = result.items
          .where(
            (i) => i.category != 'returnable' && i.category != 'consumable',
          )
          .toList();

      // Text slots (NOTE: slot 3 "hitungan lo" / driverLabel is intentionally
      // NOT declared -- it was used by the old column-header layout which is
      // replaced by per-card CustodyStepper. Declaring it would trip
      // unused_local_variable.)
      final String warehouseLabel = _t(2, 'warehouse');
      final String matchLabel = _t(4, 'Match');
      final String mismatchLabel = _t(
        5,
        'Ada selisih dengan catatan warehouse',
      );
      final String matchBtnLabel = _t(
        6,
        'KONFIRMASI LOAD \u{00B7} SIAP BERANGKAT',
      );
      final String mismatchBtnLabel = _t(7, 'LANJUT \u{00B7} REPORT MISMATCH');
      final String recountLabel = _t(8, 'Hitung Ulang');

      // Route fields
      final String matchRoute = (widget.component['matchRoute'] ?? '')
          .toString()
          .trim();
      final String mismatchRoute = (widget.component['mismatchRoute'] ?? '')
          .toString()
          .trim();
      final String recountRoute = (widget.component['recountRoute'] ?? '')
          .toString()
          .trim();

      // Write field names
      final String writeField = (widget.component['writeField'] ?? 'ip')
          .toString()
          .trim();
      final String discrepancyField =
          (widget.component['discrepancyField'] ?? 'dp').toString().trim();
      final String reconcileField = (widget.component['reconcileField'] ?? 'rs')
          .toString()
          .trim();

      // Status palette
      const _RevealPalette palette = _RevealPalette();

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
            // -- RETURNABLE section --
            if (returnableItems.isNotEmpty) ...[
              _sectionDotHeader(returnableLabel),
              const SizedBox(height: 8),
              for (int i = 0; i < returnableItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildEditableItemCard(
                  returnableItems[i],
                  matchLabel,
                  warehouseLabel,
                  palette,
                ),
              ],
              const SizedBox(height: 20),
            ],

            // -- CONSUMABLE section --
            if (consumableItems.isNotEmpty) ...[
              _sectionDotHeader(consumableLabel),
              const SizedBox(height: 8),
              for (int i = 0; i < consumableItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildEditableItemCard(
                  consumableItems[i],
                  matchLabel,
                  warehouseLabel,
                  palette,
                ),
              ],
              const SizedBox(height: 20),
            ],

            // -- Ungrouped items (if any) --
            if (ungroupedItems.isNotEmpty) ...[
              for (int i = 0; i < ungroupedItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildEditableItemCard(
                  ungroupedItems[i],
                  matchLabel,
                  warehouseLabel,
                  palette,
                ),
              ],
              const SizedBox(height: 20),
            ],

            // -- Callout banner --
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isMatch ? palette.greenBg : palette.amberBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isMatch ? palette.greenBorder : palette.amberBorder,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isMatch
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    size: 20,
                    color: isMatch ? palette.greenText : palette.amberText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isMatch ? '\u{2713} Semua match' : '! $mismatchLabel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isMatch ? palette.greenText : palette.amberText,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- Branch buttons --

            // Primary action (match or mismatch)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: isWriting
                    ? null
                    : () {
                        // Build ip[] from EDITED state
                        final List<Map<String, dynamic>> ipArray =
                            <Map<String, dynamic>>[];
                        for (final entry in editMap.values) {
                          ipArray.add(entry.toIpMap());
                        }

                        if (isMatch) {
                          // Match: write ip[]+rs=matched -> nav matchRoute
                          _writeAndNavigate({
                            writeField: ipArray,
                            reconcileField: 'matched',
                          }, matchRoute);
                        } else {
                          // Mismatch: build dp[] + write ip[]+dp[]+rs
                          final List<Map<String, dynamic>> dpArray =
                              _buildDpArray(result.items);
                          _writeAndNavigate({
                            writeField: ipArray,
                            discrepancyField: dpArray,
                            reconcileField: 'discrepancy_detected',
                          }, mismatchRoute);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isMatch
                      ? palette.greenBtn
                      : palette.amberBtn,
                  disabledBackgroundColor: const Color(0xFFD1D5DB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isWriting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isMatch ? matchBtnLabel : mismatchBtnLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Recount button (always visible)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: isWriting ? null : () => _navigateTo(recountRoute),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563), // gray-600
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  recountLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Section dot-header: "(dot) RETURNABLE" / "(dot) CONSUMABLE".
  Widget _sectionDotHeader(String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF4B5563), // gray-600
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151), // gray-700
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Build one per-item card with EDITABLE tinted stepper.
  ///
  /// Layout:
  ///   Row: item name (left) + category chip (right) + italic "Warehouse: N"
  ///   CustodyStepper (tinted by status, EDITABLE -/+)
  Widget _buildEditableItemCard(
    _CompareItem item,
    String matchLabel,
    String warehouseLabel,
    _RevealPalette palette,
  ) {
    final bool itemMatch = item.delta == 0;
    final bool itemOver = item.delta > 0;

    final String statusLabel;
    final Color statusColor;
    final Color frameBg;
    final Color frameBorder;
    if (itemMatch) {
      statusLabel = '\u{2713} $matchLabel';
      statusColor = palette.greenText;
      frameBg = palette.greenBg;
      frameBorder = palette.greenBorder;
    } else if (itemOver) {
      statusLabel = 'Selisih: +${item.delta}';
      statusColor = palette.purpleText;
      frameBg = palette.purpleBg;
      frameBorder = palette.purpleBorder;
    } else {
      statusLabel = 'Selisih: ${item.delta}';
      statusColor = palette.amberText;
      frameBg = palette.amberBg;
      frameBorder = palette.amberBorder;
    }

    final String countKey = '${item.ii}__${item.cd}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row: item name + category chip + warehouse label
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.name,
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
                  if (item.category.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6), // gray-100
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.category.toUpperCase(),
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
            ),
            const SizedBox(width: 8),
            Text(
              '$warehouseLabel: ${item.expected}',
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8), // slate-400
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Editable tinted stepper
        CustodyStepper(
          value: item.actual,
          onDecrement: () {
            _onRevealCountChanged(countKey, item.actual - 1, item.ii, item.cd);
          },
          onIncrement: () {
            _onRevealCountChanged(countKey, item.actual + 1, item.ii, item.cd);
          },
          min: 0,
          enabled: true,
          frameBg: frameBg,
          frameBorder: frameBorder,
          numberColor: statusColor,
          statusLine: Text(
            statusLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Internal helpers ─────────────────────────────────────────────────────

class _CompareItem {
  final String ii;
  final String cd;
  final String name;
  final String category;
  final int expected; // ie.qt (warehouse)
  final int actual; // ip.qt (driver)
  final int delta; // actual - expected

  const _CompareItem({
    required this.ii,
    required this.cd,
    required this.name,
    required this.category,
    required this.expected,
    required this.actual,
    required this.delta,
  });
}

class _CompareResult {
  final bool isMatch;
  final List<_CompareItem> items;

  const _CompareResult({required this.isMatch, required this.items});
}

/// Status color palette shared by the callout banner and per-item stepper
/// frames. Match = emerald, over = violet, under = amber.
class _RevealPalette {
  const _RevealPalette();

  Color get greenBg => const Color(0xFFECFDF5); // emerald-50
  Color get greenText => const Color(0xFF065F46); // emerald-800
  Color get greenBtn => const Color(0xFF059669); // emerald-600
  Color get greenBorder => const Color(0xFFA7F3D0); // emerald-200

  Color get amberBg => const Color(0xFFFFFBEB); // amber-50
  Color get amberText => const Color(0xFF92400E); // amber-800
  Color get amberBtn => const Color(0xFFD97706); // amber-600
  Color get amberBorder => const Color(0xFFFDE68A); // amber-200

  Color get purpleBg => const Color(0xFFF5F3FF); // violet-50
  Color get purpleText => const Color(0xFF5B21B6); // violet-800
  Color get purpleBorder => const Color(0xFFDDD6FE); // violet-200
}
