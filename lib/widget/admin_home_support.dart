import 'dart:async'; // unawaited

import 'package:cloud_firestore/cloud_firestore.dart'; // SetOptions, GetOptions, Source
import 'package:flutter/material.dart'; // Color/Colors for AdminTierColors

import '../api.dart'; // getNowMillisecondFromEpoch, autheniumDecode, devPrint, errorReport
import '../firestore_repository/update_event_row.dart'; // parseUpdateEventRow, UpdateEventTarget
import '../global.dart'; // firestoreDb, mobileTable, mobileTableCollection
import 'driver_home_support.dart'; // resolveAppVid, resolveDriverCurlyTokens
import 'dsl_eq.dart';

// ============================================================================
// Admin Home support — pure helpers for H1 coordinationSignalList + header.
//
// Mirror: lib/widget/driver_home_support.dart (pure function section).
// All derive functions are pure over their inputs (no Obx, no GetX, no Redux
// reads inside). Widget code calls these inside Obx after touching reactive
// deps.
// ============================================================================

// ─── Signal model ────────────────────────────────────────────────────────────

/// One actionable signal derived from cross-collection state.
///
/// [type] is one of: `unassigned_vehicle`, `task_returned`, `no_executor`,
/// `blocked_departure`.
/// [head] is the display title (customer name or plate).
/// [ageMs] is `now - anchor` in milliseconds; always >= 0.
/// [tier] is the status tier: `danger`, `warn`, or `ok`.
/// [summary] is the one-line description under the title.
/// [address] is optional (empty string when absent).
/// [taskVid] is the task document id (tnm) for admin actions, or empty for
/// cross-runtime signals where the action carries a vehicleId instead.
/// [vehicleId] is the stock_location lv for cross-runtime nav, or empty.
class Signal {
  final String type;
  final String head;
  final int ageMs;
  final String tier;
  final String summary;
  final String address;
  final String taskVid;
  final String vehicleId;

  const Signal({
    required this.type,
    required this.head,
    required this.ageMs,
    required this.tier,
    required this.summary,
    this.address = '',
    this.taskVid = '',
    this.vehicleId = '',
  });
}

// ─── Age + tier helpers ──────────────────────────────────────────────────────

/// Danger threshold in milliseconds (90 minutes).
const int kDangerThresholdMs = 90 * 60 * 1000;

/// Warn threshold in milliseconds (30 minutes).
const int kWarnThresholdMs = 30 * 60 * 1000;

/// Compute age in milliseconds from an anchor epoch-ms value.
/// Returns 0 if [anchorMs] is null, non-positive, or in the future.
/// [nowMs] defaults to NTP-corrected time via [getNowMillisecondFromEpoch].
int computeAge(dynamic anchorMs, {int? nowMs}) {
  final int anchor = _toInt(anchorMs);
  if (anchor <= 0) return 0;
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  final int diff = now - anchor;
  return diff > 0 ? diff : 0;
}

/// Map age-ms to a 3-tier status string.
/// Default: danger > 90 min, warn > 30 min, else ok.
/// [dangerMs] and [warnMs] override the consts when provided.
String statusTier(int ageMs, {int? dangerMs, int? warnMs}) {
  final int dThresh = dangerMs ?? kDangerThresholdMs;
  final int wThresh = warnMs ?? kWarnThresholdMs;
  if (ageMs > dThresh) return 'danger';
  if (ageMs > wThresh) return 'warn';
  return 'ok';
}

/// Format age-ms as a human-readable string.
/// e.g. "2j 15m" (jam + menit), "45m", "< 1m".
String formatAge(int ageMs) {
  final int totalMinutes = ageMs ~/ 60000;
  if (totalMinutes < 1) return '< 1m';
  final int hours = totalMinutes ~/ 60;
  final int minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return '${hours}j ${minutes}m';
  if (hours > 0) return '${hours}j';
  return '${minutes}m';
}

// ─── Count helpers ───────────────────────────────────────────────────────────

/// Count "berjalan" = vehicle_check docs with cst=custody_confirmed AND
/// cdt={today} (epoch-midnight WIB match).
///
/// [vehicleChecks] — the full vehicle_check collection docs.
/// [todayStr] — the epoch-midnight-WIB string from todayEpochMidnightWib().
/// [cstField] — field name for check status (default 'cst').
/// [cdtField] — field name for check date (default 'cdt').
int countBerjalan(
  List<Map<String, dynamic>> vehicleChecks, {
  required String todayStr,
  String cstField = 'cst',
  String cdtField = 'cdt',
}) {
  int count = 0;
  for (final doc in vehicleChecks) {
    final String cst = (doc[cstField] ?? '').toString().trim();
    final String cdt = (doc[cdtField] ?? '').toString().trim();
    if (cst == 'custody_confirmed' && eq(cdt, todayStr)) {
      count++;
    }
  }
  return count;
}

// ─── Signal derivation (the SINGLE source of truth) ─────────────────────────

