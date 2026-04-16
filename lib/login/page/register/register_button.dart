// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/material.dart';

class RegisterButton extends StatelessWidget {
  final VoidCallback _onPressed;

  const RegisterButton({super.key, required VoidCallback onPressed})
      : _onPressed = onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        // backgroundColor: Colors.teal,
      ),
      // shape: RoundedRectangleBorder(
      //   borderRadius: BorderRadius.circular(30.0),
      // ),
      onPressed: _onPressed,
      child: const Text('Register'),
    );
  }
}
