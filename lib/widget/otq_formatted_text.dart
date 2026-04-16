import 'package:flutter/material.dart';
import '../global.dart';

class OtqFormattedText extends StatelessWidget {
  const OtqFormattedText(
      {super.key,
        required this.textData,
        required this.component,
        this.isEnabled = true});
  final String? textData;
  final dynamic component;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    List<dynamic> style = styleArray(component['style']);
    // Determine color based on isEnabled state
    final Color textColor = isEnabled
        ? ((component['color'] ?? 'default') != 'default'
        ? Color(int.parse(component['color']))
        : Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black)
        : Colors.grey.shade500;

    return Text(
      textData ?? "",
      softWrap: true,
      style: TextStyle(
        color: textColor, // Use the determined color
        backgroundColor: (component['background'] ?? 'default') != 'default'
            ? Color(int.parse(component['background']))
            : Theme.of(context).textTheme.bodyLarge!.backgroundColor,
        fontWeight: style[0],
        fontStyle: style[1],
        decoration: style[2],
        fontSize: 0.0 + (int.parse((component['size'] ?? 16).toString())),
      ),
    );
  }
}
