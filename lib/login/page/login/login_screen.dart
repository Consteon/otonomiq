// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../login/api/user_repository.dart';
import '../../../login/page/login/login.dart';

class LoginScreen extends StatelessWidget {
  final UserRepository _userRepository;

  const LoginScreen({required Key key, required UserRepository userRepository})
      : _userRepository = userRepository,
        super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: BlocProvider<LoginBloc>(
        create: (context) => LoginBloc(userRepository: _userRepository),
        child: LoginForm(key: UniqueKey(), userRepository: _userRepository),
      ),
    );
  }
}
