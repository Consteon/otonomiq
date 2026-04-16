import '../../global.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../redux/screen_transaction.dart';

 /*
  This part of code is used to contain all code differences between platforms
 */

void setMe(){
  // sinner(ios), andrew(android), windy(window), spider(web)
      andrew = true; // this is android
} // end of setMe

LocationSettings myLocationSetting() {
  late LocationSettings returnValue;
  if (andrew) {
    returnValue = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      // distanceFilter: 1,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 2),
    );
    // WebView.platform = AndroidWebView(); // set default web view platform
  } else if (sinner) {
    returnValue = AppleSettings(
      accuracy: LocationAccuracy.high,
      // activityType: ActivityType.fitness,
      // distanceFilter: 1,
      pauseLocationUpdatesAutomatically: true,
    );
  } else {
    returnValue = const LocationSettings(
      accuracy: LocationAccuracy.high,
      // distanceFilter: 100,
    );
  } // end if Platform
  return returnValue;
} // end myLocationSetting

Future<dynamic> getOsInfo() async {
  dynamic returnValue;
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  if (andrew) {
    returnValue = await deviceInfo.androidInfo;
  } else {
    returnValue = await deviceInfo.iosInfo;
  }
  return returnValue;
} // end getOsInfo

String? getInfo(dynamic osInfo) {
  String? returnValue;
  if (andrew) {
    returnValue = 'os:android${osInfo.version.release};model:${osInfo.manufacturer}-${osInfo.model}';
  } else {
    returnValue = 'os:${osInfo.systemName}-${osInfo.systemVersion};model:${osInfo.model}';
  }
  return returnValue;
} // end getInfo

Future getDeviceIdCore() async {
  var deviceId = '-';
  DeviceInfoPlugin deviceInfo;

  if (transactionStore.state.screenTx['#DID'] != null) {
    deviceId = transactionStore.state.screenTx['#DID'];
  } else {
    try {
      deviceInfo = DeviceInfoPlugin();
      if (andrew) {
        try {
          // TODO need to change to https://pub.dev/packages/android_id
          AndroidDeviceInfo deviceData = await deviceInfo.androidInfo;
          deviceId = deviceData.id ?? emptyString;
        } catch (e) {
          errorReport(e);
        }
      } else if (sinner) {
        IosDeviceInfo deviceData = await deviceInfo.iosInfo;
        deviceId = deviceData.identifierForVendor ?? emptyString;
      }
    } on PlatformException {
      deviceId = '--';
    }
    transactionStore.dispatch(UpdateScreenTxAction(
        ScreenTransaction({'#DID': deviceId}))); //  set #device id
  } // end if (transactionStore.state.screenTx['#DID'] != null)
  return deviceId;
} // end of getDeviceId

void enablePlatformOverride() {
  // if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
  //   debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  // }
} // end _enablePlatformOverride
