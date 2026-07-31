import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'global.dart';
import 'redux/screen_transaction.dart'
    show ScreenTransaction, UpdateScreenTxAction;

// ---------------------------------------------------------------------------
// Notification channel constants
// ---------------------------------------------------------------------------
const _androidChannelId = 'otonomiq_push_channel';
const _androidChannelName = 'Push Notifications';
const _androidChannelDesc = 'Incoming push notifications from otonomiq';

// ---------------------------------------------------------------------------
// Payload parser (pure, tested in test/fcm_bridge_test.dart)
// ---------------------------------------------------------------------------

/// Parses an FCM data payload into Firestore-ready document maps.
/// Returns null if [data] is missing the required 'threadVid' key.
/// [nowMs] overrides timestamp for testability.
Map<String, dynamic>? parseFcmPayload(Map<String, dynamic> data, {int? nowMs}) {
  final threadVid = data['threadVid'] as String?;
  if (threadVid == null || threadVid.isEmpty) return null;

  final tStamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final dp = (data['dp'] ?? '') as String;
  final dt = (data['dt'] ?? '') as String;
  final nm = (data['nm'] ?? '') as String;
  final pp = (data['pp'] ?? '') as String;
  final route = (data['route'] ?? '') as String;

  return {
    'threadVid': threadVid,
    'msgDoc': <String, dynamic>{
      'dp': dp,
      'dt': dt,
      'tr': tStamp,
      'im': true,
      'id': '',
      'st': 0,
      'rt': route,
    },
    'threadUpdate': <String, dynamic>{
      'nm': nm,
      'pp': pp,
      'lm': dp,
      'lt': tStamp,
    },
  };
}

// ---------------------------------------------------------------------------
// Bridge: write parsed push data into in-app inbox Firestore collections.
// Callable from both foreground (main isolate) and background (own isolate).
// ---------------------------------------------------------------------------

/// Writes a push message into the inbox Firestore collections.
/// [ioPath] is the firestoreIO path, e.g. `msg_DEV2/<myMsgId>/io`.
/// Silently no-ops on invalid payload or missing ioPath.
Future<void> bridgePushToInbox(
  String? ioPath,
  Map<String, dynamic> data,
) async {
  if (ioPath == null || ioPath.isEmpty) return;

  final parsed = parseFcmPayload(data);
  if (parsed == null) return; // missing threadVid

  final threadVid = parsed['threadVid'] as String;
  final msgDoc = parsed['msgDoc'] as Map<String, dynamic>;
  final threadUpdate = parsed['threadUpdate'] as Map<String, dynamic>;

  try {
    // 1. Write message doc (mirrors sendMessage pattern at api.dart:1482-1490)
    final msgCollRef = FirebaseFirestore.instance.collection(
      '$ioPath/$threadVid/msg',
    );
    final docRef = await msgCollRef.add(msgDoc);

    // 2. Update message 'id' field with the auto-generated doc ID
    //    (inline safeFsUpdate pattern -- safeFsUpdate is in global.dart,
    //    not available in background isolate)
    docRef.update({'id': docRef.id}).catchError((Object e) {
      // ponytail: fire-forget; message is already written, id field is cosmetic
    });

    // 3. Update/create thread doc (mirrors sendMessage pattern at api.dart:1497-1502)
    final threadRef = FirebaseFirestore.instance.doc('$ioPath/$threadVid');
    await FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      final snapshot = await tx.get<Map<String, dynamic>>(threadRef);
      if (snapshot.exists) {
        final currentUrd = (snapshot.data()?['urd'] ?? 0) as int;
        tx.update(threadRef, {...threadUpdate, 'urd': currentUrd + 1});
      } else {
        // New thread -- create with urd=1 and la=0
        tx.set(threadRef, {...threadUpdate, 'urd': 1, 'la': 0});
      }
    });
  } catch (e) {
    // ponytail: Firestore SDK queues writes when offline; errors here are
    // permission/corruption -- log but don't crash. errorReport is not
    // available in the background isolate, so use debugPrint.
    // ignore: avoid_print
    print('[fcm_bridge] bridgePushToInbox error: $e');
  }
}

// ---------------------------------------------------------------------------
// Local notification display
// ---------------------------------------------------------------------------

/// Initializes flutter_local_notifications plugin.
/// Returns the plugin instance. [onTap] is only wired in the main isolate
/// (foreground); background handler passes null.
Future<FlutterLocalNotificationsPlugin> _initLocalNotifications({
  void Function(NotificationResponse)? onTap,
}) async {
  final flnp = FlutterLocalNotificationsPlugin();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  await flnp.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
    onDidReceiveNotificationResponse: onTap,
  );

  // Create Android notification channel (idempotent -- safe to call repeatedly)
  final androidPlugin = flnp
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDesc,
        importance: Importance.high,
      ),
    );
  }

  return flnp;
}

