import '../../global.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../redux/screen_transaction.dart';

/*
  This part of code is used to contain all code differences between platforms
 */

void setMe() {
  // sinner(ios), andrew(android), windy(window), spider(web)
  sinner = true; // this is for ios
} // end of setMe

LocationSettings myLocationSetting() {
  late LocationSettings returnValue;
  returnValue = AppleSettings(
    accuracy: LocationAccuracy.high,
    // activityType: ActivityType.fitness,
    // distanceFilter: 1,
    pauseLocationUpdatesAutomatically: true,
  );
  return returnValue;
} // end myLocationSetting

Future<dynamic> getOsInfo() async {
  dynamic returnValue;
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  returnValue = await deviceInfo.iosInfo;
  return returnValue;
} // end getOsInfo

String? getInfo(dynamic osInfo) {
  String? returnValue;
  returnValue =
      'os:${osInfo.systemName}-${osInfo.systemVersion};model:${osInfo.model}';
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
      IosDeviceInfo deviceData = await deviceInfo.iosInfo;
      deviceId = deviceData.identifierForVendor ?? emptyString;
    } on PlatformException {
      deviceId = '--';
    }
    transactionStore.dispatch(UpdateScreenTxAction(
        ScreenTransaction({'#DID': deviceId}))); //  set #device id
  } // end if (transactionStore.state.screenTx['#DID'] != null)
  return deviceId;
} // end of getDeviceId

void enablePlatformOverride() {
} // end _enablePlatformOverride
