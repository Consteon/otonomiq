/// Public keyring sync for Scheme 3 QR verification.
///
/// The keys live in Firebase project `authenium-prod1`; this app's default
/// FirebaseApp is `otq-01` (`lib/firebase_options.dart`, `lib/main.dart`). So
/// `FirebaseFirestore.instance` is the WRONG instance here -- it would read
/// `otq-01/public_keys`, which does not exist, take the `snapshot.exists` false
/// branch, keep an empty keyring, and reject every scan with no error and no
/// log. A second, named FirebaseApp is what makes this work.
///
/// The second app carries NO auth session: the user's Firebase login belongs to
/// the default app. Rules on authenium-prod1 therefore see `request.auth ==
/// null` for every read here.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../crypto/auth_crypto.dart';
import '../global.dart';

/// Name of the SECOND FirebaseApp. The default app stays on otq-01 and is not
/// touched: FCM, Crashlytics, Storage, Auth and every table keep using it.
const String _kAutheniumApp = 'authenium';

/// Firestore collection holding one public-key document per tenant.
const String _kPublicKeysCollection = 'public_keys';

/// Options for authenium-prod1.
///
/// Kept here rather than in `lib/firebase_options.dart` because flutterfire
/// regenerates that file and would drop them.
///
/// `apiKey` and `appId` identify the registered Android / iOS app, not the
/// project, so they differ per platform -- hence the switch below, mirroring
/// `DefaultFirebaseOptions.currentPlatform`. `messagingSenderId` (the project
/// number) is shared.
///
/// These are client identifiers, not secrets: they ship inside every app
/// binary. What protects the data is the Firestore rules on authenium-prod1.
const FirebaseOptions _kAutheniumAndroid = FirebaseOptions(
  apiKey: 'AIzaSyAMi4wJ5sSIMKO7479ztSOgYlggozsMjRY',
  appId: '1:63888045044:android:110194406fa0818adeffa1',
  messagingSenderId: '63888045044',
  projectId: 'authenium-prod1',
);

/// `iosBundleId` is deliberately omitted: it is optional, and when absent the
/// iOS SDK uses the running app's own bundle identifier -- which is what we
/// want, and one fewer value to keep in sync with the white-label builds.
const FirebaseOptions _kAutheniumIos = FirebaseOptions(
  apiKey: 'AIzaSyCpT1hgClvQ44vWswMSDlh1uNSqIRx_DQU',
  appId: '1:63888045044:ios:215ed1eca066c5d0deffa1',
  messagingSenderId: '63888045044',
  projectId: 'authenium-prod1',
);

FirebaseOptions get _autheniumOptions =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? _kAutheniumIos
        : _kAutheniumAndroid;

/// Every trusted key, merged across tenants and indexed by key version.
///
/// Keyed by the tenant filter the caller asked for: `''` = all tenants.
final Map<String, Scheme3Keyring> _keyring = {};

/// Completes on the first snapshot for a filter (served from cache offline).
final Map<String, Completer<void>> _firstLoad = {};

final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
    _subs = {};

FirebaseFirestore? _db;

/// How long a caller waits for the very first snapshot before giving up and
/// answering with whatever is cached (nothing, on a cold start).
const Duration _kFirstLoadTimeout = Duration(seconds: 5);

/// Lazily creates the second FirebaseApp and its Firestore instance.
///
/// Lazy on purpose: this must NOT join the boot path in `main()`. Screens that
/// never scan a Scheme 3 QR never pay for it.
Future<FirebaseFirestore> _autheniumDb() async {
  if (_db != null) return _db!;

  // Look the app up before creating it: on hot restart the native app survives
  // and a second initializeApp with the same name throws 'duplicate-app'.
  final Iterable<FirebaseApp> existing =
      Firebase.apps.where((a) => a.name == _kAutheniumApp);
  final FirebaseApp app = existing.isNotEmpty
      ? existing.first
      : await Firebase.initializeApp(
          name: _kAutheniumApp,
          options: _autheniumOptions,
        );

  final FirebaseFirestore db = FirebaseFirestore.instanceFor(app: app);
  // Settings are per-instance and must be set before this instance's first
  // use. main.dart only pins the DEFAULT instance.
  db.settings = const Settings(persistenceEnabled: true);
  return _db = db;
}

