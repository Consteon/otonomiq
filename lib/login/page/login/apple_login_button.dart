import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../login/page/login/login.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../global.dart';

class AppleLoginButton extends StatelessWidget {
  final _component;
  final _country;
  final _inv;

  const AppleLoginButton(
      {required Key key,
      var component,
      required String country,
      required String inv})
      : _component = component,
        _country = country,
        _inv = inv,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)), backgroundColor: Colors.teal,
        ),
        icon: const Icon(FontAwesomeIcons.apple, color: Colors.white),
        onPressed: () {
          rootThis.setState(() {
            rootThis.wait = true;
            rootThis.touch = !rootThis.touch;
          });
          BlocProvider.of<LoginBloc>(context).add(
            LoginWithApplePressed(country: _country, inv: _inv),
          );
        },
        label: Text(_component['apple'] ?? 'Masuk menggunakan Apple ID',
            style: const TextStyle(color: Colors.white)),
//      color: Colors.redAccent,
      ),
    );
  }
}
