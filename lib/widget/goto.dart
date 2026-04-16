import 'package:flutter/material.dart';
import '../global.dart';
import '../api.dart';

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

    const double defaultAspectRatio = 18 / 12;
    var topPad = 6.0;
    double fontSize = (widget.component['fontSize'] ?? 14.0).toDouble();
    var textArray = diamondTextToList(widget.component['text']);
    Widget button;

    if (widget.single) {
      // single, display centered icon with map
      button = Center(
        child: Container(
          // if single
          alignment: Alignment.center,
//      color: Colors.red,
          width: (widget.component['width'] ?? 90).toDouble(),
          child: Card(
            child: InkWell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    height: topPad,
                  ),
                  AspectRatio(
                    aspectRatio: defaultAspectRatio,
                    child: displayImage(
                        imageUrl: widget.component['url'] ?? defaultImage,
                        cached: true),
                    // child: FadeInImage.memoryNetwork(
                    //   placeholder: kTransparentImage,
                    //   image: widget.component['url'] ?? defaultImage,
                    // ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      textArray[0],
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ),
                ],
              ),
              onTap: () async =>
                  await tabGoto(widget.component['route'] ?? 'home'),
            ),
          ),
        ),
      );
    } else {
      // called from Horizontal_icon, display icon only
      button = Container(
        alignment: const Alignment(0.0, 0.0),
        child: Card(
          child: InkWell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  height: topPad,
                ),
                AspectRatio(
                  aspectRatio: defaultAspectRatio,
                  child: displayImage(
                      imageUrl: widget.component['url'] ?? defaultImage,
                      cached: true),
                  // child: FadeInImage.memoryNetwork(
                  //   placeholder: kTransparentImage,
                  //   image: widget.component['url'] ?? defaultImage,
                  // ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    textArray[0],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fontSize),
                  ),
                ),
              ],
            ),
            onTap: () async =>
                await tabGoto(widget.component['route'] ?? 'home'),
          ),
        ),
      );
    }
    return button;
  }
}