/// Derive the full list of actionable admin signals from 5 collections.
///
/// This is pure over its inputs -- call it inside an Obx after touching all
/// reactive mapTableContent codes.
///
/// Returns signals clustered by type, sorted: clusters by maxAge desc (most
/// urgent cluster first), items within cluster by age desc.
///
/// [tasks] -- task collection docs.
/// [stockLocations] -- stock_location collection docs.
/// [vehicleChecks] -- vehicle_check collection docs.
/// [evidenceDocs] -- evidence collection docs.
/// [todayStr] -- epoch-midnight-WIB string for date filtering.
/// [nowMs] -- current time ms (defaults to NTP-corrected).
/// [dangerMs] / [warnMs] -- threshold overrides for statusTier.
///
/// Field-name config params (all default to current hardcoded values):
/// [statusField] -- task status field (default 'tst').
/// [vehicleField] -- task vehicle FK field (default 'vv').
/// [customerNameField] -- task customer name field (default 'kn').
/// [addressField] -- task address field (default 'al').
/// [scheduleField] -- task schedule date field (default 'tdt').
/// [plateField] -- stock_location plate/name field (default 'ln').
/// [driverField] -- stock_location driver FK field (default 'dv').
/// [locationTypeField] -- stock_location type field (default 'lt').
/// [locationIdField] -- stock_location id field (default 'lv').
/// [checkTypeField] -- vehicle_check type field (default 'cty').
/// [checkStatusField] -- vehicle_check status field (default 'cst').
/// [checkVehicleField] -- vehicle_check vehicle FK field (default 'vv').
/// [evidenceTypeField] -- evidence parent type field (default 'ept').
/// [evidenceRefField] -- evidence reference field (default 'erf').
/// [reasonNoteField] -- evidence reason note field (default 'd').
///
/// Gate-DSL config params (autheniumDecode'd before passing):
/// [unassignedGate] -- gate for unassigned_vehicle signals.
/// [returnedGate] -- gate for task_returned signals.
/// [noExecutorGate] -- gate for no_executor signals.
/// [blockedGate] -- gate for blocked_departure signals.
/// [invoiceGate] -- gate for invoice_pending signals (task docs).
List<Signal> deriveAdminSignals({
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> stockLocations,
  required List<Map<String, dynamic>> vehicleChecks,
  required List<Map<String, dynamic>> evidenceDocs,
  required String todayStr,
  int? nowMs,
  int? dangerMs,
  int? warnMs,
  // Field-name config (all optional, defaults = current hardcoded values)
  String statusField = 'tst',
  String vehicleField = 'vv',
  String customerNameField = 'kn',
  String addressField = 'al',
  String scheduleField = 'tdt',
  String plateField = 'ln',
  String driverField = 'dv',
  String locationTypeField = 'lt',
  String locationIdField = 'lv',
  String checkTypeField = 'cty',
  String checkStatusField = 'cst',
  String checkVehicleField = 'vv',
  String evidenceTypeField = 'ept',
  String evidenceRefField = 'erf',
  String reasonNoteField = 'd',
  // Gate-DSL config (autheniumDecode'd before passing)
  String unassignedGate = '',
  String returnedGate = '',
  String noExecutorGate = '',
  String blockedGate = '',
  String invoiceGate = '',
}) {
  final int now = nowMs ?? getNowMillisecondFromEpoch();

  // Pre-index: stock_location vehicles by lv (for plate lookup / no_executor)
  final Map<String, Map<String, dynamic>> vehiclesByLv = {};
  for (final sl in stockLocations) {
    if ((sl[locationTypeField] ?? '').toString().trim() == 'vehicle') {
      final String lv = (sl[locationIdField] ?? '').toString().trim();
      if (lv.isNotEmpty) vehiclesByLv[lv] = sl;
    }
  }

  // Pre-index: evidence reject docs by task tnm (for task_returned reason)
  // Match: ept=='task' -- pick the latest evidence (highest t) per erf.
  final Map<String, Map<String, dynamic>> rejectEvidenceByTnm = {};
  for (final ev in evidenceDocs) {
    if ((ev[evidenceTypeField] ?? '').toString().trim() != 'task') continue;
    final String erf = (ev[evidenceRefField] ?? '').toString().trim();
    if (erf.isEmpty) continue;
    final int evT = _toInt(ev['t']);
    final int existingT = _toInt(rejectEvidenceByTnm[erf]?['t']);
    if (evT > existingT) {
      rejectEvidenceByTnm[erf] = ev;
    }
  }

  // Pre-index: tasks grouped by vv (for no_executor active-task count +
  // blocked_departure today check)
  final Map<String, List<Map<String, dynamic>>> tasksByVv = {};
  for (final t in tasks) {
    final String vv = (t[vehicleField] ?? '').toString().trim();
    if (vv.isNotEmpty) {
      tasksByVv.putIfAbsent(vv, () => []).add(t);
    }
  }

  final List<Signal> signals = [];

  // ── 1. unassigned_vehicle: gate on task docs ────────────────────────
  if (unassignedGate.isNotEmpty) {
    for (final t in tasks) {
      if (!evaluateGate(t, unassignedGate)) continue;

      final String tnm = (t['tnm'] ?? '').toString().trim();
      final String kn = (t[customerNameField] ?? '').toString().trim();
      final String al = (t[addressField] ?? '').toString().trim();
      final int age = computeAge(t['t'], nowMs: now);
      final String tdtStr = (t[scheduleField] ?? '').toString().trim();

      signals.add(
        Signal(
          type: 'unassigned_vehicle',
          head: kn.isNotEmpty ? kn : tnm,
          ageMs: age,
          tier: statusTier(age, dangerMs: dangerMs, warnMs: warnMs),
          summary: 'Menunggu kendaraan \u{00B7} jadwal $tdtStr',
          address: al,
          taskVid: tnm,
        ),
      );
    }
  }

  // ── 2. task_returned: gate on task docs ─────────────────────────────
  if (returnedGate.isNotEmpty) {
    for (final t in tasks) {
      if (!evaluateGate(t, returnedGate)) continue;

      final String tnm = (t['tnm'] ?? '').toString().trim();
      final String kn = (t[customerNameField] ?? '').toString().trim();
      final String al = (t[addressField] ?? '').toString().trim();

      // Look for reject evidence: evidence where ept==task AND erf==tnm
      final Map<String, dynamic>? ev = rejectEvidenceByTnm[tnm];
      final String reason = (ev?[reasonNoteField] ?? '').toString().trim();
      final int evT = _toInt(ev?['t']);

      // Age anchor: evidence timestamp if available, else task.t
      final int anchor = evT > 0 ? evT : _toInt(t['t']);
      final int age = computeAge(anchor, nowMs: now);

      final String reasonSuffix = reason.isNotEmpty ? ' \u{00B7} $reason' : '';

      signals.add(
        Signal(
          type: 'task_returned',
          head: kn.isNotEmpty ? kn : tnm,
          ageMs: age,
          tier: statusTier(age, dangerMs: dangerMs, warnMs: warnMs),
          summary: 'Dikembalikan driver$reasonSuffix',
          address: al,
          taskVid: tnm,
        ),
      );
    }
  }

  // ── 3. no_executor: gate on stock_location vehicle docs ─────────────
  if (noExecutorGate.isNotEmpty) {
    for (final entry in vehiclesByLv.entries) {
      final Map<String, dynamic> veh = entry.value;
      if (!evaluateGate(veh, noExecutorGate)) continue;

      final String lv = entry.key;
      final String ln = (veh[plateField] ?? '').toString().trim();

      // Count assigned tasks for this vehicle
      final List<Map<String, dynamic>> vehTasks = tasksByVv[lv] ?? [];
      final List<Map<String, dynamic>> assignedTasks = vehTasks
          .where((t) => (t[statusField] ?? '').toString().trim() == 'assigned')
          .toList();
      if (assignedTasks.isEmpty) continue; // no assigned tasks -- skip

      // Age = oldest task.t among assigned tasks for this vehicle
      int oldestT = 0;
      for (final t in assignedTasks) {
        final int taskT = _toInt(t['t']);
        if (oldestT == 0 || (taskT > 0 && taskT < oldestT)) {
          oldestT = taskT;
        }
      }
      final int age = computeAge(oldestT, nowMs: now);

      signals.add(
        Signal(
          type: 'no_executor',
          head: ln.isNotEmpty ? ln : lv,
          ageMs: age,
          tier: statusTier(age, dangerMs: dangerMs, warnMs: warnMs),
          summary:
              '${assignedTasks.length} task ter-assign \u{00B7} belum ada pengantar',
          vehicleId: lv,
        ),
      );
    }
  }

  // ── 4. blocked_departure: gate on vehicle_check docs ────────────────
  if (blockedGate.isNotEmpty) {
    for (final vc in vehicleChecks) {
      if (!evaluateGate(vc, blockedGate)) continue;

      final String vv = (vc[checkVehicleField] ?? '').toString().trim();
      if (vv.isEmpty) continue;

      // Check if this vehicle has tasks scheduled today
      final List<Map<String, dynamic>> vehTasks = tasksByVv[vv] ?? [];
      final bool hasTodayTask = vehTasks.any(
        (t) => eq((t[scheduleField] ?? '').toString().trim(), todayStr),
      );
      if (!hasTodayTask) continue;

      // Plate from stock_location
      final String ln = (vehiclesByLv[vv]?[plateField] ?? '').toString().trim();
      // Age anchor: vehicle_check.t
      final int age = computeAge(vc['t'], nowMs: now);

      signals.add(
        Signal(
          type: 'blocked_departure',
          head: ln.isNotEmpty ? ln : vv,
          ageMs: age,
          tier: statusTier(age, dangerMs: dangerMs, warnMs: warnMs),
          summary: 'Opening check belum kelar di gudang',
          vehicleId: vv,
        ),
      );
    }
  }

  // ── 5. invoice_pending: gate on task docs ───────────────────────────
  if (invoiceGate.isNotEmpty) {
    for (final t in tasks) {
      if (!evaluateGate(t, invoiceGate)) continue;

      final String tnm = (t['tnm'] ?? '').toString().trim();
      final String kn = (t[customerNameField] ?? '').toString().trim();
      final String al = (t[addressField] ?? '').toString().trim();
      final int age = computeAge(t['t'], nowMs: now);

      signals.add(
        Signal(
          type: 'invoice_pending',
          head: kn.isNotEmpty ? kn : tnm,
          ageMs: age,
          tier: 'ok', // always neutral -- no age-based coloring
          summary: 'Selesai antar \u{00B7} perlu invoice',
          address: al,
          taskVid: tnm,
        ),
      );
    }
  }

  // ── Sort: cluster by type, clusters by maxAge desc, items by age desc ──
  return _sortSignals(signals);
}

