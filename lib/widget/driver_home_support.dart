import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../api.dart'; // getTableVid
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

// ─── DriverHome session state ──────────────────────────────────────────────

/// Per-screen state for the DriverHome page. Keyed by scrName, cleared on
/// route change (via buildPage clear hook). Reactive: Phase 2 consumers Obx
/// this to show/hide based on `confirmed`.
class DriverHomeState {
  /// Vehicle ID published by the header once workforce doc loads.
  final RxString vehicleId = ''.obs;

  /// Whether the gate search found >=1 matching doc (confirmed).
  final RxBool confirmed = false.obs;

  /// Internal: tracks whether vehicleId has been resolved at least once
  /// (distinguishes "empty because not loaded yet" from "genuinely no vehicle").
  bool vehicleIdResolved = false;

  /// Driver display name (workforce doc field `n`, published by the header).
  /// Used by `resolveDriverCurlyTokens` for `{driverName}` token.
  final RxString driverName = ''.obs;
}

/// Per-scrName state map. Accessed by header, gate card, TXT label, and
/// Phase 2 widgets. Cleared in buildPage(clear:true).
final Map<String, DriverHomeState> driverHomeStates = {};

/// Obtain or create the DriverHomeState for a screen.
DriverHomeState getDriverHomeState(String scrName) {
  return driverHomeStates.putIfAbsent(scrName, () => DriverHomeState());
}

/// Clear state for a screen. Called from buildPage alongside
/// ApproverStickyBar.clearConfigs.
void clearDriverHomeState(String scrName) {
  driverHomeStates.remove(scrName);
}

// ─── appVid resolution (shared by all 5 DriverHome widgets) ────────────────

/// Resolve the Firestore container VID for a component's table subscription.
///
/// Priority: `component['vidtable']` (explicit override) > `getTableVid(com)`
/// (tenant lookup by `component['com']`; falls back to applicationTableVid).
///
/// Returns a non-empty String suitable for the `appVid` parameter of
/// `subscribeToMapCollection`. Mirrors the scanner pattern (scanner.dart:236).
String resolveAppVid(dynamic component) {
  final String explicit = (component['vidtable'] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit;
  return getTableVid(component['com']?.toString()).toString();
}

// ─── Driver login persistence (secure-storage mirror of #has_user_login) ────

/// Secure-storage key name for the driver VID. Mirrors #has_user_login.
/// Documented in documentation.md "Secure Storage Keys" section.
const String _driverLoginKey = 'driverLogin';

/// Persist the driver VID to secure storage.
/// Called alongside every Redux dispatch of #has_user_login = a non-empty VID.
/// Error-swallowing (devPrint) matches the storage I/O pattern elsewhere —
/// a secure-storage write must never crash the scan flow.
Future<void> persistDriverLogin(String vid) async {
  try {
    await storage.write(key: _driverLoginKey, value: vid);
  } catch (e) {
    devPrint('persistDriverLogin error: $e');
  }
}

/// Clear the driver VID from secure storage.
/// Called alongside every Redux dispatch of #has_user_login = ''.
Future<void> clearDriverLogin() async {
  try {
    await storage.delete(key: _driverLoginKey);
  } catch (e) {
    devPrint('clearDriverLogin error: $e');
  }
}

/// Read the persisted driver VID from secure storage.
/// Returns the VID string, or null/empty if not set.
/// Used by globalInit to restore #has_user_login on cold start.
Future<String?> readDriverLogin() async {
  try {
    return await storage.read(key: _driverLoginKey);
  } catch (e) {
    devPrint('readDriverLogin error: $e');
    return null;
  }
}

// ─── Driver curly-token resolution ─────────────────────────────────────────

/// Resolve driver-specific `{curly}` tokens in a raw string.
///
/// Mapping (spec section 0-B):
///   {driverVid}  -> screenTx['#has_user_login'] (scanned driver VID)
///   {vehicleId}  -> DriverHomeState.vehicleId for this scrName
///   {driverName} -> DriverHomeState.driverName for this scrName
///   {activeTaskVid} -> screenTx['#ACTIVE_TASK'] (tapped task VID from P10)
///   {tnm}        -> screenTx['#ACTIVE_TASK'] (alias of {activeTaskVid}; task doc id per spec section 4)
///   {rejectTaskVid} -> screenTx['#REJECT_TASK'] (task VID being rejected from P4 stop card)
///   {today}      -> todayEpochMidnightWib() (epoch-ms of WIB midnight)
///
/// Runs BEFORE `resolveScreenTxTokens` in the filterDriverHomeDocs pipeline.
/// Unknown `{...}` tokens are left as-is so `resolveScreenTxTokens` can handle
/// them (it also leaves unknowns literal, so `filterByMultiClause`'s
/// `value.contains('{')` guard returns empty -- pending-safe).
///
/// Unresolved `{driverVid}` (empty #has_user_login), `{vehicleId}` (empty
/// state), `{driverName}` (empty state), and `{activeTaskVid}` (empty
/// #ACTIVE_TASK) are left as-is -- NOT resolved to empty string. This
/// preserves the pending-safe guard.
String resolveDriverCurlyTokens(String raw, String scrName) {
  if (!raw.contains('{')) return raw;
  final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
  final DriverHomeState state = getDriverHomeState(scrName);

  return raw.replaceAllMapped(
    RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
    (Match m) {
      final String name = m.group(1)!;
      switch (name) {
        case 'driverVid':
          final String v = (screenTx['#has_user_login'] ?? '').toString();
          return v.isNotEmpty ? v : m.group(0)!;
        case 'vehicleId':
          final String v = state.vehicleId.value;
          return v.isNotEmpty ? v : m.group(0)!;
        case 'driverName':
          final String v = state.driverName.value;
          return v.isNotEmpty ? v : m.group(0)!;
        case 'activeTaskVid':
          final String v = (screenTx['#ACTIVE_TASK'] ?? '').toString();
          return v.isNotEmpty ? v : m.group(0)!;
        case 'tnm':
          final String v = (screenTx['#ACTIVE_TASK'] ?? '').toString();
          return v.isNotEmpty ? v : m.group(0)!;
        case 'rejectTaskVid':
          final String v = (screenTx['#REJECT_TASK'] ?? '').toString();
          return v.isNotEmpty ? v : m.group(0)!;
        case 'today':
          return todayEpochMidnightWib();
        default:
          // routeParams fallback: resolve from bare screenTx key if present
          // and non-empty. Otherwise leave literal for resolveScreenTxTokens.
          // Reserved tokens (vehicleId, driverName, tnm, today, driverVid,
          // activeTaskVid, rejectTaskVid) are handled by switch cases above
          // and never reach here.
          final String bareVal = (screenTx[name] ?? '').toString();
          return bareVal.isNotEmpty ? bareVal : m.group(0)!;
      }
    },
  );
}

/// Epoch-ms of today's midnight in WIB (UTC+7), as a String.
///
/// Backend `cdt`/`tdt` fields store epoch-midnight-ms; this must match exactly
/// for eq-comparison in `filterByMultiClause`.
///
/// Uses NTP-corrected time via `getNowMillisecondFromEpoch()` (api.dart:1179)
/// when `#REF_TIME_START`/`#DEVICE_TIME_START` are present; falls back to
/// device clock otherwise (same fallback behavior as getNowMillisecondFromEpoch).
///
/// WIB = UTC+7 = +25200000 ms. Computation:
///   1. Get NTP-corrected "now" in ms.
///   2. Shift to WIB local: nowMs + 25200000.
///   3. Floor to day start: (wibMs ~/ 86400000) * 86400000.
///   4. Shift back to UTC: dayStart - 25200000.
///   5. Return as String for string eq-match.
///
/// **OPEN ITEM:** backend MUST store cdt/tdt as epoch-midnight-ms integers.
/// If on-device data still uses JS date-strings or yyyyMMdd, eq-match fails
/// silently (searches return empty -> widgets show pending/locked).
///
/// For testability, accepts an optional [nowMs] override. Production callers
/// omit it (uses getNowMillisecondFromEpoch); tests pass a fixed value.
String todayEpochMidnightWib({int? nowMs}) {
  const int wibOffsetMs = 25200000; // UTC+7 in ms
  const int msPerDay = 86400000;
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  final int wibMs = now + wibOffsetMs;
  final int dayStartWib = (wibMs ~/ msPerDay) * msPerDay;
  final int utcMidnight = dayStartWib - wibOffsetMs;
  return utcMidnight.toString();
}

// ─── routeParams DSL parsing (RBT child declarative route data) ────────────

/// Parse the `routeParams` component field. Format: key◼value pairs separated
/// by ⭘ (U+2B58). Caller MUST `autheniumDecode()` the raw string BEFORE
/// calling (server sends ◼/⭘ as _25FC_/_2B58_).
///
/// Returns a list of `MapEntry<key, rawValue>`. The rawValue may contain
/// `{curly}` tokens that need further resolution by the caller.
///
/// Length-guards every segment: missing ◼ -> skipped; empty key -> skipped.
/// Empty raw input -> empty list.
///
/// Example: `"failedTaskVid◼{tnm}⭘mode◼edit"` ->
///   `[MapEntry("failedTaskVid", "{tnm}"), MapEntry("mode", "edit")]`
List<MapEntry<String, String>> parseRouteParams(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final List<MapEntry<String, String>> out = [];
  for (final part in raw.split('\u{2B58}')) {
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}');
    if (sep < 0) continue; // malformed pair — no ◼ separator, skip
    final String key = trimmed.substring(0, sep).trim();
    if (key.isEmpty) continue;
    final String value = trimmed.substring(sep + 1).trim();
    out.add(MapEntry(key, value));
  }
  return out;
}

