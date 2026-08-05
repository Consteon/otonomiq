import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import '../part/android_part/ftz_mobile_scanner.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
// import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../crypto/auth_crypto.dart';
import '../firestore_repository/firestore_generic_repository.dart';
// import 'package:vibration/vibration.dart';
import '../global.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';
import 'biometric_gate.dart';
import 'ftz_scanner_screen.dart';
import 'photo_camera.dart';

part '../part/build_part/attend_qr_gps_selfie_state_part.dart';

/// Body text for the `fakeGpsAllowed:false` block dialog.
///
/// [OtqState.mock] defaults to `true` and is only overwritten inside the
/// `pos.latitude != invalidLocation` branch of `setAllDataAsync`. So a GPS read
/// that failed outright (service off, permission denied, no fix) arrives here
/// looking exactly like a real mock provider, and the user gets told to turn
/// off a fake-GPS app they are not running. [OtqState.gpsOn] is the one flag
/// that separates them: it is only set true once a valid position was read.
///
/// Both cases still block attendance -- this only corrects the diagnosis.
/// Sheet text slot 31 is optional; the Indonesian default stands in when the
/// tenant sheet has not defined it (same guarded pattern as slot 30).
String fakeGpsDialogText(OtqState data, List textArray) {
  if (!data.gpsOn) {
    return (textArray.length > 31 &&
            textArray[31] != null &&
            textArray[31].toString().isNotEmpty)
        ? textArray[31].toString()
        : 'GPS tidak aktif';
  }
  return (textArray.length > 23 && textArray[23] != null)
      ? textArray[23].toString()
      : 'Nonaktifkan Fake GPS';
}

/*
  Widget for employee attendance.
  component:
    type : location
    opMode :
      qr-single = scan lqr and verify
      selfie = take selfie
      checker-lqr-single
      checker-lqr-photo-single
      checker-lqr-continuous
      checker-lqr-photo-continuous
    url : image url
    text : display/dialog text, diamond separated
    route : next route
    flag : flag to be written in output
    imHeight : stored acquired image height (pixels)
    imWidth : stored acquired image width (pixels)
    folder : folder in Google Cloud storage to store acquired image
    filename : acquired image name (without .png)
    lockList : list of valid location [[lat1,lon1],[lat2,lon2],[lat3,lon3]]
    tolerance : integer in meter (default 50)
    actionLast : last action = check-in | check-out
    width : displayed image (from url) width (height will be calculated)
    displayMode : deprecated - ignored
    timeClockOut1: utc millisecond to determine attendance scenario
    timeClockOut2: 1599124581957 to determine attendance scenario

    algorithm :
       get current position (with accuracy < 50 m ???)
       if scanQr = false => selfie & record log
       else
         if (locationArray == null) then selfie & record loc
         else
           check all location with current position if there is a location within tolerance range
           if found => scan Qr => verifyQr
             if verified => record qr input and loc
             if not verified => rescan for 3 X if fail then selfie & record loc
           else selfie & record loc
        if combo = true
          scanQr
          selfie
          display route
          with same location algorithm as above
        end if

 */
class AttendQrGpsSelfie extends StatefulWidget {
  const AttendQrGpsSelfie({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final bool single;

  @override
  AttendQrGpsSelfieState createState() => AttendQrGpsSelfieState();
} // end of class AttendQrGpsSelfie

class AttendQrGpsSelfieState extends State<AttendQrGpsSelfie> {
  /// Pads a text array (output of diamondTextToList) to at least 31 elements.
  /// Index 26 defaults to 'Scan QR' (existing QR scanner title).
  /// Indexes 27-30 default to '' (filled from sheet config when present).
  static List padTextArray(List input) {
    final List result = List.from(input);
    while (result.length < 31) {
      result.add(result.length == 26 ? 'Scan QR' : '');
    }
    return result;
  }

  bool change = true;
  final controller = TextEditingController(text: '-');
  bool tapped = false;
  dynamic media;
  double h = 0;
  double w = 0;

  @override
  Widget build(BuildContext context) {
    String selfieUrl = '';

    Future<dynamic> attendanceSuccessDialog({
      String title = 'Success',
      String message1 = '',
      String message2 = '',
      String message3 = '',
      String okString = 'Ok',
    }) async {
      vibrate(duration: 50);
      await Get.dialog(
        AlertDialog(
          // dialog 3
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message1),
              Container(height: 12),
              Text(message2),
              Container(height: 12),
              Text(message3),
            ],
          ),

          actions: <Widget>[
            TextButton(
              child: Text(okString),
              onPressed: () {
                Get.back();
                // Navigator.of(con).pop();
              },
            ),
          ],
        ),
      );
      return 1;
    } // end of checkerSuccessDialog