/// Sort signals: group by type, sort clusters by maxAge desc (most urgent
/// cluster first), items within cluster by age desc.
List<Signal> _sortSignals(List<Signal> signals) {
  if (signals.isEmpty) return const [];

  // Group by type
  final Map<String, List<Signal>> groups = {};
  for (final s in signals) {
    groups.putIfAbsent(s.type, () => []).add(s);
  }

  // Sort items within each group by age desc
  for (final list in groups.values) {
    list.sort((a, b) => b.ageMs.compareTo(a.ageMs));
  }

  // Separate invoice_pending cluster (forced last) from normal clusters
  final List<MapEntry<String, List<Signal>>> normal = [];
  final List<MapEntry<String, List<Signal>>> invoiceLast = [];
  for (final entry in groups.entries) {
    if (entry.key == 'invoice_pending') {
      invoiceLast.add(entry);
    } else {
      normal.add(entry);
    }
  }
  // Sort normal clusters by maxAge desc (most urgent first)
  normal.sort((a, b) => b.value.first.ageMs.compareTo(a.value.first.ageMs));
  final List<MapEntry<String, List<Signal>>> sorted = [
    ...normal,
    ...invoiceLast,
  ];

  // Flatten
  final List<Signal> result = [];
  for (final entry in sorted) {
    result.addAll(entry.value);
  }
  return result;
}

