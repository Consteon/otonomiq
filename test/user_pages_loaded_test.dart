import 'package:flutter_test/flutter_test.dart';
import 'package:redux/redux.dart';
import 'package:otonomiq/api.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/global.dart';

/// `userPagesLoaded()` decides whether the shell paints the user's home or an
/// explicit loading/retry state. Getting it wrong reproduces the reported bug:
/// a sign-in form rendered underneath a live navbar after a successful login.
///
/// The `home` key in screenUIComponent is a SHARED slot — the sign-in page is
/// installed there before auth — so provenance (which lif the loaded pages came
/// from) is the only thing that can tell the two apart.
void main() {
  const String signupLif = '18MAwk8_signup_lif_key';
  const String userLif = '1hdcFg4_user_lif_key';

  void setSignupLif(String? value) {
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#GUEST_LIF': value})),
    );
  }

  setUp(() {
    // The real store is built inside a startup routine that also touches
    // cameras, so stand up a bare one here instead.
    transactionStore = Store<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(<String, dynamic>{}),
    );
    loadedPagesLif = '';
    setSignupLif(signupLif);
  });

  test('no pages loaded yet -> false', () {
    expect(userPagesLoaded(), isFalse);
  });

  test('sign-in pages loaded -> false (this is the bug being prevented)', () {
    loadedPagesLif = signupLif;
    expect(userPagesLoaded(), isFalse);
  });

  test('user pages loaded -> true', () {
    loadedPagesLif = userLif;
    expect(userPagesLoaded(), isTrue);
  });

  test('a failed fetch must not flip it true', () {
    // readSettings assigns `settingKey` BEFORE the HTTP call, so after a
    // timeout settingKey already names the user lif. loadedPagesLif is written
    // only on success, which is exactly why the shell reads this and not that.
    loadedPagesLif = signupLif; // last SUCCESSFUL load was the sign-in pages
    settingKey = userLif; // the fetch that failed was aiming at the user lif
    expect(userPagesLoaded(), isFalse);
  });

  test('unknown signup lif -> loaded pages are treated as the user\'s', () {
    // #GUEST_LIF is absent on some cold-start orderings. Failing closed there
    // would strand a user who does have real pages loaded behind a spinner.
    setSignupLif(null);
    loadedPagesLif = userLif;
    expect(userPagesLoaded(), isTrue);
  });

  test('empty loadedPagesLif beats a null signup lif', () {
    setSignupLif(null);
    loadedPagesLif = '';
    expect(userPagesLoaded(), isFalse);
  });
}
