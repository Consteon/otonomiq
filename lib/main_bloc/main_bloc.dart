import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';

import '../api.dart';
import '../crypto/auth_crypto.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import './bloc.dart';

class MainBloc extends Bloc<MainEvent, MainState> {
  MainBloc(super.initialState);
  //class MainBloc extends Bloc<MainEvent, MainState> {
  //  MainBloc() : super(null);

  //@override
  MainState get initialState => MainState.empty();

  @override
  Stream<MainState> mapEventToState(MainEvent event) async* {
    if (event is ResetAll) {
      yield* _mapResetAllToState();
    } else if (event is PinSubmit) {
      yield* _mapPinSubmitToState(
        event.pin,
        event.errorMid,
        event.screenJson,
        event.route,
        event.scrName,
        event.mainTid,
        event.notifyText,
        event.targetVids,
        event.from,
        event.data,
      );
    } else if (event is NewPinSubmit) {
      yield* _mapNewPinSubmitToState(event.pin);
    } else if (event is WrongPin) {
      yield* _mapWrongPinToState(event.message1, event.message2);
      //    } else if (event is NeedPinHash) {  // uncomment this line and fix pinput
      //      yield* _mapNeedPinHashState();
    } else if (event is ResetAll) {
      yield* _mapResetAllToState();
    } else if (event is QrAttend1Scan) {
      yield* _mapQrAttend1ScanToState(
        event.front!,
        event.flash!,
        event.size!,
        event.fSize!,
        event.exitSize!,
        event.exitRoute!,
        event.crypto!,
        event.exitString!,
        event.position!,
        event.screenName!,
      );
    } else if (event is ScanResult) {
      yield* _mapScanResultToState(
        event.front!,
        event.flash!,
        event.size!,
        event.fSize!,
        event.exitSize!,
        event.exitRoute!,
        event.crypto!,
        event.exitString!,
        event.result!,
        event.position!,
        event.scrName!,
      );
    }
  }

  Stream<MainState> _mapResetAllToState() async* {
    yield MainState.empty();
  }

  Stream<MainState> _mapNeedPinHashState() async* {
    yield MainState.needPin();
  }

  Stream<MainState> _mapNewPinSubmitToState(String pin) async* {
    pinHash(pin).then((theHash) {
      // put in storage
      storage.write(
        key: 'pinHash',
        value: theHash,
      ); // store pinHash in secure & persistent storage
      // put in LIF
      storage.read(key: 'myLif').then((lifKey) {
        // call something like writeSSA1 to write to spreadhseet
        // writeToSheetRange(lifKey!, 'Settings!G10:G10', [
        //   [theHash]
        // ]);
      });
      // put pin hash in firestore
      // put pin hash in blockchain
    });
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#NEED_PINHASH': false})),
    );
    yield MainState.empty();
  }

  Stream<MainState> _mapPinSubmitToState(
    String pin,
    String errorMid,
    String screenJson,
    String route,
    String scrName,
    String mainTid,
    String notifyText,
    String targetVids,
    String from,
    String data,
  ) async* {
    //    var storeHash = await storage.read(key: 'pinHash');
    // cut & concat $argon2id$v=19$m=65536,t=2,p=1$
    //    var verified = await argon2VerifyPassword(pin, storeHash);
    var verified = true;
    if (verified) {
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({'#NEXTROUTE': route, '#TIMER_DURATION': 1}),
        ),
      ); // set state #NEXTROUTE route that will be displayed after waitScreen
      // saveSendRecord(scrName);
      // find a way to record pin here
      yield MainState.empty();
      // send message here
      //      var mTo = [777250221000, 777250221003, 922250226073];
      //      var mDisplay = "This is my message.";
      //      var mData = {"action": "GOTO", "route": "Profile"};
      //      var mFrom = "777250221000";
      sendMessage(targetVids, from, notifyText, data, true, 0);
      rootThis.setState(() {
        rootThis.byPass = 0;
      });
      var pgName = home;
      routeStack.push(pgName);
      gotoRoute(pgName);
    }
  }

  Stream<MainState> _mapWrongPinToState(
    String message1,
    String message2,
  ) async* {
    yield MainState.wrongPin(message1, message2);
  }

  Stream<MainState> _mapQrAttend1ScanToState(
    bool front,
    bool flash,
    int size,
    int fSize,
    int exitSize,
    String exitRoute,
    String crypto,
    String exitString,
    int position,
    String screenName,
  ) async* {
    yield MainState.contScan(
      exitRoute,
      crypto,
      front,
      flash,
      position,
      screenName,
      size,
      fSize,
      exitSize,
      exitString,
    );
  }

  Stream<MainState> _mapScanResultToState(
    bool front,
    bool flash,
    int size,
    int fSize,
    int exitSize,
    String exitRoute,
    String crypto,
    String exitString,
    String result,
    int action,
    String scrName,
  ) async* {
    String rawResult = '--';
    String feedBackResult = rawResult;
    int feedBackAction = -1; // ACK
    int position = action; // get action as position
    String result0 = result;
    //    _result = '[1122334455,"My name is blank",1569926406]';
    switch (crypto) {
      case 'attend1':
        {
          try {
            int tNow = DateTime.now().millisecondsSinceEpoch;
            rawResult = crQRAttend1Dec(result0);
            var res = jsonDecode(rawResult);
            if (res[2] <= tNow || tNow <= res[3]) {
              feedBackResult = res[1];
              feedBackAction = 1;
            } else {
              feedBackAction = -1;
            }
          } catch (err) {
            feedBackResult = '--';
            feedBackAction = -1;
          }
        }
        break;

      case 'raw':
        {
          try {
            int tNow = DateTime.now().millisecondsSinceEpoch;
            //            rawResult = crQRAttend1Dec(_result);
            //            var res = jsonDecode(rawResult);
            feedBackResult = result0;
            feedBackAction = 1;
          } catch (err) {
            feedBackResult = '--';
            feedBackAction = -1;
          }
        }
        break;

      default:
        {
          feedBackResult = result;
        }
    }
    int duration = 2; // duration before switch back to contScan state
    // implement duration in scanFeedBack
    if (feedBackAction > 0) {
      saveSendSingle(scrName, position, rawResult);
    }
    yield MainState.scanFeedBack(
      exitRoute,
      crypto,
      front,
      flash,
      action,
      feedBackResult,
      feedBackAction,
      duration,
      scrName,
      size,
      fSize,
      exitSize,
      exitString,
    );
  }
}
