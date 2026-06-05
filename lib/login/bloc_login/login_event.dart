import 'package:meta/meta.dart';
import 'package:equatable/equatable.dart';

@immutable
abstract class LoginEvent extends Equatable {
  const LoginEvent();
  @override
  List<Object> get props => [];
}
//abstract class LoginEvent extends Equatable {
//  LoginEvent([List props = const []]) : super(props);
//}

class EmailChanged extends LoginEvent {
  final String email;
  const EmailChanged({required this.email}); // : super([email]);
  @override
  List<Object> get props => [email];
  @override
  String toString() => 'EmailChanged { email :$email }';
}

class PasswordChanged extends LoginEvent {
  final String password;
  const PasswordChanged({required this.password}); // : super([password]);
  @override
  List<Object> get props => [password];
  @override
  String toString() => 'PasswordChanged { password: $password }';
}

class SmsCodeChanged extends LoginEvent {
  final String smsCode;
  const SmsCodeChanged({required this.smsCode}); // : super([smsCode]);
  @override
  List<Object> get props => [smsCode];
  @override
  String toString() => 'SmsCodeChanged { smsCode: $smsCode }';
}

class PhoneChanged extends LoginEvent {
  final String phone;
  const PhoneChanged({required this.phone}); // : super([phone]);
  @override
  List<Object> get props => [phone];
  @override
  String toString() => 'PhoneChanged { phone: $phone }';
}

class VidChanged extends LoginEvent {
  final String vid;
  const VidChanged({required this.vid}); // : super([vid]);
  @override
  List<Object> get props => [vid];
  @override
  String toString() => 'VidChanged { Invitation: $vid }';
}

class InvChanged extends LoginEvent {
//  final String vid;
  final String inv;
  const InvChanged({required this.inv}); // : super([inv]);
  @override
  List<Object> get props => [inv];
  @override
  String toString() => 'InvChanged { inv: $inv }';
}

class CountryChanged extends LoginEvent {
//  final String vid;
  final String country;
  const CountryChanged({required this.country}); // : super([country]);
  @override
  List<Object> get props => [country];
  @override
  String toString() => 'InvChanged { country: $country }';
}

class Submitted extends LoginEvent {
  final String email;
  final String password;
  const Submitted({required this.email, required this.password});
  // : super([email, password]);
  @override
  List<Object> get props => [email, password];
  @override
  String toString() {
    return 'Submitted { email: $email, password: $password }';
  }
}

class LoginWithGooglePressed extends LoginEvent {
  final String country;
  final String inv;
//  final String vid;
//  final String pin;
//  LoginWithGooglePressed({@required this.vid, @required this.pin}) : super([vid,pin]);
  const LoginWithGooglePressed({required String country, required String inv})
      : country = country,
        inv = inv,
        super();
  @override
  List<Object> get props => [country, inv];
  @override
  String toString() => 'LoginWithGooglePressed';
}

class LoginWithApplePressed extends LoginEvent {
  final String country;
  final String inv;
//  final String vid;
//  final String pin;
//  LoginWithGooglePressed({@required this.vid, @required this.pin}) : super([vid,pin]);
  const LoginWithApplePressed({required this.country, required this.inv})
      : super();
  @override
  List<Object> get props => [country, inv];
  @override
  String toString() => 'LoginWithGooglePressed';
}

class SendSmsPressed extends LoginEvent {
  final String phone;
  const SendSmsPressed({required this.phone}); // : super([phone]);
  @override
  List<Object> get props => [phone];
  @override
  String toString() => 'SendSmsPressed';
}

class LoginWithPhonePressed extends LoginEvent {
  final String smsCode;
  const LoginWithPhonePressed({required this.smsCode}); // : super([smsCode]);
  @override
  List<Object> get props => [smsCode];
  @override
  String toString() => 'LoginWithPhonePressed';
}

class TosOKTabbed extends LoginEvent {
  final bool tosOk;
  const TosOKTabbed({required this.tosOk}); // : super([tosOk]);
  @override
  List<Object> get props => [tosOk];

  @override
  String toString() {
    return 'tosOKTabbed { tosOK: $tosOk}';
  }
}

class LoginWithCredentialsPressed extends LoginEvent {
  final String email;
  final String password;

  const LoginWithCredentialsPressed({required this.email, required this.password});
  //: super([email, password]);
  @override
  List<Object> get props => [email, password];

  @override
  String toString() {
    return 'LoginWithCredentialsPressed { email: $email, password: $password }';
  }
}

class WrongVid extends LoginEvent {
  final bool vidOk;
  const WrongVid({required this.vidOk}); // : super([vidOk]);
  @override
  List<Object> get props => [vidOk];

  @override
  String toString() {
    return 'wrongVid { vidOK: $vidOk}';
  }
}

class WrongPin extends LoginEvent {
  final bool pinOk;
  const WrongPin({required this.pinOk}); // : super([pinOk]);
  @override
  List<Object> get props => [pinOk];

  @override
  String toString() {
    return 'wrongPin { vidOK: $pinOk}';
  }
}

class FirebaseCannotLogin extends LoginEvent {
  final bool firebaseOk;

  const FirebaseCannotLogin({required this.firebaseOk}); // : super([firebaseOk]);
  @override
  List<Object> get props => [firebaseOk];

  @override
  String toString() {
    return 'firebaseCannotLogin { vidOK: $firebaseOk}';
  }
}

class InvitationLoginPressed extends LoginEvent {
  final String inv;
  final String uid;

  const InvitationLoginPressed(
      {required this.inv, required this.uid}); // : super([inv,uid]);
  @override
  List<Object> get props => [inv, uid];
  @override
  String toString() => 'InvitationLoginPressed';
}

class InvitationLoginFailed extends LoginEvent {
  final String inv;
  final String country;
  final String uid;
  final int status;

  const InvitationLoginFailed(
      {required this.inv,
        required this.country,
        required this.uid,
        required this.status}); // : super([inv,uid,status]);
  @override
  List<Object> get props => [inv, country, uid, status];
  @override
  String toString() => 'InvitationLoginFailed';
}

class OtherDeviceLoginFailed extends LoginEvent {
  final String uid;
  final int status;

  const OtherDeviceLoginFailed(
      {required this.uid, required this.status}); // : super([inv,uid,status]);
  @override
  List<Object> get props => [uid, status];
  @override
  String toString() => 'InvitationLoginFailed';
}

class LoginFailWithStatus extends LoginEvent {
  final String uid;
  final int status;

  const LoginFailWithStatus(
      {required this.uid, required this.status}); // : super([inv,uid,status]);
  @override
  List<Object> get props => [uid, status];
  @override
  String toString() => 'LoginFailWithStatus $status';
}
