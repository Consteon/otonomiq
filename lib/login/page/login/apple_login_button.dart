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
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        onPressed: () {
          rootThis.setState(() {
            rootThis.wait = true;
            rootThis.touch = !rootThis.touch;
          });
          BlocProvider.of<LoginBloc>(context).add(
            LoginWithApplePressed(country: _country, inv: _inv),
          );
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FontAwesomeIcons.apple, size: 20),
            const SizedBox(width: 12),
            Text(
              _component['apple'] ?? 'Masuk dengan Apple',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
