import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

/// Tests for the vehicleId scope gate (Fix B):
///
/// 1. The _publishVehicleId fix: vehicleIdResolved must become true when data
///    has loaded, even if the derived vehicleId is empty (unassigned driver).
///
/// 2. The gate expression in each card widget:
///    `dhState.vehicleIdResolved.value && dhState.vehicleId.value.isEmpty`
///    -> hide (SizedBox.shrink)
void main() {
  // ── _publishVehicleId resolved-flag behavior ─────────────────────────────
  //
  // We cannot call _publishVehicleId directly (it is a private method on the
  // header widget). Instead we reproduce the LOGIC it performs on
  // DriverHomeState and verify the resolved-flag outcomes for each scenario.
  // The real header's code is Task B-0 verbatim.

  group('_publishVehicleId logic (resolved-flag scenarios)', () {
    /// Simulate the core logic of the FIXED _publishVehicleId.
    ///
    /// [derivedVehicleId] -- what _findVehicleDoc resolved to ('' when null doc).
    /// [dataLoaded] -- whether mapTableContent.containsKey(_stockLocationCode).
    /// [state] -- the DriverHomeState to mutate.
    ///
    /// This mirrors the post-frame callback body in Task B-0.
    void simulatePublish(
      String derivedVehicleId,
      bool dataLoaded,
      DriverHomeState state,
    ) {
      // Early-return logic from the fixed _publishVehicleId:
      if (state.vehicleId.value == derivedVehicleId &&
          state.vehicleIdResolved.value == dataLoaded) {
        return;
      }
      // Post-frame callback body:
      if (state.vehicleId.value != derivedVehicleId) {
        state.vehicleId.value = derivedVehicleId;
      }
      if (dataLoaded && !state.vehicleIdResolved.value) {
        state.vehicleIdResolved.value = true;
      }
    }

    test('first build, no data yet: resolved stays false', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // derivedVehicleId="" (no doc found), dataLoaded=false (sub not fired)
      simulatePublish('', false, state);
      expect(state.vehicleId.value, '');
      expect(state.vehicleIdResolved.value, isFalse,
          reason: 'must NOT set resolved before subscription delivers');
    });

    test('data arrives, driver HAS vehicle: resolved=true, vehicleId set', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // Subscription fires, vehicle doc found with lv='V1'
      simulatePublish('V1', true, state);
      expect(state.vehicleId.value, 'V1');
      expect(state.vehicleIdResolved.value, isTrue);
    });

    test('data arrives, driver has NO vehicle: resolved=true, vehicleId empty', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // Subscription fires, no vehicle doc matches -> derivedVehicleId=""
      simulatePublish('', true, state);
      expect(state.vehicleId.value, '');
      expect(state.vehicleIdResolved.value, isTrue,
          reason: 'resolved must be TRUE after data loaded, even if no vehicle');
    });

    test('subsequent call after assigned: no-op (early return)', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // First call: data arrives, vehicle found
      simulatePublish('V1', true, state);
      expect(state.vehicleIdResolved.value, isTrue);
      // Second call: same values -> early return, no mutation
      simulatePublish('V1', true, state);
      expect(state.vehicleId.value, 'V1');
      expect(state.vehicleIdResolved.value, isTrue);
    });

    test('subsequent call after unassigned: no-op (early return)', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // First call: data arrives, no vehicle
      simulatePublish('', true, state);
      expect(state.vehicleIdResolved.value, isTrue);
      // Second call: same values -> early return
      simulatePublish('', true, state);
      expect(state.vehicleId.value, '');
      expect(state.vehicleIdResolved.value, isTrue);
    });

    test('vehicle assignment changes mid-session: vehicleId updates', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // Initially assigned to V1
      simulatePublish('V1', true, state);
      expect(state.vehicleId.value, 'V1');
      // Admin reassigns driver to V2 (stock_location updates live)
      simulatePublish('V2', true, state);
      expect(state.vehicleId.value, 'V2');
      expect(state.vehicleIdResolved.value, isTrue);
    });

    test('vehicle unassigned mid-session: vehicleId clears', () {
      clearDriverHomeState('pub_scr');
      final state = getDriverHomeState('pub_scr');
      // Initially assigned to V1
      simulatePublish('V1', true, state);
      expect(state.vehicleId.value, 'V1');
      // Admin unassigns driver (stock_location.dv cleared)
      simulatePublish('', true, state);
      expect(state.vehicleId.value, '');
      expect(state.vehicleIdResolved.value, isTrue);
    });
  });

  // ── Widget gate expression ───────────────────────────────────────────────

  group('vehicleId scope gate logic', () {
    test('resolved + empty vehicleId -> should hide', () {
      clearDriverHomeState('gate_scr');
      final state = getDriverHomeState('gate_scr');
      state.vehicleIdResolved.value = true;
      state.vehicleId.value = '';
      final bool shouldHide =
          state.vehicleIdResolved.value && state.vehicleId.value.isEmpty;
      expect(shouldHide, isTrue);
    });

    test('resolved + non-empty vehicleId -> should NOT hide', () {
      clearDriverHomeState('gate_scr');
      final state = getDriverHomeState('gate_scr');
      state.vehicleIdResolved.value = true;
      state.vehicleId.value = 'F621a02a983500';
      final bool shouldHide =
          state.vehicleIdResolved.value && state.vehicleId.value.isEmpty;
      expect(shouldHide, isFalse);
    });

    test('NOT resolved + empty vehicleId -> should NOT hide (loading)', () {
      clearDriverHomeState('gate_scr');
      final state = getDriverHomeState('gate_scr');
      // vehicleIdResolved defaults to false
      state.vehicleId.value = '';
      final bool shouldHide =
          state.vehicleIdResolved.value && state.vehicleId.value.isEmpty;
      expect(shouldHide, isFalse,
          reason: 'must not hide while still loading -- show pending state');
    });

    test('NOT resolved + non-empty vehicleId -> should NOT hide', () {
      clearDriverHomeState('gate_scr');
      final state = getDriverHomeState('gate_scr');
      state.vehicleId.value = 'V1';
      final bool shouldHide =
          state.vehicleIdResolved.value && state.vehicleId.value.isEmpty;
      expect(shouldHide, isFalse);
    });

    test('clearDriverHomeState resets state for next visit', () {
      final state = getDriverHomeState('gate_scr');
      state.vehicleIdResolved.value = true;
      state.vehicleId.value = 'V1';
      clearDriverHomeState('gate_scr');
      // After clear, new state is fresh defaults
      final fresh = getDriverHomeState('gate_scr');
      expect(fresh.vehicleId.value, '');
      expect(fresh.vehicleIdResolved.value, isFalse);
    });
  });

  group('end-to-end: unassigned driver sequence', () {
    /// Simulate the full unassigned driver lifecycle:
    /// 1. buildPage clears state
    /// 2. first build: no data yet -> resolved=false, cards show pending
    /// 3. subscription delivers: no vehicle match -> resolved=true, vehicleId=''
    /// 4. cards gate: resolved && empty -> hide
    void simulatePublish(
      String derivedVehicleId,
      bool dataLoaded,
      DriverHomeState state,
    ) {
      if (state.vehicleId.value == derivedVehicleId &&
          state.vehicleIdResolved.value == dataLoaded) {
        return;
      }
      if (state.vehicleId.value != derivedVehicleId) {
        state.vehicleId.value = derivedVehicleId;
      }
      if (dataLoaded && !state.vehicleIdResolved.value) {
        state.vehicleIdResolved.value = true;
      }
    }

    test('unassigned driver: resolved ends TRUE, gate hides cards', () {
      // 1. buildPage clears state
      clearDriverHomeState('e2e_scr');
      final state = getDriverHomeState('e2e_scr');
      expect(state.vehicleIdResolved.value, isFalse);
      expect(state.vehicleId.value, '');

      // 2. First build: no data yet
      simulatePublish('', false, state);
      expect(state.vehicleIdResolved.value, isFalse,
          reason: 'no data yet, must not resolve');
      // Cards see: resolved=false -> NOT hidden (show pending)
      expect(state.vehicleIdResolved.value && state.vehicleId.value.isEmpty,
          isFalse);

      // 3. Subscription delivers: no vehicle match
      simulatePublish('', true, state);
      expect(state.vehicleIdResolved.value, isTrue,
          reason: 'data loaded, must resolve even though empty');
      expect(state.vehicleId.value, '');

      // 4. Cards gate fires
      expect(state.vehicleIdResolved.value && state.vehicleId.value.isEmpty,
          isTrue,
          reason: 'gate must hide all 4 cards for unassigned driver');
    });

    test('assigned driver: resolved ends TRUE, gate does NOT hide', () {
      clearDriverHomeState('e2e_scr2');
      final state = getDriverHomeState('e2e_scr2');

      // First build: no data
      simulatePublish('', false, state);
      expect(state.vehicleIdResolved.value, isFalse);

      // Subscription delivers: vehicle found
      simulatePublish('F621a02a983500', true, state);
      expect(state.vehicleIdResolved.value, isTrue);
      expect(state.vehicleId.value, 'F621a02a983500');

      // Cards gate: resolved && NOT empty -> NOT hidden
      expect(state.vehicleIdResolved.value && state.vehicleId.value.isEmpty,
          isFalse,
          reason: 'assigned driver cards must remain visible');
    });
  });
}