/// Shows a local notification with the given title and body.
/// [route] is stored in the payload for deeplink on tap.
Future<void> _showLocalNotification(
  FlutterLocalNotificationsPlugin flnp,
  String title,
  String body, {
  String? route,
}) async {
  const androidDetails = AndroidNotificationDetails(
    _androidChannelId,
    _androidChannelName,
    channelDescription: _androidChannelDesc,
    importance: Importance.high,
    priority: Priority.high,
  );
  const iosDetails = DarwinNotificationDetails();
  const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await flnp.show(
    DateTime.now().millisecondsSinceEpoch.remainder(
      1 << 31,
    ), // ms-res id, fits 32-bit
    title,
    body,
    details,
    payload: route ?? '',
  );
}

// ---------------------------------------------------------------------------
// Deeplink helper (main isolate only -- uses globals from global.dart)
// ---------------------------------------------------------------------------

/// Navigates to [route] using the exact pattern from message_list.dart:115-133.
/// No-ops if route is empty or the page is not loaded.
void _handleDeeplink(String? route) {
  if (route == null || route.isEmpty) return;
  if (linkElement[route] == null) return; // page not loaded in SDUI cache
  routeStack.push(route); // MUST push before nav (routeStack invariant)
  List<Widget> newElementList = reloadPage(route);
  rootThis.setState(() {
    rootThis.byPass = 0;
    rootThis.pageName = route;
    rootThis.pageElements = newElementList;
  });
}

// ---------------------------------------------------------------------------
// Secure storage helper for background isolate
// ---------------------------------------------------------------------------

/// Creates a FlutterSecureStorage with the same options as global.dart:628-650.
/// Needed in background handler where the global [storage] is not available.
FlutterSecureStorage _bgSecureStorage() {
  if (Platform.isIOS) {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
  }
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(migrateWithBackup: true),
  );
}

/// Reads myCluster + myMsgId from secure storage and constructs the IO path.
/// Returns null if user is not logged in (keys missing).
Future<String?> _resolveIOPath({FlutterSecureStorage? store}) async {
  final ss = store ?? _bgSecureStorage();
  final myCluster = await ss.read(key: 'myCluster');
  final myMsgId = await ss.read(key: 'myMsgId');
  if (myCluster == null || myMsgId == null) return null;
  return msgIoPath(myCluster, myMsgId); // same shape as api.dart:2162
}

// ---------------------------------------------------------------------------
// Main class -- called from global.dart:1660 and api.dart:3279
// ---------------------------------------------------------------------------

class FirebaseNotifications {
  /// Pending deeplink route from cold-start notification tap.
  /// Checked by main_page after screens are loaded.
  static String? _pendingDeeplinkRoute;

