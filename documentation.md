# Otonomiq Mobile Application Documentation
An Otonomiq mobile apps

## git setup
- in dos command run:
  gcloud auth login
  => then login with one@otonomiq.com browser
- and press allow
- gcloud config set project otq-01
- go to this url using one@otonomiq.com browser
  https://source.developers.google.com/auth/start?scopes=https://www.googleapis.com/auth/cloud-platform&state=
- run script given in command prompt.
  git should be ready to push

## GPS and Time
- GPS data is stored in singleton variable gpsData (Global)
- GPS time is stored in gpsTime (obs) and will be updated everytime gps data changed by stream.
- updateAppGps(Position) will update gpsData, gpsTime, time2GpsOffset, and state['#GPSDATA'] .
- updateAppGps(position) will be called every time GPS data is read.
- location stream will be started in serverSetup() <= main.dart
- gpsData and gpsPlaceMark are saved in secure storage. Loaded at the end of globalInit
- gpsTime is saved in preference (@lastGpsTime)
- gpsData (as diamond separated string) and gpsTime are stored in transactionStore ('#GPSDATA' & '#LASTGPSTIME')

## Release Note

### Fix: Image Upload to Firebase Storage (2026-05-20)
Perbaikan kegagalan upload image ke Firebase Storage yang menghasilkan error `InvalidImagePath-13`.

**Files Changed:**
- `lib/api.dart` — renamePath(), getPhotoCameraImage()
- `lib/firestore_repository/firestore_generic_repository.dart` — uploadToCloudStorage()
- `lib/firestore_repository/table_repository.dart` — uploadUpdateImage()

**Root Cause:**
1. File image disimpan di cache directory (`/data/.../cache/`) yang bisa dihapus Android kapan saja saat storage penuh. Ketika retry upload, file sudah tidak ada.
2. Retry counter di-increment 2x per attempt (di `uploadImageToCloud` dan `uploadUpdateImage`), sehingga max 5 retry habis dalam 3 attempt saja.
3. `saveImagePutInImageMap` dipanggil tanpa `await`, menyebabkan race condition dengan `sendImagesInImageMap`.
4. Kegagalan upload tidak di-log (file not found, no internet, lock failed semua silent), menyulitkan debugging.
5. Bug `folder.isEmpty` di `renamePath` menyebabkan `RangeError` pada `substring(0, -1)`.

**Perbaikan:**
1. **Persistent storage** — Image file dipindah dari cache ke `getApplicationSupportDirectory()/otq_images/`. Directory ini tidak akan di-clean oleh Android. Jika `File.rename()` gagal (cross-mount), fallback ke `copy()` + `delete()`.
2. **Fix double retry increment** — Hapus `imageMapUpdateUrl` duplikat di `uploadUpdateImage()`. Retry counter sekarang increment 1x per attempt (5 retry = 5 attempt).
3. **Await first upload** — `saveImagePutInImageMap` sekarang di-`await`, mencegah race condition dengan retry scheduler.
4. **Logging** — Tambah `devPrint` untuk semua failure path di `uploadToCloudStorage`: file not found, no internet, lock failed.
5. **Fix folder.isEmpty crash** — Ganti conditional ternary dengan explicit `endsWith('/')` check.

**Flow Diagram:**
```
Camera → renamePath() → app_support/otq_images/FTZIMG%2F{folder}___{file}.jpg
  → await saveImagePutInImageMap()
    → uploadToCloudStorage() [attempt 1]
      → success: imageMap updated, file deleted after 5s
      → fail: imageMap retry++ (1x only)
  → sendImagesInImageMap() [retry 2-5]
    → uploadImageToCloud() → uploadToCloudStorage()
      → success: imageMap updated
      → fail: retry++ until max 5
  → replaceLocalImageToUrl() [saat submit transaksi]
    → final attempt upload
    → jika retry >= 5: replace dengan defaultImage
```

### 0.9.75.04
- Max of position in event is 14, event[14] will be used for table definition. History sync table_repository.dart [1527]

### 0.9.25.12
- follow instruction on https://docs.flutter.dev/release/breaking-changes/flutter-gradle-plugin-apply
- upgrade flutter to 3.19.2
- upgrade kotlin to 1.9.22
- upgrade agp to 7.3.1

