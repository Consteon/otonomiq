import 'dart:io';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ntp/ntp.dart';

import '../api.dart';
import '../global.dart';

const trueLoc = 'true-location';
const fakeLoc = 'fake-location';

class OtqState {
  bool internetOn = false;
  bool gpsOn = false;
  DateTime nowTime = DateTime.now();
  bool trueTime = false; // when abs(ntp time - gps time)<=5 sec
  double latitude = invalidLocation;
  double longitude = invalidLocation;
  double altitude = -88.0;
  int floor = -88;
  double accuracy = 0.0;
  double heading = 0.0;
  double speed = 0.0;
  double speedAccuracy = 0.0;
  DateTime? gpsTimestamp;
  bool mock = true;
  String locationStatus = "No Gps";
  String isoCountryCode = "88"; // ID
  String postalCode = ""; //40174
  String administrativeArea = ""; //Jawa Barat
  String subAdministrativeArea = ""; // Kota Bandung
  String locality = ""; // Kecamatan Cicendo
  String subLocality = ""; // Husen Sastranegara
  String thoroughfare = ""; // Jalan Istana Raya
  String subThoroughfare = ""; // E12
  bool gpsDone =
      false; // when done with gps & placemark reading, this would be true

  Future<void> setInternetData() async {
    try {
      final conn = await InternetAddress.lookup('google.com');
      if (conn.isNotEmpty && conn[0].rawAddress.isNotEmpty) {
        internetOn = true; // got internet connection
      }
    } on SocketException catch (_) {
      internetOn = false; // no connection
    }
  } // end of setInternetData

  OtqState getDataFrom(
    DateTime currentTime,
    Position? pos,
    List<Placemark> myPlace,
  ) {
    gpsDone = false;
    if (pos != null) {
      if (pos.latitude != invalidLocation) {
        latitude = pos.latitude;
        longitude = pos.longitude;
        altitude = pos.altitude;
        floor = pos.floor ?? -99;
        accuracy = pos.accuracy;
        heading = pos.heading;
        speed = pos.speed;
        speedAccuracy = pos.speedAccuracy;
        gpsTimestamp = pos.timestamp;
        mock = pos.isMocked;
        gpsOn = true;
        locationStatus = pos.isMocked ? fakeLoc : trueLoc;
        try {
          // List<Placemark?> myPlace;
          if (myPlace.isNotEmpty) {
            isoCountryCode = (myPlace[0].isoCountryCode) ?? '88';
            postalCode = myPlace[0].postalCode ?? '';
            administrativeArea = cleanupString(
              myPlace[0].administrativeArea ?? '',
            );
            subAdministrativeArea = cleanupString(
              myPlace[0].subAdministrativeArea ?? '',
            );
            locality = cleanupString(myPlace[0].locality ?? '');
            subLocality = cleanupString(myPlace[0].subLocality ?? '');
            thoroughfare = cleanupString(myPlace[0].thoroughfare ?? '');
            subThoroughfare = cleanupString(myPlace[0].subThoroughfare ?? '');
            gpsDone = true;
          } // end if myPlace
        } catch (e) {
          gpsDone = true;
          errorReport(e);
        } // end try placemark
      } else {
        gpsDone = true;
      } // end if pos.latitude != invalidLocation
    } else {
      gpsDone = true;
    } // end if pos != null
    nowTime = currentTime;
    trueTime = true;
    return this;
  } // end of setAllData

