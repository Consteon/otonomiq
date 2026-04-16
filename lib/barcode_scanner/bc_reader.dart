/*
 idea from https://pub.dev/packages/flutter_barcode_scanner#-readme-tab-
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
//import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';

class BCReader extends StatefulWidget {
  const BCReader({super.key});

  @override
  _BCReaderState createState() => _BCReaderState();
}

class _BCReaderState extends State<BCReader> {
  String _scanBarcode = 'Unknown';

  @override
  void initState() {
    super.initState();
  }

  startBarcodeScanStream() async {
//    FlutterBarcodeScanner.getBarcodeStreamReceiver("#ff6666", "Cancel", true,ScanMode.DEFAULT)
//        .listen((barcode) => devPrint(barcode));
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String barcodeScanRes = 'Failed to get platform version.';
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
//      barcodeScanRes =
//      await FlutterBarcodeScanner.scanBarcode("#ff6666", "Cancel", true,ScanMode.DEFAULT);
    } on PlatformException {
      barcodeScanRes = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _scanBarcode = barcodeScanRes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: Scaffold(
            appBar: AppBar(title: const Text('Barcode scan')),
            body: Builder(builder: (BuildContext context) {
              return Container(
                  alignment: Alignment.center,
                  child: Flex(
                      direction: Axis.vertical,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        ElevatedButton(
                            onPressed: () {
                              initPlatformState();
                            },
                            child: const Text("Start barcode scan")),
                        Text('Scan result : $_scanBarcode\n',
                            style: const TextStyle(fontSize: 20)),
                        ElevatedButton(
                            onPressed: () {
                              startBarcodeScanStream();
                            },
                            child: const Text("Start barcode scan stream"))
                      ]));
            })));
  }
}