### 0.9.25.06
- [ ] Fix bug in pages that display wrong text (maybe about encoding char in firebase page)

### 0.9.19
- [X] time picker in cupertino mode
- [X] date picker in cupertino mode
- [X] date time picker in cupertino mode
- [X] "icon":[ICON] => "icon":"[ICON]" = https://otq-icon-hosting.web.app/
- [X] "url":"true" => value non case sensitive
- [X] "currentValue":"[VALUE]" => value = millisecond of the day | millisecond from epoch
- [X] widget keepalive: txf_full, OtqDropdown, OtqSwitch, QtqGetImages
- [X] Separate class widget : 
  - [X] OtqTxt
  - [X] OtqSwitch
  - [X] OtqDropdown
  - [X] OtqGetImages
  - [X] OtqRad (deprecated, backward compatible only)
  - [X] OtqRdo (new radio button)
  - [X] OtqTxf (with Radio Button option)
 
### 0.9.15
- [X] Invitation. New user can input invitation code (phone number). If there are more than 1 invitation code entry in firebase, then ask for country code (regular country code dropdown).
- [X] Contact picker
- [X] Date picker
- [X] Show pdf
- [ ] File / image multiple upload
- [X] Combo box

### 0.9.18
- [X] Fix gps coordinate 888,888 in initial selfie action
- [X] Add getImages widget
- [X] Put gpsPosition in rbt
- [X] QR decryption in txf
- [X] QR decryption in location, oppMode : qr-single
- [X] aec2Decrypt (version decryption)
- [X] Breaking change in Android 12. Guidance : https://medium.com/androiddevelopers/lets-be-explicit-about-our-intent-filters-c5dbe2dbdce0

## TODO List
- [X] Use camera flutter utility to use back/front camera
- [X] user cancelled google login => back to login page without display error dialog
- [X] logout / no account error => clear data, ready for new account
- [ ] handle red light when no return from function (timer?)
- [X] display different error when : no account / change device
- [X] Error msg for "GPS tidak ada"
- [X] Force data ready when reload
- [X] Change FromLink => Event
- [X] Use Firestore to submit event
https://github.com/felangel/bloc/blob/master/examples/flutter_firestore_todos/lib/main.dart
how to call addTodo
- [X] reload from JSON2  
- [ ] create notification handling for firebase_messaging ^9.1.4. Disabled "onResume" & "onLaunch" in firebase_notification_handler.dart, because they are replaced by "FirebaseMessaging.onMessageOpenedApp" since 8.0.0 (read changelog). Example is in https://firebase.flutter.dev/docs/messaging/notifications/ . Need to run "RemoteMessage initialMessage =
  await FirebaseMessaging.instance.getInitialMessage();" in main.dart. Then set stream
  // Also handle any interaction when the app is in the background via a
  // Stream listener 


    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'chat') {
        Navigator.pushNamed(context, '/chat',
        arguments: ChatArguments(message));
      }
    });
- [ ] Delete file in cloud storage when it was deleted in otq_get_image [326].
## building app documentation
1. Flutter version 2.10.4 . 
2. Problem with Flutter 3:
   1. otq_icons.dart [1518] Icons.six__ft_apart => Icons.six_ft_apart
   2. Not all library are upgraded to flutter 3 (wait).
3. Build app running : 

       flutter build appbundle --release
4. splash screen documentation : https://pub.dev/packages/flutter_native_splash
5. uncomment flutter_native_splash in pubspec.yaml dev block
6. splash definition is in flutter_native_splash.yaml
7. android < 12 use \assets\splash768.png (768x768)
8. android >= 12 use \assets\splash960.png (960x960) with logo 640 pixels in diameter. use with background.
9. in project directory run : dart run flutter_native_splash:create --path=D:\LinkApp\projects\production\otonomiq\flutter_native_splash.yaml
10. comment flutter_native_splash in pubspec.yaml

## firebase signing key for debug
1. C:\Program Files\Java\jdk-21\bin> .\keytool -list -v -keystore C:\Users\harto\key.jks
2. get sha1 and sha256 then put it in com.otonomiq.master1

