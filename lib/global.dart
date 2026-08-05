import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
// import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:intl/intl.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'different_code/different_code.dart';
import 'firebase_notification_handler.dart';
import 'global2.dart';
import 'login/api/user_repository.dart';
import 'model/connection_data.dart';
import 'model/general_get_controller.dart';
import 'model/lock.dart';
import 'part/build_part/channel.dart';
import 'redux/screen_transaction.dart';
import 'redux/screen_transaction_reducers.dart';
import 'route_stack.dart';
import 'states/app_code_controller.dart';
import 'widget/driver_home_support.dart';

// import 'crypto/auth_crypto.dart';
//import 'package:pointycastle/pointycastle.dart';  // full registry

/*
  0.9.32.01 (240918) HH : upload to apple store
  0.9.32.02 (240918) HH : update firebase plugin version
  0.9.32.03 (240928) HH : ios 18
  0.9.32.04 (241003) HH : fix ios txf scan, use html_widget again,
                          modify AppDelegate.swift for firebase initialization
  0.9.32.05 (241004) HH : fix cancelled qr and checker qr scan
  0.9.32.06 (241005) HH : fix ios checker qr scan
  0.9.32.07 (241010) HH : fix checker and selfie. Maximize location stream
  0.9.32.08 (241010) HH : fix ios checker bug, save image as local in history (prepareImageAsLocal)
  0.9.32.09 (241010) HH : fix unique file name in image, using Uuid().v4() random string
                          fix getLocation wait for 5 seconds bug
  0.9.32.10 (241011) HH : fix .jpg.jpg in image name, fix cancel lqr
  0.9.32.11 (241014) HH : fix error 801, change most of settingUp to
                          oldSettingUpShouldBeDeleted, except the one in serverSetup
  0.9.32.12 (241015) HH : modify if qr-single then not go to selfie if wrong location
                          fix otq_state.getLocation()
  0.9.32.13 (241021) HH : fix text overflow in checker and hgr, fix red light in single-qr
  0.9.32.14 (241023) HH : redo as  0.9.32.13
  0.9.32.15 (241028) HH : release version of 0.9.32.14
  0.9.33.01 (241028) HH : release version of 0.9.33
  0.9.33.02 (241030) HH : android version of 0.9.33.01
  0.9.34.01 (241102) HH : run in ipad, upgrade ke ios 15.5.0 minimum
  0.9.34.02 (241103) HH : Revert back to ios 14.0 minimum, build for ios 18.1
  0.9.35.01 (241107) HH : remove code for android, in ios version (required by apple)
                          create channel.dart in part/build_part
  0.9.35.02 (241108) HH : fix wrong ios (sinner) boolean test in api.dart
  0.9.35.03 (241112) HH : debug gps position 888 in
                            Redmi Note 9 -- android 12
                            Redmi 7A -- Android 10, MIUI 12.5.2
                            Xiomi A1 -- Android 9
  0.9.35.04 (241113) HH : fix in getAppGps, put 888.999 in catch segment
  0.9.35.07 (241113) HH : fix getAppGps
  0.9.35.08 (241114) HH : fix locRange
  0.9.36.03 (241114) HH : android 0.9.36 release
  0.9.37.01 (241114) HH : iOS 0.9.37 release
  0.9.37.02 (241114) HH : android cli test
  0.9.39.01 (241114) HH : resubmit app store
  0.9.39.02 (241114) HH : release android play store
  0.9.40.01 (241213) HH : generator test
  0.9.41.01 (241226) HH : fix bundle name
  0.9.44.01 (241230) HH : new version to test app generator
  0.9.45.01 (250105) HH : new version to test app generator
  0.9.46.01 (250105) HH : new version to test app generator
  0.9.47.01 (250111) HH : try new debug.keystore
  0.9.50.01 (250115) HH : revise google-services.json
  0.9.51.01 (250120) HH : iOS 18.2 support
  0.9.52.01 (250311) HH : aum__ processing, add imageMap
  0.9.53.01 (250316) HH : send image in 1 minute ++, lock imageMap record
  0.9.54.01 (250316) HH : turn clearHistory to true. delete loadHistory from asyncAppStartup
  0.9.55.01 (250320) HH : speed up loading in internet connect. fix calling appStartup2
  0.9.56.01 (250322) HH : fix firebase write in loadHistory when offline
  0.9.57.01 (250322) HH : tweak await in loadHistory => faster, clearHistory = false
  0.9.58.01 (250322) HH : prevent replacing same image in firebase storage
  0.9.59.01 (250322) HH : send and clear history in main_page[483] for debugging
  0.9.60.01 (250401) HH : add forceSend in historySync. Add rbt action sendHistory. still have red button at top bar
  0.9.61.01 (250401) HH : fix image not send debug. add dialog box in sendHistory and archive history
  0.9.62.02 (250401) HH : add clear history icon, handle sublist bug in history
  0.9.62.03 (250404) HH : add temporary historyFix function to handle sublist bug in history
  0.9.63.01 (250405) HH : try to history sync after each successful sendImagesInImageMap
  0.9.63.01 (250405) HH : add imageLock as locking mechanism for imageMap
  0.9.63.01 (250405) HH : fix imageLock.unlock bug. alter imageMap[key][4] in sendImageInImageMap
  0.9.66.01 (250408) HH : fix history error.
  0.9.67.01 (250409) HH : fix send image bug
  0.9.69.01 (250410) HH : cleanup for release
  0.9.70.01 (250414) HH : fix history sync on offline gps & placemark
  0.9.71.01 (250414) HH : add locking mechanism in uploadToCloudStorage function
  0.9.72.01 (250414) HH : delete await dataOK(context) in getImage and attendance_qr_selfie_gps_verify
                          Flutter version 3.22.1 on channel stable at /Users/harryhuang/development/flutter
  0.9.73.01 (250423) HH : release
  0.9.74.01 (250630) HH : multiScanWidget, add multiScanWidget to widget list
  0.9.75.01 (250718) HH : fix multiScanWidget, modify txf for aqr.
                          tableVid for aqr in otq_txf and multiScanQR is hardcoded to otonomiq's
  0.9.75.03 (250731) HH : add FtzBluetoothPrinter widget
  0.9.75.04 (250805) HH : write to table from multiScanWidget
  0.9.75.07 (250806) HH : write to 'A' table from rbt with parameter in table name
  0.9.75.08 (250811) HH : fix searchtable txf bug. last backup before move to flutter 3.32
                        : current version 3.22.1
                          to upgrade : flutter upgrade
                          to downgrade : flutter downgrade v3.22.1
  0.9.75.09 (250811) HH : use flutter 3.32.8
  0.9.75.10 (250812) HH : backup
  0.9.75.12 (250813) HH : update plugins
  0.9.75.13 (250813) HH : rebuild
  0.9.75.14 (250814) HH : remove android:maxSdkVersion="30"
            in <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  0.9.75.16 (250814) HH : downgrade geolocator from 14.0.2 => 13.0.1 to test tolerance
  0.9.75.17 (250820) HH : update autheniumDecode to fix '_25FC_' <= black square
  0.9.75.18 (250820) HH : debug image path, error 13
  0.9.76.02 (250821) HH : release version 0.9.76
  0.9.77.01 (250821) HH : google sign in no scope, released version
  0.9.78.01 (250828) HH : add NUMBER widget
  0.9.78.02 (250831) HH : fix searchTable and NUMBER bug, add variant "send' to rbt
  0.9.78.03 (250831) HH : add width, height, buttonColor, textColor to rbt
  0.9.78.04 (250831) HH : correction of TXF money, * in format, and keyboard with decimal
  0.9.78.05 (250903) HH : MultiScan wait for load table. disable for :
                          MultiScanWidget, OtqTxf
  0.9.78.06 (250903) HH : Gagal Scan di widget multiScanQRToggle di autsorz proxy
            Save Table di widget RBT di autsorz proxy
            penamaan tabel pakai no DO
            Enable disable widget, supaya ga bisa diubah lagi setelah ditulis
            definisi tanggal ◁6|T"&System!$B$3&"|Ddd MMM yyyy▷
            bikin Clear data dan balik ke halaman yang itu lagi misaln button create new DO
            Cetak Invoice
            widget PRN untuk width ditambah lebarnya jadi full screen
  0.9.78.07 (250908) HH : add summarize table, fix getImage disable, fix txf disable
  0.9.78.08 (250909) HH : fix multiscan disable bug, rbt clear,
            rbt get_gps, get_address, get_radius. add FtzDisplayImages.
  0.9.78.10 (250911) HH : from flutter 3.32.8 to flutter  3.35.3
             com = con in txf. edit to consteon
  0.9.78.12 (250912) HH : fix normalizeTableName bug in otz_txf.dart
  0.9.78.15 (250913) HH : fix price with :;, fix print & summary
  0.9.78.16 (250923) HH : fix dynamic table master.doc with index format in rbt'addTable:
                          ... ⭘index◼3★S◼6★S⭘ ... => index field 3 as string,
                          index field 6 as string . Flutter 3.35.4
  0.9.78.17 (250930) HH : fix MultiScanWidget data bug, drd disable, read table filter
  0.9.78.19 (251005) HH : add retry in writeToStaticTable
  0.9.78.20 (251023) HH : fix txf-static, txf-null bug, txf-display selection bug
  0.9.78.21 (251115) HH : backup source code before update cryptography
  0.9.78.22 (251118) HH : fix pointycastle and bluetooth plugins. add license menu
  0.9.78.23 (251202) HH : add indexStart parameter in txf
  0.9.78.24 (251207) HH : fix indexStart bug in txf, add  update in txf
  0.9.78.25 (251209) HH : fix update bug in txf with indexStart for static table (A)
                          fix datetime selection, save default time to final
                          get: ^4.7.2 -> ^4.7.3
  0.9.78.26 (251212) HH : fix rbt updateTable
  0.9.78.27 (260111) HH : fix android secure storage key change (by android)
                          in debug count 34 (Error 801-34)
  0.9.78.28 (260424) HH : update attendance_qr_selfie_gps_verify, ftz_row_of_button,
                          otq_txf, to response to fakeGpsAllowed, outPositionAllowed and addition text
                          updated by OO
  0.9.78.29 (260428) OO : add time_presence, progress_bar, location_detector, tasklist, button_choice
                          update to otq_rdo_new, otq_txf_new.
  0.9.78.30 (260507) OO : update dart files: api, table_repository, mobile_table_controller
                          attendance_qr_selfie_gps_verify, ftz_row_of_button_2, otq_rdo_2,
                          otq_txf_2, progress_bar, location_detector, tasklist,
                          ftz_checker, build_display_component
  0.9.78.31 (260519) OO : pubspec yaml : file_picker: ^8.1.7.
                          add: worker_card_detail, otq_bottom_nav_bar, approver_sticky_bar,
                          approval, approval_detail
                          edit : tasklist, selectable_btn, photo_camera,
                          otq_txf2, otq_get_image_2, location_detector,
                          ftz_row_of_button2, ftz_autonumber, comment_detail,
                          attendance_qr_selfie_gps_verify, stl_page, main_page,
                          home_page, any_page, login_form, google_login_button,
                          apple_login_button
  0.9.78.32 (260522) OO : udpate approval, etc
  0.9.78.33 (260526) OO : update request incident, fix bug log history
  0.9.78.34 (260602) OO : fix bug front camera stuck, blank white screen when open apps, implement addToEvent to Firestore
  0.9.78.35 (260602) OO : fix bug in attendance_qr_selfie_gps_verify
  0.9.79.01 (260604) OO : Release (cancelled)
  0.9.79.02 (260605) OO : fix loading bug
  0.9.80.01 (260609) OO : Release
  0.9.80.02 (260702) OO : update flutter 3.44.4, add module driver runtime, admin runtime, warehouse runtime, loading splash screen, 
                          implement firebase crashlytics, fixing bug ftz_array_search, fixing bug data history patrol, cleanup unused file
  0.9.82.01 (260702) HH : update plugins
  0.9.82.02 (260703) HH : update plugins
  0.9.83.01 (260703) OO : bug fix
  0.9.83.02 (260713) OO : fix splash screen, fix photo camera, login phone match, add flutter_native_icons, offline, trip sequence driver,
                          print thermal bluetooth, nfc reader,
  0.9.84.02 (260714) OO : fix layout nfc reader, fix get cache data after close app, default value pickup and drop in admin runtime, 
                          implement local auth in attendance qr
  0.9.84.03 (260724) OO : fcm notification single and broadcast, notif ui, message list, asset stock, task feed list, 
                          fix stuck capture camera, crashlytics fix, search in contact picker, map point picker, group picker, share pdf, whatsapp send,
  0.9.84.04 (260729) OO : fix bug login, add get image gallery, stat card row, payout list widget
  0.9.85.01 (260730) HH : update version number
  0.9.85.02 (260731) OO : fix bug approval, driver modul, notification list chips
  0.9.86.01 (260801) OO : update version number
  0.9.87.01 (260802) OO : update version number
  0.9.87.04 (260805) HH : update version number
  0.9.88.01 (260805) OO : add feature adhoc in driver runtime, redesign report, log, improve login and mobile refresh
*/