// ─── Private utilities ───────────────────────────────────────────────────────

/// Safely coerce a dynamic value to int. Returns 0 on null, empty, or
/// non-parseable input.
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

// ─── Gate-DSL evaluator ─────────────────────────────────────────────────────

/// Evaluate a gate-DSL predicate against a single document.
///
/// Gate format (after autheniumDecode): `field◼value⭘field◼value...`
/// - Clauses joined by ⭘ (U+2B58) are AND'd.
/// - Each clause: `field◼value` (U+25FC separator).
/// - Non-empty value: doc[field] must equal value (type-tolerant via [eq]).
/// - Empty value (e.g. `vv◼`): doc[field] must be empty/blank.
///
/// ## Two-evaluator contract (spec S3-A)
///
/// This function implements **case 2: literal-empty = match-empty**.
/// An empty clause value means "the doc's field must be empty/blank" -- this
/// is the semantics needed by admin gates and picker search configs that
/// intentionally write `dv◼` (no token) to select unassigned docs.
///
/// For case 1 (empty value = fail-closed, match nothing), see
/// `filterByMultiClause` in `driver_home_support.dart`.
///
/// Live configs using match-empty semantics through this function:
/// - `unassignedGate`: `tst◼assigned⭘vv◼`
/// - `noExecutorGate`: `lt◼vehicle⭘dv◼`
/// - `invoiceGate`: `tst◼completed⭘iv◼`
/// - vehiclePicker `search`: `lt◼vehicle⭘lst◼active⭘dv◼`
///
/// No token resolution is performed here -- callers (admin signal builders,
/// `PickerList.filterRows` in `picker_list.dart`) pass literal DSL that was
/// never tokenized.
///
/// Returns true when ALL clauses match.
/// Returns false on empty [gateDsl] (no gate = no match = skip).
///
/// Caller MUST autheniumDecode the DSL BEFORE calling.
bool evaluateGate(Map<String, dynamic> doc, String gateDsl) {
  if (gateDsl.trim().isEmpty) return false;

  final List<String> clauses = gateDsl.split('\u{2B58}');
  for (final clause in clauses) {
    final String trimmed = clause.trim();
    if (trimmed.isEmpty) continue;
    final int sep = trimmed.indexOf('\u{25FC}');
    if (sep < 0) continue; // malformed clause -- skip
    final String field = trimmed.substring(0, sep).trim();
    if (field.isEmpty) continue;
    final String expectedValue = trimmed.substring(sep + 1).trim();
    final String docValue = (doc[field] ?? '').toString().trim();
    if (expectedValue.isEmpty) {
      // Empty expected = doc field must be empty
      if (docValue.isNotEmpty) return false;
    } else {
      // Non-empty expected = type-tolerant match
      if (!eq(docValue, expectedValue)) return false;
    }
  }
  return true;
}

// ─── Imperative updateEventRow executor ─────────────────────────────────────

