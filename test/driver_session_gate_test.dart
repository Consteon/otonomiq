import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // Seed the Redux store once (mirrors driver_home_support_test.dart). The
  // global `transactionStore` is null in a bare test, so any dispatch/read
  // would throw NoSuchMethod without this.
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  group('driver session gate -- Redux state transitions', () {
    test('setting #has_user_login stores the VID', () {
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': '12345'})));
      final String vid =
          (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(vid, '12345');
    });

    test('clearing #has_user_login resets to empty string', () {
      // Pre-condition: VID is set from previous test.
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': ''})));
      final String vid =
          (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(vid, '');
    });

    test('#has_user_login survives unrelated dispatch (per-key merge)', () {
      // Set a VID.
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': '99999'})));
      // Dispatch unrelated keys (mirrors main.dart bootstrap dispatch).
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REFRESH': false,
        '#DATA_OK': false,
      })));
      // VID must survive the merge.
      final String vid =
          (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(vid, '99999');
    });
  });

  group('driver session gate -- DriverHomeState clear on logout', () {
    test('clearDriverHomeState removes the per-scrName state', () {
      // Seed state for a screen.
      final state = getDriverHomeState('TestDriverScreen');
      state.vehicleId.value = 'V123';
      state.confirmed.value = true;
      state.vehicleIdResolved = true;

      // Verify it exists.
      expect(driverHomeStates.containsKey('TestDriverScreen'), true);

      // Clear it (mirrors logout flow).
      clearDriverHomeState('TestDriverScreen');

      // Verify it is removed.
      expect(driverHomeStates.containsKey('TestDriverScreen'), false);
    });

    test('getDriverHomeState creates fresh state after clear', () {
      clearDriverHomeState('FreshScreen');
      final state = getDriverHomeState('FreshScreen');
      expect(state.vehicleId.value, '');
      expect(state.confirmed.value, false);
      expect(state.vehicleIdResolved, false);
    });
  });

  group('driver session gate -- logout flow end-to-end (Redux only)', () {
    test('full logout clears #has_user_login and DriverHomeState', () {
      // Setup: driver logged in.
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': '54321'})));
      final state = getDriverHomeState('DriverHome');
      state.vehicleId.value = 'V789';
      state.confirmed.value = true;

      // Execute logout (mirrors _onLogoutTap minus storage + navigation).
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': ''})));
      clearDriverHomeState('DriverHome');

      // Verify.
      final String vid =
          (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(vid, '');
      expect(driverHomeStates.containsKey('DriverHome'), false);
    });
  });

  group('driver session gate -- self-skip read pattern', () {
    test('non-empty #has_user_login is truthy for self-skip gate', () {
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': '11111'})));
      final String existingVid =
          (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(existingVid.isNotEmpty, true);
    });

    test('empty #has_user_login is falsy for self-skip gate', () {
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#has_user_login': ''})));
      final String existingVid =
          (transactionStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(existingVid.isNotEmpty, false);
    });

    test('null #has_user_login (never set) is falsy for self-skip gate', () {
      // Create a fresh store without #has_user_login.
      final freshStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
      final String existingVid =
          (freshStore.state.screenTx['#has_user_login'] ?? '').toString();
      expect(existingVid.isNotEmpty, false);
    });
  });

  group('driver session gate -- persist helper signatures', () {
    test('persist/clear/read helpers exist with the expected signatures', () {
      // Actual storage I/O requires platform bindings (integration test only).
      // This is a compile-time signature check: binding each helper to a
      // strongly-typed function variable fails to compile if a signature
      // changes. The runtime expect just keeps the tear-offs live.
      final Future<void> Function(String) persist = persistDriverLogin;
      final Future<void> Function() clear = clearDriverLogin;
      final Future<String?> Function() read = readDriverLogin;
      expect(persist, isNotNull);
      expect(clear, isNotNull);
      expect(read, isNotNull);
    });
  });
}