/// Resolve routeParams values and dispatch them as bare keys into screenTx.
///
/// Pipeline:
///   1. autheniumDecode the raw DSL (server encodes ◼/⭘ as _25FC_/_2B58_).
///   2. parseRouteParams -> list of key/rawValue pairs.
///   3. For each pair, resolve the rawValue via resolveDriverCurlyTokens
///      (e.g. `{tnm}` -> `screenTx['#ACTIVE_TASK']`).
///   4. Collect all resolved pairs with non-empty values into a single
///      UpdateScreenTxAction dispatch (bare keys, no # prefix).
///
/// If the DSL is null/empty, or all pairs resolve to empty, no dispatch occurs.
/// Skips pairs whose resolved value is empty (pending-safe: unresolved `{x}`
/// tokens from resolveDriverCurlyTokens still contain `{` and will be treated
/// as unresolved, so they are NOT dispatched -- the destination page's
/// pending-safe guard handles it).
///
/// NOTE: literal routeParams values MUST NOT contain a `{` character. The
/// pending-safe guard drops any resolved value that still contains `{`, so a
/// literal like `mode◼a{b` would be silently skipped (treated as unresolved).
///
/// [rawDsl] -- the raw `component['routeParams']` string.
/// [scrName] -- screen name for curly-token resolution context.
void writeRouteParams(String? rawDsl, String scrName) {
  if (rawDsl == null || rawDsl.trim().isEmpty) return;
  final String decoded = autheniumDecode(rawDsl) ?? rawDsl;
  final List<MapEntry<String, String>> pairs = parseRouteParams(decoded);
  if (pairs.isEmpty) return;

  final Map<String, dynamic> toDispatch = {};
  for (final pair in pairs) {
    // Resolve curly tokens in the value (e.g. {tnm} -> #ACTIVE_TASK value).
    final String resolved = resolveDriverCurlyTokens(pair.value, scrName);
    // Skip if resolved value is empty or still contains unresolved token.
    if (resolved.isEmpty || resolved.contains('{')) continue;
    toDispatch[pair.key] = resolved;
  }

  if (toDispatch.isNotEmpty) {
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction(toDispatch)),
    );
  }
}

// ─── Multi-clause AND filter ───────────────────────────────────────────────

