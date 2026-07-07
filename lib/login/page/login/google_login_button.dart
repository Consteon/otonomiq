import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../login/page/login/login.dart';

class GoogleLoginButton extends StatelessWidget {
  final _component;
  final _country;
  final _inv;

  const GoogleLoginButton({
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
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade300),
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
          ).add(LoginWithGooglePressed(country: _country, inv: _inv));
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(
              FontAwesomeIcons.google,
              size: 18,
              color: Color(0xFF4285F4),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _component['google'] ?? 'Masuk dengan Google',
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
