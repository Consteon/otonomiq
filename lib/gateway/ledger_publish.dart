import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../firestore_repository/add_to_event.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../model/lock.dart';
import 'gateway_client.dart';

// ===========================================================================
// Constants
// ===========================================================================

/// Secure-storage key for the ledger publish outbox (a JSON list of entries).
/// Documented in `documentation.md` → "Secure Storage Keys".
const String ledgerOutboxName = '_LEDGER_OUTBOX';

/// Gateway base URL. BUILD-TIME ONLY — never from a sheet, config or Firestore:
/// the request carries a Firebase ID token, so a sheet-editable URL would let
/// anyone with edit access redirect that token to another server.
/// Defaults to the otq-01 gateway (Cloud Run deterministic URL; verified live
/// 2026-09-14) so a plain `flutter run` or release build publishes without a
/// flag. Override with `--dart-define=GATEWAY_URL=...` (e.g. a local gateway);
/// an explicitly empty define turns the feature off (entries stay queued, one
/// errorReport per session, no crash).
const String gatewayUrl = String.fromEnvironment(
  'GATEWAY_URL',
  defaultValue: 'https://pub-sub-gateway-721538991284.asia-southeast2.run.app',
);

/// Base URL the drain may POST to, or null when [raw] is not usable.
///
/// `Uri.tryParse` accepts almost anything (`gw.example.run.app`, even
/// `not a url`), and a scheme-less base yields a host-less request URI that
/// `http` rejects with an `ArgumentError` — which the client would map to
/// `retryable` and retry forever with NO report. So require an absolute https
/// URL with a host. `http://` is allowed only when [allowHttp] (debug builds:
/// the local gateway in FLUTTER_v2.md §8 runs on http://10.0.2.2:8080).
///
/// No path either (a bare trailing `/` is fine): the client builds
/// `/v1/ledgers/…` with `replace(path:)`, which silently drops a base path
/// such as `/v1` — every request would 404 and every entry end up `failed`.
/// Rejected here instead, the feature stays off with one report and the
/// entries stay queued.
Uri? parseGatewayBaseUrl(String raw, {bool allowHttp = kDebugMode}) {
  final String s = raw.trim();
  if (s.isEmpty) return null;
  final Uri? u = Uri.tryParse(s);
  if (u == null || !u.hasScheme || u.host.isEmpty) return null;
  if (u.path.isNotEmpty && u.path != '/') return null; // client owns the path
  if (u.isScheme('https')) return u;
  if (allowHttp && u.isScheme('http')) return u;
  return null;
}

/// The gateway remembers `(user, ledgerCode, Idempotency-Key)` for 24 h.
const int ledgerIdempotencyWindowMs = 24 * 60 * 60 * 1000;

/// `failed` entries are dropped this many days after `failedAt`. They are pure
/// forensics — nothing reads them.
const int ledgerFailedMaxDayAge = 30;

/// Max encoded body the gateway accepts (`FLUTTER_v2.md` §3).
const int ledgerMaxBodyBytes = 256 * 1024;

/// Serialises the drain cycle. Its OWN lock: `historySyncLock` must stay free so
/// a slow gateway can never delay the history queue.
final Lock ledgerDrainLock = Lock();

final RegExp _ledgerCodeRe = RegExp(r'^[A-Z0-9]{4,16}$');

bool _gatewayUrlReported = false;

// ===========================================================================
// Entry model
// ===========================================================================

/// One queued publish. Persisted as JSON under [ledgerOutboxName].
class LedgerEntry {
  LedgerEntry({
    required this.key,
    required this.uid,
    required this.ledgerCode,
    required this.body,
    required this.actionAt,
    required this.historyId,
    this.attempted = false,
    this.notBefore = 0,
    this.failed = false,
    this.error = '',
    this.errorId = '',
    this.failedAt = 0,
  });

