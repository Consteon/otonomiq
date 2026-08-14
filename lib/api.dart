import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import "package:http/http.dart" as http;
import 'package:http/io_client.dart'; // part of dart.http package
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ntp/ntp.dart';
// import 'package:mobile_number/mobile_number.dart'; // android only
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointycastle/export.dart';
import 'package:transparent_image/transparent_image.dart';

import 'bloc_submit/bloc.dart';
import 'bloc_timer/bloc.dart';
import 'crypto/auth_crypto.dart';
import 'different_code/different_code.dart';
import 'firebase_notification_handler.dart';
import 'firestore_repository/add_to_event.dart';
import 'firestore_repository/firestore_generic_repository.dart';
import 'firestore_repository/proxy_repository.dart';
import 'firestore_repository/table_repository.dart';
import 'ftz_secret.dart';
import 'global.dart';
import 'global2.dart';
import 'login/api/user_repository.dart';
import 'model/function_body.dart';
import 'model/general_get_controller.dart';
import 'model/otq_state.dart';
import 'notification/bloc.dart';
import 'page/main_page.dart';
import 'part/build_part/channel.dart';
import 'redux/screen_transaction.dart';
import 'screen_session.dart';
import 'token_resolver.dart';
import 'widget/build_theme.dart';
import 'widget/driver_home_support.dart';
import 'widget/ftz_webview.dart';
import 'widget/logout_transition_support.dart';
import 'widget/photo_camera.dart';
import 'widget/ui_component.dart';

/// Login perf instrumentation. Mirrors UserRepository.loginPerfTrace.
/// Set to false (or remove) after root-cause confirmation.
bool _loginPerfTrace = true;

Future apiTest() async {
  bool testNow = true;
  int d = 1;
  if (testNow) {
    // argon test
    const pw = '287738';
    try {
      var testSHash = passwordHashCreate(pw);
      bool testResult = passwordVerify(pw, testSHash);
      bool testResult2 = passwordVerify('937898', testSHash);
      d = 1;
    } catch (ae) {
      d = 1;
    }
  } // end if (testNow)
} // end of apiTest

int getTableVid(String? com) {
  int result = appCodeController.applicationTableVid;
  if (com != null && com.isNotEmpty) {
    switch (com.toLowerCase()) {
      case 'con':
        result = 20342033315492;
        break;
      case 'auz':
        result = 70027002611015;
        break;
      case 'otq':
        result = 60936087747650;
        break;
      default:
        result = appCodeController.applicationTableVid;
    } // end switch (com.toLowerCase())
  } // end if (com != null && com.isNotEmpty)
  return result;
} // end of getTableVid

Future<void> callEventFunction() async {
  if (internetConnected()) {
    const String functionName = 'callEventFunction';
    String? currentSsid = await waitUntilNotNullScreenTx(
      functionName,
      '#INTERFACE_KEY',
      20,
    );
    if (currentSsid != loginSsid) {
      Timer(const Duration(seconds: 3), () async {
        if (currentSsid != null) {
          dynamic qParams = {"ssid": currentSsid};
          devPrint('=== call $eventFunctionName with param=$qParams');
          dynamic uri = Uri.https(functionFront, eventFunctionName);
          try {
            callHttpPost(uri, qParams);
          } catch (eHttp) {
            debugPrint(
              'Error in calling $eventCollectionName: $eHttp',
            ); // do nothing
          }
        }
      });
    } // end if (ssid != loginSsid)
  } // end if (internetConnected())
} // end of callEventFunction

Future scheduleSendImagesInImageMap() async {
  // run sendImagesInImageMap in a schedule.
  // because user tend to open the app and close it immediately
  // Run immediately
  await sendImagesInImageMap();
  historyTrim(day: 7).then((_) async {
    await historySync('scheduleSendImagesInImageMap1', false);
    await saveHistory();
    callEventFunction();
  });
  // Schedule to run after 1 minute
  Timer(const Duration(minutes: 1), () async {
    await sendImagesInImageMap();
    historySync('scheduleSendImagesInImageMap2', false);
    // Schedule to run after 2 minutes
    Timer(const Duration(minutes: 1), () async {
      await sendImagesInImageMap();
      historySync('scheduleSendImagesInImageMap3', false);
      // Schedule to run every 2 minutes thereafter
      Timer.periodic(imageUploadInterval, (Timer timer) async {
        await sendImagesInImageMap();
        historySync('scheduleSendImagesInImageMap4', false);
      });
    });
  });
} // end of scheduleSendImagesInImageMap

bool isGpsUpdated(int delay) {
  // true if gpsTime and current time difference is less than delay (in ms)
  return (DateTime.now().millisecondsSinceEpoch +
              time2GpsOffset -
              gpsTime.value)
          .abs() <
      delay;
} // end of isGpsUpdated

Future<void> startGettingGpsData() async {
  int? lastGTime = prefs.getInt('@lastGpsTime');
  if (lastGTime == null) {
    lastGTime = 0;
    await prefs.setInt('@lastGpsTime', lastGTime);
  }
  dynamic gpsArray = await Future.wait([
    secureRead(key: 'gpsData'),
    secureRead(key: 'gpsPlaceMark'),
  ]);

  if (gpsArray[0] != null) {
    gpsData = convertToPosition(gpsArray[0]);
  }
  if (gpsArray[1] != null) {
    gpsPlaceMark = convertToPlaceMark(gpsArray[1]);
  }
  // trigger location stream
  LocationSettings locationSettings = myLocationSetting();
  bool gpsEnabled = await Geolocator.isLocationServiceEnabled();
  dynamic gpsPermission = await Geolocator.checkPermission();
  if (gpsPermission == LocationPermission.denied ||
      gpsPermission == LocationPermission.deniedForever) {
    gpsPermission = await Geolocator.requestPermission();
  }
  if (gpsEnabled &
      ((gpsPermission == LocationPermission.always) |
          (gpsPermission == LocationPermission.whileInUse))) {
    positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
    positionStreamSubs = positionStream.listen(
      (Position position) {
        // update app gps
        int currentEpoch = DateTime.now().millisecondsSinceEpoch;
        if (position.timestamp.millisecondsSinceEpoch > 0 &&
            gpsTime.value <
                (position.timestamp.millisecondsSinceEpoch + time2GpsOffset)) {
          gpsData = positionCopy(position);
          gpsTime.value = gpsData.timestamp.millisecondsSinceEpoch;
          time2GpsOffset =
              position.timestamp.millisecondsSinceEpoch - currentEpoch;
        } // end if (position.timestamp.millisecondsSinceEpoch > 0)
        // devPrint("gpsTime:${gpsTime.value} , time2GpsOffset:$time2GpsOffset");
        gpsSaveTimer ??= Timer.periodic(const Duration(minutes: 3), (_) {
          getAppGps();
          devPrint('=======-======---= saved by 3 minute ${DateTime.now()}');
        });
      },
      onError: (e) {
        // Location service disabled mid-stream → geolocator emits
        // LocationServiceDisabledException on the stream. With no onError the
        // stream error is unhandled → fatal. Log + cancel the now-dead sub;
        // startGettingGpsData re-subscribes when GPS is re-enabled.
        devPrint('positionStream error (location disabled?): $e');
        positionStreamSubs.cancel();
      },
    );
  } // end if (gpsEnabled & (gpsPermission == LocationPermission.always))
} // end of startGettingGpsData

Future<dynamic> getAppGps() async {
  // check if gps data is available and updated
  // save to persistence storage if gps data is updated
  // return data from gpsData, gpsTime, gpsPlaceMark
  dynamic returnValue;
  const int getGpsDataWaitTime = 5; // in seconds
  const int acceptableGpsTime = 1800000; // in milliseconds, 30 minutes
  // positionStreamSubs
  //devPrint(
  //    'gpsTime= ${gpsTime.value}, lat=${gpsData.latitude}, alt=${gpsData.altitude}');
  if (gpsTime.value <= 0) {
    await gpsTime.stream
        .firstWhere((value) => value > 0)
        .timeout(
          const Duration(seconds: getGpsDataWaitTime),
          onTimeout: () => 0, // Do nothing on timeout
        ); // wait until get location for max 5 seconds
  }
  if (isGpsUpdated(acceptableGpsTime)) {
    // save data when gps data have meaningfully value
    if (internetConnected()) {
      // devPrint('--get placemark from gps');
      try {
        List<Placemark> temp = await placemarkFromCoordinates(
          gpsData.latitude,
          gpsData.longitude,
        );
        gpsPlaceMark = placeMarkCopy(temp[0]);
      } catch (e) {
        gpsPlaceMark = placeMarkCopy(null);
      }
      // devPrint('--end placemark from gps');
    } else {
      gpsPlaceMark = placeMarkCopy(null);
    }
    devPrint('== saving gps data etc');
    storage.write(key: 'gpsData', value: json.encode(gpsData));
    secureWrite(key: 'gpsPlaceMark', value: json.encode(gpsPlaceMark));
    prefs.setInt('@lastGpsTime', gpsTime.value);
    String gpsDataStream = positionToGpsString(gpsData);
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#GPSDATA': gpsDataStream,
          '#LASTGPSTIME': gpsTime.value,
        }),
      ),
    );
    returnValue = {
      'gpsData': gpsData,
      'gpsTime': gpsTime.value,
      'gpsPlaceMark': gpsPlaceMark,
    };
  } else {
    // when gps data is not updated return invalid gps data
    returnValue = {
      'gpsData': Position(
        latitude: invalidLocation,
        longitude: invalidLocation,
        // longitude: gpsData.longitude,
        altitude: -88.0,
        accuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        heading: 0.0,
        isMocked: false,
        timestamp: invalidTime,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      ), // gpsdData wi,
      'gpsTime': 0,
      'gpsPlaceMark': placeMarkCopy(null),
    };
  } // end if (gpsTime.value > 0)
  if (returnValue['gpsData'].latitude == invalidLocation ||
      returnValue['gpsData'].longitude == invalidLocation) {
    // Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).then((Position position) {
    await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        )
        .then((Position position) async {
          try {
            gpsData = positionCopy(position);
            gpsTime.value = gpsData.timestamp.millisecondsSinceEpoch;
            returnValue['gpsTime'] = position.timestamp.millisecondsSinceEpoch;
            returnValue['gpsData'] = position;
            storage.write(key: 'gpsData', value: json.encode(position));
            String gpsDataStream = positionToGpsString(position);
            transactionStore.dispatch(
              UpdateScreenTxAction(
                ScreenTransaction({
                  '#GPSDATA': gpsDataStream,
                  '#LASTGPSTIME': position.timestamp.millisecondsSinceEpoch,
                }),
              ),
            );
            prefs.setInt(
              '@lastGpsTime',
              position.timestamp.millisecondsSinceEpoch,
            );
            List<Placemark> myPL = await placemarkFromCoordinates(
              position.latitude,
              position.longitude,
            );
            returnValue['gpsPlaceMark'] = placeMarkCopy(myPL[0]);
            secureWrite(
              key: 'gpsPlaceMark',
              value: json.encode(returnValue['gpsPlaceMark']),
            );
          } catch (e) {
            try {
              returnValue['gpsData'] = position;
            } catch (e1) {
              returnValue['gpsData'] = Position(
                latitude: invalidLocation,
                longitude: invalidLocation,
                altitude: -88.0,
                accuracy: 0.0,
                speed: 0.0,
                speedAccuracy: 0.0,
                heading: 0.0,
                isMocked: false,
                timestamp: invalidTime,
                altitudeAccuracy: 0.0,
                headingAccuracy: 0.0,
              );
            } // end try gpsData
            try {
              returnValue['gpsTime'] =
                  position.timestamp.millisecondsSinceEpoch;
            } catch (e2) {
              returnValue['gpsTime'] = 0;
            } // end try gpsTime
            try {
              List<Placemark> myPL2 = await placemarkFromCoordinates(
                position.latitude,
                position.longitude,
              );
              returnValue['gpsPlaceMark'] = placeMarkCopy(myPL2[0]);
            } catch (e3) {
              returnValue['gpsPlaceMark'] = placeMarkCopy(null);
              returnValue['gpsPlaceMark'].name = 'Error $e';
            } // end try gpsPlaceMark
          } // end try
        })
        .catchError((Object e) {
          // getCurrentPosition itself rejects (location service off, permission
          // denied, timeout) -> the .then callback never runs, so the try/catch
          // INSIDE it is skipped and the error escapes getAppGps -> getLocation ->
          // OtqState.setAllDataAsync, which swallows it and returns an OtqState
          // still holding its defaults (mock=true, latitude=invalidLocation,
          // gpsDone=false). Keep the invalid-location sentinel already in
          // returnValue and report non-fatal instead.
          errorReport('getAppGps getCurrentPosition: $e');
        });
  }
  return returnValue;
} // end of getAppGps

int getCurrentTimeComparableToGpsTime() {
  return DateTime.now().millisecondsSinceEpoch + time2GpsOffset;
} // end of getCurrentTimeComparableToGpsTime

void updateAppGps(Position position) async {
  // update app gps
  int currentEpoch = DateTime.now().millisecondsSinceEpoch;
  if (position.timestamp.millisecondsSinceEpoch > 0 &&
      gpsTime.value < position.timestamp.millisecondsSinceEpoch) {
    gpsData = positionCopy(position);
    gpsTime.value = gpsData.timestamp.millisecondsSinceEpoch;
    time2GpsOffset = position.timestamp.millisecondsSinceEpoch - currentEpoch;
    gpsSaveTimer ??= Timer.periodic(const Duration(minutes: 3), (_) {
      getAppGps();
      devPrint('=======-======---= saved by 3 minute ${DateTime.now()}');
    });
  } // end if (position.timestamp.millisecondsSinceEpoch > 0)
} // end of updateAppGps

Future secureWrite({required String key, required String value}) async {
  // write encrypted value to secure storage
  try {
    return storage.write(key: key, value: value);
  } catch (e) {
    // errorReport(e);
    return null;
  }
} // end of secureWrite

Future<String?> secureRead({required String key}) async {
  // read encrypted value from secure storage
  try {
    return storage.read(key: key);
  } on PlatformException {
    // errorReport(e);
    return null;
  } catch (e) {
    // errorReport(e);
    return null;
  }
} // end of secureRead

Future<void> vibrate({int duration = 50}) async {
  // vibrate device in millisecond
  try {
    if (andrew) {
      // Use HapticFeedback for Android
      // HapticFeedback.vibrate(HapticFeedbackType.light);
      // await Future.delayed(Duration(milliseconds: duration));
      // HapticFeedback.vibrate(HapticFeedbackType.light);
    } else if (sinner) {
      // Use platform channel for iOS (example implementation)
      //await Platform.invokeMethod('vibrate', {"duration": duration});
    } else {
      // Handle other platforms or web
      debugPrint('Vibration not supported on this platform');
    }
  } on PlatformException catch (e) {
    debugPrint("Error: $e");
  }
} // end of vibrate

bool canInitializePage(String? thePage) {
  // check if the page is home or listed in asHomeArray
  // return true if the page is not home and not in asHomeArray
  // return false if the page cannot be initialized
  bool result = false;
  if (thePage != null) {
    result = (thePage == home && asHomeArray.contains(thePage));
  } // end if (thePage != null)
  return result;
} // end of canInit

bool internetConnected() {
  return internetConnectionFlag.value;
} // end of internetConnected

Future<bool> internetConnectedCheck({bool forceTest = false}) async {
  // check internet connection flag
  // use https://pub.dev/packages/internet_connection_checker_plus
  if (forceTest) {
    bool nowConnected = await internetConnection.hasConnection.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    ); //.InternetConnection().hasInternetAccess;
    if (nowConnected != internetConnectionFlag.value) {
      internetConnectionFlag.value = nowConnected;
    } // end if (nowConnected != internetConnectionFlag.value)
  } // end if (forceTest)
  return internetConnectionFlag.value;
} // end of internetConnected

Placemark placeMarkCopy(Placemark? placeMark) {
  return Placemark(
    name: placeMark?.name ?? emptyString,
    street: placeMark?.street ?? emptyString,
    isoCountryCode: placeMark?.isoCountryCode ?? invalidCountry,
    country: placeMark?.country ?? invalidCountry,
    postalCode: placeMark?.postalCode ?? emptyString,
    administrativeArea: placeMark?.administrativeArea ?? emptyString,
    subAdministrativeArea: placeMark?.subAdministrativeArea ?? emptyString,
    locality: placeMark?.locality ?? emptyString,
    subLocality: placeMark?.subLocality ?? emptyString,
    thoroughfare: placeMark?.thoroughfare ?? emptyString,
    subThoroughfare: placeMark?.subThoroughfare ?? emptyString,
  );
} // end of Placemark

Position positionCopy(Position? position) {
  return Position(
    latitude: position?.latitude ?? 0,
    longitude: position?.longitude ?? 0,
    accuracy: position?.accuracy ?? 0,
    altitude: position?.altitude ?? 0,
    floor: position?.floor ?? 0,
    heading: position?.heading ?? 0,
    speed: position?.speed ?? 0,
    speedAccuracy: position?.speedAccuracy ?? 0,
    timestamp: position?.timestamp ?? DateTime.now(),
    isMocked: position?.isMocked ?? false,
    altitudeAccuracy: position?.altitudeAccuracy ?? 0.0,
    headingAccuracy: position?.headingAccuracy ?? 0.0,
  );
} // end of positionCopy

Future<dynamic> callHttpPost(dynamic uri, dynamic param) async {
  if (await internetConnectedCheck()) {
    // http.post throws ClientException on a mid-request connection reset
    // ("Software caused connection abort") even when connectivity checked OK a
    // moment earlier. The caller (callEventFunction) does NOT await this, so an
    // uncaught throw escapes its (sync) try/catch and becomes a FATAL crash via
    // platformDispatcher.onError. Catch here, report non-fatal, return a
    // sentinel string (mirrors the "No internet connection" path below).
    try {
      return await http.post(uri, body: param);
    } catch (e) {
      errorReport('callHttpPost $uri: $e');
      return "Http post failed";
    }
  } else {
    return "No internet connection";
  } // end if (internetConnected())
} // end of callHttpPost

Future<List<dynamic>> sendHistoryImagesToCloud(position, content) async {
  // wrapper for position and content
  return [position, await replaceLocalImageToUrl(content)];
  //return [position, await uploadImageToCloud(content)];
} // end of sendHistoryImagesToCloud

// Strips the leading "<appSupportDir>/otq_images/FTZIMG/" from a decoded local
// image path, leaving the Firebase Storage folder.
//
// `lastIndexOf` returns -1 when the FTZIMG marker is absent, and the old inline
// arithmetic (-1 + 6 + 1) silently degraded to `substring(6)`: a RangeError on a
// path shorter than 6 chars, and a wrongly-chopped Storage folder on a longer
// one. The marker IS absent on two real paths — renamePath's else branch
// (non-camera input returned unchanged) and its rename+copy double-failure
// fallback to the raw camera path — so treat "no marker" as "no folder prefix
// to strip" and hand the caller what it already has.
/// Builds the canonical image file name for local storage.
/// Format: `FTZIMG%2F<Uri-encoded folder>___<Uri-encoded fileName>.jpg`
///
/// The round-trip contract:
///   split('___')[0] → Uri.decodeComponent → folderFromRawPath → original folder
///   split('___')[1] → raw fileName with .jpg extension
///
/// Used by [renamePath] and tested in test/image_destination_path_test.dart.
String buildImageDestinationName(String folder, String fileName) {
  String finalFolder = folder;
  if (finalFolder.endsWith('/')) {
    finalFolder = finalFolder.substring(0, finalFolder.length - 1);
  }
  return '$localImageBeginningFolderDivider%2F${Uri.encodeComponent(finalFolder)}$localImageFolderSeparator${Uri.encodeComponent(fileName)}.jpg';
}

String folderFromRawPath(String rawFolder) {
  final int i = rawFolder.lastIndexOf('$localImageBeginningFolderDivider/');
  if (i < 0) return rawFolder;
  return rawFolder.substring(i + localImageBeginningFolderDivider.length + 1);
}

Future<String> replaceLocalImageToUrl(String input) async {
  // replace local image to cloud url
  // input the whole event string
  // return new text
  String result = input;
  if (internetConnected()) {
    const pointerPrefix = 'FTZ||';
    String pattern = r"aum__(.*?)__mua";
    RegExp regex = RegExp(pattern);
    String newInput = input;
    try {
      Iterable<Match> matches = regex.allMatches(input);
      List<Future<dynamic>> futures = [];
      int c = 0;
      for (Match match in matches) {
        List<String> fileArray = match.group(1)!.split('___');
        String rawFolder = Uri.decodeComponent(fileArray[0]);
        String folder = folderFromRawPath(rawFolder);
        futures.add(uploadImageToCloud(match.group(1)!));
        // futures.add(saveImageToCloud(
        //     imagePath: match.group(1)!,
        //     folder: folder,
        //     rawFileName: fileArray[1]));
        String pointer = '$pointerPrefix${(++c).toString().padLeft(3, '0')}';
        newInput = newInput.replaceFirst(
          match.group(0) ?? emptyString,
          pointer,
        );
      } // end for (RegExpMatch match in matches)
      List<dynamic> urls = await Future.wait(futures);
      for (int i = 0; i < urls.length; i++) {
        String pointer = '$pointerPrefix${(i + 1).toString().padLeft(3, '0')}';
        String newUrl = urls[i];
        if (newUrl.contains(invalidPathPrefix) || newUrl == emptyString) {
          newUrl = defaultImage;
        } // end if (newUrl.contains(invalidPathPrefix))
        newInput = newInput.replaceFirst(pointer, newUrl);
      } // end for (int i = 0; i < urls.length; i++)
      result = newInput;
    } catch (e) {
      result = input;
    } // end try
  }
  return result;
} // end of replaceLocalImagetoUrl

Future<String> prepareImageAsLocal({
  required String imagePath,
  required String folder,
  required String fileName,
  bool forceRename = false,
}) async {
  // prepare image as local file, rename it with local name standard
  String result = emptyString;
  String finalImagePath = await renamePath(
    originalImagePath: imagePath,
    folder: folder,
    fileName: fileName,
    forceRename: forceRename,
  );
  // finalImagePath = finalImagePath.replaceAll('.jpg', '');
  result = '$localImagePrefix$finalImagePath$localImagePostfix';
  return result;
} // end of prepareImageAsLocal

Future saveImagePutInImageMap(String url) async {
  // put url entry in tableContent[imageMapName]
  // if connected to internet then try to send the image to cloud
  String localPath = url
      .replaceAll(localImagePrefix, '')
      .replaceAll((localImagePostfix), '');
  dynamic imageMapEntry = imageMapGet(localPath);
  if (imageMapEntry == null) {
    imageMapEntry = [
      DateTime.now().millisecondsSinceEpoch,
      emptyString,
      false,
      0,
      0,
    ];
    await imageMapUpdateUrl(localPath, emptyString);
  } // end if (imageMapEntry == null)
  if (await internetConnectedCheck()) {
    if (imageMapEntry[1].length < 5) {
      // try to upload the image to cloud
      List<String> fileArray = localPath.split('___');
      String rawFolder = Uri.decodeComponent(fileArray[0]);
      String folder = folderFromRawPath(rawFolder);
      // NOT awaited. Both callers (getPhotoCameraImage / getGalleryImage) are
      // awaited by the widget BEFORE it shows the thumbnail, so awaiting the
      // Storage round-trip here froze every capture for the whole upload:
      // getDownloadURL (404) + putFile + getDownloadURL — seconds on a weak
      // network, and the camera dialog was already closed with nothing on
      // screen. Nothing downstream needs the URL now: the entry is registered
      // in imageMap above, sendImagesInImageMap() re-uploads it periodically
      // AND is awaited at submit time (submit_repository.addNewSubmit2), which
      // is exactly the offline path that already works with no upload here.
      safeUnawaited(
        saveImageToCloud(
          imagePath: localPath,
          folder: folder,
          // A path with no '___' splits to a single element, so fileArray[1]
          // would throw the next RangeError right after the substring one this
          // guard removes. Same trigger (camera cancelled -> empty path).
          rawFileName: fileArray.length > 1 ? fileArray[1] : emptyString,
        ),
        'saveImagePutInImageMap upload',
      );
    }
  } // end if (await internetConnectedCheck())
} // end of saveImagePutInImageMap

Future replaceAumImageInHistoryUnUsed(
  String oldImage,
  String folder,
  String fileName,
) async {
  // replace relevant oldImage  in all history records with newImage from _IMAGEMap table
  String imagePath = oldImage
      .replaceAll(localImagePrefix, '')
      .replaceAll((localImagePostfix), '');
  String url = await uploadToCloudStorage(imagePath, "$folder/$fileName.jpg");
  if (isValidImageUrl(url)) {
    await historyLock('replaceAumImageInHistory');
    for (int i = 0; i < tableContent[historyName].length; i++) {
      if (tableContent[historyName][i][2].contains(oldImage)) {
        tableContent[historyName][i][2] = tableContent[historyName][i][2]
            .replaceAll(oldImage, url);
      } // end if (tableContent[historyName][i][2].includes(oldImage))
    } // end for (int i = 0; i < tableContent[historyName].length)
    historyUnLock('replaceImageInHistory');
    await saveHistory();
  } // end if (url != emptyImageUrl)
} // end of replaceImageInHistory

