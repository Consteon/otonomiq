// import 'package:flutter/material.dart';
// // import 'package:qr_code_scanner/qr_code_scanner.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import '../main_bloc/bloc.dart';
// import '../global.dart';
// import '../bloc_timer/bloc.dart';
//
// const flash_on = "FLASH ON";
// const flash_off = "FLASH OFF";
// const front_camera = "FRONT CAMERA";
// const back_camera = "BACK CAMERA";
//
// class QrScan extends StatefulWidget {
//   const QrScan({
//     required Key key,
//     this.front = true,
//     this.flash = false,
//     this.size = 300,
//     this.fSize = 16,
//     this.exitSize = 16,
//     this.exitRoute = home,
//     this.crypto = '0',
//     this.exitString = empty,
//     this.feedBackDisplay = empty,
//     this.position = 1,
//     this.screenName = home,
//   }) : super(key: key);
//   final bool? front;
//   final bool? flash;
//   final int? size;
//   final int? fSize;
//   final int? exitSize;
//   final String? exitRoute;
//   final String? crypto;
//   final String? exitString;
//   final String? feedBackDisplay;
//   final int? position;
//   final String? screenName;
//   @override
//   State<StatefulWidget> createState() => _QrScanState();
// }
//
// class _QrScanState extends State<QrScan> {
//   String qrText = ""; // current qr read
//   String lastQr = ""; // last qr read
//   var flashState = flash_on;
//   var cameraState = front_camera;
//   late QRViewController controller;
//   final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
//   int loopCheck = 0; // 0 = no check
//   int checkCount = 0; // check counter
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Column(
//         children: <Widget>[
//           Expanded(
//             flex: 4,
//             child: QRView(
//               key: qrKey,
//               onQRViewCreated: _onQRViewCreated,
//               overlay: QrScannerOverlayShape(
//                 borderColor: Colors.red,
//                 borderRadius: 10,
//                 borderLength: 30,
//                 borderWidth: 10,
//                 cutOutSize: (widget.size ?? 300).toDouble(),
//               ),
//             ),
//           ),
//           Expanded(
//             flex: 1,
//             child: FittedBox(
//               fit: BoxFit.contain,
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: <Widget>[
// //                  Text("Result: $qrText"),
//                   Container(
//                     height: 12,
//                   ),
//                   Text(widget.feedBackDisplay ?? '--',
//                       style: TextStyle(fontSize: 0.0 + (widget.fSize ?? 16.0))),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     crossAxisAlignment: CrossAxisAlignment.center,
//                     children: <Widget>[
//                       Container(
//                         margin: const EdgeInsets.all(8.0),
//                         child: ElevatedButton(
//                           onPressed: () {
//                             gotoRoute(widget.exitRoute!);
//                             var state = transactionStore.state.screenTx;
// //                            transactionStore.dispatch(
// //                                UpdateScreenTxAction(ScreenTransaction({
// //                              '#TIMER_DURATION': 1,
// //                            }))); // minimum timer. Required by savesend.
//                             state['#TIMER_BLOC'].dispatch(
//                                 Reset()); // reset timer state to Ready
//                             BlocProvider.of<MainBloc>(context).add(const ResetAll());
//                           },
//                           child: Text(widget.exitString!,
//                               style: TextStyle(
//                                   fontSize: 0.0 + (widget.exitSize ?? 16.0))),
//                         ),
//                       )
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           )
//         ],
//       ),
//     );
//   }
//
//   void _onQRViewCreated(QRViewController controller) {
//     this.controller = controller;
//     if (widget.front ?? false) {
//       this.controller.flipCamera(); // flip to front
//     }
//     if (widget.flash ?? false) {
//       controller.toggleFlash(); // toggle to on
//     }
//     controller.scannedDataStream.listen((scanData) {
//       setState(() {
//         if (qrText != scanData.code) {
// //          pool.play(beepId);
//           lastQr = qrText;
//           qrText = scanData.code ?? emptyString;
//           BlocProvider.of<MainBloc>(context).add(ScanResult(
//             front: widget.front,
//             flash: widget.flash,
//             size: widget.size,
//             fSize: widget.fSize,
//             exitSize: widget.exitSize,
//             exitRoute: widget.exitRoute,
//             exitString: widget.exitString,
//             result: scanData.code,
//             position: widget.position,
//             scrName: widget.screenName,
//             crypto: widget.crypto,
//           ));
//         }
//       });
//     });
//   }
//
//   @override
//   void dispose() {
//     controller.dispose();
//     super.dispose();
//   }
// }
