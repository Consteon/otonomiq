import 'package:flutter/material.dart';

class WaitScreen extends StatelessWidget {
  const WaitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(250, 250, 250, 0.6),
      body: Center(
        child: Container(
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