  /// Server JSON / stored JSON is dynamic BY DESIGN — every field is read with
  /// an explicit per-field coercion so a hand-edited or older blob cannot throw.
  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    key: (j['key'] ?? '').toString(),
    uid: (j['uid'] ?? '').toString(),
    ledgerCode: (j['ledgerCode'] ?? '').toString(),
    body: (j['body'] ?? '').toString(),
    actionAt: int.tryParse((j['actionAt'] ?? '0').toString()) ?? 0,
    historyId: int.tryParse((j['historyId'] ?? '0').toString()) ?? 0,
    attempted: j['attempted'] == true,
    notBefore: int.tryParse((j['notBefore'] ?? '0').toString()) ?? 0,
    failed: j['failed'] == true,
    error: (j['error'] ?? '').toString(),
    errorId: (j['errorId'] ?? '').toString(),
    failedAt: int.tryParse((j['failedAt'] ?? '0').toString()) ?? 0,
  );

  /// `Idempotency-Key` — minted at tap time, never regenerated.
  final String key;

  /// `{"schemaVersion":N,"data":{...}}` encoded ONCE. Every attempt sends these
  /// exact bytes; re-encoding risks `409 idempotency_conflict`.
  final String body;

  final String ledgerCode;
  final int actionAt;
  final int historyId;

  /// UID captured at enqueue. '' = unknown; the drain adopts the current user
  /// once and reports it.
  String uid;

  /// true once the bytes have reached the network at least once. Persisted
  /// BEFORE the POST so a kill mid-request cannot look like "never sent".
  bool attempted;
  int notBefore;
  bool failed;
  String error;
  String errorId;
  int failedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'uid': uid,
    'ledgerCode': ledgerCode,
    'body': body,
    'actionAt': actionAt,
    'historyId': historyId,
    'attempted': attempted,
    'notBefore': notBefore,
    'failed': failed,
    'error': error,
    'errorId': errorId,
    'failedAt': failedAt,
  };
}

// ===========================================================================
// Compose side (saveSend)
// ===========================================================================

/// Finish the compose-time publish segment: guard the outer `tb` frame and stamp
/// the `Idempotency-Key`.
///
/// [resolved] is the `publishLedger` value AFTER the addToEvent pre-pass
/// (autheniumDecode → resolveDriverCurlyTokens → replacePlaceholders →
/// TokenResolver.screenTxMarkers). Empty in → empty out.
///
/// `⬤` (separator[0]) → space: `saveSend` joins the `tb` segments with it, so one
/// literal ⬤ in the authored JSON would shift every later segment.
///
/// ponytail: the inner DSL glyphs (◆ ⭘ ◼) are deliberately NOT sanitised. Unlike
/// addToEvent's notification suffix, the WHOLE segment is author-written DSL, and
/// `stringCleanUp` already strips those glyphs from every resolved form value.
/// Add per-value sanitising only if a tenant proves it needs one.
String buildPublishSegment(String resolved, {String? idempotencyKey}) {
  if (resolved.isEmpty) return '';
  final String safe = resolved.replaceAll(separator[0], ' ');
  final String key = idempotencyKey ?? const Uuid().v4();
  return '$safe${separator[8]}_k${separator[2]}$key';
}

/// The 6th `⬤` segment of a history record's `tb` — the publish segment.
/// Length-guarded: every shorter legacy `tb` form yields ''.
String publishSegmentFromTb(String rawTb) {
  final List<String> parts = rawTb.split(separator[0]);
  return parts.length > 5 ? parts[5] : '';
}

// ===========================================================================
// Photo references
// ===========================================================================

/// Value separators used in this codebase that can never occur inside a Firebase
/// download URL. They terminate the URL match, so a space-joined OR `◇`-joined
/// multi-photo value converts every URL it holds. `forbiddenCharacter` contains
/// no ASCII, so nothing legal in a URL is caught here.
final String _urlStopClass =
    '\\s${forbiddenCharacter.map(RegExp.escape).join()}';

final RegExp _storageUrlRe = RegExp(
  'https://firebasestorage\\.googleapis\\.com/v0/b/'
  '([^/$_urlStopClass]+)/o/([^?$_urlStopClass]*)(\\?[^$_urlStopClass]*)?',
  caseSensitive: false,
);

/// Rewrite every Firebase Storage download URL inside [value] as
/// `gs://<bucket>/<decoded path>`, and blank the lost-photo placeholder.
///
/// ORDER MATTERS: [defaultImage] IS a download URL, so it is removed BEFORE the
/// regex runs. Otherwise a lost photo would publish a real object path in another
/// project's bucket instead of "no photo".
String convertStorageUrls(String value) {
  final String withoutPlaceholder = value.replaceAll(defaultImage, '');
  return withoutPlaceholder.replaceAllMapped(_storageUrlRe, (Match m) {
    final String bucket = m.group(1) ?? '';
    final String encodedPath = m.group(2) ?? '';
    String path;
    try {
      path = Uri.decodeComponent(encodedPath);
    } catch (_) {
      path = encodedPath; // malformed %-escape: keep it verbatim
    }
    return 'gs://$bucket/$path';
  });
}

