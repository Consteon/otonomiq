import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../model/otq_state.dart';
import 'do_chain.dart';
import 'driver_home_support.dart';
import 'item_execution_list.dart';
import 'panel_card_support.dart';

/// ITEM_EXECUTION_SUBMIT -- atomic submit button for P11 DeliveryWorkspace.
///
/// Persists driver stepper actuals into the task `it[]` array via a SINGLE
/// atomic native Firestore write (`writeNativeFields` set-merge), together
/// with `tst=completed` + `tce=<submit epoch-ms>`, so the CF `OnTaskCompleted`
/// reads actuals instead of falling back to plan values.
///
/// Evidence (addToEvent), GPS, and navigation dialog are handled by the
/// existing `saveSend` pipeline (separate collection, no ordering dependency).
/// The `updateEventRow` DSL passed to saveSend has `tst`/`tce` clauses stripped
/// to avoid double-write with the native write; if stripping leaves no body
/// clause, `updateEventRow` is dropped from the saveSend payload entirely.
///
/// ## DSL encoding (W1)
///
/// `updateEventRow` / `addToEvent` are handed to `saveSend` exactly the way the
/// sibling `CustodyEventSubmit` does (custody_event_submit.dart:279-287): only
/// `{curly}` tokens are resolved (`resolveDriverCurlyTokens`); the DSL is left
/// in its stored literal `⭘`/`◼` form. `saveSend` (api.dart:4269/4282) runs its
/// own `autheniumDecode` (a no-op on already-literal text) and the diamond
/// decode happens later at history-sync (table_repository.dart:1502/1514). This
/// widget therefore does NOT pre-`autheniumDecode` either DSL, and the
/// `tst`/`tce` strip operates on the literal stored form.
///
/// ## Component JSON fields
///
///   `table`             -- task collection path (e.g. `84214220504259//task`)
///   `search`            -- task doc search (e.g. `tnm◼{activeTaskVid}`)
///   `itemsField`        -- items array field name (default `it`)
///   `txField`           -- transaction kind field (default `tx`)
///   `planDropField`     -- plan drop field (default `pd`)
///   `planPickupField`   -- plan pickup field (default `pp`)
///   `saleField`         -- plan sale field (default `ps`)
///   `buyField`          -- plan buy field (default `pb`)
///   `refillField`       -- plan refill field (default `pr`)
///   `actualDropField`   -- actual drop field to write (default `ad`)
///   `actualPickupField` -- actual pickup field to write (default `ap`)
///   `actualSaleField`   -- actual sale field to write (default `as`)
///   `actualBuyField`    -- actual buy field to write (default `ab`)
///   `actualRefillField` -- actual refill field to write (default `ar`)
///   `updateEventRow`    -- DSL string (curly-resolved; tst/tce auto-stripped)
///   `addToEvent`        -- DSL string (evidence, optional)
///   `chain`             -- DO_DIALOG confirmation (optional)
///   `route`             -- fallback navigation target (if no chain)
///   `text`              -- diamond-separated: [0] enabled, [1] disabled
///   `vidtable`, `com`   -- standard appVid/tenant overrides
class ItemExecutionSubmit extends StatefulWidget {
  const ItemExecutionSubmit({
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

  /// Clear state for a screen. Called from buildPage / clearData.
  static void clearState(String scrName) {
    _writing.remove(scrName);
  }

  /// Shared actual-write core used by both [runActualWrite] (hook) and
  /// [_ItemExecutionSubmitState._onTap] (orphaned widget). Given a component
  /// with table/search/field config, finds the active task doc, rebuilds
  /// it[] with actuals from the execution store, and writes atomically
  /// via writeNativeFields (set-merge) alongside tst=completed + tce.
  ///
  /// Returns true on success (including the empty-items case, which still
  /// writes tst/tce natively). Returns false on failure (caller MUST NOT
  /// proceed with saveSend -- spec section 6 atomicity).
  static Future<bool> _doActualWrite({
    required dynamic component,
    required String scrName,
  }) async {
    // 1. Parse config from the component.
    final ItemExecutionSubmitConfig cfg = parseConfigFromComponent(component);

    // 2. Find the active task doc.
    final Map<String, dynamic>? taskDoc = findActiveTaskDoc(component, scrName);
    if (taskDoc == null) {
      devPrint('[_doActualWrite] no active task doc for scrName=$scrName');
      return false;
    }

    // 3. Extract items. May be empty -- a degenerate task with no it[] still
    //    completes (tst/tce written below); only the it[] patch key is skipped.
    final List<Map<String, dynamic>> items = extractItemsFromDoc(
      taskDoc,
      cfg.itemsField,
    );

    // 4. Timestamp: server-truth NTP via getRealTime (matching saveSend's clock).
    final int timeStamp = await getRealTime();

    // 5. Build the atomic patch. tst/tce are ALWAYS written natively so the
    //    savesend hook can uniformly strip them from the updateEventRow
    //    (invariant: _doActualWrite==true => the native write owns tst/tce).
    //    it[] is included ONLY when items exist, rebuilt with actuals from the
    //    execution store. Empty it[] -> patch carries only tst/tce; CF
    //    OnTaskCompleted reads the (empty) it[] and emits no movements.
    final Map<String, dynamic> patch = <String, dynamic>{
      'tst': 'completed',
      'tce': timeStamp,
    };
    if (items.isNotEmpty) {
      final Map<String, ExecutionEntry> execMap = ItemExecutionList.getExecMap(
        scrName,
      );
      patch[cfg.itemsField] = rebuildItWithActuals(items, execMap, cfg);
    }

    // 6. Read table + search from component.
    final String rawTable = (component['table'] ?? '').toString().trim();
    final String rawSearch = (component['search'] ?? '').toString().trim();
    if (rawTable.isEmpty || rawSearch.isEmpty) {
      devPrint('[_doActualWrite] missing table/search in component');
      return false;
    }

    // 7. Atomic native write (set-merge on the single matched task doc).
    final bool success = await writeNativeFields(
      component: component,
      rawTable: rawTable,
      rawSearch: rawSearch,
      scrName: scrName,
      patch: patch,
    );
    if (!success) {
      devPrint(
        '[_doActualWrite] writeNativeFields failed for scrName=$scrName',
      );
    } else if (!internetConnected()) {
      // Silent hook path (no BuildContext): devPrint only, per design.
      devPrint(
        '[_doActualWrite] offline: write queued locally for '
        'scrName=$scrName (auto-sync when online)',
      );
    }
    return success;
  }

  /// Hook entry point for the saveSend RBT path.
  ///
  /// Called from `doSaveProcedure` in `ftz_row_of_button_2.dart` when an
  /// `ITEM_EXECUTION_LIST` is registered for [scrName]. Runs the atomic
  /// native write using the LIST's component config.
  ///
  /// Returns true if no LIST is registered (no-op -- let saveSend proceed)
  /// or the write succeeded. Returns false if the write failed (caller
  /// MUST NOT proceed with saveSend).
  static Future<bool> runActualWrite(String scrName) async {
    final dynamic component = ItemExecutionList.submitComponentByScr[scrName];
    if (component == null) return true; // no LIST on this screen -> no-op
    return _doActualWrite(component: component, scrName: scrName);
  }

  @override
  State<ItemExecutionSubmit> createState() => _ItemExecutionSubmitState();
}

class _ItemExecutionSubmitState extends State<ItemExecutionSubmit> {
  String _taskCode = '';
  List<String> _textArray = [];

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

  /// Text slot accessors:
  ///  [0] enabled label  (e.g. "KONFIRMASI PENGIRIMAN")
  ///  [1] disabled label (e.g. "MEMPROSES...")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }
  }

  /// Find the active task doc (mirrors ItemExecutionList._findActiveTask).
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

  Future<void> _onTap(BuildContext context) async {
    if (ItemExecutionSubmit._writing[widget.scrName] == true) return;

    ItemExecutionSubmit._writing[widget.scrName] = true;
    ItemExecutionList.executionRev.value++; // trigger rebuild -> spinner

    try {
      // 1. Atomic native write (shared core with runActualWrite hook).
      final bool success = await ItemExecutionSubmit._doActualWrite(
        component: widget.component,
        scrName: widget.scrName,
      );
      if (!success) {
        if (context.mounted) _showSnackBar(context, 'Gagal menyimpan data');
        return; // NO saveSend, NO nav on native write failure
      }

      // 2. saveSend for evidence + GPS + history.
      //    Mirrors CustodyEventSubmit (custody_event_submit.dart:275-301):
      //    deep-copy the component, resolve {curly} tokens ONLY (no decode --
      //    saveSend decodes its own DSL), then hand to saveSend. The
      //    updateEventRow has tst/tce stripped here so it is not double-written
      //    by historySync; if stripping leaves no body clause it is dropped.
      final Map<String, dynamic> resolved = Map<String, dynamic>.from(
        widget.component as Map,
      );

      final String rawUER = (resolved['updateEventRow'] ?? '').toString();
      if (rawUER.isNotEmpty) {
        final String uerResolved = resolveDriverCurlyTokens(
          rawUER,
          widget.scrName,
        );
        final String stripped = stripTstFromUpdateEventRow(uerResolved);
        if (updateEventRowHasBody(stripped)) {
          resolved['updateEventRow'] = stripped;
        } else {
          // Only header (path/tablevid/search) survived the strip -- no field
          // to merge. Drop it so historySync skips the redundant no-op query.
          resolved.remove('updateEventRow');
        }
      }

      final String rawATE = (resolved['addToEvent'] ?? '').toString();
      if (rawATE.isNotEmpty) {
        resolved['addToEvent'] = resolveDriverCurlyTokens(
          rawATE,
          widget.scrName,
        );
      }

      // Separate timestamp for the saveSend history entry. A few ms after the
      // native write's tce -- harmless; the native tce is the authoritative
      // completion timestamp that CF reads.
      final int saveSendTimestamp = await getRealTime();

      // locString via the canonical helper (15-diamond-slot format expected by
      // saveSend/historySync), built from the saveSend timestamp.
      final OtqState locSensor = OtqState();
      locSensor.nowTime = DateTime.fromMillisecondsSinceEpoch(
        saveSendTimestamp,
      );
      final String locString = getLocationString('', '', '', locSensor);

      saveSend(
        saveSendTimestamp,
        widget.scrName,
        resolved,
        locString,
        defaultVid(),
      );

      // 3. Navigate (chain-aware, mirrors custody_event_submit)
      final dynamic chain = widget.component['chain'];
      if (chain != null && chain.toString().trim().isNotEmpty) {
        if (context.mounted) {
          await doChain(context, widget.scrName, chain);
        }
      } else {
        final String rawRoute = (widget.component['route'] ?? '')
            .toString()
            .trim();
        final String route = stripRouteWrapper(rawRoute);
        if (route.isNotEmpty && routeExist(route)) {
          routeStack.push(route);
          gotoRoute(route);
        }
      }
    } catch (e) {
      errorReport(e);
      if (context.mounted) {
        _showSnackBar(context, 'Gagal mengirim: $e');
      }
    } finally {
      ItemExecutionSubmit._writing[widget.scrName] = false;
      ItemExecutionList.executionRev.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch executionRev for Obx dependency (spinner + item count).
      ItemExecutionList.executionRev.value;
      // Touch mapTableContent for reactive rebuild when the task doc arrives.
      mapTableContent[_taskCode];

      final bool isWriting =
          ItemExecutionSubmit._writing[widget.scrName] ?? false;

      // Gate: task doc must exist and have items
      final Map<String, dynamic>? taskDoc = _findActiveTask();
      final bool hasTask = taskDoc != null;
      final String itemsField = (widget.component['itemsField'] ?? 'it')
          .toString()
          .trim();
      final dynamic rawItems = taskDoc?[itemsField];
      final bool hasItems = rawItems is List && rawItems.isNotEmpty;
      final bool enabled = hasTask && hasItems && !isWriting;

      // Labels
      final String enabledLabel = _t(0, 'KONFIRMASI PENGIRIMAN');
      final String disabledLabel = _t(1, _t(0, 'KONFIRMASI PENGIRIMAN'));
      final String label = enabled ? enabledLabel : disabledLabel;

      // Colors: enabled = indigo-700, disabled = gray-300
      final Color bgColor = enabled
          ? const Color(0xFF4338CA) // indigo-700
          : const Color(0xFFD1D5DB); // gray-300
      final Color textColor = enabled
          ? Colors.white
          : const Color(0xFF6B7280); // gray-500

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: enabled ? () => _onTap(context) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              foregroundColor: textColor,
              disabledForegroundColor: const Color(0xFF6B7280),
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
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      );
    });
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

// ── Testable pure-logic helpers ────────────────────────────────────────────

/// Config container for field names, parsed from component JSON.
/// All defaults mirror the live server values (ad, ap, as, ab, ar, etc.).
class ItemExecutionSubmitConfig {
  final String itemsField;
  final String txField;
  final String planDropField;
  final String planPickupField;
  final String saleField;
  final String buyField;
  final String refillField;
  final String actualDropField;
  final String actualPickupField;
  final String actualSaleField;
  final String actualBuyField;
  final String actualRefillField;