// ========= Constants ==========================
const iOSDevPage = false;
final launchTime = DateTime.now().millisecondsSinceEpoch;
const clearHistory =
    false; // clear history on launch, true = for debugging, false = production
int debugTime = launchTime;
String defaultCountry = '62'; // indonesia, change this later
int debugCount = 0;
const String version = '0.9.88';
const String subVersion = '.01';
// String versionShown = ''; // use this for production
const retentionDefault = 30160; // default retention period in seconds = 35 days
String versionShown = version + subVersion; // use this for debugging & testing
bool andrew = false;
bool windy = false;
bool spider = false;
bool sinner = false;
// const int otonomiqVid = 60936087747650;
// const int consteonVid = 60936087747650; // otonomiq
const int consteonVid = 20342033315492; // consteon
const emptyString = '--';
const body = 'body'; // for body of https request
const defaultConfiguration = {'1': ''};
const int qrLoop = 1; // # of attempt to get right qr, before selfie
const defaultFinalSaveCounter = 2; // seconds
const String functionFront = 'asia-northeast1-otq-01.cloudfunctions.net';
const String eventFunctionName = 'processEvent2';
const String historyName = '_HISTORY';
const String imageMapSecureName = '_IMAGEMAP';
const localImagePrefix = 'aum__';
const localImagePostfix = '__mua';
const invalidPathPrefix = 'aum__InvalidImagePath-';
const invalidPathPostfix = localImagePostfix;
const emptyImageUrl = '$localImagePrefix$emptyString$localImagePostfix';
const localImageArtifact = 'OTQC';
const localImageBeginningFolderDivider = 'FTZIMG'; // Starting of a folder
const readyColor = Colors.green;
const notReadyColor = Colors.red;
const localImageFolderSeparator = '___';
const thisAppName = appName;
List<dynamic> asHomeArray = [];
bool historyTableIsLocked = false; // lock history when history is being written
bool historySyncIsLocked = false; // lock for history sync function
final historySyncLock = Lock(); // lock for history sync
late dynamic internetConnection;
String loginSsid =
    '18MAwk8_l2ADCpuOPaQAzMykDpTZZhVFjP1n5Kcn_RTk'; // guest proxy
Map<String, dynamic> imageMap =
    {}; // imageMap for saving image to firebase storage
const int maxImageUploadRetry = 5; // max retry to load image
int imageMapMaxDayAge = 31; // max age (day) of image in imageMap
const int imageMapLockExpiration = 30000; // lock expiration in milliseconds
const Duration imageUploadInterval = Duration(
  minutes: 1,
); // interval for imageMap upload check
final imageLock = Lock(expirationIntervalSeconds: 15); // lock for imageMap
final imageSendLock = Lock(queueMax: 1); // lock for sendImagesInImageMap
final imageFirebaseLock = Lock(
  expirationIntervalSeconds: 15,
); // lock for firebase image upload
// ==============GetX state management
RxMap<String, bool> tableSourceUpdated = {
  'default': false,
}.obs; // State management for table
RxMap<String, dynamic> tableContent = {
  'default': [],
}.obs; // content of table in ready to use array
// Char-code map subcollections (e.g. `site`, `workforce`): each entry is a list
// of raw Firestore doc maps (NOT positional `c`-arrays like `tableContent`).
RxMap<String, List<Map<String, dynamic>>> mapTableContent =
    <String, List<Map<String, dynamic>>>{}.obs;
final displayRefresher = true.obs; // change this for updating screen
final internetConnectionFlag = false.obs; // read by internetConnected()
final transactionOKFlag = false.obs; // read by transactionOK()
// final appStatusColor = notReadyColor.obs; // application status color
final gpsTime = 0.obs; // gps time
Position gpsData = Position(
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
); // gpsdData will be updated along with gpsTime
int time2GpsOffset =
    0; // = gpsTime - currentTime; currentTime+time2GpsOffset = gpsTime
Placemark gpsPlaceMark = const Placemark(
  name: emptyString,
  street: emptyString,
  isoCountryCode: invalidCountry,
  country: invalidCountry,
  postalCode: emptyString,
  administrativeArea: emptyString,
  subAdministrativeArea: emptyString,
  locality: emptyString,
  subLocality: emptyString,
  thoroughfare: emptyString,
  subThoroughfare: emptyString,
); //gpsPlaceMark will be updated along with gpsTime
// =================== end of GetX state management

// ========= Color and Theme ===================
final Map<String, dynamic> colorMap = {};
// ========= End of Color and Theme ===================

Map<String, String> tableHeader = {'default': ""}; // table header
Map<String, String> tableType = {'default': "A"}; // table type
dynamic needUpgrade;
dynamic topCollection;
bool mobileLayout = true;
var sha3_256Registry = SHA3Digest(256);
//var sha3_512Registry = SHA3Digest(512);
late int dhP; // Diffie Hellman p parameter
late int dhG; // Diffie Hellman g parameter
bool demoApp =
    demoVersion; // determine from different_code.dart whether a demo or not
bool devMode = devModeConst; // true : using devSystem; false using system
dynamic bitIcon; // 64 bit
String appLogVersion = '1.0.11';
String appsCode = appsKey; // Apps key that identify this code
String getSettingUrl =
    'https://us-central1-collanium1-4babc.cloudfunctions.net/getAgeniaSettings';
String cloudFunctionDomain = "us-central1-collanium1-4babc.cloudfunctions.net";
var resetString = 'k5lok4K987J'; //= used in v_crypto.dart argon
String cloudFunctionName = "/getPoxSettings";
String linkSettingFunctionName = "/getLinkSettings";
String getNewVidFunctionName = "/getNewVid";
String runIFunctionName = "/runInstruction";
String runI1FunctionName = "/runInstruction1";
String runI2FunctionName = "/runInstruction2";
//String appSettingFunctionName = "/${functionName['appSettings']}";
String appSettingFunctionName = empty;
String autsorzFunctionDomain = "--";
String resetVidName = "--";
const String folderSeparator = "//"; // separator for folder in table name
int sheetSystemLength = 0;
dynamic keyboardLength;
dynamic fromLink; // sheet to append
String rangeLink = "--";
dynamic vidRange;
dynamic lifSetting2;
dynamic lifSetting;
dynamic paramRange;
dynamic rootThis; // Main page
//const errorPageFront = '{"title":"vertika.id","children":[{"type":"HTML","leftRightPadding":0,"beforeSpacing":0,"afterSpacing":0,"data":"<img src=\'https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/vertriz%2Fc%2Fvertika-brand-1000x99.png?alt=media&token=bf91f95d-8eb7-4543-a246-d491616842b7\'</img><h6> </h6><h4>#VERTIKA</h4><h6> </h6><h2>--Halaman ini sedang diperbaharui--</h2>"}]}';
// var errorPageFront;
// var errorPageEnd;
dynamic errorPage;
dynamic errorUrl;
dynamic linkUrls;
dynamic legalPage;
dynamic invitationPage;
dynamic newPinPage;
late GoogleSignIn vGoogleSignIn;
// GoogleSignIn vGoogleSignIn = GoogleSignIn(
//   scopes: [
//     'https://www.googleapis.com/auth/drive',
//     'https://www.googleapis.com/auth/drive.appdata',
//     'https://www.googleapis.com/auth/spreadsheets',
//     'https://www.googleapis.com/auth/contacts.readonly',
//   ],
// );
GoogleSignInAccount? currentUser;
dynamic vSetting;
dynamic settingKey;
dynamic userKey;
dynamic uiKey;
dynamic aTheme;
const String empty = "--";
const String errorString = "Error";
const formatErrorString = '*';
final String checkMark = String.fromCharCode(8730); // checkmark character
// final String fromLinkSeparator = String.fromCharCode(9670);
final List<String> separator = [
  String.fromCharCode(11044), // 0 Black circle
  String.fromCharCode(9670), // 1 Black diamond
  String.fromCharCode(9724), // 2 Black square
  String.fromCharCode(9733), // 3 Black star
  ',', // 4 Separator within widget parameter
  String.fromCharCode(9671), // 5 white diamond
  String.fromCharCode(9734), // 6 white star
  String.fromCharCode(9313), // 7 circle 2
  String.fromCharCode(11096), // 8 white hollow circle
];
final blackDiamond = separator[1];
final whiteDiamond = separator[5];
const atiCode =
    '.\u{0F13}ati'; // internal code to mark a string. Put in the beginning
const List<String> forbiddenCharacter = [
  '\u{25C6}', // 0 black diamond
  '\u{25C7}', // 1 white diamond
  '\u{25C8}', // 2 inside diamond
  '\u{2B24}', // 3 black big circle
  '\u{2B58}', // 4 white big circle
  '\u{25FC}', // 5 black square
  '\u{25FB}', // 6 white square
  '\u{25C0}', // 7 black left triangle
  '\u{25C1}', // 8 white left triangle
  '\u{25B6}', // 9 black right triangle
  '\u{25B7}', // 10 white right triangle
  '\u{25CB}', // 11 white small circle
  '\u{25CF}', // 12 black small circle
  '\u{2605}', // 13 black star
  '\u{2606}', // 14 white star
  '\u{2A1D}', // 15 white N-ary vector
  '\u{2460}', // 16 circle 1
  '\u{2461}', // 17 circle 2
  '\u{2462}', // 18 circle 3
  '\u{2463}', // 19 circle 4
  '\u{2464}', // 20 circle 5
  '\u{2465}', // 21 circle 6
  '\u{2466}', // 22 circle 7
  '\u{2467}', // 23 circle 8
  '\u{2468}', // 24 circle 9
  '\u{2469}', // 25 circle 10
  '\u{246A}', // 26 circle 11
  '\u{246B}', // 27 circle 12
  '\u{246C}', // 28 circle 13
  '\u{246D}', // 29 circle 14
  '\u{246E}', // 30 circle 15
  '\u{246F}', // 31 circle 16
  '\u{2470}', // 32 circle 17
  '\u{2471}', // 33 circle 18
  '\u{2472}', // 34 circle 19
  '\u{2473}', // 35 circle 20
];
// final String fromLinkSeparator = separator[1];
int star = separator[3].codeUnitAt(0);
final String plusMinus = String.fromCharCode(177);
Map<String, Widget> linkPage = {}; // list of pages
Map<String, List<Widget>> linkElement = {}; // list of page elements