Future<List<String>> saveImageToCloud({
  required String imagePath,
  required String folder,
  required String rawFileName,
}) async {
  String fileName = rawFileName.replaceAll('.jpg', '');
  List<String> result = [emptyString, emptyString];
  String finalImagePath = await renamePath(
    originalImagePath: imagePath,
    folder: folder,
    fileName: fileName,
  );
  dynamic state = transactionStore.state.screenTx;
  try {
    if (await internetConnectedCheck()) {
      if (File(finalImagePath).existsSync()) {
        String tempResult = await uploadToCloudStorage(
          finalImagePath,
          "$folder/$fileName.jpg",
        );
        if (isValidImageUrl(tempResult)) {
          result = [finalImagePath, tempResult];
          await imageMapUpdateUrl(finalImagePath, tempResult);
        } else {
          result = [
            finalImagePath,
            '${invalidPathPrefix}01$invalidPathPostfix',
          ]; // not a valid url
        }
      } else {
        result = [
          finalImagePath,
          '${invalidPathPrefix}02$invalidPathPostfix',
        ]; // file not exist
      } // end if (file.existsSync())
    } // end if (transactionStore.state.screenTx['#INTERNET'] ?? false)
  } catch (e) {
    // result = '$localImagePrefix$finalImagePath$localImagePostfix';
    result = [
      finalImagePath,
      '${invalidPathPrefix}03:${e.toString()}$invalidPathPostfix',
    ]; // general error
  }
  return result;
} // end of saveImageToCloud

Future<String> renamePath({
  required String originalImagePath,
  required String folder,
  required String fileName,
  bool forceRename = false,
}) async {
  String tempImagePath = originalImagePath.replaceFirst(localImagePrefix, "");
  tempImagePath = tempImagePath.endsWith(localImagePostfix)
      ? tempImagePath.substring(
          0,
          tempImagePath.length - localImagePostfix.length,
        )
      : tempImagePath;
  String finalImagePath = tempImagePath;
  bool originalPath = tempImagePath.contains(
    localImageArtifact,
  ); // original path from camera
  if (originalPath || forceRename) {
    final Directory appDir = await getApplicationSupportDirectory();
    final String imageDir = '${appDir.path}/otq_images';
    await Directory(imageDir).create(recursive: true);
    finalImagePath = '$imageDir/${buildImageDestinationName(folder, fileName)}';
    try {
      await File(tempImagePath).rename(finalImagePath);
    } catch (e) {
      try {
        await File(tempImagePath).copy(finalImagePath);
        await File(tempImagePath).delete();
      } catch (e2) {
        finalImagePath = tempImagePath;
        debugPrint(
          'Cannot move $tempImagePath to $finalImagePath :${e2.toString()}',
        );
      }
    }
  } else {
    finalImagePath = tempImagePath;
  } // end if (originalPath
  return finalImagePath;
} // end of renamePath

Widget displayImage({
  String imageUrl = defaultImage,
  bool cached = true,
  BoxFit? fit,
}) {
  const int duration = 100;
  String finalUrl = defaultImage;
  late Widget result;
  if (imageUrl.isNotEmpty) {
    finalUrl = imageUrl;
  } // end if (imageUrl.isNotEmpty)
  try {
    if (finalUrl.startsWith(localImagePrefix)) {
      String localImage = finalUrl.substring(
        localImagePrefix.length,
        finalUrl.length - localImagePostfix.length,
      );
      File localFile = File(localImage);
      if (!localFile.existsSync()) {
        result = CachedNetworkImage(
          imageUrl: defaultImage,
          placeholder: (context, url) => Container(
            color: Colors.transparent, // Set transparency
            width: double.infinity, // Match image size
            height: double.infinity, // Match image size
          ),
        ); // default image
      } else {
        result = Image.file(
          localFile,
          fit: BoxFit.contain,
          // existsSync() above is a build-time check; Image.file loads async, so
          // the file can be deleted between check and load (history-sync uploads
          // then removes the local copy) → FileImage.length() PathNotFoundException
          // fires OUTSIDE the sync try/catch → fatal. errorBuilder catches the
          // deferred load error and falls back to the same transparent placeholder.
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.transparent,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      } // end if (!localFile.existsSync())
    } else {
      if (cached) {
        result = CachedNetworkImage(
          imageUrl: finalUrl,
          fit: fit, // null = old behavior; callers opt in (e.g. IMG logo)
          placeholder: (context, url) => Container(
            color: Colors.transparent, // Set transparency
            width: double.infinity, // Match image size
            height: double.infinity, // Match image size
          ), // Placeholder while loading
          errorWidget: (context, url, error) =>
              const Icon(Icons.error), // Error widget
          fadeInDuration: const Duration(
            milliseconds: duration,
          ), // Fade-in effect
        );
      } else {
        result = FadeInImage.memoryNetwork(
          fit: BoxFit.contain,
          placeholder: kTransparentImage,
          image: finalUrl,
          // Without imageErrorBuilder a failed fetch has no error listener, so
          // the framework reports it to FlutterError.onError → Crashlytics
          // fatal. Same guard the cached branch gets from errorWidget.
          imageErrorBuilder: (_, _, _) => const Icon(Icons.error),
        );
      } // end if(cached)
    }
  } catch (e) {
    result = CachedNetworkImage(
      imageUrl: defaultImage,
      placeholder: (context, url) => Container(
        color: Colors.transparent, // Set transparency
        width: double.infinity, // Match image size
        height: double.infinity, // Match image size
      ), // Placeholder while loading
      errorWidget: (context, url, error) =>
          const Icon(Icons.error), // Error widget
      fadeInDuration: const Duration(milliseconds: duration), // Fade-in effect
    );
  } // end try
  return result;
} // end of displayImage

String getAppVid(String ssid) {
  // should access to ssid and fetch the application vid from it
  String result = 'TestVid049848784'; // todo change this for production
  return result;
} // end of getAppVid

String getLocationString(
  String locId,
  String imageUrl,
  String position3,
  OtqState locSensor,
) {
  // Every free-text slot goes through cleanupString (global.dart). isoCountryCode
  // and postalCode are geocoder output like the address slots below and used to
  // be the only placemark fields written raw; locId is scanned-QR text. The
  // numeric slots (timestamp/lat/long) cannot carry a hostile char.
  final diamond = separator[1];
  String result = diamond; //1
  result += locSensor.nowTime.millisecondsSinceEpoch.toString() + diamond; //2
  result += cleanupString(position3) + diamond; //3
  result += cleanupString(locId) + diamond; //4
  result += locSensor.latitude.toString() + diamond; //5
  result += locSensor.longitude.toString() + diamond; //6
  result += cleanupString(imageUrl) + diamond; //7
  result += cleanupString(locSensor.isoCountryCode) + diamond; //8
  result += cleanupString(locSensor.postalCode) + diamond; //9
  result += cleanupString(locSensor.administrativeArea) + diamond; //10
  result += cleanupString(locSensor.subAdministrativeArea) + diamond; //11
  result += cleanupString(locSensor.locality) + diamond; //12
  result += cleanupString(locSensor.subLocality) + diamond; //13
  result += cleanupString(locSensor.thoroughfare) + diamond; //14
  result += cleanupString(locSensor.subThoroughfare);
  result += diamond + cleanupString(locSensor.locationStatus); // 15

  return result;
} // end of getLocationString

String myCountryCode() {
  try {
    dynamic cc = transactionStore.state.screenTx['#COUNTRY'];
    debugPrint('cc=$cc');
    int dd = 1;
  } catch (e) {
    int d = 1;
  }
  return transactionStore.state.screenTx['#COUNTRY'].toString();
} // end of getCountryCode

String phoneWithoutCC(String inp) {
  String result = inp.replaceAllMapped(RegExp(r'( |\.|-|\+|\(|\)|\[|\])'), (
    match,
  ) {
    return '';
  });
  String result1 = result.replaceAllMapped(RegExp(r'^' + myCountryCode()), (
    match,
  ) {
    return '';
  });
  String result2 = result1.replaceAllMapped(RegExp(r'^0'), (match) {
    return '';
  });
  return result2;
} // end of phoneWithoutCC

String phoneWithCC(String inp) {
  return '${myCountryCode()}${phoneWithoutCC(inp)}';
} // end of String phoneWithCC

Future<String> getQRContent(
  String qrType,
  String rawText,
  Position? position,
  String? rawTableString,
  String? negativeTableString,
  List<int>? refClusters,
) async {
  /*
     qrType L = location qr; U = user qr; G|other = no conversion
     output with prefix '#ErrorXX' indicate error number XX
     01 = out of range
     02 = no qr result
     05 = qr not in reference list
     06 = qr is not in positive list
     07 = qr is in negative list
     98 = qr not recognized
     99 = generic error
  */
  String tableString = normalizeTableName(
    autheniumDecode(rawTableString) ?? '',
  );
  final String errString = textList["ErrorPrefix"];
  dynamic result = '${errString}99';
  dynamic refTable;
  final List<int> clusters = refClusters ?? [];
  List<String> tableCodeArray = tableString.split(separator[1]) ?? [];
  String? tableCode = tableCodeArray.isNotEmpty ? tableCodeArray[0] : null;
  int tableColumn = max(
    0,
    ((tableCodeArray.length > 1) ? int.tryParse(tableCodeArray[1]) ?? 1 : 1) -
        1,
  );
  List<String> negativeTableCodeArray =
      negativeTableString?.split(separator[1]) ?? [];
  String? negativeTableCode = negativeTableCodeArray.isNotEmpty
      ? negativeTableCodeArray[0]
      : null;
  int negativeTableColumn = max(
    0,
    ((negativeTableCodeArray.length > 1)
            ? int.tryParse(negativeTableCodeArray[1]) ?? 1
            : 1) -
        1,
  );
  try {
    if (qrType == 'L') {
      dynamic p;
      dynamic q;
      await Future.wait([omLqrReaderP(), osLqrMakerQ()]).then((res) {
        p = res[0];
        q = res[1];
      });
      String lqr = await lqrVerify(p, q, rawText);
      if (lqr == errorString) {
        result = '${errString}98';
      } else {
        String resultOk = empty;
        if (tableCode == null || tableCode.isEmpty) {
          refTable = transactionStore.state.screenTx['#LQR_LIST'];
        } else {
          refTable = transactionStore.state.screenTx['#TABLE$tableCode'];
        }
        resultOk = (refTable[lqr]) != null ? lqr : empty;
        if (resultOk == empty || resultOk == errorString) {
          result = '${errString}02';
        } else {
          int tol = (refTable[lqr][3] ?? 0).round();
          num finalTolerance =
              (position == null ? 0 : (position.accuracy ?? 0).round()) + tol;
          num d = (distanceM(
            position!.latitude,
            position.longitude,
            refTable[lqr][1],
            refTable[lqr][2],
          )).round();
          if (d > finalTolerance) {
            result = '${errString}01';
          } else {
            result = lqr;
            //locationStatus = 1;
            // for (int t = 0; t < newArray.length; t++) {
            //   newArray[t] = newArray[t].replaceAll('<L>', resultOk);
            // } // end for newArray
          } // end if (d > finalTolerance)
        } // end if (resultOk != empty && resultOk != errorString)
      } // end if (finalQrText != empty && finalQrText != errorString)
    } else if (qrType == 'U') {
      if (tableCode == null) {
        refTable = {};
      } else {
        refTable = transactionStore.state.screenTx['#TABLE$tableCode'];
      }
      result = await getVidUQR(rawText);
      if (result == -1) {
        result = '${errString}98'; // qr not recognized
      } else {
        result = result.toString();
        if (refTable[result] == null) {
          result = '${errString}05'; // user not in list
        } // if (refTable[result]==null)
      }
    } else if (qrType == 'A') {
      // A for Asset
      String universalCode = assetVerify(rawText, 9); // Todo use component
      if (universalCode == errorString) {
        result = '${errString}98';
      } else {
        String resultOk = empty;
        if (tableCode == null || tableCode.isEmpty) {
          refTable = {};
        } else {
          refTable = transactionStore.state.screenTx['#TABLE$tableCode'];
        }
        resultOk = (refTable[universalCode]) != null ? universalCode : empty;
        if (resultOk == empty || resultOk == errorString) {
          result = '${errString}02';
        } else {
          if (negativeTableCode == null || negativeTableCode.isEmpty) {
            result = universalCode;
          } else {
            dynamic negativeList =
                transactionStore.state.screenTx['#TABLE$negativeTableCode'];
            resultOk = (negativeList[universalCode]) != null
                ? universalCode
                : empty;
            if (resultOk == empty || resultOk == errorString) {
              result = universalCode; // not in negative list
            } else {
              result = '${errString}07'; // in negative list
            } // end if (resultOk == empty || resultOk == errorString)
          } // end if (tableCode == null || tableCode.isEmpty)
        } // end if (resultOk != empty && resultOk != errorString)
      } // end if (finalQrText != empty && finalQrText != errorString)
    } else {
      result = rawText;
    } // end if (qrType == 'L')
  } catch (e) {
    result += ' $e';
  } // end try
  return result;
} // end of getQRContent

String ftzDateTimeFormatConverter(String source) {
  return source;
} // end of ftzDateTimeFormatConverter

Future syncLocaleTable() async {
  // load locale table from proxy's Locale!A1 checksum
  //   and Locale!B1:C
  // localeText : {
  //   "checksum": "329756954", last 6 digits = checksum, the front = last row
  //   "language": "id",
  //   "country": "ID",
  //   100010: "Masuk",
  //  }
  //  localeText will be read by function getLocaleText(String key)
  List response = [];
  const int nullValue = -99999;
  try {
    int lastChecksum = (prefs.getInt('@localeCheckSum') ?? nullValue);
    int wholeCS = 0;
    List response = await proxyRead(['Locale!A1']);
    wholeCS = response[0][0][0];
    if (lastChecksum != wholeCS) {
      int lastRow = (wholeCS / 1000000).floor();
      response = await proxyRead(["Locale!B1:C$lastRow"]);
      localeText = {};
      localeText['checksum'] = wholeCS;
      localeText['language'] = response[0][2][1];
      localeText['country'] = response[0][7][1];
      for (int i = 16; i < response[0].length; i++) {
        if (response[0][i][0].toString().isNotEmpty) {
          localeText[(response[0][i][0]).toString()] = response[0][i][1];
        } // end if isNotEmpty
      } // end for response[0]
      prefs.setString(
        '@localeText',
        stringCompress(jsonEncode(localeText)) ?? emptyString,
      );
      prefs.setInt('@localeCheckSum', wholeCS);
      int ddd = 1;
    } else {
      String? stored = prefs.getString('@localeText');
      localeText = jsonDecode(stringDecompress(stored) ?? '{}');
      int d = 1;
    } // end if (lastChecksum != wholeCS)
  } catch (e) {
    //result = {}; // error in reading Locale checksum
    int d1 = 2;
  }
  int dd = 1;
} // end of loadLocaleTable

String? stringCompress(String? inp) {
  String? result;
  try {
    if (inp != null) {
      final utf8EncodedString = utf8.encode(inp);
      final gZipString = gzip.encode(utf8EncodedString);
      result = base64.encode(gZipString);
    } // end (inp != null)
  } catch (_) {}
  return result;
} // end of stringCompress

String? stringDecompress(String? inp) {
  String? result;
  try {
    if (inp != null) {
      final decodedBase64Input = base64.decode(inp);
      final decodedGZipInput = gzip.decode(decodedBase64Input);
      result = utf8.decode(decodedGZipInput);
    } // end (inp != null)
  } catch (_) {}
  return result;
} // end of stringDecompress

Future<List> proxyRead(dynamic ranges) async {
  // ranges = ["Locale!A1","Locale!B1:C"]
  // result = [[result from range1],[results from range2]]
  List result = [];
  try {
    FunctionBody functionBody = getFunctionBody(
      transactionStore.state.screenTx['#INTERFACE_KEY'],
      ranges,
    );
    dynamic response = await http.post(
      Uri.parse(functionBody.url),
      body: functionBody.body,
    );
    result = jsonDecode(response.body);
    int d = 1;
  } catch (e) {
    result = [];
  }
  return result;
} // end of proxyRead

List<dynamic> getCurrencyFormat(String? inp) {
  const defaultLang = "en_US";
  const dotLang = "id_ID";
  List<dynamic> result = [
    "",
    defaultLang,
    0,
  ]; // symbol, thousand separator, mantissa
  String decodedInp = autheniumDecode(inp) ?? '';
  if (inp != null && inp.isNotEmpty) {
    List<dynamic> splitArray = decodedInp.split(separator[3]); // black star
    String lang = defaultLang;
    int aLen = splitArray.length;
    if (aLen == 1) {
      result = [splitArray[0], defaultLang, 0];
    } else if (aLen == 2) {
      try {
        lang = splitArray[1].toString().trim();
        if (lang == ".") {
          lang = dotLang;
        } else if (lang == ",") {
          lang = defaultLang;
        }
      } catch (e) {
        lang = defaultLang;
      }
      result = [splitArray[0], lang, 0];
    } else {
      int mantis = 0;
      try {
        mantis = int.parse(splitArray[2]);
      } catch (e) {
        mantis = 0;
      }
      try {
        lang = splitArray[1].toString().trim();
        if (lang == ".") {
          lang = dotLang;
        } else if (lang == ",") {
          lang = defaultLang;
        }
      } catch (e) {
        lang = defaultLang;
      }
      result = [splitArray[0], lang, mantis];
    } // end if alen
  }
  return result;
} // end of getCurrencyFormat

Future<String> dataProcess(
  BuildContext context,
  String inputText,
  String screenName,
  dynamic component,
) async {
  String resultOk = empty;
  String finalQrText = empty;
  List<dynamic> tArray = diamondTextToList(component['text'] ?? empty);

  // Platform messages may fail, so we use a try/catch PlatformException.
  try {
    int nowTime = 0; // = await ntpTimeSec();
    Position? position;
    dynamic p;
    dynamic q;

    await Future.wait([
      // getCurrentPosition(desiredAccuracy: LocationAccuracy.high),
      omLqrReaderP(),
      osLqrMakerQ(),
    ]).then((res) {
      p = res[0];
      q = res[1];
    });

    if (inputText != empty) {
      //got qr
      var scannedText = inputText;
      finalQrText = await lqrVerify(p, q, scannedText);
      if (finalQrText != errorString) {
        if (transactionStore.state.screenTx['#LQR_LIST'] == null) {
          resultOk = empty;
        } else {
          resultOk =
              (transactionStore.state.screenTx['#LQR_LIST'][finalQrText]) !=
                  null
              ? transactionStore.state.screenTx['#LQR_LIST'][finalQrText][0]
              : empty;
        } // end if (transactionStore.state.screenTx['#LQR_LIST'] == null)
      } else {
        resultOk = errorString;
      } // end if finalQrText
    } else {
      // got selfie url
      resultOk = errorString;
    } // end if inputText != empty

    actionLock('dataProcess api');
    switch (resultOk) {
      case empty: // valid qr but not listed in proxy
        // await Vibration.vibrate(duration: 50);
        // await Future.delayed(const Duration(milliseconds: 100));
        // Vibration.vibrate(duration: 50);
        if (component['position'] != null) {
          txfController[screenName]![getPosition(component['position'])]!
                  .controller
                  .text =
              textList["LocNotListed"];
          txfController[screenName]![getPosition(component['position'])]!
                  .finalData =
              finalQrText;
        } // end if (widget.component['position'] != null)
        break;

      case errorString:
        // await Vibration.vibrate(duration: 50);
        // await Future.delayed(const Duration(milliseconds: 100));
        // await Vibration.vibrate(duration: 50);
        // await Future.delayed(const Duration(milliseconds: 100));
        // Vibration.vibrate(duration: 50);
        if (component['position'] != null) {
          txfController[screenName]![getPosition(component['position'])]!
                  .controller
                  .text =
              "";
          txfController[screenName]![getPosition(component['position'])]!
                  .finalData =
              "";
        } // end  if (widget.component['position'] != null)
        break;

      default: // valid location qr
        // Vibration.vibrate(duration: 100);
        if (component['position'] != null) {
          txfController[screenName]![getPosition(component['position'])]!
                  .controller
                  .text =
              resultOk;
          txfController[screenName]![getPosition(component['position'])]!
                  .finalData =
              finalQrText;
        } // end if (widget.component['position'] != null)
    } // end of switch(resultOk)
  } catch (e) {
    errorReport(e);
    resultOk = errorString;
  }
  setDataOK('2'); // reload pages and display green status.
  return resultOk;
} // end of dataProcess

String getThousandSeparator(String lang) {
  late String result;
  try {
    dynamic fmt = NumberFormat("#,##0.00", lang);
    String thousandFormatted = fmt.format(1000.00);
    result = thousandFormatted[1];
  } catch (e) {
    result = ".";
  }
  return result;
} // end of getThousandSeparator

Future<void> openInWebView(
  BuildContext context,
  String url,
  String? title,
) async {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          title: Text(
            title ?? url,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Builder(
          builder: (BuildContext context) {
            return WebView(url: url);
          }, // end of builder
        ),
      ),
    ),
  );
} // end of openInWebView

int getNowMillisecondFromEpoch() {
  // return milliseconds from epoch integer
  //   relatively close to ntp, from device local time
  int result = DateTime.now().millisecondsSinceEpoch;
  int temp = result;
  try {
    dynamic state = transactionStore.state.screenTx;
    if (state['#REF_TIME_START'] != null) {
      result = (result + state['#REF_TIME_START'] - state['#DEVICE_TIME_START'])
          .round();
    } // end (state['#REF_TIME_START'] != null)
  } catch (e) {
    result = temp;
  } // end try
  return result;
} // end of getNowTime

String dateTimeToGSheet(DateTime myDate, bool utc) {
  String result = emptyString;
  result = utc
      ? NumberFormat("##0").format(myDate.millisecondsSinceEpoch)
      : NumberFormat("##0").format(
          myDate.millisecondsSinceEpoch + myDate.timeZoneOffset.inMilliseconds,
        );
  return result;
} // end of dateTimeToGSheet

String timeOfDayToGSheet(TimeOfDay myTime, bool utc) {
  String result = utc
      ? NumberFormat("##0").format(
          myTime.hour * 3600000 +
              myTime.minute * 60000 -
              DateTime.now().timeZoneOffset.inMilliseconds,
        )
      : NumberFormat(
          "##0",
        ).format(myTime.hour * 3600000 + myTime.minute * 60000);
  return result;
} // end of dateTimeToGSheet

void getLqrList(String? proxySsid) async {
  Map<String, dynamic> lqr = {};
  String? lqrString;
  try {
    lqrString = await secureRead(
      key: "lqrList",
    ); //= get documentID of entry in msg_xxxx collection
    if (lqrString != null) {
      lqr = json.decode(lqrString);
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#LQR_LIST': lqr})),
      );
      debugPrint('[getLqrList] cache #LQR_LIST=$lqr');
    }
  } catch (er) {
    errorReport(er);
  }

  try {
    while (locRange == '--') {
      // Wait until locRange is populated
      await Future.delayed(const Duration(milliseconds: 300));
      int d = 1;
    }
    FunctionBody functionBody = getFunctionBody(proxySsid!, [locRange]);
    dynamic locString = await http.post(
      Uri.parse(functionBody.url),
      body: functionBody.body,
    );
    dynamic lqrArray = json.decode(locString.body)[0];
    lqr = {};

    for (int i = 0; i < lqrArray.length && lqrArray[i][3] != ""; i++) {
      lqr[lqrArray[i][3]] = [
        lqrArray[i][2],
        lqrArray[i][0],
        lqrArray[i][1],
        lqrArray[i][4],
      ];
    } // end for in lqrArray
  } catch (eLoc) {
    errorReport(eLoc);
  }
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#LQR_LIST': lqr})),
  );
  debugPrint('[getLqrList] net #LQR_LIST=$lqr');
  storage.write(key: "lqrList", value: json.encode(lqr));
} //end of getLqrList

Future<void> getAllPermission() async {
  // Map<Permission, PermissionStatus> statuses =
  await [
    Permission.location,
    Permission.phone,
    Permission.camera,
    Permission.microphone,
  ].request();
  // devPrint('Location:${statuses[Permission.location]}');
  // devPrint('Phone:${statuses[Permission.phone]}');
}

void getCountryCodeList() async {
  // get list of country code from sim card (Android only)
  // TODO: add getCountryCodeList ios part
  // List<String> cCodes = ['62', '63', '60', '66', '91', '84', '65'];
  List<String> cCodes = [defaultCountry];
  // try {
  //   // final List<SimCard> simCards = (await MobileNumber.getSimCards)!;
  //   // cCodes = simCards
  //   //     .map((SimCard sim) => '62')
  //   //     .toSet()
  //   //     .toList();
  //
  // } on PlatformException catch (e) {
  //   devPrint("Failed to get mobile number because of '${e.message}'");
  // }
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({'#SIM_COUNTRY_CODES': cCodes, '#COUNTRY': cCodes[0]}),
    ),
  );
}

