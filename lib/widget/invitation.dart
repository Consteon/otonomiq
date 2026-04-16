import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../global.dart';
import '../global2.dart';
import '../login/bloc_login/bloc.dart';
import '../login/page/login/login.dart';
import '../otq_icons.dart';

import '../api.dart';

class Invitation extends StatefulWidget {
  const Invitation({required Key key, required this.scrName, required this.component})
      : super(key: key);
  final dynamic component;
  final dynamic scrName;
//  final parentContext;

  @override
  _InvitationState createState() => _InvitationState();
}

class _InvitationState extends State<Invitation> {
  bool touch = true;

  @override
  Widget build(BuildContext context) {
    Widget result;
//    final _txfKey = widget.key;
    final txfKey = UniqueKey();
    var txfComponent = Map<String, dynamic>.from(widget.component);
    txfComponent['variant'] = 'barcode3';
    txfComponent['color'] = 'default';
    inputTxt[txfKey] = widget.component['currentValue'] ?? "";

    if (widget.component['position'] != null) {
      txfControllerCheck(
          widget.scrName, widget.component['position']); // build txfController if necessary
      if (canInitializePage(widget.scrName)) {
        txfController[widget.scrName]![getPosition(widget.component['position'])]!
            .controller
            .text = widget.component['currentValue'] ?? "";
        txfController[widget.scrName]![getPosition(widget.component['position'])]!
            .finalData = emptyString;
        txfController[widget.scrName]![getPosition(widget.component['position'])]!
            .initialValue = widget.component['currentValue'] ?? "";
      } // end if (canInitializePage(widget.scrName))
    } // end if (widget.component['position'] != null)

    // if (txfController[widget.scrName]![widget.component['position']] == null) {
    //   txfController[widget.scrName]![
    //           getPosition(widget.component['position'])] =
    //       InputController(
    //           getPosition(widget.component['position']),
    //           TextEditingController(
    //               text: widget.component['currentValue'] ?? ""),
    //           widget.component['currentValue'] ?? "",
    //           emptyString);
    // } else {
    //   txfController[widget.scrName]![getPosition(widget.component['position'])]!
    //       .controller
    //       .text = widget.component['currentValue'] ?? "";
    //   txfController[widget.scrName]![getPosition(widget.component['position'])]!
    //       .finalData = emptyString;
    //   txfController[widget.scrName]![getPosition(widget.component['position'])]!
    //       .initialValue = widget.component['currentValue'] ?? "";
    // } // end if (txfController[widget.scrName]![widget.component['position'] ?? 1] ==  null)
    var state = transactionStore.state.screenTx;
    dynamic uid;
    if (demoApp) {
      uid = null;
    } else {
      uid = state['#FIREBASE_USER'].uid;
    }
    double lPad = (systemUIComponent['Mobile']['leftPad'] ?? 0.0).toDouble();
    double tPad = (systemUIComponent['Mobile']['topPad'] ?? 0.0).toDouble();
    double rPad = (systemUIComponent['Mobile']['rightPad'] ?? 0.0).toDouble();
    double bPad = (systemUIComponent['Mobile']['bottomPad'] ?? 0.0).toDouble();

    result = Column(
      children: <Widget>[
        Container(
          margin: EdgeInsets.only(
              top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
              bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble()),
          padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),

          child: TextFormField(
            keyboardType: TextInputType.number,
            key: txfKey,
            controller: txfController[widget.scrName]![
                    getPosition(widget.component['position'])]!
                .controller,
            decoration: InputDecoration(
              icon: (widget.component['icon'] ?? 0) > 0
                  ? Icon(
                      otqIcons[widget.component['icon'].toString()],
                    )
                  : null,
              hintText: widget.component['hint'] ?? ' ',
              labelText: widget.component['label'] ?? ' ',
            ),
            style: TextStyle(
              color: (widget.component['color'] ?? 'default') != 'default'
                  ? Color(int.parse('0x' + widget.component['color']))
                  : Theme.of(context).textTheme.bodyMedium!.color,
              backgroundColor:
                  (widget.component['background'] ?? 'default') != 'default'
                      ? Color(int.parse(widget.component['background']))
                      : Theme.of(context).textTheme.bodyMedium!.backgroundColor,
              fontWeight: (widget.component['bold'] ?? 'FALSE') == 'TRUE'
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: (widget.component['italic'] ?? 'FALSE') == 'TRUE'
                  ? FontStyle.italic
                  : FontStyle.normal,
              decoration: (widget.component['underline'] ?? 'FALSE') == 'TRUE'
                  ? TextDecoration.underline
                  : TextDecoration.none,
              fontSize: 0.0 + widget.component['size'],
            ),
            obscureText:
                (widget.component['variant'] ?? 'generic') == 'password'
                    ? true
                    : false,
            onFieldSubmitted: (String value) {
              inputTxt[txfKey] = value;
            },
          ), // end of txf
        ),
//        Container(
//          child: TxfFull(
//            key: _txfKey,
//            scrName: widget.scrName,
//            component: txfComponent,
//          ),
//        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0)),
                  backgroundColor: Colors.teal,
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                onPressed: () {
                  rootThis.setState(() {
                    rootThis.wait = true;
                  });
                  var invNum = txfController[widget.scrName]![
                          getPosition(widget.component['position'])]!
                      .controller
                      .text;
                  BlocProvider.of<LoginBloc>(context).add(
                    InvitationLoginPressed(inv: invNum, uid: uid),
                  );
                },
                label: Text(widget.component['enter'],
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
    return result;
  }
}