/// Filter docs by a multi-clause AND condition string. Clauses are separated
/// by `⭘` (U+2B58, the AND separator). Each clause is `field◼value` (U+25FC
/// is the field/value separator). All clauses must match for a doc to pass.
///
/// Token resolution (`{key}`) must be done BEFORE calling this.
/// If any clause has an empty value or still contains an unresolved token
/// (contains `{`), returns empty list (pending/safe default).
///
/// [docs] — the Firestore map docs to filter.
/// [resolvedConditions] — the conditions string AFTER autheniumDecode + token
///   resolution (already contains literal `◼` and `⭘` chars).
///
/// Returns matching docs, or empty list if no match or unresolvable token.
List<Map<String, dynamic>> filterByMultiClause(
  List<Map<String, dynamic>> docs,
  String resolvedConditions,
) {
  if (resolvedConditions.trim().isEmpty) return docs;

  // Split on ⭘ (AND separator)
  final List<String> clauses = resolvedConditions.split('\u{2B58}');
  final List<MapEntry<String, String>> pairs = [];

  for (final clause in clauses) {
    final String trimmed = clause.trim();
    if (trimmed.isEmpty) continue;
    // Split on first ◼ (field/value separator)
    final int sep = trimmed.indexOf('\u{25FC}');
    if (sep < 0) continue; // malformed clause — skip
    final String field = trimmed.substring(0, sep).trim();
    final String value = trimmed.substring(sep + 1).trim();
    if (field.isEmpty) continue;
    // Unresolved token guard: if value still has `{` (unresolved curly token),
    // bail to empty (pending).
    if (value.isEmpty || value.contains('{')) {
      return const [];
    }
    pairs.add(MapEntry(field, value));
  }

  if (pairs.isEmpty) return docs;

  // AND: doc must match ALL clauses
  return docs.where((doc) {
    for (final pair in pairs) {
      if ((doc[pair.key] ?? '').toString().trim() != pair.value) return false;
    }
    return true;
  }).toList();
}

/// Convenience: decode + resolve tokens + multi-clause filter in one call.
/// This is the primary entry point for DriverHome widgets' gate/data searches.
///
/// Pipeline order:
///   1. autheniumDecode -- server encodes special chars as _25FC_/_2B58_ etc.
///   2. resolveDriverCurlyTokens -- {driverVid}, {vehicleId}, {today}
///   3. resolveScreenTxTokens -- any remaining {key} from screenTx
///   4. filterByMultiClause -- AND filter on resolved conditions
List<Map<String, dynamic>> filterDriverHomeDocs(
  List<Map<String, dynamic>> docs,
  String rawSearch,
  String scrName,
) {
  if (rawSearch.trim().isEmpty) return docs;
  // 1. autheniumDecode: server encodes special chars
  final String decoded = autheniumDecode(rawSearch) ?? rawSearch;
  // 2. resolveDriverCurlyTokens: {driverVid}, {vehicleId}, {today} -> literals
  final String driverResolved = resolveDriverCurlyTokens(decoded, scrName);
  // 3. resolveScreenTxTokens: any remaining {key} from Redux screenTx
  final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
  final String fullyResolved = resolveScreenTxTokens(driverResolved, screenTx);
  // 4. Multi-clause AND filter
  return filterByMultiClause(docs, fullyResolved);
}

// ─── Per-widget gate evaluation (shared by inventory, stop, nav) ───────────

/// Evaluate a widget's own gate condition against its subscribed gate table.
///
/// [gateCode] — the subscription code for the gate table (e.g.
///   `"84214220504259/vehicle_check"`). Must already be subscribed via
///   `subscribeToMapCollection`.
/// [rawGateSearch] — the raw `component['gateSearch']` value. Server-encoded
///   (autheniumDecode + token resolution handled by `filterDriverHomeDocs`).
/// [scrName] — screen name for token resolution context.
///
/// Returns true when at least one gate doc matches the search condition.
/// Returns false when:
///   - gateCode is empty (no subscription)
///   - rawGateSearch is empty (explicit: empty gate = hidden; consistent with
///     PreconditionGateCard._matchedGateDoc's empty-search guard)
///   - no docs match the filter
bool evaluateGateSearch(
  String gateCode,
  String rawGateSearch,
  String scrName,
) {
  if (gateCode.isEmpty) return false;
  if (rawGateSearch.trim().isEmpty) return false;
  final List<Map<String, dynamic>> gateDocs =
      List<Map<String, dynamic>>.from(mapTableContent[gateCode] ?? const []);
  final List<Map<String, dynamic>> matched =
      filterDriverHomeDocs(gateDocs, rawGateSearch, scrName);
  return matched.isNotEmpty;
}

// ─── Item-name FK resolution (shared by inventory + gate cards) ────────────