/// Execute an updateEventRow DSL template with caller-supplied token values.
///
/// This is the admin-write equivalent of [writeNativeFields] but uses the
/// updateEventRow DSL format from spec(2). It resolves `{tokenName}` placeholders
/// with [tokens], parses the DSL via [parseUpdateEventRow], builds a Firestore
/// query from the search conditions, and does a single-doc set-merge.
///
/// Returns true on success (the set-merge is queued fire-and-forget; the SDK
/// cache serves the query offline), false on error (0 matches, >1 matches,
/// bad DSL, unresolved token).
///
/// [rawDsl] -- the raw `component['updateEventRow']` DSL template string.
/// [tokens] -- map of `{tokenName}` -> literal replacement value.
///   e.g. `{'{taskVid}': 'T001', '{vehicleId}': 'VEH01'}`.
/// [component] -- the widget's component map (for [resolveAppVid]).
///
/// IMPORTANT: numeric-looking field values (e.g. `vv` or `tnm` that happen to
/// be all-digits) get `num`-coerced in both query and patch via the
/// num.tryParse branch below. The coder must verify this matches the real
/// Firestore field types. If `vv`/`tnm` are stored as strings in Firestore,
/// the num-coercion would cause a 0-match on the query or a wrong-type write.
/// The existing `writeNativeFields` (driver_home_support.dart:1631-1639) and
/// `writeUpdateEventRow` (table_repository.dart:1538 via `_parseSearchValue`)
/// both use the same num/bool/string coercion pattern, so this is consistent
/// with the codebase convention -- but verify against live data.
///
/// Uses the real [UpdateEventTarget] API:
/// - `.collection` (String): `<tableDocId>//<subColl>` routing prefix.
/// - `.tablevid` (String): Firebase table node id override.
/// - `.conditions` (`List<MapEntry<String, String>>`): AND search conditions
///   where each entry has `.key` (field name) and `.value` (match value).
/// - `.body` (`Map<String, String>`): char-code keys to sparse-merge.
///
/// Path construction mirrors `eventCollectionPath` (table_repository.dart:1406):
/// splits `.collection` on `//` (folderSeparator, global.dart:330) to get
/// `<docId>` and `<sub>`, then builds `MobileTable/<tablevid>/tables/<docId>/<sub>`.
Future<bool> executeUpdateEventRow({
  required String rawDsl,
  required Map<String, String> tokens,
  required dynamic component,
  required String scrName,
}) async {
  try {
    if (rawDsl.trim().isEmpty) return false;

    // 1. autheniumDecode
    String decoded = autheniumDecode(rawDsl) ?? rawDsl;

    // 2. Replace caller tokens
    for (final entry in tokens.entries) {
      decoded = decoded.replaceAll(entry.key, entry.value);
    }

    // 2b. Resolve system/session tokens the caller cannot know ({today},
    // {now}, {userVid}, {userName}, ...) with the canonical resolver.
    // Caller tokens win (already substituted above). Unknown tokens stay
    // literal so the guard below still fails closed.
    decoded = resolveDriverCurlyTokens(decoded, scrName);

    // Guard: if any {token} remains unresolved, bail
    if (decoded.contains('{')) {
      devPrint('[executeUpdateEventRow] unresolved token in DSL: $decoded');
      return false;
    }

    // 3. Parse via the real parseUpdateEventRow API
    final UpdateEventTarget target = parseUpdateEventRow(decoded);
    if (target.conditions.isEmpty) {
      devPrint('[executeUpdateEventRow] no search conditions');
      return false;
    }

    // 4. Build Firestore path (mirrors eventCollectionPath logic)
    final String appVid = resolveAppVid(component);
    final int tableVid =
        int.tryParse(target.tablevid.trim()) ?? int.tryParse(appVid) ?? 0;
    if (tableVid == 0) {
      devPrint('[executeUpdateEventRow] bad tablevid: ${target.tablevid}');
      return false;
    }
    // Split collection on "//" (folderSeparator) to get docId and subColl
    final String rawColl = target.collection.trim();
    String tableDocId;
    String subColl;
    if (rawColl.contains('//')) {
      final List<String> seg = rawColl.split('//');
      tableDocId = seg.first.trim();
      subColl = (seg.length > 1 && seg.last.trim().isNotEmpty)
          ? seg.last.trim()
          : 'content';
    } else {
      tableDocId = rawColl;
      subColl = 'content';
    }
    if (tableDocId.isEmpty || subColl.isEmpty) {
      devPrint('[executeUpdateEventRow] bad collection: ${target.collection}');
      return false;
    }
    final String path =
        '$mobileTable/$tableVid/$mobileTableCollection/$tableDocId/$subColl';

    // 5. Build query from target.conditions (List<MapEntry<String, String>>)
    dynamic query = firestoreDb.collection(path);
    for (final c in target.conditions) {
      final String key = c.key.trim();
      final String rawVal = c.value.trim();
      if (key.isEmpty) continue;
      // Type-coerce value (mirrors _parseSearchValue pattern)
      dynamic typedValue;
      final String lower = rawVal.toLowerCase();
      if (lower == 'true') {
        typedValue = true;
      } else if (lower == 'false') {
        typedValue = false;
      } else {
        typedValue = num.tryParse(rawVal) ?? rawVal;
      }
      query = query.where(key, isEqualTo: typedValue);
    }

    // 6. Execute query + uniqueness guard. Offline (flag false): force
    //    Source.cache so the query resolves immediately from the SDK cache
    //    instead of waiting on a server timeout.
    final snap = internetConnected()
        ? await query.get()
        : await query.get(const GetOptions(source: Source.cache));
    final docs = snap.docs;
    if (docs.isEmpty) {
      devPrint('[executeUpdateEventRow] 0 matches at $path; cannot write');
      return false;
    }
    if (docs.length > 1) {
      errorReport(
        '[executeUpdateEventRow] ${docs.length} matches at $path; '
        'refusing to write (corrupt uniqueness)',
      );
      return false;
    }

    // 7. Build patch from target.body (Map<String, String>) + set-merge
    final Map<String, dynamic> patch = {};
    target.body.forEach((k, v) {
      // Type-coerce body values too
      final String lower = v.toString().toLowerCase();
      if (lower == 'true') {
        patch[k] = true;
      } else if (lower == 'false') {
        patch[k] = false;
      } else {
        patch[k] = num.tryParse(v.toString()) ?? v;
      }
    });
    // Fire-and-forget: the write Future only resolves on SERVER ack (hangs
    // offline). SDK persistence queues it; late failure -> errorReport.
    unawaited(
      docs.first.reference
          .set(patch, SetOptions(merge: true))
          .then((_) {
            devPrint('[executeUpdateEventRow] acked $path/${docs.first.id}');
          })
          .catchError((Object e) {
            errorReport('[executeUpdateEventRow] late-fail $path: $e');
          }),
    );
    devPrint(
      '[executeUpdateEventRow] queued $patch into $path/${docs.first.id}',
    );
    return true;
  } catch (e, st) {
    devPrint('[executeUpdateEventRow] error: $e\n$st');
    errorReport('[executeUpdateEventRow] $e');
    return false;
  }
}

// ─── Item-level progress (it[] ad/ap) ───────────────────────────────────────

/// Count done vs total lines in a task's items array.
///
/// [task] -- the task doc.
/// [doneMarker] -- comma-separated field names; a line is "done" if ANY marker
///   field has a non-empty value. e.g. "ad,ap" = done if ad OR ap is present.
/// [itemsField] -- field name for the items array on the task doc (default 'it').
///
/// Returns (done, total). Total = items.length; done = count of items where at
/// least one marker field is non-empty.
(int done, int total) progressFromItems(
  Map<String, dynamic> task, {
  String doneMarker = 'ad,ap',
  String itemsField = 'it',
}) {
  final dynamic rawItems = task[itemsField];
  if (rawItems is! List) return (0, 0);
  if (rawItems.isEmpty) return (0, 0);

  final List<String> markers = doneMarker
      .split(',')
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toList();
  if (markers.isEmpty) return (0, rawItems.length);

  int done = 0;
  for (final dynamic item in rawItems) {
    if (item is! Map) continue;
    bool isDone = false;
    for (final String marker in markers) {
      final String val = (item[marker] ?? '').toString().trim();
      if (val.isNotEmpty) {
        isDone = true;
        break;
      }
    }
    if (isDone) done++;
  }
  return (done, rawItems.length);
}

