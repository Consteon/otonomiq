import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/login/bloc_login/login_state.dart';

// Fix B: when a social sign-in (Google/Apple) returns null — the user
// cancelled the account picker, or a silent failure produced no user — the
// bloc must reach a terminal, NON-error state so the spinner dismisses and the
// form becomes usable again. Previously the Google handler emitted nothing
// after `LoginState.loading()`, leaving the spinner stuck forever.
void main() {
  group('LoginState.cancelled', () {
    test('dismisses the spinner', () {
      expect(loginSpinnerVisible(LoginState.cancelled(1)), isFalse);
    });

    test('is not a failure (no error dialog)', () {
      expect(LoginState.cancelled(1).isFailure, isFalse);
    });

    test('is not a success (no LoggedIn)', () {
      expect(LoginState.cancelled(1).isSuccess, isFalse);
    });

    test('has empty loginUid (no accidental invitation navigation)', () {
      // login_form listener routes to _Invitation when loginUid != ''.
      expect(LoginState.cancelled(1).loginUid, '');
    });

    test('is not mid-process', () {
      expect(LoginState.cancelled(1).inLoginProcess, isFalse);
    });

    test('preserves the sign-in method passed in', () {
      expect(LoginState.cancelled(7).signInMethod, 7);
    });
  });
}
