// from : https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

@immutable
class LoginState {
  final bool isEmailValid;
  final bool isPasswordValid;
  final bool isSmsCodeValid;
  final bool isPhoneValid;
  final bool isTosOK;
  final bool isWaitingSmsCode;
  final bool isSubmitting;
  final String
  loginUid; // ask for invitation. Authentication ok, this is new user. Need to ask for invitation. Have uid, but not yet registered in firestore
  final bool isSuccess;
  final bool isFailure;
  final bool isVidOK; // Vid = Vertriz ID
  final bool isPinOK; // PIN = initial pin when user got predefined vid & pin
  final bool
  isFirebaseOK; // status of firebase login regardless of the method (google sign in, facebook, twitter, etc)
  final bool
  isUserFull; // true if no more empty user in SQL.operation1. Function getNewVid return 0
  final String loginVid; // Vid #
  final String loginInv; // Invitation # if user invited
  final String loginCountry; // Country code of invitation (phone #)
  final bool
  inLoginProcess; // true when submitting and login state is not final
  final int
  loginStatus; // 0=ok;1=user full;2=vid fail;3=Invitation Code Not Match;4=other failure;99=in progress
  /*
    state ini main_page [416]
      isFailure = true :
        1   : Full !; Wah!, banyak sekali yang mendaftar. Sementara ini tidak dapat menambah pemakai baru. Kami sedang terus menambah kapasitas, silahkan coba beberapa jam lagi.
        2   : Other user logged in ; Ada pemakai lain yang sedang memakai invitasi ini. Silahkan pergunakan nomor invitasi lain.
        3   : Invitation Code Not Match; Kode Undangan tidak ada.
        4   : Sign in error ; Terjadi kesalahan pada saat sign in, silahkan coba beberapa jam lagi.
        5   : Sign in error ; Terjadi kesalahan pada saat autorisasi akun Google, silahkan coba lagi.
        7   : Invitation Code has been used before; Kode undangan telah dipakai oleh pengguna lain.
        802 : ERROR 802 ; ERROR 802 Login gagal; Anda mencoba masuk di perangkat lain. Untuk faktor keamanan, anda hanya dapat menggunakan satu akun pada satu perangkat. Anda perlu otentifikasi ulang jika ingin masuk di perangkat lain.
        809 : ERROR 809 ; ERROR 809 Login gagal; Anda belum memiliki akun.; Mohon hubungi administrator untuk mendaftarkan akun anda.
        810 : ERROR 810 ; Error 810 GPS tidak berfungsi ; Pengaturan ???pelacakan GPS???  serta ???pelacakan catatan GPS??? pada perangkat anda tidak berfungsi. Anda diminta untuk selalu mengaktifkan GPS oleh perusahan.; Mohon aktifkan pengaturan ???pelacakan GPS???  serta ???pelacakan catatan GPS??? pada perangkat anda.
        else : Login fail : Login anda gagal. Kemungkinan karena koneksi internet anda terganggu. Silahkan coba beberapa saat lagi

   */
  final int
  signInMethod; // 1 = google sign in; 2 = facebook; 3 = twitter; 4 = phone; 5 = email/pw; 6 = credential (username / pw); 11 = vertriz sign in
  final int
  currentState; // -1 = not yet defined; 0 = direct user; 1 = by invitation
  bool get isFormValid => isPhoneValid;

  const LoginState({
    required this.isEmailValid,
    required this.isPasswordValid,
    required this.isSmsCodeValid,
    required this.isPhoneValid,
    required this.isTosOK,
    required this.isWaitingSmsCode,
    required this.isSubmitting,
    required this.loginUid,
    required this.isSuccess,
    required this.isFailure,
    required this.isVidOK,
    required this.isPinOK,
    required this.isFirebaseOK,
    required this.isUserFull,
    required this.loginVid,
    required this.loginCountry,
    required this.loginInv,
    required this.inLoginProcess,
    required this.loginStatus,
    required this.signInMethod,
    required this.currentState,
  });