/// Build a `Map<String, String>` mapping item-id -> item-name from a list of
/// item-collection docs.
///
/// Both the inventory card (asset_cache groups) and the gate card
/// (`{confirmedSummary}` from `ip[]`) need to resolve raw `ii` ids to human
/// display names. This helper is the SINGLE source of truth for that FK.
///
/// [itemDocs] -- docs from `mapTableContent[_itemCode]` (the item
///   subcollection). Each doc is expected to have [idField] (default `ii`)
///   and [nameField] (default `in`).
///
/// Convention #7: itemDocs originate from firestoreDb (dynamic); each doc is
/// `Map<String, dynamic>`. Field reads use `.toString().trim()` to handle
/// null / non-string gracefully. Entries with empty `ii` are skipped.
///
/// Returns an explicitly typed `Map<String, String>` (never a dynamic map).
Map<String, String> buildItemNameMap(
  List<Map<String, dynamic>> itemDocs, {
  String idField = 'ii',
  String nameField = 'in',
}) {
  final Map<String, String> map = <String, String>{};
  for (final Map<String, dynamic> doc in itemDocs) {
    final String id = (doc[idField] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final String name = (doc[nameField] ?? '').toString().trim();
    map[id] = name;
  }
  return map;
}

// ─── Per-item cargo rows (P12 vehicleCargoSummary) ─────────────────────────

/// One row of the per-item vehicle cargo card: an item (resolved name + raw
/// id) with its summed full/empty quantities.
///
/// Produced by [computePerItemCargoRows] for VehicleCargoSummary's "Sisa di
/// Kendaraan" card. `fullQty`/`emptyQty` are 0-filled when the corresponding
/// condition has no asset_cache doc for the item.
class CargoItemRow {
  /// Raw item id (asset_cache `ii`). Used as the sort tiebreak and the
  /// display-name fallback when the item master has no name.
  final String itemId;

  /// Resolved display name (item master `in`), or the raw [itemId] when the
  /// item master is absent or has an empty / missing name for it.
  final String displayName;

  /// Summed quantity for the `full` condition (0 when absent).
  final int fullQty;

  /// Summed quantity for the `empty` condition (0 when absent).
  final int emptyQty;

  const CargoItemRow({
    required this.itemId,
    required this.displayName,
    required this.fullQty,
    required this.emptyQty,
  });
}

/// Group asset_cache docs by item id, sum quantity per condition, resolve
/// names, return rows sorted by resolved name ascending (tiebreak raw `ii`).
/// 0-fills missing conditions.
///
/// Pure — no Flutter/Obx deps, directly testable. The SINGLE source of truth
/// for VehicleCargoSummary's per-item aggregation (the widget calls this; it
/// does not re-implement the logic).
///
/// Algorithm:
///   1. Group [cacheDocs] by [itemField] (skip docs with empty `ii`).
///   2. Within each group, sum [qtyField] per LOWERCASED [conditionField].
///   3. Resolve `ii` -> name via [itemNameMap]; fall back to the raw `ii`
///      when the map has no entry OR the entry is an empty string.
///   4. Sort distinct ids by resolved name ascending, tiebreak by raw `ii`
///      ascending.
///   5. Emit one [CargoItemRow] per id, 0-filling [conditionFull] /
///      [conditionEmpty] when that condition is absent for the item.
///
/// Convention #7/#10: [cacheDocs] originate from a `dynamic` Firestore store;
/// field reads use `.toString().trim()` and `int.tryParse(...) ?? 0`. Returns
/// an explicitly typed `List<CargoItemRow>` (never `.map().toList()` into a
/// typed store).
List<CargoItemRow> computePerItemCargoRows(
  List<Map<String, dynamic>> cacheDocs,
  Map<String, String> itemNameMap, {
  String itemField = 'ii',
  String conditionField = 'cd',
  String qtyField = 'qt',
  String conditionFull = 'full',
  String conditionEmpty = 'empty',
}) {
  // Group by ii. grouped[ii] = { conditionValue: summedQty }
  final Map<String, Map<String, int>> grouped = <String, Map<String, int>>{};
  final Set<String> seen = <String>{};

  for (final Map<String, dynamic> doc in cacheDocs) {
    final String itemId = (doc[itemField] ?? '').toString().trim();
    if (itemId.isEmpty) continue;
    seen.add(itemId);
    final String cond =
        (doc[conditionField] ?? '').toString().trim().toLowerCase();
    final int qty =
        int.tryParse((doc[qtyField] ?? '0').toString().trim()) ?? 0;
    final Map<String, int> bucket =
        grouped.putIfAbsent(itemId, () => <String, int>{});
    bucket[cond] = (bucket[cond] ?? 0) + qty;
  }

  // Sort by resolved name ascending, tiebreak by raw ii.
  final List<String> sortedIds = seen.toList()
    ..sort((a, b) {
      final String nameA =
          itemNameMap[a]?.isNotEmpty == true ? itemNameMap[a]! : a;
      final String nameB =
          itemNameMap[b]?.isNotEmpty == true ? itemNameMap[b]! : b;
      final int cmp = nameA.compareTo(nameB);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

  final List<CargoItemRow> rows = <CargoItemRow>[];
  for (final String itemId in sortedIds) {
    final String displayName =
        itemNameMap[itemId]?.isNotEmpty == true ? itemNameMap[itemId]! : itemId;
    rows.add(CargoItemRow(
      itemId: itemId,
      displayName: displayName,
      fullQty: grouped[itemId]?[conditionFull] ?? 0,
      emptyQty: grouped[itemId]?[conditionEmpty] ?? 0,
    ));
  }
  return rows;
}

/// Aggregate `vehicle_check.ip[]` into a display summary string.
///
/// The `ip` array on a vehicle_check doc records the actual physical count
/// per item/condition: each entry is `{ii: <item-id>, cd: <condition>, qt: <qty>}`.
///
/// This groups by [idField] (default `ii`), SUMS [qtyField] (default `qt`)
/// across ALL `cd` values (full + empty = total physical per item), resolves
/// `ii` -> item name via [itemNameMap] (built by `buildItemNameMap`), and
/// formats each as `"{totalQty} {name}"`, joined by ` \u{00B7} ` (middle dot).
///
/// If `ii` has no entry in [itemNameMap], falls back to the raw `ii` string.
///
/// Convention #7: the `ip` array is `dynamic` from Firestore. Guarded:
///   - `ipArray` must be `List` (else returns empty string)
///   - each entry must be `Map` (non-Map entries skipped)
///   - `qt` parsed via `int.tryParse(... ) ?? 0`
///
/// Returns empty string when `ipArray` is empty, not a List, or all entries
/// are malformed.
String aggregateActualSummary(
  dynamic ipArray,
  Map<String, String> itemNameMap, {
  String idField = 'ii',
  String qtyField = 'qt',
}) {
  if (ipArray is! List) return '';

  // Preserve first-seen order: ordered list of ids + an id->totalQty map.
  final List<String> order = <String>[];
  final Map<String, int> totals = <String, int>{};

  for (final dynamic entry in ipArray) {
    if (entry is! Map) continue;
    final String id = (entry[idField] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final int qty =
        int.tryParse((entry[qtyField] ?? '0').toString().trim()) ?? 0;
    if (!totals.containsKey(id)) {
      order.add(id);
      totals[id] = 0;
    }
    totals[id] = totals[id]! + qty;
  }

  if (order.isEmpty) return '';

  final List<String> parts = <String>[];
  for (final String id in order) {
    final String name = itemNameMap[id]?.isNotEmpty == true
        ? itemNameMap[id]!
        : id; // fallback to raw id
    parts.add('${totals[id]} $name');
  }
  return parts.join(' \u{00B7} '); // middle dot separator
}

// ─── Gate-card cargo manifest (preconditionGateCard) ───────────────────────

/// Flatten + aggregate the nested per-task item arrays into a display list.
///
/// R2-3: the cargo manifest is NOT a flat list of item docs. Each task doc
/// carries an [itemsField] ARRAY (default `it`); each entry is a map like
/// `{in: <item name>, pd: <planned qty>, ...}`. This walks every task doc's
/// item array, sums the [qtyField] (default `pd`) per distinct [labelField]
/// (default `in`), and returns one row per distinct label in first-seen order.
///
/// Output rows are shaped `{<labelField>: name, <qtyField>: totalQty}` so the
/// existing pending-card render (which reads `row[labelField]` / `row[qtyField]`)
/// works unchanged.
///
/// Convention #7/#10: `taskDocs` come from a `dynamic` Firestore store, so the
/// `it` value is `dynamic` — guarded `is List` / `is Map` before iterating, and
/// qty parsed via `int.tryParse(... ) ?? 0`. The returned list is built as an
/// explicitly typed `List<Map<String, dynamic>>` (never `.map().toList()` into a
/// typed store).
List<Map<String, dynamic>> aggregateItems(
  List<Map<String, dynamic>> taskDocs,
  String itemsField,
  String labelField,
  String qtyField,
) {
  // Preserve first-seen order: ordered list of labels + a label->total map.
  final List<String> order = <String>[];
  final Map<String, int> totals = <String, int>{};

  for (final Map<String, dynamic> doc in taskDocs) {
    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue; // guard non-array / absent
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue; // guard non-map entries
      final String label = (entry[labelField] ?? '').toString().trim();
      if (label.isEmpty) continue;
      final int qty =
          int.tryParse((entry[qtyField] ?? '0').toString().trim()) ?? 0;
      if (!totals.containsKey(label)) {
        order.add(label);
        totals[label] = 0;
      }
      totals[label] = totals[label]! + qty;
    }
  }

  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final String label in order) {
    out.add(<String, dynamic>{
      labelField: label,
      qtyField: totals[label],
    });
  }
  return out;
}

/// Numeric coercion for Firestore dynamic fields: handles int, double, String,
/// null. Returns the numeric value or 0.
num _coerceNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString().trim()) ?? 0;
}

