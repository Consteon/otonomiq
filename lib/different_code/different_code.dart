/*
  otonomiq master

  pieces of code that can be different among app variant. Current build variants are :
    agenia       (agenia)
    autsorz
	schania
	otonomiq

  there are other files that different
    pubspec.yaml
    android/app/src/main/res/drawable/launch_image_png
    ic_launcher.png (logo) in :
      android/app/src/main/res/mipmap-hdpi
      android/app/src/main/res/mipmap-mdpi
      android/app/src/main/res/mipmap-xhdpi
      android/app/src/main/res/mipmap-xxhdpi
      android/app/src/main/res/mipmap-xxxhdpi

   app name (https://www.woolha.com/tutorials/flutter-change-app-launcher-icon-name-android-ios)
   android/app/src/main/AndroidManifest.xml (for android only)
   ios/Runner/Info.plist (for ios only)

   app Id / package name (https://stackoverflow.com/questions/51534616/how-to-change-package-name-in-flutter)
     android/app/build.gradle
     android/app/src/main/AndroidManifest.xml (for android only)
     android/app/src/java/com/vertika/vdemo/MainActivity.java
     rename folder above to android/app/src/java/com/<COMPANY>/<APPNAME>

   appsKey :
     1 : autsorz
	 2 : Schania
	 3 : Otonomiq
	 4 : Agenia

	 populate d:\LinkApp\projects\unique\otonomiq with :
	  different_code.otonomiq (this file)
	  hdpi.png (48x48)
      mdpi.png (72x72)
      xhdpi.png (96x96)
      xxhdpi.png (144x144)
      xxxhdpi.png (192x192)
	  google-services.json (got from registering com.otonomiq.mobile to firebase with
	    sha1 debug : 89:40:30:2C:68:83:89:92:CE:EF:A0:E0:8D:2F:2B:57:67:F7:4B:1C
		sha1 production : get it from playstore
	    in https://console.firebase.google.com/project/otq-01/overview )

	 To create app, go to https://docs.google.com/spreadsheets/d/1DxrT_jjlmKQ3wNqql4G7MT24TCoghCNXwcjFAmCcjns/edit#gid=456416398
	 Edit Settings!B4:E7
	 copy Bat!A3:A to autsorz2otonomiq.bat
	 then run autsorz2otonomiq.bat

	 for first time:
	 open new folder in intellij. Enable dart support. Put D:\flutter\bin\cache\dart-sdk in dart sdk setting
	 run pubspec get

 */

const bool demoVersion = false;
const appName = 'Otonomiq';
const appsKey = "3"; //= will be used for cloud function. Should be an Apps Id.
const bool devModeConst = false; // true : using devSystem; false using system
const defaultAppVid = 60936087747650; // todo replace with otonomiq vid
const tableVid =
    60936087747650; //= folder of all table in firestore under MobileTable
const defaultCloudConfig = {
  "minimumVersion": "0.9.12",
  "minVerRoute": "error809",
  "guestUpgradeIdx": 7,
  "vmUpgradeIdx": 8,
  "guestRoute": "home",
  "location": "{}",
  "locRange": "op1!I12:M211",
  "systemRange": "JSON!B6:E49",
  "screenRange": "JSON!B51:E",
  "screenRange2": "JSON2!B51:E",
  "testInterfaceKey": "13HZHLrfzf8y-5YBGN76n_u6BrZx0V_gebn2y971tRXw",
  "signupLif": "18MAwk8_l2ADCpuOPaQAzMykDpTZZhVFjP1n5Kcn_RTk",
  "signupIdx": 1,
  "signupDemo": "1B0tI2O89HtDY-t_yt9-_QP9MrkmFSwRNymfSYPAZai8",
  "vidKey": "1LVZIncIFXQsUaG_DDmIEJai4-by-ZpyDhTYFk4DjFk8",
  "devInterfaceKey": "1btHbSqofEmIvHo1W2oHsv0Tnfuli_ZWcUtxDm1UWe7o",
  "devSystemRange": "Json!B6:E49",
  "devScreenRange": "Json!B51:E",
  "localeChecksum": "Locale!B15",
  "localeRange": "Locale!B17:C"
};

const defaultOfflineLoginPage = {
  // Otonomiq
  "title": "Sign In",
  "children": [
    {
      "type": "IMG",
      "url":
          "https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/c%2Fotonomiq%2Fotonomiq-signup-300x90.png?alt=media&token=a04e0026-aedd-4898-ab94-804185fb7183",
      "height": 120,
      "alignment": "left",
      "beforeSpacing": 0,
      "afterSpacing": 0
    },
    {
      "type": "SIGNUP",
      "left": "TRUE",
      "leftPadding": 0,
      "rightPadding": 0,
      "beforeSpacing": 10,
      "afterSpacing": 0,
      "font": "default",
      "size": 18,
      "color": "FF001A72",
      "text1":
          "Saya telah membaca dan setuju dengan Syarat dan Ketentuan, Pemberitahuan Privasi, dan Peraturan Layanan tertulis di link ini.",
      "text2": "Saya Setuju",
      "text3": "Nomor Ponsel Terdaftar",
      "text4": "Contoh : 08xxx",
      "text5": "Masuk",
      "text6": "Nomor ponsel tidak valid",
      "text7": "Nomor undangan sudah kadaluarsa",
      "text8": "Ada user lain yang sign up dengan Google account ini",
      "text9": "Ada user lain yang sign up dengan Facebook account ini",
      "text10": "Ada user lain yang sign up dengan Twitter account ini",
      "text11": "Akun dalam kondisi terblokir",
      "text12": "Login gagal",
      "route": "_Invitation",
      "google": "Masuk menggunakan Google"
    }
  ]
};
final defaultGuestLine = defaultCloudConfig[
    "signupIdx"]; // login page in guess | Proxy JSON row 50 + defaultGuessLine
final String defaultGuestHome = defaultCloudConfig["guestRoute"]
    .toString(); // login page in guess | Proxy JSON row 50 + defaultGuessLine
