import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import '../notification/bloc.dart';

@immutable
abstract class NotificationState extends Equatable {
  const NotificationState();
  @override
  List<Object> get props => [];
}
//abstract class NotificationState extends Equatable {
//  NotificationState([List props = const <dynamic>[]]) : super(props);
//}

class NotificationLoading extends NotificationState {
  @override
  String toString() => 'NotificationLoading';
}

// ignore: must_be_immutable
class NotificationLoaded extends NotificationState {
  List<Notification> notifications;
  int unReadNumber;

  NotificationLoaded([this.notifications = const [], this.unReadNumber=0]);

  @override
  List<Object> get props => [
        notifications,
        unReadNumber
      ]; // This line make notification updated lively

  @override
  String toString() =>
      'NotificationLoaded { notifications: $notifications, unReadNumber: $unReadNumber }';
}

class NotificationsNotLoaded extends NotificationState {
  @override
  String toString() => 'NotificationsNotLoaded';
}