    Future<String?> attendanceDialog({
      String title = '',
      String message = '',
      String okString = 'Ok',
    }) async {
      return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            // dialog 3
            title: Text(title),
            content: Container(
              alignment: const Alignment(0.0, 0.0),
              height: dialogHeight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(message)],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(okString),
                onPressed: () {
                  routeStack.pop();
                  Get.back();
                  // Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } // end of checkerDialog

    /*
    Future<String?> attendanceTakeQR(
        String label, String scrName, var component, String caller) async {}
    moved to part '../part/attend_qr_gps_selfie_state_part.dart';
    */

    // Future<String?> attendanceTakeQR(
    //     String label, String scrName, var component, String caller) async {

    Future<String> takePicture(String lens) async {
      // get selfie, save to firebase, then return url to selfie image
      List<CameraDescription>? cams =
          transactionStore.state.screenTx['#CAMS'] as List<CameraDescription>?;
      if (cams == null || cams.isEmpty) return emptyImageUrl;
      String selfieUrl = await getPhotoCameraImage(
        cams,
        widget.component['label'] ?? 'Camera',
        lens,
        (widget.component['imgWidth'] ?? 540) >
                (widget.component['imgHeight'] ?? 540)
            ? widget.component['imgWidth'] ?? 540
            : widget.component['imgHeight'] ?? 540,
        widget.component['quality'] ?? 80,
        widget.component['folder'] ?? 'default',
        widget.component['filename'] ?? const Uuid().v4().replaceAll('-', ''),
        h,
        w,
      );
      return selfieUrl;
    } // end of takePicture

    Future saveData(String scrName, String locString) async {
      // TimerBloc timerBloc = transactionStore.state.screenTx['#TIMER_BLOC'];
      var route = widget.component['route'] ?? widget.scrName;
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#NEXTROUTE': route,
            '#TIMER_CONTEXT': context,
            '#TIMER_DURATION': widget.component['delay'] ?? 5,
          }),
        ),
      ); // set state #NEXTROUTE route that will be displayed after waitScreen
      int timeStamp = await getRealTime();
      saveSend(timeStamp, scrName, widget.component, locString, defaultVid());
    } // end of saveData

    String? locationNameFromLqrRef(double lat, double lng, double accuracy) {
      final dynamic lqrList = transactionStore.state.screenTx['#LQR_LIST'];
      if (lqrList == null || lqrList is! Map || lqrList.isEmpty) return null;
      try {
        String? nearestName;
        double minDistance = double.infinity;
        for (final entry in lqrList.entries) {
          final List data = entry.value as List;
          final double targetLat = (data[1] as num).toDouble();
          final double targetLng = (data[2] as num).toDouble();
          final double tolerance = (data[3] as num).toDouble();
          final double zone2 = tolerance + accuracy * 2;
          final double distance = Geolocator.distanceBetween(
            lat,
            lng,
            targetLat,
            targetLng,
          );
          if (distance <= zone2 && distance < minDistance) {
            minDistance = distance;
            nearestName = data[0].toString();
          }
        }
        return nearestName;
      } catch (_) {}
      return null;
    }

    // The scanned QR uniquely identifies its location; use ITS registered name
    // (#LQR_LIST[qrKey][0]) instead of the nearest-by-GPS name, which picks the
    // wrong site when two QRs (e.g. BSD A / BSD B) sit close together.
    String? locationNameFromScannedLqr(String? qrKey) {
      if (qrKey == null || qrKey.isEmpty) return null;
      final dynamic lqrList = transactionStore.state.screenTx['#LQR_LIST'];
      if (lqrList == null || lqrList is! Map) return null;
      final dynamic entry = lqrList[qrKey];
      if (entry is List && entry.isNotEmpty) {
        final String name = entry[0].toString();
        if (name.isNotEmpty) return name;
      }
      return null;
    }

    // Per-scanned-QR geofence. Returns true (→ caller aborts the write & shows
    // "Diluar Area Absensi") when out-of-position is NOT allowed AND the current
    // GPS is beyond the SCANNED QR's own tolerance zone. Opt-in via
    // outPositionAllowed:FALSE (default TRUE = out-of-position allowed = no gate),
    // same flag as the pre-scan geofence. Fail-open on missing data / parse error.
    // Zone = tolerance + accuracy*2 (same buffer as the pre-scan check here).
    Future<bool> blockIfOutsideScannedLqr(
      String? qrKey,
      double lat,
      double lng,
      double accuracy,
      List tArray,
    ) async {
      final bool outPositionAllowed =
          (widget.component['outPositionAllowed']?.toString().toUpperCase() ??
              'TRUE') !=
          'FALSE';
      if (outPositionAllowed) return false;
      if (qrKey == null || qrKey.isEmpty) return false;
      final dynamic lqrList = transactionStore.state.screenTx['#LQR_LIST'];
      if (lqrList == null || lqrList is! Map) return false;
      final dynamic entry = lqrList[qrKey];
      if (entry is! List || entry.length < 4) return false;
      double distance;
      double zone2;
      try {
        final double targetLat = (entry[1] as num).toDouble();
        final double targetLng = (entry[2] as num).toDouble();
        final double tolerance = (entry[3] as num).toDouble();
        zone2 = tolerance + accuracy * 2;
        distance = Geolocator.distanceBetween(lat, lng, targetLat, targetLng);
      } catch (_) {
        return false; // fail-open: never block on bad data
      }
      debugPrint(
        '[qr-geofence] scanned=$qrKey distance=${distance.toStringAsFixed(1)}m zone2=${zone2.toStringAsFixed(1)}m block=${distance > zone2}',
      );
      if (distance <= zone2) return false;
      if (context.mounted) {
        await Get.dialog(
          AlertDialog(
            title: Text(
              tArray.length > 24 ? tArray[24] : 'Diluar Area Absensi',
            ),
            content: Text(tArray.length > 25 ? tArray[25] : ''),
            actions: [
              TextButton(
                child: Text(tArray.length > 8 ? tArray[8] : 'OK'),
                onPressed: () => Get.back(),
              ),
            ],
          ),
        );
      }
      return true;
    }

    Future<void> processData(
      tArray,
      String dialogText1,
      String selfieUrl,
      fromLinkOption,
      OtqState locSensor,
    ) async {
      try {
        // actionLock('processData attendance_qr_selfie_gps_verify');
        // pool.play(scannerBeep);
        while (!locSensor.gpsDone) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        vibrate(duration: 100);
        widget.component['route'] =
            widget.component['route'] ?? home; //= default route = Home
        String locString = getLocationString(
          '',
          selfieUrl,
          fromLinkOption,
          locSensor,
        );
        await saveData(widget.scrName, locString); //= send record to FromLink

        // display dialog 1
        await attendanceSuccessDialog(
          title: tArray[2] ?? '-- Title --',
          message1: dialogText1,
          message2:
              locationNameFromLqrRef(
                locSensor.latitude,
                locSensor.longitude,
                locSensor.accuracy,
              ) ??
              (locSensor.isoCountryCode == '88'
                  ? ""
                  : "${locSensor.subLocality}, ${locSensor.locality.replaceFirst(RegExp(r'^[Kk]ecamatan\s+'), '')}, ${locSensor.subAdministrativeArea.replaceFirst(RegExp(r'^([Kk]abupaten|[Kk]ota)\s+'), '')} ${locSensor.postalCode}"),
          message3: '$plusMinus ${locSensor.accuracy.round()}m',
          okString: tArray[8],
        );
      } on PlatformException catch (err) {
        setDataOK(
          '1',
        ); // reload pages and display green anyway. So the app will not lock up
        errorReport(err);

        await Get.dialog(
          AlertDialog(
            // dialog 3
            title: Text(textList["Fail"]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textList["Retry"]),
                Text("System: (${err.toString()})"),
                const Text("Position: attendance_qr_selfie_gps_verify(1)"),
                Text(textList["ScreenShot"]),
              ],
            ),

            actions: <Widget>[
              TextButton(
                child: Text(textList["OK"]),
                onPressed: () {
                  Get.back();
                  //Navigator.of(context1).pop();
                },
              ),
            ],
          ),
        );
        /*
        await showDialog(
            context: context,
            builder: (BuildContext context1) {
              return AlertDialog(
                // dialog 3
                title: Text(textList["Fail"]),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(textList["Retry"]),
                    Text("System: (${err.toString()})"),
                    const Text("Position: attendance_qr_selfie_gps_verify(1)"),
                    Text(textList["ScreenShot"]),
                  ],
                ),

                actions: <Widget>[
                  TextButton(
                    child: Text(textList["OK"]),
                    onPressed: () {
                      Navigator.of(context1).pop();
                    },
                  ),
                ],
              );
            }); // end of dialog

         */
      } catch (e) {
        setDataOK(
          '1',
        ); // reload pages and display green anyway. So the app will not lock up
        errorReport(e);
        Get.dialog(
          AlertDialog(
            // dialog 3
            title: Text(textList["Fail"]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textList["Retry"]),
                Text("System: (${e.toString()})"),
                const Text("Position: attendance_qr_selfie_gps_verify(2)"),
                Text(textList["ScreenShot"]),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: Text(textList["OK"]),
                onPressed: () {
                  Get.back();
                  // Navigator.of(context1).pop();
                },
              ),
            ],
          ),
        );
        /*
        await showDialog(
            context: context,
            builder: (BuildContext context1) {
              return AlertDialog(
                // dialog 3
                title: Text(textList["Fail"]),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(textList["Retry"]),
                    Text("System: (${e.toString()})"),
                    const Text("Position: attendance_qr_selfie_gps_verify(2)"),
                    Text(textList["ScreenShot"]),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(textList["OK"]),
                    onPressed: () {
                      Navigator.of(context1).pop();
                    },
                  ),
                ],
              );
            }); // end of dialog
         */
        errorReport(e);
      }
    } // end of processData

    Future<String> qrDataProcess(
      String? inputText,
      String? selfieUrl,
      int tried,
      String originalScrName,
    ) async {
      String resultOk = empty;
      String finalQrText = empty;
      String mock = 'Unknown';
      // ponytail: ?? '' is intentional — diamondTextToList(String) would TypeError
      // on the old ?? [] fallback if component['text'] were null
      List tArray = padTextArray(
        diamondTextToList(widget.component['text'] ?? ''),
      );

      // Platform messages may fail, so we use a try/catch PlatformException.
      try {
        int nowTime = 0; // = await ntpTimeSec();
        Position? position;
        dynamic p;
        dynamic q;

        await Future.wait([
          // getCurrentPosition(desiredAccuracy: LocationAccuracy.high),
          getLocation(),
          omLqrReaderP(),
          osLqrMakerQ(),
          getRealTime(),
        ]).then((res) {
          position = res[0];
          p = res[1];
          q = res[2];
          nowTime = res[3];
        });

        if (inputText != empty) {
          //got qr
          finalQrText = await lqrVerify(p, q, inputText);
          if (finalQrText == errorString) {
            resultOk = empty;
          } else {
            resultOk =
                (transactionStore.state.screenTx['#LQR_LIST'][finalQrText]) !=
                    null
                ? transactionStore.state.screenTx['#LQR_LIST'][finalQrText][0]
                : empty;
          } // end if (finalQrText != empty && finalQrText != errorString)
        } else {
          resultOk = errorString;
        } // end (inputText != empty)

        if (resultOk != empty && resultOk != errorString) {
          late String? dialogText1;
          late String fromLinkOption;
          List<Placemark> placeMark = [];

          switch (widget.component['actionLast'] ?? "Checkpoint") {
            case 'clock-out':
              dialogText1 = tArray[3] ?? "--Bad Text#4--"; // scenario 1
              fromLinkOption = 'normal-clock-in';
              break;

            case 'clock-in':
              if ((widget.component['timeClockOut1'] ?? 0) <= nowTime &&
                  nowTime <= (widget.component['timeClockOut2'] ?? 0)) {
                dialogText1 = tArray[4] ?? "--Bad Text#5--"; // scenario 2
                fromLinkOption = 'normal-clock-out';
              } else {
                await showDialog(
                  // show dialog 34
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      // dialog 34
                      title: Text(tArray[15] ?? "--Bad Text#16--"),
                      content: Text(tArray[16] ?? "--Bad Text#17--"),
                      actions: <Widget>[
                        TextButton(
                          child: Text(
                            tArray[18] ?? "--Bad Text#19--",
                          ), // scenario 4
                          onPressed: () {
                            dialogText1 =
                                tArray[5] ?? "--Bad Text#6--"; // scenario 4
                            fromLinkOption = 'clock-out-overtime';
                            Navigator.of(context).pop();
                          },
                        ),
                        TextButton(
                          child: Text(tArray[17] ?? "--Bad Text#18--"),
                          onPressed: () {
                            dialogText1 =
                                tArray[6] ?? "--Bad Text#7--"; // scenario 3
                            fromLinkOption = 'forgot-clock-out';
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
              }
              break;

            default: // Checkpoint , scenario 5
              dialogText1 = tArray[7] ?? "--Bad Text#8--";
              fromLinkOption = 'checkpoint';
          } // end of switch

          if (position != null) {
            mock = position!.isMocked ? 'Mocked location' : 'True location';
            try {
              placeMark = await placemarkFromCoordinates(
                position!.latitude,
                position!.longitude,
              );
            } catch (e) {
              errorReport(e);
            }
            // Per-scanned-QR geofence (see blockIfOutsideScannedLqr). resultOk is
            // already the valid location name, so returning it exits the scan loop
            // cleanly without a rescan; setDataOK('2') leaves the page (no write).
            if (await blockIfOutsideScannedLqr(
              finalQrText,
              position!.latitude,
              position!.longitude,
              position!.accuracy,
              tArray,
            )) {
              setDataOK('2');
              return resultOk;
            }
            actionLock('qrDataProcess attendance_qr_selfie_gps_verify');
            // pool.play(scannerBeep);
            vibrate(duration: 100);
            /*
            String content = widget.component['flag'] ?? 'location';
            txfController[originalScrName]![1] = InputController(
                1, TextEditingController(text: content), content, content);
            content = nowTime.toString();
            txfController[originalScrName]![2] = InputController(
                2, TextEditingController(text: content), content, content);
            content = fromLinkOption;
            txfController[originalScrName]![3] = InputController(
                3, TextEditingController(text: content), content, content);
            content = finalQrText == empty ? '' : finalQrText;
            txfController[originalScrName]![4] = InputController(
                4, TextEditingController(text: content), content, content);
            content = position!.latitude.toString();
            txfController[originalScrName]![5] = InputController(
                5, TextEditingController(text: content), content, content);
            content = position!.longitude.toString();
            txfController[originalScrName]![6] = InputController(
                6, TextEditingController(text: content), content, content);
            content = selfieUrl ?? '';
            txfController[originalScrName]![7] = InputController(
                7, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty
                ? placeMark[0].isoCountryCode!
                : invalidCountry;
            txfController[originalScrName]![8] = InputController(
                8, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty ? placeMark[0].postalCode! : "";
            txfController[originalScrName]![9] = InputController(
                9, TextEditingController(text: content), content, content);
            content = cleanupString(
                placeMark.isNotEmpty ? placeMark[0].administrativeArea! : "");
            txfController[originalScrName]![10] = InputController(
                10, TextEditingController(text: content), content, content);
            content = cleanupString(placeMark.isNotEmpty
                ? placeMark[0].subAdministrativeArea!
                : "");
            txfController[originalScrName]![11] = InputController(
                11, TextEditingController(text: content), content, content);
            content = cleanupString(
                placeMark.isNotEmpty ? placeMark[0].locality! : "");
            txfController[originalScrName]![12] = InputController(
                12, TextEditingController(text: content), content, content);
            content = cleanupString(
                placeMark.isNotEmpty ? placeMark[0].subLocality! : "");
            txfController[originalScrName]![13] = InputController(
                13, TextEditingController(text: content), content, content);
            content = cleanupString(
                placeMark.isNotEmpty ? placeMark[0].thoroughfare! : "");
            txfController[originalScrName]![14] = InputController(
                14, TextEditingController(text: content), content, content);
            content = cleanupString(
                placeMark.isNotEmpty ? placeMark[0].subThoroughfare! : "");
            txfController[originalScrName]![15] = InputController(
                15, TextEditingController(text: content), content, content);
            */

            widget.component['route'] =
                widget.component['route'] ?? home; //= default route = Home
            OtqState locSensor = OtqState().getDataFrom(
              DateTime.fromMillisecondsSinceEpoch(nowTime),
              position!,
              placeMark,
            );
            String locString = getLocationString(
              finalQrText == empty ? '' : finalQrText,
              selfieUrl ?? '',
              fromLinkOption,
              locSensor,
            );
            saveData(originalScrName, locString); //= send record to FromLink
            routeStack.pop();
            await attendanceSuccessDialog(
              title: tArray[2] ?? '-- Title --',
              message1: dialogText1 ?? "Success message1",
              message2:
                  locationNameFromScannedLqr(finalQrText) ??
                  locationNameFromLqrRef(
                    locSensor.latitude,
                    locSensor.longitude,
                    locSensor.accuracy,
                  ) ??
                  (placeMark.isNotEmpty
                      ? "${placeMark[0].subLocality ?? ''}, ${(placeMark[0].locality ?? '').replaceFirst(RegExp(r'^[Kk]ecamatan\s+'), '')}, ${(placeMark[0].subAdministrativeArea ?? '').replaceFirst(RegExp(r'^([Kk]abupaten|[Kk]ota)\s+'), '')} ${placeMark[0].postalCode ?? ''}"
                      : ""),
              message3:
                  '$plusMinus ${position == null ? "-" : position!.accuracy.round()}m',
              okString: tArray[8],
            );
          } else {
            setDataOK(
              '1',
            ); // reload pages and display green anyway. So the app will not lock up
            await attendanceDialog(
              title: textList['Fail'],
              message: "Gagal, tidak dapat membaca lokasi GPS.",
              okString: tArray[8] ?? 'Ok',
            );
            resultOk = errorString;
          } // end if position
        } // end if (resultOk == empty || resultOk == errorString)
      } catch (e) {
        // display dialog fail, and play wrong beep
        errorReport(e);
        setDataOK(
          '1',
        ); // reload pages and display green anyway. So the app will not lock up
        Get.dialog(
          AlertDialog(
            // dialog 3
            title: Text(textList["Fail"]), // Scan again
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textList["Retry"]),
                Text("System: (${e.toString()})"),
                const Text("Position: otq_qr1(1)"),
                Text(textList["ScreenShot"]),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: Text(textList["OK"]),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
        resultOk = errorString;
      }
      return resultOk;
    } // end of qrDataProcess

    Future<void> acquireData(
      String actionType,
      List tArray,
      OtqState? locSensor,
    ) async {
      try {
        for (var i = 0; i < 10 && locSensor == null; i++) {
          await Future.delayed(Duration(milliseconds: 100 + i * 20));
        }
        if ((actionType != 'selfie') &&
            (actionType != 'back') &&
            (locSensor == null || !locSensor.gpsOn)) {
          await attendanceDialog(
            title: textList['Fail'],
            message: textList["GpsProblem"],
            okString: tArray[8] ?? 'Ok',
          );
          // await showDialog(
          //     context: context,
          //     builder: (BuildContext context) {
          //       return AlertDialog(
          //         // dialog 3
          //         title: Text(textList["Fail"]),
          //         content: Column(
          //           mainAxisSize: MainAxisSize.min,
          //           mainAxisAlignment: MainAxisAlignment.start,
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //           children: [
          //             Text(textList["GpsProblem"]),
          //           ],
          //         ),
          //         actions: <Widget>[
          //           TextButton(
          //             child: Text(tArray[8] ?? "--Bad GPS_SEND Text#9--"),
          //             onPressed: () {
          //               Navigator.of(context).pop();
          //             },
          //           ),
          //         ],
          //       );
          //     }); // end of dialog
          setDataOK('2');
        } else {
          bool cameraCancel = false;
          if (actionType == 'selfie' || actionType == 'back') {
            String lens = 'front';
            if (actionType == 'back') {
              lens = 'back';
            }
            try {
              List<CameraDescription>? cams =
                  transactionStore.state.screenTx['#CAMS']
                      as List<CameraDescription>?;
              if (cams == null || cams.isEmpty)
                throw Exception('No cameras available');
              transactionStore.dispatch(
                UpdateScreenTxAction(ScreenTransaction({'#CAMERA': true})),
              );
              selfieUrl = await getPhotoCameraImage(
                cams,
                widget.component['label'] ?? 'Camera',
                lens,
                (widget.component['imgWidth'] ?? 540) >
                        (widget.component['imgHeight'] ?? 540)
                    ? widget.component['imgWidth'] ?? 540
                    : widget.component['imgHeight'] ?? 540,
                widget.component['quality'] ?? 80,
                widget.component['folder'] ?? 'default',
                (widget.component['filename'] ?? 'file') +
                    '_' +
                    const Uuid().v4().replaceAll('-', ''),
                h,
                w,
              );
              if (selfieUrl == emptyImageUrl || selfieUrl == emptyString) {
                cameraCancel = true;
                setDataOK('2');
              } else {
                for (
                  var l = 0;
                  l < 50 && (locSensor == null || !locSensor.gpsDone);
                  l++
                ) {
                  await Future.delayed(Duration(milliseconds: 100 + l * 20));
                }
              } // end if selfieUrl == emptyString
            } catch (e) {
              errorReport(e);
              cameraCancel = true;
              setDataOK('2');
            }
            transactionStore.dispatch(
              UpdateScreenTxAction(ScreenTransaction({'#CAMERA': false})),
            );
          }
          if ((actionType == 'selfie' && !cameraCancel) ||
              actionType != 'selfie') {
            late String dialogText1;
            late String fromLinkOption;
            //**actionLock();
            switch (widget.component['actionLast'] ?? "Checkpoint") {
              case 'clock-out':
                dialogText1 = tArray[3] ?? "--Bad Text#4--"; // scenario 1
                fromLinkOption = 'normal-clock-in';
                break;

              case 'clock-in':
                if ((widget.component['timeClockOut1'] ?? 0) <=
                        locSensor!.nowTime.millisecondsSinceEpoch &&
                    locSensor.nowTime.millisecondsSinceEpoch <=
                        (widget.component['timeClockOut2'] ?? 0)) {
                  dialogText1 = tArray[4] ?? "--Bad Text#5--"; // scenario 2
                  fromLinkOption = 'normal-clock-out';
                } else {
                  await Get.dialog(
                    AlertDialog(
                      // dialog 34
                      title: Text(tArray[15] ?? "--Bad Text#16--"),
                      content: Text(tArray[16] ?? "--Bad Text#17--"),
                      actions: <Widget>[
                        TextButton(
                          child: Text(
                            tArray[18] ?? "--Bad GPS_SEND Text#19--",
                          ), // scenario 4
                          onPressed: () {
                            dialogText1 =
                                tArray[5] ??
                                "--Bad GPS_SEND Text#6--"; // scenario 4
                            fromLinkOption = 'clock-out-overtime';
                            Navigator.of(context).pop();
                          },
                        ),
                        TextButton(
                          child: Text(tArray[17] ?? "--Bad GPS_SEND Text#18--"),
                          onPressed: () {
                            dialogText1 =
                                tArray[6] ??
                                "--Bad GPS_SEND Text#7--"; // scenario 3
                            fromLinkOption = 'forgot-clock-out';
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  );

                  // await showDialog(
                  //     // show dialog 34
                  //     context: context,
                  //     builder: (BuildContext context) {
                  //       return AlertDialog(
                  //         // dialog 34
                  //         title: Text(tArray[15] ?? "--Bad Text#16--"),
                  //         content: Text(tArray[16] ?? "--Bad Text#17--"),
                  //         actions: <Widget>[
                  //           TextButton(
                  //             child: Text(tArray[18] ??
                  //                 "--Bad GPS_SEND Text#19--"), // scenario 4
                  //             onPressed: () {
                  //               dialogText1 = tArray[5] ??
                  //                   "--Bad GPS_SEND Text#6--"; // scenario 4
                  //               fromLinkOption = 'clock-out-overtime';
                  //               Navigator.of(context).pop();
                  //             },
                  //           ),
                  //           TextButton(
                  //             child: Text(
                  //                 tArray[17] ?? "--Bad GPS_SEND Text#18--"),
                  //             onPressed: () {
                  //               dialogText1 = tArray[6] ??
                  //                   "--Bad GPS_SEND Text#7--"; // scenario 3
                  //               fromLinkOption = 'forgot-clock-out';
                  //               Navigator.of(context).pop();
                  //             },
                  //           ),
                  //         ],
                  //       );
                  //     });
                } // end if ((widget.component['timeClockOut1'] ?? 0)...
                break;

              default: // Checkpoint , scenario 5
                dialogText1 = tArray[7] ?? "--Bad GPS_SEND Text#8--";
                fromLinkOption = 'checkpoint';
            } // end of switch widget.component['actionLast']
            await processData(
              tArray,
              dialogText1,
              selfieUrl,
              fromLinkOption,
              locSensor!,
            );
          } // end if ((actionType == 'selfie' && !cameraCancel)
        } // end if ((actionType != 'selfie') &&...
      } on PlatformException catch (err) {
        // play wrong beep
        setDataOK('2'); // display green without do anything
        errorReport(err);
        await attendanceDialog(
          title: textList['Fail'],
          message: textList["Retry"],
          okString: tArray[8] ?? 'Ok',
        );
      } // end of platformException
    } // end of acquireData

    Future<void> acquireQrSelfie(
      String scrName,
      String originalScrName,
      dynamic component,
      OtqState locSensor,
      bool forceSelfie,
    ) async {
      int tried = 1;
      String? qrText = empty;
      bool done = false;
      bool qrPhoto = false;
      bool qrCancel = false;
      String selfieUrl = '';
      String qrResult = '';
      // ponytail: ?? '' is intentional — diamondTextToList(String) would TypeError
      // on the old ?? [] fallback if component['text'] were null
      List tArray = padTextArray(
        diamondTextToList(widget.component['text'] ?? ''),
      );
      if (widget.component['opMode'] == 'qr-checker-single' ||
          widget.component['opMode'] == 'qr-checker-continuous') {
        qrPhoto = true;
        qrText = await attendanceTakeQR(
          tArray[26] ?? 'Scan QR',
          scrName,
          component,
          'loc',
        );
        qrResult = await qrDataProcess(
          qrText ?? emptyString,
          '',
          tried,
          originalScrName,
        );
      } else {
        while (!done && tried <= qrLoop) {
          qrText = await attendanceTakeQR(
            tArray[26] ?? 'Scan QR',
            scrName,
            component,
            'loc',
          );
          if (qrText == 'null' || qrText == emptyString) {
            qrText = emptyString;
            qrCancel = true;
            tried = qrLoop + 1;
          } else {
            tried++;
          }
          qrResult = await qrDataProcess(qrText, '', tried, originalScrName);
          done =
              qrResult != errorString &&
              qrResult != empty &&
              qrResult != 'null';
          if (!done && !qrCancel && !qrPhoto) {
            await Get.dialog(
              AlertDialog(
                // dialog 2 & 3
                title: Text(
                  tried <= qrLoop
                      ? (tArray[9] ?? "--Bad Text#10--")
                      : (tArray[forceSelfie ? 12 : 9] ??
                            "--Bad GPS_SEND Text#13--"),
                ), //Text('QR salah'),
                content: Text(
                  tried <= qrLoop
                      ? (tArray[10] ?? "--Bad Text#11--")
                      : (tArray[forceSelfie ? 13 : 9] ?? "--Bad Text#14--"),
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(
                      tried <= qrLoop
                          ? (tArray[11] ?? "--Bad Text#12--")
                          : (tArray[forceSelfie ? 14 : 8] ?? "--Bad Text#15--"),
                    ),
                    onPressed: () {
                      Get.back();
                      // Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            );
          } // end if (done)
        } // end while (!done && tried <= 3)
      } // end if checker

      if (forceSelfie && !done && !qrCancel) {
        // qr fail, then call selfie
        late String dialogText1;
        late String fromLinkOption;
        selfieUrl = await takePicture(qrPhoto ? 'back' : 'front');

        switch (widget.component['actionLast'] ?? "Checkpoint") {
          case 'clock-out':
            dialogText1 = tArray[3] ?? "--Bad Text#4--"; // scenario 1
            fromLinkOption = 'normal-clock-in';
            break;

          case 'clock-in':
            if ((widget.component['timeClockOut1'] ?? 0) <=
                    locSensor.nowTime.millisecondsSinceEpoch &&
                locSensor.nowTime.millisecondsSinceEpoch <=
                    (widget.component['timeClockOut2'] ?? 0)) {
              dialogText1 = tArray[4] ?? "--Bad Text#5--"; // scenario 2
              fromLinkOption = 'normal-clock-out';
            } else {
              await showDialog(
                // show dialog 34
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    // dialog 34
                    title: Text(tArray[15] ?? "--Bad Text#16--"),
                    content: Text(tArray[16] ?? "--Bad Text#17--"),
                    actions: <Widget>[
                      TextButton(
                        child: Text(
                          tArray[18] ?? "--Bad GPS_SEND Text#19--",
                        ), // scenario 4
                        onPressed: () {
                          dialogText1 =
                              tArray[5] ??
                              "--Bad GPS_SEND Text#6--"; // scenario 4
                          fromLinkOption = 'clock-out-overtime';
                          Navigator.of(context).pop();
                        },
                      ),
                      TextButton(
                        child: Text(tArray[17] ?? "--Bad GPS_SEND Text#18--"),
                        onPressed: () {
                          dialogText1 =
                              tArray[6] ??
                              "--Bad GPS_SEND Text#7--"; // scenario 3
                          fromLinkOption = 'forgot-clock-out';
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            }
            break;

          default: // Checkpoint , scenario 5
            dialogText1 = tArray[7] ?? "--Bad GPS_SEND Text#8--";
            fromLinkOption = 'checkpoint';
        } // end of switch widget.component['actionLast']
        await processData(
          tArray,
          dialogText1,
          selfieUrl,
          fromLinkOption,
          locSensor,
        );
      }
      if (qrCancel || !forceSelfie) {
        setDataOK('2');
      }
    } // end of acquireQrSelfie

    Future<void> doQrSelfieFlow(List textArray, OtqState currentData) async {
      // ponytail: all-in-one inner function; split when testable seams emerge
      try {
        // --- §3 step 1 (geofence) handled by caller via stacked case ---

        // --- §3 step 2: QR scan loop (indefinite until valid or cancel) ---
        dynamic p;
        dynamic q;
        await Future.wait([omLqrReaderP(), osLqrMakerQ()]).then((res) {
          p = res[0];
          q = res[1];
        });

        String finalQrText = '';
        bool qrValid = false;
        while (!qrValid) {
          String? qrText = await attendanceTakeQR(
            textArray.length > 26 ? textArray[26] : 'Scan QR',
            '_OtqQR1',
            widget.component,
            'loc',
          );

          // User cancelled the scanner
          if (qrText == null ||
              qrText == 'null' ||
              qrText == emptyString ||
              qrText.isEmpty) {
            setDataOK('2');
            return;
          }

          // Validate QR via lqrVerify + #LQR_LIST lookup
          String verifiedQr = await lqrVerify(p, q, qrText);
          if (verifiedQr != errorString) {
            final dynamic lqrList =
                transactionStore.state.screenTx['#LQR_LIST'];
            if (lqrList != null &&
                lqrList is Map &&
                lqrList[verifiedQr] != null) {
              finalQrText = verifiedQr;
              qrValid = true;
            }
          }

          if (!qrValid) {
            // Show invalid-QR dialog with Scan Lagi / Batal (§3 step 2 loop)
            bool rescan = false;
            await Get.dialog(
              AlertDialog(
                title: Text(
                  textArray.length > 9
                      ? (textArray[9] ?? 'QR salah')
                      : 'QR salah',
                ),
                content: Text(
                  textArray.length > 10 ? (textArray[10] ?? '') : '',
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(
                      textArray.length > 1
                          ? (textArray[1] ?? 'Batal')
                          : 'Batal',
                    ),
                    onPressed: () {
                      rescan = false;
                      Get.back();
                    },
                  ),
                  TextButton(
                    child: Text(
                      textArray.length > 11
                          ? (textArray[11] ?? 'Scan Lagi')
                          : 'Scan Lagi',
                    ),
                    onPressed: () {
                      rescan = true;
                      Get.back();
                    },
                  ),
                ],
              ),
            );
            if (!rescan) {
              setDataOK('2');
              return;
            }
            // Loop continues to re-scan
          }
        } // end QR scan loop

        // Per-scanned-QR geofence: the scanned QR's OWN location must be in range
        // (fixes "scan BSD A while nearest BSD B" — reject if you're not AT the
        // scanned QR). Checked here (pre-camera) so a rejected scan wastes no
        // selfie/upload. Opt-in via outPositionAllowed:FALSE, like the pre-scan gate.
        if (await blockIfOutsideScannedLqr(
          finalQrText,
          currentData.latitude,
          currentData.longitude,
          currentData.accuracy,
          textArray,
        )) {
          setDataOK('2');
          return;
        }

        // --- §3 step 2→3 transition: Scenario resolution (actionLast switch) ---
        late String dialogText1;
        late String fromLinkOption;
        int nowTime = await getRealTime();

        switch (widget.component['actionLast'] ?? "Checkpoint") {
          case 'clock-out':
            dialogText1 = textArray[3] ?? "--Bad Text#4--";
            fromLinkOption = 'normal-clock-in';
            break;

          case 'clock-in':
            if ((widget.component['timeClockOut1'] ?? 0) <= nowTime &&
                nowTime <= (widget.component['timeClockOut2'] ?? 0)) {
              dialogText1 = textArray[4] ?? "--Bad Text#5--";
              fromLinkOption = 'normal-clock-out';
            } else {
              // W1 fix: barrierDismissible: false prevents LateInitializationError
              // on dialogText1/fromLinkOption if user dismisses barrier without
              // pressing a button. Existing modes are NOT changed.
              await Get.dialog(
                AlertDialog(
                  title: Text(textArray[15] ?? "--Bad Text#16--"),
                  content: Text(textArray[16] ?? "--Bad Text#17--"),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textArray[18] ?? "--Bad Text#19--"),
                      onPressed: () {
                        dialogText1 = textArray[5] ?? "--Bad Text#6--";
                        fromLinkOption = 'clock-out-overtime';
                        Get.back();
                      },
                    ),
                    TextButton(
                      child: Text(textArray[17] ?? "--Bad Text#18--"),
                      onPressed: () {
                        dialogText1 = textArray[6] ?? "--Bad Text#7--";
                        fromLinkOption = 'forgot-clock-out';
                        Get.back();
                      },
                    ),
                  ],
                ),
                barrierDismissible: false,
              );
            }
            break;

          default: // Checkpoint, scenario 5
            // For qr-selfie checkpoint: use tArray[30] (qr+selfie specific text)
            // falling back to tArray[7] if tArray[30] is empty (pad default)
            String qrSelfieMsg =
                (textArray.length > 30 &&
                    textArray[30] != null &&
                    textArray[30].toString().isNotEmpty)
                ? textArray[30]
                : (textArray[7] ?? "--Bad Text#8--");
            dialogText1 = qrSelfieMsg;
            fromLinkOption = 'checkpoint';
        } // end actionLast switch

        // §3 step 3: QR valid → straight to selfie camera (no dialog; user feedback).
        // Let the just-closed QR scanner (mobile_scanner) release the physical
        // camera before the selfie camera (camera plugin) opens. Without this
        // settle the two plugins contend for the same hardware and the selfie
        // preview comes up blank white (mirrors ftz_checker's checkerTakePicture).
        await Future.delayed(const Duration(milliseconds: 500));

        // --- §3 step 3→4 transition: Front-camera selfie ---
        List<CameraDescription>? cams =
            transactionStore.state.screenTx['#CAMS']
                as List<CameraDescription>?;
        if (cams == null || cams.isEmpty) {
          setDataOK('2');
          return;
        }
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#CAMERA': true})),
        );

        int maxSize =
            (widget.component['imgWidth'] ?? 540) >
                (widget.component['imgHeight'] ?? 540)
            ? widget.component['imgWidth'] ?? 540
            : widget.component['imgHeight'] ?? 540;
        String uniqueFilename =
            '${widget.component['filename'] ?? 'file'}_${const Uuid().v4().replaceAll('-', '')}';

        String capturedPath;
        try {
          capturedPath = await acquireCamera(
            cams,
            widget.component['label'] ?? 'Camera',
            'front',
            maxSize,
            widget.component['quality'] ?? 80,
            h,
            w,
          );
        } catch (eCam) {
          errorReport(eCam);
          capturedPath = emptyString;
        }
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#CAMERA': false})),
        );

        if (capturedPath == emptyString || capturedPath.isEmpty) {
          setDataOK('2');
          return;
        }

        // --- §3 step 3→4 transition: Synchronous upload with retry ---
        // C2 fix: normalize the camera capture path ONCE before the retry loop.
        // saveImageToCloud internally calls renamePath which MOVES the OTQC-artifact
        // camera file on first call. If the upload fails, the original capturedPath
        // no longer exists and retries would fail forever with invalidPathPrefix02.
        // By calling renamePath here, we get the stable otq_images/ path; subsequent
        // renamePath calls inside saveImageToCloud see no OTQC artifact and return
        // the path unchanged (api.dart:709-711 else-branch).
        String stablePath = await renamePath(
          originalImagePath: capturedPath,
          folder: widget.component['folder'] ?? 'default',
          fileName: uniqueFilename,
        );

        String uploadedUrl = '';
        bool uploadSuccess = false;
        while (!uploadSuccess) {
          List<String> uploadResult = await saveImageToCloud(
            imagePath: stablePath,
            folder: widget.component['folder'] ?? 'default',
            rawFileName: uniqueFilename,
          );
          if (uploadResult.length > 1 && isValidImageUrl(uploadResult[1])) {
            uploadedUrl = uploadResult[1];
            uploadSuccess = true;
          } else {
            // Upload failed — offer retry (re-upload same file, not re-capture)
            bool retryUpload = false;
            await Get.dialog(
              AlertDialog(
                title: Text(textList['Fail'] ?? 'Gagal'),
                content: Text(
                  textList['Retry'] ?? 'Gagal, coba ulangi sekali lagi.',
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(
                      textArray.length > 1
                          ? (textArray[1] ?? 'Batal')
                          : 'Batal',
                    ),
                    onPressed: () {
                      retryUpload = false;
                      Get.back();
                    },
                  ),
                  TextButton(
                    child: Text(
                      textArray.length > 8 ? (textArray[8] ?? 'OK') : 'OK',
                    ),
                    onPressed: () {
                      retryUpload = true;
                      Get.back();
                    },
                  ),
                ],
              ),
            );
            if (!retryUpload) {
              setDataOK('2');
              return;
            }
            // Loop continues to re-upload same stable file
          }
        } // end upload retry loop

        // --- §3 step 4: Write attendance (ONCE) ---
        Position? position;
        List<Placemark> placeMark = [];
        int writeTime = 0;

        await Future.wait([getLocation(), getRealTime()]).then((res) {
          position = res[0];
          writeTime = res[1];
        });

        if (position == null) {
          setDataOK('1');
          await attendanceDialog(
            title: textList['Fail'] ?? 'Gagal',
            message: 'Gagal, tidak dapat membaca lokasi GPS.',
            okString: textArray.length > 8 ? (textArray[8] ?? 'Ok') : 'Ok',
          );
          return;
        }

        try {
          placeMark = await placemarkFromCoordinates(
            position!.latitude,
            position!.longitude,
          );
        } catch (e) {
          errorReport(e);
        }

        actionLock('qrSelfie write attendance_qr_selfie_gps_verify');
        vibrate(duration: 100);

        widget.component['route'] = widget.component['route'] ?? home;
        OtqState locSensor = OtqState().getDataFrom(
          DateTime.fromMillisecondsSinceEpoch(writeTime),
          position!,
          placeMark,
        );
        String locString = getLocationString(
          finalQrText,
          uploadedUrl,
          fromLinkOption,
          locSensor,
        );
        saveData(widget.scrName, locString);
        routeStack.pop();

        await attendanceSuccessDialog(
          title: textArray.length > 2
              ? (textArray[2] ?? '-- Title --')
              : '-- Title --',
          message1: dialogText1,
          message2:
              locationNameFromScannedLqr(finalQrText) ??
              locationNameFromLqrRef(
                locSensor.latitude,
                locSensor.longitude,
                locSensor.accuracy,
              ) ??
              (placeMark.isNotEmpty
                  ? "${placeMark[0].subLocality ?? ''}, ${(placeMark[0].locality ?? '').replaceFirst(RegExp(r'^[Kk]ecamatan\s+'), '')}, ${(placeMark[0].subAdministrativeArea ?? '').replaceFirst(RegExp(r'^([Kk]abupaten|[Kk]ota)\s+'), '')} ${placeMark[0].postalCode ?? ''}"
                  : ""),
          message3:
              '$plusMinus ${position == null ? "-" : position!.accuracy.round()}m',
          okString: textArray.length > 8 ? textArray[8] : 'Ok',
        );
      } catch (e) {
        errorReport(e);
        setDataOK('2');
        Get.dialog(
          AlertDialog(
            title: Text(textList['Fail'] ?? 'Gagal'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textList['Retry'] ?? 'Gagal, coba ulangi.'),
                Text('System: (${e.toString()})'),
                const Text('Position: qr-selfie(1)'),
                Text(textList['ScreenShot'] ?? ''),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: Text(textList['OK'] ?? 'Ok'),
                onPressed: () {
                  Get.back();
                },
              ),
            ],
          ),
        );
      }
    } // end of doQrSelfieFlow

    media = MediaQuery.maybeOf(context);
    h = media?.size.height - 20;
    w = media.size.width - 20;
    const double defaultAspectRatio = 18 / 12;
    var topPad = 6.0;
    double fontSize = (widget.component['fontSize'] ?? 14.0).toDouble();
    // ponytail: ?? '' is intentional — diamondTextToList(String) would TypeError
    // on a null text; old code had no guard here at all
    var textArray = padTextArray(
      diamondTextToList(widget.component['text'] ?? ''),
    );
    Widget button1;
    if (widget.single) {
      button1 = Center(
        child: Column(
          children: [
            Container(
              // display single icon
              alignment: Alignment.center,
              width: (widget.component['width'] ?? 90).toDouble(),
              child: Card(
                child: InkWell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Container(height: topPad),
                      AspectRatio(
                        aspectRatio: defaultAspectRatio,
                        child: displayImage(
                          imageUrl: widget.component['url'] ?? defaultImage,
                          cached: true,
                        ),
                        // child: FadeInImage.memoryNetwork(
                        //   placeholder: kTransparentImage,
                        //   image: widget.component['url'] ?? defaultImage,
                        // ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          textArray[0],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fontSize),
                        ),
                      ),
                    ],
                  ),
                  onTap: () async {
                    if (!await bioGate(widget.component, context)) return;
                    if (!mounted) return;
                    if (!tapped) {
                      setState(() {
                        tapped = true;
                      });
                      // if (await dataOk(context)) {
                      actionLock(
                        'acquireSelfie attendance_qr_selfie_gps_verify',
                      );
                      // ConnectionData connectionData =
                      //     await ConnectionData().getConnection(true, true);
                      // if (true || await internetOk(context)) {
                      if (true) {
                        try {
                          OtqState currentData = await OtqState()
                              .setAllDataAsync();
                          switch (widget.component['opMode'] ?? 'gps-single') {
                            case 'qr-checker-single':
                              await acquireData(
                                'qr-checker-single',
                                textArray,
                                currentData,
                              );
                              var locArray = widget.component['locList'] ?? [];
                              bool selfie;
                              if (locArray.length < 1) {
                                // location array =  empty
                                selfie = true; // selfie
                              } else {
                                if (await locationVerify(
                                  locArray,
                                  widget.component['tolerance'] ?? 50,
                                  currentData,
                                )) {
                                  selfie = false; // scan qr
                                } else {
                                  selfie = true; // selfie
                                }
                              }
                              await acquireData('back', textArray, currentData);
                              String toGo = widget.component['route'] ?? home;
                              routeStack.push(toGo);
                              gotoRoute(toGo);
                              break; // end case 'qr-checker-single'

                            case 'qr-selfie':
                            case 'qr-single':
                              final bool fakeGpsAllowed =
                                  (widget.component['fakeGpsAllowed']
                                          ?.toString()
                                          .toLowerCase() ??
                                      'true') !=
                                  'false';
                              if (!fakeGpsAllowed && currentData.mock) {
                                if (context.mounted) {
                                  await showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: Text(
                                          textArray[22] ?? 'Lokasi tidak valid',
                                        ),
                                        content: Text(
                                          fakeGpsDialogText(
                                            currentData,
                                            textArray,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            child: Text(textArray[8] ?? 'OK'),
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                }
                                setDataOK('2');
                                break;
                              }
                              final bool outPositionAllowed =
                                  (widget.component['outPositionAllowed']
                                          ?.toString()
                                          .toUpperCase() ??
                                      'TRUE') !=
                                  'FALSE';
                              bool outBlocked = false;
                              if (!outPositionAllowed) {
                                final dynamic lqrList = transactionStore
                                    .state
                                    .screenTx['#LQR_LIST'];
                                final bool hasLqrList =
                                    lqrList != null &&
                                    lqrList is Map &&
                                    lqrList.isNotEmpty;
                                if (hasLqrList) {
                                  try {
                                    final double gpsAccuracy =
                                        currentData.accuracy;
                                    bool insideAny = false;
                                    double minDistance = double.infinity;
                                    double matchZone2 = 0;
                                    for (final entry in lqrList.values) {
                                      final List data = entry as List;
                                      final double targetLat = (data[1] as num)
                                          .toDouble();
                                      final double targetLng = (data[2] as num)
                                          .toDouble();
                                      final double tolerance = (data[3] as num)
                                          .toDouble();
                                      final double zone2 =
                                          tolerance + gpsAccuracy * 2;
                                      final double distance =
                                          Geolocator.distanceBetween(
                                            targetLat,
                                            targetLng,
                                            currentData.latitude,
                                            currentData.longitude,
                                          );
                                      if (distance < minDistance) {
                                        minDistance = distance;
                                        matchZone2 = zone2;
                                      }
                                      if (distance <= zone2) {
                                        insideAny = true;
                                      }
                                    }
                                    debugPrint(
                                      '[qr-single/single] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                                    );
                                    if (!insideAny) {
                                      outBlocked = true;
                                      if (context.mounted) {
                                        await Get.dialog(
                                          AlertDialog(
                                            title: Text(textArray[24]),
                                            content: Text(textArray[25]),
                                            actions: [
                                              TextButton(
                                                child: Text(textArray[8]),
                                                onPressed: () => Get.back(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    }
                                  } catch (eLoc) {
                                    debugPrint(
                                      '[qr-single/single] parse error: $eLoc — bypass pengecekan',
                                    );
                                  }
                                } else {
                                  if (!internetConnected()) {
                                    debugPrint(
                                      '[qr-single/single] offline & #LQR_LIST kosong/null — block absensi',
                                    );
                                    outBlocked = true;
                                    if (context.mounted) {
                                      await Get.dialog(
                                        AlertDialog(
                                          title: Text(textArray[24]),
                                          content: Text(textArray[25]),
                                          actions: [
                                            TextButton(
                                              child: Text(textArray[8]),
                                              onPressed: () => Get.back(),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else {
                                    debugPrint(
                                      '[qr-single/single] online & #LQR_LIST kosong/null — bypass pengecekan',
                                    );
                                  }
                                }
                              }
                              if (outBlocked) {
                                setDataOK('2');
                                break;
                              }
                              if ((widget.component['opMode'] ??
                                      'gps-single') ==
                                  'qr-selfie') {
                                await doQrSelfieFlow(textArray, currentData);
                              } else {
                                String myPage = '_OtqQR1';
                                await acquireQrSelfie(
                                  myPage,
                                  widget.scrName,
                                  widget.component,
                                  currentData,
                                  false,
                                );
                              }
                              break;

                            case 'selfie':
                              final bool fakeGpsAllowedSelfie =
                                  (widget.component['fakeGpsAllowed']
                                          ?.toString()
                                          .toLowerCase() ??
                                      'true') !=
                                  'false';
                              if (!fakeGpsAllowedSelfie && currentData.mock) {
                                if (context.mounted) {
                                  await showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: Text(textArray[22]),
                                        content: Text(
                                          fakeGpsDialogText(
                                            currentData,
                                            textArray,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            child: Text(textArray[8]),
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                }
                                setDataOK('2');
                                break;
                              }
                              final bool outPositionAllowedSelfie =
                                  (widget.component['outPositionAllowed']
                                          ?.toString()
                                          .toUpperCase() ??
                                      'TRUE') !=
                                  'FALSE';
                              bool outBlockedSelfie = false;
                              if (!outPositionAllowedSelfie) {
                                final dynamic lqrList = transactionStore
                                    .state
                                    .screenTx['#LQR_LIST'];
                                final bool hasLqrList =
                                    lqrList != null &&
                                    lqrList is Map &&
                                    lqrList.isNotEmpty;
                                if (hasLqrList) {
                                  try {
                                    final double gpsAccuracy =
                                        currentData.accuracy;
                                    bool insideAny = false;
                                    double minDistance = double.infinity;
                                    double matchZone2 = 0;
                                    for (final entry in lqrList.values) {
                                      final List data = entry as List;
                                      final double targetLat = (data[1] as num)
                                          .toDouble();
                                      final double targetLng = (data[2] as num)
                                          .toDouble();
                                      final double tolerance = (data[3] as num)
                                          .toDouble();
                                      final double zone2 =
                                          tolerance + gpsAccuracy * 2;
                                      final double distance =
                                          Geolocator.distanceBetween(
                                            targetLat,
                                            targetLng,
                                            currentData.latitude,
                                            currentData.longitude,
                                          );
                                      if (distance < minDistance) {
                                        minDistance = distance;
                                        matchZone2 = zone2;
                                      }
                                      if (distance <= zone2) {
                                        insideAny = true;
                                      }
                                    }
                                    debugPrint(
                                      '[selfie/single] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                                    );
                                    if (!insideAny) {
                                      outBlockedSelfie = true;
                                      if (context.mounted) {
                                        await Get.dialog(
                                          AlertDialog(
                                            title: Text(textArray[24]),
                                            content: Text(textArray[25]),
                                            actions: [
                                              TextButton(
                                                child: Text(textArray[8]),
                                                onPressed: () => Get.back(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    }
                                  } catch (eLoc) {
                                    debugPrint(
                                      '[selfie/single] parse error: $eLoc — bypass pengecekan',
                                    );
                                  }
                                } else {
                                  if (!internetConnected()) {
                                    debugPrint(
                                      '[selfie/single] offline & #LQR_LIST kosong/null — block absensi',
                                    );
                                    outBlockedSelfie = true;
                                    if (context.mounted) {
                                      await Get.dialog(
                                        AlertDialog(
                                          title: Text(textArray[24]),
                                          content: Text(textArray[25]),
                                          actions: [
                                            TextButton(
                                              child: Text(textArray[8]),
                                              onPressed: () => Get.back(),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else {
                                    debugPrint(
                                      '[selfie/single] online & #LQR_LIST kosong/null — bypass pengecekan',
                                    );
                                  }
                                }
                              }
                              if (outBlockedSelfie) {
                                setDataOK('2');
                                break;
                              }
                              await acquireData(
                                'selfie',
                                textArray,
                                currentData,
                              );
                              String toGo = widget.component['route'] ?? home;
                              routeStack.push(toGo);
                              gotoRoute(toGo);
                              break;

                            default: // gps-single or other
                              final bool fakeGpsAllowedGps =
                                  (widget.component['fakeGpsAllowed']
                                          ?.toString()
                                          .toLowerCase() ??
                                      'true') !=
                                  'false';
                              if (!fakeGpsAllowedGps && currentData.mock) {
                                if (context.mounted) {
                                  await showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: Text(textArray[22]),
                                        content: Text(
                                          fakeGpsDialogText(
                                            currentData,
                                            textArray,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            child: Text(textArray[8]),
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                }
                                setDataOK('2');
                                break;
                              }
                              final bool outPositionAllowedGps =
                                  (widget.component['outPositionAllowed']
                                          ?.toString()
                                          .toUpperCase() ??
                                      'TRUE') !=
                                  'FALSE';
                              bool outBlockedGps = false;
                              if (!outPositionAllowedGps) {
                                final dynamic lqrList = transactionStore
                                    .state
                                    .screenTx['#LQR_LIST'];
                                final bool hasLqrList =
                                    lqrList != null &&
                                    lqrList is Map &&
                                    lqrList.isNotEmpty;
                                if (hasLqrList) {
                                  try {
                                    final double gpsAccuracy =
                                        currentData.accuracy;
                                    bool insideAny = false;
                                    double minDistance = double.infinity;
                                    double matchZone2 = 0;
                                    for (final entry in lqrList.values) {
                                      final List data = entry as List;
                                      final double targetLat = (data[1] as num)
                                          .toDouble();
                                      final double targetLng = (data[2] as num)
                                          .toDouble();
                                      final double tolerance = (data[3] as num)
                                          .toDouble();
                                      final double zone2 =
                                          tolerance + gpsAccuracy * 2;
                                      final double distance =
                                          Geolocator.distanceBetween(
                                            targetLat,
                                            targetLng,
                                            currentData.latitude,
                                            currentData.longitude,
                                          );
                                      if (distance < minDistance) {
                                        minDistance = distance;
                                        matchZone2 = zone2;
                                      }
                                      if (distance <= zone2) {
                                        insideAny = true;
                                      }
                                    }
                                    debugPrint(
                                      '[gps-single/single] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                                    );
                                    if (!insideAny) {
                                      outBlockedGps = true;
                                      if (context.mounted) {
                                        await Get.dialog(
                                          AlertDialog(
                                            title: Text(textArray[24]),
                                            content: Text(textArray[25]),
                                            actions: [
                                              TextButton(
                                                child: Text(textArray[8]),
                                                onPressed: () => Get.back(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    }
                                  } catch (eLoc) {
                                    debugPrint(
                                      '[gps-single/single] parse error: $eLoc — bypass pengecekan',
                                    );
                                  }
                                } else {
                                  if (!internetConnected()) {
                                    debugPrint(
                                      '[gps-single/single] offline & #LQR_LIST kosong/null — block absensi',
                                    );
                                    outBlockedGps = true;
                                    if (context.mounted) {
                                      await Get.dialog(
                                        AlertDialog(
                                          title: Text(textArray[24]),
                                          content: Text(textArray[25]),
                                          actions: [
                                            TextButton(
                                              child: Text(textArray[8]),
                                              onPressed: () => Get.back(),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else {
                                    debugPrint(
                                      '[gps-single/single] online & #LQR_LIST kosong/null — bypass pengecekan',
                                    );
                                  }
                                }
                              }
                              if (outBlockedGps) {
                                setDataOK('2');
                                break;
                              }
                              await acquireData(
                                'gps-single',
                                textArray,
                                currentData,
                              );
                              String toGo = widget.component['route'] ?? home;
                              routeStack.push(toGo);
                              gotoRoute(toGo);
                          } // end of switch
                        } catch (e) {
                          setDataOK('2');
                          errorReport(e);
                        }
                        if (mounted) {
                          setState(() {
                            tapped = false;
                          });
                        }
                      }
                    } // end if !tapped
                  }, // end of onTap
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // else if (widget.single)
      button1 = Container(
        alignment: const Alignment(0.0, 0.0),
        child: Card(
          child: InkWell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(height: topPad),
                AspectRatio(
                  aspectRatio: defaultAspectRatio,
                  child: displayImage(
                    imageUrl: widget.component['url'] ?? defaultImage,
                    cached: true,
                  ),
                  // child: FadeInImage.memoryNetwork(
                  //   placeholder: kTransparentImage,
                  //   image: widget.component['url'] ?? defaultImage,
                  // ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    textArray[0],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fontSize),
                  ),
                ),
              ],
            ),
            onTap: () async {
              if (!await bioGate(widget.component, context)) return;
              if (!mounted) return;
              if (!tapped) {
                setState(() {
                  tapped = true;
                });
                // if (await dataOk(context)) {
                actionLock(
                  '[1302] acquireSelfie attendance_qr_selfie_gps_verify',
                );
                // ConnectionData connectionData =
                //     await ConnectionData().getConnection(true, true);
                // if (await internetOk(context)) {
                if (true) {
                  try {
                    OtqState currentData = await OtqState().setAllDataAsync();
                    switch (widget.component['opMode'] ?? 'gps-single') {
                      case 'qr-checker-single':
                        var locArray = widget.component['locList'] ?? [];
                        bool selfie;
                        if (locArray.length < 1) {
                          // location array =  empty
                          selfie = true; // selfie
                        } else {
                          if (await locationVerify(
                            locArray,
                            widget.component['tolerance'] ?? 50,
                            currentData,
                          )) {
                            selfie = false; // scan qr
                          } else {
                            selfie = true; // selfie
                          }
                        }
                        if (selfie) {
                          await showDialog(
                            // show dialog 5
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                // dialog 3
                                title: Text(textArray[19]),
                                content: Text(textArray[20]),
                                actions: <Widget>[
                                  TextButton(
                                    child: Text(textArray[21]),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                          await acquireData('selfie', textArray, currentData);
                          String toGo = widget.component['route'] ?? home;
                          routeStack.push(toGo);
                          gotoRoute(toGo);
                        } else {
                          String myPage = '_OtqQR1';
                          await acquireQrSelfie(
                            myPage,
                            widget.scrName,
                            widget.component,
                            currentData,
                            true,
                          );
                          // setDataOK('2');
                          // routeStack.push(myPage);
                          // gotoRoute(myPage);
                        }
                        break; // end case qr-checker-single

                      case 'qr-selfie':
                      case 'qr-single':
                        final bool fakeGpsAllowed =
                            (widget.component['fakeGpsAllowed']
                                    ?.toString()
                                    .toLowerCase() ??
                                'true') !=
                            'false';
                        if (!fakeGpsAllowed && currentData.mock) {
                          if (context.mounted) {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(textArray[22]),
                                  content: Text(
                                    fakeGpsDialogText(currentData, textArray),
                                  ),
                                  actions: [
                                    TextButton(
                                      child: Text(textArray[8]),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                );
                              },
                            );
                          }
                          setDataOK('2');
                          break;
                        }
                        final bool outPositionAllowed =
                            (widget.component['outPositionAllowed']
                                    ?.toString()
                                    .toUpperCase() ??
                                'TRUE') !=
                            'FALSE';
                        bool outBlocked = false;
                        if (!outPositionAllowed) {
                          final dynamic lqrList =
                              transactionStore.state.screenTx['#LQR_LIST'];
                          final bool hasLqrList =
                              lqrList != null &&
                              lqrList is Map &&
                              lqrList.isNotEmpty;
                          if (hasLqrList) {
                            try {
                              final double gpsAccuracy = currentData.accuracy;
                              bool insideAny = false;
                              double minDistance = double.infinity;
                              double matchZone2 = 0;
                              for (final entry in lqrList.values) {
                                final List data = entry as List;
                                final double targetLat = (data[1] as num)
                                    .toDouble();
                                final double targetLng = (data[2] as num)
                                    .toDouble();
                                final double tolerance = (data[3] as num)
                                    .toDouble();
                                final double zone2 =
                                    tolerance + gpsAccuracy * 2;
                                final double distance =
                                    Geolocator.distanceBetween(
                                      targetLat,
                                      targetLng,
                                      currentData.latitude,
                                      currentData.longitude,
                                    );
                                if (distance < minDistance) {
                                  minDistance = distance;
                                  matchZone2 = zone2;
                                }
                                if (distance <= zone2) {
                                  insideAny = true;
                                }
                              }
                              debugPrint(
                                '[qr-single/multi] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                              );
                              if (!insideAny) {
                                outBlocked = true;
                                if (context.mounted) {
                                  await Get.dialog(
                                    AlertDialog(
                                      title: Text(textArray[24]),
                                      content: Text(textArray[25]),
                                      actions: [
                                        TextButton(
                                          child: Text(textArray[8]),
                                          onPressed: () => Get.back(),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              }
                            } catch (eLoc) {
                              debugPrint(
                                '[qr-single/multi] parse error: $eLoc — bypass pengecekan',
                              );
                            }
                          } else {
                            if (!internetConnected()) {
                              debugPrint(
                                '[qr-single/multi] offline & #LQR_LIST kosong/null — block absensi',
                              );
                              outBlocked = true;
                              if (context.mounted) {
                                await Get.dialog(
                                  AlertDialog(
                                    title: Text(textArray[24]),
                                    content: Text(textArray[25]),
                                    actions: [
                                      TextButton(
                                        child: Text(textArray[8]),
                                        onPressed: () => Get.back(),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            } else {
                              debugPrint(
                                '[qr-single/multi] online & #LQR_LIST kosong/null — bypass pengecekan',
                              );
                            }
                          }
                        }
                        if (outBlocked) {
                          setDataOK('2');
                          break;
                        }
                        if ((widget.component['opMode'] ?? 'gps-single') ==
                            'qr-selfie') {
                          await doQrSelfieFlow(textArray, currentData);
                        } else {
                          String myPage = '_OtqQR1';
                          await acquireQrSelfie(
                            myPage,
                            widget.scrName,
                            widget.component,
                            currentData,
                            false,
                          );
                        }
                        break;

                      case 'selfie':
                        final bool fakeGpsAllowedSelfie =
                            (widget.component['fakeGpsAllowed']
                                    ?.toString()
                                    .toLowerCase() ??
                                'true') !=
                            'false';
                        if (!fakeGpsAllowedSelfie && currentData.mock) {
                          if (context.mounted) {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(textArray[22]),
                                  content: Text(
                                    fakeGpsDialogText(currentData, textArray),
                                  ),
                                  actions: [
                                    TextButton(
                                      child: Text(textArray[8]),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                );
                              },
                            );
                          }
                          setDataOK('2');
                          break;
                        }
                        final bool outPositionAllowedSelfie =
                            (widget.component['outPositionAllowed']
                                    ?.toString()
                                    .toUpperCase() ??
                                'TRUE') !=
                            'FALSE';
                        bool outBlockedSelfie = false;
                        if (!outPositionAllowedSelfie) {
                          final dynamic lqrList =
                              transactionStore.state.screenTx['#LQR_LIST'];
                          final bool hasLqrList =
                              lqrList != null &&
                              lqrList is Map &&
                              lqrList.isNotEmpty;
                          if (hasLqrList) {
                            try {
                              final double gpsAccuracy = currentData.accuracy;
                              bool insideAny = false;
                              double minDistance = double.infinity;
                              double matchZone2 = 0;
                              for (final entry in lqrList.values) {
                                final List data = entry as List;
                                final double targetLat = (data[1] as num)
                                    .toDouble();
                                final double targetLng = (data[2] as num)
                                    .toDouble();
                                final double tolerance = (data[3] as num)
                                    .toDouble();
                                final double zone2 =
                                    tolerance + gpsAccuracy * 2;
                                final double distance =
                                    Geolocator.distanceBetween(
                                      targetLat,
                                      targetLng,
                                      currentData.latitude,
                                      currentData.longitude,
                                    );
                                if (distance < minDistance) {
                                  minDistance = distance;
                                  matchZone2 = zone2;
                                }
                                if (distance <= zone2) {
                                  insideAny = true;
                                }
                              }
                              debugPrint(
                                '[selfie/multi] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                              );
                              if (!insideAny) {
                                outBlockedSelfie = true;
                                if (context.mounted) {
                                  await Get.dialog(
                                    AlertDialog(
                                      title: Text(textArray[24]),
                                      content: Text(textArray[25]),
                                      actions: [
                                        TextButton(
                                          child: Text(textArray[8]),
                                          onPressed: () => Get.back(),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              }
                            } catch (eLoc) {
                              debugPrint(
                                '[selfie/multi] parse error: $eLoc — bypass pengecekan',
                              );
                            }
                          } else {
                            if (!internetConnected()) {
                              debugPrint(
                                '[selfie/multi] offline & #LQR_LIST kosong/null — block absensi',
                              );
                              outBlockedSelfie = true;
                              if (context.mounted) {
                                await Get.dialog(
                                  AlertDialog(
                                    title: Text(textArray[24]),
                                    content: Text(textArray[25]),
                                    actions: [
                                      TextButton(
                                        child: Text(textArray[8]),
                                        onPressed: () => Get.back(),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            } else {
                              debugPrint(
                                '[selfie/multi] online & #LQR_LIST kosong/null — bypass pengecekan',
                              );
                            }
                          }
                        }
                        if (outBlockedSelfie) {
                          setDataOK('2');
                          break;
                        }
                        await acquireData('selfie', textArray, currentData);
                        String toGo = widget.component['route'] ?? home;
                        routeStack.push(toGo);
                        gotoRoute(toGo);
                        break;

                      default: // gps-single or other
                        final bool fakeGpsAllowedGps =
                            (widget.component['fakeGpsAllowed']
                                    ?.toString()
                                    .toLowerCase() ??
                                'true') !=
                            'false';
                        if (!fakeGpsAllowedGps && currentData.mock) {
                          if (context.mounted) {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(textArray[22]),
                                  content: Text(
                                    fakeGpsDialogText(currentData, textArray),
                                  ),
                                  actions: [
                                    TextButton(
                                      child: Text(textArray[8]),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                );
                              },
                            );
                          }
                          setDataOK('2');
                          break;
                        }
                        final bool outPositionAllowedGps =
                            (widget.component['outPositionAllowed']
                                    ?.toString()
                                    .toUpperCase() ??
                                'TRUE') !=
                            'FALSE';
                        bool outBlockedGps = false;
                        if (!outPositionAllowedGps) {
                          final dynamic lqrList =
                              transactionStore.state.screenTx['#LQR_LIST'];
                          final bool hasLqrList =
                              lqrList != null &&
                              lqrList is Map &&
                              lqrList.isNotEmpty;
                          if (hasLqrList) {
                            try {
                              final double gpsAccuracy = currentData.accuracy;
                              bool insideAny = false;
                              double minDistance = double.infinity;
                              double matchZone2 = 0;
                              for (final entry in lqrList.values) {
                                final List data = entry as List;
                                final double targetLat = (data[1] as num)
                                    .toDouble();
                                final double targetLng = (data[2] as num)
                                    .toDouble();
                                final double tolerance = (data[3] as num)
                                    .toDouble();
                                final double zone2 =
                                    tolerance + gpsAccuracy * 2;
                                final double distance =
                                    Geolocator.distanceBetween(
                                      targetLat,
                                      targetLng,
                                      currentData.latitude,
                                      currentData.longitude,
                                    );
                                if (distance < minDistance) {
                                  minDistance = distance;
                                  matchZone2 = zone2;
                                }
                                if (distance <= zone2) {
                                  insideAny = true;
                                }
                              }
                              debugPrint(
                                '[gps-single/multi] insideAny=$insideAny, minDistance=${minDistance.toStringAsFixed(1)}m, zone2=${matchZone2.toStringAsFixed(1)}m',
                              );
                              if (!insideAny) {
                                outBlockedGps = true;
                                if (context.mounted) {
                                  await Get.dialog(
                                    AlertDialog(
                                      title: Text(textArray[24]),
                                      content: Text(textArray[25]),
                                      actions: [
                                        TextButton(
                                          child: Text(textArray[8]),
                                          onPressed: () => Get.back(),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              }
                            } catch (eLoc) {
                              debugPrint(
                                '[gps-single/multi] parse error: $eLoc — bypass pengecekan',
                              );
                            }
                          } else {
                            if (!internetConnected()) {
                              debugPrint(
                                '[gps-single/multi] offline & #LQR_LIST kosong/null — block absensi',
                              );
                              outBlockedGps = true;
                              if (context.mounted) {
                                await Get.dialog(
                                  AlertDialog(
                                    title: Text(textArray[24]),
                                    content: Text(textArray[25]),
                                    actions: [
                                      TextButton(
                                        child: Text(textArray[8]),
                                        onPressed: () => Get.back(),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            } else {
                              debugPrint(
                                '[gps-single/multi] online & #LQR_LIST kosong/null — bypass pengecekan',
                              );
                            }
                          }
                        }
                        if (outBlockedGps) {
                          setDataOK('2');
                          break;
                        }
                        await acquireData('gps-single', textArray, currentData);
                        String toGo = widget.component['route'] ?? home;
                        routeStack.push(toGo);
                        gotoRoute(toGo);
                    } // end of switch
                  } catch (e) {
                    setDataOK('2');
                    errorReport(e);
                  } // end of try
                }
                if (mounted) {
                  setState(() {
                    tapped = false;
                  });
                }
              } // end if ! tapped
            }, // end of onTap
          ),
        ),
      );
    } // end if (widget.single)
    return button1;
  } // end of class _AttendQrGpsSelfieState build

  @override
  void dispose() {
    // Dispose resources here
    super.dispose();
  }
} // end of class _AttendQrGpsSelfieState
