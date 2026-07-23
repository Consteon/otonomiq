import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

import '../bloc_submit/bloc.dart';
import '../global.dart';
import '../login/api/user_repository.dart';
import '../main_bloc/bloc.dart';
import '../page/main_page.dart';
import '../redux/screen_transaction.dart';

// Canonical fallbacks, copied from the default map already sitting in
// buildTheme (build_theme.dart:7-12). Duplicated rather than imported because
// that copy is dead -- build_theme.dart:13 does `appTheme = null;` right after
// building it, so its `??` never fires.
const int _defaultPrimaryColor = 4278196850;
const int _defaultBottomAppBarColor = 4293454582;

// Reads a colour out of the server-driven theme map, degrading to `fallback`
// instead of throwing.
//
// This is the ROOT MaterialApp: anything thrown from VertrizApp.build renders
// NOTHING -- a blank app, not a degraded screen. Three real states reach here:
//   - systemUIComponent is null      (global.dart:490 declares it bare `dynamic`)
//   - systemUIComponent is {}        (the init/reset routine, global.dart:849)
//   - the tenant sheet omits the key
// All three produced `NoSuchMethodError` from
// `systemUIComponent[theme]['primaryColor'].toInt()`.
//
// `v is num` also closes a second, separate class the old code had backwards:
// the null-guarded reads passed the raw dynamic to `Color(x)` with no
// `.toInt()`, so a sheet value decoded as double threw TypeError there while
// the unguarded ones threw NoSuchMethodError here. One helper, both classes.
Color themeColor(String key, Color fallback) {
  try {
    final dynamic v = systemUIComponent?[theme]?[key];
    if (v is num) return Color(v.toInt());
  } catch (_) {
    // systemUIComponent is not a Map at all.
  }
  return fallback;
}

class VertrizApp extends StatelessWidget {
  // This widget is the root of your application.
  final UserRepository _userRepository;

  const VertrizApp({required Key key, required this._userRepository})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: thisAppName,
      theme: ThemeData(
        //useMaterial3: true,
        //primaryColor: Colors.red,
        // colorSchemeSeed: const Color(0xff6750a4), useMaterial3: true,
        // ColorSchemeSeed: const Color(0xff6750a4), useMaterial3: true,
        primaryColor: themeColor(
          'primaryColor',
          const Color(_defaultPrimaryColor),
        ),
        // buttonTheme: ButtonThemeData(
        // buttonColor: systemUIComponent[theme]['buttonColor'] == null
        //     ? Colors.yellow
        //     : Color(systemUIComponent[theme]['buttonColor']),
        //   buttonColor: Colors.yellow,
        //
        // ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            // side: MaterialStateProperty.resolveWith<BorderSide>(
            //         (states) => BorderSide(color: borderColor ?? Colors.black)),
            backgroundColor: WidgetStateProperty.resolveWith<Color>(
              (states) => themeColor('buttonColor', Colors.grey[400]!),
            ),
            foregroundColor: WidgetStateProperty.resolveWith<Color>(
              (states) => themeColor('buttonText', Colors.black87),
            ),
            // backgroundColor: MaterialStateProperty.resolveWith<Color>(
            //         (states) => systemUIComponent[theme]['buttonColor'] == null
            //         ? Colors.grey[400]!
            //         : Colors.grey[400]!,
            shape: WidgetStateProperty.resolveWith<OutlinedBorder>((_) {
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              );
            }),
            // textStyle: MaterialStateProperty.resolveWith<TextStyle>(
            //     (states) => TextStyle(color: Colors.red)),
          ),
          // style: ElevatedButton.styleFrom(
          //   primary: systemUIComponent[theme]['buttonColor'] == null
          //       ? Colors.grey[400]
          //       : Color(systemUIComponent[theme]['buttonColor']),
          //   onPrimary: systemUIComponent[theme]['buttonText'] == null
          //       ? Colors.black
          //       : Color(systemUIComponent[theme]['buttonText']),
          // ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: themeColor('buttonText', Colors.black),
          ),
        ),
        bottomAppBarTheme: BottomAppBarThemeData(
          color: themeColor(
            'bottomAppBarColor',
            const Color(_defaultBottomAppBarColor),
          ),
        ),
        // toggleableActiveColor: Color(systemUIComponent[theme]['toggleableActiveColor'].toInt()??4280391411), // blue
        // disabledColor: Color(systemUIComponent[theme]['disabledColor'].toInt()??4288585374), // grey
      ),

      home: MultiBlocProvider(
        providers: [
          BlocProvider<MainBloc>(
            create: (BuildContext context) => MainBloc(MainState.empty()),
          ),
          BlocProvider<SubmitBloc>(
            create: (BuildContext context) {
              return SubmitBloc(submitRepository: FirebaseSubmitRepository())
                ..add(LoadSubmit());
            },
          ),
          //        BlocProvider<TimerBloc>(
          //          builder: (BuildContext context) => TimerBloc(),
          //        ),
        ],
        child: BlocBuilder<MainBloc, MainState>(
          builder: (context, state) {
            var state = transactionStore.state.screenTx;
            if (state['#NEED_PINHASH'] == true) {
              BlocProvider.of<MainBloc>(context).add(NeedPinHash());
            }
            // Stable key: MainBloc emits (nav between home variants, NeedPinHash,
            // etc.) must NOT tear down + re-inflate the whole shell. A fresh
            // UniqueKey() here forced Flutter to destroy the old MainPage and
            // build a new one every emit, which (a) mounted two Scaffolds sharing
            // the module-global mainScaffoldKey for one frame -> "Duplicate
            // GlobalKey detected", (b) ran ancestor lookups on the deactivating
            // subtree -> "Looking up a deactivated widget's ancestor is unsafe",
            // and (c) re-ran initState (asyncAppStartup2 + subscribeToProxy) ->
            // "table ... has already subscribed" spam. A const ValueKey keeps the
            // single MainPageState alive, matching the shell's render-once design.
            return const MainPage(key: ValueKey('mainPage'));
            // return BlocBuilder<SubmitBloc, SubmitState> (
            //   builder: (context, state) {
            //     return MainPage();
            //   }, // SubmitBloc builder
            // );
          }, // MainBloc builder
        ),
      ),
      //      home: BlocProvider<MainBloc>(
      //        builder: (context) => MainBloc(),
      //        child: BlocBuilder<MainBloc,MainState>(
      //          builder: (context, state) => MainPage(),
      //        ),
      //      ),
    );
  }
}

class LinkReduxApp extends StatelessWidget {
  final DevToolsStore<ScreenTransaction> store;
  final UserRepository _userRepository;

  const LinkReduxApp(this.store, this._userRepository, {super.key});

  @override
  Widget build(BuildContext context) {
    return StoreProvider<ScreenTransaction>(
      store: transactionStore,
      child: VertrizApp(key: UniqueKey(), userRepository: _userRepository),
    );
  }
}
