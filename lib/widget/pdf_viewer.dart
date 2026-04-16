import 'package:flutter/material.dart';
import '../global.dart';
// import '../page/otq_pdf_viewer.dartdisabled';

import '../api.dart';

/*
  launch otq pdf viewer
*/
class PdfViewer extends StatefulWidget {
  const PdfViewer({
    required Key key,
    required this.component,
    required this.scrName,
  }) : super(key: key);
  final String scrName;
  final dynamic component;

  @override
  _PdfViewerState createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  bool change = true;

  @override
  Widget build(BuildContext context) {
    const String defaultPdf =
        'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/c%2Fautsorz%2FOtonomiq.pdf?alt=media&token=efcd3c1a-987e-4521-a31e-27660d5a86c6';
    const double defaultAspectRatio = 18 / 12;
    var topPad = 6.0;
    double fontSize = (widget.component['fontSize'] ?? 14.0).toDouble();
    var textArray = diamondTextToList(widget.component['text']);
    Widget button;

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
                    getText(textArray, 0),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fontSize),
                  ),
                ),
              ],
            ),
            onTap: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const Text(
                      'PDF Viewer temporarily disabled, due to ios18 incompatibility'),
                  // builder: (context) => OtqPdfViewer(
                  //   urlPath: widget.component['path'] ?? defaultPdf,
                  //   remote: true,
                  //   password: widget.component['password'] ?? '',
                  //   linkNavigation: widget.component['linkNavigation'] == null
                  //       ? false
                  //       : widget.component['linkNavigation']
                  //               .toString()
                  //               .trim()
                  //               .toLowerCase() ==
                  //           'true',
                  //   swipe: widget.component['swipe'] == null
                  //       ? 'vertical'
                  //       : widget.component['swipe']
                  //           .toString()
                  //           .trim()
                  //           .toLowerCase(),
                  // ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return button;
  }
}