bool allPagesBuilt =
    false; // status of any pages other than home. On Refresh(dev) this var should be set to false
bool allPagesReady =
    false; // would be true when all pages already built in poxPage
String systemJsonRange = "--";
String screenJsonRange = "--";
String mobile = 'Mobile';
String theme = 'ThemeAgenia';
String locale = 'Locale';
String locRange = empty;
String fsCollection = empty;
String fsMsgCollection = empty;
String firestoreEventCollection = empty;
String lastEventCollection = empty;
String eventDoc = empty;
late SheetsApi sheetApi;
dynamic dio;
late AppCodeController appCodeController;
//final GeneralGetXController getXController = GeneralGetXController(); // general GetX controller for controlling widget rebuild
dynamic minYear; // earliest date = 1 Jan 1900
int maxPlusYear = 20; // latest date = current year + 20 years
DateTime refDate = DateTime(1899, 12, 30); // google sheet base date = 1900,1,1
String shortDateFormat = 'dd/MM/yyy';
String dateTimeFormat = 'dd MMM yyyy HH:mm';
//Soundpool pool = Soundpool({StreamType streamType = StreamType.notification, int maxStreams = 1})
int scannerBeep = 0; // beep id defined in main
ScrollController myScrollController = ScrollController(keepScrollOffset: true);
dynamic systemUIComponent; // list of system JSON
dynamic screenUIComponent; // list of screen JSON
dynamic linkTransaction; // list of transaction
dynamic oVid;
dynamic oPin;
dynamic refreshFlag;
var functionName = {}; //= List of function name
var functionDomain = {}; //= List of function domain by country code
var storageBucket = {}; //= List of bucket by country code

Map<Key, dynamic> inputTxt = {}; // k = txf key, v = input string value
Map<Key, dynamic> inputList = {}; // k = form key, v = array of inputlist
Map<Key, int> inputInt = {}; // k = GlobalKey, v = input int, for radio, etc
RouteStack routeStack = RouteStack(home);
dynamic storage;
dynamic secureStorageOptions;

dynamic firestoreDb;
dynamic firestoreCollection;
dynamic
firestoreIO; // firestore collection for IO for this vid user/92343234234/io
dynamic
firestoreMsg; // firestore collection for msg for any particular users/<my vid>/io/<other's vid>/msg
dynamic firestoreNotif;
dynamic transactionStore;
String fsDeviceSubCollection = 'dvc'; //= device collection in user's uid doc
String msgPrefix = "msg_";

/// The user's inbox collection: `msg_<cluster>/<msgDocId>/io`.
/// One place, because the background-isolate bridge used to hardcode `msg_`
/// while everything else went through [msgPrefix].
String msgIoPath(String cluster, String msgId) =>
    '$msgPrefix$cluster/$msgId/io';
const defaultCluster = "DEV2";
//const defaultCluster = "TEST1";    // comment this and uncomment DEV2
const eventPrefix = "evnt_";
const tableDirectory = 'TableDirectory';
const mobileTable = 'MobileTable';
const mobileTableCollection = 'tables';
const mobileTableContent = 'content';
//const eventPrefix = "test_"; // comment this for production
const String fsName = 'a1'; //= hard coded top user collection;
bool timeInit = true;
bool appStartupRun = false;
const qrQ = '38383838';
const home = 'home';
const defaultImage =
    'https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/vertriz%2Fc%2Fmekaar-90x90.png?alt=media&token=998fac83-0ead-4252-b7d1-d9dad4ce139e';

dynamic textList = {};
Map<dynamic, dynamic> localeText = {}; // text from proxy Locale!B17:C
double dialogHeight = 120.0;
dynamic location = {};
const invalidLocation = 888.8888888;
const String invalidCountry = '88';
final invalidTime = DateTime(1970, 1, 1);
final GlobalKey<ScaffoldState> mainScaffoldKey = GlobalKey<ScaffoldState>();
var globalRandom = Random.secure();
late SharedPreferences prefs;
late StreamSubscription<Position> positionStreamSubs;
Timer? gpsSaveTimer;
dynamic positionStream;
//final navigatorKey = GlobalKey<NavigatorState>();
//final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const a64 = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
  'x',
  'y',
  'z',
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '-',
  '_',
];
const proxyCollectionName = 'Proxy';
const eventCollectionName = 'Event';

