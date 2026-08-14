import 'dart:async'; // unawaited

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart'; // WidgetsBinding (deferred publish)
import 'package:get/get.dart';

import '../api.dart'; // getTableVid
import '../global.dart';
import '../redux/screen_transaction.dart';
import '../screen_session.dart';
import 'dsl_eq.dart';
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
  /// Reactive so the card scope-gates (read inside Obx) rebuild deterministically
  /// when the stock_location subscription resolves for an unassigned driver.
  final RxBool vehicleIdResolved = false.obs;

  /// Driver display name (workforce doc field `n`, published by the header).
  /// Used by `resolveDriverCurlyTokens` for `{driverName}` token.
  final RxString driverName = ''.obs;

  /// Active trip doc-id: Firestore doc-id of the newest non-closed
  /// vehicle_check opening for this vehicle. Published by
  /// [resolveAndPublishActiveTrip] (called from evaluateGateSearch as a
  /// side-effect). Used by `resolveDriverCurlyTokens` for `{activeTrip}` token.
  /// Empty when no active trip exists — fail-closed (pending-safe).
  final RxString activeTrip = ''.obs;
}

/// Per-scrName state map. Accessed by header, gate card, TXT label, and
/// Phase 2 widgets. Cleared in buildPage(clear:true).
final Map<String, DriverHomeState> driverHomeStates = {};

/// Obtain or create the DriverHomeState for a screen.
DriverHomeState getDriverHomeState(String scrName) {
  registerDriverHomeScreenSession();
  return driverHomeStates.putIfAbsent(scrName, () => DriverHomeState());
}

void registerDriverHomeScreenSession() {
  ScreenSession.ensure(
    'DriverHomeState',
    clearDriverHomeState,
    nav: NavPolicy.none,
  );
}

/// Clear state for a screen. Called from buildPage alongside
/// ApproverStickyBar.clearConfigs.
void clearDriverHomeState(String scrName) {
  driverHomeStates.remove(scrName);
}

/// `cst` values that END a trip: an opening doc in one of these anchors no
/// live trip.
///
/// `closed` = C1 closing done. `cancelled` = trip abandoned — written
/// CONFIG-side (the ad-hoc driver flow), never by Dart, and absent from the
/// field dictionary, which is why every "is this trip live" check used to
/// compare against `'closed'` alone. Prod consequence (otq-01, MBL-01
/// 2026-08-05): an abandoned `CHK-MBL-01-20260805-3` with an empty `ie[]`
/// out-ranked the real newest trip and became the "active" trip for every
/// read path once that trip closed.
bool isTripTerminalCst(Object? cst) {
  final String s = (cst ?? '').toString().trim();
  return s == 'closed' || s == 'cancelled';
}

/// Pick the active (newest non-terminal) opening from a list of docs.
///
/// Filters for `cty == 'opening'`, sorts by `t` desc, and prefers the newest
/// doc whose `cst` is not trip-terminal ([isTripTerminalCst]). Falls back to
/// the newest opening overall when every opening is closed/cancelled. Returns
/// `null` when the input contains no opening-shaped docs.
///
/// Shared by [resolveAndPublishActiveTrip] (driver pages) and
/// `_findCheckDoc` in custody_count_list / custody_reveal (P6/P7).
Map<String, dynamic>? pickActiveOpening(List<Map<String, dynamic>> docs) {
  final List<Map<String, dynamic>> openings = <Map<String, dynamic>>[];
  for (final doc in docs) {
    if ((doc['cty'] ?? '').toString().trim() == 'opening') {
      openings.add(doc);
    }
  }
  if (openings.isEmpty) return null;
  // Sort by t descending (newest first)
  openings.sort((a, b) {
    final int tA = int.tryParse((a['t'] ?? '0').toString().trim()) ?? 0;
    final int tB = int.tryParse((b['t'] ?? '0').toString().trim()) ?? 0;
    return tB.compareTo(tA);
  });
  // Prefer newest non-terminal
  for (final doc in openings) {
    if (!isTripTerminalCst(doc['cst'])) return doc;
  }
  // All closed/cancelled: return newest overall
  return openings.first;
}

/// Pick the doc with the largest `t` (newest write timestamp).
///
/// Single-pass, first-max-wins: strict `>` means when all docs share the same
/// `t` (or none has `t` at all), the first element wins — identical to what
/// `matched.first` returned before this helper existed. That is the
/// zero-regression guarantee.
///
/// `t` is parsed tolerantly (int or String) — same idiom as [pickActiveOpening].
/// Unlike [pickActiveOpening] — whose `cty == 'opening'` filter drops closing
/// docs (they are not opening-shaped) and returns null — this reads any doc
/// shape, which is why the ClosingMatch list can only be fixed here.
/// Returns null on an empty list.
Map<String, dynamic>? pickNewestDoc(List<Map<String, dynamic>> docs) {
  Map<String, dynamic>? best;
  int bestT = -1;
  for (final d in docs) {
    final int t = int.tryParse((d['t'] ?? '0').toString().trim()) ?? 0;
    if (t > bestT) {
      bestT = t;
      best = d;
    }
  }
  return best;
}

/// Compute the active trip doc-id from a list of vehicle_check docs.
///
/// Returns:
/// - `null` when [docs] contains zero `cty=='opening'` entries (no openings;
///   the caller should not treat this as definitive -- another table key may
///   contain the openings).
/// - `''` when openings exist but none are active for [vehicleId] (all
///   `cst=='closed'` or no vv match) -- a legitimate fail-closed result.
/// - A non-empty doc-id string when an active (non-closed) opening is found
///   for [vehicleId].
///
/// Pure -- no Flutter/Obx/WidgetsBinding deps. Shared by
/// [resolveAndPublishActiveTrip] and the compute-on-read fallback in
/// [resolveDriverCurlyTokens]. Uses [eq] for type-tolerant vv comparison
/// (Number vs String) and [pickActiveOpening] for deterministic multi-opening
/// selection.
String? computeActiveTripDocId(
  List<Map<String, dynamic>> docs,
  String vehicleId,
) {
  if (vehicleId.isEmpty) return null;

  // Gate: only return a definitive answer when docs contain opening-shaped
  // entries. Zero openings means this table is not vehicle_check (or data
  // hasn't loaded) -- return null so the caller can try the next key.
  bool hasAnyOpening = false;
  for (final doc in docs) {
    if ((doc['cty'] ?? '').toString().trim() == 'opening') {
      hasAnyOpening = true;
      break;
    }
  }
  if (!hasAnyOpening) return null;

  // Filter to this vehicle's docs.
  final List<Map<String, dynamic>> vvDocs = <Map<String, dynamic>>[];
  for (final doc in docs) {
    if (eq((doc['vv'] ?? '').toString().trim(), vehicleId)) {
      vvDocs.add(doc);
    }
  }

  final Map<String, dynamic>? picked = pickActiveOpening(vvDocs);
  // If picked is non-null but closed/cancelled, treat as no active trip.
  if (picked != null && !isTripTerminalCst(picked['cst'])) {
    return (picked['__docId'] ?? '').toString();
  }
  return ''; // openings exist but none active for this vehicle
}

/// Schedule a deferred publish of [docId] into
/// [DriverHomeState.activeTrip] for [scrName].
///
/// Mirrors the deferred pattern in [resolveAndPublishActiveTrip]: guards
/// against same-value no-op and re-reads state inside the callback (route
/// change may have cleared it). Used by both [resolveAndPublishActiveTrip]
/// and the compute-on-read fallback in [resolveDriverCurlyTokens].
void _deferActiveTripPublish(String scrName, String docId) {
  final DriverHomeState state = getDriverHomeState(scrName);
  if (state.activeTrip.value == docId) return; // already current
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final DriverHomeState? s = driverHomeStates[scrName];
    if (s == null) return; // route changed, state cleared
    if (s.activeTrip.value != docId) {
      s.activeTrip.value = docId;
    }
  });
}

/// Resolve the active trip doc-id from vehicle_check data in mapTableContent.
///
/// Delegates to [computeActiveTripDocId] for the pure compute (vv-filter via
/// [eq], [pickActiveOpening], cst!='closed' -> docId). Publishes the result
/// into [DriverHomeState.activeTrip] via [_deferActiveTripPublish].
///
/// Called as a side-effect from [evaluateGateSearch] and from
/// [VehicleCustodyHeader.build] (P5). Publish is deferred via
/// [WidgetsBinding.instance.addPostFrameCallback] to avoid setState-during-build.
///
/// Gate: when [computeActiveTripDocId] returns null (no opening-shaped docs),
/// returns without publishing -- preserves current activeTrip to avoid
/// clobbering from a sibling widget whose gateCode targets a different table.
void resolveAndPublishActiveTrip(String scrName, String checkCode) {
  if (checkCode.isEmpty) return;
  final DriverHomeState state = getDriverHomeState(scrName);
  final String vehicleId = state.vehicleId.value;
  if (vehicleId.isEmpty) return;

  final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
    mapTableContent[checkCode] ?? const [],
  );

  final String? result = computeActiveTripDocId(docs, vehicleId);
  if (result == null) return; // no openings -> preserve current activeTrip

  _deferActiveTripPublish(scrName, result);
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

