import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../bloc_timer/timer_bloc.dart';
import '../bloc_timer/timer_event.dart';
import '../global.dart';
import '../global2.dart';
import '../model/input_controller.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';

class QrGps extends StatefulWidget {
  const QrGps({
    required Key key,
    required this.component,
    required this.scrName,
  }) : super(key: key);
  final String scrName;
  final dynamic component;

  @override
  QrGpsState createState() => QrGpsState();
}

class QrGpsState extends State<QrGps> {
  bool change = true;
  // double width, height;
  final controller = TextEditingController(text: '-');
  String txtRes = '-';

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

    Future<void> scan1() async {
      String barcodeScanRes = empty;
      // Platform messages may fail, so we use a try/catch PlatformException.
      try {
        //        barcodeScanRes = qr1Decrypt(await FlutterBarcodeScanner.scanBarcode(
        //            "#ff3d00", "Batal", true, ScanMode.DEFAULT));
        if (barcodeScanRes.substring(1, 5) != "Fail") {
          Position? position = await getLocation();
          // await getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          controller.text = 'OK!';
          change = !change;
          String mock = 'No Gps';
          mock = position!.isMocked ? 'Mocked location' : 'True location';
          List<Placemark> placeMark = List<Placemark>.empty();
          try {
            placeMark = await placemarkFromCoordinates(
              position.latitude,
              position.longitude,
            );
          } catch (e) {
            debugPrint(e.toString());
          }
          // pool.play(scannerBeep);
          vibrate(duration: 100);

          String content = widget.component['flag'] ?? 'QR_GPS';
          txfController[widget.scrName]![1] = InputController(
            1,
            TextEditingController(text: content),
            content,
            content,
          );
          content = barcodeScanRes;
          txfController[widget.scrName]![2] = InputController(
            2,
            TextEditingController(text: content),
            content,
            content,
          );
          content = position.latitude.toString();
          txfController[widget.scrName]![3] = InputController(
            3,
            TextEditingController(text: content),
            content,
            content,
          );
          content = position.longitude.toString();
          txfController[widget.scrName]![4] = InputController(
            4,
            TextEditingController(text: content),
            content,
            content,
          );
          content = placeMark[0].isoCountryCode ?? "";
          txfController[widget.scrName]![5] = InputController(
            5,
            TextEditingController(text: content),
            content,
            content,
          );
          content = placeMark[0].postalCode ?? "";
          txfController[widget.scrName]![6] = InputController(
            6,
            TextEditingController(text: content),
            content,
            content,
          );
          content = cleanupString(placeMark[0].administrativeArea ?? "");
          txfController[widget.scrName]![7] = InputController(
            7,
            TextEditingController(text: content),
            content,
            content,
          );
          content = cleanupString(placeMark[0].subAdministrativeArea ?? "");
          txfController[widget.scrName]![8] = InputController(
            8,
            TextEditingController(text: content),
            content,
            content,
          );
          content = cleanupString(placeMark[0].locality ?? "");
          txfController[widget.scrName]![9] = InputController(
            9,
            TextEditingController(text: content),
            content,
            content,
          );
          content = cleanupString(placeMark[0].subLocality ?? "");
          txfController[widget.scrName]![10] = InputController(
            10,
            TextEditingController(text: content),
            content,
            content,
          );
          content = cleanupString(placeMark[0].thoroughfare ?? "");
          txfController[widget.scrName]![11] = InputController(
            11,
            TextEditingController(text: content),
            content,
            content,
          );
          content = cleanupString(placeMark[0].subThoroughfare ?? "");
          txfController[widget.scrName]![12] = InputController(
            12,
            TextEditingController(text: content),
            content,
            content,
          );
          content = mock;
          txfController[widget.scrName]![13] = InputController(
            13,
            TextEditingController(text: content),
            content,
            content,
          );

          widget.component['route'] =
              widget.component['route'] ?? home; //= default route = Home

          OtqState locSensor = OtqState().getDataFrom(
            position.timestamp,
            position,
            placeMark,
          );
          String locString = getLocationString(
            barcodeScanRes == empty ? '' : barcodeScanRes,
            '',
            '',
            locSensor,
          );
          saveData(widget.scrName, locString); //= send record to FromLink
        }
      } on PlatformException {
        barcodeScanRes = 'Failed to scan.';
      } catch (e) {
        barcodeScanRes = 'Failed to scan.';
      }
    } // end if (barcodeScanRes.substring(1, 5) != "Fail")

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      //      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 50),
        Text(
          widget.component['text'] ?? 'Push Scan Button',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        //        Container(
        //          height: 50,
        //        ),
        //        TextFormField(
        //          controller: controller,
        //          textAlign: TextAlign.center,
        //          enabled: false,
        //        ),
        Container(height: 100),
        ButtonTheme(
          minWidth: 200,
          height: 200,
          buttonColor: Colors.greenAccent,
          child: ElevatedButton(
            onPressed: () async => await scan1(),
            child: Text(
              widget.component['button'] ?? 'Scan',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
