import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../notification/bloc.dart';
import '../global.dart';

abstract class NotificationRepository {
  Future<void> addNewNotification(Notification notification);
  Future<void> deleteNotification(Notification notification);
  Stream<List<Notification>> notifications();
  Future<void> updateNotification(Notification notification);
}

class FirebaseNotificationRepository implements NotificationRepository {
  final notificationList = FirebaseFirestore.instance
      .collection(firestoreIO)
      .orderBy('lt', descending: true);
  final notificationCollection =
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
    return FirebaseFirestore.instance
        .collection(firestoreIO)
        .orderBy('lt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) =>
              Notification.fromEntity(NotificationEntity.fromSnapshot(doc)))
          .toList();
    });
  }

  @override
  Future<void> updateNotification(Notification update) {
    return notificationCollection
        .doc(update.vid)
        .update(update.toEntity().toDocument());
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
