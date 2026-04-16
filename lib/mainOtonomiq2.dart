import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';
import 'widget/build_theme.dart';
import 'api.dart';
import 'firestore_repository/firestore_generic_repository.dart';
import 'firestore_repository/proxy_repository.dart';
import 'firestore_repository/table_repository.dart';
import 'global.dart';
import 'page/vertriz_app.dart';
import 'redux/screen_transaction.dart';
import 'widget/ui_component.dart';
import 'login/api/user_repository.dart';
import 'login/bloc_authentication/bloc.dart';
import 'login/page/tos_page.dart';
import 'login/page/splash_screen.dart';
import 'login/page/simple_bloc_delegate.dart';
import 'page/test_page.dart';
import 'bloc_timer/bloc.dart';
import 'login/bloc_login/bloc.dart';
import 'ticker.dart';
import 'notification/bloc.dart';
import 'bloc_submit/bloc.dart';
import 'part/build_part/channel.dart';

final navigatorKey = GlobalKey<NavigatorState>();
// Sets a platform override for desktop to avoid exceptions. See
// https://flutter.dev/desktop#target-platform-override for more info.

void main() async {
  // TODO put runZonedGuarded before WidgetFlutterBinding
  //   https://flutter.dev/docs/testing/errors
  /*
    like:
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp();
      runApp(MyApp());
    }
   */
  debugCount = -1;
  trace(debugCount);
  WidgetsFlutterBinding.ensureInitialized(); // needed by flutter error message
  enablePlatformOverride();
  debugCount = -2;
  trace(debugCount);
  await globalInit();
  debugCount = -3;
  trace(debugCount);
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
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#REFRESH': false,
      '#DATA_OK': false,
      '#GPSDELAYTIME': 0,
      '#GPSDATA': empty,
    })));
    Map<int, TextEditingController> ct = {};
    ct[1] = TextEditingController();
    ct[3] = TextEditingController();
    mobileLayout = (MediaQueryData.fromView(WidgetsBinding.instance.window)
            .size
            .shortestSide) <
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
    await serverSetup();
    // encryptionTest();  // TODO delete this after test all qr encryption
    debugCount = 22;
    trace(debugCount);
    state = transactionStore.state.screenTx;
    var res = json.decode(state['#SETTINGS'][0]['body']);
    debugCount = 23;
    var defaultLifKey = res['signupLif'];
    loginSsid = res['signupLif']; // default signupLif
    var invitationKey = res['signupDemo'];
    debugCount = 3;
    fUser = await getFirebaseUser();
    debugCount = 31;
    trace(debugCount);
    try {
      myLif = await storage.read(key: 'myLif');
    } catch (erLif) {
      debugCount = 32;
      myLif = null;
    }
    debugCount = 33;
    if (fUser != null) {
      String? userDocId = await checkIfUserReset(
          fUser, await getDeviceId()); // check in firebase if user reset
      if (userDocId == null) {
        myLif = null;
        await kickedOut();
      } else {
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
            {'#FIREBASE_USER': fUser, '#FS_USER_DOC_ID': userDocId})));
        subscribeToUserReset(userDocId); // listen to dvc
      } // end if (userReset)
    } //if (fUser != null)

    debugCount = 34;
    if (myLif == null) {
      await storage.write(
          key: 'myLif',
          value: defaultLifKey); // store in secure & persistent storage
      myLif = defaultLifKey;
    }

    debugCount = 4;
//    var pa = Uri(path: Uri.encodeFull("sounds/scanner-beep.mp3")).path;
//    scannerBeep = await rootBundle
//        .load("sounds/scanner-beep.mp3")
//        .then((ByteData soundData) {
//      return pool.load(soundData);
//    });
    transactionStore.dispatch(UpdateScreenTxAction(
        ScreenTransaction({'#SIGNUP_KEY': defaultLifKey})));
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
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#CLUSTER': myClt,
        '#INTERFACE_KEY': myLif,
        '#CURRENT_ROUTE': home,
      })));
      loadHistory(clearHistory, 'main[161] in mainOtonomiz2.dart <= async');
//      runLifInstructions('2'); //   run Instructions2 in background
    }
    debugCount = 5;
//    await readSettings(myLif);
    final UserRepository userRepository = UserRepository();
    debugCount = 51;
    transactionStore.dispatch(UpdateScreenTxAction(
        ScreenTransaction({'#USER_REPOSITORY': userRepository})));
    debugCount = 52;
    trace(debugCount);

    await syncLocaleTable();
    // setTransactionOK('main');
    debugCount = 53;
    trace(debugCount);
    await readSettingsStart(myLif, 1); // *** need to delete
    buildTheme(systemUIComponent[theme]);
    debugCount = 6;
    trace(debugCount);
    constructHomeElements();
    debugCount = 7;
    trace(debugCount);
//    BlocSupervisor.delegate = SimpleBlocDelegate();
    Bloc.observer = SimpleBlocDelegate();
    state = transactionStore.state.screenTx;
    int launchOk = 0;
    if (state['#INTERFACE_KEY'] != null &&
        state['#INTERFACE_KEY'] != '' &&
        state['#INTERFACE_KEY'] != loginSsid) {
      subscribeToEvent(state['#INTERFACE_KEY']);
    }
    if (state['#VID'] != null && state['#VID'] != '') {
      launchOk = await launchCheck(); // Check launch status
      debugCount = 8;
      trace(debugCount);
    }
    // setTransactionOK('main');
    if (launchOk > 0) {
      // error in launching
      debugCount = launchOk;
      runApp(TestApp(flag: 'launchOK = $launchOk',));
    } else {
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
                      ..add(AppStarted())),
            BlocProvider<TimerBloc>(
              create: (BuildContext context1) {
                TimerBloc timerBloc = TimerBloc(ticker: Ticker());
                transactionStore.dispatch(UpdateScreenTxAction(
                    ScreenTransaction({'#TIMER_BLOC': timerBloc})));
                return timerBloc;
              },
            ),
            BlocProvider<LoginBloc>(
              create: (context) => LoginBloc(userRepository: userRepository),
            ),
            BlocProvider<NotificationBloc>(
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
                return SubmitBloc(
                  submitRepository: FirebaseSubmitRepository(),
                )..add(LoadSubmit());
              },
            ),
          ],
          child: App(key: UniqueKey(), userRepository: userRepository),
        ),
      ); // end of runApp
    }
  } catch (err) {
    runApp(TestApp(flag: 'Error: ${err.toString()}',));
  }
} // end of main

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

  const App({required Key key, required UserRepository userRepository})
      : _userRepository = userRepository,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    SubmitBloc submitBloc = BlocProvider.of<SubmitBloc>(context);
    TimerBloc timerBloc = BlocProvider.of<TimerBloc>(context);
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
        {'#TIMER_BLOC': timerBloc, '#SUBMIT_BLOC': submitBloc})));
    return GetMaterialApp(
      // localeResolutionCallback: (
      //     Locale? locale,
      //     Iterable<Locale> supportedLocales,
      //     ) {
      //   return locale;
      // },

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
                transactionStore, _userRepository); // <<=== display Home screen
          }
          if (state is TosReview) {
            ret = const TosPage();
          }
          if (state is Authenticated) {
            ret = LinkReduxApp(
                transactionStore, _userRepository); // <<=== display Home screen
          }
          return ret;
        },
      ),
      //navigatorKey: navigatorKey, // Setting a global key for navigator
    );
  }
}

// TODO internationalization
