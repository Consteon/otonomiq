import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
abstract class AuthenticationEvent extends Equatable {
  const AuthenticationEvent();
  @override
  List<Object> get props => [];
  //AuthenticationEvent([List props = const []]) : super(props);
}
//abstract class AuthenticationEvent extends Equatable {
//  AuthenticationEvent([List props = const []]) : super(props);
//}

class AppStarted extends AuthenticationEvent {
  @override
  String toString() => 'AppStarted';
}

class LoggedIn extends AuthenticationEvent {
  @override
  String toString() => 'LoggedIn';
}

class LoggedOut extends AuthenticationEvent {
  @override
  String toString() => 'LoggedOut';
}

class TosReviewed extends AuthenticationEvent {
  @override
  String toString() => 'TosReviewed';
}