/// Session VID for log-only use. Same `screenTx['#VID']` that
/// [resolveDriverCurlyTokens] resolves `{userVid}` from — NOT a permission input.
String sessionVidForLog() =>
    (transactionStore.state.screenTx['#VID'] ?? '').toString();

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
///   {checkerVid}    -> screenTx['#VID'] (logged-in checker VID from main auth)
///   {userVid}       -> screenTx['#VID'] (logged-in user VID; role-agnostic)
///   {userName}      -> screenTx['#NAME'] (logged-in user display name; role-agnostic)
///   {activeVehicle}  -> screenTx['#ACTIVE_VEHICLE'] (tapped vehicle lv from H1)
///   {chosenVid}     -> screenTx['#CHOSEN_DRIVER_VID'] (driver chosen on O1)
///   {chosenName}    -> screenTx['#CHOSEN_DRIVER_NAME'] (driver name chosen on O1)
///   {warehouseId}   -> screenTx['#ACTIVE_WAREHOUSE'] (gudang from task gl)
///   {activeTrip}   -> DriverHomeState.activeTrip (active vehicle_check opening doc-id)
///   {now}           -> getNowMillisecondFromEpoch().toString() (epoch-ms now)
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

  return raw.replaceAllMapped(RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'), (
    Match m,
  ) {
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
      case 'checkerVid':
        final String v = (screenTx['#VID'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'userVid':
        final String v = (screenTx['#VID'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'userName':
        final String v = (screenTx['#NAME'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'activeVehicle':
        final String v = (screenTx['#ACTIVE_VEHICLE'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'chosenVid':
        final String v = (screenTx['#CHOSEN_DRIVER_VID'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'chosenName':
        final String v = (screenTx['#CHOSEN_DRIVER_NAME'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'warehouseId':
        final String v = (screenTx['#ACTIVE_WAREHOUSE'] ?? '').toString();
        return v.isNotEmpty ? v : m.group(0)!;
      case 'activeTrip':
        final String vid = state.vehicleId.value;
        if (vid.isEmpty) {
          // No vehicle context — use cached value if available.
          final String cached = state.activeTrip.value;
          return cached.isNotEmpty ? cached : m.group(0)!;
        }
        // Vehicle known: compute from vehicle_check data (authoritative).
        // Does NOT trust the cached activeTrip blindly; the cache may
        // hold a stale trip from a previous vehicle or a closed trip.
        for (final String key in mapTableContent.keys) {
          if (!key.endsWith('/vehicle_check')) continue;
          final List<Map<String, dynamic>> checkDocs =
              List<Map<String, dynamic>>.from(mapTableContent[key] ?? const []);
          final String? result = computeActiveTripDocId(checkDocs, vid);
          if (result == null) continue; // no openings in this key
          if (result.isNotEmpty) {
            // Schedule deferred publish so state converges for Obx
            // consumers that touch activeTrip.
            _deferActiveTripPublish(scrName, result);
            return result;
          }
          // result == '' -> openings exist but none active -> fail-closed
          return m.group(0)!;
        }
        // Compute inconclusive (no vehicle_check data loaded) —
        // fall back to cached value.
        final String v = state.activeTrip.value;
        return v.isNotEmpty ? v : m.group(0)!;
      case 'now':
        return getNowMillisecondFromEpoch().toString();
      case 'today':
        return todayEpochMidnightWib();
      default:
        // routeParams fallback: resolve from bare screenTx key if present
        // and non-empty. Otherwise leave literal for resolveScreenTxTokens.
        // Reserved tokens (vehicleId, driverName, tnm, today, driverVid,
        // activeTaskVid, rejectTaskVid, checkerVid, userVid, userName,
        // activeVehicle, chosenVid, chosenName, warehouseId, activeTrip, now)
        // are handled by switch cases above and never reach here.
        final String bareVal = (screenTx[name] ?? '').toString();
        return bareVal.isNotEmpty ? bareVal : m.group(0)!;
    }
  });
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

/// Resolve `{field}` curly tokens against a row's named-field Map.
///
/// Tokens whose name matches a non-empty key in [rowFields] are replaced with
/// the stringified value. Tokens with no match (or empty value) are left as-is
/// so the caller can fall back to [resolveDriverCurlyTokens] for session tokens
/// like `{today}` or `{driverVid}`.
///
/// Pure function, no side effects. Safe to call with an empty map (returns
/// [raw] unchanged). Uses the same single-brace regex as
/// [resolveDriverCurlyTokens] -- `{{POS(0)}}` double-brace is NOT matched.
String resolveRowCurlyTokens(String raw, Map<String, dynamic> rowFields) {
  if (!raw.contains('{') || rowFields.isEmpty) return raw;
  return raw.replaceAllMapped(RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'), (
    Match m,
  ) {
    final String name = m.group(1)!;
    final dynamic val = rowFields[name];
    if (val == null) return m.group(0)!; // leave for session fallback
    final String s = val.toString().trim();
    return s.isNotEmpty ? s : m.group(0)!; // empty = leave for fallback
  });
}

/// Resolve routeParams with row-context-first resolution, then dispatch as
/// bare screenTx keys. Designed for list/picker row taps where the tapped row
/// provides named fields (e.g. `{lv}` -> `row['lv']`).
///
/// Pipeline:
///   1. Null/empty [rawDsl] OR null [row] -> return (no-op). Null row is the
///      adhoc-row case in PickerList -- no doc fields to resolve from.
///   2. autheniumDecode the raw DSL (server encodes U+25FC/U+2B58 as
///      _25FC_/_2B58_).
///   3. parseRouteParams -> list of key/rawValue pairs (REUSED, not reinvented).
///   4. For each value:
///      a. Resolve `{field}` from [row] via [resolveRowCurlyTokens].
///      b. If still contains `{`, resolve via [resolveDriverCurlyTokens]
///         (session/driver tokens like {vehicleId}, {today}).
///   5. Dispatch resolved non-empty pairs as bare screenTx keys.
///
/// Skips pairs whose resolved value is empty or still contains an unresolved
/// `{` (pending-safe, same contract as [writeRouteParams]).
///
/// [rawDsl]  -- raw `component['routeParams']` string.
/// [row]     -- the tapped row's named-field Map (nullable for adhoc rows).
/// [scrName] -- screen name for [resolveDriverCurlyTokens] context.
void writeRouteParamsFromRow(
  String? rawDsl,
  Map<String, dynamic>? row,
  String scrName,
) {
  if (rawDsl == null || rawDsl.trim().isEmpty) return;
  if (row == null) return;
  final String decoded = autheniumDecode(rawDsl) ?? rawDsl;
  final List<MapEntry<String, String>> pairs = parseRouteParams(decoded);
  if (pairs.isEmpty) return;

  final Map<String, dynamic> toDispatch = {};
  for (final pair in pairs) {
    // Step a: resolve from row fields first.
    String resolved = resolveRowCurlyTokens(pair.value, row);
    // Step b: fallback to session/driver tokens for anything still unresolved.
    if (resolved.contains('{')) {
      resolved = resolveDriverCurlyTokens(resolved, scrName);
    }
    // Skip empty or still-unresolved.
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
///
/// ## Two-evaluator contract (spec S3-A)
///
/// This function implements **case 1: fail-closed on empty value**.
/// A literal-empty clause value here means "an unresolved token" -- NOT
/// "match docs whose field is empty". For case 2 (literal-empty = match
/// docs with an empty field), see `evaluateGate` in `admin_home_support.dart`.
///
/// Why case 1 can never accidentally match-empty:
/// [resolveDriverCurlyTokens] and [resolveScreenTxTokens] both leave the
/// `{token}` LITERAL when the underlying value is empty, so the
/// `value.contains('{')` guard below fires first. An empty value without
/// a `{` can only appear if someone writes a literal-empty clause in the
/// SDUI config and routes it through [filterDriverHomeDocs] -- which no
/// live config does. If a builder does this, the result is a silent zero
/// (fail-closed), not a match-empty. That is documented behavior, not a bug.
///
/// Live configs that need match-empty semantics (e.g. `noExecutorGate`
/// `lt◼vehicle⭘dv◼`, vehiclePicker `search` `lt◼vehicle⭘lst◼active⭘dv◼`)
/// route through `evaluateGate` instead.
///
/// **FAIL-CLOSED CONTRACT (scope-leak prevention):**
/// If ANY clause has an empty resolved value (null, `""`, or whitespace-only
/// per [isTokenEmpty]) OR still contains an unresolved `{key}` token, the
/// ENTIRE query returns an empty list -- "match nothing", NOT "drop the
/// clause". This prevents data leaks when a scope token like `{vehicleId}`
/// resolves empty: the remaining clauses (e.g. `tdt◼{today}`) must NOT run
/// unscoped.
///
/// [docs] -- the Firestore map docs to filter.
/// [resolvedConditions] -- the conditions string AFTER autheniumDecode + token
///   resolution (already contains literal `◼` and `⭘` chars).
///
/// Returns matching docs, or empty list if no match or unresolvable/empty token.
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
    if (sep < 0) continue; // malformed clause -- skip
    final String field = trimmed.substring(0, sep).trim();
    final String value = trimmed.substring(sep + 1).trim();
    if (field.isEmpty) continue;
    // FAIL-CLOSED: empty resolved value OR unresolved {token} -> match nothing.
    // "Empty" covers null, "", and whitespace-only (isTokenEmpty).
    // This is the primary defense against scope leaks from empty tokens.
    if (isTokenEmpty(value) || value.contains('{')) {
      // ponytail: growable (NOT const []) — callers .sort() this result
      return <Map<String, dynamic>>[];
    }
    pairs.add(MapEntry(field, value));
  }

  if (pairs.isEmpty) return docs;

  // AND: doc must match ALL clauses
  return docs.where((doc) {
    for (final pair in pairs) {
      if (!eq((doc[pair.key] ?? '').toString().trim(), pair.value))
        return false;
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
bool evaluateGateSearch(String gateCode, String rawGateSearch, String scrName) {
  if (gateCode.isEmpty) return false;
  if (rawGateSearch.trim().isEmpty) return false;
  final List<Map<String, dynamic>> gateDocs = List<Map<String, dynamic>>.from(
    mapTableContent[gateCode] ?? const [],
  );
  // Side-effect: attempt activeTrip resolution from the gate docs.
  // Skips publish when docs contain zero cty=='opening' entries (gate targets
  // a non-vehicle_check table, or subscription not loaded). When openings ARE
  // present but none active for this vv, publishes '' (legitimate all-closed
  // clear). Publish is deferred via addPostFrameCallback (Task 3c).
  // Cost: one in-memory scan, no I/O.
  resolveAndPublishActiveTrip(scrName, gateCode);
  final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
    gateDocs,
    rawGateSearch,
    scrName,
  );
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

/// Build a `Map<String, String>` mapping item-id -> unit/satuan (`un`) from a
/// list of item-collection docs.
///
/// Sibling of [buildItemNameMap]: same shape and conventions, but resolves the
/// unit field (`un`, e.g. "Tabung"/"Galon"/"Karton") instead of the name. Used
/// by P12 vehicleCargoSummary to prefix each condition row ("{un} isi {qty}")
/// per spec §2 — replacing the hardcoded "Tabung" label so galon/karton items
/// are labelled correctly.
///
/// Convention #7: itemDocs originate from firestoreDb (dynamic); each doc is
/// `Map<String, dynamic>`. Field reads use `.toString().trim()` to handle
/// null / non-string gracefully. Entries with empty `ii` are skipped; a doc
/// with no `un` maps to `''` (degrades to a bare condition label downstream).
///
/// Returns an explicitly typed `Map<String, String>` (never a dynamic map).
Map<String, String> buildItemUnitMap(
  List<Map<String, dynamic>> itemDocs, {
  String idField = 'ii',
  String unitField = 'un',
}) {
  final Map<String, String> map = <String, String>{};
  for (final Map<String, dynamic> doc in itemDocs) {
    final String id = (doc[idField] ?? '').toString().trim();
    if (id.isEmpty) continue;
    map[id] = (doc[unitField] ?? '').toString().trim();
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

  /// Resolved unit / satuan (item master `un`, e.g. "Tabung"/"Galon"/
  /// "Karton"), or `''` when the item master has no `un` for it. Rendered as
  /// the per-condition prefix in P12 ("{unit} isi {qty}"); blank degrades to a
  /// bare "isi {qty}". Defaults to `''` so callers that do not resolve units
  /// (and existing tests) keep working unchanged.
  final String unit;

  /// Summed quantity for the `full` condition (0 when absent).
  final int fullQty;

  /// Summed quantity for the `empty` condition (0 when absent).
  final int emptyQty;

  const CargoItemRow({
    required this.itemId,
    required this.displayName,
    this.unit = '',
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
  Map<String, String> itemUnitMap = const <String, String>{},
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
    final String cond = (doc[conditionField] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final int qty = int.tryParse((doc[qtyField] ?? '0').toString().trim()) ?? 0;
    final Map<String, int> bucket = grouped.putIfAbsent(
      itemId,
      () => <String, int>{},
    );
    bucket[cond] = (bucket[cond] ?? 0) + qty;
  }

  // Sort by resolved name ascending, tiebreak by raw ii.
  final List<String> sortedIds = seen.toList()
    ..sort((a, b) {
      final String nameA = itemNameMap[a]?.isNotEmpty == true
          ? itemNameMap[a]!
          : a;
      final String nameB = itemNameMap[b]?.isNotEmpty == true
          ? itemNameMap[b]!
          : b;
      final int cmp = nameA.compareTo(nameB);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

  final List<CargoItemRow> rows = <CargoItemRow>[];
  for (final String itemId in sortedIds) {
    final String displayName = itemNameMap[itemId]?.isNotEmpty == true
        ? itemNameMap[itemId]!
        : itemId;
    // Unit / satuan (item master `un`) for the per-condition prefix. Absent
    // entry -> '' (degrades to a bare condition label). itemUnitMap defaults
    // empty, so callers that do not resolve units get '' for every row.
    final String unit = (itemUnitMap[itemId] ?? '').trim();
    rows.add(
      CargoItemRow(
        itemId: itemId,
        displayName: displayName,
        unit: unit,
        fullQty: grouped[itemId]?[conditionFull] ?? 0,
        emptyQty: grouped[itemId]?[conditionEmpty] ?? 0,
      ),
    );
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

// ─── hideZero flag read (shared) ────────────────────────────────────────────

/// True when [component]'s `hideZero` config equals the string "TRUE"
/// (case/space-insensitive). The server sends String "TRUE", never bool `true`
/// — a `== true` / bool-parse check never fires (spec §4 Q2). Single read used
/// by INVENTORY_BUCKET_CARD, ITEM_EXECUTION_LIST pivot, PRECONDITION_GATE_CARD.
bool hideZeroEnabled(dynamic component) {
  if (component is! Map) return false; // server JSON is dynamic (convention #7)
  return (component['hideZero'] ?? '').toString().trim().toUpperCase() ==
      'TRUE';
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
    out.add(<String, dynamic>{labelField: label, qtyField: totals[label]});
  }
  return out;
}

/// Numeric coercion for Firestore dynamic fields: handles int, double, String,
/// null. Returns the numeric value or 0. Public so custody_count_list can
/// reuse it (was file-private _coerceNum; renamed to avoid duplication).
num coerceNum(dynamic v) {
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
/// Convention #7: dynamic guards throughout (is List, is Map, coerceNum).
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
      final int lineQty =
          (coerceNum(entry[deliverField]) +
                  coerceNum(entry[saleField]) +
                  coerceNum(entry[refillField]))
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
    out.add(<String, dynamic>{labelField: label, deliverField: total});
  }
  return out;
}

/// Aggregate a vehicle_check `ie[]` array into display rows for the
/// pending-card item list.
///
/// The `ie` array on an opening doc records the manifest per item/condition:
/// each entry is `{ii: <item-id>, cd: <condition>, qt: <qty>}`. This groups
/// by [idField] (default `ii`), SUMS [qtyField] (default `qt`) across ALL
/// `cd` values (full + empty = total per item), resolves `ii` -> item name
/// via [nameMap] (built by `buildItemNameMap`), and returns one row per
/// distinct item in first-seen order.
///
/// Output rows are shaped `{<labelField>: name, <qtyField>: total}` so the
/// pending-card render (which reads `row[labelField]` / `row[qtyField]`)
/// works unchanged.
///
/// [ieArray] -- the raw `ie` field from the opening doc (dynamic from
///   Firestore). Must be a List; non-List returns empty.
/// [nameMap] -- item-id -> display name map (from `buildItemNameMap`).
///   Unknown ids fall back to the raw id string.
/// [idField] -- key for item id in each ie entry (default `ii`).
/// [qtyField] -- key for quantity in each ie entry AND the output row key
///   (default `qt`). This MUST match the resolved `component['qtyField']` so
///   the render loop reads the correct key.
/// [labelField] -- key for the output row's name (default `in`). This MUST
///   match the resolved `component['labelField']`.
/// [hideZero] -- when true, drop items whose summed total is 0.
///
/// Convention #7: `ieArray` is `dynamic` from Firestore. Guarded: `is List`,
/// each entry `is Map`, qt via `int.tryParse(...) ?? 0`. Returns an
/// explicitly typed `List<Map<String, dynamic>>`.
List<Map<String, dynamic>> aggregateManifestFromIe(
  dynamic ieArray,
  Map<String, String> nameMap, {
  String idField = 'ii',
  String qtyField = 'qt',
  String labelField = 'in',
  bool hideZero = false,
}) {
  if (ieArray is! List) return const [];

  // Preserve first-seen order: ordered list of ids + an id->totalQty map.
  final List<String> order = <String>[];
  final Map<String, int> totals = <String, int>{};

  for (final dynamic entry in ieArray) {
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

  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final String id in order) {
    final int total = totals[id]!;
    if (hideZero && total == 0) continue;
    final String name = nameMap[id]?.isNotEmpty == true ? nameMap[id]! : id;
    out.add(<String, dynamic>{labelField: name, qtyField: total});
  }
  return out;
}

/// Aggregate plan qty per item-id across task docs.
///
/// O1 count-list source: walks each task's [itemsField] array, sums
/// [deliverField]+[saleField]+[refillField] per distinct `ii` (item id).
/// Excludes tasks whose `tst` matches [excludeStatus].
///
/// Returns a [PlanAggregate] with ii-order list and per-ii totals.
/// Pure -- no Flutter/Obx deps, directly testable.
///
/// Convention #7: dynamic guards throughout (is List, is Map, coerceNum).
PlanAggregate aggregatePlanByItem(
  List<Map<String, dynamic>> taskDocs, {
  required String itemsField,
  required String deliverField,
  required String saleField,
  required String refillField,
  String excludeStatus = '',
}) {
  final List<String> iiOrder = <String>[];
  final Map<String, int> totals = <String, int>{};

  for (final Map<String, dynamic> doc in taskDocs) {
    if (excludeStatus.isNotEmpty) {
      final String tst = (doc['tst'] ?? '').toString().trim();
      if (tst == excludeStatus) continue;
    }
    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue;
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      final String ii = (entry['ii'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      final int lineQty =
          (coerceNum(entry[deliverField]) +
                  coerceNum(entry[saleField]) +
                  coerceNum(entry[refillField]))
              .toInt();
      if (!totals.containsKey(ii)) {
        iiOrder.add(ii);
        totals[ii] = 0;
      }
      totals[ii] = totals[ii]! + lineQty;
    }
  }
  return PlanAggregate(iiOrder: iiOrder, totals: totals);
}

/// Result of [aggregatePlanByItem]: per-item-id plan totals in first-seen order.
class PlanAggregate {
  /// Item ids in first-seen order.
  final List<String> iiOrder;

  /// Summed plan qty per item id.
  final Map<String, int> totals;
  const PlanAggregate({required this.iiOrder, required this.totals});
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

/// Strict truthy whitelist for SDUI toggle keys (D-D).
///
/// [SduiSpec] has no bool accessor; [SduiSpec.has] only tests non-empty, so
/// `groupByItem: FALSE` would switch grouping ON. Accept only these values
/// (case-insensitive, trimmed); everything else is OFF.
bool sduiBool(String value) {
  const Set<String> truthy = <String>{'true', '1', 'yes', 'ya'};
  return truthy.contains(value.trim().toLowerCase());
}

/// Parse a `condLabels` config string into a `{rawCd: displayLabel}` map.
///
/// Format: `full◼Penuh⭘empty◼Kosong` -- entries separated by `⭘` (U+2B58),
/// each entry is `rawCdValue◼displayLabel` (U+25FC). Reuses [parseBuckets]
/// which parses the identical `⭘`/`◼` format into `List<BucketDef>`.
///
/// **`'ok'` filter (W2):** [parseBuckets] substitutes `'ok'` when the second
/// segment is empty (its domain is `inventoryBucketCard` visual variants).
/// A label map must not leak that vocabulary: `condLabels: "full◼⭘…"` should
/// fall back to the raw `cd` (`full`), not display `ok`. Pairs whose
/// `BucketDef.status` is `'ok'` are therefore **skipped** here -- the caller's
/// `condLabels[cd] ?? cd` produces the honest raw value instead. A builder who
/// genuinely wants the literal label `'ok'` can write `full◼ok` and
/// `parseBuckets` returns it with `status.isEmpty == false`, but since we
/// cannot distinguish that case from the default, `'ok'` as a display label
/// is unsupported. This is documented in section 8 Open Risks.
///
/// Caller MUST pass a string already decoded by [autheniumDecode] (or
/// [SduiSpec.str], which calls it). `_25FC_` (◼) is decoded by
/// `autheniumDecode` (global.dart:1152); `_2B58_` (⭘) is NOT decoded
/// (line 1159 commented out) -- the sheet cell must carry a literal `⭘`,
/// same constraint as `search` and `flowSearch`.
Map<String, String> parseCondLabels(String raw) {
  if (raw.isEmpty) return const <String, String>{};
  final List<BucketDef> buckets = parseBuckets(raw);
  if (buckets.isEmpty) return const <String, String>{};
  final Map<String, String> map = <String, String>{};
  for (final BucketDef b in buckets) {
    // Skip the 'ok' default that parseBuckets substitutes for an empty
    // second segment. A genuine 'ok' label is indistinguishable and
    // therefore unsupported (see doc comment).
    if (b.status == 'ok') continue;
    map[b.label] = b.status;
  }
  return map;
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
bool isStopClosed(String tst) =>
    _closedStatuses.contains(tst.trim().toLowerCase());

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

  /// Sum of sale qty (ps) across all item lines. Zero when not tx-aware.
  final int totalSale;

  /// Sum of buy qty (pb) across all item lines. Zero when not tx-aware.
  final int totalBuy;

  /// Sum of refill qty (pr) across all item lines. Zero when not tx-aware.
  final int totalRefill;

  const TaskAggregate({
    required this.itemLineCount,
    required this.totalDrop,
    required this.totalPickup,
    this.totalSale = 0,
    this.totalBuy = 0,
    this.totalRefill = 0,
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
  String actualDropField = 'ad',
  String actualPickupField = 'ap',
  String txField = '',
  String saleField = '',
  String buyField = '',
  String refillField = '',
  String actualSaleField = 'as',
  String actualBuyField = 'ab',
  String actualRefillField = 'ar',
}) {
  final dynamic rawItems = doc[itemsField];
  if (rawItems is! List) {
    return const TaskAggregate(itemLineCount: 0, totalDrop: 0, totalPickup: 0);
  }
  int lineCount = 0;
  int dropSum = 0;
  int pickupSum = 0;
  int saleSum = 0;
  int buySum = 0;
  int refillSum = 0;
  for (final dynamic entry in rawItems) {
    if (entry is! Map) continue;
    lineCount++;
    if (txField.isNotEmpty) {
      final String tx = (entry[txField] ?? '').toString().trim();
      switch (tx) {
        case 'deliver':
          dropSum += resolveItemQty(entry, dropField, actualDropField);
          pickupSum += resolveItemQty(entry, pickupField, actualPickupField);
          break;
        case 'sale':
          if (saleField.isNotEmpty) {
            saleSum += resolveItemQty(entry, saleField, actualSaleField);
          }
          break;
        case 'purchase':
          if (buyField.isNotEmpty) {
            buySum += resolveItemQty(entry, buyField, actualBuyField);
          }
          break;
        case 'refill':
          if (refillField.isNotEmpty) {
            refillSum += resolveItemQty(entry, refillField, actualRefillField);
          }
          break;
        default:
          // Unknown tx: fall through to drop/pickup (safe default).
          dropSum += resolveItemQty(entry, dropField, actualDropField);
          pickupSum += resolveItemQty(entry, pickupField, actualPickupField);
      }
    } else {
      // Legacy mode: sum all items' drop/pickup.
      dropSum += resolveItemQty(entry, dropField, actualDropField);
      pickupSum += resolveItemQty(entry, pickupField, actualPickupField);
    }
  }
  return TaskAggregate(
    itemLineCount: lineCount,
    totalDrop: dropSum,
    totalPickup: pickupSum,
    totalSale: saleSum,
    totalBuy: buySum,
    totalRefill: refillSum,
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
          int.tryParse((entry[actualPickupField] ?? '0').toString().trim()) ??
          0;
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

// ─── Actual-over-plan qty resolution ─────────────────────────────────────

/// Resolve a single item-line quantity using actual-over-plan semantics.
///
/// If the [actual] key is present in [e], non-null, and its trimmed string
/// representation is non-empty, parse it as an int (unparseable -> 0).
/// Otherwise fall back to the [plan] key with the same parse-or-zero logic.
///
/// This mirrors the CF `task_complete.qtFor` contract: `actual ?? plan`.
/// Presence is checked via `containsKey` + non-null + non-empty trim, so
/// `actual: 0` correctly displays 0 (does NOT fall back to plan), while
/// `actual: ''` (blank SDUI cell = "unset") falls back to plan.
///
/// WARNING: the `e[actual] != null` clause is load-bearing. Production
/// pre-execution docs carry `'ad': null` / `'ap': null` (written by
/// admin_create_task_support.dart toItMap()). Removing the null check would
/// cause null.toString() -> "null" -> int.tryParse fails -> 0, blanking
/// every pre-execution drop/pickup number on P10, O1, and the manifest.
///
/// Pure function, no Flutter deps, directly testable.
int resolveItemQty(Map e, String plan, String actual) {
  if (e.containsKey(actual) && e[actual] != null) {
    final String raw = e[actual].toString().trim();
    if (raw.isNotEmpty) {
      return int.tryParse(raw) ?? 0;
    }
  }
  return int.tryParse((e[plan] ?? '0').toString().trim()) ?? 0;
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
/// [actualDropField] -- key for actual-drop qty (default `ad`). Presence-checked.
/// [actualPickupField] -- key for actual-pickup qty (default `ap`). Presence-checked.
///
/// Convention #7: dynamic guards throughout (is List, is Map, int.tryParse).
CirculationResult aggregateItemCirculation(
  List<Map<String, dynamic>> taskDocs, {
  String itemsField = 'it',
  String labelField = 'in',
  String dropField = 'pd',
  String pickupField = 'pp',
  String actualDropField = 'ad',
  String actualPickupField = 'ap',
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
      final int drop = resolveItemQty(entry, dropField, actualDropField);
      final int pickup = resolveItemQty(entry, pickupField, actualPickupField);
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
    items.add(
      ItemCirculation(
        itemName: label,
        totalDrop: dropTotals[label]!,
        totalPickup: pickupTotals[label]!,
      ),
    );
  }
  return CirculationResult(
    items: items,
    grandDrop: grandDrop,
    grandPickup: grandPickup,
  );
}

// ─── Per-tx item circulation (P12 circulationSummary "Opsi A") ─────────────

/// One row of the tx-driven circulation summary: an item name with its summed
/// quantity per transaction flow. Unlike [ItemCirculation] (drop/pickup only),
/// this carries all four flows so sale/refill/purchase items no longer render
/// 0/0/0 (spec `driver-return-vehicle-p12-dev-spec (2).md` §3). Each task
/// `it[]` line contributes to exactly ONE flow, chosen by its `tx`
/// discriminator (empty/unknown `tx` == `deliver`).
class TxItemCirculation {
  final String itemName;
  final int drop; // Σ pd  (tx == deliver)
  final int pickup; // Σ pp  (tx == deliver)
  final int sale; // Σ ps  (tx == sale)
  final int refill; // Σ pr  (tx == refill)
  final int buy; // Σ pb  (tx == purchase)
  const TxItemCirculation({
    required this.itemName,
    this.drop = 0,
    this.pickup = 0,
    this.sale = 0,
    this.refill = 0,
    this.buy = 0,
  });

  /// True when every flow is zero (item contributes no visible metric).
  bool get isEmpty =>
      drop == 0 && pickup == 0 && sale == 0 && refill == 0 && buy == 0;
}

/// Result of tx-driven circulation aggregation: per-item rows (first-seen
/// order) + grand totals per flow.
class TxCirculationResult {
  final List<TxItemCirculation> items;
  final int grandDrop;
  final int grandPickup;
  final int grandSale;
  final int grandRefill;
  final int grandBuy;
  const TxCirculationResult({
    required this.items,
    this.grandDrop = 0,
    this.grandPickup = 0,
    this.grandSale = 0,
    this.grandRefill = 0,
    this.grandBuy = 0,
  });
}

/// Aggregate ALL tasks' it[] entries by item name, routing each line's qty to
/// the flow named by its `tx` ([txField]) per spec `(2).md` §3 "Opsi A":
///
///   tx == deliver (or empty/unknown) -> drop += pd, pickup += pp
///   tx == sale                       -> sale += ps
///   tx == refill                     -> refill += pr
///   tx == purchase                   -> buy += pb
///
/// Returns [TxCirculationResult] (per-item rows in first-seen order + grand
/// totals per flow). Mirrors [aggregateItemCirculation] conventions: dynamic
/// guards (is List, is Map, int.tryParse), label trimmed, empty labels skipped.
TxCirculationResult aggregateTxCirculation(
  List<Map<String, dynamic>> taskDocs, {
  String itemsField = 'it',
  String labelField = 'in',
  String txField = 'tx',
  String dropField = 'pd',
  String pickupField = 'pp',
  String saleField = 'ps',
  String refillField = 'pr',
  String buyField = 'pb',
  String actualDropField = 'ad',
  String actualPickupField = 'ap',
  String actualSaleField = 'as',
  String actualRefillField = 'ar',
  String actualBuyField = 'ab',
}) {
  final List<String> order = <String>[];
  final Map<String, int> drop = <String, int>{};
  final Map<String, int> pickup = <String, int>{};
  final Map<String, int> sale = <String, int>{};
  final Map<String, int> refill = <String, int>{};
  final Map<String, int> buy = <String, int>{};

  for (final Map<String, dynamic> doc in taskDocs) {
    final dynamic rawItems = doc[itemsField];
    if (rawItems is! List) continue;
    for (final dynamic entry in rawItems) {
      if (entry is! Map) continue;
      final String label = (entry[labelField] ?? '').toString().trim();
      if (label.isEmpty) continue;
      if (!drop.containsKey(label)) {
        order.add(label);
        drop[label] = 0;
        pickup[label] = 0;
        sale[label] = 0;
        refill[label] = 0;
        buy[label] = 0;
      }
      // Empty / unknown tx == deliver: old it[] lines carry no tx and represent
      // a delivery, so they route to drop/pickup (backward-compatible).
      final String tx = (entry[txField] ?? '').toString().trim().toLowerCase();
      switch (tx) {
        case 'sale':
          sale[label] =
              sale[label]! + resolveItemQty(entry, saleField, actualSaleField);
          break;
        case 'refill':
          refill[label] =
              refill[label]! +
              resolveItemQty(entry, refillField, actualRefillField);
          break;
        case 'purchase':
          buy[label] =
              buy[label]! + resolveItemQty(entry, buyField, actualBuyField);
          break;
        default: // deliver (incl. empty/unknown tx)
          drop[label] =
              drop[label]! + resolveItemQty(entry, dropField, actualDropField);
          pickup[label] =
              pickup[label]! +
              resolveItemQty(entry, pickupField, actualPickupField);
      }
    }
  }

  int sumValues(Map<String, int> m) =>
      m.values.fold<int>(0, (int a, int b) => a + b);

  final List<TxItemCirculation> items = <TxItemCirculation>[];
  for (final String label in order) {
    items.add(
      TxItemCirculation(
        itemName: label,
        drop: drop[label]!,
        pickup: pickup[label]!,
        sale: sale[label]!,
        refill: refill[label]!,
        buy: buy[label]!,
      ),
    );
  }
  return TxCirculationResult(
    items: items,
    grandDrop: sumValues(drop),
    grandPickup: sumValues(pickup),
    grandSale: sumValues(sale),
    grandRefill: sumValues(refill),
    grandBuy: sumValues(buy),
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

/// One condition-quantity pair for a grouped CUSTODY_CONFIRMED_LIST row.
///
/// In grouped mode, a single item's `ip[]` entries (one per condition) are
/// merged. Each entry becomes a [ConditionQty] carrying the display [label]
/// (mapped from the raw `cd` value via the `condLabels` config) and the
/// per-condition [qty]. The list is empty for consumable items (condition
/// breakdown suppressed) and for non-grouped rows.
class ConditionQty {
  final String label;
  final int qty;
  const ConditionQty({required this.label, required this.qty});
}

// ─── Confirmed-list rows (CUSTODY_CONFIRMED_LIST) ──────────────────────────

/// One rendered row of CUSTODY_CONFIRMED_LIST.
///
/// Carries the recount line (name / category / qty from `ip[]` + the item
/// JOIN) plus the OPTIONAL movement badge numbers aggregated from task
/// `it[]`. [drop] / [pickup] are 0 whenever the `flow*` config is absent --
/// the backward-compatible default that renders exactly today's row.
class ConfirmedRow {
  /// Raw `ip[]` item id (`ii`).
  final String itemId;

  /// Display name from the item JOIN; falls back to [itemId].
  final String name;

  /// Category from the item JOIN; falls back to the `ip[]` `cd`.
  final String category;

  /// Counted quantity from `ip[]` `qt`.
  final int qty;

  /// Sum of actual drop (antar) for [itemId]. 0 => hide the badge.
  final int drop;

  /// Sum of actual pickup (ambil) for [itemId]. 0 => hide the badge.
  final int pickup;

  /// Per-condition breakdown. Populated ONLY in grouped mode for non-consumable
  /// items; empty otherwise (the default). The render checks
  /// `conditions.isNotEmpty` to decide whether to show the breakdown line.
  final List<ConditionQty> conditions;

  const ConfirmedRow({
    required this.itemId,
    required this.name,
    required this.category,
    required this.qty,
    this.drop = 0,
    this.pickup = 0,
    this.conditions = const <ConditionQty>[],
  });
}

/// Transform `ip[]` entries into display rows, JOINing item detail and
/// OPTIONALLY attaching per-item movement badges from [flowMap].
///
/// [ipEntries] -- the `ip[]` array off the vehicle_check doc. Each entry is
///   `{ii, cd, qt}` (CountEntry.toIpMap). Entries with an empty `ii` are
///   skipped; `qt` parses via int.tryParse with a 0 default.
/// [itemDetailMap] -- from [buildItemDetailMap]; missing entries fall back to
///   the raw `ii` / `cd`.
/// [flowMap] -- per-item drop/pickup totals keyed by whatever `flowKeyField`
///   produced (item id `ii`, or item name `in`). Defaults to `const {}`, which
///   yields drop = pickup = 0 on every row -- i.e. the pre-badge output.
/// [groupByItem] -- merge entries sharing an `ii` into one row (spec 3b).
/// [condLabels] -- `{rawCd: displayLabel}` from `parseCondLabels`; an unmapped
///   `cd` falls back to its raw value.
/// [condField] -- which entry field carries the condition (default `cd`).
/// [consumableCategory] -- category value whose items skip the condition
///   breakdown (D-A). Empty disables the suppression entirely.
///
/// When [groupByItem] is true, entries sharing the same `ii` are merged into
/// one row: [ConfirmedRow.qty] becomes the sum, [ConfirmedRow.conditions]
/// carries the per-condition breakdown, and badges attach directly (no twin
/// dedup needed). Condition breakdown is suppressed for items whose category
/// matches [consumableCategory] (case-insensitive, D-A).
///
/// Category fallback differs by mode: non-grouped keeps `detail?.category ?? cd`
/// (round 1 behaviour); grouped uses `detail?.category ?? ''` (blank chip
/// hidden) because the raw `cd` now appears in the condition breakdown line
/// and echoing it in the chip would duplicate it.
///
/// When [groupByItem] is false (the default), behaviour is identical to
/// round 1: one row per ip[] entry, first-row-only badge via the [badged]
/// seen-set, [conditions] stays empty on every row.
///
/// FIRST-ROW-ONLY badges (non-grouped branch only): `ip[]` carries one entry
/// per (item, condition), so a single item can occupy two rows (isi + kosong)
/// with the same `ii`. Badges attach to the FIRST row per `ii` in first-seen
/// order; later rows keep 0 so the caller's hide-zero rule suppresses them.
/// Without this, the same sum would read twice as a doubled total. The grouped
/// branch needs no such guard -- one row per `ii` means there is no twin.
///
/// JOIN-KEY TOLERANCE: the spec allows `flowKeyField` to be `ii` OR `in`, so
/// the lookup tries the item id first, then the resolved display name. One
/// lookup pair covers both contract spellings without a config branch.
///
/// CAVEAT (accepted, NOT guarded): the name fallback can cross-match in
/// theory. If a row's own `ii` is absent from [flowMap] AND some OTHER item's
/// `ii` happens to equal that row's resolved display name, the wrong sums
/// attach. Removing the risk would need a config branch on `flowKeyField`;
/// that costs more than the contrived failure is worth in this data.
/// Documented deliberately -- do not add the branch. NOTE: BOTH branches now
/// perform this `flowMap[ii] ?? flowMap[name]` lookup (round 2 added the
/// grouped one), so a future "fix" would have two call sites, not one.
///
/// Pure function -- no Flutter widgets, no Obx, no Firestore. Directly testable.
List<ConfirmedRow> buildConfirmedRows(
  List<Map<String, dynamic>> ipEntries,
  Map<String, ItemDetail> itemDetailMap, {
  Map<String, ItemCirculation> flowMap = const <String, ItemCirculation>{},
  bool groupByItem = false,
  Map<String, String> condLabels = const <String, String>{},
  String condField = 'cd',
  String consumableCategory = '',
}) {
  final List<ConfirmedRow> rows = <ConfirmedRow>[];

  if (groupByItem) {
    // ── Grouped mode: one row per unique ii ──────────────────────────────
    // Dart Map preserves insertion order (LinkedHashMap), so first-seen
    // order of items in ip[] is preserved in the output.
    final Map<String, List<Map<String, dynamic>>> groups =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> entry in ipEntries) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      if (ii.isEmpty) continue;
      groups.putIfAbsent(ii, () => <Map<String, dynamic>>[]).add(entry);
    }

    for (final MapEntry<String, List<Map<String, dynamic>>> g
        in groups.entries) {
      final String ii = g.key;
      final ItemDetail? detail = itemDetailMap[ii];
      final String name = detail?.name ?? ii;
      // Category fallback: '' (not the raw cd). In grouped mode the raw cd
      // appears in the condition breakdown line; echoing it in the category
      // chip would duplicate it. A blank chip is hidden by the render.
      final String category = detail?.category ?? '';

      int totalQt = 0;
      final List<ConditionQty> conds = <ConditionQty>[];
      for (final Map<String, dynamic> entry in g.value) {
        final String cd = (entry[condField] ?? '').toString().trim();
        final int qt =
            int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
        totalQt += qt;
        conds.add(ConditionQty(label: condLabels[cd] ?? cd, qty: qt));
      }

      // Suppress condition breakdown for consumable items (D-A).
      // Compare case-insensitively against the consumable category value
      // from _t(2). When consumableCategory is empty (P7 / unconfigured),
      // the comparison always fails and conditions are shown -- which is
      // the correct default for a widget that has no text slot 2.
      final bool isConsumable =
          consumableCategory.isNotEmpty &&
          category.toLowerCase() == consumableCategory.toLowerCase();

      // Badges attach directly -- one row per ii, no twin dedup needed.
      final ItemCirculation? flow = flowMap[ii] ?? flowMap[name];

      rows.add(
        ConfirmedRow(
          itemId: ii,
          name: name,
          category: category,
          qty: totalQt,
          drop: flow?.totalDrop ?? 0,
          pickup: flow?.totalPickup ?? 0,
          conditions: isConsumable ? const <ConditionQty>[] : conds,
        ),
      );
    }
  } else {
    // ── Non-grouped mode (unchanged from round 1) ────────────────────────
    final Set<String> badged = <String>{};
    for (final Map<String, dynamic> entry in ipEntries) {
      final String ii = (entry['ii'] ?? '').toString().trim();
      final String cd = (entry['cd'] ?? '').toString().trim();
      final int qt = int.tryParse((entry['qt'] ?? '0').toString().trim()) ?? 0;
      if (ii.isEmpty) continue;
      final ItemDetail? detail = itemDetailMap[ii];
      final String name = detail?.name ?? ii;

      int drop = 0;
      int pickup = 0;
      // Set.add returns false for an `ii` already badged on an earlier row.
      if (badged.add(ii)) {
        final ItemCirculation? flow = flowMap[ii] ?? flowMap[name];
        if (flow != null) {
          drop = flow.totalDrop;
          pickup = flow.totalPickup;
        }
      }

      rows.add(
        ConfirmedRow(
          itemId: ii,
          name: name,
          category: detail?.category ?? cd,
          qty: qt,
          drop: drop,
          pickup: pickup,
        ),
      );
    }
  }

  return rows;
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

  /// Expected quantity (plan). Set by O1 aggregate or C1 asset_cache source.
  /// Default 0 for P6 blind mode (planQty unused). The submit reads this to
  /// build the reconciliation expected map without re-subscribing to the data
  /// source.
  ///
  /// NOT emitted by [toIpMap] -- ip[] entries carry only ii/cd/qt (counted).
  int planQty;

  CountEntry({
    required this.ii,
    required this.cd,
    this.qty = 0,
    this.planQty = 0,
  });

  /// Build the Firestore-ready map for one ip[] element.
  Map<String, dynamic> toIpMap() => {'ii': ii, 'cd': cd, 'qt': qty};
}

// ─── Shared reconciliation helper (custody_reveal + C1 submit) ─────────────

/// Result of reconciliation: dp[] discrepancy array + rs status string.
class ReconciliationResult {
  /// Discrepancy entries: only items where expected != actual.
  /// Each entry: `{ii, cd, ex, ac, dl}`.
  final List<Map<String, dynamic>> dp;

  /// Reconcile status: `'matched'` (all equal) or `'discrepancy_detected'`.
  final String rs;

  const ReconciliationResult({required this.dp, required this.rs});
}

/// Build reconciliation from expected vs actual quantity maps.
///
/// For each key in the union of [expected] and [actual] (keyed by `ii__cd`),
/// computes `dl = actual - expected`. Keys where `dl == 0` are omitted from
/// dp[]. Returns [ReconciliationResult] with dp[] and rs.
///
/// Key iteration order is STABLE (insertion order): expected-keys first, then
/// actual-only keys. This preserves custodyReveal's prior dp[] ordering (ie[]
/// order first, then count-store-only keys) after the refactor.
///
/// Pure function, no Flutter/Obx deps, directly testable.
/// Used by custodyReveal (refactored) and C1 CustodyCountSubmit closing mode.
ReconciliationResult buildReconciliation({
  required Map<String, int> expected,
  required Map<String, int> actual,
}) {
  // LinkedHashSet preserves insertion order: expected keys (in their map's
  // iteration order) first, then any actual-only keys. Keep dp[] deterministic.
  final Set<String> allKeys = <String>{...expected.keys, ...actual.keys};
  final List<Map<String, dynamic>> dp = <Map<String, dynamic>>[];
  for (final String key in allKeys) {
    final int ex = expected[key] ?? 0;
    final int ac = actual[key] ?? 0;
    final int dl = ac - ex;
    if (dl == 0) continue;
    // Parse ii and cd from composite key "ii__cd"
    final int sep = key.indexOf('__');
    final String ii = sep >= 0 ? key.substring(0, sep) : key;
    final String cd = sep >= 0 ? key.substring(sep + 2) : '';
    dp.add(<String, dynamic>{'ii': ii, 'cd': cd, 'ex': ex, 'ac': ac, 'dl': dl});
  }
  final String rs = dp.isEmpty ? 'matched' : 'discrepancy_detected';
  return ReconciliationResult(dp: dp, rs: rs);
}

// ─── Deterministic check / investigation doc-id generators ─────────────────

/// Format the WIB (UTC+7) date as `YYYYMMDD` for a given epoch-ms instant.
/// Shared by [genOpeningCnm] / [genClosingCnm] / [genInvestigationVnm].
String _wibDateStamp(int nowMs) {
  const int wibOffsetMs = 25200000; // UTC+7
  final DateTime wibNow = DateTime.fromMillisecondsSinceEpoch(
    nowMs + wibOffsetMs,
    isUtc: true,
  );
  return '${wibNow.year}${wibNow.month.toString().padLeft(2, '0')}'
      '${wibNow.day.toString().padLeft(2, '0')}';
}

/// Generate the OPENING vehicle_check display id.
///
/// Format:
///   seq <= 1 -> `CHK-{vehicleId}-{YYYYMMDD}` (backward compat, no suffix)
///   seq > 1  -> `CHK-{vehicleId}-{YYYYMMDD}-{seq}` (multi-trip suffix)
///
/// [seq] is 1-based: first opening of the day = 1 (no suffix), second = 2, etc.
/// Doc-id uniqueness is Firestore auto-id; cnm is display-only.
String genOpeningCnm(String vehicleId, {int? nowMs, int seq = 1}) {
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  final String base = 'CHK-$vehicleId-${_wibDateStamp(now)}';
  return seq > 1 ? '$base-$seq' : base;
}

/// Generate the CLOSING vehicle_check display id.
///
/// Format:
///   seq <= 1 -> `CHK-{vehicleId}-{YYYYMMDD}-C`
///   seq > 1  -> `CHK-{vehicleId}-{YYYYMMDD}-{seq}-C`
String genClosingCnm(String vehicleId, {int? nowMs, int seq = 1}) {
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  final String base = 'CHK-$vehicleId-${_wibDateStamp(now)}';
  return seq > 1 ? '$base-$seq-C' : '$base-C';
}

/// Generate the investigation doc display id.
///
/// Format:
///   seq <= 1 -> `INV-{vehicleId}-{YYYYMMDD}`
///   seq > 1  -> `INV-{vehicleId}-{YYYYMMDD}-{seq}`
String genInvestigationVnm(String vehicleId, {int? nowMs, int seq = 1}) {
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  final String base = 'INV-$vehicleId-${_wibDateStamp(now)}';
  return seq > 1 ? '$base-$seq' : base;
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
    final String fullyResolved = resolveScreenTxTokens(
      driverResolved,
      screenTx,
    );

    // 3. Parse search clauses into (field, value) String pairs.
    if (fullyResolved.trim().isEmpty) {
      devPrint('[writeNativeFields] empty search after resolve');
      return false;
    }
    final List<MapEntry<String, String>> pairs = <MapEntry<String, String>>[];
    for (final clause in fullyResolved.split('\u{2B58}')) {
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
      pairs.add(MapEntry(field, rawValue));
    }
    if (pairs.isEmpty) {
      devPrint('[writeNativeFields] no valid clauses after resolve');
      return false;
    }

    // 4. Type-agnostic query. Firestore `isEqualTo` matches by exact type, so
    //    a String query misses a num-stored field and vice-versa. To read the
    //    doc whether the matched field is stored as num OR String:
    //      a) Anchor ONE clause on the server with `whereIn:[String, num]`
    //         (a single disjunction -- the only one Firestore allows per query)
    //         so it matches regardless of stored type. Prefer a numeric-valued
    //         clause (selective id/date like `vv`/`cdt`); fall back to the
    //         first clause.
    //      b) Filter the REMAINING clauses client-side with String semantics
    //         (`field.toString().trim() == value`) -- identical to the READ
    //         path (filterByMultiClause), and type-agnostic because
    //         num/bool/String all stringify predictably.
    //    This keeps WRITE matching whatever READ matches, and fixes the P6
    //    "Gagal menyimpan data" bug (numeric-looking `vv`/`cdt` stored as
    //    String were missed by a num-coerced equality query).
    MapEntry<String, String> anchor = pairs.first;
    for (final p in pairs) {
      if (num.tryParse(p.value) != null) {
        anchor = p;
        break;
      }
    }
    final num? anchorNum = num.tryParse(anchor.value);
    dynamic query = firestoreDb.collection(path);
    query = anchorNum != null
        ? query.where(anchor.key, whereIn: <Object>[anchor.value, anchorNum])
        : query.where(anchor.key, isEqualTo: anchor.value);

    // 5. Execute + client-side AND filter (String compare, type-agnostic).
    //    Offline (flag false): force Source.cache so the query resolves
    //    immediately from the SDK cache instead of waiting on a server
    //    timeout (pattern: firestore_generic_repository.dart:104). Online:
    //    default serverAndCache, unchanged. If the flag is stale-true while
    //    actually offline, the SDK's own cache fallback still answers, just
    //    slower.
    final snap = internetConnected()
        ? await query.get()
        : await query.get(const GetOptions(source: Source.cache));
    final List<dynamic> matched = snap.docs.where((d) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(
        d.data() as Map,
      );
      for (final p in pairs) {
        if (!eq((data[p.key] ?? '').toString().trim(), p.value)) return false;
      }
      return true;
    }).toList();

    if (matched.isEmpty) {
      devPrint('[writeNativeFields] 0 matches at $path; cannot write');
      return false;
    }
    if (matched.length > 1) {
      errorReport(
        '[writeNativeFields] ${matched.length} matches at $path; '
        'refusing to write (corrupt uniqueness)',
      );
      return false;
    }

    // 6. Set-merge -- fire-and-forget. The Firestore write Future only
    //    resolves on SERVER ack, so awaiting it hangs the UI offline. SDK
    //    persistence (pinned in main.dart) queues the write and syncs when
    //    online. All honest-fail paths already returned false above; a late
    //    server rejection surfaces via errorReport only (accepted).
    unawaited(
      matched.first.reference
          .set(patch, SetOptions(merge: true))
          .then((_) {
            devPrint('[writeNativeFields] acked $path/${matched.first.id}');
          })
          .catchError((Object e) {
            errorReport('[writeNativeFields] late-fail $path: $e');
          }),
    );
    devPrint(
      '[writeNativeFields] queued $patch into $path/${matched.first.id}',
    );
    return true;
  } catch (e, st) {
    devPrint('[writeNativeFields] error: $e\n$st');
    errorReport('[writeNativeFields] $e');
    return false;
  }
}

/// Create a new Firestore document natively with a DETERMINISTIC doc id.
///
/// Unlike [writeNativeFields] (which queries by search then merges), this
/// creates the document directly by doc id. Used by O1 submit to atomically
/// write the opening vehicle_check doc (scalars + ie[] array) in one call.
///
/// The Firestore SDK's offline persistence queues the write and syncs when
/// online, so this is offline-safe (the Future completes immediately even
/// offline).
///
/// [component] -- the widget's component map (for [resolveAppVid]).
/// [rawTable] -- e.g. `84214220504259//vehicle_check`.
/// [docId] -- the deterministic document id (e.g. the generated cnm).
/// [docMap] -- the complete document map to write (scalars + arrays).
///
/// Uses `SetOptions(merge: true)` so a retry on the same cnm is idempotent
/// (same fields, same values).
///
/// Returns `true` on success, `false` on failure (caller shows snackbar).
Future<bool> createNativeDoc({
  required dynamic component,
  required String rawTable,
  required String docId,
  required Map<String, dynamic> docMap,
}) async {
  try {
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty || tp.subColl.isEmpty) {
      devPrint('[createNativeDoc] bad table path: $rawTable');
      return false;
    }
    if (docId.isEmpty) {
      devPrint('[createNativeDoc] empty docId');
      return false;
    }
    final String appVid = resolveAppVid(component);
    final String path =
        '$mobileTable/$appVid/$mobileTableCollection/${tp.tableDocId}/${tp.subColl}';

    // Fire-and-forget: the write Future only resolves on SERVER ack (hangs
    // offline). SDK persistence queues it; late failure -> errorReport.
    unawaited(
      firestoreDb
          .collection(path)
          .doc(docId)
          .set(docMap, SetOptions(merge: true))
          .then((_) {
            devPrint('[createNativeDoc] acked $path/$docId');
          })
          .catchError((Object e) {
            errorReport('[createNativeDoc] late-fail $path/$docId: $e');
          }),
    );
    devPrint('[createNativeDoc] queued $path/$docId');
    return true;
  } catch (e, st) {
    devPrint('[createNativeDoc] error: $e\n$st');
    errorReport('[createNativeDoc] $e');
    return false;
  }
}

/// Create a new Firestore document with an AUTO-GENERATED doc id.
///
/// Unlike [createNativeDoc] (which writes to a deterministic doc id),
/// this creates a document with a Firestore-generated random id (matches
/// the seed convention where vehicle_check/investigation docs have auto ids).
/// The caller's business key (e.g. `cnm`, `vnm`) lives as a FIELD in the
/// doc map, not as the doc id.
///
/// The Firestore SDK's offline persistence queues the write and syncs when
/// online, so this is offline-safe.
///
/// Returns `true` on success, `false` on failure (caller shows snackbar).
Future<bool> createNativeDocAutoId({
  required dynamic component,
  required String rawTable,
  required Map<String, dynamic> docMap,
}) async {
  try {
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty || tp.subColl.isEmpty) {
      devPrint('[createNativeDocAutoId] bad table path: $rawTable');
      return false;
    }
    final String appVid = resolveAppVid(component);
    final String path =
        '$mobileTable/$appVid/$mobileTableCollection/${tp.tableDocId}/${tp.subColl}';
    // .doc() generates the auto-id CLIENT-side (exactly what .add() does
    // internally), so the id is known for logging without awaiting the
    // server. The set() Future only resolves on SERVER ack (hangs offline)
    // -- fire-and-forget; SDK persistence queues it; late failure ->
    // errorReport.
    final dynamic ref = firestoreDb.collection(path).doc();
    unawaited(
      ref
          .set(docMap)
          .then((_) {
            devPrint('[createNativeDocAutoId] acked $path/${ref.id}');
          })
          .catchError((Object e) {
            errorReport(
              '[createNativeDocAutoId] late-fail $path/${ref.id}: $e',
            );
          }),
    );
    devPrint('[createNativeDocAutoId] queued auto-id doc $path/${ref.id}');
    return true;
  } catch (e, st) {
    devPrint('[createNativeDocAutoId] error: $e\n$st');
    errorReport('[createNativeDocAutoId] $e');
    return false;
  }
}

/// Fetch the active opening doc-id AND the count of today's openings for a
/// vehicle in a single Firestore round-trip.
///
/// Returns a record `(activeDocId, todayCount)`:
///   `activeDocId`: doc-id of the newest non-closed opening ('' if none).
///   `todayCount`: number of opening docs whose cdt matches [today].
///
/// Server-side anchor: cty=opening + vv whereIn [String, num].
/// Client-side: counts docs with eq(cdt, today); finds newest cst != 'closed'.
/// Offline: Source.cache fallback.
///
/// For use in warehouse O1 (needs todayCount for seq) and C1 (needs both
/// activeDocId for targeted close + todayCount for closing cnm seq).
Future<({String activeDocId, int todayCount})> fetchOpeningState({
  required dynamic component,
  required String rawTable,
  required String vehicleId,
  required String today,
}) async {
  if (vehicleId.isEmpty) return (activeDocId: '', todayCount: 0);
  try {
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty || tp.subColl.isEmpty) {
      return (activeDocId: '', todayCount: 0);
    }
    final String appVid = resolveAppVid(component);
    final String path =
        '$mobileTable/$appVid/$mobileTableCollection/${tp.tableDocId}/${tp.subColl}';

    // Type-agnostic anchor on vv (mirrors writeNativeFields :1672-1683)
    final num? numVid = num.tryParse(vehicleId);
    final List<Object> vvValues = numVid != null
        ? <Object>[vehicleId, numVid]
        : <Object>[vehicleId];
    dynamic query = firestoreDb
        .collection(path)
        .where('cty', isEqualTo: 'opening')
        .where('vv', whereIn: vvValues);

    final snap = internetConnected()
        ? await query.get()
        : await query.get(const GetOptions(source: Source.cache));

    // Client-side: count today's openings + find newest non-terminal
    int todayCount = 0;
    final List<dynamic> nonClosed = <dynamic>[];
    for (final d in snap.docs) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(
        d.data() as Map,
      );
      if (eq((data['cdt'] ?? '').toString().trim(), today)) todayCount++;
      if (!isTripTerminalCst(data['cst'])) nonClosed.add(d);
    }

    String activeDocId = '';
    if (nonClosed.isNotEmpty) {
      nonClosed.sort((dynamic a, dynamic b) {
        final int tA =
            int.tryParse(((a.data() as Map)['t'] ?? '0').toString()) ?? 0;
        final int tB =
            int.tryParse(((b.data() as Map)['t'] ?? '0').toString()) ?? 0;
        return tB.compareTo(tA); // desc
      });
      activeDocId = nonClosed.first.id.toString();
    }

    return (activeDocId: activeDocId, todayCount: todayCount);
  } catch (e) {
    devPrint('[fetchOpeningState] error: $e');
    return (activeDocId: '', todayCount: 0);
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

const String kDefaultExcludeStatus = 'load_rejected';

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
      .where(
        (doc) => (doc[statusField] ?? '').toString().trim() != excludeStatus,
      )
      .toList();
}

// ─── Load discrepancy detection (PRECONDITION_GATE_CARD state 4) ─────────

/// Whether a vehicle_check doc carries load discrepancy entries.
///
/// [dpArray] is `gateDoc['dp']` (or `gateDoc[dpField]`), which is `dynamic`
/// from Firestore. Returns `true` iff it is a non-empty `List`. The contents
/// of the entries ({ac, ex, dl}) are NOT inspected -- the binary non-empty
/// test is the whole signal (spec section 10).
///
/// Pure function, no Flutter deps, directly testable.
bool hasLoadDiscrepancy(dynamic dpArray) =>
    dpArray is List && dpArray.isNotEmpty;

// ─── Warehouse id resolution (O1 vehicle_check.gl) ─────────────────────────

/// Look up the warehouse `lv` from the `stock_location` collection.
///
/// Filters [stockDocs] for the single doc whose [typeField] (default `lt`)
/// equals [typeValue] (default `warehouse`) and returns its [idField]
/// (default `lv`). Single-warehouse demo assumption (spec §2.1): exactly one
/// such doc exists per tenant.
///
/// Returns '' when no doc matches (the O1 opening doc then keeps `gl:''`, the
/// current CF-null-tolerant behavior). Docs whose resolved id is empty are
/// skipped so a malformed row cannot mask a real one. When MULTIPLE non-empty
/// matches exist, returns the FIRST and logs a warning (a multi-warehouse
/// tenant needs the deferred session-anchor design, out of scope here).
///
/// Convention #7/#10: [stockDocs] originate from a `dynamic` Firestore store;
/// every field read is `.toString().trim()` (no unguarded cast). Pure — no
/// Flutter/Obx/Firestore deps, directly testable. Reads only in-memory data:
/// never writes Firestore, never enqueues history, never fires a movement.
String lookupWarehouseLv(
  List<Map<String, dynamic>> stockDocs, {
  String typeField = 'lt',
  String typeValue = 'warehouse',
  String idField = 'lv',
}) {
  String firstLv = '';
  int matchCount = 0;
  for (final Map<String, dynamic> doc in stockDocs) {
    final String lt = (doc[typeField] ?? '').toString().trim();
    if (lt != typeValue) continue;
    final String lv = (doc[idField] ?? '').toString().trim();
    if (lv.isEmpty) continue;
    matchCount++;
    if (firstLv.isEmpty) firstLv = lv;
  }
  if (matchCount > 1) {
    devPrint(
      '[lookupWarehouseLv] WARNING: $matchCount stock_location docs with '
      '$typeField==$typeValue; using first $idField="$firstLv" '
      '(single-warehouse demo assumption).',
    );
  }
  return firstLv;
}

/// Return ALL active warehouse entries from a stock_location doc list.
///
/// Each result map has keys `lv` (id) and `ln` (display name), both sanitized
/// via `.toString().trim()`. Skips docs where `lt != warehouse`, `lst != active`,
/// or `lv` is empty.
///
/// Unlike [lookupWarehouseLv] (which returns only the FIRST lv and ignores
/// `lst`), this helper exposes the full list so callers can branch on count:
/// 0 -> error, 1 -> auto-use, >1 -> picker.
///
/// Convention #7: [stockDocs] originate from a `dynamic` Firestore store;
/// every field read is `.toString().trim()` (no unguarded cast). Pure -- no
/// Flutter/Obx/Firestore deps, directly testable.
List<Map<String, String>> listActiveWarehouses(
  List<Map<String, dynamic>> stockDocs, {
  String typeField = 'lt',
  String typeValue = 'warehouse',
  String statusField = 'lst',
  String statusValue = 'active',
  String idField = 'lv',
  String nameField = 'ln',
}) {
  final List<Map<String, String>> result = [];
  for (final Map<String, dynamic> doc in stockDocs) {
    final String lt = (doc[typeField] ?? '').toString().trim();
    if (lt != typeValue) continue;
    final String lst = (doc[statusField] ?? '').toString().trim();
    if (lst != statusValue) continue;
    final String lv = (doc[idField] ?? '').toString().trim();
    if (lv.isEmpty) continue;
    final String ln = (doc[nameField] ?? '').toString().trim();
    result.add({'lv': lv, 'ln': ln});
  }
  return result;
}

/// Resolve the warehouse id (`gl`) for the O1 opening doc, applying precedence:
///
///   1. [configResolved] — the token-resolved `component['warehouseId']` value
///      (resolve tokens BEFORE calling). Wins when non-empty AND contains no
///      unresolved `{` token. Tenant override knob (spec §3).
///   2. [fromStore] — the current `#ACTIVE_WAREHOUSE` value (published from
///      `tasks.first['gl']`). Wins next, so a filled `task.gl` (admin Option C,
///      forward-compat) is honored over the fallback lookup.
///   3. [lookupWarehouseLv] over [stockDocs] — the single-warehouse fallback
///      (spec §2.1). Used only when 1 and 2 are empty.
///
/// Returns '' when all three are empty (`gl` stays empty; CF `fl` is null-
/// tolerant). Pure — no Flutter/Obx/Firestore deps; directly testable.
String resolveWarehouseId({
  required String configResolved,
  required String fromStore,
  required List<Map<String, dynamic>> stockDocs,
  String typeField = 'lt',
  String typeValue = 'warehouse',
  String idField = 'lv',
}) {
  final String cfg = configResolved.trim();
  if (cfg.isNotEmpty && !cfg.contains('{')) return cfg;
  final String store = fromStore.trim();
  if (store.isNotEmpty) return store;
  return lookupWarehouseLv(
    stockDocs,
    typeField: typeField,
    typeValue: typeValue,
    idField: idField,
  );
}

// ─── New-customer id-gen hook (B1-A: admin create-task) ──────────────────

/// Whether a component's `addToEvent` carries the `{newCustomerId}` marker
/// token, indicating the N2 new-customer submit button that needs a
/// client-side id-gen hook in `doSaveProcedure`.
///
/// Gate is airtight: only the N2 "Daftarkan & Lanjut" button (screen
/// `vertikaTeknoLokaciptaNewCustomer`) carries this token in its addToEvent
/// config. No custody / item-execution / other RBT addToEvent contains it.
/// The marker is plain ASCII `{newCustomerId}` — `autheniumDecode`
/// (global.dart:1130) does NOT encode/decode `{` or `}`, so the raw
/// `component['addToEvent']` string always contains the literal token.
///
/// Pure — directly testable (no Firestore/Redux dependency).
bool hasNewCustomerIdMarker(dynamic component) {
  final String raw = (component['addToEvent'] ?? '').toString();
  return raw.contains('{newCustomerId}');
}

/// Generate a unique customer identifier (`lv`) and dispatch it into
/// `screenTx` so:
///   (a) the addToEvent field `lv◼{newCustomerId}` resolves in `saveSend`
///       (api.dart:4278 `resolveDriverCurlyTokens` default case reads
///       `screenTx['newCustomerId']` at line 194), writing `lv` to the
///       stock_location doc;
///   (b) `screenTx['kl']` carries the new customer's id to P2/P4 — the
///       durable carrier that `_republishClient` (task_item_builder.dart:223)
///       and `task_create_submit._onSubmit` (line 124-126 fallback) read.
///
/// Uses `firestoreDb.collection('_').doc().id` (20-char Firestore auto-ID,
/// generated locally, offline-safe). The dispatch is synchronous (Redux);
/// `screenTx` is updated before this function returns.
///
/// Called from `doSaveProcedure` (ftz_row_of_button_2.dart) BEFORE
/// `saveData(...)`, gated by [hasNewCustomerIdMarker].
void generateAndDispatchNewCustomerId() {
  final String lv = firestoreDb.collection('_').doc().id.toString();
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'newCustomerId': lv, 'kl': lv})),
  );
}