// ─── R2 helpers: stat-list derive ───────────────────────────────────────────

// ── BERJALAN: stop progress per vehicle ─────────────────────────────────────

// NOTE: named `AdminStopProgress` / `computeAdminStopProgress` (not the plan's
// `StopProgress` / `computeStopProgress`) because driver_home_support.dart
// already exports a differently-shaped `StopProgress` + `computeStopProgress`,
// and both files are re-exported by the `all_widget.dart` barrel — the bare
// names collide at compile time (ambiguous export). The admin variant is
// per-vehicle (completed/total over a vehicleId), distinct from the driver
// variant (per-doc-list snapshot). See walkthrough Deviations.

/// Count of (completed, total) tasks for a vehicle.
class AdminStopProgress {
  final int completed;
  final int total;
  const AdminStopProgress(this.completed, this.total);
}

/// Compute stop progress for a single vehicle.
///
/// [tasks] -- all task docs.
/// [vehicleId] -- the vehicle's `lv` (stock_location id).
/// [vvField] -- field name for vehicle FK on task (default `vv`).
/// [tstField] -- field name for task status (default `tst`).
///
/// Returns (completed, total). "completed" = tasks whose normalized status
/// is `done` (via [_isDone]). "total" = all tasks assigned to this vehicle
/// (any tst, excluding `load_rejected`).
AdminStopProgress computeAdminStopProgress(
  List<Map<String, dynamic>> tasks,
  String vehicleId, {
  String vvField = 'vv',
  String tstField = 'tst',
}) {
  int completed = 0;
  int total = 0;
  for (final t in tasks) {
    final String vv = (t[vvField] ?? '').toString().trim();
    if (vv != vehicleId) continue;
    final String tst = (t[tstField] ?? '').toString().trim();
    if (tst == 'load_rejected') continue;
    total++;
    if (_isDone(tst)) completed++;
  }
  return AdminStopProgress(completed, total);
}

/// Check if a task status is "done" (completed/done/closed).
/// Mirrors the `stopStatusOf` normalization in driver_home_support.dart:858.
bool _isDone(String tst) {
  return tst == 'completed' || tst == 'done' || tst == 'closed';
}

/// Find the name of the last completed stop for a vehicle.
///
/// Returns the `kn` (customer name) of the task with the highest `tce`
/// (completed_at) among done tasks for this vehicle. Empty string if none.
String lastCompletedStopName(
  List<Map<String, dynamic>> tasks,
  String vehicleId, {
  String vvField = 'vv',
  String tstField = 'tst',
  String knField = 'kn',
  String tceField = 'tce',
}) {
  int latestTce = 0;
  String name = '';
  for (final t in tasks) {
    final String vv = (t[vvField] ?? '').toString().trim();
    if (vv != vehicleId) continue;
    final String tst = (t[tstField] ?? '').toString().trim();
    if (!_isDone(tst)) continue;
    final int tce = _toInt(t[tceField]);
    if (tce > latestTce) {
      latestTce = tce;
      name = (t[knField] ?? '').toString().trim();
    }
  }
  return name;
}

// ── AKAN DATANG: item summary ───────────────────────────────────────────────

/// Summarize a task's `it[]` array into "Drop N . Pickup N" text.
///
/// [rawItems] -- the `it` field from a task doc (expected `List<dynamic>`).
/// [dropField] -- field name for planned drop qty (default `pd`).
/// [pickupField] -- field name for planned pickup qty (default `pp`).
/// [dropLabel] -- label for drop (default `Drop`).
/// [pickupLabel] -- label for pickup (default `Pickup`).
///
/// Returns empty string if rawItems is not a List or both sums are 0.
String summarizeItems(
  dynamic rawItems, {
  String dropField = 'pd',
  String pickupField = 'pp',
  String dropLabel = 'Drop',
  String pickupLabel = 'Pickup',
}) {
  if (rawItems is! List) return '';
  int dropSum = 0;
  int pickupSum = 0;
  for (final dynamic item in rawItems) {
    if (item is! Map) continue;
    dropSum += _toInt(item[dropField]);
    pickupSum += _toInt(item[pickupField]);
  }
  if (dropSum == 0 && pickupSum == 0) return '';
  final List<String> parts = [];
  if (dropSum > 0) parts.add('$dropLabel $dropSum');
  if (pickupSum > 0) parts.add('$pickupLabel $pickupSum');
  return parts.join(' \u{00B7} '); // middot separator
}

/// Format an epoch-ms timestamp to HH:mm (24h) in WIB (UTC+7).
///
/// Returns empty string if [epochMs] is null, 0, or non-numeric.
String formatTimePill(dynamic epochMs) {
  final int ms = _toInt(epochMs);
  if (ms <= 0) return '';
  try {
    final DateTime utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final DateTime wib = utc.add(const Duration(hours: 7));
    final String h = wib.hour.toString().padLeft(2, '0');
    final String m = wib.minute.toString().padLeft(2, '0');
    return '$h:$m';
  } catch (_) {
    return '';
  }
}

// ── PRIORITAS: outstanding grouping + aging ─────────────────────────────────

/// Outstanding aging thresholds in days (dev-spec section-3.2: danger=14, warn=7).
const int kKritisThresholdDays = 14;
const int kPerhatianThresholdDays = 7;

