import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';

import '../api.dart';
import '../bloc_timer/timer_bloc.dart';
import '../bloc_timer/timer_event.dart';
import '../global.dart';
import '../global2.dart';
import '../model/connection_data.dart';
import '../model/input_controller.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';

/*
  Send current GPS location and display google map static
 */
class GpsSend extends StatefulWidget {
  const GpsSend({
    required Key key,
    required this.component,
    required this.scrName,
    this.single,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final dynamic single;

  @override
  GpsSendState createState() => GpsSendState();
}

class GpsSendState extends State<GpsSend> {
  bool change = true;

  @override
  Widget build(BuildContext context) {
    void saveData(String scrName, String locString) {
      TimerBloc timerBloc = transactionStore.state.screenTx['#TIMER_BLOC'];
      var route = widget.component['route'] ?? widget.scrName;
      rootThis.setState(() {
        rootThis.wait = true;
      });
      timerBloc.add(
        const Start(duration: 5),
      ); //  get timerBloc from transactionStore
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#NEXTROUTE': route,
            '#TIMER_CONTEXT': context,
            '#TIMER_DURATION': widget.component['delay'] ?? 5,
          }),
        ),
      ); // set state #NEXTROUTE route that will be displayed after waitScreen
      saveSend(null, scrName, widget.component, locString, defaultVid());
    } // end of saveData

    Future<void> sendLocation(List tArray) async {
      // Platform messages may fail, so we use a try/catch PlatformException.
      ConnectionData connectionData = await ConnectionData().getConnection(
        true,
        true,
      );
      if (await dataOk(context)) {
        setTransactionNotOK('sendLocation [57]');
        try {
          int nowTime = connectionData.time;
          var position = connectionData.position;
          if (position == null) {
            await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  // dialog 3
                  title: Text(textList["Fail"]),
                  content: Container(
                    alignment: const Alignment(0.0, 0.0),
                    height: dialogHeight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(textList["GpsProblem"])],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(getText(tArray, 8)),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else {
            // actionLock();
            String mock = 'Unknown';
            mock = position.isMocked ? 'Mocked location' : 'True location';

            late String? dialogText1;
            late String fromLinkOption;

            switch (widget.component['actionLast'] ?? "Checkpoint") {
              case 'clock-out':
                dialogText1 = getText(tArray, 3); // scenario 1
                fromLinkOption = 'normal-clock-in';
                break;

              case 'clock-in':
                if ((widget.component['timeClockOut1'] ?? 0) <= nowTime &&
                    nowTime <= (widget.component['timeClockOut2'] ?? 0)) {
                  dialogText1 = getText(tArray, 4); // scenario 2
                  fromLinkOption = 'normal-clock-out';
                } else {
                  await showDialog(
                    // show dialog 34
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        // dialog 34
                        title: Text(getText(tArray, 9)),
                        content: Text(getText(tArray, 10)),
                        actions: <Widget>[
                          TextButton(
                            child: Text(getText(tArray, 12)), // scenario 4
                            onPressed: () {
                              dialogText1 = getText(tArray, 5); // scenario 4
                              fromLinkOption = 'clock-out-overtime';
                              Navigator.of(context).pop();
                            },
                          ),
                          TextButton(
                            child: Text(getText(tArray, 11)),
                            onPressed: () {
                              dialogText1 = getText(tArray, 6); // scenario 3
                              fromLinkOption = 'forgot-clock-out';
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                }
                break;

              default: // Checkpoint , scenario 5
                dialogText1 = getText(tArray, 7);
                fromLinkOption = 'checkpoint';
            } // end switch

            change = !change;
            List<Placemark> placeMark = connectionData.placeMark;
            // List<Placemark> placeMark = await placemarkFromCoordinates(
            //     position.latitude, position.longitude);
            // pool.play(scannerBeep);
            vibrate(duration: 100);

            String content = widget.component['flag'] ?? 'GPS_SEND';
            txfController[widget.scrName]![1] = InputController(
              1,
              TextEditingController(text: content),
              content,
              content,
            );
            content = nowTime.toString();
            txfController[widget.scrName]![2] = InputController(
              2,
              TextEditingController(text: content),
              content,
              content,
            );
            content = fromLinkOption;
            txfController[widget.scrName]![3] = InputController(
              3,
              TextEditingController(text: content),
              content,
              content,
            );

            content = position.latitude.toString();
            txfController[widget.scrName]![4] = InputController(
              4,
              TextEditingController(text: content),
              content,
              content,
            );
            content = position.longitude.toString();
            txfController[widget.scrName]![5] = InputController(
              5,
              TextEditingController(text: content),
              content,
              content,
            );
            content = placeMark.isNotEmpty
                ? placeMark[0].isoCountryCode!
                : invalidCountry;
            txfController[widget.scrName]![6] = InputController(
              6,
              TextEditingController(text: content),
              content,
              content,
            );
            content = placeMark.isNotEmpty ? placeMark[0].postalCode! : "";
            txfController[widget.scrName]![7] = InputController(
              7,
              TextEditingController(text: content),
              content,
              content,
            );
            content = cleanupString(
              placeMark.isNotEmpty ? placeMark[0].administrativeArea! : "",
            );
            txfController[widget.scrName]![8] = InputController(
              8,
              TextEditingController(text: content),
              content,
              content,
            );
            content = cleanupString(
              placeMark.isNotEmpty ? placeMark[0].subAdministrativeArea! : "",
            );
            txfController[widget.scrName]![9] = InputController(
              9,
              TextEditingController(text: content),
              content,
              content,
            );
            content = cleanupString(
              placeMark.isNotEmpty ? placeMark[0].locality! : "",
            );
            txfController[widget.scrName]![10] = InputController(
              10,
              TextEditingController(text: content),
              content,
              content,
            );
            content = cleanupString(
              placeMark.isNotEmpty ? placeMark[0].subLocality! : "",
            );
            txfController[widget.scrName]![11] = InputController(
              11,
              TextEditingController(text: content),
              content,
              content,
            );
            content = cleanupString(
              placeMark.isNotEmpty ? placeMark[0].thoroughfare! : "",
            );
            txfController[widget.scrName]![12] = InputController(
              12,
              TextEditingController(text: content),
              content,
              content,
            );
            content = cleanupString(
              placeMark.isNotEmpty ? placeMark[0].subThoroughfare! : "",
            );
            txfController[widget.scrName]![13] = InputController(
              13,
              TextEditingController(text: content),
              content,
              content,
            );
            content = mock;
            txfController[widget.scrName]![14] = InputController(
              14,
              TextEditingController(text: content),
              content,
              content,
            );

            widget.component['route'] =
                widget.component['route'] ?? home; //= default route = Home
            OtqState locSensor = OtqState().getDataFrom(
              DateTime.fromMillisecondsSinceEpoch(nowTime),
              position,
              placeMark,
            );
            String locString = getLocationString('', '', '', locSensor);
            saveData(widget.scrName, locString); //= send record to FromLink

            // display dialog 1
            await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  // dialog 1
                  title: Text(getText(tArray, 2)),
                  content: Container(
                    alignment: const Alignment(0.0, 0.0),
                    height: dialogHeight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dialogText1 ?? "--Bad GPS_SEND Text--"),
                        Container(height: 12),
                        Text(
                          "${placeMark.isNotEmpty ? placeMark[0].thoroughfare! : emptyString} ${placeMark.isNotEmpty ? placeMark[0].subThoroughfare! : emptyString}, ${placeMark.isNotEmpty ? placeMark[0].administrativeArea! : emptyString} ${placeMark.isNotEmpty ? placeMark[0].postalCode! : emptyString}",
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(getText(tArray, 8)),
                      onPressed: () {
                        devPrint(
                          '********** actionUnLock from gps_send dialog [240]',
                        );
                        // actionUnLock('gps_send dialog action [243]');
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } // end if position
        } on PlatformException catch (err) {
          // display dialog fail, and play wrong beep
          setDataOK(
            '1',
          ); // reload pages and display green anyway. So the app will not lock up
          devPrint(err);
          await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                // dialog 3
                title: const Text("Gagal"),
                content: Container(
                  alignment: const Alignment(0.0, 0.0),
                  height: dialogHeight,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text("Gagal, coba ulangi sekali lagi.")],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(getText(tArray, 8)),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        }
      } // end of dataOk
    } // end of _sendLocation

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
                  Container(height: topPad),
                  AspectRatio(
                    aspectRatio: defaultAspectRatio,
                    child: displayImage(
                      imageUrl: widget.component['url'] ?? defaultImage,
                      cached: true,
                    ),
                    // child: FadeInImage.memoryNetwork(
                    //   placeholder: kTransparentImage,
                    //   image: widget.component['url'] ?? defaultImage,
                    // ),
                  ),
                  Text(
                    textArray[0],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fontSize),
                  ),
                ],
              ),
              onTap: () async {
                await sendLocation(textArray);
              },
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
                Container(height: topPad),
                AspectRatio(
                  aspectRatio: defaultAspectRatio,
                  child: displayImage(
                    imageUrl: widget.component['url'] ?? defaultImage,
                    cached: true,
                  ),
                  // child: CachedNetworkImage(
                  //   imageUrl: widget.component['url'] ?? defaultImage,
                  //   placeholder: (context, url) => Container(
                  //     color: Colors.transparent, // Set transparency
                  //     width: double.infinity, // Match image size
                  //     height: double.infinity, // Match image size
                  //   ), // Placeholder while loading
                  //   errorWidget: (context, url, error) => const Icon(Icons.error), // Error widget
                  //   fadeInDuration: const Duration(milliseconds: 100), // Fade-in effect
                  // ),
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
            onTap: () async {
              await sendLocation(textArray);
            },
          ),
        ),
      );
    }
    return button;
  }
}
