import 'dart:core';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../global.dart';
import '../notification/bloc.dart';

abstract class MessageRepository {
  Future<void> addNewMessage(Message message);
  Future<void> deleteMessage(Message message);
  Stream<List<Message>> messages();
  Future<void> updateMessage(Message message);
}

class FirebaseMessageRepository implements MessageRepository {
  final messageCollection = FirebaseFirestore.instance.collection(firestoreMsg);
  final messageList = FirebaseFirestore.instance
      .collection(firestoreMsg)
      .orderBy('tr', descending: true);

  @override
  Future<void> addNewMessage(Message message) {
    return messageCollection.add(message.toEntity().toDocument());
  }

  @override
  Future<void> deleteMessage(Message message) async {
    return messageCollection.doc(message.messageId).delete();
  }

  @override
  Stream<List<Message>> messages() {
    // the stream of message
    //    return messageList.snapshots().map((snapshot) {
    return FirebaseFirestore.instance
        .collection(firestoreMsg)
        .orderBy('tr', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Message.fromEntity(MessageEntity.fromSnapshot(doc)))
              .toList();
        });
  }

  @override
  Future<void> updateMessage(Message update) {
    return safeFsUpdate(
      messageCollection.doc(update.messageId),
      update.toEntity().toDocument(),
      'updateMessage',
    );
  }
}