  const ItemExecutionSubmitConfig({
    required this.itemsField,
    required this.txField,
    required this.planDropField,
    required this.planPickupField,
    required this.saleField,
    required this.buyField,
    required this.refillField,
    required this.actualDropField,
    required this.actualPickupField,
    required this.actualSaleField,
    required this.actualBuyField,
    required this.actualRefillField,
  });
}

/// Extract items from a task doc as `List<Map<String,dynamic>>`.
///
/// Byte-for-byte mirror of `ItemExecutionList._extractItems` (the extractor
/// that seeds the execution store): non-Map entries are skipped and each entry
/// is cast via `Map<String,dynamic>.from`. Sharing the identical extraction
/// guarantees the `'$i'` index keys of the execution store line up exactly with
/// the rebuilt `it[]` here (I1 -- no actual can land on the wrong item).
///
/// Convention #7: items originate from firestoreDb (dynamic).
List<Map<String, dynamic>> extractItemsFromDoc(
  Map<String, dynamic>? taskDoc,
  String itemsField,
) {
  if (taskDoc == null) return const [];
  final dynamic rawItems = taskDoc[itemsField];
  if (rawItems is! List) return const [];
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final dynamic entry in rawItems) {
    if (entry is! Map) continue;
    out.add(Map<String, dynamic>.from(entry));
  }
  return out;
}

