import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:geolocator/geolocator.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';

import 'api.dart';
import 'bloc_submit/bloc.dart';
import 'bloc_timer/bloc.dart';
import 'firebase_options.dart';
import 'firestore_repository/firestore_generic_repository.dart';
import 'firestore_repository/proxy_repository.dart';
import 'firestore_repository/table_repository.dart';
import 'global.dart';
import 'login/api/user_repository.dart';
import 'login/bloc_authentication/bloc.dart';
import 'login/bloc_login/bloc.dart';
import 'login/page/simple_bloc_delegate.dart';
import 'login/page/splash_screen.dart';
import 'login/page/tos_page.dart';
import 'notification/bloc.dart';
import 'page/test_page.dart';
import 'page/vertriz_app.dart';
import 'part/build_part/channel.dart';
import 'redux/screen_transaction.dart';
import 'ticker.dart';
import 'widget/build_theme.dart';
import 'widget/ui_component.dart';

final navigatorKey = GlobalKey<NavigatorState>();
// Sets a platform override for desktop to avoid exceptions. See
// https://flutter.dev/desktop#target-platform-override for more info.

void main() async {
  debugCount = -1;
  trace(debugCount);
  WidgetsFlutterBinding.ensureInitialized(); // needed by flutter error message
  // Paint the loading screen immediately, BEFORE the multi-second Firebase +
  // globalInit bootstrap, so the user sees "Loading…" instead of a blank
  // window. SplashScreen is self-contained (no Firebase/globals), so it is
  // safe to render this early.
  runApp(const _BootstrapLoadingApp());
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firestore offline persistence: pinned ONCE, immediately after
  // Firebase.initializeApp and BEFORE any Firestore use (globalInit below is
  // the first user). Settings cannot change after the first Firestore call,
  // and the old per-call-site toggles in table_repository.dart fought each
  // other (historySync set false, saveHistory set true). Native direct
  // writes (writeNativeFields / createNativeDoc*) rely on this cache to
  // queue offline writes and serve offline queries. persistenceEnabled:true
  // matches the mobile SDK default, so a hot-restart re-assignment is a
  // no-op (no settings-mismatch throw). Cache size stays default.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // Crash reporting. Disabled in debug so dev runs don't pollute the console.
  // Captures uncaught Flutter framework errors and async/platform errors;
  // errorReport() (the app-wide sink) forwards non-fatal errors separately.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );
  FlutterError.onError = (errorDetails) {
    if (kDebugMode) {
      FlutterError.presentError(errorDetails);
    } else {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  enablePlatformOverride();
  debugCount = -2;
  trace(debugCount);
  await globalInit();
  // Loading screen was already painted before Firebase init above; the real
  // app replaces it with a second runApp() once the home shell is ready.
  debugCount = -3;
  trace(debugCount);
  // await apiTest();
  // debugCount = -4;
  // trace(debugCount);
  dynamic state;
  User? fUser;
  try {
    debugCount = 1;
    trace(debugCount);
    String? myLif;
    rangeLink = fromLink + "!A:Z";
    // int? lastGTime = prefs.getInt('@lastGpsTime');
    // if (lastGTime == null) {
    //   lastGTime = 0;
    //   await prefs.setInt('@lastGpsTime', lastGTime);
    // }
    // setTransactionNotOK('main');
    // setTransactionOK('main');
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#REFRESH': false,
          '#DATA_OK': false,
          '#GPSDELAYTIME': 0,
          '#GPSDATA': empty,
        }),
      ),
    );
    Map<int, TextEditingController> ct = {};
    ct[1] = TextEditingController();
    ct[3] = TextEditingController();
    // mobileLayout = (MediaQueryData.fromView(WidgetsBinding.instance.window)
    //         .size
    //         .shortestSide) <
    //     600;
    mobileLayout =
        (MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ).size.shortestSide) <
        600;
    if (mobileLayout) {
      // mobile
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      // tablet or desktop
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } //if (shortest < 600)

    debugCount = 2;
    // Start the serverSetup-independent reads concurrently to shave cold-start
    // latency. deviceIdF is error-swallowing because on the logged-OUT path
    // (fUser == null) it is never awaited — an un-awaited rejected future would
    // otherwise surface as an unhandled async error -> Crashlytics fatal.
    // serverSetup stays awaited HERE to preserve producer-before-consumer
    // ordering of the #SETTINGS dispatch that the lines below read.
    final fUserF = getFirebaseUser();
    final myLifF = storage.read(key: 'myLif').catchError((_) => null);
    final deviceIdF = getDeviceId().catchError((_) => '-');
    await serverSetup();
    debugCount = 22;
    trace(debugCount);
    state = transactionStore.state.screenTx;
    var res = json.decode(state['#SETTINGS'][0]['body']);
    debugCount = 23;
    var defaultLifKey = res['signupLif'];
    loginSsid = res['signupLif']; // default signupLif
    var invitationKey = res['signupDemo'];
    debugCount = 3;
    fUser = await fUserF;
    debugCount = 31;
    trace(debugCount);
    myLif =
        await myLifF; // null-on-error preserved by .catchError on hoisted future
    debugCount = 32;
    debugCount = 33;
    trace(debugCount);
    if (fUser != null) {
      String? userDocId = await checkIfUserReset(
        fUser,
        await deviceIdF,
      ); // check in firebase if user reset
      if (userDocId == null) {
        myLif = null;
        await kickedOut();
      } else {
        transactionStore.dispatch(
          UpdateScreenTxAction(
            ScreenTransaction({
              '#FIREBASE_USER': fUser,
              '#FS_USER_DOC_ID': userDocId,
            }),
          ),
        );
        subscribeToUserReset(userDocId); // listen to dvc
      } // end if (userReset)
    } //if (fUser != null)

    debugCount = 34;
    trace(debugCount);
    // if (myLif == null) {
    //   await storage.write(
    //       key: 'myLif',
    //       value: defaultLifKey); // store in secure & persistent storage
    //   myLif = defaultLifKey;
    // }
    if (myLif == null) {
      try {
        // Attempt 1: Normal write
        await storage.write(key: 'myLif', value: defaultLifKey);
      } on PlatformException catch (e) {
        // Detect the specific "NullPointerException" or general platform failure
        devPrint("Storage corrupted. Resetting... Error: $e");

        // HEALING LOGIC:
        // 1. Wipe the corrupted storage container
        await storage.deleteAll();

        // 2. Retry the write immediately after the wipe
        await storage.write(key: 'myLif', value: defaultLifKey);
      } catch (e) {
        // Fallback for other non-platform errors
        devPrint("Unexpected error writing to storage: $e");
        // Optional: decide if you want to proceed or rethrow
      }

      // Success (either on first try or after healing)
      myLif = defaultLifKey;
    }

    debugCount = 4;
    trace(debugCount);
    //    var pa = Uri(path: Uri.encodeFull("sounds/scanner-beep.mp3")).path;
    //    scannerBeep = await rootBundle
    //        .load("sounds/scanner-beep.mp3")
    //        .then((ByteData soundData) {
    //      return pool.load(soundData);
    //    });
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#SIGNUP_KEY': defaultLifKey})),
    );
    if (demoApp && fUser != null && myLif == defaultLifKey) {
      myLif = invitationKey;
    }
    if (fUser == null) {
      myLif = defaultLifKey;
    } // end if (fUser == null)
    // subscribeToProxy(myLif); // listen to proxy firebase
    if (myLif != defaultLifKey && myLif != invitationKey) {
      // if user logged in
      var myClt = await storage.read(key: 'myCluster');
      // Resolve the inbox path HERE, from secure storage, not only inside
      // readSettingsStart's firstTimeRun branch (api.dart:2162). A warm start
      // with a populated @screenUI cache takes the cache branch (api.dart:2249)
      // and never reaches that assignment, so firestoreIO stayed on its boot
      // default (`users_<fsName>`, global.dart:762/863) until the opt-2 loader's
      // 27-38s CF fetch landed -- if it landed at all. The notification stream
      // (notification_repository.dart:34) then queried a collection with no
      // 'lt' field and the inbox rendered empty: no chips, no unread badge.
      var myMsg = await storage.read(key: 'myMsgId');
      if (myClt != null && myMsg != null) {
        firestoreIO = msgIoPath(myClt, myMsg);
        firestoreMsg = firestoreIO;
      }
      // Logs null too, so a secure-storage miss is visible instead of silently
      // leaving firestoreIO on the boot default.
      devPrint('[inbox] warm start: clt=$myClt msgId=$myMsg -> $firestoreIO');
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#CLUSTER': myClt,
            '#INTERFACE_KEY': myLif,
            '#CURRENT_ROUTE': home,
          }),
        ),
      );
      loadHistory(clearHistory, 'main[175] <= async');
      //      runLifInstructions('2'); //   run Instructions2 in background
    }
    debugCount = 5;
    trace(debugCount);
    //    await readSettings(myLif);
    final UserRepository userRepository = UserRepository();
    debugCount = 51;
    trace(debugCount);
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({'#USER_REPOSITORY': userRepository}),
      ),
    );
    localeText = jsonDecode(
      stringDecompress(prefs.getString('@localeText')) ?? '{}',
    );
    syncLocaleTable();
    // setTransactionOK('main');
    debugCount = 52;
    trace(debugCount);
    // Watchdog: never let the (possibly network-bound) settings load block the
    // splash forever. On timeout we proceed to runApp and mount the home shell
    // from cache; the secondary background loader refreshes pages a moment
    // later. The inner http.post calls also have their own 15s timeouts.
    await readSettingsStart(myLif, 1).timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        devPrint('readSettingsStart timed out; mounting from cache');
      },
    ); // *** need to delete
    buildTheme(systemUIComponent[theme]);
    debugCount = 6;
    trace(debugCount);
    constructHomeElements();
    debugCount = 7;
    trace(debugCount);
    //    BlocSupervisor.delegate = SimpleBlocDelegate();
    // Debug-only: SimpleBlocDelegate logs every bloc event incl. password
    // change events. Keep it out of release builds.
    if (kDebugMode) {
      Bloc.observer = SimpleBlocDelegate();
    }
    state = transactionStore.state.screenTx;
    if (state['#INTERFACE_KEY'] != null &&
        state['#INTERFACE_KEY'] != '' &&
        state['#INTERFACE_KEY'] != loginSsid) {
      subscribeToEvent(state['#INTERFACE_KEY']);
    }
    // launchCheck() does FCM setup + Firestore reads + a pin-hash cloud call.
    // None of it is needed to paint the home shell (already built from cache),
    // so run it off the critical path after the first frame instead of
    // blocking startup on it.
    if (state['#VID'] != null && state['#VID'] != '') {
      unawaited(
        launchCheck()
            .then((launchOk) {
              debugCount = 8;
              trace(debugCount);
              if (launchOk > 0) {
                debugPrint('launchCheck returned $launchOk (background)');
              }
            })
            .catchError((e) {
              debugPrint('launchCheck error (background): $e');
            }),
      );
    }
    {
      debugCount = 9;
      /*
      // argon2 example
      var uPw = "112233";
      var pwHashStore1 = await argon2CreateHash(uPw);
      var pwHashStore2 = await argon2CreateHash(uPw);
      var pwMatch1 = await argon2VerifyPassword(uPw,pwHashStore1);
      var pwMatch2 = await argon2VerifyPassword(uPw,pwHashStore2);
      var pwMatch3 = await argon2VerifyPassword(uPw,'\$argon2id\$v=19\$m=65536,t=2,p=1\$wRFGOjz+sMqFu+0stJaXjg\$dzmcIMGSaI49Brxm6AqKMHkbqKlsJwtyYzRT9DKxDT8');
      */

      //var myData = await getVidData (); // read my firestore data
      //await updateVidData ('fcm', 'fcmtoken222');

      runApp(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthenticationBloc>(
              create: (context) =>
                  AuthenticationBloc(userRepository: userRepository)
                    ..add(AppStarted()),
            ),
            BlocProvider<TimerBloc>(
              create: (BuildContext context1) {
                TimerBloc timerBloc = TimerBloc(ticker: Ticker());
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({'#TIMER_BLOC': timerBloc}),
                  ),
                );
                return timerBloc;
              },
            ),
            BlocProvider<LoginBloc>(
              create: (context) => LoginBloc(userRepository: userRepository),
            ),
            BlocProvider<NotificationBloc>(
              // eager (not lazy): the bloc must exist at app start so
              // NotificationBloc.instance is set before api.dart re-dispatches
              // LoadNotification when firestoreIO is resolved — otherwise the
              // inbox intermittently stays bound to the boot-time default path.
              lazy: false,
              create: (BuildContext contextN) {
                return NotificationBloc(
                  notificationRepository: FirebaseNotificationRepository(),
                )..add(LoadNotification());
              },
            ),
            BlocProvider<MessageBloc>(
              create: (BuildContext contextN) {
                return MessageBloc(
                  messageRepository: FirebaseMessageRepository(),
                )..add(LoadMessage());
              },
            ),
            BlocProvider<SubmitBloc>(
              create: (BuildContext contextN) {
                return SubmitBloc(submitRepository: FirebaseSubmitRepository())
                  ..add(LoadSubmit());
              },
            ),
          ],
          child: App(key: UniqueKey(), userRepository: userRepository),
        ),
      ); // end of runApp
    }
  } catch (err) {
    runApp(TestApp(flag: 'Error: ${err.toString()}'));
  }
} // end of main

