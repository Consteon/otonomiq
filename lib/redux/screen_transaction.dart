import '../global.dart';

class ScreenTransaction {
  Map<String, dynamic> screenTx;
  ScreenTransaction(this.screenTx);

  @override
  String toString() {
    return "Redux screen transactions store for Link apps";
  }
} // end of ScreenTx

class AddScreenTxKeyAction {                       // add new screen and rows
  final ScreenTransaction screenRecord;            // two dimensional array value{'scr1':[[1,2,3,4]]} / dynamic
  AddScreenTxKeyAction(this.screenRecord);
} // end of AddScreenKey

class AddScreenTxRowAction {                       // add rows to existing screen; if screen not exist, insert new screen
  final ScreenTransaction screenRow;               // two  dimensional array value {'scr1':[[1,2,3]]} / dynamic
  AddScreenTxRowAction(this.screenRow);
}

class UpdateScreenTxAction {                       // replace existing screen; if screen not exist, insert new screen
  final ScreenTransaction screenRow;               // two  dimensional array value {'scr1':[[1,2,3]]} / dynamic
  UpdateScreenTxAction(this.screenRow);
}

class DeleteScreenTxRowAction {                    // delete screenName entry in transactionStore
  final String screenName;                         // name of screen
  DeleteScreenTxRowAction(this.screenName);
}

class DeleteAllScreenTxRowAction {                 // delete all screen entry in transactionStore
  DeleteAllScreenTxRowAction();
}

class SaveSendTxAction {                           // add rows to existing screen; if screen not exist, insert new screen
  final ScreenTransaction screenRow;               // two  dimensional array value {'scr1':[[1,2,3]]} / dynamic
  SaveSendTxAction(this.screenRow);
}

class SaveTxAction {                               // add rows to existing screen; if screen not exist, insert new screen
  final ScreenTransaction screenRow;               // two  dimensional array value {'scr1':[[1,2,3]]} / dynamic
  SaveTxAction(this.screenRow);
}

Map<String,dynamic> initTransactionStore() {
  Map<String,dynamic> result = {};
  result['#VID'] = null;
  result['#TX_LOCK'] = false;
  result['#LOGIN_OK'] = false;
  result['#NOTIFICATION'] = 0;
  result['#CART'] = 0;
  result['#UNREAD'] = 0;
  result['#SHEET_API'] = false;
  result['#CURRENT_ROUTE'] = home;

  return result;
}


