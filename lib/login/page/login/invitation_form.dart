// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../global.dart';
import '../../../login/api/user_repository.dart';
import '../../../login/bloc_authentication/bloc.dart';
import '../../../login/page/login/login.dart';

class InvitationForm extends StatefulWidget {
  final UserRepository _userRepository;
  final String tosText;
  final String tosRoute;
  final BuildContext parentContext;
  final _component;

  const InvitationForm({
    required Key key,
    required this._userRepository,
    required this.tosText,
    required this.tosRoute,
    required this.parentContext,
    @required var this._component,
  }) : super(key: key);

  @override
  State<InvitationForm> createState() => _InvitationFormState();
}

class _InvitationFormState extends State<InvitationForm> {
  final TextEditingController _invController = TextEditingController();

  LoginBloc? _loginBloc;
  bool _wait = false;
  String tText = 'a';
  UserRepository get _userRepository => widget._userRepository;

  bool isLoginProcessing(LoginState state) {
    return _wait || state.inLoginProcess;
  }

  @override
  void initState() {
    super.initState();
    _loginBloc = BlocProvider.of<LoginBloc>(context);
    _invController.addListener(_onInvChanged);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener(
      bloc: _loginBloc,
      listener: (BuildContext context, LoginState state) {
        if (state.isFailure) {
          if (state.loginStatus == 2) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("User not found"),
                  content: const Text(
                    "VID tidak ditemukan, masukan sekali lagi, atau kosongkan jika tidak tahu.",
                  ), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 6) {
            _wait = false;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Invitation Error"),
                  content: Text(widget._component['text6']),
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 1) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Full !"),
                  content: const Text(
                    "Wah!, banyak sekali yang mendaftar. Sementara ini tidak dapat menambah pemakai baru. Kami sedang terus menambah kapasitas, silahkan coba beberapa jam lagi.",
                  ), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 4) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Sign in error"),
                  content: const Text(
                    "Terjadi kesalahan pada saat sign in, silahkan coba beberapa saat lagi.",
                  ), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 5) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Sign in error"),
                  content: const Text(
                    "Terjadi kesalahan pada saat autorisasi akun Google, silahkan coba lagi.",
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 7) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Code Expired"),
                  content: const Text(
                    "Terlambat. Nomor undangan yang anda masukan sudah kadaluwarsa. Silahkan hubungi administrator komunitas yang memberikan nomor undangan ini untuk mendapatkan nomor undangan yang baru.",
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Login fail"),
                  content: const Text(
                    "Login anda gagal. Kemungkinan karena koneksi internet anda terganggu. Silahkan coba beberapa saat lagi",
                  ), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: const Text("OK"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          }
        }
        if (state.isSuccess) {
          BlocProvider.of<AuthenticationBloc>(context).add(LoggedIn());
          //          _wait = false;
        }
      },
      child: BlocBuilder(
        bloc: _loginBloc,
        builder: (BuildContext context, LoginState state) {
          return Padding(
            padding: const EdgeInsets.all(0.0),
            child: Form(
              child: Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      Container(
                        child: TextFormField(
                          keyboardType: TextInputType.number,
                          controller: _invController,
                          decoration: InputDecoration(
                            icon: const Icon(Icons.drafts),
                            hintText: widget._component['text4'],
                            labelText: widget._component['text3'],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ElevatedButton.icon(
                              // shape: RoundedRectangleBorder(
                              //     borderRadius: BorderRadius.circular(30.0)),
                              icon: const FaIcon(
                                FontAwesomeIcons.rightToBracket,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _wait = true;
                                });
                                var uid = transactionStore
                                    .state
                                    .screenTx['#FIREBASE_USER']
                                    ?.uid;
                                BlocProvider.of<LoginBloc>(context).add(
                                  InvitationLoginPressed(
                                    inv: _invController.text,
                                    uid: uid,
                                  ),
                                );
                              },
                              label: Text(
                                widget._component['text5'],
                                style: const TextStyle(color: Colors.white),
                              ),
                              // color: Colors.teal,
                            ),
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
                                width: 1000,
                                height: 2000,
                                color: Colors.white.withValues(alpha: 0.5),
                                //                              child: Center(child: CircularProgressIndicator()),
                              ),
                            ),
                            const Center(
                              child: CircularProgressIndicator(
                                //                                backgroundColor: Colors.red,
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
    _invController.dispose();
    super.dispose();
  }

  void _onInvChanged() {
    _loginBloc!.add(VidChanged(vid: _invController.text));
  }

  String phoneInternationalize(String phone) {
    String result = phone;
    String one = phone.substring(0, 1);
    if (one == '0') {
      result = '+62${phone.substring(1, phone.length)}';
    }
    return result;
  }
}
