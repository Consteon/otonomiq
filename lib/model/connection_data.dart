import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:geocoding/geocoding.dart';
// import 'package:connectivity/connectivity.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ntp/ntp.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';

class ConnectionData {
  bool internetConnection = false;
  bool internet = false; // true = internet connection; false = no connection
  Position? position; // Gps location
  List<Placemark> placeMark = List.empty();
  int time = 0;
  int trueTime =
      0; // -1 = false; 0 = unknown; 1 = true time because automatic time = true

  Future<ConnectionData> getConnection(
    bool ntp,
    bool loc, {
    bool awaitImages = true,
  }) async {
    // dynamic state = transactionStore.state.screenTx;
    // bool lastConnectionStatus = await internetConnectedCheck();
    bool lastConnectionStatus = internetConnectionFlag.value ? true : false;
    ConnectionData result = ConnectionData();
    // List<Placemark> pm;
    result.internet = false;
    result.trueTime = 0;
    result.time = 0;
    try {
      final conn = await InternetAddress.lookup('google.com');
      if (conn.isNotEmpty && conn[0].rawAddress.isNotEmpty) {
        internetConnectionFlag.value = true;
        internetConnection = true;
        result.internet = true; // got internet connection
        if (settingKey != null &&
            transactionStore.state.screenTx['#CLUSTER'] != null) {
          runSheetStartup(
            settingKey,
            transactionStore.state.screenTx['#CLUSTER'],
          );
        }
        debugPrint('>>>>> Internet is connected');
      } else {
        internetConnectionFlag.value = false;
        debugPrint('>>>>> Internet is not connected');
      }
    } on SocketException catch (_) {
      result.internet = false; // no connection
      internetConnectionFlag.value = false;
    }
    // if (result.internet) {
    if (loc) {
      try {
        await getLocation(); // get gps location
        result.position = positionCopy(gpsData);
        result.placeMark = [placeMarkCopy(gpsPlaceMark)];
        result.time = gpsTime.value;
      } catch (ep) {
        errorReport(ep);
      } // end try getLocation
    } // end if loc

    if (internetConnected() && ntp) {
      try {
        DateTime n = DateTime.now();
        try {
          n = await NTP.now().timeout(const Duration(seconds: 2));
        } catch (e) {
          reportNonTimeout(e);
        }
        result.time = result.time == 0 ? n.millisecondsSinceEpoch : 0;
      } catch (eNtp) {
        errorReport(eNtp);
      }
    } // end if ntp

    // if (!lastConnectionStatus && internetConnectionFlag.value) {
    getAppGps();
    debugPrint('run historySync.');
    if (awaitImages) {
      await sendImagesInImageMap(); // send unsent images in imageMap to firebase storage
    } else {
      // non-blocking on refresh: images still upload (mutex-locked + retry), just
      // don't block. .catchError so an un-awaited rejection can't become fatal.
      sendImagesInImageMap().catchError((e) {
        reportNonTimeout(e);
      });
    }
    historySync('Connection Data', false);
    // }
    // } else {
    //   // else internet
    //   debugPrint('Internet is not connected');
    //   result.time = DateTime.now().millisecondsSinceEpoch;
    //   if (internetConnectionFlag.value) {
    //     // internet just got disconnected
    //   } // end if state['#INTERNET']
    // } // end if internet
    internetConnectionFlag.value = internetConnection;
    result.internet = internetConnection;
    await transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({'#INTERNET': internetConnection}),
      ),
    );
    debugPrint(
      '>>> internetConnected=${internetConnectionFlag.value}, internetConnection = $internetConnection',
    );
    return result;
  } // end of getConnection
} // end of ConnectionData
