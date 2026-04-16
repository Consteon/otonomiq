import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
abstract class RegisterEvent extends Equatable {
  const RegisterEvent();
  @override
  List<Object> get props => [];
}
//abstract class RegisterEvent extends Equatable {
//  RegisterEvent([List props = const []]) : super(props);
//}

class EmailChanged extends RegisterEvent {
  final String email;

  const EmailChanged({required this.email}) ;

  @override
  String toString() => 'EmailChanged { email :$email }';
}

class PasswordChanged extends RegisterEvent {
  final String password;

  const PasswordChanged({required this.password});

  @override
  String toString() => 'PasswordChanged { password: $password }';
}

class Submitted extends RegisterEvent {
  final String email;
  final String password;

  const Submitted({required this.email, required this.password});

  @override
  String toString() {
    return 'Submitted { email: $email, password: $password }';
  }
}

class VidChanged extends RegisterEvent {
  final String vid;

  const VidChanged({required this.vid});// : super([vid]);

  @override
  String toString() => 'VidChanged { vid: $vid }';
}

class PinChanged extends RegisterEvent {
  final String pin;

  const PinChanged({required this.pin});// : super([pin]);

  @override
  String toString() => 'PinChanged { pin: $pin }';
}