/// Next value of a thread's `urd` unread counter after one message is read or
/// deleted. Tolerates a missing or garbage counter: `null - 1` threw
/// NoSuchMethodError inside the transaction below, which aborted the decrement
/// AFTER the `st:101` update had already been queued — leaving a badge with no
/// unread message to match it, permanently.
int decUnread(dynamic cur) => (cur is num && cur > 1) ? cur.toInt() - 1 : 0;

Future setStatus(msgId, status) async {
  var statusUpdate = {
    "st": 101, // set to no need action
  };
  safeFsUpdate(
    FirebaseFirestore.instance.collection(firestoreNotif + "/msg").doc(msgId),
    statusUpdate,
    'setStatus',
  );

  final notifRef = FirebaseFirestore.instance.doc(firestoreNotif);
  // Guarded HERE, not per caller: a transaction cannot run offline (no
  // queueing, it needs a server round-trip), and `setStatus` is called
  // fire-and-forget from message_list.dart — an un-awaited rejection there
  // escapes to platformDispatcher.onError as a FATAL. notification_list.dart
  // had its own `.catchError`; its sibling did not. Nobody consumes the
  // return value, so never rejecting is the whole contract.
  safeUnawaited(
    FirebaseFirestore.instance.runTransaction((Transaction tx) async {
      final docSnapshot = await tx.get<Map<String, dynamic>>(notifRef);
      // A thread doc can exist without `urd` (server CF, half-applied offline
      // write) or not exist at all — either way tx.update would throw here.
      if (!docSnapshot.exists) return;
      tx.update(notifRef, {"urd": decUnread(docSnapshot.data()?['urd'])});
    }),
    'setStatus urd',
  ); // end of firebase transaction
}

Future sendMessage(mTo, mFrom, mDisplay, mData, mIn, mStatus) async {
  var tStamp = DateTime.now().millisecondsSinceEpoch;
  String msgId;
  var toVid = jsonDecode(mTo);
  //  var myState = transactionStore.state.screenTx;
  for (var i = 0; i < toVid.length; i++) {
    var val = toVid[i];
    var sendCollection = "$fsMsgCollection/$val/io/$mFrom";
    var messageCollection = FirebaseFirestore.instance.collection(
      "$sendCollection/msg",
    );
    var msg = {
      "to": val,
      "fr": mFrom,
      "dp": mDisplay,
      "dt": mData,
      "im": mIn,
      "st": mStatus,
      "id": '',
      "tr": tStamp,
      // should be deleted because time received will be written by receiver
    };
    await messageCollection.add(msg).then((doc) {
      msgId = doc.id;
      var updateData = {"id": msgId};
      safeFsUpdate(
        FirebaseFirestore.instance.collection("$sendCollection/msg").doc(msgId),
        updateData,
        'sendMessage',
      );
    });

    try {
      DocumentSnapshot docSnap = await FirebaseFirestore.instance
          .doc(sendCollection)
          .get();
      final postRef = FirebaseFirestore.instance.doc(sendCollection);
      await FirebaseFirestore.instance.runTransaction((Transaction tx) async {
        final docSnapshot = await tx.get<Map<String, dynamic>>(postRef);
        var currentUnread = docSnapshot.data()!['urd'] + 1;
        var updateData = {"lm": mDisplay, "urd": currentUnread, "lt": tStamp};
        tx.update(postRef, updateData);
      }); // end of firebase transaction
    } catch (eTrans) {
      // Was `errorReport(e)`: there is no `e` in scope here, so it silently
      // resolved to dart:math's Euler constant and every failed transaction
      // reported "2.718281828459045" to Crashlytics instead of the error.
      errorReport(eTrans);
    }
  }
} // end of sendMessage

Future<int> resetVid(List<dynamic> targets) async {
  String operationString = 'reset-device';
  // result : 1 = success
  //    -4 = general error; -5 vid registered in more than 1 user
  //    -6 = error accessing firebase
  int result = -4;
  // search for vid in dvc collection
  // if more than 1 user then return -5 error
  // reset all dvc :
  //  user => e : "-" ; u : "-"
  //  dvc => did : "TBD" ; in : false
  Map<String, dynamic> dvcData = {'did': 'TBD', 'in': false};
  Map<String, dynamic> userData = {'e': '-', 'u': '-'};

  try {
    for (dynamic target in targets) {
      operationString = 'reset-device';
      result = await FirebaseFirestore.instance
          .collectionGroup('dvc')
          .where('vid', isEqualTo: target[0]) // vid
          .get()
          .then((res) {
            String proxy = '';
            if (target[1] != null && target[1].isNotEmpty) {
              userData = {'e': '-', 'u': '-', 'i': phoneCanonical62(target[1])};
              operationString = 'reset-device-update-phone-number';
            } else {
              userData = {'e': '-', 'u': '-'};
              operationString = 'reset-device';
            } // end if (target[1] != null && target[1].isNotEmpty)
            bool parentUpdated = false;
            for (dynamic dvc in res.docs) {
              dynamic dvcRef = dvc.reference;
              proxy = dvc.data()['lif'];
              safeFsUpdate(
                dvcRef,
                dvcData,
                'resetVid-dvc',
              ); //= write updated data to user dvc
              if (!parentUpdated) {
                safeFsUpdate(
                  dvcRef.parent.parent,
                  userData,
                  'resetVid-user',
                ); //= write updated data to user
                parentUpdated = true;
              } // if (!parentUpdated)
            } // end for (dynamic dvc in dvcDocs)
            registerDeviceOperation(
              proxy,
              target[2],
              operationString,
              phoneCanonical62(target[1]),
            );
            return 1;
          });
    } // end for (String vid in vids)
  } catch (e) {
    result = -5;
  }
  return result;
} // end of resetVid

void resetVidUid(String userUid) async {
  // call GCP resetVid with uid as parameter.
  // delete all occurrence of uid in firebase and SQL
  // making user can be linked to other account
  // this is used by QA team
  var qParams = {"uid": userUid};
  var uri = Uri.https(cloudFunctionDomain, resetVidName, qParams);
  // Caller (ftz_row_of_button_2) does NOT await this void-async fn, so a bare
  // http.post throw (ClientException on mid-request connection reset) would
  // escape as a FATAL via platformDispatcher.onError. Route through the
  // hardened callHttpPost, which catches + reports non-fatal.
  await callHttpPost(uri, null);
}

Future getNewVid(String userUid, String userName, String userEmail) {
  // call function getNewVid. This function will give new vid and update firebase accordingly
  // output will be content of dvc entry
  var qParams = {"uid": userUid};
  if (userName != '') {
    qParams["name"] = userName;
  }
  if (userEmail != '') {
    qParams["email"] = userEmail;
  }
  var uri = Uri.https(cloudFunctionDomain, getNewVidFunctionName, qParams);
  return http.post(uri);
}

void getLinkInterfaceKey(BuildContext context, String vid, String pin) {
  String result = '';
  var b = transactionStore.state;
  var vidKey = b.screenTx['#VID_KEY'];
  dynamic vidList;
  int foundRow = -1;

  Future.wait([
    // TODO get from Firebase (get data from vidKey).
    sheetApi.spreadsheets.values.batchGet(
      vidKey,
      ranges: [vidRange],
      dateTimeRenderOption: "SERIAL_NUMBER",
      valueRenderOption: "UNFORMATTED_VALUE",
    ),
  ]).then((entryList) {
    vidList = entryList[0].valueRanges![0].values;
    bool found = false;
    for (var i = 0; i < vidList.length && !found; i++) {
      // loop for search of the right vid
      if (vidList[i][0] == vid || vidList[i][0] == int.parse(vid)) {
        found = true;
        foundRow = i;
      }
    }
    if (found) {
      // if vid found
      if (vidList[foundRow][4] == pin || // check for pin
          vidList[foundRow][4] == int.parse(pin)) {
        transactionStore.dispatch(
          UpdateScreenTxAction(
            //   if pin ok then
            ScreenTransaction({'#VID': int.parse(vid)}),
          ),
        ); //     set state #VID
        result = vidList[foundRow][2]; //     put interface key as result
        storage.write(key: 'myLif', value: result).then((val) {
          // put interface key in secure storage
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#INTERFACE_KEY': result})),
          ); //     set state #INTERFACE_KEY
          readSettings(result, 1).then((_) {
            rootThis.setState(() {
              rootThis.key = UniqueKey(); //     refresh page
            });
          });
        }); // store in secure & persistent storage
      } else {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              //   else (pin not match)
              title: const Text("User not found"),
              content: const Text(
                "Pin salah, masukan sekali lagi.",
              ), // show dialog
              actions: <Widget>[
                TextButton(
                  child: const Text("OK"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } else {
      // else (vid not found
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            //   show dialog (vid not found)
            title: const Text("User not found"),
            content: const Text("Vid tidak ditemukan."),
            actions: <Widget>[
              TextButton(
                child: const Text("OK"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  });
} // end of getLinkInterfaceKey

Future setDataOK(String iNumber) async {
  // iNumber = 1 : reload and set data ok
  // 1Number = 2 : set data ok only, because there is a cancel operation
  // iNumber = 3 : set data ok and reload (async)
  // iNumber = 4 : set data ok and reload without reading from spreadsheet (called by subscribeToProxy)
  // application will get green light by submit_bloc.dart > _mapSubmitUpdatedToState
  String desc = '';
  dynamic state = transactionStore.state;
  setTransactionOK('setDataOK $iNumber');
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({'#DATA_OK': true, '#REFRESH': false}),
    ),
  );
  switch (iNumber) {
    case '1': // reload from proxy
      desc = '1=>reload from proxy';
      var lifKey = state.screenTx['#INTERFACE_KEY'];
      String newRoute = transactionStore.state.screenTx['#CURRENT_ROUTE'];
      try {
        await readSettings(lifKey, 2) // read from JSON2
            .timeout(const Duration(seconds: 15)); // 15 sec timeout
        if (newRoute == home) {
          List<Widget> newElementList = reloadPage(newRoute);
          rootThis.setState(() {
            rootThis.pageName = newRoute;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
            rootThis.touch = !rootThis.touch;
            rootThis.dataColor = readyColor;
          });
        }
      } catch (e) {
        rootThis.setState(() {
          rootThis.wait = false;
          rootThis.touch = !rootThis.touch;
          rootThis.dataColor = readyColor;
        });
        errorReport(e);
      }
      break;

    case '2': // set data ok only
      desc = '2=>set data ok only';
      rootThis.setState(() {
        rootThis.wait = false;
        rootThis.touch = !rootThis.touch;
        rootThis.dataColor = readyColor;
      });
      break;

    case '3': // reload from proxy
      desc = '3=>reload from proxy';
      var lifKey = state.screenTx['#INTERFACE_KEY'];
      String newRoute = transactionStore.state.screenTx['#CURRENT_ROUTE'];
      try {
        readSettings(lifKey, 2) // read from JSON2
            .timeout(const Duration(seconds: 15)); // 15 sec timeout
        if (newRoute == home) {
          List<Widget> newElementList = reloadPage(newRoute);
          rootThis.setState(() {
            rootThis.pageName = newRoute;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
            rootThis.touch = !rootThis.touch;
            rootThis.dataColor = readyColor;
          });
        }
      } catch (e) {
        rootThis.setState(() {
          rootThis.wait = false;
          rootThis.touch = !rootThis.touch;
          rootThis.dataColor = readyColor;
        });
        errorReport(e);
      }
      break;

    case '4':
      desc =
          '4=>reload without reading from spreadsheet (called by subscribeToProxy)';
      String newRoute = transactionStore.state.screenTx['#CURRENT_ROUTE'];
      List<Widget> newElementList = reloadPage(newRoute);
      if (rootThis != null) {
        rootThis.setState(() {
          rootThis.pageName = newRoute;
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
          rootThis.touch = !rootThis.touch;
          rootThis.dataColor = readyColor;
        });
      } // end if (rootThis != null)
      break;
  }
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#CAMERA': false})),
  );
  debugPrint('setDataOK $desc');
  // devPrint(
  //     "Updating Done! #DATA_OK:${transactionStore.state.screenTx['#DATA_OK']}");
} // end of setDataOK

Future<dynamic> getDataFromCloud() async {
  // get data from functionName['appSettings'] ~ /appSettings3
  dynamic returnValue = [
    {body: jsonEncode(defaultCloudConfig)},
  ];
  if (internetConnected()) {
    try {
      dynamic qParams = {"app": appsCode};
      dynamic uri = Uri.https(
        autsorzFunctionDomain,
        appSettingFunctionName,
        qParams,
      );
      dynamic rawReturnValue = await Future.wait([
        http.post(uri).timeout(const Duration(seconds: 15)),
        //      getServiceAccountCredential(), //= TODO uncomment this
      ]);
      returnValue = [
        {'body': rawReturnValue[0].body},
      ];
    } catch (e) {
      returnValue = [
        {body: jsonEncode(defaultCloudConfig)},
      ];
    }
  }
  return returnValue;
} // end of getDataFromCloud

Future settingUp() async {
  // TODO call function in nearest server & use function callable. Still problem with firebase function
  dynamic r = [
    {body: jsonEncode(defaultCloudConfig)},
  ];
  String? storedAppSettings = await secureRead(key: 'appSettings');
  if (storedAppSettings == null || storedAppSettings == emptyString) {
    try {
      dynamic raw = await getDataFromCloud();
      String? data = raw[0][body];
      if (data != null) {
        dynamic j = json.decode(data);
        locRange = j['locRange'];
      } else {
        locRange = defaultCloudConfig['locRange'].toString();
      }
      secureWrite(key: 'appSettings', value: data ?? emptyString);
      r.add({body: data ?? emptyString});
    } catch (eCloud) {
      r = [
        {body: jsonEncode(defaultCloudConfig)},
      ];
      locRange = defaultCloudConfig['locRange'].toString();
    }
  } else {
    dynamic j = json.decode(storedAppSettings);
    locRange = j['locRange'];
    r = [
      {'body': storedAppSettings},
    ];
    if (internetConnected()) {
      try {
        getDataFromCloud().then((result) {
          try {
            String? data = result[0][body];
            if (data != null) {
              dynamic j = json.decode(data);
              locRange = j['locRange'];
            } else {
              locRange = defaultCloudConfig['locRange'].toString();
            }
            secureWrite(key: 'appSettings', value: data ?? emptyString);
            devPrint('=======>>>>>> data saved to secure appSettings: $data');
          } catch (eCloud) {
            // do nothing
          }
        }); // end of getDataFromCloud().then
      } catch (e) {
        // do nothing
      }
    } // end if (internetConnected())
  } // end if (storedAppSettings == null)
  return r;
} // end of settingUp

Future oldSettingUpShouldBeDeleted() async {
  return [];
} // end of settingUp

Future<bool> newUpdateApp() async {
  String? lastVersion;
  try {
    lastVersion = await secureRead(key: 'lastVersion');
  } catch (e) {
    dynamic error = e;
  }
  bool test = lastVersion != null && lastVersion != '$version$subVersion';
  return (lastVersion != null && lastVersion != '$version$subVersion');
} // end of newUpdateApp

/// Lif key whose pages are currently loaded in [screenUIComponent], or '' when
/// unknown.
///
/// Assigned ONLY where a load actually succeeded. `settingKey` cannot be used
/// for this: it is set BEFORE the HTTP call, so after a failed fetch it already
/// names the lif whose pages never arrived.
String loadedPagesLif = '';

/// True when the loaded pages belong to a signed-in user rather than to the
/// sign-in/signup LIF.
///
/// The shell must gate on THIS, not on auth state alone. `screenUIComponent`'s
/// `home` entry is a shared slot: before auth the sign-in page is deliberately
/// installed there (see the `settingKey == #GUEST_LIF` branch in readSettings),
/// and after auth the user's own home is meant to overwrite it. When that second
/// half fails, auth state says "signed in" while the slot still holds the login
/// form — which is exactly what painted a login screen under a live navbar.
bool userPagesLoaded() {
  if (loadedPagesLif.isEmpty) return false;
  final dynamic signupLif = transactionStore.state.screenTx['#GUEST_LIF'];
  return signupLif == null || loadedPagesLif != signupLif;
}

/// Persist the current home/system page maps to SharedPreferences so the next
/// (warm) startup renders the home shell from cache instead of re-fetching.
/// Guarded so an encode failure can't crash startup.
///
/// Each map is encoded exactly ONCE. When [alsoGuest] is true the same two
/// encoded strings are ALSO written to the guest snapshot keys
/// (`@guestScreenUI`/`@guestSystemUI`) for the instant logout→login restore —
/// avoiding a second large-map `json.encode` on the pre-`runApp` critical path.
void _persistUiCache({bool alsoGuest = false}) {
  try {
    final String screenJson = json.encode(screenUIComponent);
    final String systemJson = json.encode(systemUIComponent);
    prefs.setString('@screenUI', screenJson);
    prefs.setString('@systemUI', systemJson);
    // Provenance travels WITH the cache. Without it a warm start cannot tell a
    // cached user home from a cached sign-in page — both live under `home`.
    prefs.setString('@screenUILif', loadedPagesLif);
    if (alsoGuest) {
      // Guest snapshot reuses the SAME encoded strings — no re-encode. Gated by
      // the caller on signInProcess so only guest bootstrap pages are captured,
      // never an authenticated user's UI. At call time screenUIComponent['home']
      // already points to the guest login page, so the snapshot is self-contained.
      prefs.setString('@guestScreenUI', screenJson);
      prefs.setString('@guestSystemUI', systemJson);
    }
  } catch (e) {
    devPrint('save screenUI/systemUI failed: $e');
  }
}

/// Load the signed-in user's pages from Firestore `/Proxy/<lif>` instead of the
/// Sheets `readSS` Cloud Function.
///
/// WHY THIS EXISTS — measured 2026-08-03 against the live tenant workbook:
///   full login payload (3 ranges, 67 page definitions, 181,557 bytes)
///       -> 85.7s / 90.2s / 66.3s — and the 90.2s run came back HTTP 200 with a
///          24-BYTE body, i.e. junk the parser below would have choked on
///   system range alone (1,278 bytes) -> 3.6s / 4.0s / 5.8s
///   one page row      (2,419 bytes)  -> 4.7s / 4.2s / 3.4s
/// Rendering home needs ~3.7 KB and login was dragging 181 KB to get it. The
/// SAME content already lives in Firestore: `/Proxy/<lif>/System` and
/// `/Proxy/<lif>/Page` are exactly what the proxy listener in main_page.dart has
/// been applying in production, and Firestore reads on this path run ~0.2-0.5s.
///
/// Returns false and NEVER throws, so the caller falls back to readSettings().
/// Everything is decoded into locals and only then swapped into the globals —
/// a half-applied swap (system map from one source, pages from another) is
/// precisely what sank the earlier cache-first attempt.
Future<bool> loadPagesFromProxy(
  String lifKey, {
  bool skipIfUnchanged = false,
}) async {
  if (lifKey.isEmpty) return false;
  final sw = _loginPerfTrace ? (Stopwatch()..start()) : null;
  try {
    final bool ok = await _loadPagesFromProxy(
      lifKey,
      skipIfUnchanged: skipIfUnchanged,
    ).timeout(const Duration(seconds: 15));
    if (sw != null) {
      debugPrint(
        '[LOGINPERF] loadPagesFromProxy = ${sw.elapsedMilliseconds}ms ok=$ok',
      );
    }
    return ok;
  } catch (e) {
    devPrint('[LOGINPERF] loadPagesFromProxy failed, falling back: $e');
    return false;
  }
}

/// Decode `/Proxy/<lif>/{System,Page}` document bodies into the
/// name -> decoded-content map that systemUIComponent/screenUIComponent expect.
///
/// Each document is `{p: name, c: encoded JSON, t: epoch, v: vid}`. Documents
/// with a blank `p` are skipped — a nameless entry would otherwise land under
/// the key `''` and silently shadow nothing useful.
///
/// [onDecodeError] mirrors readSettings' policy for pages: one unparsable blob
/// becomes an error page instead of failing the whole load. Pass null (the
/// default, used for System) to let a bad blob throw, because a broken system
/// map has no safe substitute and must fall back to Sheets.
///
/// Pure and Firestore-free so the decode step can be tested on its own.
Map<String, dynamic> proxyDocsToUiMap(
  Iterable<dynamic> docBodies, {
  dynamic Function()? onDecodeError,
}) {
  final Map<String, dynamic> out = {};
  for (final dynamic d in docBodies) {
    if (d == null) continue;
    final String name = '${d['p'] ?? ''}';
    if (name.isEmpty) continue;
    if (onDecodeError == null) {
      out[name] = json.decode(d['c']);
    } else {
      try {
        out[name] = json.decode(d['c']);
      } catch (_) {
        out[name] = onDecodeError();
      }
    }
  }
  return out;
}

/// Map the `/Proxy/<lif>` document's profile fields onto their screenTx keys.
///
/// ★ Values are stringified. readSettings sets these from Settings!B1:B5 via
/// settingCell(), which returns `row[0].toString()`, so #VID and friends are
/// STRINGS at rest on every pre-existing path — while the proxy stores `v` and
/// `p` as numbers. #VID alone has 43 readers; handing them an int here would be
/// a far more expensive bug than a slow login.
///
/// Empty/absent fields are omitted rather than dispatched as '', so a partially
/// filled proxy document cannot blank out a key that already holds a good value.
Map<String, dynamic> proxyProfileKeys(dynamic rec) {
  const Map<String, String> fieldToKey = {
    'v': '#VID',
    'n': '#NAME',
    'e': '#EMAIL',
    'p': '#PHONE',
  };
  final Map<String, dynamic> out = {};
  if (rec == null) return out;
  fieldToKey.forEach((String field, String key) {
    final String s = '${rec[field] ?? ''}';
    if (s.isNotEmpty) out[key] = s;
  });
  return out;
}

/// Re-point the inbox stream at the real per-user message path and refresh the
/// badge. Extracted 1:1 from readSettingsStart's settings block so the proxy
/// loader path keeps it — without this the inbox stays bound to the boot-time
/// default and shows empty (project_firestoreio_boot_default_empty_inbox).
/// No-op when the stored cluster/msgId are absent (pre-login).
Future<void> rebindInboxFromStorage() async {
  try {
    final String? myCluster = await secureRead(key: 'myCluster');
    final String? myMsgId = await secureRead(key: 'myMsgId');
    if (myCluster == null || myMsgId == null) return;
    firestoreIO = msgIoPath(myCluster, myMsgId);
    firestoreMsg = firestoreIO;
    firestoreEventCollection = '$eventPrefix$myCluster';
    NotificationBloc.instance?.add(LoadNotification());
  } catch (e) {
    devPrint('rebindInboxFromStorage failed: $e');
  }
}

/// Boot-loader freshness gate: true when a cold-start proxy load must be
/// SKIPPED because the proxy has not moved since we last applied it.
///
/// ★ WHY. `/Proxy/<lif>` is a materialized copy that LAGS the sheet. The AppBar
/// refresh reads the sheet DIRECTLY (readSettingsContext -> /readSS) and writes
/// those fresh pages to `@screenUI`; opt-1 renders them on the next cold start.
/// Then asyncAppStartup2 ran the proxy loader unconditionally, swapped the OLDER
/// proxy copy back in, and `_persistUiCache()` overwrote the fresh cache with it
/// — so the refreshed data disappeared on reopen and stayed gone. Same symptom
/// as the listener-side clobber, new path since opt 2 went proxy-first.
///
/// Uses the same `@proxyCS_<lif>` checksum + int guard as the live listener in
/// main_page.dart. Skipping requires the in-memory pages to already BE this
/// lif's — never true on the login path, where memory still holds the guest
/// pages — so `true` means "pages for lifKey are loaded and at least as fresh
/// as the proxy", never "no pages". A non-int `t` falls through to the load
/// (old behaviour), as does a first run with no saved checksum.
bool proxyBootSkip({
  required bool skipIfUnchanged,
  required String lifKey,
  required String loadedLif,
  required dynamic proxyT,
  required int? savedCs,
}) =>
    skipIfUnchanged &&
    lifKey.isNotEmpty &&
    loadedLif == lifKey &&
    proxyT is int &&
    savedCs != null &&
    proxyT == savedCs;

Future<bool> _loadPagesFromProxy(
  String lifKey, {
  bool skipIfUnchanged = false,
}) async {
  final dynamic snap = await firestoreDb
      .collection(proxyCollectionName)
      .doc(lifKey)
      .get();
  if (snap == null || snap.exists != true) return false;
  final dynamic rec = snap.data();
  if (rec == null) return false;

  if (proxyBootSkip(
    skipIfUnchanged: skipIfUnchanged,
    lifKey: lifKey,
    loadedLif: loadedPagesLif,
    proxyT: rec['t'],
    savedCs: prefs.getInt('@proxyCS_$lifKey'),
  )) {
    devPrint('proxy unchanged (t=${rec['t']}) — keeping local pages');
    return true;
  }

  // Both subcollections in flight together — two ~200ms reads, not 400ms.
  final dynamic systemFuture = firestoreDb
      .collection('$proxyCollectionName/$lifKey/System')
      .get();
  final dynamic pageFuture = firestoreDb
      .collection('$proxyCollectionName/$lifKey/Page')
      .get();
  final dynamic systemSnap = await systemFuture;
  final dynamic pageSnap = await pageFuture;

  final Map<String, dynamic> newSystem = proxyDocsToUiMap(
    systemSnap.docs.map((dynamic d) => d.data()),
  );
  if (newSystem.isEmpty) return false;

  final Map<String, dynamic> newScreen = proxyDocsToUiMap(
    pageSnap.docs.map((dynamic d) => d.data()),
    onDecodeError: () => json.decode(errorPage),
  );
  // Provenance gate. No `home` means these are not usable pages for this user,
  // and swapping them in would recreate the "logged in but showing a page that
  // is not theirs" bug. Fall back to Sheets instead.
  if (newScreen[home] == null) return false;

  // ---- commit point: everything above decoded cleanly ----
  systemUIComponent = newSystem;
  screenUIComponent = newScreen;
  buildTheme(systemUIComponent[theme]);
  screenUIComponent['_Legal'] = json.decode(legalPage);
  screenUIComponent['_Invitation'] = json.decode(invitationPage);
  screenUIComponent['_NewPin'] = json.decode(newPinPage);
  try {
    asHomeArray = json.decode(rec['u'] ?? '[]');
  } catch (_) {
    asHomeArray = [];
  }

  // Persist the checksum of what was just loaded. subscribeToProxy restores
  // `@proxyCS_<ssid>` into #PROXY_LISTENER_CS when it (re)subscribes — which
  // happens right after login, when the Authenticated transition recreates
  // MainPage. Without this write the restored CS is last session's (or absent),
  // the listener's first snapshot sees `t != CS`, and it re-downloads the
  // identical System+Page set seconds after this function already applied it.
  // Same key and int guard as the listener's own persist (main_page.dart).
  if (rec['t'] is int) {
    try {
      prefs.setInt('@proxyCS_$lifKey', rec['t']);
    } catch (e) {
      devPrint('persist @proxyCS from proxy loader failed: $e');
    }
  }

  final Map<String, dynamic> profile = proxyProfileKeys(rec);
  if (profile.isNotEmpty) {
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(profile)));
  }
  // Deliberately NOT writing #PROXY_LISTENER_CS here. It is a single global slot
  // shared with the live proxy listener, which at this point is still subscribed
  // to the SIGN-IN lif (main_page subscribes once, in initState). Writing this
  // lif's checksum into it would mis-gate that listener. See the note in
  // _loginPagesReady.

  loadedPagesLif = lifKey;
  _persistUiCache();
  if (lifKey != transactionStore.state.screenTx['#GUEST_LIF']) {
    try {
      prefs.setString('@authedSystemUI', json.encode(systemUIComponent));
    } catch (e) {
      devPrint('proxy persist @authedSystemUI failed: $e');
    }
  }
  constructAllPageElements();
  return true;
}

Future<void> readSettingsStart(String? lifKey, int opt) async {
  // opt 1 = regular startup, load only home.
  // opt 2 = fastened setup, load as second loader in asyncAppStartup2
  debugPrint('start readSettingsStart opt=$opt');
  var myState = transactionStore.state.screenTx;
  //getLqrList(lifKey);
  debugCount = 521;
  trace(debugCount);
  var aRes = myState['#SETTINGS'];
  debugCount = 522;
  var res = json.decode(aRes[0]['body']);
  debugCount = 523;
  bool signInProcess = false;
  String guestRange = "JSON!B51:E51";
  String asHome = home;
  int guestIndex = 0;
  debugCount = 524;
  systemJsonRange = res['systemRange'];
  screenJsonRange = res['screenRange'];
  debugCount = 525;
  settingKey = lifKey;
  userKey = settingKey;
  String localeString = Platform.localeName;
  debugCount = 526;
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#INTERFACE_KEY': settingKey})),
  ); // set state #INTERFACE_KEY
  dynamic response;
  String lastPages = '';
  // Always reuse the cached pages on the startup-critical loader (opt 1) when
  // they exist, so the home shell renders immediately from cache instead of
  // blocking on a full network page-fetch. A version change (newUpdateApp) no
  // longer forces a blocking re-fetch here — the secondary loader
  // (asyncAppStartup2 / opt 2) always re-fetches the latest pages in the
  // background and rebuilds, so updated layouts appear a moment later.
  if (opt == 1) {
    try {
      lastPages = prefs.getString('@screenUI') ?? "";
    } catch (e) {
      dynamic error = e;
    }
  }
  bool firstTimeRun = lastPages.isEmpty;
  try {
    if (opt == 2 || lastPages.isEmpty) {
      debugCount = 527;
      trace(debugCount);
      signInProcess = settingKey == myState['#GUEST_LIF'];
      if (signInProcess) {
        // this is sign in process. Get dedicated page for this app type
        guestIndex = (50 + myState['#GUEST_INDEX']).toInt();
        debugCount = 528;
        if (needUpgrade != empty) {
          guestIndex = 59; // get info page
        }
        guestRange =
            "JSON!B$guestIndex:E$guestIndex"; // get dedicated sign in page from appSettings. #GUEST_INDEX was defined in serverSetup()
        debugCount = 529;
      } else {
        if (needUpgrade != empty) {
          guestIndex = (51 + myState['#VM_UPGRADE_INDEX']).toInt();
          if (opt == 2) {
            // as secondary loader
            guestRange = res['screenRange']; // load all pages
          } else {
            guestRange =
                "JSON!B$guestIndex:E$guestIndex"; // get dedicated sign in page from appSettings. #GUEST_INDEX was defined in serverSetup()
          }
          debugCount = 5210;
        }
        debugCount = 5211;
        trace(debugCount);
        await runSheetStartup(settingKey, myState['#CLUSTER']);
        debugCount = 5212;
      }
      trace(debugCount);
      if (firstTimeRun) {
        devPrint('First time run');
        debugCount = 52121;
        trace(debugCount);
        try {
          FunctionBody functionBody = getFunctionBody(settingKey, [
            systemJsonRange,
            guestRange,
            lifSetting,
          ]);
          response = await http
              .post(Uri.parse(functionBody.url), body: functionBody.body)
              // 60s, matching the login path. This was 15s while the same CF
              // call measures 27-38s for a heavy tenant's own LIF (the sign-in
              // LIF is 3.4s, which is why this only bites AFTER a login). The
              // "recovers gracefully" note below was wrong for that case: this
              // is `firstTimeRun`, so bailing leaves screenUIComponent empty,
              // linkElement[home] never built, and MainPageState crashed on its
              // force-unwrap before any UI existed. signOut wipes @screenUI, so
              // logout -> cold start reached exactly that state.
              .timeout(const Duration(seconds: 60));
          debugCount = 5213;
          trace(debugCount);
          lastPages = response.body;
        } catch (e) {
          debugCount = 5214;
          // A handled timeout here still bails below; the caller-side guards
          // (empty linkElement -> page gate) keep that survivable instead of
          // fatal. reportNonTimeout skips TimeoutException, forwards real errors.
          reportNonTimeout(e);
        }
        // The first-time settings POST above failed (timeout/network): the
        // inner catch reported it but `response` is still null. Bail here
        // instead of falling through to `jsonDecode(response.body)` — that
        // null-deref was the `NoSuchMethodError: getter 'body' on null` that
        // surfaced from the outer catch. `firstTimeRun` means `@screenUI` was
        // empty, so there is no cached page to construct from anyway.
        if (response == null) return;
        // Same class of bail as the null case: a gateway/proxy hiccup returns a
        // plain-text body ("upstream request timeout"), not JSON — jsonDecode
        // would throw FormatException on the startup path. First run has no
        // cached page anyway, so bail.
        final String rsBody = response.body.trimLeft();
        if (rsBody.isEmpty || (rsBody[0] != '[' && rsBody[0] != '{')) {
          devPrint('readSettingsStart: non-JSON body, bail: ${response.body}');
          return;
        }
        dynamic getResult = jsonDecode(response.body);
        debugCount = 5215;
        trace(debugCount);
        //systemUIComponent.clear();
        for (
          var i = 0;
          i < getResult[0].length &&
              getResult[0][i].length > 0 &&
              getResult[0][i][0].length > 0;
          i++
        ) {
          var combination = combineJson(getResult[0][i]);
          systemUIComponent[getResult[0][i][0]] = json.decode(combination);
        }
        debugCount = 5216;
        buildTheme(systemUIComponent[theme]);
        //screenUIComponent.clear();
        screenUIComponent['_NewPin'] = json.decode(newPinPage);
        screenUIComponent['_Legal'] = json.decode(legalPage);
        screenUIComponent['_Invitation'] = json.decode(invitationPage);
        debugCount = 5217;
        getResult[1].forEach((scr) {
          var combination = combineJson(scr);
          try {
            screenUIComponent[scr[0]] = json.decode(combination);
          } catch (_) {
            screenUIComponent[scr[0]] = json.decode(errorPage);
          }
        });
        debugCount = 5218;
        trace(debugCount);
        if (signInProcess) {
          asHome = getResult[1][0][0];
          screenUIComponent[home] =
              screenUIComponent[asHome]; // if in sign in process, copy this page as home
          debugCount = 5219;
          trace(debugCount);
        } else if (needUpgrade != empty) {
          asHome = getResult[1][0][0];
          screenUIComponent[home] =
              screenUIComponent[asHome]; // if in sign in process, copy this page as home
          debugCount = 5220;
          trace(debugCount);
        }
        debugCount = 5221;
        // Settings!B1:B5 -> [vid, name, email, phone, type]. Read every cell
        // through settingCell(): a blank cell arrives as `[]` and trailing
        // blanks are dropped, so direct [n][0] indexing throws RangeError.
        final String currentVid = settingCell(getResult[2], 0);
        if (currentVid.isNotEmpty) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#VID': currentVid})),
          );
          String myCluster = (await secureRead(key: "myCluster"))!;
          String myMsgId = (await secureRead(key: "myMsgId"))!;
          firestoreIO = msgIoPath(myCluster, myMsgId);
          firestoreMsg = firestoreIO;
          // Inbox stream was bound to the boot-time default path at launch;
          // now that the real path is set, re-subscribe so the badge + inbox
          // populate immediately (no need to wait for an incoming push to
          // trigger a reload).
          NotificationBloc.instance?.add(LoadNotification());
          firestoreEventCollection = '$eventPrefix$myCluster';
          debugCount = 5222;
        }
        debugCount = 5223;
        final String sName = settingCell(getResult[2], 1);
        if (sName.isNotEmpty) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#NAME': sName})),
          );
        }
        debugCount = 5224;
        final String sEmail = settingCell(getResult[2], 2);
        if (sEmail.isNotEmpty) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#EMAIL': sEmail})),
          );
        }
        debugCount = 5225;
        final String sPhone = settingCell(getResult[2], 3);
        if (sPhone.isNotEmpty) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#PHONE': sPhone})),
          );
        }
        debugCount = 5226;
        final String sType = settingCell(getResult[2], 4);
        if (sType.isNotEmpty) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#TYPE': sType})),
          );
        }
        debugCount = 5227;
        trace(debugCount);
        // #1 Persist the home/system pages from the FIRST fetch now — before
        // the all-pages load below. Previously the save sat AFTER readUIPages
        // inside the same try, so a readUIPages timeout (~15s) threw and SKIPPED
        // the save → @screenUI stayed empty → every reopen re-fetched (the slow
        // "Loading…"). Saving here breaks that cycle.
        // Persist the home/system pages AND (when signInProcess) snapshot the
        // guest UI for an instant logout→login restore — both from a SINGLE
        // encode of each map. Gating on signInProcess (== settingKey matches
        // #GUEST_LIF) means only guest bootstrap pages are captured, never an
        // authenticated user's UI. At this point screenUIComponent['home']
        // already points to the guest login page (assigned above when
        // signInProcess), so the snapshot is self-contained: signOut() can
        // restore it and show login with no fetch.
        loadedPagesLif = settingKey ?? '';
        _persistUiCache(alsoGuest: signInProcess);
        // #2 On the startup-critical loader (opt 1) DON'T block home on the
        // full all-pages fetch — the home page is already in screenUIComponent
        // from the first fetch. The background loader (asyncAppStartup2 / opt 2,
        // which runs right after home on every launch) fetches the complete
        // page set and re-caches it.
        if (opt != 1) {
          // Background all-pages refresh. Home/system pages are already
          // persisted above (_persistUiCache), so a network TimeoutException
          // here is benign — the opt-2 loader re-runs on every launch. Swallow
          // only the timeout (debug log); still surface genuine server/parse
          // failures so they remain visible in Crashlytics.
          try {
            await readUIPages(settingKey, guestIndex);
          } on TimeoutException catch (e) {
            devPrint('readUIPages timed out (background refresh): $e');
          } catch (e) {
            errorReport(e);
          }
        }
        debugCount = 5228;
        trace(debugCount);
      } else {
        devPrint('Not first time run');
        debugCount = 52281;
        trace(debugCount);
      } // end if (firstTimeRun)
      debugCount = 52282;
      trace(debugCount);
    } else {
      // Load the home shell from cache. Guard each key independently so a
      // missing @systemUI can't NPE — keep whatever serverSetup already set.
      final String? lastSystem = prefs.getString('@systemUI');
      if (lastSystem != null) {
        systemUIComponent.clear();
        systemUIComponent = jsonDecode(lastSystem);
      }
      screenUIComponent.clear();
      screenUIComponent = jsonDecode(lastPages);
      // These pages came from @screenUI, so their provenance is whatever wrote
      // that cache — restore it rather than assuming it belongs to this user.
      loadedPagesLif = prefs.getString('@screenUILif') ?? '';
      debugCount = 5229;
    } // end if (opt == 2 || lastPages.isEmpty)
    devPrint('saving screenUIComponent & systemUIComponent to pref');
    _persistUiCache();
    debugCount = 52291;
    trace(debugCount);
    if (opt == 2) {
      int launchOk = 0;
      launchOk = await launchCheck(); // Check launch status
      if (launchOk > 0) {
        // error in launchCheck
        // TODO create error message to display
        debugCount = 5230;
        trace(debugCount);
      } else {
        debugCount = 5231;
        trace(debugCount);
      } // end if launchOk
    }
    constructAllPageElements();
    debugCount = 5232;
  } catch (e) {
    errorReport(e);
    //debugCount = 5233;
  }

  debugPrint('end readSettingsStart');
} // end of readSettingsStart

