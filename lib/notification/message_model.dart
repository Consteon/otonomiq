import 'package:meta/meta.dart';
import '../notification/bloc.dart';

@immutable
class Message {
  final String? displayMessage; // message to human, should be displayed (dp)
  final String? dataPayload; // data to be processed by app. Json formatted (dt)
  final int? receivedTime; // received in vid inbox. seconds from unix time (tr)
  final bool? inbox; // true = incoming message; false = out coming messaged(ib)
  final String?
      messageId; // firebase message id. Searchable in collectionGroup('msg') (id)
  final int?
      status; // (in=True, 0=received,1=read but not processed, 101 = display & data processed),
  final String? route;
  // (in=False,0=not processed, 51=sent to server, 52=received in other vid,
  // 53=read but not processed, 102 = read & processed) (st)

  const Message({
    this.displayMessage,
    this.dataPayload,
    this.receivedTime,
    this.inbox,
    this.messageId,
    this.status,
    this.route,
  });

//  Notification(this.task, {this.complete = false, String note = '', String id})
//      : this.note = note ?? '',
//        this.id = id;

  Message copyWith(
      {String? displayMessage,
      String? dataPayload,
      int? receivedTime,
      bool? inbox,
      String? messageId,
      int? status}) {
    return Message(
      displayMessage: displayMessage ?? this.displayMessage,
      dataPayload: dataPayload ?? this.dataPayload,
      receivedTime: receivedTime ?? this.receivedTime,
      inbox: inbox ?? this.inbox,
      messageId: messageId ?? this.messageId,
      status: status ?? this.status,
      route: route ?? route,
    );
  }

  @override
  int get hashCode =>
      status.hashCode ^
      dataPayload.hashCode ^
      receivedTime.hashCode ^
      inbox.hashCode ^
      messageId.hashCode ^
      status.hashCode ^
      route.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          displayMessage == other.displayMessage &&
          dataPayload == other.dataPayload &&
          receivedTime == other.receivedTime &&
          inbox == other.inbox &&
          messageId == other.messageId &&
          status == other.status &&
          route == other.route;

  @override
  String toString() {
    return 'Notification{status: $status, dataPayload: $dataPayload, receivedTime: $receivedTime, inbox: $inbox, messageId: $messageId, status: $status, route: $route}';
  }

  MessageEntity toEntity() {
    return MessageEntity(displayMessage!, dataPayload!, receivedTime!, inbox!,
        messageId!, status!, route!);
  }

  static Message fromEntity(MessageEntity entity) {
    return Message(
      displayMessage: entity.dp,
      dataPayload: entity.dt,
      receivedTime: entity.tr,
      inbox: entity.im,
      messageId: entity.id,
      status: entity.st,
      route: entity.rt,
    );
  }
}