/// Tx-aware manifest aggregator for [PreconditionGateCard].
///
/// Like [aggregateItems] but sums THREE qty fields (deliver + sale + refill)
/// and supports task exclusion by status + zero-qty hiding.
///
/// [taskDocs] -- task docs from `mapTableContent`.
/// [itemsField] -- key for the nested items array (e.g. `it`).
/// [labelField] -- key for the item display name (e.g. `in`).
/// [deliverField] -- key for planned-deliver qty (e.g. `pd`).
/// [saleField] -- key for sale qty (e.g. `ps`).
/// [refillField] -- key for refill/exchange qty (e.g. `pr`).
/// [excludeStatus] -- if non-empty, skip task docs whose `tst` field matches
///   this value (e.g. `load_rejected`). Empty string = skip nothing.
/// [hideZero] -- when true, drop items whose aggregated total is 0.
///
/// Output rows are shaped `{<labelField>: name, <deliverField>: total}` so the
/// existing pending-card render (which reads `row[labelField]` / `row[qtyField]`
/// where qtyField == deliverField) works unchanged.
///
/// Convention #7: dynamic guards throughout (is List, is Map, _coerceNum).
List<Map<String, dynamic>> aggregateManifestItems(
  List<Map<String, dynamic>> taskDocs, {
  required String itemsField,
  required String labelField,
  required String deliverField,
  required String saleField,
  required String refillField,
  String excludeStatus = '',
  bool hideZero = false,
}) {
  final List<String> order = <String>[];
  final Map<String, int> totals = <String, int>{};

  for (final Map<String, dynamic> doc in taskDocs) {
    // A: skip tasks with excluded status
    if (excludeStatus.isNotEmpty) {
      final String tst = (doc['tst'] ?? '').toString().trim();
      if (tst == excludeStatus) continue;
    }

    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue; // guard non-array / absent

    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue; // guard non-map entries
      final String label = (entry[labelField] ?? '').toString().trim();
      if (label.isEmpty) continue;

      // B: sum deliver + sale + refill
      final int lineQty = (_coerceNum(entry[deliverField]) +
              _coerceNum(entry[saleField]) +
              _coerceNum(entry[refillField]))
          .toInt();

      if (!totals.containsKey(label)) {
        order.add(label);
        totals[label] = 0;
      }
      totals[label] = totals[label]! + lineQty;
    }
  }

  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final String label in order) {
    final int total = totals[label]!;
    // C: hide zero-qty items
    if (hideZero && total == 0) continue;
    out.add(<String, dynamic>{
      labelField: label,
      deliverField: total,
    });
  }
  return out;
}

// ─── Bucket parsing (inventoryBucketCard) ─────────────────────────────────

/// One entry from the component `buckets` field: `label◼status` per bucket
/// definition (e.g. "isi◼ok"). The label is the display name, the status is
/// the visual variant (ok/warn/danger).
class BucketDef {
  final String label;
  final String status;
  const BucketDef(this.label, this.status);
}

/// Parse the `buckets` component field. Format: entries separated by `⭘`
/// (U+2B58), each entry is `label◼status` (U+25FC). Caller MUST
/// `autheniumDecode()` the raw string BEFORE calling (server sends
/// `_25FC_`/`_2B58_` escapes). Returns empty list on null/empty/malformed.
///
/// Example: `"isi◼ok⭘kosong◼warn"` -> `[BucketDef("isi","ok"), BucketDef("kosong","warn")]`
List<BucketDef> parseBuckets(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final List<BucketDef> out = [];
  for (final part in raw.split('\u{2B58}')) {
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}');
    if (sep < 0) continue; // malformed — skip
    final String label = trimmed.substring(0, sep).trim();
    final String status = trimmed.substring(sep + 1).trim();
    if (label.isEmpty) continue;
    out.add(BucketDef(label, status.isEmpty ? 'ok' : status));
  }
  return out;
}

// ─── Stop progress computation (driverStopCard + navActionCard) ───────────

/// Centralized stop-status mapping. The `tst` field on a task doc holds a
/// lowercase string. This is the SINGLE source of truth for the mapping.
///
/// Spec vocab (section 4):
/// - `closed` -> normalized `done` -> terminal (SELESAI)
/// - `failed` -> normalized `failed` -> terminal (GAGAL)
/// - `ongoing` -> normalized `active` -> open (LANJUT)
/// - `assigned` / empty / absent -> normalized `pending` -> open (KIRIM/AMBIL)
///
/// Backward-compatible aliases (existing data):
/// - `done` -> `done` (unchanged)
/// - `active` -> `active` (unchanged)
///
/// `_closedStatuses` contains the NORMALIZED values (`done`, `failed`); raw
/// spec values (`closed`) are normalized BEFORE the set check.
const Set<String> _closedStatuses = {'done', 'failed'};