  factory LoginState.empty(int last) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: false,
      isPhoneValid: false,
      isTosOK: false,
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: false,
      loginStatus: 99,
      signInMethod: last,
      currentState: -1,
    );
  }

  factory LoginState.cancelled(int last) {
    // Social sign-in returned null: the user cancelled the account picker, or a
    // silent failure produced no user. Terminal and NON-error — dismiss the
    // spinner and leave the form usable. isFailure stays false (no error
    // dialog) and loginUid stays empty (no accidental invitation navigation).
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, // keep social buttons enabled
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: false,
      loginStatus: 99,
      signInMethod: last,
      currentState: -1,
    );
  }

  factory LoginState.loading(int last) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display sign in button
      isWaitingSmsCode: false,
      isSubmitting: true,
      loginUid: '',
      isSuccess: false,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry:'',
      inLoginProcess: true,
      loginStatus: 99,
      signInMethod: last,
      currentState: -1,
    );
  }

  factory LoginState.smsVerification(int last) {
    return LoginState(
      isEmailValid: false,
      isPasswordValid: false,
      isSmsCodeValid: false,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: true,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: true,
      loginStatus: 99,
      signInMethod: last,
      currentState: -1,
    );
  }

  factory LoginState.newUser(int last, String loginUid) {
    // Auth ok, but no record firebase
    return LoginState(
      isEmailValid: true,
      isPasswordValid: false,
      isSmsCodeValid: false,
      isPhoneValid: false,
      isTosOK: true,
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: loginUid,
      isSuccess: false,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: true,
      loginStatus: 99,
      signInMethod: last,
      currentState: -1,
    );
  }

  factory LoginState.failure(
      int current, int last, String loginVid, String loginInv, String loginCountry) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: loginVid,
      loginInv: loginInv,
      loginCountry: loginCountry,
      inLoginProcess: false,
      loginStatus: 99,
      signInMethod: last,
      currentState: current,
    );
  }

  factory LoginState.loginError(int current, int last, int stat) {
    // error 802 : login from other device
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: false,
      loginStatus: stat,
      signInMethod: last,
      currentState: current,
    );
  }

  factory LoginState.invIsWrong(int last, String loginUid, String loginInv) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: loginUid,
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: false,
      loginVid: '',
//      loginPin: '',
      loginInv: loginInv,
      loginCountry: '',
      inLoginProcess: false,
      loginStatus: 3,
      signInMethod: last,
      currentState: 1,
    );
  }

  factory LoginState.invExpired(int last, String uid, String loginInv, String loginCountry) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: uid,
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: false,
      loginVid: '',
      loginInv: loginInv,
      loginCountry: loginCountry,
//      loginPin: '',
      inLoginProcess: false,
      loginStatus: 7,
      signInMethod: last,
      currentState: 1,
    );
  }

  factory LoginState.userFull(int last) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: true,
      loginVid: '',
      loginCountry: '',
//      loginPin:'',
      loginInv: '',
      inLoginProcess: false,
      loginStatus: 1,
      signInMethod: last,
      currentState: 0,
    );
  }

  factory LoginState.userLoggedIn(int last) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: '',
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: true,
      loginVid: '',
