// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../login/api/user_repository.dart';
import '../../../login/page/login/login.dart';
import '../../../login/bloc_authentication/bloc.dart';
import '../../../global.dart';

class LoginForm extends StatefulWidget {
  final UserRepository _userRepository;
  final String? tosText;
  final String? tosRoute;
  final BuildContext? parentContext;
  final dynamic component;
  final dynamic route;

  const LoginForm(
      {required Key key,
      required UserRepository userRepository,
      this.tosText,
      this.tosRoute,
      this.parentContext,
      this.component,
      this.route})
      : assert(component != null),
        _userRepository = userRepository,
        super(key: key);

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController();
  final TextEditingController _vidController = TextEditingController();
  final TextEditingController _invController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();

  LoginBloc? _loginBloc;
  bool _tosOk = false;
  String tText = 'a';
  UserRepository get _userRepository => widget._userRepository;
  final bool _wait = false;

  bool get isPopulated =>
//      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;
      _phoneController.text.isNotEmpty;

  bool isLoginButtonEnabled(LoginState state) {
    return state.isFormValid &&
        _smsCodeController.text.isNotEmpty &&
        state.isWaitingSmsCode &&
        state.isSmsCodeValid;
  }

  bool isSmsButtonEnabled(LoginState state) {
    return state.isFormValid &&
        _phoneController.text.isNotEmpty &&
        !state.isWaitingSmsCode &&
        state.isTosOK;
  }

  bool isOtherProviderEnabled(LoginState state) {
    return state.isTosOK;
  }

  bool isLoginProcessing(LoginState state) {
    return (state.inLoginProcess && !state.isSuccess && !state.isFailure) ||
        _wait;
  }

  bool isInvNeeded(LoginState state) {
    return state.loginUid != '';
  }