Future<int> globalInit() async {
  setMe();
  debugCount = -21;
  trace(debugCount);
  versionShown = versionShown == ""
      ? (devMode ? "$version $subVersion" : "")
      : versionShown;
  Get.put(WidgetUpdateController());
  vGoogleSignIn = GoogleSignIn.instance;
  unawaited(vGoogleSignIn.initialize());
  if (sinner) {
    secureStorageOptions = const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    );
    storage = FlutterSecureStorage(
      iOptions: secureStorageOptions,
    ); // secure storage : myLIf, pinHash, myAcc, myHub

    // vGoogleSignIn = GoogleSignIn();
    // scopes: [
    //   'https://www.googleapis.com/auth/drive',
    //   'https://www.googleapis.com/auth/drive.appdata',
    //   'https://www.googleapis.com/auth/spreadsheets',
    //   'https://www.googleapis.com/auth/contacts.readonly',
    // ],
    // clientId:
    //     '721538991284-iet4kp21754cj1ve7a78dpml9p6lps60.apps.googleusercontent.com',
    // );
  } else {
    // migrateWithBackup: guard one-time 9.x->10.x cipher migration — kill mid-
    // migration without it permanently wipes session/tenant keys (resetOnError).
    storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(migrateWithBackup: true),
    );
    // vGoogleSignIn = GoogleSignIn();
    // scopes: [
    //   'https://www.googleapis.com/auth/drive',
    //   'https://www.googleapis.com/auth/drive.appdata',
    //   'https://www.googleapis.com/auth/spreadsheets',
    //   'https://www.googleapis.com/auth/contacts.readonly',
    // ],
    // );
  }
  //========= Color
  colorMap['enabled'] = Colors.blueAccent;
  colorMap['disabled'] = Colors.grey;
  colorMap['cancel'] = Colors.red;
  colorMap['ok'] = Colors.green;
  colorMap['error'] = Colors.red;
  colorMap['wait'] = Colors.red;
  colorMap['ready'] = Colors.red;
  colorMap['notReady'] = Colors.red;
  //========= End of Color
  //============= Text Asset ==============
  textList["ErrorPrefix"] = "#Error";
  textList['GeneralError'] = 'General Error';
  textList["QRError"] = "QR Error";
  textList["QRNotListed"] =
      "QR tidak terdaftar, tetapi data tetap akan disimpan.";
  textList["QRNotListed2"] = "QR tidak terdaftar";
  textList["QRIsWrong"] =
      "QR tidak sesuai untuk aplikasi ini, data tidak disimpan.";
  textList["LocNotListed"] = "Belum terdaftar";
  textList["NeedGreen"] = "Perlu menunggu lampu status menjadi hijau.";
  textList["AlertTitle"] = "Tunggu";
  textList["OK"] = "Ok";
  textList["ExitConfirmation"] = "Ingin menutup aplikasi? Tekan [Tutup].";
  textList["Cancel"] = "Batal";
  textList["Exit"] = "Tutup";
  textList["GpsProblem"] =
      "Permasalahan di GPS. Anda harus menyalakan GPS setting di hp anda, matikan battery saver, dan matikan aplikasi yang memalsukan lokasi GPS.";
  textList["ScreenShot"] =
      "Tolong screenshot layar ini dan kirimkan ke administrator anda.";
  textList["Retry"] = "Gagal, coba ulangi sekali lagi.";
  textList["Fail"] = "Gagal";
  textList["ErrorLoading"] =
      "Server sedang penuh, coba lagi beberapa waktu kemudian.";
  textList["NoInternet"] =
      "Anda tidak memiliki koneksi internet atau koneksi internet lambat. Harap tutup aplikasi, periksa dan perbaiki koneksi internet anda dan ulangi.";
  textList["NoInternetTitle"] = "Koneksi internet terputus";
  // textList["802"] =
  //     "Anda tidak bisa masuk lagi karena ada perangkat yang terhubung dengan akun ini. Sebuah email telah dikirimkan ke email anda. Silahkah ikuti petunjuk di email tersebut untuk me-reset akun anda.";
  textList["802"] =
      "Anda mencoba masuk di perangkat lain. Untuk faktor keamanan, anda hanya dapat menggunakan satu akun saja pada satu perangkat. Anda perlu otentifikasi ulang jika ingin masuk di perangkat lain.";
  textList["NoPosition"] = "Tidak ada informasi posisi ada di widget ini";
  textList["TXFInitError"] = "Terjadi kesalahan pada saat inisiasi widget txf";
  textList["ScanFailed"] = "Scan gagal.";
  textList['PhoneUsed'] = 'Phone number has been used before ';
  textList['PhoneUsedMessage'] =
      'Nomor ponsel telah dipakai oleh pengguna lain. Silakan hubungi administrator anda.';
  textList['PhoneNotMatch'] = 'Phone number not match';
  textList['PhoneNotMatchMessage'] =
      'Nomor ponsel belum terdaftar, silakan hubungi administrator anda.';
  textList['AnotherUserLogin'] = 'Other user logged in';
  textList['AnotherUserLoginMessage'] =
      'Ada pemakai lain yang sedang memakai nomor ini. Silahkan pergunakan nomor telp lain.';
  textList['Full'] = 'Full !';
  textList['FullMessage'] =
      'Wah!, banyak sekali yang mendaftar. Sementara ini tidak dapat menambah pemakai baru. Kami sedang terus menambah kapasitas, silahkan coba beberapa jam lagi.';
  textList['SignInError'] = 'Sign in error';
  textList['SignInErrorMessage'] =
      'Terjadi kesalahan pada saat sign in, silahkan coba beberapa jam lagi.';
  textList['SignInErrorGoogle'] =
      'Terjadi kesalahan pada saat autorisasi akun Google, silahkan coba lagi.';
  textList['Error802'] = 'ERROR 802';
  textList['Error802Message'] = 'ERROR 802 Login gagal';
  textList['Error809'] = 'ERROR 809';
  textList['Error809Message'] = 'ERROR 809 Login gagal';
  textList['NoAccount'] = 'Anda belum memiliki akun.';
  textList['AdminRegisterAccount'] =
      'Mohon hubungi administrator untuk mendaftarkan akun anda.';
  textList['LoginFail'] = 'Login fail';
  textList['LoginFailMessage'] =
      'Login anda gagal. Kemungkinan karena koneksi internet anda terganggu. Silahkan coba beberapa saat lagi.';
  textList['GpsReadError'] = 'Gagal, tidak dapat membaca lokasi GPS.';
  textList['NoResult'] = 'Tidak ada hasil.';
  textList['GPSOutOfRange'] = 'Lokasi diluar batas.';
  //=========== End of Text Asset =========
  // home = 'home';
  debugCount = -22;
  trace(debugCount);
  apiInit1().then((_) => timeInit = true);
  // empty = '--';
  needUpgrade = empty;
  // internetConnection = InternetConnectionChecker();
  internetConnection = InternetConnectionChecker.instance;
  await internetConnectedCheck(forceTest: true);
  debugCount = -23;
  trace(debugCount);
  // Firebase.initializeApp() already ran in main() before globalInit().
  // Calling it again here was redundant work on the critical startup path.
  dynamic initValue = await Future.wait([
    getAllPermission(),
    SharedPreferences.getInstance(),
  ]);
  internetConnection.onStatusChange.listen((status) {
    internetConnectionFlag.value = status == InternetConnectionStatus.connected;
    debugPrint(
      '>>>>> Connectivity change, result: ${internetConnectionFlag.value.toString()}',
    );
    ConnectionData().getConnection(false, true);
  });
  debugCount = -24;
  trace(debugCount);
  prefs = initValue[1];
  firestoreDb = FirebaseFirestore.instance;
  fsCollection = "users_$fsName";
  fsMsgCollection = msgPrefix;
  firestoreEventCollection = eventPrefix + defaultCluster;
  lastEventCollection = firestoreEventCollection;
  eventDoc = firestoreEventCollection;
  // fsDeviceSubCollection = 'dvc'; //= device collection in user's uid doc
  topCollection = fsCollection;
  // kcck256 = SHA3Digest(256);
  // kcck512 = SHA3Digest(512);
  dhP = 13; // vertriz Diffie Hellman p parameter
  dhG = 2; // vertriz Diffie Hellman g parameter
  demoApp =
      demoVersion; // determine from different_code.dart whether a demo or not
  // devMode = false; // true : using devSystem; false using system
  bitIcon = const Icon(Icons.refresh); // 64 bit
  appLogVersion = '1.0.11';
  appsCode = appsKey;
  getSettingUrl =
      'https://us-central1-collanium1-4babc.cloudfunctions.net/getAgeniaSettings';
  cloudFunctionDomain = "us-central1-collanium1-4babc.cloudfunctions.net";
  resetString = 'k5lok4K987J'; //= used in v_crypto.dart argon
  cloudFunctionName = "/getPoxSettings";
  linkSettingFunctionName = "/getLinkSettings";
  getNewVidFunctionName = "/getNewVid";
  runIFunctionName = "/runInstruction";
  runI1FunctionName = "/runInstruction1";
  runI2FunctionName = "/runInstruction2";
  resetVidName = "/resetVid";
  functionDomain['default'] = 'asia-northeast1-otq-01.cloudfunctions.net';
  functionDomain['62'] = functionDomain['default'];

  storageBucket['default'] = 'gs://otq-01-ane1/';
  storageBucket['62'] = 'gs://otq-01-ase2';

  functionName['readSS'] = '/readSS'; //= unsecured read
  functionName['writeSS'] = '/writeSS'; //= unsecured write
  //  functionName['addFL'] = '/addFL'; //= unsecured append to  FromLink
  functionName['addFL'] =
      '/addFLSync3'; //= unsecured append to  FromLink, run Submitsync and sendMsg
  // addFLSync3 => write to Event
  functionName['runStartup'] = '/appStartup2';
  functionName['appSettings'] = '/appSettings3';
  functionName['runInstruction'] = '/runInstruction'; //= run instruction in gcf
  functionName['InvLogin'] = '/s1InvLogin';
  functionName['deviceOperation'] = '/deviceReset';
  autsorzFunctionDomain = functionDomain['default'];
  appSettingFunctionName = functionName['appSettings'];
  sheetSystemLength = 15;
  keyboardLength = '9939Kl=df9939)(48'; //= used in v_crypto.dart argon
  fromLink = 'FromLink'; // sheet to append
  vidRange = 'LIF!A2:E';
  lifSetting = 'Settings!B1:B5';
  lifSetting2 = 'Settings!G1:G14';
  paramRange = '*kOp1295'; //= used in v_crypto.dart argon
  errorPage =
      '{"title":"ERROR 811","children":[{"type":"TXT","beforeSpacing":30,"afterSpacing":30,"size":28,"data":"ERROR 811 Kesalahan pada JSON"},{"type":"TXT","afterSpacing":30,"size":28,"size":18,"data":"Ditemukan kesalahan aplikasi. Kemungkinan adanya kerusakan pada aplikasi."},{"type":"TXT","size":18,"data":"Mohon hubungi administrator anda."}]}';
  errorUrl =
      'https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/link_app%2Flink_error.png?alt=media&token=ebf8e9d5-e6c1-457d-8f00-b83c76d94fa8';
  linkUrls = [
    'https://script.google.com/macros/s/AKfycbxmoMsoUk7rfhud5VXXZr1LKasBeaM3Y92uXaGuyNcFat9XToE/exec',
  ];
  legalPage =
      '{"title":"Legal","children":[{"type":"VMENU","left":"TRUE","leftPadding":0,"rightPadding":0,"beforeSpacing":30,"afterSpacing":0,"font":"default","size":18,"color":"4278196850","title":"Peraturan Layanan (Bahasa Indonesia)","route":"https://storage.googleapis.com/alz-public-ase2/legal/vertika_tos_id002.html"}]}';
  // invitationPage =
  //     '{"title":"ERROR 802","children":[{"type":"TXT","beforeSpacing":30,"afterSpacing":30,"size":28,"data":"ERROR 802 Login gagal"},{"type":"TXT","afterSpacing":30,"size":28,"size":18,"data":"Anda belum memiliki akun atau anda masuk di perangkat lain. Untuk faktor keamanan, anda hanya dapat menggunakan satu akun pada satu perangkat. Anda perlu otentifikasi ulang jika ingin masuk di perangkat lain."},{"type":"TXT","size":18,"data":"Mohon hubungi administrator anda."}]}';
  invitationPage =
      '${'{"title":"ERROR 802","children":[{"type":"TXT","beforeSpacing":30,"afterSpacing":30,"size":28,"data":"ERROR 802 Login gagal"},{"type":"TXT","afterSpacing":30,"size":28,"size":18,"data":"' + textList["802"]}"}]}';
  // '{"title":"Invitation","children":[{"type":"IMG","url":"https://firebasestorage.googleapis.com/v0/b/collanium1-4babc.appspot.com/o/vertriz%2Fc%2Fagenia-logo-240x96.png?alt=media&token=7bbe5ec9-db7e-4062-97ba-80b1f9e21a12","height":120,"alignment":"left","beforeSpacing":0,"afterSpacing":0},{"type":"INVITATION","left":"TRUE","leftPadding":0,"rightPadding":0,"beforeSpacing":30,"afterSpacing":0,"font":"default","size":18,"color":"FF001A72","enter":"Masuk","label":"Nomor Undangan","hint":"Angka 4 atau 12 digit","notValid":"Nomor undangan tidak valid","expired":"Terlambat. Nomor undangan yang anda masukan sudah kadaluwarsa. Silahkan hubungi administrator komunitas yang memberikan nomor undangan ini untuk mendapatkan nomor undangan yang baru.","full":"Sementara ini tidak dapat menambah pemakai baru.","generalError":"Login gagal. Silahkan coba lagi"}]}';
  newPinPage =
      '{"title":"Pin","children":[{"type":"TXT","beforeSpacing":20,"afterSpacing":40,"size":16,"bold":"FALSE","data":"Masukan 6 angka pin anda 2X. Keduanya harus sama."},{"type":"TXF","variant":"newPin","digit":6,"route":"home","errorMessage":"PIN harus sama","submitButton":"Simpan","successMessage":"Berhasil. Simpan baik-baik PIN anda. PIN adalah kode rahasia anda. Jangan beritahukan PIN ini kepada siapapun."},{"type":"TXT","beforeSpacing":20,"afterSpacing":40,"size":16,"bold":"FALSE","data":"Jangan berikan pin ini kepada siapapun, termasuk staff agenia."}]}';

  allPagesBuilt =
      false; // status of any pages other than home. On Refresh(dev) this var should be set to false
  allPagesReady =
      false; // would be true when all pages already built in poxPage
  mobile = 'Mobile';
  theme = 'ThemeAgenia';
  locale = 'Locale';
  debugCount = 0;
  minYear = 1900; // earliest date = 1 Jan 1900
  maxPlusYear = 20; // latest date = current year + 20 years
  // shortDateFormat = 'dd/MM/yyy';
  // dateTimeFormat = 'd MMM yyyy HH:mm';
  // pool = Soundpool(streamType: StreamType.notification);
  //  int scannerBeep; // beep id defined in main
  //   myScrollController = new ScrollController(keepScrollOffset: true);
  systemUIComponent = {}; // list of system JSON
  screenUIComponent = {}; // list of screen JSON
  linkTransaction = {}; // list of transaction

  oVid = '';
  oPin = '';
  refreshFlag = false;

  debugCount = -25;
  trace(debugCount);
  appCodeController = AppCodeController();
  appCodeController.setApplicationVid();

  firestoreCollection = fsCollection;
  firestoreIO =
      firestoreCollection; // firestore collection for IO for this vid user/92343234234/io
  firestoreMsg =
      firestoreIO; // firestore collection for msg for any particular users/<my vid>/io/<other's vid>/msg
  firestoreNotif =
      firestoreIO; // firestore doc for notification from others. Document before /msg
  transactionStore = DevToolsStore<ScreenTransaction>(
    transactionReducer,
    initialState: ScreenTransaction(initTransactionStore()),
  );
  availableCameras().then((value) {
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#CAMS': value})),
    );
  });
  // ---- Restore persisted driver login (secure storage -> Redux) ----
  // I2: placed strictly AFTER transactionStore is non-null (created just
  // above). Read the driverLogin key; if non-empty, seed #has_user_login so the
  // scanner self-skip gate sees the session before the first route is built.
  // Local secure-storage read (no network) — safe in the serial bootstrap path.
  // The later main.dart bootstrap dispatch is a per-key merge and preserves
  // #has_user_login.
  try {
    final String? driverVid = await readDriverLogin();
    if (driverVid != null && driverVid.isNotEmpty) {
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#has_user_login': driverVid})),
      );
    }
  } catch (e) {
    devPrint('globalInit driverLogin restore error: $e');
  }
  getCountryCodeList(); // put country code list in #SIM_COUNTRY_CODES
  getTimeDifference();
  Get.put(GeneralGetXController());
  debugCount = -26;
  trace(debugCount);
  // MobileTableController mtc = MobileTableController();
  // mtc.setApplicationVid(appCodeController.applicationVid);
  // String test = await mtc.addContent('mobileTableTest1', 'Content table six.');
  actionLock('globalInit');
  // int? lastGTime = prefs.getInt('@lastGpsTime');
  // if (lastGTime == null) {
  //   lastGTime = 0;
  //   await prefs.setInt('@lastGpsTime', lastGTime);
  // }
  // dynamic gpsArray = await Future.wait([
  //   secureRead(key: 'gpsData'),
  //   secureRead(key: 'gpsPlaceMark'),
  //   // storage.read(key: 'gpsData'),
  //   // storage.read(key: 'gpsPlaceMark'),
  // ]);

  // dynamic gpsArray =[];
  // dynamic temp = await secureRead(key: 'temp1');
  // gpsArray.add(await secureRead(key: 'gpsData'));
  // gpsArray.add(await secureRead(key: 'gpsPlaceMark'));
  debugCount = -27;
  trace(debugCount);
  // if (gpsArray[0] != null) {
  //   gpsData = convertToPosition(gpsArray[0]);
  // }
  // if (gpsArray[1] != null) {
  //   gpsPlaceMark = convertToPlaceMark(gpsArray[1]);
  // }
  // // trigger location stream
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
  // positionStream =
  //     Geolocator.getPositionStream(locationSettings: locationSettings);
  // positionStreamSubs = positionStream.listen((Position position) {
  //   updateAppGps(position);
  //   if (kDebugMode) {
  //     String gpsDataStream = positionToGpsString(position);
  //     int calculatedTime =
  //         DateTime.now().millisecondsSinceEpoch + time2GpsOffset;
  //     int elapsedTime = calculatedTime - gpsTime.value;
  //     devPrint(
  //         "gpsTime:${gpsTime.value} , time2GpsOffset:$time2GpsOffset ,  Position stream: $gpsDataStream");
  //     devPrint("  calculatedTime: $calculatedTime , elapsedTime: $elapsedTime");
  //   } // end if kDebugMode
  // });

  // await Future.wait([
  //   secureWrite(key: 'gpsData', value: json.encode(gpsData)),
  //   secureWrite(key: 'gpsPlaceMark', value: json.encode(gpsPlaceMark)),
  // ]);
  await startGettingGpsData();
  debugCount = -271;
  trace(debugCount);
  // getLocation();
  debugCount = -28;
  trace(debugCount);
  return 1;
} // end of globalInit