/// Whether a NORMALIZED status represents a closed (done/failed) stop.
///
/// Expects the value already returned by `stopStatusOf` (one of `done`,
/// `failed`, `active`, `pending`) -- NOT a raw `tst` value. The sole caller
/// (`driver_stop_card.dart`) normalizes via `stopStatusOf` first. A raw spec
/// value such as `closed` is NOT in `_closedStatuses` and would return false
/// here; it must be normalized to `done` beforehand.
bool isStopClosed(String tst) => _closedStatuses.contains(tst.trim().toLowerCase());

/// Progress snapshot for a set of task/stop docs.
class StopProgress {
  /// Total number of stops.
  final int total;

  /// Number of closed stops (done + failed).
  final int closed;

  /// True when all stops are closed AND there is at least one stop.
  final bool allClosed;

  /// The first non-closed stop doc, or null if all closed / empty.
  final Map<String, dynamic>? nextStop;

  const StopProgress({
    required this.total,
    required this.closed,
    required this.allClosed,
    this.nextStop,
  });
}

/// Map a raw `tst` field value to a normalized display status string.
/// Returns one of: `done`, `failed`, `active`, `pending`.
///
/// Spec vocab (section 4: tst exec-state):
///   `closed`    -> `done`    (terminal; badge SELESAI)
///   `completed` -> `done`    (terminal; P10 alias for closed)
///   `failed`    -> `failed`  (terminal; badge GAGAL)
///   `ongoing`   -> `active`  (open; badge LANJUT)
///   `assigned` / empty / absent / unknown -> `pending` (open; badge KIRIM/AMBIL)
///
/// Backward-compatible: `done` -> `done`, `active` -> `active` (existing data).
String stopStatusOf(Map<String, dynamic> doc, {String tstField = 'tst'}) {
  final String raw = (doc[tstField] ?? '').toString().trim().toLowerCase();
  if (raw == 'done' || raw == 'closed' || raw == 'completed') return 'done';
  if (raw == 'failed') return 'failed';
  if (raw == 'active' || raw == 'ongoing') return 'active';
  return 'pending';
}

/// Compute stop progress from a list of filtered task docs.
///
/// [docs] should already be filtered by vehicle + today via
/// `filterDriverHomeDocs`. The `tst` field (overridable via [tstField]) on
/// each doc determines its status.
///
/// Returns a [StopProgress] snapshot with totals, closed count, allClosed
/// flag, and the next (first non-closed) stop doc.
StopProgress computeStopProgress(
  List<Map<String, dynamic>> docs, {
  String tstField = 'tst',
}) {
  if (docs.isEmpty) {
    return const StopProgress(total: 0, closed: 0, allClosed: false);
  }
  int closed = 0;
  Map<String, dynamic>? nextStop;
  for (final doc in docs) {
    final String status = stopStatusOf(doc, tstField: tstField);
    if (_closedStatuses.contains(status)) {
      closed++;
    } else {
      // First non-closed doc becomes nextStop; later ones leave it unchanged.
      nextStop ??= doc;
    }
  }
  return StopProgress(
    total: docs.length,
    closed: closed,
    allClosed: closed == docs.length,
    nextStop: nextStop,
  );
}

// ─── Per-task drop/pickup aggregate (P5 taskManifestList) ──────────────────

/// Aggregated drop/pickup totals for a single task doc.
class TaskAggregate {
  /// Number of item-line entries in this task's it[] (length of the array).
  final int itemLineCount;

  /// Sum of planned_drop (pd) across all item lines.
  final int totalDrop;

  /// Sum of planned_pickup (pp) across all item lines.
  final int totalPickup;

  const TaskAggregate({
    required this.itemLineCount,
    required this.totalDrop,
    required this.totalPickup,
  });
}

/// Compute per-task aggregate drop/pickup from a single task doc's items array.
///
/// [doc] -- a single task doc from mapTableContent.
/// [itemsField] -- key for the nested items array (default `it`).
/// [dropField] -- key for planned-drop qty inside each item (default `pd`).
/// [pickupField] -- key for planned-pickup qty inside each item (default `pp`).
///
/// Convention #7: the `it` value is `dynamic` from Firestore. Guarded: `is List`
/// before iterating, `is Map` per entry, qty via `int.tryParse(...) ?? 0`.
///
/// Returns [TaskAggregate] with item-line count and summed pd/pp. If the items
/// field is absent or not a List, returns zeros.
TaskAggregate aggregateTaskDropPickup(
  Map<String, dynamic> doc, {
  String itemsField = 'it',
  String dropField = 'pd',
  String pickupField = 'pp',
}) {
  final dynamic rawItems = doc[itemsField];
  if (rawItems is! List) {
    return const TaskAggregate(itemLineCount: 0, totalDrop: 0, totalPickup: 0);
  }
  int lineCount = 0;
  int dropSum = 0;
  int pickupSum = 0;
  for (final dynamic entry in rawItems) {
    if (entry is! Map) continue;
    lineCount++;
    dropSum +=
        int.tryParse((entry[dropField] ?? '0').toString().trim()) ?? 0;
    pickupSum +=
        int.tryParse((entry[pickupField] ?? '0').toString().trim()) ?? 0;
  }
  return TaskAggregate(
    itemLineCount: lineCount,
    totalDrop: dropSum,
    totalPickup: pickupSum,
  );
}

// ─── Grand drop/pickup aggregate (P10 routeFeedHeader) ─────────────────────

/// Grand drop/pickup totals across multiple task docs.
class GrandDropPickup {
  final int totalDrop;
  final int totalPickup;
  final int actualDrop;
  final int actualPickup;
  const GrandDropPickup({
    required this.totalDrop,
    required this.totalPickup,
    required this.actualDrop,
    required this.actualPickup,
  });
}