/// Parse field-name config from any component JSON that carries task-field
/// overrides (LIST or SUBMIT widget). Pure function for testability.
///
/// Defaults mirror the live server values. The LIST component carries the
/// plan-field overrides (itemsField, txField, planDropField, etc.); the
/// actual-field defaults (ad, ap, as, ab, ar) are always correct because
/// the server does not override them on the LIST component.
ItemExecutionSubmitConfig parseConfigFromComponent(dynamic component) {
  String f(String key, String def) => (component[key] ?? def).toString().trim();
  return ItemExecutionSubmitConfig(
    itemsField: f('itemsField', 'it'),
    txField: f('txField', 'tx'),
    planDropField: f('planDropField', 'pd'),
    planPickupField: f('planPickupField', 'pp'),
    saleField: f('saleField', 'ps'),
    buyField: f('buyField', 'pb'),
    refillField: f('refillField', 'pr'),
    actualDropField: f('actualDropField', 'ad'),
    actualPickupField: f('actualPickupField', 'ap'),
    actualSaleField: f('actualSaleField', 'as'),
    actualBuyField: f('actualBuyField', 'ab'),
    actualRefillField: f('actualRefillField', 'ar'),
  );
}

/// Find the active task doc from a component's table/search config.
///
/// Replicates the logic of `ItemExecutionList._findActiveTask` and
/// `_ItemExecutionSubmitState._findActiveTask` as a static utility:
///   1. Parse table path from component['table'].
///   2. Read docs from mapTableContent[code].
///   3. Filter by component['search'] via filterDriverHomeDocs.
///   4. Return the first match, or null.
///
/// NOT pure (reads mapTableContent, calls filterDriverHomeDocs which reads
/// transactionStore). Tested via manual/integration, not unit.
Map<String, dynamic>? findActiveTaskDoc(dynamic component, String scrName) {
  final String rawTable = (component['table'] ?? '').toString().trim();
  if (rawTable.isEmpty) return null;
  final TablePath tp = parseTablePath(rawTable);
  if (tp.tableDocId.isEmpty) return null;
  // vid-scoped: must match ItemExecutionList/ItemExecutionSubmit's scoped
  // _taskCode key, else this read-back misses the task doc and the actual
  // write drops it[] actuals (only tst/tce land).
  final String taskCode =
      '${resolveAppVid(component)}/${tp.tableDocId}/${tp.subColl}';
  final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
    mapTableContent[taskCode] ?? const [],
  );
  final String rawSearch = (component['search'] ?? '').toString().trim();
  if (rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
  final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
    docs,
    rawSearch,
    scrName,
  );
  return matched.isNotEmpty ? matched.first : null;
}