//      loginPin:'',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: false,
      loginStatus: 2,
      signInMethod: last,
      currentState: 0,
    );
  }

  factory LoginState.firebaseLoginSuccess(
      int last, String loginUid, String loginVid, String loginInv, String loginCountry) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: loginUid,
      isSuccess: false,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: false,
      loginVid: loginVid,
      loginInv: loginInv,
      loginCountry: loginCountry,
      inLoginProcess: true,
      loginStatus: 99,
      signInMethod: last,
      currentState: 9,
    );
  }

  factory LoginState.firebaseLoginFailure(
      int last, String uid, String loginVid, String loginInv, String loginCountry) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: uid,
      isSuccess: false,
      isFailure: true,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: false,
      isUserFull: false,
      loginVid: loginVid,
      loginInv: loginInv,
      loginCountry: loginCountry,
      inLoginProcess: false,
      loginStatus: 5,
      signInMethod: last,
      currentState: -1,
    );
  }

  factory LoginState.success(int current, int last, String uid) {
    return LoginState(
      isEmailValid: true,
      isPasswordValid: true,
      isSmsCodeValid: true,
      isPhoneValid: true,
      isTosOK: true, //always display signin button
      isWaitingSmsCode: false,
      isSubmitting: false,
      loginUid: uid,
      isSuccess: true,
      isFailure: false,
      isVidOK: false,
      isPinOK: false,
      isFirebaseOK: true,
      isUserFull: false,
      loginVid: '',
      loginInv: '',
      loginCountry: '',
      inLoginProcess: false,
      loginStatus: 0,
      signInMethod: last,
      currentState: current,
    );
  }

  LoginState update({
    bool? isEmailValid,
    bool? isPasswordValid,
    bool? isSmsCodeValid,
    bool? isPhoneValid,
    bool? isTosOK,
    bool? isWaitingSmsCode,
    String? loginUid,
    bool? isVidOK,
    bool? isPinOK,
    bool? isFirebaseOK,
    bool? isUserFull,
    String? loginVid,
    String? loginInv,
    String? loginCountry,
    bool? inLoginProcess,
    int? loginStatus,
    int? signInMethod,
    int? currentState,
  }) {
    return copyWith(
      isEmailValid: isEmailValid,
      isPasswordValid: isPasswordValid,
      isSmsCodeValid: isSmsCodeValid,
      isPhoneValid: isPhoneValid,
      isTosOK: isTosOK,
      isWaitingSmsCode: isWaitingSmsCode,
      isSubmitting: false,
      loginUid: loginUid,
      isSuccess: false,
      isFailure: false,
      isVidOK: isVidOK,
      isPinOK: isPinOK,
      isFirebaseOK: isFirebaseOK,
      isUserFull: isUserFull,
      loginVid: loginVid,
      loginInv: loginInv,
      loginCountry: loginCountry,
      inLoginProcess: inLoginProcess,
      loginStatus: loginStatus,
      signInMethod: signInMethod,
      currentState: currentState,
    );
  }

  LoginState copyWith({
    bool? isEmailValid,
    bool? isPasswordValid,
    bool? isSmsCodeValid,
    bool? isPhoneValid,
    bool? isTosOK,
    bool? isWaitingSmsCode,
    bool? isSubmitEnabled,
    bool? isSubmitting,
    String? loginUid,
    bool? isSuccess,
    bool? isFailure,
    bool? isVidOK,
    bool? isPinOK,
    bool? isFirebaseOK,
    bool? isUserFull,
    String? loginVid,
    String? loginInv,
    String? loginCountry,
    bool? inLoginProcess,
    int? loginStatus,
    int? signInMethod,
    int? currentState,
  }) {
    return LoginState(
      isEmailValid: isEmailValid ?? this.isEmailValid,
      isPasswordValid: isPasswordValid ?? this.isPasswordValid,
      isSmsCodeValid: isSmsCodeValid ?? this.isSmsCodeValid,
      isPhoneValid: isPhoneValid ?? this.isPhoneValid,
      isTosOK: isTosOK ?? this.isTosOK,
      isWaitingSmsCode: isWaitingSmsCode ?? this.isWaitingSmsCode,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      loginUid: loginUid ?? this.loginUid,
      isSuccess: isSuccess ?? this.isSuccess,
      isFailure: isFailure ?? this.isFailure,
      isVidOK: isVidOK ?? this.isVidOK,
      isPinOK: isPinOK ?? this.isPinOK,
      isFirebaseOK: isFirebaseOK ?? this.isFirebaseOK,
      isUserFull: isUserFull ?? this.isUserFull,
      loginVid: loginVid ?? this.loginVid,
      loginInv: loginInv ?? this.loginInv,
      loginCountry: loginCountry ?? this.loginCountry,
      inLoginProcess: inLoginProcess ?? this.inLoginProcess,
      loginStatus: loginStatus ?? this.loginStatus,
      signInMethod: signInMethod ?? this.signInMethod,
      currentState: currentState ?? this.currentState,
    );
  }

  @override
  String toString() {
    return '''LoginState {
      isEmailValid: $isEmailValid,
      isPasswordValid: $isPasswordValid,
      isSmsCodeValid: $isSmsCodeValid,
      isPhoneValid: $isPhoneValid,
      isTosOK: $isTosOK,
      isSubmitting: $isSubmitting,
      loginUid: $loginUid,
      isSuccess: $isSuccess,
      isFailure: $isFailure,
      isVidOK: $isVidOK,
      isPinOK: $isPinOK,
      isFirebaseOK: $isFirebaseOK,
      isUserFull: $isUserFull,
      loginVid: $loginVid,
      loginInv: $loginInv,
      loginCountry: $loginCountry,
      inLoginProcess: $inLoginProcess,
      loginStatus: $loginStatus,
      lastState: $signInMethod,
      currentState: $currentState,
    }''';
  }
}

/// Single source of truth for the blocking login spinner's visibility.
///
/// Driven by [LoginState.isSubmitting] (true only for [LoginState.loading]) so
/// every terminal/transitional state — newUser, success, failure, cancel —
/// dismisses it. The previous predicate keyed off
/// `inLoginProcess && !isSuccess && !isFailure`, which stayed true for the
/// newUser state and left the spinner stuck over the invitation screen.
bool loginSpinnerVisible(LoginState state) => state.isSubmitting;
