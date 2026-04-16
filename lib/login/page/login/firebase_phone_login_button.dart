import 'package:flutter/material.dart';

class FirebasePhoneLoginButton extends StatelessWidget {
  final VoidCallback _onPressed;

  const FirebasePhoneLoginButton({required Key key, required VoidCallback onPressed})
      : _onPressed = onPressed,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Colors.teal,
      ),
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
      icon: const Icon(Icons.perm_phone_msg, color: Colors.white),
      onPressed: _onPressed,
      label: const Text('Masuk menggunakan SMS', style: TextStyle(color: Colors.white)),
//      color: Colors.redAccent,
//       color: Colors.teal,
    );
  }
}