Future<void> readUIPages(String lifKey, int guestIndex) async {
  // read json part of lif and put them in screenUIComponent
  FunctionBody functionBody = getFunctionBody(settingKey, [screenJsonRange]);
  var response = await http
      .post(Uri.parse(functionBody.url), body: functionBody.body)
      .timeout(const Duration(seconds: 15));
  var entryList = jsonDecode(response.body);
  entryList[0].forEach((scr) {
    var combination = combineJson(scr);
    try {
      screenUIComponent[scr[0]] = json.decode(combination);
    } catch (_) {
      screenUIComponent[scr[0]] = json.decode(errorPage);
    }
  });
  if (guestIndex > 0) {
    // this is sign in process
    screenUIComponent[home] =
        screenUIComponent[entryList[0][guestIndex -
            51][0]]; // change home with dedicated signin page
  }
  // await prefs.setString('@systemUI', jsonEncode(systemUIComponent));
  // await prefs.setString('@screenUI', jsonEncode(screenUIComponent));
  // constructAllPageElements();
} // end of readUIPages

/// Returns TRUE when fresh pages were fetched and applied, FALSE when the
/// fetch failed and the in-memory `screenUIComponent` was left untouched.
///
/// Callers that only repaint an already-authenticated user's own pages can
/// ignore the result — rebuilding from the surviving in-memory copy is correct
/// graceful degradation there. The LOGIN caller must NOT: at login the surviving
/// copy is still the GUEST LIF, so repainting it renders the sign-in form as if
/// it were home (nav bar on, body stuck on login). That path has to gate its
/// page swap on this flag.
///
/// [timeoutSec] guards the settings HTTP POST. The default 8s fits interactive
/// refresh; login passes a longer budget because the backend has been measured
/// at 4-14s and the user is already waiting on a blocking screen.
Future<bool> readSettings(String lifKey, int opt, {int timeoutSec = 8}) async {
  // opt 1 = Load as usual from JSON etc; 2 = load from JSON2 only
  // then constructPageElement of the respective screen

  var myState = transactionStore.state.screenTx;
  var aRes = myState['#SETTINGS'];
  var res = json.decode(aRes[0]['body']);

  // if (devMode) {
  //   systemJsonRange = _res['devSystemRange'];
  //   screenJsonRange = _res['devScreenRange'];
  // } else {
  systemJsonRange = res['systemRange'];
  screenJsonRange = res['screenRange'];
  if (opt == 2) {
    screenJsonRange = res['screenRange2'];
  }
  // }
  settingKey = lifKey;

  // transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
  //     {'#INTERFACE_KEY': userKey}))); // set state #INTERFACE_KEY
  userKey = settingKey;
  String tempVidKey = res['vidKey'];
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({'#VID_KEY': tempVidKey, '#INTERFACE_KEY': userKey}),
    ),
  );

  http.Response? response;
  try {
    FunctionBody functionBody;
    if (opt == 1) {
      functionBody = getFunctionBody(settingKey, [
        systemJsonRange,
        screenJsonRange,
        lifSetting,
      ]);
    } else {
      //opt == 2
      functionBody = getFunctionBody(settingKey, [screenJsonRange]);
    }
    if (_loginPerfTrace) {
      debugPrint(
        // settingKey is logged because the sign-in-LIF fetch and the user-LIF
        // fetch are otherwise indistinguishable in the log (same ranges, same
        // body size) while only one of them fails — and an empty/wrong key
        // looks exactly like a slow workbook from the client side.
        // `#GUEST_LIF` is res['signupLif'] (api.dart:4146): the LIF holding the
        // sign-in/signup screens. It is NOT a guest account — this app requires
        // login. Labelled signupLif here to match what it actually is.
        '[LOGINPERF] readSettings.req key=$settingKey signupLif=${settingKey == myState['#GUEST_LIF']} body=${functionBody.body.toString().length}b ranges=[$systemJsonRange | $screenJsonRange]',
      );
    }
    final swRS = _loginPerfTrace ? (Stopwatch()..start()) : null;
    response = await http
        .post(Uri.parse(functionBody.url), body: functionBody.body)
        .timeout(Duration(seconds: timeoutSec));
    if (swRS != null) {
      debugPrint(
        '[LOGINPERF] readSettings.http = ${swRS.elapsedMilliseconds}ms',
      );
    }
  } catch (e) {
    reportNonTimeout(e);
  }
  if (response == null) {
    // F1: HTTP timeout or network error. The in-memory screenUIComponent
    // survives, so refresh callers may rebuild from it — but say so, because
    // the login caller must NOT (its in-memory copy is the guest LIF).
    if (_loginPerfTrace) {
      debugPrint(
        '[LOGINPERF] readSettings FAILED (response null), returning early',
      );
    }
    return false;
  }
  var getResult = jsonDecode(response.body);
  // Measured 2026-08-03: the full-payload fetch sometimes returns HTTP 200 with
  // a 24-byte body instead of the expected [system, screens, settings] arrays.
  // Indexing that threw part-way through the load; treat it as a failed fetch
  // so the caller can retry or fall back, exactly like a timeout.
  if (getResult is! List || getResult.length < (opt == 1 ? 3 : 1)) {
    devPrint(
      'readSettings: unexpected body shape, treating as failure: ${response.body}',
    );
    return false;
  }
  if (opt == 1) {
    // systemUIComponent.clear();
    for (
      var i = 0;
      i < getResult[0].length &&
          getResult[0][i].length > 0 &&
          getResult[0][i][0].length > 0;
      i++
    ) {
      var combination = combineJson(getResult[0][i]);
      systemUIComponent[getResult[0][i][0]] = json.decode(combination);
    }
    // screenUIComponent.clear();
    buildTheme(systemUIComponent[theme]);
    screenUIComponent['_Legal'] = json.decode(legalPage);
    screenUIComponent['_Invitation'] = json.decode(invitationPage);
    screenUIComponent['_NewPin'] = json.decode(newPinPage);
    getResult[1].forEach((scr) {
      var combination = combineJson(scr);
      try {
        screenUIComponent[scr[0]] = json.decode(combination);
      } catch (_) {
        screenUIComponent[scr[0]] = json.decode(errorPage);
      }
    });
    if (settingKey == myState['#GUEST_LIF']) {
      // sign in process
      int index = myState['#GUEST_INDEX'] - 1;
      if (needUpgrade == empty) {
        screenUIComponent[home] = screenUIComponent[getResult[1][index][0]];
      } else {
        screenUIComponent[home] =
            screenUIComponent[myState['#GUEST_UPGRADE_INDEX']]; // row 59
      }
    } else if (needUpgrade != empty) {
      screenUIComponent[home] = screenUIComponent[needUpgrade];
    }
    // Settings!B1:B5 -> [vid, name, email, phone, type]. Read every cell
    // through settingCell(): a blank cell arrives as `[]` and trailing blanks
    // are dropped, so direct [n][0] indexing throws RangeError. There is no
    // try/catch around this block, so that throw was fatal on login.
    final String currentVid = settingCell(getResult[2], 0);
    if (currentVid.isNotEmpty) {
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#VID': currentVid})),
      );
      // firestoreIO = '$firestoreCollection/$currentVid/io';
      // firestoreMsg = firestoreIO;
      //  firestoreMsg = 'users/922250226073/io/vid1111/msg';
      final String sName = settingCell(getResult[2], 1);
      if (sName.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#NAME': sName})),
        );
      }
      final String sEmail = settingCell(getResult[2], 2);
      if (sEmail.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#EMAIL': sEmail})),
        );
      }
      final String sPhone = settingCell(getResult[2], 3);
      if (sPhone.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#PHONE': sPhone})),
        );
      }
      final String sType = settingCell(getResult[2], 4);
      if (sType.isNotEmpty) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#TYPE': sType})),
        );
      }
    }
    constructAllPageElements();
  } else {
    // opt == 2
    getResult[0].forEach((scr) {
      var combination = combineJson(scr);
      if (combination.trim().length > 1) {
        // devPrint('JSON2 : ${scr[0]}');
        try {
          screenUIComponent[scr[0]] = json.decode(combination);
          constructPageElements(scr[0]);
        } catch (_) {
          screenUIComponent[scr[0]] = json.decode(errorPage);
        }
      }
    });
  }
  // save array tp persistence data

  try {
    var saveLast = <Future>[];
    // Encoded once each and reused below — systemUIComponent used to be encoded
    // twice here (plain + authed snapshot).
    final String systemJson = json.encode(systemUIComponent);
    final String screenJson = json.encode(screenUIComponent);
    saveLast.add(prefs.setString('@systemUI', systemJson));
    saveLast.add(prefs.setString('@screenUI', screenJson));
    // Persist the authed system snapshot for cache-first navbar restore on the
    // next login. Gated on non-guest settingKey so the guest bootstrap pages
    // never overwrite the last authenticated session's bottomBar.
    if (settingKey != myState['#GUEST_LIF']) {
      saveLast.add(prefs.setString('@authedSystemUI', systemJson));
    }
    // Set BEFORE the awaits: the pages are already applied to
    // screenUIComponent at this point, so the shell may render them even if
    // persisting them fails.
    loadedPagesLif = lifKey;
    saveLast.add(prefs.setString('@screenUILif', lifKey));
    await Future.wait(saveLast);
  } catch (e) {
    errorReport("Error in saving to shared preferences (readSettings): $e");
  }
  // await prefs.setString('@systemUI', json.encode(systemUIComponent));
  // await prefs.setString('@screenUI', json.encode(screenUIComponent));
  // Pages were fetched and applied. A prefs-write failure above is logged but
  // does not invalidate the in-memory pages, so it stays a success.
  return true;
} // end of readSettings

/// Re-run the page fetch for the signed-in user and rebuild the shell.
/// Used by the shell's retry action when the post-login fetch failed.
/// Returns false when the fetch failed again (shell stays on its retry state).
Future<bool> retryUserPages() async {
  final dynamic lifKey = transactionStore.state.screenTx['#INTERFACE_KEY'];
  if (lifKey == null || lifKey.toString().isEmpty) return false;
  final bool ok = await readSettings(lifKey.toString(), 1, timeoutSec: 60);
  if (!ok) return false;
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({'#REFRESH': false, '#CURRENT_ROUTE': home}),
    ),
  );
  final List<Widget> newElementList = reloadPage(home);
  rootThis.setState(() {
    rootThis.pageName = home;
    rootThis.pageElements = newElementList;
    rootThis.wait = false;
    rootThis.touch = !rootThis.touch;
  });
  return true;
}