  @override
  void initState() {
    super.initState();
    _loginBloc = BlocProvider.of<LoginBloc>(context);
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);
    _phoneController.addListener(_onPhoneChanged);
    _smsCodeController.addListener(_onSmsCodeChanged);
    _vidController.addListener(_onVidChanged);
    _invController.addListener(_onInvChanged);
    _countryController.addListener(_onCountryChanged);
    _countryController.text = "Indonesia";
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener(
      bloc: _loginBloc,
      listener: (BuildContext context, LoginState state) {
        if (state.isFailure) {
          _userRepository.systemSignOut();
          if (state.loginStatus == 2) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['AnotherUserLogin']),
                  content:
                      Text(textList['AnotherUserLoginMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 3) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['PhoneNotMatch']),
                  content: Text(textList['PhoneNotMatchMessage']),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 7) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['PhoneUsed']),
                  content: Text(textList['PhoneUsedMessage']),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 1) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['Full']),
                  content: Text(textList['FullMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 4) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['SignInError']),
                  content: Text(textList['SignInErrorMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 5) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['SignInError']),
                  content: Text(textList['SignInErrorGoogle']),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 802) {
            // got text from guest | VM>JSON
            // TODO read from Firestore
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['Error802']),
                  content: Column(
                    mainAxisSize: MainAxisSize
                        .min, // Column length = sum of children length
                    children: [
                      Text(textList['Error802Message']),
                      Container(
                        height: 10,
                      ),
                      Text(textList["802"]),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else if (state.loginStatus == 809) {
            // got text from guest | VM>JSON
            // TODO read from Firestore
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['Error809']),
                  content: Column(
                    mainAxisSize: MainAxisSize
                        .min, // Column length = sum of children length
                    children: [
                      Text(textList['Error809Message']),
                      Container(
                        height: 10,
                      ),
                      Text(textList['NoAccount']),
                      Container(
                        height: 10,
                      ),
                      Text(textList['AdminRegisterAccount']),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          } else {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['LoginFail']),
                  content: Text(textList['LoginFailMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                );
              },
            );
          }
        } else if (state.isSuccess) {
          BlocProvider.of<AuthenticationBloc>(context).add(LoggedIn());
        } else if (state.loginUid != '') {
          gotoRoute(widget.route ??
              '_Invitation'); // TODO delete this line, change it with new user getter.
        }
      },
      child: BlocBuilder(
        bloc: _loginBloc,
        builder: (BuildContext context, LoginState state) {
          isLoginProcessing(state);
          return Padding(
            padding: const EdgeInsets.all(0.0),
            child: Form(
//            child: ListView(
              child: Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      !state.isWaitingSmsCode
                          ? Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 5.0),
                              child: Row(
                                children: <Widget>[
                                  GestureDetector(
                                    onTap: _onTosOKTabbed,
                                    child: Checkbox(
                                      value: _tosOk,
                                      onChanged: (bool? value) {
                                        _onTosOKTabbed();
                                      },
//                                  onChanged: (_)=>_onTosOKTabbed, // onChanged handled by GestureDetector
                                    ),
                                  ),
                                  Flexible(
                                    child: GestureDetector(
                                      onTap: () {
                                        gotoRoute(widget.tosRoute!);
                                      },
                                      child: Text(widget.tosText!),
                                    ),
                                  ),
                                ],
                              ))
                          : Container(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            isOtherProviderEnabled(state)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      TextField(
                                        textAlign: TextAlign.center,
                                        controller: _invController,
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp('[0-9]+'))
                                        ],
                                        decoration: InputDecoration(
                                          labelText: widget.component['text3'],
                                          border: const OutlineInputBorder(
                                            borderRadius: BorderRadius.all(
                                                Radius.circular(10.0)),
                                          ),
                                          hintText: widget.component['text4'],
                                        ),
                                      ),
                                      Container(
                                        height: 10.0,
                                      ),
                                      sinner
                                          ? AppleLoginButton(
                                              key: GlobalKey(),
                                              component: widget.component,
                                              country: _countryController.text,
                                              inv: _invController.text,
                                            )
                                          : Container(
                                              height: 0,
                                            ),
                                      Container(),
                                      GoogleLoginButton(
                                        key: GlobalKey(),
                                        component: widget.component,
                                        country: _countryController.text,
                                        inv: _invController.text,
                                      )
                                    ],
                                  )
                                : Container(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  isLoginProcessing(state)
                      ? Stack(
                          children: <Widget>[
                            Center(
                              child: Container(
                                width: double.infinity,
                                height: 300,
                                color: Colors.white.withOpacity(0.5),
                                child: const Center(
                                    child: CircularProgressIndicator()),
                              ),
                            ),
                          ],
                        )
                      : Container(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    _loginBloc!.add(
      EmailChanged(email: _emailController.text),
    );
  }

  void _onPasswordChanged() {
    _loginBloc!.add(
      PasswordChanged(password: _passwordController.text),
    );
  }

  void _onSmsCodeChanged() {
    _loginBloc!.add(SmsCodeChanged(smsCode: _smsCodeController.text));
  }

  void _onPhoneChanged() {
    _loginBloc!.add(PhoneChanged(phone: _phoneController.text));
  }

  void _onVidChanged() {
    _loginBloc!.add(VidChanged(vid: _vidController.text));
  }

  void _onInvChanged() {
    _loginBloc!.add(InvChanged(inv: _invController.text));
  }

  void _onCountryChanged() {
    _loginBloc!.add(CountryChanged(country: _countryController.text));
  }

  void _onTosOKTabbed() {
    _tosOk = !_tosOk;
    _loginBloc!.add(TosOKTabbed(tosOk: _tosOk));
  }

  String phoneInternationalize(String phone) {
    String result = phone;
    String one = phone.substring(0, 1);
    if (one == '0') {
      result = '+62${phone.substring(1, phone.length)}';
    }
    return result;
  }

//  void _onSmsSendPressed() {
//    String intlPhone = phoneInternationalize(_phoneController.text);
//    _loginBloc.add(
//      SendSmsPressed(
//        phone: intlPhone,
//      ),
//    );
//  }

//  void _onPhoneLoginPressed() {
//    _loginBloc.add(
//      LoginWithPhonePressed(
//        smsCode: _smsCodeController.text,
//      ),
//    );
//  }
}
