import 'dart:core';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../global.dart';
import '../notification/bloc.dart';

abstract class NotificationRepository {
  Future<void> addNewNotification(Notification notification);
  Future<void> deleteNotification(Notification notification);
  Stream<List<Notification>> notifications();
  Future<void> updateNotification(Notification notification);
}

class FirebaseNotificationRepository implements NotificationRepository {
  // A getter, not a field: as a field this froze whatever `firestoreIO` was at
  // construction time (main.dart builds this repo during runApp), so every
  // write went to the boot-default `users_<fsName>` even after login resolved
  // the real path. `notifications()` already read the global at call time --
  // this makes the write side agree with it.
  CollectionReference<Map<String, dynamic>> get notificationCollection =>
      FirebaseFirestore.instance.collection(firestoreIO);

  @override
  Future<void> addNewNotification(Notification notification) {
    return notificationCollection.add(notification.toEntity().toDocument());
  }

  @override
  Future<void> deleteNotification(Notification notification) async {
    return notificationCollection.doc(notification.vid).delete();
  }

  @override
  Stream<List<Notification>> notifications() {
    // the stream of notification
    //    return notificationList.snapshots().map((snapshot) {
    // The single most useful line when the inbox renders empty: which path did
    // it actually subscribe to? `users_<fsName>` here means firestoreIO was
    // never resolved and the feed can never populate.
    devPrint('[inbox] subscribe $firestoreIO');
    return FirebaseFirestore.instance
        .collection(firestoreIO)
        .orderBy('lt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => Notification.fromEntity(
                  NotificationEntity.fromSnapshot(doc),
                ),
              )
              .toList();
        });
  }

  @override
  Future<void> updateNotification(Notification update) {
    return safeFsUpdate(
      notificationCollection.doc(update.vid),
      update.toEntity().toDocument(),
      'updateNotification',
    );
  }

  //  @override
  //  Stream<List<Notification>> messages() {
  //    // the stream of messages between my vid and one other vid
  //    return messageList.snapshots().map((snapshot) {
  //      return snapshot.documents
  //          .map((doc) =>
  //          Notification.fromEntity(NotificationEntity.fromSnapshot(doc)))
  //          .toList();
  //    });
  //  }
}
