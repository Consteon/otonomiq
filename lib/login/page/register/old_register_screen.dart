//// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
//import 'package:flutter/material.dart';
//import 'package:flutter_bloc/flutter_bloc.dart';
//import 'package:va/login/api/user_repository.dart';
//import 'package:va/login/page/register/register.dart';
//
//class RegisterScreen extends StatefulWidget {
//  final UserRepository _userRepository;
//
//  RegisterScreen({Key key, @required UserRepository userRepository})
//      : assert(userRepository != null),
//        _userRepository = userRepository,
//        super(key: key);
//
//  State<RegisterScreen> createState() => _RegisterScreenState();
//}
//
//class _RegisterScreenState extends State<RegisterScreen> {
//  RegisterBloc _registerBloc;
//
//  @override
//  void initState() {
//    super.initState();
//    _registerBloc = RegisterBloc(
//      userRepository: widget._userRepository,
//    );
//  }
//
//  @override
//  Widget build(BuildContext context) {
//    return Scaffold(
//      appBar: AppBar(title: Text('Register')),
//      body: Center(
//        child: BlocProvider<RegisterBloc>(
//          bloc: _registerBloc,
//          child: RegisterForm(),
//        ),
//      ),
//    );
//  }
//
//  @override
//  void dispose() {
//    _registerBloc.dispose();
//    super.dispose();
//  }
//}