Future<void> readSettingsContext(
  BuildContext context,
  String lifKey,
  int opt,
) async {
  // opt 1 = Load as usual from JSON etc; 2 = load from JSON2 only
  // then constructPageElement of the respective screen

  var myState = transactionStore.state.screenTx;
  var aRes = myState['#SETTINGS'];
  var res = json.decode(aRes[0]['body']);

  // if (devMode) {
  //   systemJsonRange = _res['devSystemRange'];
  //   screenJsonRange = _res['devScreenRange'];
  // } else {
  systemJsonRange = res['systemRange'];
  screenJsonRange = res['screenRange'];
  if (opt == 2) {
    screenJsonRange = res['screenRange2'];
  }
  // }
  settingKey = lifKey;
  // showAlert(context, "Test1");
  // transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
  //     {'#INTERFACE_KEY': userKey}))); // set state #INTERFACE_KEY
  userKey = settingKey;
  String tempVidKey = res['vidKey'];
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({'#VID_KEY': tempVidKey, '#INTERFACE_KEY': userKey}),
    ),
  );

  http.Response? response;
  try {
    FunctionBody functionBody;
    if (opt == 1) {
      functionBody = getFunctionBody(settingKey, [
        systemJsonRange,
        screenJsonRange,
        lifSetting,
      ]);
    } else {
      //opt == 2
      functionBody = getFunctionBody(settingKey, [screenJsonRange]);
    }
    response = await http.post(
      Uri.parse(functionBody.url),
      body: functionBody.body,
    );
    print('data response: $response');
    print('data response: ${functionBody.body}');
    print('data response: ${functionBody.url}');
  } catch (e) {
    errorReport(e);
    showAlert(
      context,
      textList["ErrorLoading"] + " [readSettingsContext] : $e",
    );
  }
  if (response != null) {
    // The settings/pages payload is always a JSON array/object. A gateway or
    // proxy hiccup returns a plain-text body instead (e.g. "upstream request
    // timeout"); jsonDecode would throw FormatException, which pops a raw
    // exception alert on a routine refresh AND logs a Crashlytics non-fatal.
    // Detect the non-JSON body up front and keep the cached UI — the refresh
    // chain (.then in main_page) still completes cleanly on cache.
    final String rsBody = response.body.trimLeft();
    if (rsBody.isEmpty || (rsBody[0] != '[' && rsBody[0] != '{')) {
      devPrint(
        'readSettingsContext: non-JSON body, keep cache: ${response.body}',
      );
      return;
    }
    var getResult = [];
    try {
      getResult = jsonDecode(response.body);
      if (opt == 1) {
        // systemUIComponent.clear();
        for (
          var i = 0;
          i < getResult[0].length &&
              getResult[0][i].length > 0 &&
              getResult[0][i][0].length > 0;
          i++
        ) {
          var combination = combineJson(getResult[0][i]);
          systemUIComponent[getResult[0][i][0]] = json.decode(combination);
        }
        buildTheme(systemUIComponent[theme]);
        screenUIComponent['_Legal'] = json.decode(legalPage);
        screenUIComponent['_Invitation'] = json.decode(invitationPage);
        screenUIComponent['_NewPin'] = json.decode(newPinPage);
        getResult[1].forEach((scr) {
          var combination = combineJson(scr);
          try {
            if (scr[0].length > 0) {
              screenUIComponent[scr[0]] = json.decode(combination);
            }
          } catch (e) {
            errorReport(e);
            showAlert(
              context,
              textList["ErrorLoading"] + " : $e : scr[0] = ${scr[0]}",
            );
            screenUIComponent[scr[0]] = json.decode(errorPage);
          }
        });

        if (settingKey == myState['#GUEST_LIF']) {
          // sign in process
          int index = myState['#GUEST_INDEX'] - 1;
          if (needUpgrade == empty) {
            screenUIComponent[home] = screenUIComponent[getResult[1][index][0]];
          } else {
            screenUIComponent[home] =
                screenUIComponent[myState['#GUEST_UPGRADE_INDEX']]; // row 59
          }
        } else if (needUpgrade != empty) {
          screenUIComponent[home] = screenUIComponent[needUpgrade];
        }
        // Settings!B1:B5 -> [vid, name, email, phone, type]. Read every cell
        // through settingCell(): a blank cell arrives as `[]` and trailing
        // blanks are dropped, so direct [n][0] indexing threw RangeError and
        // aborted the whole settings block mid-way on every refresh.
        final String currentVid = settingCell(getResult[2], 0);
        if (currentVid.isNotEmpty) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#VID': currentVid})),
          );
          // firestoreIO = '$firestoreCollection/$currentVid/io';
          // firestoreMsg = firestoreIO;
          //  firestoreMsg = 'users/922250226073/io/vid1111/msg';
          final String sName = settingCell(getResult[2], 1);
          if (sName.isNotEmpty) {
            transactionStore.dispatch(
              UpdateScreenTxAction(ScreenTransaction({'#NAME': sName})),
            );
          }
          final String sEmail = settingCell(getResult[2], 2);
          if (sEmail.isNotEmpty) {
            transactionStore.dispatch(
              UpdateScreenTxAction(ScreenTransaction({'#EMAIL': sEmail})),
            );
          }
          final String sPhone = settingCell(getResult[2], 3);
          if (sPhone.isNotEmpty) {
            transactionStore.dispatch(
              UpdateScreenTxAction(ScreenTransaction({'#PHONE': sPhone})),
            );
          }
          final String sType = settingCell(getResult[2], 4);
          if (sType.isNotEmpty) {
            transactionStore.dispatch(
              UpdateScreenTxAction(ScreenTransaction({'#TYPE': sType})),
            );
          }
        }
        constructAllPageElements();
      } else {
        // opt == 2
        getResult[0].forEach((scr) {
          var combination = combineJson(scr);
          if (combination.trim().length > 1) {
            // devPrint('JSON2 : ${scr[0]}');
            try {
              screenUIComponent[scr[0]] = json.decode(combination);
              constructPageElements(scr[0]);
            } catch (_) {
              errorReport(e);
              showAlert(context, textList["ErrorLoading"] + " : $e");
              screenUIComponent[scr[0]] = json.decode(errorPage);
            }
          }
        });
      }
      // save array tp persistence data

      try {
        var saveLast = <Future>[];
        saveLast.add(
          prefs.setString('@systemUI', json.encode(systemUIComponent)),
        );
        saveLast.add(
          prefs.setString('@screenUI', json.encode(screenUIComponent)),
        );
        // Persist authed system snapshot (same gate as readSettings).
        if (settingKey != myState['#GUEST_LIF']) {
          saveLast.add(
            prefs.setString('@authedSystemUI', json.encode(systemUIComponent)),
          );
        }
        await Future.wait(saveLast);
      } catch (e) {
        errorReport(e);
        showAlert(context, textList["ErrorLoading"] + " : $e");
        // devPrint ("Error in saving to shared preferences (readSettings): $e");
      }
    } catch (ep) {
      errorReport(ep);
      showAlert(context, textList["ErrorLoading"] + " : $ep");
    }
  } // end if (response != null)
} // end of readSettingsContext

void showAlert(BuildContext context, String msg) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        //   else (pin not match)
        title: const Text("Alert"),
        content: Text(msg), // show dialog
        actions: <Widget>[
          TextButton(
            child: const Text("OK"),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
} // end of ShowAlert

/// Read cell [n] of a one-column Sheets value range (e.g. `Settings!B1:B5`,
/// which maps to `[vid, name, email, phone, type]`).
///
/// The Sheets API returns `[]` for a blank cell and omits trailing blank rows
/// entirely, so the direct `rows[n][0]` this replaces threw
/// `RangeError (length): ... Valid value range is empty: 0` whenever a tenant
/// left one of those settings empty — fatal on the login path, a swallowed
/// non-fatal that aborts the rest of the settings block on refresh.
/// Returns '' for a missing row, a blank row, or a null cell.
String settingCell(dynamic rows, int n) {
  if (rows is! List || n < 0 || n >= rows.length) return '';
  final row = rows[n];
  if (row is! List || row.isEmpty) return '';
  return row[0]?.toString() ?? '';
}

String combineJson(var j) {
  return '${j.length > 1 ? j[1].replaceAll('%26', '&') : ""}${j.length > 2 ? j[2].replaceAll('%26', '&') : ""}${j.length > 3 ? j[3].replaceAll('%26', '&') : ""}';
}

Future getServiceAccountCredential() async {
  var scopes = [
    //    'https://www.googleapis.com/auth/drive',
    //    'https://www.googleapis.com/auth/drive.appdata',
    'https://www.googleapis.com/auth/spreadsheets',
  ];
  var client = http.Client();
  return auth.obtainAccessCredentialsViaServiceAccount(
    auth.ServiceAccountCredentials.fromJson(
      await rootBundle.loadStructuredData("start.sct", (jsonStr) async {
        return json.decode(jsonStr);
      }),
    ),
    scopes,
    client,
  );
}

String getSettingKey() {
  int idx = 4;
  String rKey =
      vSetting[idx].substring(0, 14) +
      vSetting[idx].substring(17, vSetting[idx].length);
  return rKey;
}

Future getSetting() {
  dynamic result;
  var qParams = {"app": appsCode};
  var uri = Uri.https(
    "us-central1-collanium1-4babc.cloudfunctions.net",
    "/getPoxSettings",
    qParams,
  );
  // devPrint("api.getSetting; ${uri.toString()}");
  return http.post(uri).then((res) {
    result = json.decode(res.body);
    return result;
  });
}

class GoogleHttpClient extends IOClient {
  // from https://stackoverflow.com/questions/48477625/how-to-use-google-api-in-flutter/48485898#48485898
  final Map<String, String> _headers;

  GoogleHttpClient(this._headers) : super();

  @override
  //Future<http.StreamedResponse> send(http.BaseRequest request) =>
  Future<IOStreamedResponse> send(http.BaseRequest request) =>
      super.send(request..headers.addAll(_headers));

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      super.head(url, headers: headers!..addAll(_headers));
}

Future<void> handleSignIn() async {
  try {
    // await vGoogleSignIn.signIn();
    await vGoogleSignIn.authenticate();
  } catch (error) {
    errorReport(error);
  }
}

Future<String> appendToSheetOld(dynamic val) async {
  var state = transactionStore.state.screenTx;
  try {
    FunctionBody functionBody = appendSSA1(state['#INTERFACE_KEY'], [
      val,
    ], defaultCluster);
    await http
        .post(Uri.parse(functionBody.url), body: functionBody.body)
        .timeout(const Duration(seconds: 10));

    TimerBloc timerBloc = state['#TIMER_BLOC'];
    // Guard (see appendToSheet): skip the timer when #TIMER_DURATION is absent
    // rather than crash on Start(null). Same null-only-safe fix.
    final dynamic timerDuration = state['#TIMER_DURATION'];
    if (timerDuration is int) {
      timerBloc.add(Start(duration: timerDuration));
    }
  } catch (e) {
    errorReport(e);
  }
  setDataOK('1');
  return 'End of appendToSheet';
} // end of appendToSheet

Future runSheetStartup(String lif, String clt) async {
  // Per-LIF, so per-LOGIN — not per-process. signOut wipes the geofence list
  // (`'#LQR_LIST': {}`, api.dart:3140), and while this call sat inside the
  // appStartupRun guard a logout->login within the same process never refetched
  // it: #LQR_LIST stayed empty, LocationDetector._deriveGpsStatus fell through
  // to 'last_known' ("Unknown"), and attendance stopped working until a force
  // close reset the flag. The block below is genuinely process-scoped
  // (timezone, screen size, OS info) and stays one-shot.
  //
  // Fire-and-forget and cache-backed, so this costs the login nothing.
  getLqrList(lif);
  if (!appStartupRun) {
    debugPrint('start runSheetStartup');
    Duration nw = DateTime.now().timeZoneOffset;
    String tz = (nw.inMinutes / 60).toString();
    // dynamic physicalScreenSize = window.physicalSize;
    dynamic physicalScreenSize =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    dynamic physicalWidth = physicalScreenSize.width;
    dynamic physicalHeight = physicalScreenSize.height;
    // final List<Locale> systemLocales = window.locales;
    final List<Locale> systemLocales =
        WidgetsBinding.instance.platformDispatcher.locales;
    String lang = systemLocales[0].toString();
    String country = '';
    dynamic osInfo = await getOsInfo();
    String? info = getInfo(osInfo);

    String startupUrl =
        "https://$autsorzFunctionDomain${functionName['runStartup']}";
    var bodyElement = {
      "ssid": lif,
      "clt": clt,
      "ver": version + subVersion,
      "tz": tz,
      "wd": physicalWidth.round().toString(),
      "hg": physicalHeight.round().toString(),
      "lc": lang,
      "cc": country,
      "dvc": info,
    };

    try {
      if (internetConnected()) {
        callHttpPost(Uri.parse(startupUrl), bodyElement);
        debugPrint('call ${functionName['runStartup']} function');
        appStartupRun = true;
      }
    } catch (e) {
      devPrint(e);
    }
  } // end if (!appStartupRun)
} // end of runSheetStartup

// TODO make getVidData; updateVidData; deleteVidData
Future getVidData() async {
  dynamic ref;
  dynamic messageRef;
  try {
    fsCollection = (await secureRead(key: "myPath"))!;
    String docId = (await secureRead(key: "myDoc"))!;
    // String myMsgId = (await storage.read(key: "myMsgId"))!;
    String myCluster = (await secureRead(key: "myCluster"))!;
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#FS_PATH': fsCollection,
          '#CLUSTER': myCluster,
          '#FS_IO': firestoreIO,
        }),
      ),
    );
    fsMsgCollection =
        "$msgPrefix$myCluster"; //= set singleton for whole project
    var myVid = transactionStore.state.screenTx['#VID'].toString();

    var futures = <Future>[];
    futures.add(
      firestoreDb //= get user data from firestore
          .collection(fsCollection)
          .doc(docId)
          .get(),
    );

    futures.add(getFirestoreMessageRef(myVid));

    //https://alvinalexander.com/dart/how-run-multiple-dart-futures-in-parallel/
    await Future.wait(futures).timeout(const Duration(seconds: 12)).then((
      List<dynamic> res,
    ) {
      ref = res[0];
      messageRef = res[1];
    });
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#FS_DOC': docId,
          '#FS_REF': ref.reference,
          '#MSG_REF': messageRef,
        }),
      ),
    );
  } catch (e) {
    // Swallowing this silently also hid WHY #MSG_REF/#FS_REF stayed null for
    // the rest of the launch (see launchCheck's msgDoc guard).
    devPrint('getVidData failed — #FS_REF/#MSG_REF not dispatched: $e');
    ref = null;
  }
  // ref is null whenever ANYTHING above failed — most commonly the pre-login
  // cold start, where secureRead('myPath')! throws because no user was ever
  // stored. `ref.data()` on that null was the recurring
  // NoSuchMethodError('data' called on null) in every fresh-install log.
  // Callers never consume this return value (launchCheck's `vidData` local is
  // unused); the function's real output is the #FS_* dispatches above.
  return ref?.data();
} // end of getVidData

Future updateVidData(String key, var val) async {
  dynamic res;
  try {
    var state = transactionStore.state.screenTx;
    var myVid = state['#VID'].toString();
    await FirebaseFirestore.instance.collection(fsCollection).doc(myVid).update(
      {key: val},
    ); // put back updated data
  } catch (_) {
    res = null;
  }
  return res;
} // end of getVidData

Future getGPSLoc() async {
  //    Position position = await Geolocator().getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  // var latLang = await Gps.currentGps();
  Position? geoPos;
  // Placemark myPlace;
  // await getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
  // await getLocation()
  //     .then((Position position) async {
  geoPos = await getLocation();
  if (geoPos != null) {
    // List<Placemark> p =
    //     await placemarkFromCoordinates(geoPos.latitude, geoPos.longitude);
    // myPlace = p[0];
  }
  // });
  transactionStore.dispatch(
    // UpdateScreenTxAction(ScreenTransaction({'#LOCATION': latLang})));
    UpdateScreenTxAction(ScreenTransaction({'#LOCATION': geoPos})),
  );
  //devPrint('Latitude:${latLang.lat}, Longitude : ${latLang.lng}');
  return geoPos;
}

Future getMyImei() async {
  var myImei = '-';
  try {
    myImei = await getDeviceId();
  } catch (erImei) {
    errorReport(erImei);
  }
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#DID': myImei})),
  ); //  set #IMEI
  return myImei;
}

Future kickedOut() async {
  await unsubscribeUserReset();
  // Both stay fire-and-forget — tearing down the local session must not block
  // on a provider round-trip — but an un-awaited rejection is recorded as a
  // FATAL crash (main.dart:90). GoogleSignIn.signOut() in particular throws
  // `clearCredentialState no provider dependencies found` on devices with no
  // Android credential provider, which killed the app on every forced logout.
  safeUnawaited(FirebaseAuth.instance.signOut(), 'kickedOut FirebaseAuth');
  safeUnawaited(GoogleSignIn.instance.signOut(), 'kickedOut GoogleSignIn');
  // GoogleSignIn().signOut();
  // signInOption: SignInOption.standard,
  // scopes: [],
  // ).signOut();
  await signOut();
} // end of kickedOut

Future signOut() async {
  // reset uid, imei, in = false, fcm
  const functionName = 'signOut';
  var state = transactionStore.state.screenTx;
  // var cUser = state['#FIREBASE_USER']; // get current firebase user data
  var updateData = <String, dynamic>{};
  var myDocRef = state['#FS_REF'];
  // String myFirebaseUid = cUser.uid;
  updateData["in"] = false;
  //updateData["fcm"] = "";
  updateData["ph1"] = "";
  try {
    // #FS_REF can be null on a warm-reopened session; this firestore
    // housekeeping (in=false) is non-critical and must NEVER abort the logout
    // UI reset below — otherwise the shell stays on the (nav-less) home page.
    try {
      if (myDocRef != null) safeFsUpdate(myDocRef, updateData, 'signOut');
    } catch (e) {
      devPrint('signOut firestore update skipped: $e');
    }
    var pgName = routeStack.popAll();
    dynamic signUpKey;
    if (demoApp) {
      signUpKey = state['#DEMO_SIGNUP_KEY'];
    } else {
      signUpKey = state['#SIGNUP_KEY'];
    }
    storage.write(key: 'myLif', value: signUpKey);
    storage.write(key: 'myMsgId', value: null);
    storage.write(key: 'lqrList', value: null); // delete location qr list
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({'#INTERFACE_KEY': signUpKey, '#LQR_LIST': {}}),
      ),
    ); // set state #INTERFACE_KEY
    await historyLock(functionName);
    tableContent[historyName].clear();
    await storage.write(key: historyName, value: 'null');
    historyUnLock(functionName);
    await imageMapClear();
    await storage.write(key: imageMapSecureName, value: 'null');
    // devPrint("After in = false; try to signOut from firebaseAuth");
    if (!demoApp) {
      //        FirebaseAuth.instance.signOut(); // signOut from firebase
      // TODO signOut from google, facebook, twitter
    }
    unSubscribeToEvent(); // unsubscribe to proxy event listener
    await Future.wait([
      prefs.remove('@systemUI'),
      prefs.remove('@screenUI'),
      prefs.remove('@lastGpsTime'),
    ]);
    // Switch the shell back to the sign-in page. This MUST run or the body
    // keeps rendering the stale (now nav-less) home pageElements. Reset on BOTH
    // success and failure of the page re-fetch so a slow/failed network — or a
    // readSettings timeout — can never strand the user on home.
    void showSignInPage() {
      try {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})),
        );
        List<Widget> newElementList = reloadPage(pgName);
        rootThis.setState(() {
          // Clearing the cold-path logout spinner here means it lifts on BOTH
          // the success and failure branches that call showSignInPage(). On the
          // warm path the flag is already false, so this is a harmless no-op.
          MainPageState.logoutInProgress = false;
          rootThis.pageName = pgName;
          rootThis.pageElements = newElementList;
        });
      } catch (e) {
        devPrint('signOut showSignInPage failed: $e');
        // setState above may have thrown before clearing the flag — clear it
        // directly so the spinner can never get stuck on screen.
        MainPageState.logoutInProgress = false;
      }
      setDataOK('2');
    }

    // Attempt an instant restore from the guest UI snapshotted at bootstrap.
    // shouldRestoreGuestSnapshot() (the same pure helper unit-tested in
    // test/logout_transition_test.dart) returns true only when BOTH snapshots
    // exist, are non-empty, and JSON-decode to a Map.
    final String? guestScreen = prefs.getString('@guestScreenUI');
    final String? guestSystem = prefs.getString('@guestSystemUI');

    if (shouldRestoreGuestSnapshot(guestScreen, guestSystem)) {
      // Warm cache: restore the guest UI and show the login page NOW — no
      // network, no spinner. The globals are dynamic, so reassigning them with
      // the decoded snapshot is valid (no .clear() needed).
      try {
        systemUIComponent = json.decode(guestSystem!);
        screenUIComponent = json.decode(guestScreen!);
        buildTheme(systemUIComponent[theme]);
        constructAllPageElements();
        showSignInPage();
      } catch (e) {
        devPrint(
          'signOut guest snapshot restore failed: $e — falling back to network',
        );
        // Snapshot decoded by the gate but failed to rebuild the UI: fall into
        // the cold/corrupt path (spinner + network re-fetch) below.
        rootThis.setState(() {
          MainPageState.logoutInProgress = true;
        });
        readSettings(signUpKey, 1).then((_) => showSignInPage()).catchError((
          e,
        ) {
          devPrint('signOut readSettings failed: $e');
          showSignInPage();
        });
        return; // do not also run the background refresh below
      }
      // Background refresh: reconcile any server-side guest-page changes since
      // the snapshot was taken. Fire-and-forget — the login page is already
      // visible from the snapshot (showSignInPage ran above), so the @screenUI/
      // @systemUI cache refresh ALWAYS runs, but the *visual* rebuild is gated:
      // only re-render when the refreshed pages actually DIFFER from the
      // snapshot already on screen. Re-encoding the two maps and comparing them
      // byte-for-byte against the rendered snapshot strings (guestScreen/
      // guestSystem) avoids the double-render flicker when the server returned
      // identical guest pages (the common case).
      readSettings(signUpKey, 1)
          .then((_) {
            // Guard: if the user has already re-logged-in (the #INTERFACE_KEY has
            // changed away from signUpKey), this background refresh is stale —
            // skip the reconcile to avoid overwriting authed data / re-rendering
            // the sign-in page over the just-loaded authed shell.
            final currentKey =
                transactionStore.state.screenTx['#INTERFACE_KEY'];
            if (currentKey != null && currentKey != signUpKey) {
              devPrint('signOut background refresh skipped: user re-logged-in');
              return;
            }
            try {
              final String refreshedScreen = json.encode(screenUIComponent);
              final String refreshedSystem = json.encode(systemUIComponent);
              final bool screenChanged = refreshedScreen != guestScreen;
              final bool systemChanged = refreshedSystem != guestSystem;
              if (!screenChanged && !systemChanged) {
                // Identical to what's already rendered — skip reloadPage+setState
                // entirely (no flicker). The cache is still refreshed by the fetch.
                return;
              }
              // Server-side drift (plan R5): reconcile. Re-run buildTheme BEFORE the
              // rebuild only when the system/theme map changed, so a server theme
              // tweak takes effect; then rebuild via the showSignInPage() closure.
              if (systemChanged) {
                buildTheme(systemUIComponent[theme]);
              }
              showSignInPage();
            } catch (e) {
              devPrint('signOut background refresh reconcile failed: $e');
              // Reconcile failed mid-flight — fall back to a plain rebuild so the
              // refreshed pages still take effect rather than stranding on stale.
              showSignInPage();
            }
          })
          .catchError((e) {
            devPrint('signOut background readSettings failed: $e');
            // A failed refresh must not strand the shell (iOS dual-call invariant);
            // the snapshot is already up, but re-run showSignInPage() defensively.
            showSignInPage();
          });
    } else {
      // Cold/corrupt cache: no usable guest snapshot. Show a "logging out…"
      // spinner overlay (scoped MainPageState.logoutInProgress flag) while the
      // login page is re-fetched over the network, then swap to it on BOTH
      // success and failure (showSignInPage clears the spinner in either case).
      rootThis.setState(() {
        MainPageState.logoutInProgress = true;
      });
      readSettings(signUpKey, 1)
          .then((_) {
            // Same staleness guard as the warm-path background refresh (T8): if the
            // user re-logged-in while this cold-path re-fetch was in flight, do not
            // swap the shell back to the sign-in page over the authed shell.
            final currentKey =
                transactionStore.state.screenTx['#INTERFACE_KEY'];
            if (currentKey != null && currentKey != signUpKey) {
              devPrint('signOut cold-path refresh skipped: user re-logged-in');
              // Spinner must still lift so it can never strand on screen.
              MainPageState.logoutInProgress = false;
              return;
            }
            showSignInPage();
          })
          .catchError((e) {
            devPrint('signOut readSettings failed: $e');
            showSignInPage();
          });
    }
  } catch (err) {
    // devPrint("Error writing to firestore :" + err.toString());
    // Clear the cold-path logout spinner here too: if setting the flag (or any
    // cleanup after it) threw, showSignInPage may not have run, so guarantee the
    // overlay can never strand on screen.
    MainPageState.logoutInProgress = false;
    await Future.wait([
      prefs.remove('@systemUI'),
      prefs.remove('@screenUI'),
      prefs.remove('@lastGpsTime'),
    ]);
    setDataOK('2');
  }
} // end of signOut

