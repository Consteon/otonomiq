import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/login/bloc_login/login_state.dart';

// Fix A: the blocking login spinner must be driven by a single source of
// truth (LoginState.isSubmitting) so every terminal / transitional state
// dismisses it. Previously the login_form predicate used
// `inLoginProcess && !isSuccess && !isFailure`, which stayed true for the
// `newUser` state -> spinner stuck over the invitation screen.
void main() {
  group('loginSpinnerVisible', () {
    test('visible while loading', () {
      expect(loginSpinnerVisible(LoginState.loading(1)), isTrue);
    });

    test('hidden for new-user (invitation) state', () {
      // Regression guard for the stuck-spinner-over-invitation bug.
      expect(loginSpinnerVisible(LoginState.newUser(1, 'uid123')), isFalse);
    });

    test('hidden on success', () {
      expect(loginSpinnerVisible(LoginState.success(1, 1, 'uid123')), isFalse);
    });

    test('hidden on failure', () {
      expect(
        loginSpinnerVisible(LoginState.failure(1, 1, 'vid', 'inv', 'country')),
        isFalse,
      );
    });

    test('hidden when idle/empty', () {
      expect(loginSpinnerVisible(LoginState.empty(1)), isFalse);
    });
  });
}
