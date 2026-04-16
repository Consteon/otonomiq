import 'package:meta/meta.dart';
import 'notification_entities.dart';

@immutable
class Notification {
  final String? vid; // vid, documentId
  final int? unRead; // # of unread messages of this vid (urd)
  final String? lastMessage; // last message to display in notification list (lm)
  final int? lastMessageTime; // time of last message in unix milli second (lt)
  final String? name; // name of vid displayed (nm)
  final String? profilePicture; // url to profilePicture (pp)
  final int? lastAccess; // time of last read (la)

  // Notification();
  @override
  List<Object> get props => [];

  const Notification({
    this.vid,
    this.unRead,
    this.lastMessage,
    this.lastMessageTime,
    this.name,
    this.profilePicture,
    this.lastAccess,
  });

//  Notification(this.task, {this.complete = false, String note = '', String id})
//      : this.note = note ?? '',
//        this.id = id;

  // Notification copyWith({bool complete, String id, String note, String task}) {
  //   return Notification(
  //     task ?? this.task,
  //     complete: complete ?? this.complete,
  //     id: id ?? this.id,
  //     note: note ?? this.note,
  //   );
  // }

  Notification copyWith(
      {String? vid,
      int? unRead,
      String? lastMessage,
      int? lastMessageTime,
      String? name,
      String? profilePicture,
      int? lastAccess}) {
    return Notification(
      unRead: unRead ?? this.unRead,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      profilePicture: profilePicture ?? this.profilePicture,
      lastAccess: lastAccess ?? this.lastAccess,
    );
  }

  @override
  int get hashCode =>
      vid.hashCode ^
      unRead.hashCode ^
      lastMessage.hashCode ^
      lastMessageTime.hashCode ^
      name.hashCode ^
      profilePicture.hashCode ^
      lastAccess.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Notification &&
          runtimeType == other.runtimeType &&
          vid == other.vid &&
          unRead == other.unRead &&
          lastMessage == other.lastMessage &&
          lastMessageTime == other.lastMessageTime &&
          name == other.name &&
          profilePicture == other.profilePicture &&
          lastAccess == other.lastAccess;

  @override
  String toString() {
    return 'Notification{vid: $vid, unRead: $unRead, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, name: $name, profilePicture: $profilePicture, lastAccess: $lastAccess}';
  }

  NotificationEntity toEntity() {
    return NotificationEntity(vid!, unRead!, lastMessage!, lastMessageTime!, name!,
        profilePicture!, lastAccess!);
  }

  static Notification fromEntity(NotificationEntity entity) {
    return Notification(
      vid: entity.vid,
      unRead: entity.urd,
      lastMessage: entity.lm,
      lastMessageTime: entity.lt,
      name: entity.nm,
      profilePicture: entity.pp,
      lastAccess: entity.la,
    );
  }
}
