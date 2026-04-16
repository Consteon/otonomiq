import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import '../notification/bloc.dart';

@immutable
abstract class NotificationEvent extends Equatable {
  const NotificationEvent();
  @override
  List<Object> get props => [];
}
//abstract class NotificationEvent extends Equatable {
//  NotificationEvent([List props = const <dynamic>[]]) : super(props);
//}

class LoadNotification extends NotificationEvent {
  @override
  String toString() => 'LoadNotifications';
}

class AddNotification extends NotificationEvent {
  final Notification notifications;

  const AddNotification(this.notifications);// : super([notifications]);

  @override
  String toString() => 'AddNotification { notifications: $notifications }';
}

class UpdateNotification extends NotificationEvent {
  final Notification notifications;

  const UpdateNotification(this.notifications);// : super([notifications]);

  @override
  String toString() => 'UpdateNotification { UpdateNotification: $notifications }';
}

class DeleteNotification extends NotificationEvent {
  final Notification notifications;

  const DeleteNotification(this.notifications);// : super([notifications]);

  @override
  String toString() => 'DeleteNotification { notification: $notifications }';
}

class ClearCompleted extends NotificationEvent {
  @override
  String toString() => 'ClearCompleted';
}

class NotificationUpdated extends NotificationEvent {
  final List<Notification> notifications;

  const NotificationUpdated(this.notifications);

  @override
  String toString() => 'NotificationUpdated';
}

//class ToggleAll extends NotificationEvent {
//  @override
//  String toString() => 'ToggleAll';
//}