Placemark convertToPlaceMark(String? strObj) {
  dynamic placeMark = strObj == null ? null : json.decode(strObj);
  late Placemark result;
  try {
    result = Placemark(
      name: placeMark?['name'] ?? '%-pmName-%',
      street: placeMark?['street'] ?? '%-pmstr-%',
      isoCountryCode: placeMark?['isoCountryCode'] ?? '%-pmIsoCC-%',
      country: placeMark?['country'] ?? invalidCountry,
      postalCode: placeMark?['postalCode'] ?? '%-pmPostal-%',
      administrativeArea: placeMark?['administrativeArea'] ?? '%-pmAdmin-%',
      subAdministrativeArea:
          placeMark?['subAdministrativeArea'] ?? '%-pmSubAdmin-%',
      locality: placeMark?['locality'] ?? '%-pmLocality-%',
      subLocality: placeMark?['subLocality'] ?? '%-pmSubLocality-%',
      thoroughfare: placeMark?['thoroughfare'] ?? '%-pmThrFare-%',
      subThoroughfare: placeMark?['subThoroughfare'] ?? '%-pmSubThrFare-%',
    );
  } catch (e) {
    result = const Placemark(
      name: emptyString,
      street: emptyString,
      isoCountryCode: invalidCountry,
      country: invalidCountry,
      postalCode: emptyString,
      administrativeArea: emptyString,
      subAdministrativeArea: emptyString,
      locality: emptyString,
      subLocality: emptyString,
      thoroughfare: emptyString,
      subThoroughfare: emptyString,
    );
  } // end try
  return result;
} // end of convertToPlaceMark

Position convertToPosition(String? strObj) {
  dynamic obj = strObj == null ? null : json.decode(strObj);
  late Position result;
  try {
    result = Position(
      latitude: obj?['latitude'] ?? invalidLocation,
      longitude: obj['longitude'] ?? invalidLocation,
      accuracy: obj['accuracy'] ?? 0.0,
      altitude: obj['altitude'] ?? -88.0,
      speed: obj['speed'] ?? 0.0,
      speedAccuracy: obj['speedAccuracy'] ?? 0.0,
      heading: obj['heading'] ?? 0.0,
      isMocked: obj['isMocked'] ?? false,
      timestamp: DateTime.parse(obj['timestamp'] ?? invalidTime),
      altitudeAccuracy: obj['altitudeAccuracy'] ?? 0.0,
      headingAccuracy: obj['headingAccuracy'] ?? 0.0,
    );
  } catch (e) {
    result = Position(
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
  } // end try
  return result;
} // end of convertToPosition

Future<Position> setGpsLocation(String from) async {
  try {
    Position temp = (await getLocation())!;
    if ((temp.timestamp.millisecondsSinceEpoch) != 0) {
      gpsData = temp;
      gpsTime.value = (gpsData.timestamp.millisecondsSinceEpoch);
      await storage.write(key: 'gpsData', value: json.encode(gpsData));
      await prefs.setInt('@lastGpsTime', gpsTime.value);
      debugPrint('gpsLocation updated from $from');
    }
  } catch (e) {
    debugPrint('Cannot getGpsLocation (${e.toString()}) from $from');
  }
  return gpsData;
}

List<List<dynamic>> deepCopy2(List<dynamic> originalArray) {
  // Deep copy of 2 dimensional array
  List<List<dynamic>> result = [];
  for (int i = 0; i < originalArray.length; i++) {
    List<dynamic> rowCopy = [];
    for (int j = 0; j < originalArray[i].length; j++) {
      rowCopy.add(originalArray[i][j]);
    } // end for j
    result.add(rowCopy);
  } // end for i
  return result;
} // end of deepCopy2

// This function takes in data and indexString, and returns a list of image URLs
// corresponding to the specified index. If the data or indexString are null or invalid,
// the function returns the default image URL.
List<String> getImageList(dynamic data, String? indexString) {
  // If data or indexString are null, return the default image URL.
  if (data == null || indexString == null) {
    return [defaultImage];
  }
  // Try to parse the indexString into an integer. If it fails or the index is invalid, return the default image URL.
  int? index = int.tryParse(indexString.trim().replaceAll(RegExp('[<>]'), ''));
  if (index == null || index < 0 || index >= data.length) {
    return [defaultImage];
  }
  // If the data at the specified index is empty or whitespace, return the default image URL.
  // index = max(0,index-1);
  String imageData = data[index].toString().trim().replaceAll(
    separator[6],
    separator[5],
  );
  imageData = imageData.replaceAll(' ', separator[5]);
  if (imageData.isEmpty) {
    return [defaultImage];
  }
  // Split the string at the specified index into a list of URLs. If the list is empty, return the default image URL.
  // final urlList = imageData.split(separator[6]);
  final urlList = imageData.split(separator[5]); // white diamond
  if (urlList.isEmpty) {
    return [defaultImage];
  }
  return urlList;
} // end of getImageList

Map<K, V> dict<K, V>(Iterable<MapEntry<K, V>> entries) {
  // convert to Map
  var map = <K, V>{};
  for (var entry in entries) {
    map[entry.key] = entry.value;
  } // end for (var entry in entries)
  return map;
} // end of dict

int getIntChecksum(String inp) {
  // convert last 6 of hexadecimal string to integer not less than 8 digits
  const resultMin = 10000000;
  final random = Random();
  int result = random.nextInt(10000000) + 40000000;
  try {
    result = int.parse(inp.substring(inp.length - 6), radix: 16);
    if (result < resultMin) {
      result += resultMin * 3;
    } // end if (result < resultMin)
  } catch (e) {
    result = random.nextInt(10000000) + 40000000;
  } // end try
  return result;
} // end of getIntChecksum

String? autheniumDecode(String? inp) {
  String? result = inp;
  if (result != null) {
    result = result.replaceAll('_u2606_', '\u{2606}');
    result = result.replaceAll('_u25FC_', '\u{25FC}');
    result = result.replaceAll('_u25C0_', '\u{25C0}');
    result = result.replaceAll('_u25B6_', '\u{25B6}');
    result = result.replaceAll('_u25C1_', '\u{25C1}');
    result = result.replaceAll('_u25B7_', '\u{25B7}');
    result = result.replaceAll('_u2605_', '\u{2605}');
    result = result.replaceAll('_u2B24_', '\u{2B24}');
    result = result.replaceAll('_u2B58_', '\u{2B58}');
    result = result.replaceAll('_u2B2A_', '\u{2B2A}');
    result = result.replaceAll('_u25C6_', '\u{25C6}');
    result = result.replaceAll('_u25C7_', '\u{25C7}');
    result = result.replaceAll('_25FC_', '\u{25FC}'); // this is buggy character
    // result = result.replaceAll('_25C0_', '\u{25C0}');
    // result = result.replaceAll('_25B6_', '\u{25B6}');
    // result = result.replaceAll('_25C1_', '\u{25C1}');
    // result = result.replaceAll('_25B7_', '\u{25B7}');
    // result = result.replaceAll('_2605_', '\u{2605}');
    // result = result.replaceAll('_2B24_', '\u{2B24}');
    // result = result.replaceAll('_2B58_', '\u{2B58}');
  }
  return result;
} // end of autheniumDecode

int getNumberOfField(String? input) {
  if (input == null) return 0;
  return int.parse(input.split(separator[6])[2]);
} // end of getNumberOfField

bool beginWithAtiCode(String? input) {
  if (input == null) return false;
  if (input.length < atiCode.length) return false;
  return input.substring(0, atiCode.length) == atiCode;
} // end of atiCheck

String? cleanAtiCode(String? input) {
  if (input == null) return null;
  if (beginWithAtiCode(input)) {
    return input.substring(atiCode.length);
  }
  return input;
} // end of cleanAtiCode

String? quoteCleanUp(String? inp) {
  // replace " and ' to `
  if (inp == null) return null;
  String output = inp.replaceAll('"', '``').replaceAll("'", '`');
  return output;
} // end of quoteCleanUp

String? stringCleanUp(String? inp) {
  if (inp == null) return null;
  String output = quoteCleanUp(cleanAtiCode(inp)) ?? '';
  if (!beginWithAtiCode(inp)) {
    // Strip control chars except \n (handled separately in saveSend)
    output = output.replaceAll(RegExp(r'[\x00-\x09\x0B-\x1F]'), '');
    for (final c in forbiddenCharacter) {
      if (c != separator[5]) {
        // except white diamond for get_images
        output = output.replaceAll(c, ' ');
      } // end if (c != separator[5])
    } // end for c
    // Guard formula injection: prefix space if starts with = or @
    if (output.isNotEmpty && (output[0] == '=' || output[0] == '@')) {
      output = ' $output';
    }
  } // end if (beginWithAtiCode(inp))
  return output;
} // end of stringCleanUp

List<dynamic> tableToArray(
  Map<String, dynamic>? sourceTable,
  String tableCode,
  String? sort,
) {
  List<dynamic> res = [];
  int sortFactor = 0; // no sort as default
  if (sort != null) {
    switch (sort.trim().toLowerCase()) {
      case "asc":
        sortFactor = -1;
        break;
      case "desc":
        sortFactor = 1;
        break;
      default:
        sortFactor = 0; // do not sort
    } // end switch (sort)
  } // end if (sort != null)
  if (sourceTable != null) {
    Map<String, dynamic>? myTable = sourceTable;
    if (sortFactor != 0) {
      try {
        // String? checksum = myTable[tableCode];
        myTable.remove(tableCode);
        myTable = dict(
          sourceTable.entries.toList()..sort(
            (e1, e2) =>
                sortFactor * int.parse(e2.key).compareTo(int.parse(e1.key)),
          ),
        );
        // myTable[tableCode] = checksum;
      } catch (e) {
        myTable = sourceTable;
      }
    } // end if (sortFactor == 0)
    myTable.forEach((k, v) {
      if (k != tableCode) {
        List<dynamic> element = [k];
        element.addAll(v);
        res.add(element);
      } //end if (v is! int)
    });
  }
  if (sortFactor != 0) {
    res.sort((a, b) => sortFactor * int.parse(a[0]).compareTo(int.parse(b[0])));
  } //if (sortFactor != 0)
  return res;
} // end of tableToArray

String replaceMarkerPrototype(String source, List ref, int startIndex) {
  // replace all <i> in source with the corresponding value in ref
  // for backward compatible, startIndex = 0
  String res = '$source/n';
  try {
    for (int i = 0; i < ref.length; i++) {
      res = res.replaceAll('<$i>', 'i');
    } // end for (int i = 0; i < ref.length; i++)
  } catch (e) {
    res = 'i';
  }
  return res;
} // end of replaceMarkerPrototype

String replaceMarker(String source, List ref, int startIndex, bool newLine) {
  // replace all <i> in source with the corresponding value in ref
  // for backward compatible, startIndex = 0
  // if newLine == true, then /n will not replaced by --
  // ref = [sort key, timestamp, field1, field2,...]
  String res = source;
  try {
    final int len = ref.length;
    final int maxIndex = max(0, len - 1);
    final int indexFactor = 1 - startIndex; // 1 - startIndex;
    for (int i = 0; i < len; i++) {
      int convertedIndex = min(max(1, i + indexFactor), maxIndex);
      res = res.replaceAll(
        '<$i>',
        ref[convertedIndex].toString(),
      ); // notation begin with 1. 0 = sort key, 1 = timestamp
    } // end for (int i = 0; i < len; i++)
    if (!newLine) {
      res = res.replaceAll('\\n', ' -- ');
    }
  } catch (e) {
    res = e.toString();
  } // end try
  return res;
} // end of replaceMarker

String cleanupString(String inp) {
  String output = inp
      .replaceAll('"', '')
      .replaceAll('\'', '/')
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
  for (final c in forbiddenCharacter) {
    output = output.replaceAll(c, ' ');
  }
  return output;
}

void getTimeDifference() async {
  getRealTime().then((res) {
    int deviceTime = DateTime.now().millisecondsSinceEpoch;
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#REF_TIME_START': res,
          '#DEVICE_TIME_START': deviceTime,
        }),
      ),
    );
  });
} // end of getTimeDifference

