// inspired from https://medium.com/flutterpub/enabling-firebase-cloud-messaging-push-notifications-with-flutter-39b08f2ed723
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'global.dart';

//final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();
/*
to send a message to a particular fcm token
DATA='{"notification": {"body": "this is a body","title": "this is a title"}, "priority": "high", "data": {"click_action": "FLUTTER_NOTIFICATION_CLICK", "id": "1", "status": "done"}, "to": "fqisi6oMX8A:APA91bFrwZyxjIt62v706Dw4EUK_AB3xi35cwAXSi5NwEmk2emqSUxdMyXWV8LGSWgqCpy15nycKAGvOSIbv2zLby6fC1MOlMGBCZ1GZNhz_AREcvKulIHbWTLQNG55GYj9BX6C4H1-Y"}'
curl https://fcm.googleapis.com/fcm/send -H "Content-Type:application/json" -X POST -d "$DATA" -H "Authorization: key=AAAAm0aQkfI:APA91bHTZHzJc6DhLgRFKM9wckFBN9R8gTxpujXX9PO5GHvczYQhTJy3ezAsrsAPp7FGnMhfzymg5D9VR9ufa7oQaWOG0qdF6hPm4VyTa1Tjbn3k5qd9tuJUE02msWhprU4gv2JGNxAR"
 */

class FirebaseNotifications {
  //FirebaseMessaging _firebaseMessaging = FirebaseMessaging();
  FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Future setUpFirebase() async {
    _firebaseMessaging = FirebaseMessaging.instance;
    await firebaseCloudMessagingListeners();
  }

  Future firebaseCloudMessagingListeners() async {
    if (Platform.isIOS) iOSPermission();

    // disable token retrieval temporary, need to enable for notification
    // await _firebaseMessaging.getToken().then((token) {
    //   devPrint('firebase_notification_handler.dart : FCM token: $token');
    //   transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
    //     '#FCM_TOKEN': token,
    //   })));
    // });

    // TODO put message in notification list. Create List, Create top icon
    // _firebaseMessaging.configure(
    //   onMessage: (Map<String, dynamic> message) async {
    //     devPrint('on message $message');
    //     //_showItemDialog(message); // from https://pub.dev/packages/firebase_messaging
    //     // call runInstruction('2')
    //     // put in notif list
    //     // display dialog; go = put route to notif['route'] | dismiss
    //   },
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      devPrint('on message $message');
        //_showItemDialog(message); // from https://pub.dev/packages/firebase_messaging
        // call runInstruction('2')
        // put in notif list
        // display dialog; go = put route to notif['route'] | dismiss
      },

       // onBackgroundMessage: myBackgroundMessageHandler, // still error. from
//          https://github.com/FirebaseExtended/flutterfire/tree/master/packages/firebase_messaging
    /* disabled 210516 by HH. Should be replaced with code
        as in https://firebase.flutter.dev/docs/messaging/notifications/

      onResume: (Map<String, dynamic> message) async {
        devPrint('on resume $message');
        //_navigateToItemDetail(message); // from https://pub.dev/packages/firebase_messaging
        // call runInstruction('2')
        // put in notif list
        // put route to notif['route']
        settingUp().then((aRes) {
          var state = transactionStore.state;
          var lifKey = state.screenTx['#INTERFACE_KEY'];
          readSettings(lifKey,1).then((_) {
            transactionStore.dispatch(UpdateScreenTxAction(
                ScreenTransaction(
                    {'#REFRESH': false})));
            rootThis.setState(() {
              rootThis.byPassWidget = NotificationList();
              rootThis.byPass = 1;
            });
          });
        });
      },
      onLaunch: (Map<String, dynamic> message) async {
        devPrint('on launch $message');
        settingUp().then((aRes) {
          var state = transactionStore.state;
          var lifKey = state.screenTx['#INTERFACE_KEY'];
          readSettings(lifKey,1).then((_) {
            transactionStore.dispatch(UpdateScreenTxAction(
                ScreenTransaction(
                    {'#REFRESH': false})));
            rootThis.setState(() {
              rootThis.byPassWidget = NotificationList();
              rootThis.byPass = 1;
            });
          });
        });
        //_navigateToItemDetail(message);  // from https://pub.dev/packages/firebase_messaging
        // call runInstruction('2')
        // put in notif list
        // put route to notif['route']
      },

     */
    );
    FirebaseMessaging.onBackgroundMessage(myBackgroundMessageHandler);
  }

   void iOSPermission() {
  // disabled 210516 by HH. Should follow instructions for iOS in https://firebase.flutter.dev/docs/messaging/notifications/
  //   _firebaseMessaging.requestNotificationPermissions(
  //       IosNotificationSettings(sound: true, badge: true, alert: true));
  //   _firebaseMessaging.onIosSettingsRegistered
  //       .listen((IosNotificationSettings settings) {
  //     devPrint("Settings registered: $settings");
  //   });
   }
}

// ignore: missing_return
Future<void> myBackgroundMessageHandler(RemoteMessage message) async {
  // from https://pub.dev/packages/firebase_messaging -- HH
  // from https://firebase.flutter.dev/docs/messaging/usage/ --HH
  await Firebase.initializeApp();
  if (message.data['data'] != null) {
    // Handle data message
    final dynamic data = message.data['data'];
  }

  if (message.data['notification'] != null) {
    // Handle notification message
    final dynamic notification = message.data['notification'];
  }
  // Or do other work.
}