// ===========================================================================
// Builder
// ===========================================================================

/// Outcome of turning one publish segment into an outbox entry.
class LedgerBuild {
  LedgerBuild._(
    this.entry,
    this.reason,
    this.key,
    this.ledgerCode,
    this.placeholderDropped,
  );

  factory LedgerBuild.ok(LedgerEntry e, {bool placeholderDropped = false}) =>
      LedgerBuild._(e, '', e.key, e.ledgerCode, placeholderDropped);

  factory LedgerBuild.invalid(
    String reason, {
    String key = '',
    String ledgerCode = '',
  }) => LedgerBuild._(null, reason, key, ledgerCode, false);

  /// null when the config is invalid.
  final LedgerEntry? entry;

  /// Why the config was rejected. NEVER contains the payload.
  final String reason;

  final String key;
  final String ledgerCode;

  /// A lost-photo placeholder was blanked — data loss worth reporting.
  final bool placeholderDropped;

  bool get valid => entry != null;
}

/// Build one outbox entry from a decoded publish segment.
///
/// Pure: every environment value is a parameter, so this runs in plain
/// `flutter_test` with no Firebase and no `globalInit`.
LedgerBuild buildLedgerEntry(
  String segment,
  List<dynamic> ref, {
  required int tableVid,
  required int appVid,
  required int timeReceived,
  required String receivingPage,
  required String uid,
}) {
  final Map<String, dynamic> parsed = parseAddToEvent(segment);
  final String key = (parsed['_k'] ?? '').toString().trim();
  final String ledgerCode = (parsed['_collection'] ?? '').toString().trim();
  if (!_ledgerCodeRe.hasMatch(ledgerCode)) {
    return LedgerBuild.invalid(
      'ledgerCode "$ledgerCode" does not match ^[A-Z0-9]{4,16}\$',
      key: key,
    );
  }
  final int? schemaVersion = int.tryParse(
    (parsed['_v'] ?? '').toString().trim(),
  );
  if (schemaVersion == null) {
    return LedgerBuild.invalid(
      '_v is missing or not an int',
      key: key,
      ledgerCode: ledgerCode,
    );
  }
  if (key.length < 16 || key.length > 128) {
    return LedgerBuild.invalid(
      '_k length ${key.length} outside 16..128',
      key: key,
      ledgerCode: ledgerCode,
    );
  }

  bool placeholderDropped = false;
  final Map<String, String> data = <String, String>{};
  parsed.forEach((String k, dynamic v) {
    if (k == '_collection') return; // write target, not a field
    if (k.startsWith('_'))
      return; // meta (_v, _k, unknown _x) never enters data
    final String resolved = resolveValueTokens(
      v.toString(),
      ref,
      tableVid: tableVid,
      appVid: appVid,
      timeReceived: timeReceived,
      receivingPage: receivingPage,
    );
    if (resolved.contains(defaultImage)) placeholderDropped = true;
    data[k] = convertStorageUrls(resolved);
  });
  // App-owned key: always injected, and a config-written actionAt is overwritten.
  data['actionAt'] = timeReceived.toString();

  // Encoded ONCE and stored as a string: every retry must send byte-identical
  // bytes or the gateway answers 409 idempotency_conflict.
  final String body = jsonEncode(<String, dynamic>{
    'schemaVersion': schemaVersion,
    'data': data,
  });
  final int bytes = utf8.encode(body).length;
  if (bytes > ledgerMaxBodyBytes) {
    return LedgerBuild.invalid(
      'body $bytes bytes > $ledgerMaxBodyBytes',
      key: key,
      ledgerCode: ledgerCode,
    );
  }
  return LedgerBuild.ok(
    LedgerEntry(
      key: key,
      uid: uid,
      ledgerCode: ledgerCode,
      body: body,
      actionAt: timeReceived,
      historyId: timeReceived,
    ),
    placeholderDropped: placeholderDropped,
  );
}

// ===========================================================================
// Outbox store
// ===========================================================================

List<LedgerEntry>? _outbox;