String getLocaleText(String key) {
  const String errString = "No locale string";
  String result = errString;
  if (key == '99900990') {
    result = 'RP ###.##0';
  }
  try {
    result = localeText[key] ?? errString;
  } catch (_) {}
  return result;
} // end of getLocaleText

CrossAxisAlignment crossAlignmentConst(String? inp) {
  // get MainAxisAlignment const from string input
  // default = MainAxisAlignment.start
  CrossAxisAlignment result = CrossAxisAlignment.start;
  String alg = (inp ?? 'start').toString().toLowerCase();
  if (alg == 'start') {
    result = CrossAxisAlignment.start;
  } else if (alg == 'end') {
    result = CrossAxisAlignment.end;
  } else if (alg == 'center' ||
      alg == 'centre' ||
      alg == 'spacebetween' ||
      alg == 'spaceevenly' ||
      alg == 'spacearound') {
    result = CrossAxisAlignment.center;
  } else {
    result = CrossAxisAlignment.start;
  } // end if alg
  return result;
} // end of crossAlignmentConst

MainAxisAlignment mainAlignmentConst(String? inp) {
  // get MainAxisAlignment const from string input
  // default = MainAxisAlignment.start
  MainAxisAlignment result = MainAxisAlignment.start;
  String alg = (inp ?? 'start').toString().toLowerCase();
  if (alg == 'start') {
    result = MainAxisAlignment.start;
  } else if (alg == 'end') {
    result = MainAxisAlignment.end;
  } else if (alg == 'center' || alg == 'centre') {
    result = MainAxisAlignment.center;
  } else if (alg == 'spacebetween') {
    result = MainAxisAlignment.spaceBetween;
  } else if (alg == 'spaceevenly') {
    result = MainAxisAlignment.spaceEvenly;
  } else if (alg == 'spacearound') {
    result = MainAxisAlignment.spaceAround;
  } else {
    result = MainAxisAlignment.start;
  } // end if alg
  return result;
} // end of mainAlignmentConst

List<dynamic> styleArray(String? inp) {
  // input is string consist of b = bold, i = italic, u=underline, k = strikethrough
  // result = [bold, italic, underline | strike]
  List<dynamic> result = [];
  String inpStyle = (inp ?? "").toString().toLowerCase();
  try {
    result.add(inpStyle.contains('bold') ? FontWeight.bold : FontWeight.normal);
    result.add(
      inpStyle.contains('italic') ? FontStyle.italic : FontStyle.normal,
    );
    if (inpStyle.contains('underline') && inpStyle.contains('strikethrough')) {
      result.add(
        TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
        ]),
      );
    } else {
      if (inpStyle.contains('underline')) {
        result.add(TextDecoration.underline);
      } else if (inpStyle.contains('strikethrough')) {
        result.add(TextDecoration.lineThrough);
      } else {
        result.add(TextDecoration.none);
      } // end if u
    } // end if u & k
    //result.add(inpStyle.contains('underline') ? true : false);
  } catch (e) {
    result = [false, false, false];
  }
  return result;
} //end of styleArray

List<double> marginArray(String? inp) {
  // get spacing array from "0;0;0;0" input format
  // if error or null will return [0,0,0,0]
  // output of format top,bottom,left,right
  List<double> result = [];
  try {
    var sArray = (inp ?? '0,0,0,0').toString().split(separator[4]);
    for (int i = 0; i < 4; i++) {
      try {
        result.add(double.parse(sArray[i]));
      } catch (_) {
        result.add(0.0);
      } // end try
    } // end for i
  } catch (_) {
    result = [0.0, 0.0, 0.0, 0.0];
  } // end try
  return result;
} // end of spacingConst

bool string2Bool(String? inp) {
  bool retVal = false;
  if (inp != null && inp.trim().toLowerCase() == 'true') {
    retVal = true;
  }
  return retVal;
} // end of string2Bool

Future firstLogin(String vid, String sheetKey) async {
  // no need to add document in firestore. It is done by function getNewVid
  // run when first user login
  int now = DateTime.now().millisecondsSinceEpoch;
  await Future.wait([
    getGPSLoc(), // put gps loc in #LOCATION
    getMyImei(), // put imei in #IMEI
  ]);
  var state = transactionStore.state.screenTx;
  var cUser = state['#FIREBASE_USER'];
  //* Set vid, email, sheetKey in transactionStore
  //* save to firestore :  email,uid
  //  await setUidImeiEmail(vid); // To Firestore
  //* save to persistence.storage :
  //*   sheetKey => 'myLif',
  // X   #FIREBASE_USER => 'myFirebaseData'
  storage.write(
    key: 'myLif',
    value: sheetKey,
  ); // put interface key as default LIF in persistent secure storage
  //* put to LIF :
  //*  name, email, imei, gps, timestamp, photoUrl, authentication method
  if (state['#SHEET_API']) {
    // Write to Lif for first time.
    ValueRange vu = ValueRange.fromJson({
      "values": [
        [cUser.displayName],
        [cUser.email],
      ],
    });
    sheetApi.spreadsheets.values.update(
      vu,
      sheetKey,
      'Settings!B2:B3',
      valueInputOption: 'USER_ENTERED',
    );
    ValueRange profile = ValueRange.fromJson({
      "values": [
        [state['#IMEI'] ?? '-'],
        [cUser.photoUrl ?? ''],
        [state['#LOCATION'].lat ?? 0],
        [state['#LOCATION'].lng ?? 0],
        [now],
        [state['#AUTH_METHOD']],
      ],
    });
    sheetApi.spreadsheets.values.update(
      profile,
      sheetKey,
      'Settings!G1:G6',
      valueInputOption: 'USER_ENTERED',
    );
  }
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({
        '#INTERFACE_KEY': sheetKey,
        '#VID': vid,
        '#EMAIL': cUser.email,
      }),
    ),
  );
  launchCheck();
} // end of firstLogin

dynamic displayPage(String pageName) {
  // clear global variables, ready for new page
  //   txfController.clear();
  //   inputTxt.clear();
  //  return AnyPage(pageName:pageName);
  return linkPage[pageName];
}

bool routeExist(String? page) {
  bool retVal = false;
  if (page != null && page.isNotEmpty) {
    retVal = linkElement[page] != null;
  }
  return retVal;
}

List<Widget> reloadPage(String page) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    clearData(page);
  });
  List<Widget> newPageElement =
      []; //List<Widget>.empty(); // create output List
  if (linkElement[page] != null) {
    //newPageElement.addAll(linkElement[page]!); // format for output
    newPageElement = List<Widget>.of(
      linkElement[page]!.map((widget) => widget),
    );
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#CURRENT_ROUTE': page})),
    );
  } else {
    // if page not found, put error page here for application debug
    // newPageElement.addAll(linkElement[home]!); // format for output
    // Sibling of the guard in MainPageState: this is the fallback for an
    // unknown route, so it must not itself throw when home was never built
    // (failed startup page load). Empty list -> the shell's page gate handles it.
    newPageElement = List<Widget>.of(
      (linkElement[home] ?? const <Widget>[]).map((widget) => widget),
    );
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#CURRENT_ROUTE': home})),
    );
  }
  return newPageElement;
}

void gotoRoute(String routeName) {
  if (routeExist(routeName)) {
    var state = transactionStore.state.screenTx;
    if (state['#REFRESH']) {
      oldSettingUpShouldBeDeleted().then((aRes) {
        var state = transactionStore.state;
        var lifKey = state.screenTx['#INTERFACE_KEY'];
        readSettings(lifKey, 1).then((_) {
          transactionStore.dispatch(
            UpdateScreenTxAction(
              ScreenTransaction({
                '#REFRESH': false,
                '#CURRENT_ROUTE': routeName,
              }),
            ),
          );
          String newRoute = routeName;
          List<Widget> newElementList = reloadPage(newRoute);
          rootThis.setState(() {
            rootThis.pageName = newRoute;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
          });
        });
      });
    } else {
      String newRoute = routeName;
      List<Widget> newElementList = reloadPage(newRoute);
      if (newElementList.isNotEmpty) {
        rootThis.setState(() {
          rootThis.pageName = newRoute;
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
        });
      }
    }
  } // end if routeExist
} // end of gotoRoute