Future<int> userIntegrityCheck() async {
  //= deprecated
  int result = 99;
  Map<String, dynamic> updateData = {};
  try {
    var state = transactionStore.state.screenTx;
    var myVid = state['#VID'].toString();

    // check fcm token & Imei, update when firebase in = true;
    // ask other device to logout first
    var vidData = await getVidData();
    var cUser = state['#FIREBASE_USER'];
    if (cUser == null) {
      // no #FIREBASE_USER. This can happen when user close the app but not signed out
      // This is default state for most user. User is not recommended to log out
      cUser = await getFirebaseUser();
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#FIREBASE_USER':
                cUser, // #FIREBASE_USER should be available afterward
          }),
        ),
      );
    }

    if ((vidData['in'] != null && vidData['in']) &&
        (vidData['uid'] != null && vidData['uid'] != cUser.uid)) {
      result = 101; // other user with different uid logged in
    } else {
      if ((vidData['in'] == null || !vidData['in']) && !demoApp) {
        result = 102; // user not logged in yet
      } else {
        // update Firebase Cloud Messaging token with current token
        if (vidData['fcm'] == null) {
          updateData['fcm'] = state['#FCM_TOKEN'];
        } else {
          if (vidData['fcm'] != state['#FCM_TOKEN']) {
            updateData['fcm'] = state['#FCM_TOKEN'];
          }
        }
        if (vidData['email'] == null) {
          if (cUser.email != null) updateData['email'] = cUser.email;
        } else {
          if (cUser.email != null && vidData['email'] != cUser.email) {
            updateData['email'] = cUser.email;
          }
        }
        safeFsUpdate(
          FirebaseFirestore.instance.collection(fsCollection).doc(myVid),
          updateData,
          'userIntegrityCheck',
        ); // write updated data to firestore

        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#EMAIL': cUser.email})),
        );

        try {
          secureRead(key: 'pinHash')
              .then((myPinHash) {
                // TODO check pin hash integrity with lif
                if (myPinHash == null) {
                  sheetApi.spreadsheets.values
                      .batchGet(
                        settingKey, // read from Link Interface
                        ranges: ['Settings!G10'],
                        dateTimeRenderOption: "SERIAL_NUMBER",
                        valueRenderOption: "UNFORMATTED_VALUE",
                      )
                      .then((entryList) {
                        if (entryList.valueRanges![0].values == null) {
                          transactionStore.dispatch(
                            UpdateScreenTxAction(
                              ScreenTransaction({'#NEED_PINHASH': true}),
                            ),
                          );
                        } else {
                          var lifHash = entryList.valueRanges![0].values![0][0];
                          storage.write(
                            key: 'pinHash',
                            value: lifHash.toString(),
                          ); // store pinHash in secure & persistent storage
                          transactionStore.dispatch(
                            UpdateScreenTxAction(
                              ScreenTransaction({'#NEED_PINHASH': false}),
                            ),
                          );
                        }
                      });
                } else {
                  transactionStore.dispatch(
                    UpdateScreenTxAction(
                      ScreenTransaction({'#NEED_PINHASH': false}),
                    ),
                  );
                }
              })
              .catchError((_) {
                sheetApi.spreadsheets.values
                    .batchGet(
                      settingKey, // read from Link Interface
                      ranges: ['Settings!G10'],
                      dateTimeRenderOption: "SERIAL_NUMBER",
                      valueRenderOption: "UNFORMATTED_VALUE",
                    )
                    .then((entryList) {
                      var lifHash = entryList.valueRanges![0].values![0][0];
                      if (lifHash == null) {
                        transactionStore.dispatch(
                          UpdateScreenTxAction(
                            ScreenTransaction({'#NEED_PINHASH': true}),
                          ),
                        );
                      } else {
                        storage.write(
                          key: 'pinHash',
                          value: lifHash.toString(),
                        ); // store pinHash in secure & persistent storage
                        transactionStore.dispatch(
                          UpdateScreenTxAction(
                            ScreenTransaction({'#NEED_PINHASH': false}),
                          ),
                        );
                      }
                    });
              });
        } catch (erLif) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#NEED_PINHASH': true})),
          );
        }
        result = 0;
      }
    }
  } catch (e) {
    result = 99; // general error in integrity check
    errorReport(e);
  }
  return result;
} // end of userIntegrityCheck

Future getLifProfileData(String lifKey) async {
  Map<String, dynamic> profileData = {};
  // `lifSetting2` (Settings!G1:G14) is NOT requested any more. Measured
  // 2026-08-03 against the live workbook, that range comes back as fourteen
  // empty strings:
  //   [[""],[""],[""],[""],[""],[""],[""],[""],[""],[""],[""],[""],[""],[""]]
  // It fed imei / pinHash / cipherText / publicKey / address, and the only
  // callers (reLogin, reLoginDemo) dispatched pinHash/cipherText/publicKey
  // into #PINHASH / #CIPHERTEXT / #PUBLICKEY — keys with ZERO readers
  // anywhere in lib/. So the whole second half of this request was buying
  // empty strings for keys nobody reads, on the slowest call in the app.
  // Re-add it only when Settings!G actually holds something AND something
  // reads it.
  FunctionBody functionBody = getFunctionBody(lifKey, [lifSetting]);
  // ★ readSS latency is NOT controllable from here. Measured 2026-08-03,
  // 13 samples against the same workbook, varying payload shape deliberately:
  //   3.8 4.0 4.7 4.7 4.9 15.9 18.7 34.6 38.7 40.2 54.1 60.2 79.0  (seconds)
  // median 18.7s, ~46% over 20s, tail 79s. Byte-identical requests came back
  // 79.0s and 4.9s back-to-back, and a 2-range request beat a 1-range one, so
  // neither payload size nor range count predicts anything.
  //
  // Consequences, both learned the hard way here:
  //  - ONE long budget is bad: it buys a single draw and waits out the loss.
  //  - Short retries are ALSO not sufficient: 3 x 20s all timed out on device,
  //    because slow responses arrive in bursts rather than independently.
  // So the retry below is a best-effort speedup ONLY. It is NOT what makes
  // login reliable — the caller's fallback is (see reLogin in
  // user_repository.dart). Do not "fix" login by growing these numbers again.
  http.Response? response;
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      response = await http
          .post(Uri.parse(functionBody.url), body: functionBody.body)
          .timeout(const Duration(seconds: 20));
      break;
    } on TimeoutException {
      devPrint(
        '[LOGINPERF] getLifProfileData attempt $attempt timed out (20s)',
      );
      // Only timeouts are retried. A network/DNS error still throws straight
      // out — retrying those just delays the same failure.
      if (attempt == 3) rethrow;
    }
  }
  var getResult = jsonDecode(response!.body);
  profileData['vid'] = getResult[0][0][0];
  return profileData;
}

Future<int> launchCheck() async {
  // TODO finish justLaunch procedure
  // Launch with logged in status. Always run at launch like good old autoexec.bat
  // firstLogin, reLogin, run this function

  int result = 99; // return > 0 when something wrong
  dynamic state;
  Map<String, dynamic> updateData = {};
  final swLC = _loginPerfTrace ? (Stopwatch()..start()) : null;
  try {
    // Pre-login cold start: readSettingsStart calls this unconditionally, but
    // with no stored user every step below is meaningless — getVidData has no
    // myPath/myDoc, and the pinHash block would fire a 15s readSS for nobody
    // while the user is trying to sign in. Skip outright; the same work runs
    // from reLogin right after login, and on every warm start once a user
    // exists. setUpFirebase is not lost either: asyncAppStartup2 calls it
    // separately on every app start.
    if (await secureRead(key: 'myDoc') == null) {
      devPrint('[LOGINPERF] launchCheck skipped: no stored user (pre-login)');
      return result;
    }
    // historyLoadFromSecureStorage();
    final sw1 = _loginPerfTrace ? (Stopwatch()..start()) : null;
    await FirebaseNotifications()
        .setUpFirebase(); // setup fcm notification for app
    if (sw1 != null) {
      debugPrint(
        '[LOGINPERF] launchCheck.setUpFirebase = ${sw1.elapsedMilliseconds}ms',
      );
    }
    result = 991;
    //-- user integrity check
    state = transactionStore.state.screenTx;
    // subscribeToProxy(state['#INTERFACE_KEY']); // subscribe to firebase proxy
    final sw2 = _loginPerfTrace ? (Stopwatch()..start()) : null;
    var vidData = await getVidData(); // get vid data plus uid
    if (sw2 != null) {
      debugPrint(
        '[LOGINPERF] launchCheck.getVidData = ${sw2.elapsedMilliseconds}ms',
      );
    }
    var cUser = state['#FIREBASE_USER'];
    if (cUser == null) {
      // no #FIREBASE_USER. This can happen when user close the app but not signed out
      // This is default state for most user. User is not recommended to log out
      cUser = await getFirebaseUser();
      result = 992;
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#FIREBASE_USER':
                cUser, // #FIREBASE_USER should be available afterward
          }),
        ),
      );
    }
    final sw3 = _loginPerfTrace ? (Stopwatch()..start()) : null;
    try {
      await secureRead(key: 'pinHash')
          .then((myPinHash) async {
            // Checking pinhash with Lif. Pinhash in Lif is the main data.
            result = 993;
            if (myPinHash == null || myPinHash == "") {
              updateData["ph1"] = empty;
              result = 994;
              FunctionBody functionBody = getFunctionBody(settingKey, [
                'Settings!G10',
              ]);
              result = 995;
              final swHTTP = _loginPerfTrace ? (Stopwatch()..start()) : null;
              var response = await http
                  .post(Uri.parse(functionBody.url), body: functionBody.body)
                  .timeout(const Duration(seconds: 15));
              if (swHTTP != null) {
                debugPrint(
                  '[LOGINPERF] launchCheck.pinHashHTTP = ${swHTTP.elapsedMilliseconds}ms',
                );
              }
              result = 996;
              var entryList = jsonDecode(response.body);
              result = 997;
              if (entryList[0][0][0] == null) {
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({'#NEED_PINHASH': true}),
                  ),
                );
                result = 998;
              } else {
                var lifHash = entryList[0][0][0];
                storage.write(
                  key: 'pinHash',
                  value: lifHash,
                ); // store pinHash in secure & persistent storage
                updateData["ph1"] = lifHash;
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({'#NEED_PINHASH': false}),
                  ),
                );
                result = 999;
              }
              //          });
            } else {
              result = 9910;
              updateData["ph1"] = myPinHash;
              FunctionBody functionBody = getFunctionBody(settingKey, [
                'Settings!G10',
              ]);
              result = 9911;
              final swHTTP = _loginPerfTrace ? (Stopwatch()..start()) : null;
              var response = await http
                  .post(Uri.parse(functionBody.url), body: functionBody.body)
                  .timeout(const Duration(seconds: 15));
              if (swHTTP != null) {
                debugPrint(
                  '[LOGINPERF] launchCheck.pinHashHTTP = ${swHTTP.elapsedMilliseconds}ms',
                );
              }
              result = 9912;
              var entryList = jsonDecode(response.body);
              result = 9913;
              //          await sheetApi.spreadsheets.values
              //              .batchGet(settingKey, // read from Link Interface
              //                  ranges: ['Settings!G10'],
              //                  dateTimeRenderOption: "SERIAL_NUMBER",
              //                  valueRenderOption: "UNFORMATTED_VALUE")
              //              .then((entryList) {
              if (entryList[0][0][0] == null) {
                storage.write(
                  key: 'pinHash',
                  value: '--',
                ); //= delete storage.pinhash if pinhash in lif = null
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({'#NEED_PINHASH': true}),
                  ),
                );
                result = 9914;
              } else {
                result = 9915;
                var lifHash = entryList[0][0][0];
                storage.write(
                  key: 'pinHash',
                  value: lifHash,
                ); // store pinHash in secure & persistent storage
                updateData["ph1"] = lifHash;
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({'#NEED_PINHASH': false}),
                  ),
                );
                result = 9916;
              }
              //          }); // end of sheetApi
            }
          })
          .catchError((er) async {
            if (_loginPerfTrace) {
              debugPrint(
                '[LOGINPERF] launchCheck.pinHashHTTP CAUGHT ERROR, entering retry: $er',
              );
            }
            result = 9917;
            //  retry read pinhash in LIF
            FunctionBody functionBody = getFunctionBody(settingKey, [
              'Settings!G10',
            ]);
            result = 9918;
            final swRetry = _loginPerfTrace ? (Stopwatch()..start()) : null;
            var response = await http
                .post(Uri.parse(functionBody.url), body: functionBody.body)
                .timeout(const Duration(seconds: 15));
            if (swRetry != null) {
              debugPrint(
                '[LOGINPERF] launchCheck.pinHashRetry = ${swRetry.elapsedMilliseconds}ms',
              );
            }
            result = 9919;
            var entryList = jsonDecode(response.body);
            result = 9920;
            if (entryList[0][0][0] == null) {
              storage.write(
                key: 'pinHash',
                value: '--',
              ); //= delete storage.pinhash if pinhash in lif = null
              transactionStore.dispatch(
                UpdateScreenTxAction(
                  ScreenTransaction({'#NEED_PINHASH': true}),
                ),
              );
              result = 9921;
            } else {
              result = 9922;
              var lifHash = entryList[0][0][0];
              storage.write(
                key: 'pinHash',
                value: lifHash,
              ); // store pinHash in secure & persistent storage
              updateData["ph1"] = lifHash;
              transactionStore.dispatch(
                UpdateScreenTxAction(
                  ScreenTransaction({'#NEED_PINHASH': false}),
                ),
              );
              result = 9923;
            }
          });
    } catch (erLif) {
      result = 9924;
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#NEED_PINHASH': true})),
      );
    }
    if (sw3 != null) {
      debugPrint(
        '[LOGINPERF] launchCheck.pinHashBlock = ${sw3.elapsedMilliseconds}ms',
      );
    }
    // end of integrity check

    state = transactionStore.state.screenTx;
    String? myDid = state['#DID'];
    result = 9925;
    if (myDid == null) {
      //= if deviceId is not read
      myDid = await getDeviceId(); //= get deviceID
      result = 9926;
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#DID': myDid})),
      );
    }
    updateData["did"] = myDid;
    updateData["in"] = true;
    updateData["pk1"] = state['publicKey'];
    var docRef = state['#FS_REF']; //= get user doc reference for firestore
    result = 9927;
    safeFsUpdate(
      docRef,
      updateData,
      'loginUpdate',
    ); //= write updated data to user dpc
    result = 9928;
    docRef = state['#MSG_REF']; //= get message doc reference for firestore
    // getVidData() dispatches #MSG_REF ONLY when its Future.wait(...) 12s block
    // succeeds; on a pre-login cold start / timeout / offline it throws, its
    // catch sets ref = null and dispatches NOTHING, so #MSG_REF is still null
    // here. tx.get(null) then throws "type 'Null' is not a subtype of type
    // 'DocumentReference<Map<String, dynamic>>'" from inside the transaction
    // callback. Skip the write — the next launchCheck retries it. (The #FS_REF
    // update above survives the same hole only because safeFsUpdate guards the
    // cast itself.)
    if (docRef is! DocumentReference) {
      devPrint('launchCheck: #MSG_REF not ready — msgDoc transaction skipped');
    } else {
      // A transaction NEVER works offline — unlike the plain update above it
      // cannot be queued by Firestore persistence, it needs a server round-trip.
      // Un-awaited and unguarded, its rejection ([cloud_firestore/unavailable]
      // "Unable to resolve host") escaped the surrounding (synchronous) try to
      // platformDispatcher.onError and was recorded as a FATAL. Awaiting instead
      // would block login on that round-trip, so keep it fire-and-forget and
      // guard it. The write is retried by the next launchCheck.
      safeUnawaited(
        FirebaseFirestore.instance.runTransaction((Transaction tx) async {
          result = 9929;
          var msgSnapshot = await tx.get<Map<String, dynamic>>(docRef);
          Map<String, dynamic> updateMsg = {};
          result = 9930;
          // Only write a real token. This ran unguarded, so any start that reached
          // here before setUpFirebase had dispatched #FCM_TOKEN (getToken() null,
          // or the static _isSetUp guard short-circuiting a later call in a process
          // where the dispatch never happened) wrote `f: null` and WIPED the stored
          // token -- after which the sender has no target and nobody gets a push.
          final fcmToken = state['#FCM_TOKEN'];
          if (fcmToken != null && fcmToken.toString().isNotEmpty) {
            updateMsg["f"] = fcmToken;
          }
          result = 9931;
          if (msgSnapshot.exists) {
            result = 9932;
            if (msgSnapshot.data()!["n"] == null) {
              updateMsg["n"] = cUser.displayName ?? '';
              result = 9933;
            }
            if (msgSnapshot.data()!["p"] == null) {
              updateMsg["p"] = cUser.photoURL ?? '';
              result = 9934;
            }
            //await tx.update(docRef, updateMsg);
          }
          result = 9935;
          // updateMsg can now be empty (no token yet, nothing else to backfill);
          // skip the write rather than issue a pointless transaction update.
          if (updateMsg.isNotEmpty) tx.update(docRef, updateMsg);
          result = 9936;
        }),
        'launchCheck msgDoc',
      ); // end of firebase transaction
    }
    //    docRef.updateData(updateData); //= write updated data to message doc
    // write user qr seed to secure storage
    final sw4 = _loginPerfTrace ? (Stopwatch()..start()) : null;
    bool secureWrite = true;
    try {
      String? sd1 = await secureRead(key: 'sd1');
      if (sd1 != null) {
        secureWrite = false;
      } // end if (sd2 != null)
    } catch (e) {
      secureWrite = true;
    } // end try
    if (secureWrite) {
      await storage.write(
        key: 'sd1',
        value: ftzSecretOneSeed,
      ); //   put Account key in secure storage
    } // end if (write)
    secureWrite = true;
    try {
      String? sd2 = await secureRead(key: 'sd2');
      if (sd2 != null) {
        secureWrite = false;
      } // end if (sd2 != null)
    } catch (e) {
      secureWrite = true;
    } // end try
    if (secureWrite) {
      await storage.write(
        key: 'sd2',
        value: ftzSecretOneSeed2R,
      ); //   put Account key in secure storage
    } // end if (write)
    if (sw4 != null) {
      debugPrint(
        '[LOGINPERF] launchCheck.secureWriteBlock = ${sw4.elapsedMilliseconds}ms',
      );
    }
    result = 0;
    apiTest();
  } catch (e) {
    errorReport(e);
  }
  if (swLC != null) {
    debugPrint('[LOGINPERF] launchCheck.total = ${swLC.elapsedMilliseconds}ms');
  }
  if (result == 0) {
    storage.write(key: 'lastVersion', value: '$version$subVersion');
  }
  return result;
} // end of launchCheck

Future apiInit1() async {
  // async api init
  try {
    //var uptime = await Uptime.uptime;
    //bool _init = await TrueTime.init(ntpServer: 'pool.ntp.org');
  } catch (e) {
    errorReport(e);
  }
  return true;
}

String autheniumDecrypt(String cipherText) {
  // TODO put decryption algorithm here
  return cipherText;
}

String autheniumEncrypt(String rawText, String encryptionType) {
  // TODO put encryption algorithm here
  return rawText;
}

String getAutheniumKey(String keyType) {
  // TODO put algorithm to get authenium key
  return "11223344";
}

Future getDeviceId() async {
  return await getDeviceIdCore();
} // end of getDeviceId

Future getFirestoreUserData(
  String myUid,
  String myEmail,
  String county,
  String inv,
) async {
  /*
        output :
        is not String = login successful
        is String = login failure, content of output = error message
  */
  dynamic result;
  String myDevice = await getDeviceId();
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#DID': myDevice})),
  );
  Map<String, dynamic> user;
  var invitationStatus = 0; // 0 = init, 1 = found, 901 = not found
  bool needToRegisterInvLogin = false;
  var uidUser = await FirebaseFirestore.instance
      .collection(
        topCollection,
      ) // search data in firebase with corresponding uid
      .where('u', isEqualTo: myUid)
      .get();
  var recFound = uidUser.docs.length;
  final bool matchedByUid = recFound >= 1;
  if (recFound < 1) {
    // Uid not found in firebase
    uidUser = await FirebaseFirestore.instance
        .collection(
          topCollection,
        ) // search data in firebase with corresponding uid
        .where('e', isEqualTo: myEmail)
        .where('u', isEqualTo: 'TBD')
        .get();
    recFound = uidUser.docs.length;
    if (recFound >= 1) {
      // Email and TBD found
      // This is a new login of predefined user. Put uid in u
      var docRef = uidUser.docs[0].reference;
      var data = {"u": myUid};
      await docRef.update(data);
    } else {
      // Email and TBD not found, check invitation
      // var nowTime = DateTime.now().millisecondsSinceEpoch;
      final canon62 = phoneCanonical62(inv);
      final legacy = phoneCleanup(inv);
      final forms = <String>{
        if (canon62.isNotEmpty) canon62,
        if (legacy.isNotEmpty) legacy,
      };
      if (forms.isEmpty) {
        uidUser = await FirebaseFirestore.instance
            .collection(topCollection)
            .where('i', isEqualTo: 'OtonomiqInvitationNotExist...')
            .get();
      } else {
        uidUser = await FirebaseFirestore.instance
            .collection(
              topCollection,
            ) // search data in firebase with invitation
            .where('i', whereIn: forms.toList())
            // .where('e', isEqualTo: "-") // Find invitation that is not used
            // .where('x', isGreaterThan: nowTime)
            .get();
      }
      recFound = uidUser.docs.length;
      if (recFound <= 0) {
        // Not found
        invitationStatus = 3;
      } else if (recFound == 1) {
        // Found 1 Invitation.
        if (uidUser.docChanges[0].doc.data()!["e"] == null ||
            uidUser.docChanges[0].doc.data()!["e"] == "-" ||
            uidUser.docChanges[0].doc.data()!["e"] == "TBD") {
          //  This is new user login with invitation for the first time
          var docRef = uidUser.docs[0].reference;
          var data = {
            // "x": FieldValue.delete(),
            "e": myEmail,
            "u": myUid,
          }; // set as used
          await docRef.update(data);
          needToRegisterInvLogin = true; // put flag to register invLogin
          //TODO call cloud function to register email, etc
          invitationStatus = 1;
        } else {
          recFound = 0;
          invitationStatus =
              7; // Invitation has been used by another user with different email
        }
      } else {
        // Found more than 1,
        // TODO: should ask for country
        if (uidUser.docChanges[0].doc.data()!["e"] == "-") {
          // Check email
          var docRef = uidUser.docs[0].reference; // process only the first rec
          var data = {
            // "x": FieldValue.delete(),
            "e": myEmail,
            "u": myUid,
          }; // set as used
          await docRef.update(data);
          invitationStatus = 1;
        } else {
          recFound = 0;
          invitationStatus =
              7; // Invitation has been used by another user with different email
        } // end if e = "-"
      } // end if recFound == 0
    } // end if recFound >= 1
  } // end if recFound < 1
  if (recFound >= 1) {
    //= user exist
    var ref2 = uidUser.docs[0].reference; //= get only the first uid found
    user = uidUser.docs[0].data(); //= record user tier 1
    // Phone-match gate: on the uid-match path, verify that the typed phone
    // matches the stored phone. Skip if stored i is empty (no phone on record).
    // Decision mirrored by gatePassesMirror in
    // test/login_phone_match_gate_test.dart — keep the two in sync.
    if (matchedByUid) {
      final storedI = (user['i'] ?? '').toString().trim();
      if (storedI.isNotEmpty &&
          phoneCanonical62(inv) != phoneCanonical62(storedI)) {
        return 3; // PhoneNotMatch — typed phone != registered i (uid path)
      }
    }
    if (user["d"] == 1) {
      //= found regular user
      await ref2 //= get dvc entry
          .collection(fsDeviceSubCollection) // search data dvc sub collection
          .limit(1)
          .get()
          .then((results) async {
            user = results.docs[0].data();
            if (results.docs.length == 1) {
              if (user['in'] && user["did"] != myDevice) {
                // TODO handle situation when user deny imei access
                result = 802;
                // TODO call function to send reset email
                //   add prefix ";R"(reset) firebaseDocName
                // "Login fail. You already signed in with other device, or you deny access to phone."; //= return result
              } else {
                result = results.docs[0]; //= return result
              }
            } else {
              //= for some reason user was registered but no data in dvc. Treat like new user.
              // TODO add new vid to user
              result = 809;
            }
          });
    } else if (user["d"] < 1) {
      //= uid registered but no data, check dvc
      await ref2 //= get dvc entry
          .collection(fsDeviceSubCollection) // search data dvc sub collection
          .get()
          .then((results) async {
            if (results.docs.length == 1) {
              if (user['in'] && user["did"] != myDevice) {
                // TODO handle situation when user deny imei access
                result = 802; // error 802
                // "Login fail. You already signed in with other device, or you deny access to phone."; //= return result
              } else {
                result = results.docs[0]; //= return result
              }
            } else if (results.docs.isEmpty) {
              //= for some reason user was registered but no data in dvc. Treat like new user.
              // TODO add new vid to user
              result = 809;
            } else {
              //= multiple entry. Found demo or dev account
              bool deviceFound = false;
              int idx = 0;
              for (int i = 0; i < results.docs.length && !deviceFound; i++) {
                if (results.docs[i].data()["did"] == myDevice ||
                    results.docs[i].data()["did"] == "TBD") {
                  deviceFound = true;
                  idx = i;
                }
              }
              if (deviceFound) {
                result = results.docs[idx]; //= return result
              } else {
                result = 809; //"This device id is not registered.";
              }
            }
          });
    } else {
      //= more than 1 dvc entry => demo | dev user
      await ref2 //= get dvc entry
          .collection(fsDeviceSubCollection) // search data dvc sub collection
          .get()
          .then((results) async {
            bool deviceFound = false;
            int idx = 0;
            for (int i = 0; i < results.docs.length && !deviceFound; i++) {
              if (results.docs[i].data()["did"] == myDevice ||
                  results.docs[i].data()["did"] == "TBD") {
                deviceFound = true;
                idx = i;
              }
            }
            if (deviceFound) {
              result = results.docs[idx]; //= return result
            } else {
              result = 809;
              // "This device id is not registered. Deleted?"; //= return result
            }
          });
    }
  } else {
    //= not found, try to search email in e field (in case she is a new predefined user)
    // var cUser = state['#FIREBASE_USER']; //= get current firebase user data
    // result =
    //     getNewVid(cUser.uid, user.displayName, user.email); //= return result
    // TODO add new vid to user
    if (invitationStatus > 1) {
      result = invitationStatus; // Something wrong with invitation
    } else {
      result = 809;
    }
  }
  if (!(result is String || result is int) && needToRegisterInvLogin) {
    String proxy = result.data()['lif'];
    registerNewInvitationLogin(proxy, myEmail);
  }
  return result;
} // end of getFirestoreUserData