/// Aggregate pd, pp, ad, ap across ALL task docs' it[] arrays.
///
/// [taskDocs] -- filtered task docs for this vehicle+today.
/// [itemsField] -- key for the nested items array (default `it`).
/// [dropField] -- key for planned-drop qty (default `pd`).
/// [pickupField] -- key for planned-pickup qty (default `pp`).
/// [actualDropField] -- key for actual-drop qty (default `ad`).
/// [actualPickupField] -- key for actual-pickup qty (default `ap`).
///
/// Convention #7: dynamic guards throughout (is List, is Map, int.tryParse).
GrandDropPickup aggregateGrandDropPickup(
  List<Map<String, dynamic>> taskDocs, {
  String itemsField = 'it',
  String dropField = 'pd',
  String pickupField = 'pp',
  String actualDropField = 'ad',
  String actualPickupField = 'ap',
}) {
  int totalDrop = 0;
  int totalPickup = 0;
  int actualDrop = 0;
  int actualPickup = 0;

  for (final Map<String, dynamic> doc in taskDocs) {
    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue;
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      totalDrop +=
          int.tryParse((entry[dropField] ?? '0').toString().trim()) ?? 0;
      totalPickup +=
          int.tryParse((entry[pickupField] ?? '0').toString().trim()) ?? 0;
      actualDrop +=
          int.tryParse((entry[actualDropField] ?? '0').toString().trim()) ?? 0;
      actualPickup +=
          int.tryParse((entry[actualPickupField] ?? '0').toString().trim()) ?? 0;
    }
  }
  return GrandDropPickup(
    totalDrop: totalDrop,
    totalPickup: totalPickup,
    actualDrop: actualDrop,
    actualPickup: actualPickup,
  );
}

// ─── Cross-route item circulation aggregate (P5 circulationSummary) ────────

/// One row of the circulation summary: an item name with its summed drop/pickup.
class ItemCirculation {
  final String itemName;
  final int totalDrop;
  final int totalPickup;
  const ItemCirculation({
    required this.itemName,
    required this.totalDrop,
    required this.totalPickup,
  });
}

/// Result of cross-route item aggregation: per-item rows + grand totals.
class CirculationResult {
  final List<ItemCirculation> items;
  final int grandDrop;
  final int grandPickup;
  const CirculationResult({
    required this.items,
    required this.grandDrop,
    required this.grandPickup,
  });
}

/// Aggregate ALL tasks' it[] entries by item name, summing drop and pickup per
/// distinct item. Returns [CirculationResult] with per-item rows (first-seen
/// order) and grand totals.
///
/// [taskDocs] -- filtered task docs for this vehicle+today.
/// [itemsField] -- key for the nested items array (default `it`).
/// [labelField] -- key for the item display name (default `in`).
/// [dropField] -- key for planned-drop qty (default `pd`).
/// [pickupField] -- key for planned-pickup qty (default `pp`).
///
/// Convention #7: dynamic guards throughout (is List, is Map, int.tryParse).
CirculationResult aggregateItemCirculation(
  List<Map<String, dynamic>> taskDocs, {
  String itemsField = 'it',
  String labelField = 'in',
  String dropField = 'pd',
  String pickupField = 'pp',
}) {
  final List<String> order = <String>[];
  final Map<String, int> dropTotals = <String, int>{};
  final Map<String, int> pickupTotals = <String, int>{};
  int grandDrop = 0;
  int grandPickup = 0;

  for (final Map<String, dynamic> doc in taskDocs) {
    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue;
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      final String label = (entry[labelField] ?? '').toString().trim();
      if (label.isEmpty) continue;
      final int drop =
          int.tryParse((entry[dropField] ?? '0').toString().trim()) ?? 0;
      final int pickup =
          int.tryParse((entry[pickupField] ?? '0').toString().trim()) ?? 0;
      if (!dropTotals.containsKey(label)) {
        order.add(label);
        dropTotals[label] = 0;
        pickupTotals[label] = 0;
      }
      dropTotals[label] = dropTotals[label]! + drop;
      pickupTotals[label] = pickupTotals[label]! + pickup;
      grandDrop += drop;
      grandPickup += pickup;
    }
  }

  final List<ItemCirculation> items = <ItemCirculation>[];
  for (final String label in order) {
    items.add(ItemCirculation(
      itemName: label,
      totalDrop: dropTotals[label]!,
      totalPickup: pickupTotals[label]!,
    ));
  }
  return CirculationResult(
    items: items,
    grandDrop: grandDrop,
    grandPickup: grandPickup,
  );
}

// ---- Item detail FK resolution (P6 custodyCountList) ---------------------

/// Detail fields for a single item, resolved from the item collection.
class ItemDetail {
  /// Item display name (field `in`).
  final String name;

  /// Item category (field `ic`, e.g. "returnable" / "consumable").
  final String category;

  const ItemDetail({required this.name, required this.category});
}