Future saveSendSingle(String screenName, int position, String sendData) async {
  // get data from txfController => put to ScreenTransaction of corresponding screen
  // dynamic row = List()..length = sheetSystemLength + 1;
  dynamic row = List.filled(sheetSystemLength + 1, null, growable: true);
  await initSheetRow(row); // init row for system column
  row[7] = screenName;

  int pos = position + sheetSystemLength;
  if (pos >= row.length) {
    int dif = (pos - row.length - 1).toInt();
    for (var ii = 0; ii < dif; ii++) {
      row.add('');
    }
    row.add("'$sendData");
  } else {
    row[pos] = "'$sendData";
  }

  transactionStore.dispatch(
    SaveSendTxAction(
      ScreenTransaction({
        'screenName': [row],
      }),
    ),
  );
}

// Future saveSendRecord(String screenName, String tail) async {
//   // get data from txfController => put to ScreenTransaction of corresponding screen
//   // dynamic row = List()
//   //   ..length = sheetSystemLength + txfController[screenName]!.length;
//   dynamic row = List<dynamic>.filled(
//       sheetSystemLength + txfController[screenName]!.length, null,
//       growable: true);
//   int maxPosition = 0;
//   await initSheetRow(row); // init row for system column
//   row[1] = screenName; //7
//   String originalText = '0'; // encryption type 0 = no encryption
//   txfController[screenName]!.forEach((k, input) {
//     int pos = input.position + sheetSystemLength - 1;
//     maxPosition = input.position > maxPosition ? input.position : maxPosition;
//     if (pos >= row.length) {
//       int dif = row.length - pos - 1;
//       for (var ii = 0; ii < dif; ii++) {
//         row.add('');
//       }
//       row.add(input.finalData == emptyString
//           ? input.controller.text.replaceAll("\n", "\\n")
//           : input.finalData
//               .replaceAll("\n", "\\n")); // get data from txf controller
//     } else {
//       row[pos] = input.finalData == emptyString
//           ? input.controller.text.replaceAll("\n", "\\n")
//           : input.finalData
//               .replaceAll("\n", "\\n"); // get data from txf controller
//     }
//   });
//   row = row.sublist(
//       0, (maxPosition + 15 < row.length) ? maxPosition + 15 : row.length);
//   for (int c = 15; c < row.length; c++) {
//     if (15 < c) originalText += separator[1];
//     if (row[c] != null) originalText += row[c];
//   }
//   row[2] = '$originalText$tail';
//   row = row.sublist(0, 3);
//
//   appendToSheet(row);
//   // for firebase (0.9.12.c) uncomment this and comment command below
//   // transactionStore.dispatch(SaveSendTxAction(ScreenTransaction({
//   //   'screenName': [row]
//   // })));
// } // end of saveSendRecord

String displayDateTime(int msUnix) {
  String result = DateFormat(
    "d MMM y H:m",
  ).format(DateTime.fromMillisecondsSinceEpoch(msUnix));
  return result;
}

void signUp(BuildContext context, String screenName) {
  // get data from txfController => put to ScreenTransaction of corresponding screen
  int counter = 0;
  txfController[screenName]!.forEach((k, input) {
    if (counter == 0) {
      oVid = input.controller.text;
    } else {
      oPin = input.controller.text;
    }
    counter++;
  });
  getLinkInterfaceKey(context, oVid, oPin);
}

Future initSheetRow(dynamic row) async {
  var b = transactionStore.state;
  //row[0] = DateTime.now().millisecondsSinceEpoch;
  row[0] = await getRealTime();
  row[1] = 'M';
  row[2] = b.screenTx['#VID'];
  row[8] = 'E0';
  row[3] = 'NTP';
}

int hexToInt(String hex) {
  int val = 0;
  int len = hex.length;
  for (int i = 0; i < len; i++) {
    int hexDigit = hex.codeUnitAt(i);
    if (hexDigit >= 48 && hexDigit <= 57) {
      val += (hexDigit - 48) * (1 << (4 * (len - 1 - i)));
    } else if (hexDigit >= 65 && hexDigit <= 70) {
      // A..F
      val += (hexDigit - 55) * (1 << (4 * (len - 1 - i)));
    } else if (hexDigit >= 97 && hexDigit <= 102) {
      // a..f
      val += (hexDigit - 87) * (1 << (4 * (len - 1 - i)));
    } else {
      throw const FormatException("Invalid hexadecimal value");
    }
  }
  return val;
}

Future<int> launchCheckDemo() async {
  // justLaunch procedure
  // Launch with logged in status. Always run at launch like good old autoexec.bat
  // firstLogin, justReLogin and launch with logged in status, run this function
  int result = 99; // return > 0 when something wrong
  try {
    await FirebaseNotifications()
        .setUpFirebase(); // setup fcm notification for app
    result =
        await userIntegrityCheck(); // check fcm token & Imei, update when firebase in = true; ask other device to logout first
  } catch (_) {
    result = 99;
  }
  return result;
} // end of LaunchCheckDemo

Future reLoginDemo() async {
  // justReLogin procedure
  // after logged out then re login
  // Set vid in transactionStore
  // save sheetKey to persistence.storage
  //X save FirebaseUser to persistence.storage 'myFirebaseData'
  // save uid, imei, in to firebase
  await getMyImei(); // put imei in #IMEI
  var state = transactionStore.state.screenTx;
  var sheetData = await getLifProfileData(state['#INTERFACE_KEY']);
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#VID': sheetData['vid']})),
  );
  storage.write(key: 'myLif', value: state['#INTERFACE_KEY']);
  //  storage.write(key: 'myFirebaseData', value: jsonEncode(state['#FIREBASE_USER']));
  //  await setUidImeiEmail(sheetData['vid'].toString()); // To Firestore
  launchCheckDemo();
} // end of reLoginDemo

Future firstLoginDemo(String vid, String sheetKey) async {
  // firstLogin procedure
  // no need to add document in firestore. Done by function getNewVid
  // run when first user login
  int now = DateTime.now().millisecondsSinceEpoch;
  //  var setResult =
  await Future.wait([
    getGPSLoc(), // put gps loc in #LOCATION
    getMyImei(), // put imei in #IMEI
  ]);
  var state = transactionStore.state.screenTx;
  var cUser = state['#FIREBASE_USER'];
  if (cUser == null) {
    cUser = await getFirebaseUser();
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#FIREBASE_USER': cUser})),
    );
  }
  //* Set vid, email, sheetKey in transactionStore
  //* save to firestore :  email,uid
  //  await setUidImeiEmail(vid); // To Firestore
  //* save to persistence.storage :
  //*   sheetKey => 'myLif',
  // X   #FIREBASE_USER => 'myFirebaseData'
  storage.write(
    key: 'myLif',
    value: sheetKey,
  ); // put interface key as default LIF in persistent secure storage
  //  var jsonForm = cUser.toJson();
  //  var encoded = jsonEncode(jsonForm);
  //  storage.write(
  //      key: 'myFirebaseData',
  //      value: jsonEncode(encoded));      // put firebase user data in persistent secure storage

  //* put to LIF :
  //*  name, email, imei, gps, timestamp, photoUrl, authentication method
  if (state['#SHEET_API']) {
    // Write to Lif for first time.
    //    ValueRange vu = new ValueRange.fromJson({
    //      "values": [
    //        [cUser.displayName],
    //        [cUser.email]
    //      ]
    //    });
    //    sheetApi.spreadsheets.values.update(vu, sheetKey, 'Settings!B2:B3',
    //        valueInputOption: 'USER_ENTERED');
    //    String pk = createPrivateKey('');
    ValueRange profile = ValueRange.fromJson({
      "values": [
        [state['#IMEI'] ?? '-'],
        [cUser.photoUrl ?? ''],
        [state['#LOCATION'].lat ?? 0],
        [state['#LOCATION'].lng ?? 0],
        [now],
        ['Demo'],
        [''],
        [now],
        [''],
        ['pinhash'],
        ['cipher'],
        ['public'],
        ['private'],
        ['address'],
      ],
    });
    // write setting to LIF.
    // put pinhash, publicKey, [privateKey (temporary)], address in LIF
    sheetApi.spreadsheets.values.update(
      profile,
      sheetKey,
      lifSetting2,
      valueInputOption: 'USER_ENTERED',
    );
  }
  transactionStore.dispatch(
    UpdateScreenTxAction(
      ScreenTransaction({
        '#INTERFACE_KEY': sheetKey,
        '#VID': vid,
        '#EMAIL': cUser.email,
      }),
    ),
  );
  launchCheckDemo();
} // end of firstLoginDemo

List<String> diamondTextToList(String input) {
  // convert "abc◆def◆ghi" => List ["abc","def","ghi"]
  List<String> retVal = [];
  if (input != empty) {
    try {
      String noDiamondStr = input.replaceAll(separator[1], '_u25C6_');
      String strTest = '["${noDiamondStr.replaceAll('_u25C6_', '","')}"]';
      retVal = jsonDecode(strTest).cast<String>();
    } catch (_) {
      retVal = input.split('◆');
    }
  } // end if input
  return retVal;
} // end of diamondTextToList