void registerNewInvitationLogin(String proxy, String email) {
  const jsonEncoder = JsonEncoder();
  String data = jsonEncoder.convert([proxy, email]);
  var qParams = {"d": ";0$data"};
  var uri = Uri.https(autsorzFunctionDomain, functionName['InvLogin'], qParams);
  try {
    callHttpPost(uri, null);
  } catch (e) {
    errorReport(e);
  }
} //end of registerNewInvitationLogin

void registerDeviceOperation(
  String proxy,
  String email,
  String operation,
  String phone,
) {
  const jsonEncoder = JsonEncoder();
  String data = jsonEncoder.convert([proxy, email, operation, phone]);
  var qParams = {"d": ";0$data"};
  var uri = Uri.https(
    autsorzFunctionDomain,
    functionName['deviceOperation'],
    qParams,
  );
  try {
    callHttpPost(uri, null);
  } catch (e) {
    errorReport(e);
  }
} //end of registerNewInvitationLogin

Future updateFirestore(var data) async {
  // update user's firestore data.
  var docRef = transactionStore
      .state
      .screenTx["#FS_REF"]; //= get this user firestore reference
  return docRef.updateData(data);
}

Future getFirestoreMessageRef(String myVid) async {
  /*
    output :
      message doc reference

    if not exist, will generate blank document for this vid
  */
  dynamic result;
  dynamic messageDocument;
  dynamic myMessageId;
  try {
    myMessageId = await secureRead(
      key: "myMsgId",
    ); //= get documentID of entry in msg_xxxx collection
  } catch (er) {
    errorReport(er);
  }
  if (myMessageId == null) {
    //= do not have message id stored
    try {
      messageDocument = await FirebaseFirestore
          .instance //= try to get anyway
          .collection(
            fsMsgCollection,
          ) //= search data in firebase with corresponding uid
          .where('v', isEqualTo: myVid)
          .limit(1)
          .get();
      if (messageDocument.docs.length > 0) {
        //= message record exist
        result = messageDocument.docs[0].reference;
      } else {
        //= not found, new user
        var myUid = transactionStore.state.screenTx['#FIREBASE_USER'].uid;
        result = await createNewMessageDocument(myVid, myUid);
      }
    } catch (er) {
      errorReport(er);
    }
  } else {
    try {
      messageDocument = await FirebaseFirestore.instance
          .collection(fsMsgCollection)
          .doc(myMessageId)
          .get();
      if (messageDocument.exists) {
        result = messageDocument.reference;
      } else {
        //= not found, new user
        var myUid = transactionStore.state.screenTx['#FIREBASE_USER'].uid;
        result = await createNewMessageDocument(myVid, myUid);
      }
    } catch (er) {}
  }
  return result;
} // end of getFirestoreMessageRef

Future createNewMessageDocument(String myVid, String myUid) async {
  var data = {"u": myUid, "v": myVid};
  var newDoc = await FirebaseFirestore.instance
      .collection(fsMsgCollection)
      .add(data);
  return newDoc;
} // end of createNewMessageDocument

String otqStateToGpsString(dynamic position) {
  String result = "";
  result =
      position.latitude.toString() +
      separator[3] +
      position.longitude.toString() +
      separator[3] +
      (((position.accuracy * 100).round()) / 100).toString() +
      separator[3] +
      position.gpsTimestamp!.millisecondsSinceEpoch.toString() +
      separator[3] +
      (position.mock ? "mocked" : "true") +
      separator[3] +
      position.heading.toString() +
      separator[3] +
      (((position.speed * 100).round()) / 100).toString() +
      separator[3] +
      (((position.speedAccuracy * 100).round()) / 100).toString() +
      separator[3] +
      position.altitude.round().toString() +
      separator[3] +
      position.floor.toString() +
      separator[3] +
      position.isoCountryCode.toString() +
      separator[3] +
      position.postalCode.toString() +
      separator[3] +
      cleanupString(position.administrativeArea.toString()) +
      separator[3] +
      cleanupString(position.subAdministrativeArea.toString()) +
      separator[3] +
      cleanupString(position.locality.toString()) +
      separator[3] +
      cleanupString(position.subLocality.toString()) +
      separator[3] +
      cleanupString(position.thoroughfare.toString()) +
      separator[3] +
      cleanupString(position.subThoroughfare.toString());
  return result;
} // end of otqStateToGpsString

String positionToGpsString(dynamic position) {
  String result = "";
  result =
      position.latitude.toString() +
      separator[3] +
      position.longitude.toString() +
      separator[3] +
      (((position.accuracy * 100).round()) / 100).toString() +
      separator[3] +
      position.timestamp!.millisecondsSinceEpoch.toString() +
      separator[3] +
      (position.isMocked ? "mocked" : "true") +
      separator[3] +
      position.heading.toString() +
      separator[3] +
      (((position.speed * 100).round()) / 100).toString() +
      separator[3] +
      (((position.speedAccuracy * 100).round()) / 100).toString() +
      separator[3] +
      position.altitude.round().toString() +
      separator[3] +
      position.floor.toString();
  return result;
} // end of positionToGpsString

Future serverSetup() async {
  // do all initial server, firebase storage.
  try {
    // late LocationSettings locationSettings;
    // if (Platform.isAndroid) {
    //   locationSettings = AndroidSettings(
    //     accuracy: LocationAccuracy.bestForNavigation,
    //     // distanceFilter: 1,
    //     forceLocationManager: true,
    //     intervalDuration: const Duration(seconds: 2),
    //   );
    //   // WebView.platform = AndroidWebView(); // set default web view platform
    // } else if (Platform.isIOS || Platform.isMacOS) {
    //   locationSettings = AppleSettings(
    //     accuracy: LocationAccuracy.high,
    //     // activityType: ActivityType.fitness,
    //     // distanceFilter: 1,
    //     pauseLocationUpdatesAutomatically: true,
    //   );
    // } else {
    //   locationSettings = const LocationSettings(
    //     accuracy: LocationAccuracy.high,
    //     // distanceFilter: 100,
    //   );
    // } // end if Platform
    debugCount = 210;
    trace(debugCount);
    // positionStream =
    //     Geolocator.getPositionStream(locationSettings: locationSettings);
    // positionStreamSubs = positionStream.listen((Position position) {
    //   updateAppGps(position);
    //   String gpsDataStream = positionToGpsString(position);
    //   int calculatedTime =
    //       DateTime.now().millisecondsSinceEpoch + time2GpsOffset;
    //   int elapsedTime = calculatedTime - gpsTime.value;
    //   devPrint(
    //       "gpsTime:${gpsTime.value} , time2GpsOffset:$time2GpsOffset ,  Position stream: $gpsDataStream");
    //   devPrint("  calculatedTime: $calculatedTime , elapsedTime: $elapsedTime");
    // });
  } catch (er) {
    errorReport(er);
  } // end try location stream
  debugCount = 2101;
  trace(debugCount);
  dynamic aRes;
  try {
    aRes = await settingUp();
  } catch (er) {
    errorReport(er);
  }
  debugCount = 211;
  trace(debugCount);
  var res = json.decode(aRes[0]['body']);
  debugCount = 212;
  var signUpDemo = res['signupDemo'];
  location = json.decode(res['location']);
  debugCount = 213;
  debugCount = 214;
  debugCount = 215;
  trace(debugCount);
  FirebaseStorage storageBucket = FirebaseStorage.instanceFor(
    bucket: 'gs://otq-01-ase2',
  ); //= TODO move to procedure after sign in
  debugCount = 216;
  trace(debugCount);
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({
        '#GUEST_LIF': res['signupLif'],
        '#GUEST_INDEX': res['signupIdx'],
        '#GUEST_UPGRADE_INDEX': res['guestUpgradeIdx'],
        '#VM_UPGRADE_INDEX': res['vmUpgradeIdx'],
        '#SETTINGS': aRes,
        '#DEMO_SIGNUP_KEY': signUpDemo,
        '#STORAGE_BUCKET': storageBucket,
      }),
    ),
  ); // set result of settingUp (function getPoxSettings as state #SETTING
  debugCount = 217;
  trace(debugCount);
} // end of serverSetup

int defaultVid() {
  return 70027002611015; // autsorz
} // end of defaultVid

String getEventDocName(String vidTime) {
  String str = sha3_256B64(vidTime);
  return base64ForUrl(str.substring(str.length - 21).substring(0, 20));
} // end of getEventDocName

void clearData(String scrName) {
  // clear all data in a page

  // ScreenSession.navReset iterates all registered stores whose NavPolicy
  // is screen or all, and fires their clear function. This replaces the
  // hand-maintained list of 11 static clear calls + GroupPicker.clearAll
  // that lived here before. Must run ABOVE the txfController early-return:
  // custody pages have no txfController entries and would be skipped.
  ScreenSession.navReset(scrName);

  if (txfController[scrName] == null) return;

  final List<String> widgetsToUpdate = [];

  txfController[scrName]!.forEach((k, input) {
    // clear all data
    try {
      String wId = '$scrName-${input.position}';
      // GeneralGetXController.to.getWidgetId(scrName, input.position);

      // Restore state
      input.controller.text = input.initialValue;
      input.finalData = input.initialValue;
      input.isEnabled = input.initialIsEnabled; // Restore isEnabled state
      input.stateObject = input.initialStateObject; // Restore state object

      widgetsToUpdate.add(wId);

      dynamic theController = GeneralGetXController.to.getController(
        scrName,
        input.position,
      );
      if (theController is TextEditingController) {
        theController.text = input.initialValue;
        devPrint(
          'clearing input controller for txf myController $wId initialValue = ${input.initialValue}',
        );
      }

      devPrint('clearing GetXController $wId');
      GeneralGetXController.to.deleteAllWidget(
        scrName,
        input.position,
      ); // for images
      devPrint('GetXController $wId cleared');
    } catch (e) {
      // do nothing
    }
  });

  if (widgetsToUpdate.isNotEmpty) {
    Get.find<WidgetUpdateController>().update(widgetsToUpdate);
  }
} // end of clearData

String replacePlaceHoldersFromTxfController(String scrName, String text) {
  // Define a regular expression to find the placeholder.
  // The `r''` denotes a raw string, and `\d+` matches one or more digits.
  // The parentheses `()` create a capturing group for the number.
  // {{POS(n)}} will be replaced with ref[1][n]
  final RegExp regex = RegExp(r'{{(POS|DOC)\((\d+)\)}}');

  // Use replaceAllMapped to find all matches and apply a function to each one.
  return text.replaceAllMapped(regex, (match) {
    try {
      final String type = match.group(1)!;
      // Get the captured number (from the first capturing group).
      final int index = int.parse(match.group(2)!);

      // Access the value from the ref list and return it.
      // Assuming the user's example of ref[1][n] is the required structure.
      String content = txfController[scrName]![index]?.finalData ?? 'No-DATA';
      if (type == 'DOC') {
        return getDocumentName(content);
      } else if (type == 'POS') {
        // Otherwise, it's a POS placeholder, return the value directly.
        return content;
      } else {
        return 'NO-$type';
      }
    } catch (e) {
      errorReport(e);
    }
    // Return NO-DATA if the index is out of bounds.
    return 'NO-DATA';
  });
} // end of replacePlaceHoldersFromTxfController

String replacePlaceholders(String text, List<List<dynamic>> ref) {
  // Define a regular expression to find the placeholder.
  // The `r''` denotes a raw string, and `\d+` matches one or more digits.
  // The parentheses `()` create a capturing group for the number.
  // {{POS(n)}} will be replaced with ref[1][n]
  final RegExp regex = RegExp(r'{{(POS|DOC)\((\d+)\)}}');

  // Use replaceAllMapped to find all matches and apply a function to each one.
  return text.replaceAllMapped(regex, (match) {
    try {
      final String type = match.group(1)!;
      // Get the captured number (from the first capturing group).
      final int index = int.parse(match.group(2)!);

      // Access the value from the ref list and return it.
      // Assuming the user's example of ref[1][n] is the required structure.
      if (ref.length > 1 && ref[1].length > index) {
        if (type == 'DOC') {
          return getDocumentName((ref[1][index] ?? 'No-DATA').toString());
        } else if (type == 'POS') {
          // Otherwise, it's a POS placeholder, return the value directly.
          return (ref[1][index] ?? 'No-DATA').toString();
        } else {
          return 'NO-$type';
        }
      }
    } catch (e) {
      errorReport(e);
    }

    // Return NO-DATA if the index is out of bounds.
    return 'NO-DATA';
  });
} // end of replacePlaceholders

void saveSend(
  int? timeStamp,
  String scrName,
  var component,
  String locString,
  int appVid, {
  bool send = true,
}) {
  int currentTableVid = appVid;
  if (component['com'] == 'con') {
    currentTableVid = consteonVid;
  }
  setTransactionNotOK('saveSend');
  try {
    /*
    var state = transactionStore.state.screenTx;
    TimerBloc timerBloc = state['#TIMER_BLOC'];
    var route = component['route'] ?? scrName;
    rootThis.setState(() {
      rootThis.wait = true;
    });
    timerBloc.add(Start(duration: 5)); //  get timerBloc from transactionStore
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#NEXTROUTE': route,
      '#TIMER_CONTEXT': context,
      '#TIMER_DURATION': component['delay'] ?? 5,
    }))); // set state #NEXTROUTE route that will be displayed after waitScreen
    */
    dynamic state = transactionStore.state.screenTx;
    String flag =
        component['flag'] ??
        emptyString; // flag to be written with ⬤ separator at the end
    List<dynamic> row = List<dynamic>.filled(
      sheetSystemLength + txfController[scrName]!.length,
      null,
      growable: true,
    );
    int maxPosition = 0;
    row[0] = null;
    row[1] = scrName;
    row[2] = state['#VID'];
    row[3] = 'NTP';
    row[8] = 'E0';
    if (component['type'].toString().trim().toLowerCase() == 'checker') {
      //separator[5] = white diamond
      row[4] =
          '${separator[5]}${component['checker']}${separator[5]}${component['checkie']}';
    } else {
      row[4] = '';
    } // end (component['type'].toString().trim().toLowerCase() == 'checker')

    txfController[scrName]!.forEach((k, input) {
      try {
        if (1 <= input.position && input.position <= 100) {
          if (input.table != null) {
            // if table is not null or empty
            input.table!.forEach((documentName, content) {
              String finalName = replacePlaceHoldersFromTxfController(
                scrName,
                documentName,
              );
              writeToStaticTable(currentTableVid, finalName, content);
            });
          } // end if (input.table != null && input.table != emptyString)
          int pos = input.position + sheetSystemLength - 1;
          maxPosition = input.position > maxPosition
              ? input.position
              : maxPosition;
          if (pos >= row.length) {
            int dif = pos - row.length;
            for (var ii = 0; ii < dif; ii++) {
              row.add('');
            }
            row.add(
              input.finalData == emptyString
                  ? (stringCleanUp(input.controller.text) ?? "").replaceAll(
                      "\n",
                      "\\n",
                    )
                  : (stringCleanUp(input.finalData) ?? '').replaceAll(
                      "\n",
                      "\\n",
                    ),
            ); // get data from txf controller
            int d = 1;
          } else {
            row[pos] = input.finalData == emptyString
                ? (stringCleanUp(input.controller.text) ?? '').replaceAll(
                    "\n",
                    "\\n",
                  )
                : (stringCleanUp(input.finalData) ?? '').replaceAll(
                    "\n",
                    "\\n",
                  ); // get data from txf controller
          } // end if if (pos >= row.length)
        } // end if input.position > 0
      } catch (eEach) {
        errorReport(eEach);
      } // end try
    }); // end for each txfController
    row = row.sublist(
      0,
      (maxPosition + 15 < row.length) ? maxPosition + 15 : row.length,
    );
    List<List<dynamic>> ref = [];
    ref.add(row.sublist(0, 14));
    ref.add(row.sublist(14));
    String? tableString;
    try {
      tableString = component['addToTable'] ?? '';
      // "${component['saveToTable'] ?? ''}${separator[0]}" +
      // "${component['appendToTable'] ?? ''}${separator[0]}" +
      // "${component['addToTable'] ?? ''}";
      tableString = autheniumDecode(tableString) ?? '';
      tableString = tableString
          .replaceAll("◼A⭘", "◼A⭘tableVid◼$currentTableVid⭘")
          .replaceAll("◼D⭘", "◼D⭘tableVid◼$currentTableVid⭘")
          .replaceAll("◼S⭘", "◼S⭘tableVid◼$currentTableVid⭘");
      tableString = replacePlaceholders(tableString, ref);
      tableString = TokenResolver.screenTxMarkers(tableString);
      int d = 1;
    } catch (e) {
      // tableString = null;
    } // end try

    String updateString = '';
    try {
      String raw = component['updateTableRow'] ?? '';
      if (raw.isNotEmpty) {
        updateString = autheniumDecode(raw) ?? '';
        updateString = updateString.replaceAll(
          "◼D⭘",
          "◼D⭘tableVid◼$currentTableVid⭘",
        );
        updateString = replacePlaceholders(updateString, ref);
        updateString = TokenResolver.screenTxMarkers(updateString);
      }
    } catch (e) {
      updateString = '';
    }

    String deleteString = '';
    try {
      String raw = component['deleteFromTable'] ?? '';
      if (raw.isNotEmpty) {
        deleteString = autheniumDecode(raw) ?? '';
        deleteString = deleteString.replaceAll(
          "◼D⭘",
          "◼D⭘tableVid◼$currentTableVid⭘",
        );
        deleteString = replacePlaceholders(deleteString, ref);
        deleteString = TokenResolver.screenTxMarkers(deleteString);
      }
    } catch (e) {
      deleteString = '';
    }

    String eventString = '';
    try {
      String raw = component['addToEvent'] ?? '';
      if (raw.isNotEmpty) {
        eventString = autheniumDecode(raw) ?? '';
        eventString = resolveDriverCurlyTokens(eventString, scrName);
        eventString = replacePlaceholders(eventString, ref);
        eventString = TokenResolver.screenTxMarkers(eventString);
        // Notification fields are ADDITIVE — a failure here must never discard
        // the base addToEvent payload (the outer catch resets eventString to '').
        try {
          eventString += buildNotificationSuffix(
            component['notification'],
            (s) => TokenResolver.screenTxMarkers(replacePlaceholders(s, ref)),
          );
        } catch (e) {
          errorReport(e);
        }
      }
    } catch (e) {
      eventString = '';
    }

    String updateEventString = '';
    try {
      String raw = component['updateEventRow'] ?? '';
      if (raw.isNotEmpty) {
        updateEventString = autheniumDecode(raw) ?? '';
        updateEventString = resolveDriverCurlyTokens(
          updateEventString,
          scrName,
        );
        updateEventString = replacePlaceholders(updateEventString, ref);
        updateEventString = TokenResolver.screenTxMarkers(updateEventString);
      }
    } catch (e) {
      updateEventString = '';
    }

    if (updateEventString.isNotEmpty) {
      devPrint(
        '[saveSend] updateEventRow composed, '
        'length=${updateEventString.length}',
      );
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString${separator[0]}$eventString${separator[0]}$updateEventString';
    } else if (eventString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString${separator[0]}$eventString';
    } else if (updateString.isNotEmpty || deleteString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString';
    }

    if (routeExist(component['route'])) {
      devPrint('start clearing txfController');
      clearData(scrName);
    }
    setTransactionOK('saveSend');
    if (send) {
      saveSendRows(
        scrName,
        '',
        row,
        flag,
        timeStamp,
        locString,
        tableString,
        currentTableVid,
        component['desc'] ?? '',
        component['type'] ?? '',
      );
    } // end if (send)
    // setTransactionOK('setDataOK');
  } catch (err) {
    setDataOK('1');
    errorReport(err);
  }
} // end of saveSend

Future saveSendRows(
  String screenName,
  String tail,
  List<dynamic> row,
  String flag,
  int? timeStamp,
  String locString,
  String? tableString,
  int appVid,
  String desc,
  String widgetType,
) async {
  if (timeStamp == null) {
    row[0] = await getRealTime();
  } else {
    row[0] = timeStamp;
  }
  String originalText = '0'; // encryption type 0 = no encryption
  if (!identical(flag, emptyString)) {
    originalText += flag;
  }
  originalText += locString + separator[0]; // black circle
  for (int c = 15; c < row.length; c++) {
    if (15 < c) originalText += separator[3]; // formerly 1=black diamond
    if (row[c] != null) originalText += row[c];
  }
  row[2] = '$originalText$tail';
  row = row.sublist(0, 3);
  // dynamic tableResult = writeToTable(tableString, jsonEncode(row));
  // try {
  //   dynamic tableResult = writeToTable(tableString, row);
  // } catch (e) {
  //   String d = e.toString();
  // }
  appendToSheet(row, appVid, flag, desc, widgetType, tableString);
} // end of saveSendRows