/// Build a `Map<String, ItemDetail>` mapping item-id -> ItemDetail from a
/// list of item-collection docs.
///
/// Extends [buildItemNameMap] with the category field needed by
/// custodyCountList's filter. Both the name and category are resolved from
/// the same item doc.
///
/// [itemDocs] -- docs from `mapTableContent[itemCode]` (the item
///   subcollection). Each doc is expected to have [idField] (default `ii`),
///   [nameField] (default `in`), and [categoryField] (default `ic`).
///
/// Convention #7: itemDocs originate from firestoreDb (dynamic); each doc is
/// `Map<String, dynamic>`. Field reads use `.toString().trim()` to handle
/// null / non-string gracefully. Entries with empty `ii` are skipped.
///
/// Returns an explicitly typed `Map<String, ItemDetail>` (never a dynamic map).
Map<String, ItemDetail> buildItemDetailMap(
  List<Map<String, dynamic>> itemDocs, {
  String idField = 'ii',
  String nameField = 'in',
  String categoryField = 'ic',
}) {
  final Map<String, ItemDetail> map = <String, ItemDetail>{};
  for (final Map<String, dynamic> doc in itemDocs) {
    final String id = (doc[idField] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final String name = (doc[nameField] ?? '').toString().trim();
    final String category = (doc[categoryField] ?? '').toString().trim();
    map[id] = ItemDetail(name: name, category: category);
  }
  return map;
}

// ─── Custody count entry (reactive store payload) ──────────────────────────

/// One entry in the custody count store: item id + condition + driver qty.
///
/// Stored in [CustodyCountList.countStore] keyed by `ii__cd`. Carries the
/// full tuple so the submit button can rebuild `ip[]` without splitting the
/// composite key (an `ii` value could contain `__`).
class CountEntry {
  final String ii;
  final String cd;
  int qty;

  CountEntry({required this.ii, required this.cd, this.qty = 0});

  /// Build the Firestore-ready map for one ip[] element.
  Map<String, dynamic> toIpMap() => {'ii': ii, 'cd': cd, 'qt': qty};
}

// ─── Native Firestore write (bypasses history queue) ───────────────────────

/// Write a patch map natively to a Firestore document found by search clauses.
///
/// Mirrors [writeUpdateEventRow] (table_repository.dart:1495-1581) but operates
/// on driver-domain tables and bypasses the offline history queue. The Firestore
/// SDK's own offline persistence handles connectivity.
///
/// Pipeline:
///   1. Build collection path from [rawTable] (e.g. `84214220504259//vehicle_check`).
///   2. Decode + resolve curly tokens in [rawSearch].
///   3. Split search into AND clauses, apply as `.where()` calls.
///   4. Uniqueness guard: 0 matches -> false; >1 matches -> false (with errorReport).
///   5. `docs.first.reference.set(patch, SetOptions(merge: true))`.
///
/// [component] -- the widget's component map (for `resolveAppVid`).
/// [rawTable] -- e.g. `84214220504259//vehicle_check`.
/// [rawSearch] -- e.g. `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}`.
/// [scrName] -- screen name for token resolution context.
/// [patch] -- the fields to merge (e.g. `{'ip': [...]}` or `{'rs': 'matched'}`).
///
/// Returns `true` on success, `false` on failure (caller shows snackbar).
Future<bool> writeNativeFields({
  required dynamic component,
  required String rawTable,
  required String rawSearch,
  required String scrName,
  required Map<String, dynamic> patch,
}) async {
  try {
    // 1. Build collection path
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty || tp.subColl.isEmpty) {
      devPrint('[writeNativeFields] bad table path: $rawTable');
      return false;
    }
    final String appVid = resolveAppVid(component);
    final String path =
        '$mobileTable/$appVid/$mobileTableCollection/${tp.tableDocId}/${tp.subColl}';

    // 2. Decode + resolve tokens in search
    final String decoded = autheniumDecode(rawSearch) ?? rawSearch;
    final String driverResolved = resolveDriverCurlyTokens(decoded, scrName);
    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String fullyResolved = resolveScreenTxTokens(driverResolved, screenTx);

    // 3. Parse search clauses and build Firestore query
    if (fullyResolved.trim().isEmpty) {
      devPrint('[writeNativeFields] empty search after resolve');
      return false;
    }
    final List<String> clauses = fullyResolved.split('\u{2B58}');
    dynamic query = firestoreDb.collection(path);
    for (final clause in clauses) {
      final String trimmed = clause.trim();
      if (trimmed.isEmpty) continue;
      final int sep = trimmed.indexOf('\u{25FC}');
      if (sep < 0) continue;
      final String field = trimmed.substring(0, sep).trim();
      final String rawValue = trimmed.substring(sep + 1).trim();
      if (field.isEmpty || rawValue.isEmpty || rawValue.contains('{')) {
        devPrint('[writeNativeFields] unresolved token in search: $rawValue');
        return false;
      }
      // Type-coerce: num / bool / string (matches _parseSearchValue pattern)
      dynamic typedValue;
      final String lower = rawValue.toLowerCase();
      if (lower == 'true') {
        typedValue = true;
      } else if (lower == 'false') {
        typedValue = false;
      } else {
        typedValue = num.tryParse(rawValue) ?? rawValue;
      }
      query = query.where(field, isEqualTo: typedValue);
    }

    // 4. Execute query + uniqueness guard
    final snap = await query.get();
    final docs = snap.docs;
    if (docs.isEmpty) {
      devPrint('[writeNativeFields] 0 matches at $path; cannot write');
      return false;
    }
    if (docs.length > 1) {
      errorReport('[writeNativeFields] ${docs.length} matches at $path; '
          'refusing to write (corrupt uniqueness)');
      return false;
    }

    // 5. Set-merge
    await docs.first.reference.set(patch, SetOptions(merge: true));
    devPrint('[writeNativeFields] merged $patch into $path/${docs.first.id}');
    return true;
  } catch (e, st) {
    devPrint('[writeNativeFields] error: $e\n$st');
    errorReport('[writeNativeFields] $e');
    return false;
  }
}

// ─── Route token stripping ─────────────────────────────────────────────────

/// Strip the `[ROUTE:xxx]` wrapper if present, returning the bare route name.
///
/// The server JSON uses `[ROUTE:custodySuccess]` as a notation; the server
/// resolves it to the tenant-prefixed page name before the app receives it.
/// But as a safety measure, the widget strips the wrapper if it arrives
/// unresolved. This is safe regardless of whether stripping was needed.
///
/// Examples:
///   `[ROUTE:custodySuccess]` -> `custodySuccess`
///   `vertikaTeknoLokaciptaCustodyReveal` -> `vertikaTeknoLokaciptaCustodyReveal`
///   `` -> ``
String stripRouteWrapper(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.startsWith('[ROUTE:') && trimmed.endsWith(']')) {
    return trimmed.substring(7, trimmed.length - 1).trim();
  }
  return trimmed;
}

// -- Status exclusion filter (shared by DRIVER_STOP_CARD + future widgets) ---

/// Filter out docs whose raw status field matches [excludeStatus].
///
/// Opt-in: when [excludeStatus] is empty, returns [docs] unchanged (no
/// exclusion). This preserves backward compatibility for components that do
/// not set the field.
///
/// Compares the RAW field value (default `tst`), NOT the normalized
/// `stopStatusOf` result. `load_rejected` normalizes to `pending` via
/// `stopStatusOf`, but must be excluded by its raw value. This mirrors the
/// exclude logic in `aggregateManifestItems` (driver_home_support.dart:672).
///
/// [docs] -- task docs from `mapTableContent` (already filtered by search).
/// [excludeStatus] -- the raw status value to exclude (e.g. `load_rejected`).
///   Empty string = exclude nothing.
/// [statusField] -- the doc field to compare (default `tst`).
///
/// Convention #7: docs are `Map<String, dynamic>` from Firestore; field reads
/// use `(doc[field] ?? '').toString().trim()` to handle null / non-string.
List<Map<String, dynamic>> excludeByStatus(
  List<Map<String, dynamic>> docs,
  String excludeStatus, {
  String statusField = 'tst',
}) {
  if (excludeStatus.isEmpty) return docs;
  return docs
      .where((doc) =>
          (doc[statusField] ?? '').toString().trim() != excludeStatus)
      .toList();
}