  Future<OtqState> setAllData() async {
    DateTime currentTime = nowTime;
    gpsDone = false;
    await getLocation().then((pos) {
      if (pos != null) {
        if (pos.latitude != invalidLocation) {
          latitude = pos.latitude;
          longitude = pos.longitude;
          altitude = pos.altitude;
          floor = pos.floor ?? -99;
          accuracy = pos.accuracy;
          heading = pos.heading;
          speed = pos.speed;
          speedAccuracy = pos.speedAccuracy;
          gpsTimestamp = pos.timestamp;
          mock = pos.isMocked;
          gpsOn = true;
          locationStatus = pos.isMocked ? fakeLoc : trueLoc;
          try {
            // List<Placemark?> myPlace;
            placemarkFromCoordinates(pos.latitude, pos.longitude).then((
              myPlace,
            ) {
              if (myPlace.isNotEmpty) {
                isoCountryCode = (myPlace[0].isoCountryCode) ?? '88';
                postalCode = myPlace[0].postalCode ?? '';
                administrativeArea = cleanupString(
                  myPlace[0].administrativeArea ?? '',
                );
                subAdministrativeArea = cleanupString(
                  myPlace[0].subAdministrativeArea ?? '',
                );
                locality = cleanupString(myPlace[0].locality ?? '');
                subLocality = cleanupString(myPlace[0].subLocality ?? '');
                thoroughfare = cleanupString(myPlace[0].thoroughfare ?? '');
                subThoroughfare = cleanupString(
                  myPlace[0].subThoroughfare ?? '',
                );
                gpsDone = true;
              } // end if myPlace
            }); // end of placemarkFromCoordinates
          } catch (e) {
            gpsDone = true;
            errorReport(e);
          } // end try placemark
        } else {
          gpsDone = true;
        } // end if pos.latitude != invalidLocation
      } else {
        gpsDone = true;
      } // end if pos != null
    }); // end of getLocation

    try {
      final conn = await InternetAddress.lookup('google.com');
      if (conn.isNotEmpty && conn[0].rawAddress.isNotEmpty) {
        internetOn = true; // got internet connection
      }
    } on SocketException catch (_) {
      internetOn = false; // no connection
    } // end of internetOn

    try {
      if (internetOn) {
        try {
          currentTime = await NTP.now().timeout(const Duration(seconds: 2));
          nowTime = currentTime;
          trueTime = true;
        } catch (eNtp) {
          reportNonTimeout(eNtp);
        }
      } // end if internetOn
    } catch (e) {
      errorReport(e);
    }
    return this;
  } // end of setAllData

