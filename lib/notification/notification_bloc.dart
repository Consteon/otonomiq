import 'dart:async';

import 'package:bloc/bloc.dart';

import './bloc.dart';
// inspired from https://medium.com/flutter-community/firestore-todos-with-flutter-bloc-7b2d5fadcc80

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository _notificationRepository;
  StreamSubscription? _notificationSubscription;

  /// Global handle so non-widget code (api.dart, right after firestoreIO is
  /// set) can re-subscribe the inbox stream to the correct path — the stream
  /// otherwise stays bound to the boot-time default path until something else
  /// re-dispatches LoadNotification.
  static NotificationBloc? instance;

  NotificationBloc({required this._notificationRepository})
    : super(NotificationLoading()) {
    instance = this;
  }

  NotificationState get initialState => NotificationLoading();

  @override
  Stream<NotificationState> mapEventToState(NotificationEvent event) async* {
    if (event is LoadNotification) {
      yield* _mapLoadNotificationToState();
    } else if (event is AddNotification) {
      yield* _mapAddNotificationToState(event);
    } else if (event is UpdateNotification) {
      yield* _mapUpdateNotificationToState(event);
    } else if (event is DeleteNotification) {
      yield* _mapDeleteNotificationToState(event);
    } else if (event is NotificationUpdated) {
      yield* _mapNotificationUpdatedToState(event);
    }
  }

  Stream<NotificationState> _mapLoadNotificationToState() async* {
    yield NotificationLoading();
    _notificationSubscription?.cancel();
    _notificationSubscription = _notificationRepository.notifications().listen(
      (notifications) {
        add(NotificationUpdated(notifications));
      },
      // Without this a Firestore failure (wrong path, permission denied) was
      // swallowed: the bloc sat on NotificationLoading forever and the inbox
      // looked like "Belum ada notifikasi". Surface it via BlocObserver.onError.
      onError: (Object e, StackTrace s) => addError(e, s),
    );
  }

  Stream<NotificationState> _mapAddNotificationToState(
    AddNotification event,
  ) async* {
    _notificationRepository.addNewNotification(event.notifications);
  }

  Stream<NotificationState> _mapUpdateNotificationToState(
    UpdateNotification event,
  ) async* {
    _notificationRepository.updateNotification(event.notifications);
  }

  Stream<NotificationState> _mapDeleteNotificationToState(
    DeleteNotification event,
  ) async* {
    _notificationRepository.deleteNotification(event.notifications);
  }

  Stream<NotificationState> _mapNotificationUpdatedToState(
    NotificationUpdated event,
  ) async* {
    int unReadNotification = 0;
    for (var notif in event.notifications) {
      unReadNotification += (notif.unRead)!;
    }
    //    event.notifications.sort((a,b) => a.lastMessageTime.compareTo(b.lastMessageTime));
    yield NotificationLoaded(event.notifications, unReadNotification);
  }
}
