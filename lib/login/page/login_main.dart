//import 'package:flutter/material.dart';
//import 'package:bloc/bloc.dart';
//import 'package:flutter_bloc/flutter_bloc.dart';
//import 'package:va/login/bloc_authentication/bloc.dart';
//import 'package:va/login/api/user_repository.dart';
//import 'package:va/login/page/home_screen.dart';
//import 'package:va/login/page/tos_page.dart';
//import 'package:va/login/page/login/login.dart';
//import 'package:va/login/page/splash_screen.dart';
//import 'package:va/login/page/simple_bloc_delegate.dart';
///*
//   Documentation :
//     20190511 1.0.1.A Start of versioning; podSettings spreadsheet
//*/
//
//// ========= Constants ==========================
//const String appVersion = '1.0.1.A';
//final String podSettings  = 'agenis | POD Settings';             // File name of setting spreadsheet
//final String posSheet     = 'Mobile';                            // Sheet name of setting data
//final String podFolderKey = '1JJRjyULHGMsBNt-j1XdO7fffdgKTGTC5'; // Google Drive folder for podSettings
//// ==============================================
//
//loginMain() {
//  BlocSupervisor.delegate = SimpleBlocDelegate();
//  final UserRepository userRepository = UserRepository();
//    runApp(
//        BlocProvider(
//          builder: (context) => AuthenticationBloc(userRepository: userRepository)
//              ..dispatch(AppStarted()),
//          child: App(userRepository: userRepository),
//        ),
//    );
//}
//
//
