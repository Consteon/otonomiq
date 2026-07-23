import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/model/otq_state.dart';
import 'package:otonomiq/widget/attendance_qr_selfie_gps_verify.dart';

// fakeGpsDialogText (widget/attendance_qr_selfie_gps_verify.dart) chooses the
// body text for the `fakeGpsAllowed:false` block dialog shown at 6 sites.
//
// OtqState.mock defaults to TRUE and is only overwritten inside the
// `pos.latitude != invalidLocation` branch of setAllDataAsync, so a GPS read
// that failed outright looks identical to a real mock provider unless gpsOn is
// consulted. These tests pin that split -- if the branch is dropped, a user
// with location services off is told to disable a fake-GPS app again.

void main() {
  group('fakeGpsDialogText', () {
    test('GPS never read (gpsOn false, mock default true) -> GPS message', () {
      final sensor = OtqState(); // gpsOn=false, mock=true straight from defaults
      expect(sensor.mock, isTrue, reason: 'guards the premise of this fix');
      expect(sensor.gpsOn, isFalse);
      expect(fakeGpsDialogText(sensor, []), 'GPS tidak aktif');
    });

    test('real mock provider (gpsOn true, mock true) -> fake-GPS message', () {
      final sensor = OtqState();
      sensor.gpsOn = true; // a valid position WAS read...
      sensor.mock = true; // ...and it reported isMocked
      expect(fakeGpsDialogText(sensor, []), 'Nonaktifkan Fake GPS');
    });

    test('sheet slot 31 overrides the GPS default', () {
      final textArray = List<dynamic>.filled(32, null);
      textArray[31] = 'Aktifkan lokasi dulu';
      expect(fakeGpsDialogText(OtqState(), textArray), 'Aktifkan lokasi dulu');
    });

    test('slot 31 empty or absent falls back to the default', () {
      final blank = List<dynamic>.filled(32, null);
      blank[31] = '';
      expect(fakeGpsDialogText(OtqState(), blank), 'GPS tidak aktif');
      expect(fakeGpsDialogText(OtqState(), List<dynamic>.filled(24, null)),
          'GPS tidak aktif');
      expect(fakeGpsDialogText(OtqState(), []), 'GPS tidak aktif');
    });

    test('short textArray does not RangeError on the mock branch', () {
      // The 5 unguarded call sites used a bare textArray[23]; a tenant sheet
      // with fewer than 24 slots threw RangeError instead of showing a dialog.
      final sensor = OtqState();
      sensor.gpsOn = true;
      expect(fakeGpsDialogText(sensor, []), 'Nonaktifkan Fake GPS');
      expect(fakeGpsDialogText(sensor, List<dynamic>.filled(23, null)),
          'Nonaktifkan Fake GPS');
    });

    test('slot 23 still drives the mock branch when present', () {
      final sensor = OtqState();
      sensor.gpsOn = true;
      final textArray = List<dynamic>.filled(24, null);
      textArray[23] = 'Matikan aplikasi fake GPS';
      expect(fakeGpsDialogText(sensor, textArray), 'Matikan aplikasi fake GPS');
    });
  });
}