// Minimal loading shell shown by the first runApp() call while the bootstrap
// in main() finishes. Replaced by the real App once the home shell is ready.
class _BootstrapLoadingApp extends StatelessWidget {
  const _BootstrapLoadingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

class AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    if (bloc is Cubit) debugPrint(change.toString());
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    debugPrint(transition.toString());
  }
}

void getSettingJson(var rawData) {
  for (var i = 0; i < rawData[0].valueRanges[0].values.length; i++) {
    String combination = combineJson(rawData[0].valueRanges[0].values[i]);
    systemUIComponent[rawData[0].valueRanges[0].values[i][0]] = combination;
  }
  for (var i = 0; i < rawData[0].valueRanges[1].values.length; i++) {
    var combination = combineJson(rawData[0].valueRanges[1].values[i]);
    screenUIComponent[rawData[0].valueRanges[1].values[i][0]] = combination;
  }
}

class App extends StatelessWidget {
  final UserRepository _userRepository;

  const App({required Key key, required this._userRepository})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    SubmitBloc submitBloc = BlocProvider.of<SubmitBloc>(context);
    TimerBloc timerBloc = BlocProvider.of<TimerBloc>(context);
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#TIMER_BLOC': timerBloc,
          '#SUBMIT_BLOC': submitBloc,
        }),
      ),
    );
    return GetMaterialApp(
      // localeResolutionCallback: (
      //     Locale? locale,
      //     Iterable<Locale> supportedLocales,
      //     ) {
      //   return locale;
      // },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Define supported locales.
      supportedLocales: const [
        Locale('en', ''), // English
        Locale('id', ''), // Indonesian
        // Add other locales your app supports
      ],
      home: BlocBuilder<AuthenticationBloc, AuthenticationState>(
        //        bloc: BlocProvider.of<AuthenticationBloc>(context),
        builder: (BuildContext context, state) {
          // ignore: missing_return
          Widget ret = const SplashScreen();
          if (state is Uninitialized) {
            ret = const SplashScreen();
          }
          if (state is Unauthenticated) {
            //            return LoginScreen(userRepository: _userRepository);
            ret = LinkReduxApp(
              transactionStore,
              _userRepository,
            ); // <<=== display Home screen
          }
          if (state is TosReview) {
            ret = const TosPage();
          }
          if (state is Authenticated) {
            ret = LinkReduxApp(
              transactionStore,
              _userRepository,
            ); // <<=== display Home screen
          }
          return ret;
        },
      ),
      //navigatorKey: navigatorKey, // Setting a global key for navigator
    );
  }
}

//========= IOS start here
class IosPage extends StatelessWidget {
  const IosPage({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'autsorz for IOS 1'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff001a72),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white), //= back icon
          tooltip: 'Back',
          onPressed: () {
            // handle the press
          },
        ),
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        actions: const [
          Icon(Icons.fiber_manual_record, color: Colors.green),
          Icon(Icons.refresh, color: Colors.white), //= refresh icon
        ],
      ),
      body: Column(
        // mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 30, 40, 30),
            child: Image.network(
              'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/c%2Fautsorz%2Fimage%2Fautsorz-signup-300x70.png?alt=media&token=fdf74314-429c-4c1e-bd31-a857e6f4b744',
              width: 400,
              // height: 80,
              // alignment: Alignment.center,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(40, 30, 40, 30),
            child: Text(
              'autsorz for iOS ($version$subVersion): Final Testing Underway!',
              // textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black45,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(40, 10, 40, 10),
            child: Text(
              'Get ready for a seamless experience.',
              // textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}
