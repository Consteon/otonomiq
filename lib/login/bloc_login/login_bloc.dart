import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // debugPrint for [LOGINPERF] logs

import '../../ftz_secret.dart';
import '../../global.dart';
import '../../login/api/user_repository.dart';
//import 'package:rxdart/rxdart.dart';
import '../../login/page/login/login.dart';
//import 'package:va/api.dart';
//import 'package:va/global.dart';
//import 'package:va/widget/ui_component.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final UserRepository _userRepository;

  LoginBloc({required this._userRepository}) : super(LoginState.empty(1));

  //  @override
  //  LoginState get initialState => LoginState.empty(1);

  //  @override
  //  Stream<LoginState> transform(
  //    Stream<LoginEvent> events,
  //    Stream<LoginState> Function(LoginEvent event) next,
  //  ) {
  //    final observableStream = events as Observable<LoginEvent>;
  //    final nonDebounceStream = observableStream.where((event) {
  //      return (event is! EmailChanged && event is! PasswordChanged);
  //    });
  //    final debounceStream = observableStream.where((event) {
  //      return (event is EmailChanged || event is PasswordChanged);
  //    }).debounceTime(Duration(milliseconds: 300));
  //    return super.transform(nonDebounceStream.mergeWith([debounceStream]), next);
  //  }

  @override
  Stream<LoginState> mapEventToState(LoginEvent event) async* {
    if (event is EmailChanged) {
      yield* _mapEmailChangedToState(event.email);
    } else if (event is PasswordChanged) {
      yield* _mapPasswordChangedToState(event.password);
    } else if (event is PhoneChanged) {
      yield* _mapPhoneChangedToState(event.phone);
    } else if (event is SmsCodeChanged) {
      yield* _mapSmsCodeChangedToState(event.smsCode);
    } else if (event is LoginWithGooglePressed) {
      yield* _mapLoginWithGooglePressedToState(event.country, event.inv);
    } else if (event is LoginWithApplePressed) {
      yield* _mapLoginWithApplePressedToState(event.country, event.inv);
    } else if (event is SendSmsPressed) {
      yield* _mapSendSmsPressedToState(event.phone);
    } else if (event is LoginWithPhonePressed) {
      yield* _mapLoginWithPhonePressedToState(event.smsCode);
    } else if (event is TosOKTabbed) {
      yield* _mapTosOKTabbedToState(event.tosOk);
    } else if (event is LoginWithCredentialsPressed) {
      yield* _mapLoginWithCredentialsPressedToState(
        email: event.email,
        password: event.password,
      );
    } else if (event is WrongVid) {
      yield* _mapWrongVidToState(false);
    } else if (event is VidChanged) {
      yield* _mapVidChangedToState(event.vid);
    } else if (event is InvChanged) {
      yield* _mapInvChangedToState(event.inv);
    } else if (event is CountryChanged) {
      yield* _mapCountryChangedToState(event.country);
    } else if (event is InvitationLoginPressed) {
      yield* _mapInvitationLoginPressedToState(event.inv, event.uid);
    } else if (event is InvitationLoginFailed) {
      yield* _mapInvitationLoginFailedToState(
        event.inv,
        event.country,
        event.uid,
        event.status,
      );
    } else if (event is LoginFailWithStatus) {
      yield* _mapLoginFailedWithStatusToState(event.uid, event.status);
    }
  }

  Stream<LoginState> _mapLoginFailedWithStatusToState(
    // for login status > 100
    String uid,
    int status,
  ) async* {
    yield LoginState.loginError(state.currentState, state.signInMethod, status);
  } // end of _mapLoginFailedWithStatusToState

  Stream<LoginState> _mapInvitationLoginFailedToState(
    String inv,
    String country,
    String uid,
    int status,
  ) async* {
    try {
      switch (status) {
        case 0:
          yield LoginState.success(1, state.signInMethod, uid);
          break;
        case 1:
          yield LoginState.userFull(state.signInMethod);
          break;
        case 6:
          yield LoginState.invIsWrong(state.currentState, uid, state.loginVid);
          break;
        case 4:
          yield LoginState.failure(
            state.currentState,
            state.signInMethod,
            state.loginVid,
            state.loginInv,
            state.loginCountry,
          );
          break;
        case 7:
          yield LoginState.invExpired(
            state.signInMethod,
            state.loginUid,
            state.loginInv,
            state.loginCountry,
          );
          break;
      }
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        state.signInMethod,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  }

  Stream<LoginState> _mapEmailChangedToState(String email) async* {
    yield state.update(isEmailValid: Validators.isValidEmail(email));
  }

  Stream<LoginState> _mapPasswordChangedToState(String password) async* {
    yield state.update(isPasswordValid: Validators.isValidPassword(password));
  }

  Stream<LoginState> _mapPhoneChangedToState(String phone) async* {
    yield state.update(isPhoneValid: Validators.isValidPhone(phone));
  }

  Stream<LoginState> _mapSmsCodeChangedToState(String smsCode) async* {
    yield state.update(isSmsCodeValid: Validators.isValidSmsCode(smsCode));
  }

  Stream<LoginState> _mapLoginWithGooglePressedToState(
    String country,
    String inv,
  ) async* {
    User? user;
    try {
      yield LoginState.loading(state.signInMethod);
      final sw1 = UserRepository.loginPerfTrace ? (Stopwatch()..start()) : null;
      user = await _userRepository.signInWithGoogle();
      if (sw1 != null) {
        debugPrint(
          '[LOGINPERF] signInWithGoogle = ${sw1.elapsedMilliseconds}ms',
        );
      }
    } catch (err) {
      // Genuine sign-in error (network, Firebase credential, etc.).
      yield LoginState.firebaseLoginFailure(
        state.signInMethod,
        state.loginUid,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
      return;
    }
    if (user == null) {
      // User cancelled the account picker, or sign-in produced no user.
      // Dismiss the spinner and return to the form without an error dialog.
      yield LoginState.cancelled(state.signInMethod);
      return;
    }
    try {
      final sw2 = UserRepository.loginPerfTrace ? (Stopwatch()..start()) : null;
      var loginResult = await _userRepository.aumLogin(
        country,
        inv,
      ); // vertriz login procedure
      if (sw2 != null) {
        debugPrint('[LOGINPERF] aumLogin = ${sw2.elapsedMilliseconds}ms');
      }
      switch (loginResult) {
        case 0:
          yield LoginState.success(-1, state.signInMethod, user.uid);
          break;
        case 1:
          yield LoginState.newUser(state.signInMethod, user.uid);
          break;
        case 2:
          yield LoginState.failure(
            state.currentState,
            state.signInMethod,
            state.loginVid,
            state.loginInv,
            state.loginCountry,
          );
          break;

        default:
          yield LoginState.loginError(
            state.currentState,
            state.signInMethod,
            loginResult,
          );
      }
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        state.signInMethod,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  } //end of _mapLoginWithGooglePressedToState

  Stream<LoginState> _mapLoginWithApplePressedToState(
    String country,
    String inv,
  ) async* {
    User? user;
    try {
      yield LoginState.loading(state.signInMethod);
      user = await _userRepository.signInWithApple();
    } catch (err) {
      // Genuine sign-in error (network, Firebase credential, etc.).
      yield LoginState.firebaseLoginFailure(
        state.signInMethod,
        state.loginUid,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
      return;
    }
    if (user == null) {
      // User cancelled the Apple sheet, or sign-in produced no user.
      // Dismiss the spinner and return to the form without an error dialog.
      yield LoginState.cancelled(state.signInMethod);
      return;
    }
    try {
      var loginResult = await _userRepository.aumLogin(
        country,
        inv,
      ); // vertriz login procedure
      switch (loginResult) {
        case 0:
          yield LoginState.success(-1, state.signInMethod, user.uid);
          break;
        case 1:
          yield LoginState.newUser(state.signInMethod, user.uid);
          break;
        case 2:
          yield LoginState.failure(
            state.currentState,
            state.signInMethod,
            state.loginVid,
            state.loginInv,
            state.loginCountry,
          );
          break;

        default:
          yield LoginState.loginError(
            state.currentState,
            state.signInMethod,
            loginResult,
          );
      }
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        state.signInMethod,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  } //end of _mapLoginWithApplePressedToState

  Stream<LoginState> _mapInvitationLoginPressedToState(
    String inv,
    String uid,
  ) async* {
    try {
      int loginResult;
      if (demoApp) {
        loginResult = await _userRepository.invitationLoginDemo(inv);
      } else {
        loginResult = await _userRepository.invitationLoginWithUid(inv);
      }
      switch (loginResult) {
        case 0:
          yield LoginState.success(1, state.signInMethod, uid);
          // write seed 2 to secure storage
          bool write = true;
          try {
            String? sd2 = await storage.read(key: 'sd2');
            if (sd2 != null) {
              write = false;
            } // end if (sd2 != null)
          } catch (e) {
            write = true;
          } // end try
          if (write) {
            storage.write(
              key: 'sd2',
              value: ftzSecretOneSeed2R,
            ); //   put Account key in secure storage
          } // end if (write)
          break;
        case 1:
          yield LoginState.userFull(state.signInMethod);
          break;
        case 2:
          yield LoginState.userLoggedIn(state.signInMethod);
          break;
        case 4:
          yield LoginState.failure(
            state.currentState,
            state.signInMethod,
            state.loginVid,
            state.loginInv,
            state.loginCountry,
          );
          break;
        case 6:
          yield LoginState.invIsWrong(state.currentState, uid, state.loginInv);
          break;
        case 7:
          yield LoginState.invExpired(
            state.signInMethod,
            state.loginUid,
            state.loginInv,
            state.loginCountry,
          );
          break;
      }
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        state.signInMethod,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  }

  Stream<LoginState> _mapSendSmsPressedToState(String phone) async* {
    try {
      await _userRepository.sendCodeToPhoneNumber(phone);
      yield LoginState.smsVerification(state.currentState);
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        4,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  }

  Stream<LoginState> _mapLoginWithPhonePressedToState(String smsCode) async* {
    try {
      await _userRepository.signInWithPhone(smsCode);
      yield LoginState.success(state.currentState, 4, state.loginUid);
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        4,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  }

  Stream<LoginState> _mapTosOKTabbedToState(tosOK) async* {
    yield state.update(isTosOK: tosOK, loginStatus: -1);
  }

  Stream<LoginState> _mapLoginWithCredentialsPressedToState({
    required String email,
    required String password,
  }) async* {
    yield LoginState.loading(state.currentState);
    try {
      await _userRepository.signInWithCredentials(email, password);
      yield LoginState.success(state.currentState, 6, state.loginUid);
    } catch (_) {
      yield LoginState.failure(
        state.currentState,
        4,
        state.loginVid,
        state.loginInv,
        state.loginCountry,
      );
    }
  }

  Stream<LoginState> _mapWrongVidToState(vidOK) async* {
    yield LoginState.invIsWrong(
      state.currentState,
      state.loginUid,
      state.loginVid,
    );
  }

  Stream<LoginState> _mapVidChangedToState(vid) async* {
    yield state.update(loginVid: vid);
  }

  Stream<LoginState> _mapInvChangedToState(inv) async* {
    yield state.update(loginInv: inv);
  }

  Stream<LoginState> _mapCountryChangedToState(country) async* {
    yield state.update(loginCountry: country);
  }
}