## Icon list
https://otq-icon-hosting.web.app/

## Wi-Fi connection to device for debugging
1. When connected via USB, in terminal run: adb tcpip 5555. 
2. C:\Users\harto\AppData\Local\Android\Sdk\platform-tools\adb tcpip 5555
3. Disconnect USB, view phone IP from Settings > About Phone > Status. 
4. In terminal, run: C:\Users\harto\AppData\Local\Android\Sdk\platform-tools\adb connect 192.168.x.x and that's it.
5. Reference : https://developer.android.com/studio/command-line/adb#wireless

## Debugging with Xiaomi Redmi 4a
### Problem
Cannot turn on USB Debugging.
Turn off USB Debugging will introduce this problem
### Solution
No solution yet (18 Mar 2022). Solutions below has been expired.

https://stackoverflow.com/questions/46020237/install-app-via-usb-the-device-is-temporarily-restricted

"Install via USB" wont work if your Xiaomi phone is running MIUI 8 or above. Looks like when you try to Enable this option, your phone trys to connect to some chinese server and fails.

I got a work around and it worked for me. Idea is to connect to Chinese-Shanghai server through VPN. Try the following:

Install PlexVPN from Playstore and login into it. You will get a 24 hr free VPN service.
Select China-Shanghai server and connect.
From developer option in your Xiaomi phone, Enable "Install via USB".
You can then disconnect the VPN and logout from PlexVPN.
Enjoy!!

## Android 12 adjustments
put :

    android:exported="true"
in AndroidManifest.xml
## Mobile app generation procedure
1. Make sure no folder with app's name in D:/LinkApp/projects/production folder
2. Create new Flutter project wth IntelliJ.Idea with parameters:
- with java
- put com.vertika / com.agenia / com.xxx
3. Create Otonomiq2Schania.bat
4. Run Otonomiq2Schania.bat
5. Open in IntelliJ.Idea, run Flutter pub get
6. Build

## Autsorz specific

## Note from Harry Huang
1. launchCheck() is like autoexec.bat. Will be launched everytime app is launched.
2. vertrizLogin() will be called when signin event occur.
3. globalInit() will be run every launch before anything else.
4. qr_code_scanner was copied from git://github.com/juliuscanute/qr_code_scanner.git to prevent breaking code change. 
This is done because the wrapper plugin (qr_code_scanner) need minimum of api level 24. Since the original code can run with api level 21.

### Error note
#### - Local module descriptor class for providerinstaller not found.
Error when executing method get() from document reference. Should be gone when attached to bloc / stream provider

### Code sampler
    var argon = await argon2CreateHash("thisisapassword");
    // crypto not realy match   
    var hasher = HashCrypt("SHA-3/256");
    var encrypter2 = RsaCrypt();
    var pKey = '-----BEGIN PUBLIC KEY-----MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAIevYY6rxpKBNkjiQ0Nzp1BpUGVJljJDMT+mLfZBRro/vPLZC3O/eHoQ6hmC2YRboFi8ssHyoqBwABox98au6SMCAwEAAQ==-----END PUBLIC KEY-----';
    var pKey2 = encrypter2.pubKey;
    var rsaResult = encrypter2.encrypt("abcd", pKey2);
    devPrint ('Rsa : $rsaResult');
    var sha3Result = hasher.hash('abc');
    devPrint ('sha3 : $sha3Result'); // different from web https://www.movable-type.co.uk/scripts/sha3.html
    Digest s3 = Digest("Keccak-256");
    Digest sh3 = SHA3Digest(256);
    
