import 'package:flutter/material.dart';
//import 'package:flutter_bloc/flutter_bloc.dart';
//import 'package:va/login/page/login/login.dart';

class FirebaseSendSmsButton extends StatelessWidget {
  final VoidCallback _onPressed;

  const FirebaseSendSmsButton({required Key key, required VoidCallback onPressed})
      : _onPressed = onPressed,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Colors.teal,
      ),
      //shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
      icon: const Icon(Icons.send, color: Colors.white),
      onPressed: _onPressed,
      label: const Text('Kirim kode sms', style: TextStyle(color: Colors.white)),
//      color: Colors.redAccent,
//       color: Colors.teal,
    );
  }
}
