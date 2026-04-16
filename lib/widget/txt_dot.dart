import 'package:flutter/material.dart';

class TxtDot extends StatelessWidget {
  final String txt;
  final double diameter;
  final Color color;

  const TxtDot(
      {required Key key,
      required this.txt,
      required this.diameter,
      required this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular((diameter / 2).floorToDouble()),
      ),
      height: diameter,
      constraints: BoxConstraints(
//                        minWidth: diameter,
        minHeight: diameter,
        maxWidth: diameter * 1.5,
        maxHeight: diameter,
      ),
      child: Center(
        child: Text(
          txt,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
