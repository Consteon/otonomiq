import 'package:flutter/material.dart';
import '../bloc_submit/bloc.dart';
import '../main_bloc/bloc.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import '../login/api/user_repository.dart';
import '../page/main_page.dart';

class VertrizApp extends StatelessWidget {
  // This widget is the root of your application.
  final UserRepository _userRepository;

  const VertrizApp({required Key key, required UserRepository userRepository})
      : _userRepository = userRepository,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: thisAppName,
      theme: ThemeData(
        //useMaterial3: true,
        //primaryColor: Colors.red,
        // colorSchemeSeed: const Color(0xff6750a4), useMaterial3: true,
        // ColorSchemeSeed: const Color(0xff6750a4), useMaterial3: true,
        primaryColor: Color(systemUIComponent[theme]['primaryColor'].toInt()),
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
                (states) => systemUIComponent[theme]['buttonColor'] == null
                    ? Colors.grey[400]!
                    : Color(systemUIComponent[theme]['buttonColor'])),
            foregroundColor: WidgetStateProperty.resolveWith<Color>(
                (states) => systemUIComponent[theme]['buttonText'] == null
                    ? Colors.black87
                    : Color(systemUIComponent[theme]['buttonText'])),
            // backgroundColor: MaterialStateProperty.resolveWith<Color>(
            //         (states) => systemUIComponent[theme]['buttonColor'] == null
            //         ? Colors.grey[400]!
            //         : Colors.grey[400]!,
            shape: WidgetStateProperty.resolveWith<OutlinedBorder>((_) {
              return RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4));
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
            foregroundColor: systemUIComponent[theme]['buttonText'] == null
                ? Colors.black
                : Color(systemUIComponent[theme]['buttonText']),
          ),
        ),
        bottomAppBarTheme: BottomAppBarThemeData(
            color:
                Color(systemUIComponent[theme]['bottomAppBarColor'].toInt())),
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
            return MainPage(key: UniqueKey());
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
