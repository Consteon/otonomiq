import 'package:flutter/material.dart';

import '../global.dart';
import 'menu_icon_card.dart';

/*
  Send current GPS location and display google map static
 */
class Goto extends StatefulWidget {
  const Goto({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final dynamic single;

  @override
  _GotoState createState() => _GotoState();
}

class _GotoState extends State<Goto> {
  @override
  Widget build(BuildContext context) {
    Future<void> tabGoto(String route) async {
      if (route != rootThis.pageName) {
        routeStack.push(route);
        gotoRoute(route);
      }
    } // end of tabGoto

    double fontSize = (widget.component['fontSize'] ?? 14.0).toDouble();
    var textArray = diamondTextToList(widget.component['text']);

    Widget card = menuIconCard(
      imageUrl: widget.component['url'] ?? defaultImage,
      label: textArray[0],
      fontSize: fontSize,
      onTap: () async => await tabGoto(widget.component['route'] ?? 'home'),
    );

    if (widget.single) {
      return Center(
        child: SizedBox(
          width: (widget.component['width'] ?? 90).toDouble(),
          child: card,
        ),
      );
    }
    return card;
  }
}