Future<bool> dataOk(context) async {
  bool dataOk = transactionOK();
  // dataOk = dataOk && (transactionStore.state.screenTx['#INTERNET'] ?? false);
  if (!dataOk) {
    String title = "AlertTitle";
    String body = "NeedGreen";
    // if ((transactionStore.state.screenTx['#DATA_OK'] ?? false) &&
    //     !(transactionStore.state.screenTx['#INTERNET'] ?? false)) {
    // if (transactionStore.state.screenTx['#DATA_OK'] ?? false)  {
    //   title = "NoInternetTitle";
    //   body = "NoInternet";
    // }
    rootThis.setState(() {
      rootThis.dataColor = notReadyColor;
    });
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          // display dialog that data is not ready
          title: Text(textList[title]),
          content: Container(
            alignment: const Alignment(0.0, 0.0),
            height: 100,
            child: Text(textList[body]),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: Text(
                textList["OK"],
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                  backgroundColor: Theme.of(
                    context,
                  ).textTheme.bodyLarge!.backgroundColor,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  return dataOk;
} // end of dataOK

Future<bool> internetOk(context) async {
  bool dataOk = transactionStore.state.screenTx['#INTERNET'] ?? false;
  if (!dataOk) {
    String title = "NoInternetTitle";
    String body = "NoInternet";

    rootThis.setState(() {
      rootThis.dataColor = notReadyColor;
    });
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          // display dialog that data is not ready
          title: Text(textList[title]),
          content: Container(
            alignment: const Alignment(0.0, 0.0),
            height: 100,
            child: Text(textList[body]),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(textList["OK"]),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  return dataOk;
} // end of internetOK

void actionLock(String from) {
  // lock action so no other action can be performed until current transaction completes
  // called by every action button
  // debugPrint('#### actionLock from $from');
  setTransactionNotOK('actionLock $from');
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#DATA_OK': false})),
  );
  // if (rootThis != null) {
  //   rootThis.setState(() {
  //     rootThis.dataColor = notReadyColor;
  //   });
  // } // end if (rootThis != null)
} // end of action Lock

void actionUnLock(String from) {
  // unlock action
  // debugPrint('#### actionUnLock from $from');
  setTransactionOK('actionUnlock $from');
  transactionStore.dispatch(
    UpdateScreenTxAction(ScreenTransaction({'#DATA_OK': true})),
  );
  // if (rootThis != null) {
  //   rootThis.setState(() {
  //     rootThis.touch = !rootThis.touch;
  //     rootThis.dataColor = readyColor;
  //   });
  // } // end if (rootThis != null)
} // end of action UnLock

String phoneCleanup(String ph) {
  String retVal = ph.replaceAll(RegExp("[^0-9]"), "");
  return retVal.replaceFirst(
    RegExp("^0|^62|^65|^60|^63|^66|^66|^1|^673|^61|^52"),
    "",
  );
} // end of phoneCleanup

/// Adaptive -> canonical Indonesian "62"+national.
/// Handles 08.., 8.., 89.., +62.., 62.., 6289.., separators. Idempotent.
/// Self-contained: does NOT read #COUNTRY (login-safe).
String phoneCanonical62(String inp) {
  String d = inp.replaceAll(RegExp('[^0-9]'), '');
  d = d.replaceFirst(RegExp('^62'), '');
  d = d.replaceFirst(RegExp('^0'), '');
  if (d.isEmpty) return '';
  return '62$d';
} // end of phoneCanonical62

/// True when [e] is the shape a call gets when the radio is simply down:
/// `ClientException with SocketException: Connection failed (OS Error: Network
/// is unreachable, errno = 101)`, `Failed host lookup` (errno 7), etc.
bool isNetworkDownError(dynamic e) {
  final String s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Network is unreachable') ||
      s.contains('Failed host lookup');
} // end of isNetworkDownError

void errorReport(dynamic e, [StackTrace? stack]) {
  // Offline is a NORMAL state in this offline-first app — every http / Cloud
  // Function call made with no network throws, and reporting each one made
  // "readSS Network is unreachable" the top non-fatal. Skip ONLY when the app
  // itself knows it is offline AND the error is network-shaped: the same
  // exception while online is a real failure and still reported, and a
  // non-network error while offline (RangeError, cast, …) still reports.
  if (!internetConnectionFlag.value && isNetworkDownError(e)) {
    debugPrint('offline (crash report skipped): ${e.toString()}');
    return;
  }
  // Log unconditionally (debugPrint prints in release too) AND forward to
  // Crashlytics as a non-fatal for remote capture — the hundreds of
  // catch-then-errorReport sites (incl. historySync data-loss) are now visible
  // in the field. Crashlytics no-ops when collection is disabled (debug).
  // Guarded so a not-yet-initialised Firebase never turns an error report into
  // a second crash.
  debugPrint('errorReport: ${e.toString()}');
  try {
    FirebaseCrashlytics.instance.recordError(
      e,
      stack ?? StackTrace.current,
      fatal: false,
    );
  } catch (_) {
    // Crashlytics unavailable (e.g. before Firebase.initializeApp) — ignore.
  }
} //errorReport

void devPrint(dynamic e) {
  if (kDebugMode) {
    debugPrint(e.toString());
  }
} // end of devPrint

/// Fire-and-forget-safe Firestore document `update()`.
///
/// A raw `docRef.update(map)` that is NOT awaited (and lacks `.catchError`)
/// turns any write rejection into an UNHANDLED async error: it escapes to
/// `platformDispatcher.onError` (main.dart) and is recorded as a FATAL crash,
/// with no app frames in the stack (the async gap drops them). The repetitive
/// `[cloud_firestore/invalid-argument]` crashes were exactly this shape.
///
/// This wrapper:
///   * skips an empty map (`update({})` is itself rejected as invalid-argument),
///   * routes any rejection to [errorReport] (Crashlytics NON-fatal), tagged
///     with the doc path + payload, so the offending write becomes visible
///     instead of killing the app.
///
/// [ref] is `dynamic` so it also accepts the app's dynamically-typed refs
/// (e.g. `firestoreDb.collection(...).doc(...)`); it is cast to
/// [DocumentReference] internally. Returns the (already guarded) write Future
/// so a caller may still await it — it resolves normally even on failure.
Future<void> safeFsUpdate(dynamic ref, Map<String, dynamic> data, String tag) {
  if (data.isEmpty) {
    devPrint('[safeFsUpdate] $tag skipped empty update');
    return Future<void>.value();
  }
  DocumentReference docRef;
  try {
    docRef = ref as DocumentReference;
  } catch (e) {
    errorReport('[safeFsUpdate] $tag not a DocumentReference: $e');
    return Future<void>.value();
  }
  return docRef.update(data).catchError((Object e) {
    errorReport('[safeFsUpdate] $tag ${docRef.path} data=$data err=$e');
  });
} // end of safeFsUpdate

/// Forward [e] to [errorReport] (Crashlytics non-fatal) UNLESS it is a handled
/// [TimeoutException] from a best-effort read / time fetch. Those recover
/// gracefully (UI re-renders from cache, clock falls back to the device), so
/// reporting them is pure noise — log debug-only and skip Crashlytics.
void reportNonTimeout(dynamic e, [StackTrace? stack]) {
  if (e is TimeoutException) {
    devPrint('handled timeout (crash report skipped): $e');
    return;
  }
  errorReport(e, stack);
}

void trace(int debugNum) {
  int nowTime = DateTime.now().millisecondsSinceEpoch;
  devPrint(
    "$debugNum = Millisecond clock:${nowTime - launchTime}  = ${nowTime - debugTime}",
  );
  debugTime = nowTime;
}

int otqRandom(int minInt) {
  // generate random number for daily use
  // use Random.secure if possible
  const int rndMax = 99999999;
  int result = 0;
  try {
    result = globalRandom.nextInt(rndMax) + minInt;
  } catch (_) {
    dynamic rndGen = Random();
    result = rndGen.nextInt(rndMax) + minInt;
  }
  return result;
} // end of otqRandom

List<dynamic> searchTable(String rx, var myList) {
  // search rx as or regex in myList.
  // return all match elements
  List<dynamic> res = [];
  if (rx.trim().isNotEmpty) {
    List<String> rList = rx
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"\s+\b|\b\s"), ' ')
        .split(' ');
    // Compile each search term's RegExp ONCE up front. Previously a fresh
    // RegExp was compiled per (row x term) inside the loop, i.e. on every
    // keystroke for every row — the main cost of search lag on large tables.
    final List<RegExp> regexps = rList
        .map((rg) => RegExp(rg.toLowerCase()))
        .toList();
    res = myList.where((c) {
      bool? finalResult;
      for (final regexp in regexps) {
        bool result = false;
        for (var e in c) {
          if (regexp.hasMatch(e.toString().toLowerCase())) {
            result = true;
            break;
          }
        }
        finalResult = finalResult == null ? result : (finalResult && result);
      } // end of regexps
      return finalResult ?? false;
    }).toList();
  } else {
    res = List<dynamic>.from(myList);
  } // end if (rx.isNotEmpty)
  return res;
} // end of searchTable

int binarySearch2DDesc(dynamic arr, int column, int target) {
  // binary search on particular column of 2D array
  // note: that particular column should be sorted descending
  int low = 0;
  int high = arr.length - 1;

  // Handle potential out-of-bounds error for empty array
  if (high < 0) {
    return -1; // Not found
  }
  if (column > arr[0].length) {
    return -2; // column is out of bound
  }
  while (low <= high) {
    int mid = (low + high) ~/ 2; // Integer division for cleaner syntax

    // Check if the mid element's first element is the target
    if (arr[mid][column] == target) {
      return mid;
    } else if (arr[mid][column] < target) {
      // Search the left half
      high = mid - 1;
    } else {
      // Search the right half
      low = mid + 1;
    }
  }

  return -1; // Target not found
}

String getText(dynamic arr, int index) {
  String result;
  try {
    result = arr[index] ?? '';
  } catch (e) {
    result = 'No Text with index ${index + 1}.';
  }
  return result;
}

bool transactionOK() {
  // check if transaction can be done
  return transactionOKFlag.value;
} // end of transactionOK

void setTransactionOK(String from) {
  debugPrint('#################++ setTransactionOK from $from');
  transactionOKFlag.value = true;
} // end of setTransactionOK

void setTransactionNotOK(String from) {
  debugPrint('#################-- setTransactionNotOK from $from');
  transactionOKFlag.value = false;
} // end of setTransactionNotOK

Future<dynamic> waitUntilNotNullScreenTx(
  String from,
  String screenTxName,
  int maxLoop,
) async {
  dynamic state = transactionStore.state.screenTx;
  int loopCounter = 0;
  Duration backoffDuration = const Duration(milliseconds: 250);
  while (state[screenTxName] == null && loopCounter < maxLoop) {
    debugPrint('*** waiting in $from for screenTx[$screenTxName]');
    try {
      await Future.delayed(backoffDuration);
    } on Exception catch (e) {
      // Handle potential exceptions during unlock or write
      devPrint("!!! Error waiting for screeTx[$from]: $e");
    } // end try Future.delayed
    loopCounter++;
  } // end while (historyTableIsLocked)
  return state[screenTxName];
}

/*
    linkTransaction structure:
    {
      'Profile' : [
                    [19992090,'M',989756976878,989756976878,,,'Profile','E0',,,,,,'823989893333','My name'],
                    [19992092,'M',989756976878,989756976878,,,'Profile1','E0',,,,,,'823989893334','My name2'],
                  ],
      'Shop' :    [
                    [19992090,'M',989756976878,989756976878,,,'Profile','E0',,,,,,'823989893333','My name'],
                    [19992092,'M',989756976878,989756976878,,,'Profile1','E0',,,,,,'823989893334','My name2'],
                  ],
    }
*/

/*
  In Line documentation

  put:
     android.useAndroidX=true
     android.enableJetifier=true
  in android/gradle/gradle.properties

  To clean everything up do whenever it need:
    terminal:flutter clean
    sync all file system

  AndroidManifest.xml : com.vertriz.agenia; label : agenia

  android/gradle/build.gradle, add :
    // This block encapsulates custom properties and makes them available to all
    // modules in the project.
    ext {
      // The following are only a few examples of the types of properties you can define.
      compileSdkVersion = 28
      // You can also use this to specify versions for dependencies. Having consistent
      // versions between modules can avoid behavior conflicts.
      supportLibVersion = '1.0.0-beta01'
    }

  app/build.gradle :
    minSdkVersion 21
    targetSdkVersion 28

  Splash screen guide :
    https://medium.com/@diegoveloper/flutter-splash-screen-9f4e05542548

  https://github.com/flutter/flutter/issues/31740  => to eliminate FileNotFoundException error
    change line 6 of android/gradle/wrapper/gradle-wrapper.properties became :
    distributionUrl=https\://services.gradle.org/distributions/gradle-5.1.1-all.zip

  update android/gradle/build.gradle
    classpath 'com.android.tools.build:gradle:3.4.0'
    create my_backup_rules.xml in res/xml and enable backup as in
      https://github.com/mogol/flutter_secure_storage/issues/43
      https://developer.android.com/guide/topics/data/autobackup#IncludingFiles"

  redux tutorial :
    https://hackernoon.com/flutter-redux-how-to-make-shopping-list-app-1cd315e79b65
      implemented in redux_transaction

  signing procedure :
    https://flutter.dev/docs/deployment/android#signing-the-app
  publishing in google play :
    https://themanifest.com/app-development/how-publish-app-google-play-step-step-guide
 */