Future<void> createApprovalEvent({
  required List<dynamic> row,
  required String scrName,
  required String eventFlag,
  required String actionStatus,
  required bool updateOverallStatus,
  required List<List<String>> steps,
  required int targetIdx,
  required int nowMs,
  required int appVid,
}) async {
  try {
    if (eventFlag.isEmpty) return;

    final state = transactionStore.state.screenTx;
    final String approverVid = (state['#VID'] ?? '').toString();
    final String approverName = (state['#NAME'] ?? '').toString();

    OtqState locSensor = await OtqState().setAllDataAsync();
    int timeStamp = await getRealTime();
    String locString = getLocationString('', '', '', locSensor);

    String updatedStatus = updateOverallStatus
        ? actionStatus
        : (row.length > 2 ? row[2].toString() : '');

    int totalPositions = 28;
    List<dynamic> eventRow = List<dynamic>.filled(
      sheetSystemLength + totalPositions,
      '',
      growable: true,
    );
    eventRow[0] = null;
    eventRow[1] = scrName;
    eventRow[2] = approverVid;

    // Position 3: Photo URL (<15>)
    eventRow[17] = row.length > 15 ? row[15].toString() : '';
    // Position 4: Jenis Cuti (<13>)
    eventRow[18] = row.length > 13 ? row[13].toString() : '';
    // Position 6: Tanggal Mulai (<16>)
    eventRow[20] = row.length > 16 ? row[16].toString() : '';
    // Position 7: Tanggal Selesai (<18>)
    eventRow[21] = row.length > 18 ? row[18].toString() : '';
    // Position 10: Keterangan (<14>)
    eventRow[24] = row.length > 14 ? row[14].toString() : '';
    // Position 11: Jumlah Hari (<20>)
    eventRow[25] = row.length > 20 ? row[20].toString() : '';
    // Position 15: Overall Status (<2> AFTER update)
    eventRow[29] = updatedStatus;
    // Position 16: Replacement VID (<22>)
    eventRow[30] = row.length > 22 ? row[22].toString() : '';
    // Position 17: Request Number (<1>)
    eventRow[31] = row.length > 1 ? row[1].toString() : '';
    // Position 18: Replacement Name (<23>)
    eventRow[32] = row.length > 23 ? row[23].toString() : '';
    // Position 19: Approver VID
    eventRow[33] = approverVid;
    // Position 20: Approver Name
    eventRow[34] = approverName;

    // Positions 24-28: Approval level data (cumulative)
    String wd = separator[5];
    String formattedNow = DateFormat(
      'dd MMM yyyy HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(nowMs));

    for (int lvl = 0; lvl < 5 && lvl < steps.length; lvl++) {
      List<String> step = steps[lvl];
      String status = step.length > 1 ? step[1].trim().toUpperCase() : '';
      if (status.isEmpty || status == 'PENDING') continue;

      String levelNum = step.isNotEmpty ? step[0].trim() : '${lvl + 1}';
      String name, vid, ts, epoch;
      if (lvl == targetIdx) {
        vid = approverVid;
        name = approverName;
        ts = formattedNow;
        epoch = nowMs.toString();
      } else {
        vid = step.length > 2 ? step[2].trim() : '';
        name = step.length > 3 ? step[3].trim() : '';
        ts = step.length > 4 ? step[4].trim() : '';
        epoch = step.length > 5 ? step[5].trim() : '';
      }
      eventRow[38 + lvl] = '$levelNum$wd$status$wd$name$wd$vid$wd$ts$wd$epoch';
    }

    saveSendRows(
      scrName,
      '',
      eventRow,
      eventFlag,
      timeStamp,
      locString,
      null,
      appVid,
      '',
      'approval',
    );
    debugPrint('[Approval] event created: flag=$eventFlag');
  } catch (e) {
    debugPrint('[Approval] event creation error: $e');
    errorReport(e);
  }
} // end of createApprovalEvent

Future<void> buildAndSaveEventFromDSL({
  required String eventDSL,
  required List<dynamic> updatedRow,
  required String scrName,
  required String flag,
  required int appVid,
}) async {
  try {
    if (eventDSL.isEmpty || flag.isEmpty) return;

    final state = transactionStore.state.screenTx;
    final String approverVid = (state['#VID'] ?? '').toString();
    final String approverName = (state['#NAME'] ?? '').toString();
    final String approverEmail = (state['#EMAIL'] ?? '').toString();
    final String wd = separator[5];

    OtqState locSensor = await OtqState().setAllDataAsync();
    int timeStamp = await getRealTime();
    String locString = getLocationString('', '', '', locSensor);

    int totalPositions = 28;
    List<dynamic> eventRow = List<dynamic>.filled(
      sheetSystemLength + totalPositions,
      '',
      growable: true,
    );
    eventRow[0] = null;
    eventRow[1] = scrName;
    eventRow[2] = approverVid;

    // ★1 identity block (auto, same as savesend)
    eventRow[16] = '$approverVid$wd$approverName$wd$approverEmail';

    for (final entry in eventDSL.split('⭘')) {
      final parts = entry.split('◼');
      if (parts.length != 2) continue;

      final starStr = parts[0].replaceAll('★', '').trim();
      final starIdx = int.tryParse(starStr);
      if (starIdx == null || starIdx < 2 || starIdx > 27) continue;

      final source = parts[1].trim();
      final eventIdx = 15 + starIdx;

      if (source == 'approver') {
        eventRow[eventIdx] = '$approverVid$wd$approverName';
      } else if (source == 'levels') {
        _expandEventLevels(updatedRow, eventRow, eventIdx);
      } else if (RegExp(r'^<\d+>$').hasMatch(source)) {
        final fieldIdx = int.parse(source.substring(1, source.length - 1));
        eventRow[eventIdx] = fieldIdx < updatedRow.length
            ? updatedRow[fieldIdx].toString()
            : '';
      } else {
        eventRow[eventIdx] = source;
      }
    }

    saveSendRows(
      scrName,
      '',
      eventRow,
      flag,
      timeStamp,
      locString,
      null,
      appVid,
      '',
      'approval',
    );
    debugPrint('[Approval] DSL event created: flag=$flag');
  } catch (e) {
    debugPrint('[Approval] DSL event creation error: $e');
    errorReport(e);
  }
}

void _expandEventLevels(
  List<dynamic> updatedRow,
  List<dynamic> eventRow,
  int startEventIdx,
) {
  String chainStr = '';
  for (int i = 0; i < updatedRow.length; i++) {
    String s = updatedRow[i].toString().trim();
    if (s.startsWith('[[') && s.contains(',')) {
      chainStr = s;
      break;
    }
  }
  if (chainStr.isEmpty) return;

  String inner = chainStr.substring(1, chainStr.length - 1);
  List<List<String>> steps = [];
  for (var stepStr in inner.split(RegExp(r'\]\s*,\s*\['))) {
    stepStr = stepStr.replaceAll('[', '').replaceAll(']', '').trim();
    steps.add(stepStr.split(',').map((e) => e.trim()).toList());
  }

  String wd = separator[5];
  for (int i = 0; i < steps.length && i < 5; i++) {
    int targetIdx = startEventIdx + i;
    if (targetIdx >= eventRow.length) break;

    List<String> step = steps[i];
    String status = step.length > 1 ? step[1].trim().toUpperCase() : '';
    if (status == 'PENDING' || status.isEmpty) continue;

    String levelNum = step.isNotEmpty ? step[0].trim() : '${i + 1}';
    String vid = step.length > 2 ? step[2].trim() : '';
    String name = step.length > 3 ? step[3].trim() : '';
    String ts = step.length > 4 ? step[4].trim() : '';
    String epoch = step.length > 5 ? step[5].trim() : '';

    // Output: level◇status◇name◇vid◇timestamp◇epoch (name before vid)
    eventRow[targetIdx] = '$levelNum$wd$status$wd$name$wd$vid$wd$ts$wd$epoch';
  }
}

Future<String> appendToSheet(
  dynamic val,
  int appVid,
  String flag,
  String desc,
  String wType,
  String? tableString,
) async {
  var state = transactionStore.state.screenTx;
  try {
    String c = jsonEncode(val);
    c.replaceAll('#', '--');
    devPrint("Submit value = $c");
    var ss = state['#INTERFACE_KEY'];
    var id =
        '${state['#VID']}${(Random.secure().nextDouble() * 1000).toString()}';
    SubmitBloc submitBloc = state['#SUBMIT_BLOC'];
    // SubmitBloc submitBloc = BlocProvider.of<SubmitBloc>(context);
    submitBloc.add(
      AddSubmit(
        Submit(
          st: 0,
          ss: ss,
          c: c,
          id: id,
          appVid: appVid,
          t: val[0],
          p: val[1],
          c2: val[2],
          d: desc,
          f: flag,
          w: wType,
          tb: tableString,
        ),
      ),
    ); // append to firestore
    submitBloc.add(LoadSubmit()); // refresh cache
    TimerBloc timerBloc = state['#TIMER_BLOC'];
    // Guard: #TIMER_DURATION is set only by the standard submit widgets right
    // before saveSend (ftz_row_of_button_2, otq_txf, ftz_checker, ...). Direct
    // saveSend callers (custody_count_submit O1/C1) leave it null; Start.duration
    // is a non-nullable int, so an unguarded add throws "Null is not a subtype of
    // int" here — AFTER AddSubmit — aborting appendToSheet before actionUnLock and
    // stranding the history record (evidence + updateEventRow) unsent. Skip the
    // timer when absent; those callers navigate themselves.
    final dynamic timerDuration = state['#TIMER_DURATION'];
    if (timerDuration is int) {
      timerBloc.add(Start(duration: timerDuration));
    }
    actionUnLock('appendToSheet');
  } catch (e) {
    setDataOK('1');
    errorReport(e);
  }
  return 'End of appendToSheet';
} // end of appendToSheet

Future getRealTime() async {
  // get data from device. If connected to internet, get from ntp
  // in no internet connection, get time from gps
  // if everything fail, return device time in millisecondSinceEpoch
  DateTime n = DateTime.now();
  int retVal = n.millisecondsSinceEpoch + time2GpsOffset;
  try {
    if (internetConnected()) {
      n = await NTP.now().timeout(const Duration(seconds: 2));
      retVal = n.millisecondsSinceEpoch;
      // } else {
      // try {
      //   Position? pos2 = await Geolocator.getCurrentPosition();
      //   gpsTime.value = pos2.timestamp.millisecondsSinceEpoch;
      //   transactionStore.dispatch(UpdateScreenTxAction(
      //       ScreenTransaction({'#LASTGPSTIME': gpsTime.value})));
      //   prefs.setInt('@lastGpsTime', gpsTime.value);
      // } catch (eGps) {
      //   errorReport(e);
      // } // end try
      // if (gpsTime.value > 0) {
      //   retVal = gpsTime.value;
      // }
    } // end if internetConnected()
  } catch (e) {
    reportNonTimeout(e);
  }
  // devPrint('Ntp returning : ${n.millisecondsSinceEpoch}');
  return retVal;
} // end of getRealTime

FunctionBody getFunctionBody(String ssid, var range) {
  // range is an array
  // Return url and body for gcf call
  var job = "[";
  for (int i = 0; i < range.length; i++) {
    if (i > 0) job += ',';
    job += '{"ssid":"$ssid","type":"A1","rg":"${range[i]}"}';
  }
  job += "]";
  Map<String, String> qParams = {
    "eData": "--",
    "clt": defaultCluster,
    "job": job,
  };
  var url = "https://$autsorzFunctionDomain${functionName['readSS']}";
  FunctionBody result = FunctionBody(url, qParams);
  return result;
  //  return http.post(url, body: qParams);
}

FunctionBody appendSSA1(String ssid, var rowData, String clt) {
  // range is an array
  // Return url and body for gcf call
  List job = [];
  for (int i = 0; i < rowData.length; i++) {
    job.add({"ssid": ssid, "dt": rowData[i]});
  }
  String jobStr = jsonEncode(job);
  Map<String, String> qParams = {
    "eData": "--",
    "clt": clt,
    "ver": version,
    "job": jobStr,
  };
  var url = "https://$autsorzFunctionDomain${functionName['addFL']}";
  FunctionBody result = FunctionBody(url, qParams);
  return result;
  //  return http.post(url, body: qParams);
}

Future<Position?> getLocation() async {
  // get gps location, until #LASTGPSTIME <> current readings>
  devPrint('getLocation');
  dynamic allGpsData = await getAppGps();
  // Kept as a typed local (not `return allGpsData['gpsData']` directly) so the
  // implicit cast off the dynamic map still asserts the shape here rather than
  // at a caller. Behaviour is unchanged; only the dead `myLatitude` read that
  // used to force this same cast is gone.
  Position myPosition = allGpsData['gpsData'];
  return myPosition;
} // end of getLocation

int exp2Epoch(String? inp) {
  // convert mm/yy => millisecond from epoch
  int result = DateTime.now().millisecondsSinceEpoch;
  if (inp != null) {
    dynamic inpArray = inp.split("/");
    if (inpArray.length == 2) {
      result = DateTime(
        2000 + int.parse(inpArray[1]),
        int.parse(inpArray[0]),
      ).millisecondsSinceEpoch;
    }
  }
  return result;
} // end of exp2Epoch

bool locationToleranceCheck(Position position, var locArray, int tolerance) {
  bool found = false;
  var accuracy = position.accuracy;
  var finalTolerance = tolerance + accuracy;
  for (int i = 0; i < locArray.length && !found; i++) {
    var d = distanceM(
      position.latitude,
      position.longitude,
      locArray[i][0],
      locArray[i][1],
    );
    found = d <= finalTolerance; //? true : false;
  } // end for locArray
  return found;
} // end of locationToleranceCheck

Future locationVerify(var locArray, var tolerance, OtqState? otqData) async {
  // return bool, for any location in locArray with distance <= tolerance
  // bool locOk = await locationVerify([ [-6.3161284,106.6448379],[-6.3161284,106.6448379],],100, OtqState);
  bool found = false;
  try {
    if (otqData == null) {
      sleep(const Duration(milliseconds: 100));
    }
    if (otqData != null) {
      OtqState position = otqData;
      for (var l = 0; l < 10 && !position.gpsDone; l++) {
        sleep(Duration(milliseconds: 100 + l * 20));
      } // end while !otqData.gpsDone
      if (position.gpsDone) {
        var accuracy = position.accuracy;
        var finalTolerance = tolerance + accuracy;
        for (int i = 0; i < locArray.length && !found; i++) {
          var d = distanceM(
            position.latitude,
            position.longitude,
            locArray[i][0],
            locArray[i][1],
          );
          found = d <= finalTolerance; //? true : false;
        } // end for i
      } // end if position.gpsDone
    } // end if otqData != null
  } catch (e) {
    errorReport(e);
  } // end try
  return found;
} // end of locationVerify

num distanceM(var lat1, var lon1, var lat2, var lon2) {
  // inspired by https://www.movable-type.co.uk/scripts/latlong.html
  const R = 6371000;
  const piRad = 0.0174532925199433; // pi/180
  num t1 = lat1 * piRad;
  num t2 = lat2 * piRad;
  num dt = (lat2 - lat1) * piRad;
  num dl = (lon2 - lon1) * piRad;
  num a =
      sin(dt / 2) * sin(dt / 2) + cos(t1) * cos(t2) * sin(dl / 2) * sin(dl / 2);
  num c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
} //end of distanceM

Future<String> getPhotoCameraImage(
  List<CameraDescription> cameras,
  String title,
  String lens,
  int maxsize,
  int quality,
  String folder,
  String fileName,
  double? height,
  double? width,
) async {
  final String pickedFileUrl = await acquireCamera(
    cameras,
    title,
    lens,
    maxsize,
    quality,
    height,
    width,
  );
  // String url = await saveImageToCloud(
  //     imagePath: pickedFileUrl, folder: folder, fileName: fileName);
  String url = await prepareImageAsLocal(
    imagePath: pickedFileUrl,
    folder: folder,
    fileName: fileName,
  );
  await saveImagePutInImageMap(url);
  // var state = transactionStore.state.screenTx;
  // var storageBucket = state['#STORAGE_BUCKET'];
  // Reference storageRef = storageBucket.ref().child("$folder/$fileName.jpg");
  // UploadTask uploadTask2 = storageRef.putFile(File(pickedFileUrl));
  // TaskSnapshot taskSnapshot = await uploadTask2;
  // var url = await taskSnapshot.ref.getDownloadURL();
  return url;
} // end of getPhotoCameraImage

// Named parameters here are DELIBERATE and intentionally asymmetric with the
// sibling getPhotoCameraImage (which uses positional args). The gallery path is
// new and only ever called from one site (otq_get_images_2.buttonPressed); named
// args keep that call self-documenting without disturbing the legacy positional
// signature every camera caller depends on.
Future<String> getGalleryImage({
  required String folder,
  required String fileName,
  required int maxSize,
  required int quality,
}) async {
  final ImagePicker picker = ImagePicker();
  // maxWidth/maxHeight/imageQuality force image_picker to transcode to JPEG.
  // This is required because renamePath (via buildImageDestinationName) hardcodes
  // a .jpg extension. If these params were ever removed, HEIC/PNG bytes would be
  // written under a .jpg name.
  final XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: maxSize.toDouble(),
    maxHeight: maxSize.toDouble(),
    imageQuality: quality,
  );
  if (picked == null) return emptyImageUrl;
  // forceRename: true ensures the gallery file (no OTQC artifact) is relocated
  // from the OS cache dir into <appSupport>/otq_images with the correct
  // FTZIMG%2F<folder>___<fileName>.jpg name, preventing aum__ history wedge.
  String url = await prepareImageAsLocal(
    imagePath: picked.path,
    folder: folder,
    fileName: fileName,
    forceRename: true,
  );
  await saveImagePutInImageMap(url);
  return url;
} // end of getGalleryImage

Future<String> getCameraImageNotUsed(
  double w,
  double h,
  int quality,
  String folder,
  String rawFileName,
) async {
  /*
  String fileName = rawFileName.replaceAll(".jpg", "");
  final picker = ImagePicker();
  final pickedFile = (await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxHeight: h,
      maxWidth: w,
      imageQuality: quality))!;
  var state = transactionStore.state.screenTx;
  var storageBucket = state['#STORAGE_BUCKET'];
  Reference storageRef = storageBucket.ref().child("$folder/$fileName.jpg");
  UploadTask uploadTask2 = storageRef.putFile(File(pickedFile.path));
  TaskSnapshot taskSnapshot = await uploadTask2;
  var url = await taskSnapshot.ref.getDownloadURL();
  return url;
  */
  return emptyImageUrl;
} // end of selfie

String encForOtonomiqCall(txt) {
  // Encrypt txt with totp aes then return clean Base64
  //  clean = '+' = '-'; "/" = '_'
  // key = any length B32.
  // Input text will be prefixed with ";;" for 1 or 2 totp identification
  // This prefix will be deleted when decrypted.
  String result = "";
  // var totp1 = totp(getOtqK(1), 16, 30);
  // Uint8List d = Uint8List.fromList(utf8.encode(totp1[1]));
  // var h = getSHA3(d);
  // String hHex = uint8ToHex(h);
  // let k = getSha3(256, totp1[1].toString());        // use later totp
  // let e = CryptoJS.AES.encrypt(internalPrefix + txt, k
  //     , {
  //       mode: CryptoJS.mode.CBC                       // for this library, CBC is the only mode supported
  //       , padding: CryptoJS.pad.Pkcs7
  //     }
  // );
  // return prefix+e.toString().replace(/\//g, '_').replace(/\+/g, '-');
  return result;
} // end of encForOtonomiqCall

List totp(String keycode, int len, int sec) {
  // var keycode = secret code doesn't care space and upper/lowercase (BASE32)
  // return an array,[totp before, totp current]
  // This is algorithm that used in Google Authenticator with len = 6
  var retArray = [];
  var m1 = (DateTime.now().millisecondsSinceEpoch / (sec * 1000)).floor();
  m1 = 54427511; // TODO delete this for production
  Uint8List k3 = hexToUInt8(base32ToHex(keycode.replaceAll(" ", "")));
  final hmac1 = uInt8ToHex(
    hmacSha1(k3, hexToUInt8(m1.toRadixString(16).padLeft(16, "0"))),
  );
  final hmac2 = uInt8ToHex(
    hmacSha1(k3, hexToUInt8((m1 - 1).toRadixString(16).padLeft(16, "0"))),
  );
  int position =
      int.parse(hmac2.substring(hmac2.length - 1, hmac2.length), radix: 16) * 2;
  String s1 =
      (BigInt.parse((hmac2.substring(position, position + 8)), radix: 16) &
              BigInt.from(2147483647))
          .toString();
  s1 = len < s1.length ? s1.substring(s1.length - len, s1.length) : s1;
  retArray.add(s1); // older number goes first
  position =
      int.parse(hmac1.substring(hmac1.length - 1, hmac1.length), radix: 16) * 2;
  s1 =
      (BigInt.parse((hmac1.substring(position, position + 8)), radix: 16) &
              BigInt.from(2147483647))
          .toString();
  s1 = len < s1.length ? s1.substring(s1.length - len, s1.length) : s1;
  retArray.add(s1); // latest number goes second
  return retArray;
} // end of totp

Uint8List hmacSha1(Uint8List hmacKey, Uint8List data) {
  final hmac =
      HMac(SHA1Digest(), 64) // for HMAC SHA-256, block length must be 64
        ..init(KeyParameter(hmacKey));
  return hmac.process(data);
}

Uint8List getSHA3(Uint8List data) {
  final sha3 = SHA3Digest(256);
  return sha3.process(data);
}

String uInt8ToHex(Uint8List ar) {
  String result = "";
  for (var i = 0; i < ar.length; i++) {
    result += ar[i].toRadixString(16).padLeft(2, "0");
  }
  return result;
} // end of uInt8ToHex

Uint8List hexToUInt8(hexString) {
  int resultLen = (hexString.length / 2).ceil();
  List<int> result = [];
  for (var i = 0; i < resultLen; i++) {
    result.add(int.parse(hexString.substring(i * 2, i * 2 + 2), radix: 16));
  } // end for resultLen
  return Uint8List.fromList(result);
} // end of hexToUInt8

String base32ToHex(base32) {
  String base32chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  String bits = "";
  String hex = "";
  for (var i = 0; i < base32.length; i++) {
    int val = base32chars.indexOf(base32[i].toUpperCase());
    bits += val.toRadixString(2).padLeft(5, "0");
  }
  for (var i = 0; i + 4 <= bits.length; i += 4) {
    var chunk = bits.substring(i, i + 4 > bits.length ? bits.length : i + 4);
    hex = hex + int.parse(chunk, radix: 2).toRadixString(16);
  }
  return hex;
} // end of base32ToHex

String getOtqK(int o) {
  // key for autsorz crypto
  return o == 1
      ? "7N4PUB2M6ZM56GXWHJTHTPSPYI36KZFKCTRQHQKI6LCU5HHPGDKPPFDYUPHAK527"
      : "32EGJUG5HNLDUMFR3FCX5T2NF7UVJOQ7C5JM27EN42ULLFBMMV4YSYUTLCAOR5CD";
} // end of getOtqK

Future asyncAppStartup2() async {
  // debugPrint('start asyncAppStartup2');
  actionUnLock('asyncAppStartup2');
  String? myLif = await waitUntilNotNullScreenTx(
    'asyncAppStartup2',
    '#INTERFACE_KEY',
    20,
  );
  if (myLif != null) {
    // Secondary loader. readSettingsStart(opt 2) used to re-fetch every page
    // from Sheets here on each start — two readSS calls (home+system row, then
    // readUIPages all-pages ~181KB) on the endpoint measured at 4-90s with
    // occasional junk bodies. The same pages come from /Proxy in ~1s, so load
    // them there and keep opt 2's side effects 1:1 (runSheetStartup's
    // getLqrList, the inbox re-bind, launchCheck). The Sheets path remains for
    // the sign-in lif — its Page docs carry no 'home', so loadPagesFromProxy
    // refuses it by design — and as fallback whenever the proxy is missing.
    bool proxyOk = false;
    if (myLif != transactionStore.state.screenTx['#GUEST_LIF']) {
      // skipIfUnchanged: a cold start must not re-apply a proxy copy that has
      // not moved since we last applied it — that is what was undoing AppBar
      // refreshes on reopen.
      proxyOk = await loadPagesFromProxy(myLif, skipIfUnchanged: true);
      if (proxyOk) {
        await runSheetStartup(
          myLif,
          '${transactionStore.state.screenTx['#CLUSTER'] ?? ''}',
        );
        await rebindInboxFromStorage();
        await launchCheck();
      }
    }
    if (!proxyOk) {
      await readSettingsStart(myLif, 2);
    }
  } else {
    debugPrint('#INTERFACE_KEY = NULL  in asyncAppStartup2');
  }
  // Ensure FCM is set up on EVERY app start — including warm / auto-
  // authenticated starts where launchCheck / launchCheckDemo (the login-only
  // paths) never run, so setUpFirebase was previously skipped and no push
  // arrived until a fresh run. setUpFirebase is idempotent (guarded).
  await FirebaseNotifications().setUpFirebase();
  // debugPrint('end asyncAppStartup2');
}

// void encryptionTest() {
//   // dynamic keys = location.keys;
//   // for (String k in keys) {
//   //   devPrint ('location [$k] = ${location[k]}');
//   // } // end for location
//   location.forEach((enc, dcp) {
//     // devPrint ('location [$enc] = $dcp');
//     String eec = aecDecrypt(enc, 'l');
//     if (eec != dcp) {
//       devPrint ('wrong => $enc');
//     }
//     // else {
//     //   devPrint('ok => $ec');
//     // }
//   }); // end of location.forEach
//   int d = 1;
// } // end of encryptionTest

// Future writeToSheetRange(
//     String sheetKey, String sheetRange, dynamic val) async {
//   /// Write to google Spreadsheet
//   var state = transactionStore.state.screenTx;
//   if (state['#SHEET_API']) {
//     ValueRange vu = ValueRange.fromJson({"values": val});
//     sheetApi.spreadsheets.values
//         .update(vu, sheetKey, sheetRange, valueInputOption: 'USER_ENTERED');
//   }
// } // end of writeToSheetRange

// void getSheetApi(var _cred) {
//   auth.AuthClient client = auth.authenticatedClient(http.Client(), _cred);
//   sheetApi = SheetsApi(client);
//   transactionStore
//       .dispatch(UpdateScreenTxAction(ScreenTransaction({'#SHEET_API': true})));
// }