#### Message Sending example
      var dt = '{"action":"DISPLAY","route":"{\\\"title\\\":\\\"Konfirmasi Pesanan\\\",\\\"targetVIDs\\\":[777250221000,777250221003,922250226073],\\\"mainTid\\\":\\\"Tid1111\\\",\\\"tag\\\":\\\"CONFIRMATION\\\",\\\"children\\\":[{\\\"type\\\":\\\"TXT\\\",\\\"beforeSpacing\\\":20,\\\"afterSpacing\\\":0,\\\"size\\\":24,\\\"bold\\\":\\\"TRUE\\\",\\\"data\\\":\\\"Pesanan: 2 Donut Keju. Masukan pin untuk menyetujui transaksi ini.\\\"},{\\\"type\\\":\\\"TXF\\\",\\\"variant\\\":\\\"pin\\\",\\\"digit\\\":6,\\\"obscure\\\":\\\"TRUE\\\",\\\"route\\\":\\\"{}\\\",\\\"interval\\\":300,\\\"signature\\\":\\\"111111\\\",\\\"position\\\":10,\\\"errorMessage\\\":\\\"PIN salah\\\",\\\"data\\\":\\\"Data to be put in position 10 when pin ok.\\\"}]}"}';
      var sTo = ["777250221000","777250221003"];
      var sF  = "777250221002";
    //  firestoreMsg = fsCollection+"/"+sTo+"/io/"+sF;
    //  firestoreNotif = fsCollection+"/"+sTo+"/io/"+sF;
    //  sendMessage(sTo,sF,"Pesan dari app3 multi to",dt,true,0);
    //  var a = 1;
    //  String test1 =
    //      '56a14255bf3070c3dfcb4cfe6e8f35e616c01ac2aa5d7792c0c0bf890d56afdfeea4fb05075ca2568b24a2c4970ce6351288cd531d0472e84696a463b48d8238';
    //  String pub512 = createPublicDH1(test1, dhP, dhG);
    //  String test512 = keccak512(test1);
    //  String test256 = keccak256(test1);
    
## GetX State Management
    tableSourceUpdated = state management for table
    tableContent = content of all tables
    internetConnectionFlag = true => connected, false => not connected
    transactionOKFlag = true => ok to do transaction, false => not ok
    appStatusColor = dot color in top right corner
    gpsTime = last time gps is read. change in this state = new gps data acquired
    gpsData = last gps data, not observable. Goes along with gpsTime