  /// Guards against double listener registration: setUpFirebase is called from
  /// BOTH the login paths (launchCheck / launchCheckDemo) AND the warm-start
  /// path (asyncAppStartup2). Resets on hot-restart / process restart (fresh
  /// statics), so FCM is re-armed every launch but only once per session.
  static bool _isSetUp = false;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> setUpFirebase() async {
    if (_isSetUp) return;
    _isSetUp = true;
    devPrint('[fcm] setUpFirebase START');
    await _requestPermission();
    await _logApnsToken();
    await _registerToken();
    _listenTokenRefresh();

    // Init local notifications with tap handler (main isolate)
    final flnp = await _initLocalNotifications(
      onTap: (NotificationResponse response) {
        _handleDeeplink(response.payload);
      },
    );

    // Check if app was launched by tapping a local notification (cold start)
    final launchDetails = await flnp.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingDeeplinkRoute = launchDetails!.notificationResponse?.payload;
    }

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // Resolve the inbox path from secure storage, exactly like the background
      // handler below. Trusting the global `firestoreIO` MISFILED every
      // foreground push: on a warm start the global sits at its boot default
      // `users_<fsName>` (global.dart:762/863), so threads and messages were
      // written into the users collection while the real inbox
      // (`msg_<clt>/<msgId>/io`) stayed empty. Background pushes used the
      // secure-storage path, so the same account's history ended up split
      // across two collections. Global kept only as a pre-login fallback.
      final ioPath = (await _resolveIOPath()) ?? (firestoreIO as String?);
      // `data` alone is not enough to tell "sender sent nothing" from "sender
      // put the payload in the notification block instead of data" -- the two
      // look identical from `${message.data}` and need opposite fixes.
      devPrint(
        '[fcm] onMessage: data=${message.data}'
        ' notif=${message.notification?.title}/${message.notification?.body}'
        ' msgId=${message.messageId} ca=${message.contentAvailable}'
        '  io=$ioPath',
      );
      // Bridge: write to inbox Firestore (snapshots() auto-updates UI)
      await bridgePushToInbox(ioPath, message.data);
      // Show local notification (Android does not auto-display in foreground)
      // Fall back to the notification block: a notification-only push carries
      // no 'nm'/'dp' data keys, and without this the banner rendered blank --
      // the push looked like it never arrived at all.
      final dp =
          (message.data['dp'] ?? message.notification?.body ?? '') as String;
      final nm =
          (message.data['nm'] ?? message.notification?.title ?? '') as String;
      final route = (message.data['route'] ?? '') as String;
      if (nm.isNotEmpty || dp.isNotEmpty) {
        await _showLocalNotification(flnp, nm, dp, route: route);
      }
    });

    // App brought to foreground by tapping an FCM notification.
    // With data-only messages this won't fire, but wired as safety net
    // for future notification+data messages.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      devPrint('[fcm] onMessageOpenedApp: ${message.data}');
      _handleDeeplink(message.data['route'] as String?);
    });

    // Cold-start FCM notification tap (safety net, same caveat as above).
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      devPrint('[fcm] getInitialMessage: ${initialMessage.data}');
      // Store for deferred processing -- screens may not be loaded yet
      _pendingDeeplinkRoute ??= initialMessage.data['route'] as String?;
    }

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(myBackgroundMessageHandler);

    // Cold-start deeplink: _pendingDeeplinkRoute is now populated (if the app
    // was launched by a notification tap). setUpFirebase runs post-login, so
    // defer to after the next frame — by then the SDUI page cache (linkElement)
    // is built and _handleDeeplink can navigate (else it no-ops safely).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      processPendingDeeplink();
    });
  }

  /// Request notification permission (iOS always, Android 13+).
  Future<void> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    // On Android 13+ this triggers the system POST_NOTIFICATIONS dialog.
    // On iOS this triggers the standard push permission dialog.
    // On older Android this is a no-op (permission granted at install).
    //
    // The result was previously discarded. A `denied` status means iOS shows no
    // banner no matter what the sender does, and it is indistinguishable from a
    // routing problem unless it is logged.
    devPrint('[fcm] permission: ${settings.authorizationStatus}');
  }

  /// Logs the APNs device token on iOS.
  ///
  /// This is the one value that explains "FCM token looks fine but zero pushes
  /// arrive": on iOS every FCM message rides APNs, so with no APNs token FCM has
  /// nothing to route to and drops the send server-side. The FCM token stays
  /// valid-looking the whole time, which is why [_registerToken]'s log is not
  /// enough evidence. Android always returns null here -- skip it there.
  Future<void> _logApnsToken() async {
    if (!sinner) return;
    try {
      var apns = await _firebaseMessaging.getAPNSToken();
      if (apns == null) {
        // Registration with APNs is asynchronous and often not finished yet
        // right after requestPermission; give it one retry before believing it.
        await Future.delayed(const Duration(seconds: 3));
        apns = await _firebaseMessaging.getAPNSToken();
      }
      devPrint('[fcm] apns token: $apns');
    } catch (e) {
      devPrint('[fcm] getAPNSToken error: $e');
    }
  }

  /// Get FCM token and store in Redux #FCM_TOKEN.
  Future<void> _registerToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token == null) {
        // getToken() can return null on a cold/hot restart before Play
        // Services is ready — retry once after a short delay. onTokenRefresh
        // below also backfills #FCM_TOKEN when the token arrives later.
        await Future.delayed(const Duration(seconds: 2));
        token = await _firebaseMessaging.getToken();
      }
      devPrint(
        '[fcm] token: $token',
      ); // logs null too, so a silent-null is visible
      if (token != null) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#FCM_TOKEN': token})),
        );
      }
    } catch (e) {
      devPrint('[fcm] getToken error: $e');
    }
  }

  /// Listen for token refresh and update Redux.
  void _listenTokenRefresh() {
    _firebaseMessaging.onTokenRefresh.listen((String token) {
      devPrint('[fcm] token refreshed: $token');
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#FCM_TOKEN': token})),
      );
    });
  }

  /// Process any pending deeplink from a cold-start notification tap.
  /// Call this from main_page after screens are loaded.
  static void processPendingDeeplink() {
    final route = _pendingDeeplinkRoute;
    _pendingDeeplinkRoute = null;
    if (route != null && route.isNotEmpty) {
      _handleDeeplink(route);
    }
  }
}

// ---------------------------------------------------------------------------
// Background message handler -- TOP-LEVEL function, own isolate on Android.
// Must be top-level (not a class method). Must call Firebase.initializeApp().
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> myBackgroundMessageHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();

    // Resolve Firestore IO path from secure storage (globals not available)
    final ioPath = await _resolveIOPath();

    // Bridge: write to inbox
    await bridgePushToInbox(ioPath, message.data);

    // Show local notification (data-only messages are not auto-displayed)
    final flnp = await _initLocalNotifications(); // no tap handler in bg
    final dp = (message.data['dp'] ?? '') as String;
    final nm = (message.data['nm'] ?? '') as String;
    final route = (message.data['route'] ?? '') as String;
    await _showLocalNotification(flnp, nm, dp, route: route);
  } catch (e) {
    // ponytail: bg isolate, no UI. initializeApp / secure-storage read /
    // display can all throw; the message may already be persisted by
    // bridgePushToInbox. Log only — never let the handler Future reject.
    // ignore: avoid_print
    print('[fcm_bg] handler error: $e');
  }
}
