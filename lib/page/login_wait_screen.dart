import 'package:flutter/material.dart';

class LoginWaitScreen extends StatelessWidget {
  const LoginWaitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(250, 250, 250, 0.6),
      body: Center(
        child: Container(
          child: const CircularProgressIndicator(),
          // child: Text("Do you now that Autsorz can do much thing than you think?"),
        ),
      ),
    );
  }
}