## Screen Transaction DataStore Keys:
    '#VID' = int Versatile ID
    '#GUEST_LIF' = ssid of guest lif
    '#GUEST_INDEX' = page index (relative from JSON!B50; 1 = B51) to display as home in guest lif
    '#INTERFACE_KEY' = string User Interface spreadsheet key
    '#SHEET_API' = bool is spreadsheet api ready
    '#INTERNET' = bool is connected to internet
    '#PHONE' = string users phone #
    '#SETTINGS' = output of settingUp()
    '#GPS' = users current gps location
    '#EMAIL' = string google account
    '#NOTIFICATION' = int # of notification
    '#CART' = int # of shopping cart
    '#UNREAD' = int # of unread messages
    '#TX_LOCK' = bool lock semaphore for transaction. For writing + deleting
    '#LOGIN_OK' = bool is this user log in
    '#has_user_login' = string, decrypted (qr:uqr) or raw scanned driver VID from the scanner widget; set on a valid scan, cleared when the VID is not in the workforce table. Mirrored to secure-storage key 'driverLogin' for persistence across app restarts (restored at globalInit; cleared on Keluar logout).
    '#ACTIVE_TASK' = string, tnm VID of the task doc currently being executed on P11 DeliveryWorkspace. Set by P10 TaskFeedList on card tap (before routing to P11). Read by resolveDriverCurlyTokens to resolve {activeTaskVid} and {tnm} (alias) in search/event strings. NOT cleared on P11 exit (stale value harmless; pending-safe guard).
    '#REJECT_TASK' = string, tnm VID of the task doc being rejected on the RejectTaskSheet. Set by DriverStopCard on Tolak tap (before routing). Read by resolveDriverCurlyTokens to resolve {rejectTaskVid} in search/event strings. NOT cleared on exit (stale value harmless; pending-safe guard).
    '#ACTIVE_VEHICLE' = string, lv VID of the stock_location doc tapped for opening/closing check on H1 VehicleFeedList. Set by VehicleFeedList on card tap (before routing to O1/C1). Read by resolveDriverCurlyTokens to resolve {activeVehicle} in search/event strings. NOT cleared on exit (stale value harmless; pending-safe guard).
    '#CHOSEN_DRIVER_VID' = string, workforce VID of the driver chosen by the checker on O1 ExecutorDesignateCard. Set by ExecutorDesignateCard on pick. Read by resolveDriverCurlyTokens for {chosenVid} and by CustodyCountSubmit O1 enable gate. Cleared on route change via ExecutorDesignateCard.clearO1State.
    '#CHOSEN_DRIVER_NAME' = string, denorm driver name (workforce `n` field) chosen by the checker on O1. Set alongside #CHOSEN_DRIVER_VID. Read for {chosenName} token. Cleared on route change.
    '#ACTIVE_WAREHOUSE' = string, `gl` field (gudang origin) from the aggregated task docs on O1. Set by CustodyCountList O1 variant once tasks load. Empty if no tasks (degrade-safe). Read for {warehouseId} token. Cleared on route change.
    '#GOOGLE_OK' = bool is this user already log in in google
    '#RECEIVE_LOG_OK' = bool is this user already specify at least 1 receive location
    '#PROFILE_OK' = bool is all needed profile entered
    '#CURRENT_ROUTE' = current screen name
    '#TYPE' = 'P'ersonal or 'C'ommunity
    '#NAME' = current user name
    '#USER_REPOSITORY' = user repository gained from main()
    '#FIREBASE_USER' = current firebase user. Not necessarily had successful login in vertriz. Handled by user_repository and login_bloc
    '#STORAGE_BUCKET' =  current firebase storage.
    '#IMEI' = current device imei (deprecated, change to #DID 200708 HH)
    '#DID' = current device id (imei in android, deviceId in ios)
    '#NEXTROUTE' = route that delayed. Will be displayed when timer is finished
    '#TIMER_CONTEXT' = saved context for timer bloc
    '#TIMER_BLOC' = saved timer bloc variable
    '#LOCATION' = Position. GPS location
    '#ACC_KEY' = Key of Account Spreadsheet for current user
    '#HUB_KEY' = Key of Account Spreadsheet for current user => deprecated not used 200710 HH
    '#FCM_TOKEN' = Firebase Cloud Messaging token
    '#SIGNIN_METHOD' = Google | Facebook | Twitter
    '#DEMO_SIGNUP_KEY' = Spreadsheet key of demo signup | Link Interface. got from GetLinkSettings
    '#ADDRESS' = User's address (40 chars vid)
    '#NEED_PINHASH' = If user don't have pin => true; otherwise false
    '#FS_DOC' = Firebase documentId from /dvc : user-loginxx/{uid}/dvc/{#FS_DOC}
    '#FS_IO' = Firebase path to current user's io collection (input output collection)
      complete firestore database structure for messaging service:
        users_xx/{uid}/dvc/{docId}/io/{vid}/msg
    '#FS_PATH' = full document path until /dvc : user-loginxx/(doc}/dvc
    '#FS_REF' = user's document reference. From this we can derive full path & documentID
    '#CLUSTER' = user's clusterID
    '#MSG_REF' = User's message document reference in msg_<cluster>
    '#COUNTRY' = User's country code (phone country code eg. '62','1')
    '#F_DOMAIN' = Google function domain used for this user
    '#DATA_OK' = bool, false = not possible to do any data transaction, true = ok
    '#VM_UPGRADE_INDEX' = VM index of JSON. Row = 50+state['#VM_UPGRADE_INDEX']. Index of upgrade route in subscriber's VM.
    '#GUEST_UPGRADE_INDEX' = Guest VM index of JSON. Row = 50+state['#GUEST_UPGRADE_INDEX']. Index of upgrade route in Guest VM.
    '#INTERNET' = bool, false = no internet connection, true = internet ok
    '#CAMERA' = bool, true = camera mode is on, refresh action cannot functioned; false = no camera activity.
    '#SIM_COUNTRY_CODES = List<String>, list of country code prefixz in all sim cards.
    '#CAMS' = List <CameraDescription>, list of available cameras.
    '#LASTGPSTIME' = Last timestamp.millisecondsSinceEpoch from GPS reading.
	'#GPSDELAYTIME' = Delay time (ms) to get #GPSDATA from gps data before it. Calculated from #LASTGPSTIME. At launch, initialized as 0
	'#GPSDATA' = Latest gps data in diamond separated. At launch, initialized as '--'
	'#WIDGET_COM' = (Not Used) 2D array [<to>][<widget key>]. Content = Json object.
       {
         "data": diamond separated string, data that preceed <to> screen data. <to> screen data should be written after this
       }
    '#LQR_LIST' = Map<String,String>. List of location qr for user. This data will be read from proxy at the beginning of app start (main.dart) and when login succesfull (runSheetStartup).
        Source : proxy op1!I12M211, then saved to storage (secured storage)
        Content : <location name>◆<latitude>◆<longitude>◆<tolerance (m)>
        Example:
        {
          "0l8a2c51ba86a08e0c33bdfaac513b025d0e59136d" : "Bandung Tech Center◆-6.89609◆107.58163◆30"
        {
    '#LQR_REF' = List<String,dynamic>
         Example : {"0l8a2c51ba86a08e0c33bdfaac513b025d0e59136d" :["Bandung Tech Center",-6.89609,107.58163,30]}
    '#THEME' = Theme used in this app. Set in api.dart => buildTheme
    '#LOCALE' = Device's locale in form 'en_US'
    '#REF_TIME_START' = Ntp / GPS reference time of defice start (ms from epoch)
    '#DEVICE_TIME_START' = Device time start (ms from epoch)
        to get current ntp time : REF_TIME_START + DateTime.now() - DEVICE_START 
    '#FS_USER_DOC_ID' = firebase doc id for current user. Null if not logged in
    '#REFTABLE<tableCode>' = firestore document reference to table
    '#TABLE<tableCode>' = tablecontent of the a table
    '#DEVICE_LISTENER' = listener for firestore dvc document for htis user
    '#TABLE_HISTORY' = table history of the events. Content of this entry will be converted to tableContent['_HISTORY'].
       Safed in secure storage as '_HISTORY', and in firestore proxy 'h'
## Notification & Message Handling
###firebase_messaging: ^9.1.4
#### Ref: https://firebase.flutter.dev/docs/messaging/notifications/

# Secure Storage Keys:
    'myAcc' = ssid of account.
    'myCluster' = Cluster Id.
    'myLif' = ssid of LIF spreadsheet.
    'myPath' = firebase full path collection /dvc.
    'pinHash' = Argon2 pin hash (master pinHas is in LIF Settings!G10).
    'bucket' = storage bucket address.
    'funcDomain' = nearest function domain.
    'myMsgId' = message Id used in as document name in msg_XXX for this user. 
                Written by function firstLogin.
    'lqrList' = location qr list as described in datastore key #LQR_LIST.
    'ui_pages' = last all pages. Format = {<page name>:{t:checksum;c:{json content}}. 
    'ui_systems' = last all systems ui settings.
    'gpsData' = last gps data. Format = <latitude>◆<longitude>◆<accuracy>◆<timestamp>◆<altitude>◆<speed>◆<speedAccuracy>.
    'gpsPlaceMark' = last gps place mark.
    'appSettings' = last result from GCF functionName['appSettings'] ~ /appSettings3.
    'driverLogin' = persisted driver VID (mirrors #has_user_login in transactionStore). Written on a successful scanner VID scan, deleted on Keluar logout (and on a workforce not-found scan). Read at globalInit to restore the driver session.

# Shared Persistence Keys:
    '@pages' = deprecated 1 Feb 2024,last all pages. Get from readSettings.Deleted when logout.
    '@screenUI'= should be deprecated 1 Feb 2024, last all pages. Get from readSettings.Deleted when logout.   
    '@localeText' = compressed localeText string.
    '@localeCheckSum' = checksum of proxy's Locale text. Location cell defined in appSettings function.
    '@lastGpsTime' = last gps time. Persistent version of gpsTime state. 
    '@guestScreenUI' = guest/login screenUIComponent snapshot. Written at guest bootstrap, restored on signOut for instant login page render.
    '@guestSystemUI' = guest/login systemUIComponent snapshot. Written at guest bootstrap, restored on signOut for instant login page render.
    '@authedSystemUI' = last authenticated systemUIComponent snapshot. Written by readSettings/readSettingsContext/proxy System refresh when settingKey (or proxy ssid) is not the guest/signup key. NOT cleared on signOut; survives across sessions. Used for cache-first navbar restore on login so the full bottomBar paints on the first authenticated frame.

# GetX State management
## Directory
State directory : lib/states. Contains class of states.
every class extends GetxController, with update() function called every time the state changed.
### app_code_controller
Application code and code definition
### mobile_table_controller
Table controller for table in firestore root.mobileTable collection.
root.mobileTable.<appVid>.tables.<tableName>.content.<autoId>
mobileTable,tables,contents are collections
<appVid> = application VID (document)
<tableName> = application unique table name (document)
<autoId> = random Id generated by firestore (document)
<autoId> document = a logical record in table <tableName>
# Bloc documentation
## Login
### Events
#### EmailChanged (String email)

#### PasswordChanged(String password)

#### SmsCodeChanged(String smsCode)

####LoginFailWithStatus(String uid, int status)
status :

  802 : ERROR 802 ; ERROR 802 Login gagal; Anda mencoba masuk di perangkat lain. Untuk faktor keamanan, anda hanya dapat menggunakan satu akun pada satu perangkat. Anda perlu otentifikasi ulang jika ingin masuk di perangkat lain.
  
  809 : ERROR 809 ; ERROR 809 Login gagal; Anda belum memiliki akun.; Mohon hubungi administrator untuk mendaftarkan akun anda.
  
  810 : ERROR 810 ; Error 810 GPS tidak berfungsi ; Pengaturan ‘pelacakan GPS’  serta ‘pelacakan catatan GPS’ pada perangkat anda tidak berfungsi. Anda diminta untuk selalu mengaktifkan GPS oleh perusahan.; Mohon aktifkan pengaturan ‘pelacakan GPS’  serta ‘pelacakan catatan GPS’ pada perangkat anda.

### State
#### loginError
isFailure : true,

loginStatus : <status from event>

  802 : ERROR 802 ; ERROR 802 Login gagal; Anda mencoba masuk di perangkat lain. Untuk faktor keamanan, anda hanya dapat menggunakan satu akun pada satu perangkat. Anda perlu otentifikasi ulang jika ingin masuk di perangkat lain.
  
  809 : ERROR 809 ; ERROR 809 Login gagal; Anda belum memiliki akun.; Mohon hubungi administrator untuk mendaftarkan akun anda.
  
  810 : ERROR 810 ; Error 810 GPS tidak berfungsi ; Pengaturan ‘pelacakan GPS’  serta ‘pelacakan catatan GPS’ pada perangkat anda tidak berfungsi. Anda diminta untuk selalu mengaktifkan GPS oleh perusahan.; Mohon aktifkan pengaturan ‘pelacakan GPS’  serta ‘pelacakan catatan GPS’ pada perangkat anda.


11uaYqDG8kEp0yPxgH9qyUr-7_FRZRTKUNy92qbBAZQ4	Active!A1502:J3001	Self	1NBrUBlOwzOL7v3MlWPh9rK4Ke-X4meZS-gEgOdr4vvo	Active!A1502:J3001
11uaYqDG8kEp0yPxgH9qyUr-7_FRZRTKUNy92qbBAZQ4	Active!A3002:J4501	Self	1NBrUBlOwzOL7v3MlWPh9rK4Ke-X4meZS-gEgOdr4vvo	Active!A3002:J4501
11uaYqDG8kEp0yPxgH9qyUr-7_FRZRTKUNy92qbBAZQ4	Active!A4502:J6001	Self	1NBrUBlOwzOL7v3MlWPh9rK4Ke-X4meZS-gEgOdr4vvo	Active!A4502:J6001

8	800008	ReadCP	TRUE	Server19004★4.2112.6★2272	1641360895980	1641361157507	Server16328★4	4	Read Active!A4502:J6001 			1.86		FALSE

# White label
## App Icon Generator
https://www.appicon.co/
Create App Icon Images: Create your app icon images in various sizes. You can use an online tool like App Icon Generator to generate the required sizes.  
Add Icon Images to Xcode Project:  
Open your Flutter project in Xcode by navigating to the ios directory and opening the .xcworkspace file.
In Xcode, go to the Assets.xcassets folder.
Drag and drop the generated icon images into the AppIcon section in Assets.xcassets.
Update Info.plist:  
Ensure that the CFBundleIcons entry in your Info.plist file is correctly configured to use the new app icons.

## Asset needed
### Logo
1024x1024
put in assets/images/logo.png
### Other
Privacy policy web page like:
https://autsorz.com/privacy-policy/
https://autsorz.com/PrivacyPolicyAdrifaEPatrol.html
## Android Google Play Store
### Logo
1024x1024
960x960
768x768
576x576
512x512
384x384
300x300
288x288
192x192
144x144
96x96
72x72
48x48

### Graphics
Halaman Login
Feature Graphic
Flash Screen (3 atau 4)

## Apple App Store
1. create an identifier in apple developer account
   1. go to https://developer.apple.com/account/resources/identifiers/list
   2. click on the "+" button
   3. choose "App IDs" and click "Continue"
   4. fill in the description and bundle ID (com.autsorz.test1)
   5. enable Sign In with Apple
   6. click "Continue" and "Register"
2. create an app in app store connect
   1. go to https://appstoreconnect.apple.com/
   2. click on "My Apps" and then the "+" button
   3. enable iOS only
   4. fill in the app name that will be displayed in the app store
   5. fill in the primary language (Indonesia)
   6. fill in the bundle ID that was created in the previous step (com.autsorz.test1)
   7. fill in the SKU (Stock Keeping Unit) which is a unique identifier for the app (com.autsorz.test1)
3. create app build in flutter project
   1. copy the source code

# history
## history structure

example
[[
1741135642472, // column A
"paskalHyperSquare", // column B
"0attendance-check-in◆1741135642319◆checkpoint◆0lea63c0912a8bbdf1f1c6cfbf538f3e92d38cd167◆-6.9161386◆107.594022◆◆ID◆40181◆Jawa Barat◆Kota Bandung◆Kecamatan Andir◆Ciroyom◆◆◆true-location⬤", // column C
"location",
"attendance-check-in",
"05 Mar 2025 07:47",
"√", // sent to firestore proxy/<ssid>/Event
"√", // 
"√", // sent to proxy>Event sheet
1741135642312, // time stamp of respective status
1741135642889,
1741135644076,
{}, // additional structure
[], // additional array
null
]]

# imageMap
map of local image path (without aum__) to url in firebase storage. 
declared in global.dart as
Map<String, List<dynamic>> imageMap = {};
## imageMap structure
### key = local path in mobile device without aum__ prefix and without __mua suffix
### content
Array of 4 elements. 
0 = int, timestamp of added. Milliseconds from epoch. Subject of deletion if age is more than 31 days
1 = String, url of image in firebase storage. If it is not uploaded, the value = '--'
2 = bool, true if url has replaced the local path in history.
3 = int, number of upload tries. maxImageUploadRetry (5) is the maximum. If it reach the maximum, then it can be processed or backup.
4 = int, timestamp of last upload attempt. If it is less than 1 minutes, then it cannot be processed. If it is locked for more than 1 minutes, then it can be uploaded (need to put another timestamp).
    <= 0 not locked

### example
{
  "aum__<local path>": [<timestamp>, "<url>", <history updated>,<int>],
"/data/user/0/com.autsorz.mobile/cache/id%2F2025%2Fsatria-prawira-mahardika%2Ffield-report%2Fandika-saputra%2F46860485124982-2025-02-26-08-02-51_fc0f8.jpg"
:[1740500867945
,https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/andika-saputra%2F46860485124982-2025-02-26-08-02-51_fc0f8.jpg?alt=media&token=30e55f7e-7a5e-44ab-a77b-eced57355cd3
, true,1,0]
}
"/data/user/0/com.autsorz.mobile/cache/id%2F2025%2Fsatria-prawira-mahardika%2Ffield-report%2Fandika-saputra%2F46860485124982-2025-02-26-08-02-51_fc0f8.jpg"
:[1740500867945
,"aume__InvalidImagePath-12__eaum"
, false,5,1740500890945]
}