/// Rebuild the it[] array with actual fields set on every line.
///
/// For each item:
///   - Preserves ALL existing fields (shallow copy; do not reconstruct).
///   - Sets ONLY the actual field(s) based on tx kind.
///   - Always writes the actual field, even when untouched (actual == plan).
///
/// Convention #7: items from firestoreDb are `dynamic`; reads/writes use
/// explicit `toString()` + `int.tryParse` for plan values.
List<Map<String, dynamic>> rebuildItWithActuals(
  List<Map<String, dynamic>> items,
  Map<String, ExecutionEntry> execMap,
  ItemExecutionSubmitConfig cfg,
) {
  final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
  for (int i = 0; i < items.length; i++) {
    // Shallow copy to preserve all existing fields
    final Map<String, dynamic> item = Map<String, dynamic>.from(items[i]);
    final String txKind = classifyTxKind(
      (item[cfg.txField] ?? '').toString().trim().toLowerCase(),
    );
    final String key = '$i';

    switch (txKind) {
      case 'deliver':
        final ExecutionEntry? entry = execMap[key];
        if (entry != null) {
          item[cfg.actualDropField] = entry.dropActual;
          item[cfg.actualPickupField] = entry.pickupActual;
        } else {
          // Defensive fallback: no executionStore entry -> actual = plan
          item[cfg.actualDropField] =
              int.tryParse(
                (item[cfg.planDropField] ?? '0').toString().trim(),
              ) ??
              0;
          item[cfg.actualPickupField] =
              int.tryParse(
                (item[cfg.planPickupField] ?? '0').toString().trim(),
              ) ??
              0;
        }
        break;
      case 'sale':
        item[cfg.actualSaleField] =
            int.tryParse((item[cfg.saleField] ?? '0').toString().trim()) ?? 0;
        break;
      case 'purchase':
        item[cfg.actualBuyField] =
            int.tryParse((item[cfg.buyField] ?? '0').toString().trim()) ?? 0;
        break;
      case 'refill':
        item[cfg.actualRefillField] =
            int.tryParse((item[cfg.refillField] ?? '0').toString().trim()) ?? 0;
        break;
    }

    result.add(item);
  }
  return result;
}

