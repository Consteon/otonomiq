import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../login/page/login/login.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class GoogleLoginButton extends StatelessWidget {
  final _component;
  final _country;
  final _inv;

  const GoogleLoginButton(
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
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        onPressed: () {
          // The spinner is driven by the bloc's loading state (login_form
          // dialog + main_page LoginWaitScreen), not by rootThis.wait.
          BlocProvider.of<LoginBloc>(context).add(
            LoginWithGooglePressed(country: _country, inv: _inv),
          );
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FontAwesomeIcons.google,
                size: 18, color: Color(0xFF4285F4)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _component['google'] ?? 'Masuk dengan Google',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
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