/// Returns the trusted keyring, starting the live listener on the first call
/// and awaiting its first snapshot.
///
/// [tenantId] empty (the default) trusts EVERY tenant published in
/// `public_keys`: a badge verifies if any published key of its version accepts
/// it. That is a deliberate relaxation — the crypto layer then no longer draws
/// a tenant boundary, and the workforce table lookup is what decides whether a
/// holder belongs here. Passing a tenant id restores the boundary by trusting
/// only that document.
///
/// Never throws. On any failure it returns whatever keyring is already cached,
/// which is empty on a cold first call -- the caller then reports
/// [Scheme3Status.unknownKeyVersion], which is the honest answer.
Future<Scheme3Keyring> autheniumKeys({String tenantId = ''}) async {
  final String filter = tenantId.trim();

  if (_subs.containsKey(filter)) {
    // Listener already running; wait for the first load if it has not landed.
    final Completer<void>? first = _firstLoad[filter];
    if (first != null && !first.isCompleted) {
      await first.future.timeout(_kFirstLoadTimeout, onTimeout: () {});
    }
    return _keyring[filter] ?? const {};
  }

  final Completer<void> first = Completer<void>();
  _firstLoad[filter] = first;

  try {
    final FirebaseFirestore db = await _autheniumDb();
    // The whole collection, so a tenant added later needs no app change. One
    // document per tenant, three today -- a cheap listener either way.
    Query<Map<String, dynamic>> query = db.collection(_kPublicKeysCollection);
    if (filter.isNotEmpty) {
      query = query.where(FieldPath.documentId, isEqualTo: filter);
    }
    _subs[filter] = query.snapshots().listen((snap) {
      // Nothing in this body may throw. An uncaught error inside a snapshot
      // listener is an uncaught async error, which this app reports as a
      // Crashlytics FATAL.
      try {
        final Scheme3Keyring parsed = autheniumMergeKeyDocs(
            snap.docs.map((d) => d.data()).toList());
        // Anti-clobber floor: an empty or unparseable snapshot must never wipe
        // a keyring that is already working. Same failure class as the
        // getLqrList bug, where an error path overwrote #LQR_LIST and its cache
        // with an empty map.
        if (parsed.isNotEmpty) {
          _keyring[filter] = parsed;
          devPrint('autheniumKeys ${filter.isEmpty ? '<all tenants>' : filter}'
              ': ${snap.docs.length} doc(s), '
              '${parsed.entries.map((e) => 'v${e.key}x${e.value.length}').join(' ')}');
        } else {
          devPrint('autheniumKeys $filter: empty snapshot ignored, keeping '
              '${_keyring[filter]?.length ?? 0} version(s)');
        }
      } catch (e) {
        devPrint('autheniumKeys $filter parse error: $e');
      }
      if (!first.isCompleted) first.complete();
    }, onError: (Object e) {
      // Offline, or permission denied. Cached keys stay usable.
      devPrint('autheniumKeys $filter listener error: $e');
      if (!first.isCompleted) first.complete();
    });
  } catch (e) {
    devPrint('autheniumKeys $filter init error: $e');
    if (!first.isCompleted) first.complete();
    return _keyring[filter] ?? const {};
  }

  await first.future.timeout(_kFirstLoadTimeout, onTimeout: () {});
  return _keyring[filter] ?? const {};
}

/// Merges any number of `public_keys/{tenantId}` documents into one keyring.
///
/// Two tenants publishing a version `1` contribute two candidates under key
/// `1`; [decodeScheme3] tries each. Duplicate bytes are collapsed so a repeated
/// key is not verified twice.
///
/// Exported so the merge rules are unit-testable without Firebase.
Scheme3Keyring autheniumMergeKeyDocs(List<Map<String, dynamic>?> docs) {
  final Scheme3Keyring out = {};
  for (final doc in docs) {
    autheniumParseKeyDoc(doc).forEach((version, bytes) {
      final List<List<int>> slot = out.putIfAbsent(version, () => []);
      final String fingerprint = bytes.join(',');
      if (!slot.any((k) => k.join(',') == fingerprint)) slot.add(bytes);
    });
  }
  return out;
}

/// Turns ONE `public_keys/{tenantId}` document into version -> 32 bytes.
///
/// Shape: `{ keys: {"1": "<64-char hex>"}, latest_version: 1, tenant_id: "..." }`.
///
/// `latest_version` is deliberately ignored: it tells the SIGNER which key to
/// sign with, while a verifier must accept EVERY listed version. Honouring it
/// would reject every badge minted before the last rotation.
///
/// Entries that do not parse are skipped rather than fatal -- one bad key must
/// not disable the others.
Map<int, List<int>> autheniumParseKeyDoc(Map<String, dynamic>? data) {
  final Object? rawKeys = data?['keys'];
  if (rawKeys is! Map) return const {};

  final Map<int, List<int>> out = {};
  rawKeys.forEach((k, v) {
    // No null-check on `v`: `null.toString()` is 'null', which is not 32 bytes,
    // so the length guard below already drops it. A mutation run proved an
    // explicit check here changes nothing.
    final int? version = int.tryParse(k.toString().trim());
    if (version == null) return;
    final List<int> bytes = scheme3ParseKey(v.toString());
    if (bytes.length == 32) out[version] = bytes;
  });
  return out;
}

/// Drops every listener and cached key. Test/diagnostic hook only -- the app
/// keeps its listeners for its whole lifetime.
@visibleForTesting
Future<void> autheniumResetKeys() async {
  for (final sub in _subs.values) {
    await sub.cancel();
  }
  _subs.clear();
  _firstLoad.clear();
  _keyring.clear();
  _db = null;
}