/// Strip `tst` and `tce` body key-value pairs from an updateEventRow DSL
/// string, to avoid double-writing these fields via saveSend when the native
/// write already owns them.
///
/// DSL clauses are separated by literal `⭘` (U+2B58). Each body clause is
/// `key◼value` (literal `◼`, U+25FC). The first clause is the collection path
/// (no `◼`) and is preserved; `tablevid`/`search` header clauses are preserved;
/// only body clauses whose key (before the first `◼`) is exactly `tst` or `tce`
/// are removed.
///
/// W1: operates on the LITERAL stored form (see class doc). The form saveSend
/// persists uses literal `⭘`/`◼`, so the split chars below match exactly.
String stripTstFromUpdateEventRow(String dsl) {
  if (dsl.isEmpty) return dsl;
  // The first clause is the path (e.g. '84214220504259//task') -- no ◼
  // Subsequent clauses are key◼value.
  final List<String> clauses = dsl.split('\u{2B58}');
  final List<String> kept = <String>[];
  for (final String clause in clauses) {
    final String trimmed = clause.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}');
    if (sep > 0) {
      final String key = trimmed.substring(0, sep).trim();
      if (key == 'tst' || key == 'tce') continue; // strip
    }
    kept.add(trimmed);
  }
  return kept.join('\u{2B58}');
}

/// True iff [dsl] carries at least one body key/value clause beyond the header
/// (path / tablevid / search). Used after [stripTstFromUpdateEventRow] to decide
/// whether the resulting updateEventRow still has anything to merge.
///
/// W2: the live P11 updateEventRow is only `tst◼completed⭘tce◼{now}` plus
/// header clauses, so after the tst/tce strip the body is empty. historySync
/// would issue a harmless `set({}, merge:true)` no-op, but dropping the empty
/// updateEventRow avoids the redundant query+write. The collection path (first
/// clause, no `◼`) and the `tablevid`/`search` header pairs are NOT body.
bool updateEventRowHasBody(String dsl) {
  if (dsl.isEmpty) return false;
  final List<String> clauses = dsl.split('\u{2B58}');
  for (final String clause in clauses) {
    final String trimmed = clause.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}');
    if (sep <= 0) continue; // path clause (no ◼) -- not body
    final String key = trimmed.substring(0, sep).trim();
    if (key == 'tablevid' || key == 'search') continue; // header -- not body
    return true; // a real body clause survives
  }
  return false;
}