/// The single in-flight load, shared by concurrent first callers (the un-awaited
/// drain and the next tick's enqueue) so they cannot build two separate lists.
Future<List<LedgerEntry>>? _outboxLoading;

/// Decode the stored `_LEDGER_OUTBOX` blob. Pure: null / '' / 'null' / a
/// non-list / a malformed blob all yield an empty list; malformed input is
/// reported through [onError] with a message that NEVER contains the blob
/// (`FormatException.toString()` embeds the source, and the source holds
/// encoded request bodies).
List<LedgerEntry> decodeLedgerOutbox(
  String? raw, {
  void Function(String message) onError = errorReport,
}) {
  final List<LedgerEntry> loaded = <LedgerEntry>[];
  if (raw == null || raw.isEmpty || raw == 'null') return loaded;
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is List) {
      for (final dynamic e in decoded) {
        if (e is Map) {
          loaded.add(LedgerEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
  } catch (e) {
    final String why = e is FormatException
        ? e.message
        : e.runtimeType.toString();
    onError('ledger outbox decode failed (${raw.length} chars): $why');
  }
  return loaded;
}

/// Encode the outbox for storage. Pure.
String encodeLedgerOutbox(List<LedgerEntry> entries) =>
    jsonEncode(entries.map((LedgerEntry e) => e.toJson()).toList());

/// Lazily load the outbox from secure storage.
///
/// NEVER persist before this has succeeded: a blank in-memory list overwriting
/// the stored one is exactly how `_HISTORY` was once wiped (checkTable /
/// saveHistory). Reads `storage` DIRECTLY, not via `secureRead`: `secureRead`
/// returns null for BOTH "key absent" and "read threw", and treating a failed
/// read as an empty outbox would let the next persist wipe the stored queue.
/// A throw here leaves `_outbox` null (so `saveLedgerOutbox` stays a no-op) and
/// the next call retries; the caller reports it.
Future<List<LedgerEntry>> loadLedgerOutbox() {
  final List<LedgerEntry>? cached = _outbox;
  if (cached != null) return Future<List<LedgerEntry>>.value(cached);
  return _outboxLoading ??= _readLedgerOutbox().whenComplete(() {
    _outboxLoading = null;
  });
}

Future<List<LedgerEntry>> _readLedgerOutbox() async {
  final String? raw = await storage.read(key: ledgerOutboxName); // may throw
  final List<LedgerEntry> loaded = decodeLedgerOutbox(raw);
  // `??=`: if clearLedgerOutbox ran while this read was in flight, the clear
  // wins — a signed-out user's entries must not be resurrected.
  return _outbox ??= loaded;
}

/// Persist the in-memory outbox. No-op until a load has SUCCEEDED.
Future<void> saveLedgerOutbox() async {
  final List<LedgerEntry>? current = _outbox;
  if (current == null) return;
  await secureWrite(key: ledgerOutboxName, value: encodeLedgerOutbox(current));
}

/// Test seam: forget the cached outbox so the load path can be exercised again.
@visibleForTesting
void resetLedgerOutboxForTest() {
  _outbox = null;
  _outboxLoading = null;
}

/// Drop `failed` entries older than [ledgerFailedMaxDayAge] days. Returns how
/// many were removed so the caller can decide whether to persist.
int trimLedgerOutbox(List<LedgerEntry> entries, int nowMs) {
  final int cutoff = nowMs - ledgerFailedMaxDayAge * 86400000;
  final int before = entries.length;
  entries.removeWhere(
    (LedgerEntry e) => e.failed && e.failedAt > 0 && e.failedAt < cutoff,
  );
  return before - entries.length;
}

/// Wipe the outbox. Called from `signOut`, next to the `_HISTORY` clear.
Future<void> clearLedgerOutbox() async {
  _outbox = <LedgerEntry>[];
  _outboxLoading = null;
  await secureWrite(key: ledgerOutboxName, value: 'null');
}

// ===========================================================================
// Enqueue
// ===========================================================================

/// Decide what [enqueueLedgerPublish] should append.
///
/// Returns null when [key] is already queued — THE idempotency guarantee: a
/// record can re-enter historySync's send block on a later cycle (allFailed
/// retry, image defer), and re-enqueuing would publish the same action twice once
/// the gateway's 24 h window lapsed. Pure, so it is testable without Firebase.
LedgerEntry? ledgerEntryToAppend(
  List<LedgerEntry> entries,
  LedgerBuild built, {
  required String key,
  required String uid,
  required int historyId,
  required int nowMs,
}) {
  if (entries.any((LedgerEntry e) => e.key == key)) return null;
  final LedgerEntry? ok = built.entry;
  if (ok != null) return ok;
  // Invalid config: stored as failed immediately, with NO body, never sent.
  return LedgerEntry(
    key: key,
    uid: uid,
    ledgerCode: built.ledgerCode,
    body: '',
    actionAt: historyId,
    historyId: historyId,
    failed: true,
    error: 'invalid_config',
    failedAt: nowMs,
  );
}

/// Move one publish segment out of the history record into the outbox.
///
/// NEVER tallied by `historySync`: it does not touch `opsAttempted` /
/// `opsSucceeded`, so the queue's send / retry / partial / drop semantics stay
/// byte-identical (owner decision K4).
Future<void> enqueueLedgerPublish(String segment, String eventRowString) async {
  final List<dynamic> eventRow = jsonDecode(eventRowString) as List<dynamic>;
  final List<dynamic> ref = parseEventString(eventRow);
  final int timeReceived = eventRow.isNotEmpty
      ? (int.tryParse(eventRow[0].toString()) ?? 0)
      : 0;
  final String receivingPage = eventRow.length > 1
      ? eventRow[1].toString()
      : '';
  final int tableVid = appCodeController.applicationTableVid;
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  // autheniumDecode already ran at compose time — do NOT decode again.
  final LedgerBuild built = buildLedgerEntry(
    segment,
    ref,
    tableVid: tableVid,
    appVid: tableVid,
    timeReceived: timeReceived,
    receivingPage: receivingPage,
    uid: uid,
  );
  final String key = built.key.isEmpty ? 'invalid-$timeReceived' : built.key;
  final List<LedgerEntry> outbox = await loadLedgerOutbox();
  final LedgerEntry? toAppend = ledgerEntryToAppend(
    outbox,
    built,
    key: key,
    uid: uid,
    historyId: timeReceived,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );
  if (toAppend == null) {
    devPrint('[ledger] enqueue skipped, key already queued');
    return;
  }
  if (!built.valid) {
    errorReport(
      'ledger publish invalid config historyId=$timeReceived '
      'ledgerCode=${built.ledgerCode} key=$key: ${built.reason}',
    );
  } else if (built.placeholderDropped) {
    errorReport(
      'ledger publish photo lost (placeholder blanked) '
      'historyId=$timeReceived ledgerCode=${built.ledgerCode} key=$key',
    );
  }
  outbox.add(toAppend);
  await saveLedgerOutbox();
  devPrint('[ledger] enqueued ${toAppend.ledgerCode} key=$key');
}

// ===========================================================================
// Drain
// ===========================================================================

/// Injectable seams for [runLedgerDrain] so the decision logic is testable with
/// an in-memory list and a MockClient — no Firebase, no secure storage.
class LedgerDrainDeps {
  LedgerDrainDeps({
    required this.entries,
    required this.persist,
    required this.send,
    required this.nowMs,
    required this.currentUid,
  });

  /// The live outbox. Mutated in place (entries removed on success).
  final List<LedgerEntry> entries;

  /// Called after EVERY mutation.
  final Future<void> Function() persist;

  /// One POST attempt. Must never throw.
  final Future<PublishOutcome> Function(LedgerEntry entry) send;

  final int nowMs;
  final String currentUid;
}

/// FIFO drain decisions (oldest `actionAt` first).
///
/// Stops the whole cycle on `retryable` (a down gateway must not burn N × 15 s)
/// and on `unauthenticated` (every entry would fail the same way, and a
/// background job never signs the user out). A `rejected` entry is marked failed
/// and the cycle CONTINUES.
Future<void> runLedgerDrain(LedgerDrainDeps d) async {
  // Keep one debug log line readable — a body can reach 256 KiB.
  String clip(String s) =>
      s.length <= 2000 ? s : '${s.substring(0, 2000)}… (${s.length} chars)';
  final List<LedgerEntry> ordered = List<LedgerEntry>.from(d.entries)
    ..sort((LedgerEntry a, LedgerEntry b) => a.actionAt.compareTo(b.actionAt));
  for (final LedgerEntry e in ordered) {
    if (e.failed) continue;
    if (e.notBefore > d.nowMs) continue;
    if (e.uid.isNotEmpty && e.uid != d.currentUid) continue;
    if (e.uid.isEmpty) {
      errorReport(
        'ledger publish attribution fallback: entry ${e.key} has no uid, '
        'sending as the current user',
      );
      e.uid = d.currentUid; // adopt, so this reports once per entry
    }
    if (e.attempted && (d.nowMs - e.actionAt) > ledgerIdempotencyWindowMs) {
      errorReport(
        'ledger publish unknown-outcome entry older than 24h; sending anyway '
        'ledgerCode=${e.ledgerCode} key=${e.key}',
      );
    }
    e.attempted = true;
    await d.persist(); // BEFORE the POST — see LedgerEntry.attempted
    // DEBUG builds only (devPrint is silent in release): payload and response
    // stay out of Crashlytics — FLUTTER.md §6 "jangan log payload".
    devPrint(
      '[ledger] request ${e.ledgerCode} key=${e.key} body=${clip(e.body)}',
    );
    final PublishOutcome out = await d.send(e);
    devPrint(
      '[ledger] response ${e.ledgerCode} status=${out.statusCode ?? '-'} '
      'outcome=${out.kind.name} error=${out.errorCode} '
      'body=${clip(out.responseBody)}',
    );
    switch (out.kind) {
      case PublishOutcomeKind.success:
        d.entries.remove(e);
        await d.persist();
        devPrint(
          '[ledger] published ${e.ledgerCode} duplicate=${out.duplicate}',
        );
        break;
      case PublishOutcomeKind.rejected:
        e.failed = true;
        e.error = out.errorCode;
        e.errorId = out.errorId;
        e.failedAt = d.nowMs;
        await d.persist();
        errorReport(
          'ledger publish rejected ledgerCode=${e.ledgerCode} key=${e.key} '
          'status=${out.statusCode} error=${out.errorCode} '
          'errorId=${out.errorId}',
        );
        break;
      case PublishOutcomeKind.unauthenticated:
        devPrint('[ledger] unauthenticated, stopping cycle (no signOut)');
        return;
      case PublishOutcomeKind.retryable:
        e.notBefore = d.nowMs + (out.retryAfterSeconds ?? 0) * 1000;
        await d.persist();
        devPrint('[ledger] retryable ${out.errorCode}, stopping cycle');
        return;
    }
  }
}

/// Fire-and-forget drain, kicked once at the end of `historySync` via
/// `safeUnawaited`. It must NEVER throw.
Future<void> drainLedgerOutbox(String source) async {
  final String caller = 'drainLedgerOutbox $source';
  if (!ledgerDrainLock.queueLock(caller)) {
    devPrint('[ledger] drain skipped, already running');
    return;
  }
  try {
    final List<LedgerEntry> outbox = await loadLedgerOutbox();
    if (trimLedgerOutbox(outbox, DateTime.now().millisecondsSinceEpoch) > 0) {
      await saveLedgerOutbox();
    }
    if (outbox.isEmpty) return;
    final Uri? base = parseGatewayBaseUrl(gatewayUrl);
    if (base == null) {
      if (!_gatewayUrlReported) {
        _gatewayUrlReported = true;
        errorReport(
          'ledger publish disabled: GATEWAY_URL is empty or not a bare '
          'absolute https URL (no path); '
          '${outbox.length} entr(ies) stay queued',
        );
      }
      return;
    }
    if (!internetConnected()) return;
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // auth restore takes seconds after a cold start
    final http.Client client = http.Client();
    try {
      await runLedgerDrain(
        LedgerDrainDeps(
          entries: outbox,
          persist: saveLedgerOutbox,
          nowMs: DateTime.now().millisecondsSinceEpoch,
          currentUid: user.uid,
          send: (LedgerEntry e) => publishToGateway(
            client: client,
            baseUrl: base,
            getIdToken: ({bool forceRefresh = false}) =>
                FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh) ??
                Future<String?>.value(),
            ledgerCode: e.ledgerCode,
            idempotencyKey: e.key,
            body: e.body,
          ),
        ),
      );
    } finally {
      client.close();
    }
  } catch (e) {
    errorReport('drainLedgerOutbox($source) failed: $e');
  } finally {
    ledgerDrainLock.queueUnlock(caller);
  }
}