/// One outstanding group (client + items).
class OutstandingGroup {
  final String clientId; // stock_location lv
  final String clientName;
  final int totalQty; // net outstanding (sum qt across items)
  final int agingDays; // oldest item age in days
  final String tier; // 'kritis', 'perhatian', or 'normal'
  final String itemSummary; // e.g. "Gas 3kg . Tabung 12 pcs . 15 hari"
  final List<OutstandingItem> items; // per-item detail

  const OutstandingGroup({
    required this.clientId,
    required this.clientName,
    required this.totalQty,
    required this.agingDays,
    required this.tier,
    required this.itemSummary,
    this.items = const [],
  });
}

/// One item within an outstanding group (per-item detail).
class OutstandingItem {
  final String itemId;
  final int qty;
  final int agingDays;
  const OutstandingItem({
    required this.itemId,
    required this.qty,
    required this.agingDays,
  });
}

/// Map aging days to a 3-tier string for outstanding.
/// Default thresholds: kritis > 14 days, perhatian > 7 days, else normal.
/// [dangerDays] and [warnDays] override the consts when provided.
String agingTierDays(int days, {int? dangerDays, int? warnDays}) {
  final int dThresh = dangerDays ?? kKritisThresholdDays;
  final int wThresh = warnDays ?? kPerhatianThresholdDays;
  if (days > dThresh) return 'kritis';
  if (days > wThresh) return 'perhatian';
  return 'normal';
}

/// Format aging days as "{n} hari".
String formatAgeDays(int days) {
  if (days <= 0) return '< 1 hari';
  return '$days hari';
}

/// Group asset_cache docs into OutstandingGroup entries.
///
/// [assetCacheDocs] -- asset_cache docs where `lt == 'client'`.
/// [stockLocations] -- stock_location docs (for client name lookup by `lv`).
/// [nowMs] -- current epoch-ms (defaults to NTP-corrected).
///
/// Groups by `lv` (client id). For each group:
/// - Sum `qt` per item (`ii`). Skip groups where total qty <= 0 (hideZero).
/// - Aging = oldest item's `(now - t)` in days.
/// - Tier from agingTierDays.
/// - Sorted by aging desc (oldest first).
///
/// [lvField], [ltField], [iiField], [qtField], [tField] -- field overrides.
/// [lnField] -- name field on stock_location (default `ln`).
List<OutstandingGroup> groupOutstanding({
  required List<Map<String, dynamic>> assetCacheDocs,
  required List<Map<String, dynamic>> stockLocations,
  int? nowMs,
  String lvField = 'lv',
  String ltField = 'lt',
  String iiField = 'ii',
  String qtField = 'qt',
  String tField = 't',
  String lnField = 'ln',
  int? dangerDays,
  int? warnDays,
}) {
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  const int msPerDay = 86400000;

  // Index: stock_location clients by lv for name lookup
  final Map<String, String> clientNames = {};
  for (final sl in stockLocations) {
    if ((sl[ltField] ?? '').toString().trim() == 'client') {
      final String lv = (sl[lvField] ?? '').toString().trim();
      if (lv.isNotEmpty) {
        clientNames[lv] = (sl[lnField] ?? '').toString().trim();
      }
    }
  }

  // Group asset_cache by lv
  final Map<String, List<OutstandingItem>> groups = {};
  for (final ac in assetCacheDocs) {
    if ((ac[ltField] ?? '').toString().trim() != 'client') continue;
    final String lv = (ac[lvField] ?? '').toString().trim();
    if (lv.isEmpty) continue;
    final int qty = _toInt(ac[qtField]);
    if (qty <= 0) continue; // skip 0 or negative items
    final String ii = (ac[iiField] ?? '').toString().trim();
    final int t = _toInt(ac[tField]);
    final int ageDays = t > 0 ? ((now - t) ~/ msPerDay) : 0;
    groups
        .putIfAbsent(lv, () => [])
        .add(
          OutstandingItem(
            itemId: ii,
            qty: qty,
            agingDays: ageDays < 0 ? 0 : ageDays,
          ),
        );
  }

  // Build OutstandingGroup entries
  final List<OutstandingGroup> result = [];
  for (final entry in groups.entries) {
    final String lv = entry.key;
    final List<OutstandingItem> items = entry.value;
    if (items.isEmpty) continue;

    int totalQty = 0;
    int maxAgingDays = 0;
    for (final item in items) {
      totalQty += item.qty;
      if (item.agingDays > maxAgingDays) maxAgingDays = item.agingDays;
    }

    if (totalQty <= 0) continue; // hideZero

    final String firstName = items.isNotEmpty ? items.first.itemId : '';
    final String clientName = clientNames[lv] ?? lv;

    result.add(
      OutstandingGroup(
        clientId: lv,
        clientName: clientName,
        totalQty: totalQty,
        agingDays: maxAgingDays,
        tier: agingTierDays(
          maxAgingDays,
          dangerDays: dangerDays,
          warnDays: warnDays,
        ),
        itemSummary: firstName.isNotEmpty
            ? '$firstName \u{00B7} $totalQty pcs \u{00B7} ${formatAgeDays(maxAgingDays)}'
            : '$totalQty pcs \u{00B7} ${formatAgeDays(maxAgingDays)}',
        items: items,
      ),
    );
  }

  // Sort by aging desc (oldest first = most urgent)
  result.sort((a, b) => b.agingDays.compareTo(a.agingDays));
  return result;
}

// ─── Tier color palette (centralized, theme-tier section-0.3) ──────────────