  Future<OtqState> setAllDataAsync() async {
    // DateTime currentTime = nowTime;
    gpsDone = false;
    // A second, identical `await getLocation()` block used to run here first.
    // It was pure duplicate work: both blocks wrote the same fields, and on the
    // GPS-failure path each one triggered its own Geolocator.getCurrentPosition
    // (getAppGps re-fetches whenever the cached fix is invalidLocation) -- two
    // expensive fixes plus up to two placemarkFromCoordinates calls per
    // attendance tap. The surviving copy below runs inside Future.wait, so the
    // GPS fix now overlaps the internet lookup and the NTP call instead of
    // blocking them. Ordering note: getAppGps reads internetConnected(), which
    // is internetConnectionFlag -- the same flag the lookup below sets. That
    // race already existed for this copy; dropping the earlier sequential block
    // does not add a new one.
    try {
      await Future.wait([
        getLocation().then((pos) async {
          if (pos != null) {
            if (pos.latitude != invalidLocation) {
              latitude = pos.latitude;
              longitude = pos.longitude;
              altitude = pos.altitude;
              floor = pos.floor ?? -99;
              accuracy = pos.accuracy;
              heading = pos.heading;
              speed = pos.speed;
              speedAccuracy = pos.speedAccuracy;
              gpsTimestamp = pos.timestamp;
              mock = pos.isMocked;
              gpsOn = true;
              locationStatus = pos.isMocked ? fakeLoc : trueLoc;
              try {
                // List<Placemark?> myPlace;
                dynamic myPlace = gpsPlaceMark;
                isoCountryCode = (myPlace.isoCountryCode) ?? '88';
                postalCode = myPlace.postalCode ?? '';
                administrativeArea = cleanupString(
                  myPlace.administrativeArea ?? '',
                );
                subAdministrativeArea = cleanupString(
                  myPlace.subAdministrativeArea ?? '',
                );
                locality = cleanupString(myPlace.locality ?? '');
                subLocality = cleanupString(myPlace.subLocality ?? '');
                thoroughfare = cleanupString(myPlace.thoroughfare ?? '');
                subThoroughfare = cleanupString(myPlace.subThoroughfare ?? '');
                gpsDone = true;
              } catch (e) {
                gpsDone = true;
                errorReport(e);
              } // end try placemark
            } else {
              gpsDone = true;
            } // end if pos.latitude != invalidLocation
          } else {
            gpsDone = true;
          } // end if pos != null
        }),
        // end of getLocation
        InternetAddress.lookup('google.com')
            .then((conn) {
              if (conn.isNotEmpty && conn[0].rawAddress.isNotEmpty) {
                internetOn = true; // got internet connection
                internetConnectionFlag.value = true;
              } else {
                internetConnectionFlag.value = false;
              }
            })
            .catchError((Object e) {
              // Offline: lookup throws SocketException. Unguarded it rejects the
              // whole Future.wait below, which the outer catch turns into a
              // Crashlytics non-fatal on every offline call -- pure noise, since
              // Future.wait (eagerError: false) still lets the other two futures
              // finish, so no state is lost. Same guard setInternetData() above
              // already has. Being offline IS the answer here, not an error.
              internetConnectionFlag.value = false;
            }), // end of interAddress.lookup
        getRealTime().then((currentTime) {
          nowTime = DateTime.fromMillisecondsSinceEpoch(currentTime);
          trueTime = true;
        }), // end of NTP
      ]).then((value) {});
    } catch (e) {
      errorReport(e);
    }

    // try {
    //   await Future.wait([
    //     ;getLocation().then((pos) async {
    //       if (pos != null) {
    //         if (pos.latitude != invalidLocation) {
    //           latitude = pos.latitude;
    //           longitude = pos.longitude;
    //           altitude = pos.altitude;
    //           floor = pos.floor ?? -99;
    //           accuracy = pos.accuracy;
    //           heading = pos.heading;
    //           speed = pos.speed;
    //           speedAccuracy = pos.speedAccuracy;
    //           gpsTimestamp = pos.timestamp;
    //           mock = pos.isMocked;
    //           gpsOn = true;
    //           locationStatus = pos.isMocked ? fakeLoc : trueLoc;
    //           try {
    //             // List<Placemark?> myPlace;
    //             await placemarkFromCoordinates(pos.latitude, pos.longitude)
    //                 .then((myPlace) {
    //               if (myPlace.isNotEmpty) {
    //                 isoCountryCode = (myPlace[0].isoCountryCode) ?? '88';
    //                 postalCode = myPlace[0].postalCode ?? '';
    //                 administrativeArea =
    //                     cleanupString(myPlace[0].administrativeArea ?? '');
    //                 subAdministrativeArea =
    //                     cleanupString(myPlace[0].subAdministrativeArea ?? '');
    //                 locality = cleanupString(myPlace[0].locality ?? '');
    //                 subLocality = cleanupString(myPlace[0].subLocality ?? '');
    //                 thoroughfare = cleanupString(myPlace[0].thoroughfare ?? '');
    //                 subThoroughfare =
    //                     cleanupString(myPlace[0].subThoroughfare ?? '');
    //                 gpsDone = true;
    //               } // end if myPlace
    //             }); // end of placemarkFromCoordinates
    //           } catch (e) {
    //             gpsDone = true;
    //             errorReport(e);
    //           } // end try placemark
    //         } else {
    //           gpsDone = true;
    //         } // end if pos.latitude != invalidLocation
    //       } else {
    //         gpsDone = true;
    //       } // end if pos != null
    //     }), // end of getLocation
    //     ;InternetAddress.lookup('google.com').then((conn) {
    //       if (conn.isNotEmpty && conn[0].rawAddress.isNotEmpty) {
    //         internetOn = true; // got internet connection
    //         internetConnectionFlag.value = true;
    //       } else {
    //         internetConnectionFlag.value = false;
    //       }
    //     }), // end of interAddress.lookup
    //
    //     ;NTP.now().timeout(const Duration(seconds: 2)).then((currentTime) {
    //       nowTime = currentTime;
    //       trueTime = true;
    //     }), // end of NTP
    //   ]).then((value) {});
    // } catch (e) {
    //   errorReport(e);
    // }

    return this;
  } // end of setAllDataAsync
} //end of Class OtqState
