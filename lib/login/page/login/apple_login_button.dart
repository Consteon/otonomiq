import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../login/page/login/login.dart';

class AppleLoginButton extends StatelessWidget {
  final _component;
  final _country;
  final _inv;

  const AppleLoginButton({
    required Key key,
    var this._component,
    required String this._country,
    required String this._inv,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: () {
          // The spinner is driven by the bloc's loading state (login_form
          // dialog + main_page LoginWaitScreen), not by rootThis.wait.
          BlocProvider.of<LoginBloc>(
            context,
          ).add(LoginWithApplePressed(country: _country, inv: _inv));
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(FontAwesomeIcons.apple, size: 20),
            const SizedBox(width: 12),
            Text(
              _component['apple'] ?? 'Masuk dengan Apple',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
