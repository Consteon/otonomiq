// import 'package:flutter/material.dart';
// import '../global.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import '../main_bloc/bloc.dart';
// import 'package:pinput/pin_put/pin_put.dart';
//
// class PinNew extends StatefulWidget {
//   final int digit;
//   final String errMessage;
//   final String route;
//
//   const PinNew({
//     Key key,
//     @required this.digit,
//     @required this.errMessage,
//     @required this.route,
//   }) : super(key: key);
//
//   @override
//   _PinNewState createState() => _PinNewState();
// }
//
// class _PinNewState extends State<PinNew> {
//
//   @override
//   Widget build(BuildContext context) {
//     var _lPad = (systemUIComponent['Mobile']['leftPad'] ?? 0.0).toDouble();
//     var _tPad = (systemUIComponent['Mobile']['topPad'] ?? 0.0).toDouble();
//     var _rPad = (systemUIComponent['Mobile']['rightPad'] ?? 0.0).toDouble();
//     var _bPad = (systemUIComponent['Mobile']['bottomPad'] ?? 0.0).toDouble();
//     String nPin1;
//     String nPin2;
//
//     return Container(
//       height: 200,
//         margin: EdgeInsets.only(
//           top: 0.0,
//           bottom: 0.0,
//         ),
//         padding: EdgeInsets.fromLTRB(_lPad, _tPad, _rPad, _bPad),
//         child: Center(
//           child: PinPut(
//             fieldsCount: widget.digit ?? 6,
//             obscureText: '*',
//             //isTextObscure: true,
//             //unFocusWhen: true,
//             onSubmit: (String pin2) {
//               nPin2 = pin2;
//               if (nPin1 == nPin2) {
//                 BlocProvider.of<MainBloc>(context).add(NewPinSubmit(
//                   pin: pin2,
//                 ));
//               } else {
//
//               }
//             },
// //            onClear: (String s) {},
//           ),
//         ));
//   }
// }
//
// //class _PinNewState extends State<PinNew> {
// //  String nPin1;
// //  String nPin2;
// //
// //  @override
// //  Widget build(BuildContext context) {
// //    return Center(
// //        child: Column(
// //          children: <Widget>[
// //            PinPut(
// //              fieldsCount: widget.digit ?? 6,
// //              isTextObscure: true,
// //              unFocusWhen: true,
// //              onSubmit: (String pin1) {
// ////            txfController[widget.scrName][_txfKey].controller.text =
// ////                _component['data'] ?? 'From pin';
// //                nPin1 = pin1;
// //                if (nPin1 == nPin2) {
// //                  BlocProvider.of<MainBloc>(context).add(NewPinSubmit(
// //                    pin: pin1,
// //                    okMessage: 'OK',
// //                    errMessage: widget.errMessage ?? 'Pin not match',
// //                    route: widget.route ?? home,
// //                  ));
// //                } else {
// //                  BlocProvider.of<MainBloc>(context).add(PinNotMatch(
// //                    message: widget.errMessage ?? 'Pin not match',
// //                  ));
// //                }
// //              },
// //              onClear: (String s) {},
// //            ),
// //            PinPut(
// //              fieldsCount: widget.digit ?? 6,
// //              isTextObscure: true,
// //              unFocusWhen: true,
// //              onSubmit: (String pin2) {
// //                nPin2 = pin2;
// //                if (nPin1 == nPin2) {
// //                  BlocProvider.of<MainBloc>(context).add(NewPinSubmit(
// //                    pin: pin2,
// //                    okMessage: 'OK',
// //                    errMessage: widget.errMessage ?? 'Pin not match',
// //                    route: widget.route ?? home,
// //                  ));
// //                } else {
// //                  BlocProvider.of<MainBloc>(context).add(PinNotMatch(
// //                    message: widget.errMessage ?? 'Pin not match',
// //                  ));
// //                }
// //              },
// //              onClear: (String s) {},
// //            ),
// //          ],
// //        ));
// //  }
// //}