/// Centralized 3-tier color palette for Admin widgets.
///
/// Maps `danger` / `warn` / `ok` to the approved color pairs (fg + bg).
/// Colors resolve to the EXACT hex values approved in the R2 design review --
/// no visual regression. When the server theme eventually adds tier-color
/// slots, only this class needs updating.
///
/// Usage: `AdminTierColors.bg('danger')` instead of inline `Color(0xFFFFF7E6)`.
///
/// Dev-spec section-0.3: "Tier danger/warn/ok, warna dari THEME bukan config."
class AdminTierColors {
  AdminTierColors._();

  // ── DANGER tier (amber) ─────────────────────────────────────────────────

  /// Card/pill background for danger tier (cream).
  static const Color dangerBg = Color(0xFFFFF7E6);

  /// Card border / solid button fill for danger tier (amber).
  static const Color dangerBorder = Color(0xFFF59E0B);

  /// Badge/pill background for danger/kritis tier (light amber).
  static const Color dangerBadgeBg = Color(0xFFFEF3C7);

  /// Badge/pill text for danger/kritis tier (dark amber).
  static const Color dangerBadgeText = Color(0xFFB45309);

  // ── WARN tier (violet) ──────────────────────────────────────────────────

  /// Badge background for warn/perhatian tier (light violet).
  static const Color warnBadgeBg = Color(0xFFEDE9FE);

  /// Badge text for warn/perhatian tier (violet).
  static const Color warnBadgeText = Color(0xFF7C3AED);

  // ── OK tier (blue for admin, green for "berjalan" badge) ────────────────

  /// Primary action color for ok tier / non-danger cards (blue).
  static const Color okAction = Color(0xFF2563EB);

  /// "Berjalan" badge background (green).
  static const Color okBadgeBg = Color(0xFFDCFCE7);

  /// "Berjalan" badge text (green).
  static const Color okBadgeText = Color(0xFF16A34A);

  /// Solid action color for the invoice tier (darker green). Deliberately NOT
  /// [okBadgeText] -- that green is only 3.3:1 against a white button label,
  /// below AA for the 14px bold text; this one is 5.0:1. Badge use is fine.
  static const Color okActionGreen = Color(0xFF15803D);

  /// "Gudang" cross-badge background (same green as berjalan).
  static const Color crossBadgeBg = Color(0xFFDCFCE7);

  /// "Gudang" cross-badge text.
  static const Color crossBadgeText = Color(0xFF16A34A);

  // ── NEUTRAL structural tokens ───────────────────────────────────────────

  /// Normal/ok badge background (slate).
  static const Color normalBadgeBg = Color(0xFFF1F5F9);

  /// Normal/ok badge text (dark slate).
  static const Color normalBadgeText = Color(0xFF475569);

  /// Age pill bg for non-danger signals.
  static const Color neutralPillBg = Color(0xFFF1F5F9);

  /// Age pill text for non-danger signals.
  static const Color neutralPillText = Color(0xFF64748B);

  /// Icon tile background (light blue).
  static const Color iconTileBg = Color(0xFFEAF1FF);

  /// Card border for non-danger cards.
  static const Color cardBorder = Color(0xFFE5E7EB);

  /// Title text color.
  static const Color titleText = Color(0xFF1F2937);

  /// Subtitle/body text color.
  static const Color subText = Color(0xFF6B7280);

  /// Muted text color (address, last-stop).
  static const Color mutedText = Color(0xFF9CA3AF);

  /// Section header caps color.
  static const Color sectionCaps = Color(0xFF94A3B8);

  // ── Convenience methods for tier-driven lookups ─────────────────────────

  /// Returns (badgeBg, badgeText) for an outstanding aging tier.
  /// [tier] is one of: `'kritis'`, `'perhatian'`, `'normal'`.
  static (Color bg, Color fg) outstandingBadge(String tier) {
    switch (tier) {
      case 'kritis':
        return (dangerBadgeBg, dangerBadgeText);
      case 'perhatian':
        return (warnBadgeBg, warnBadgeText);
      default:
        return (normalBadgeBg, normalBadgeText);
    }
  }

  /// Returns (pillBg, pillText) for a signal age pill.
  /// [tier] is one of: `'danger'`, `'warn'`, `'ok'`.
  /// [green] -- invoice tier: work is done, the pill reads "settled", not aging.
  static (Color bg, Color fg) signalAgePill(String tier, {bool green = false}) {
    if (tier == 'danger') {
      return (dangerBadgeBg, dangerBadgeText);
    }
    if (green) {
      return (okBadgeBg, okBadgeText);
    }
    return (neutralPillBg, neutralPillText);
  }

  /// Returns (cardBg, cardBorderColor, borderWidth) for a signal card.
  /// [isDanger] -- true for danger-tier admin signals or hard cross signals.
  static (Color bg, Color border, double width) signalCard(bool isDanger) {
    if (isDanger) {
      return (dangerBg, dangerBorder, 1.5);
    }
    return (Colors.white, cardBorder, 1.0);
  }

  /// Returns (buttonBg, buttonFg, isOutline) for a signal action button.
  /// [isSoft] -- true for blocked_departure (outline blue).
  /// [isDanger] -- true for danger-tier admin or no_executor.
  /// [isCross] -- true for cross-runtime signals.
  /// [isOk] -- true for invoice_pending (delivery finished, just bill): green.
  static (Color bg, Color fg, bool isOutline) signalButton({
    required bool isSoft,
    required bool isDanger,
    required bool isCross,
    bool isOk = false,
  }) {
    if (isSoft) {
      return (Colors.transparent, okAction, true);
    }
    if (isDanger || isCross) {
      return (dangerBorder, Colors.white, false);
    }
    if (isOk) {
      return (okActionGreen, Colors.white, false);
    }
    return (okAction, Colors.white, false);
  }
}
