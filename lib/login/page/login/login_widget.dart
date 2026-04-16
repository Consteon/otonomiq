// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../login/api/user_repository.dart';
import '../../../login/page/login/login.dart';

class LoginWidget extends StatelessWidget {
  final UserRepository _userRepository;
  final String _tosText;
  final String _tosRoute;
  final BuildContext _parentContext;
  final _component;
  final _nextRoute;

  const LoginWidget(
      {super.key,
      required UserRepository userRepository,
      required String tosText,
      required String tosRoute,
      required BuildContext parentContext,
      required var component,
      required String nextRoute})
      : _userRepository = userRepository,
        _tosText = tosText,
        _tosRoute = tosRoute,
        _parentContext = parentContext,
        _component = component,
        _nextRoute = nextRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: BlocProvider<LoginBloc>(
        create: (context) => LoginBloc(userRepository: _userRepository),
//        child: InvitationForm(
//          userRepository: _userRepository,
//          tosRoute: _tosRoute,
//          tosText: _tosText,
//          parentContext: _parentContext,
//          component: _component,
        child: LoginForm(
          key: UniqueKey(),
          userRepository: _userRepository,
          tosRoute: _tosRoute,
          tosText: _tosText,
          parentContext: _parentContext,
          component: _component,
          route: _nextRoute,
        ),
      ),
    );
  }
} // end of LoginScreen
