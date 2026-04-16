import '../redux/screen_transaction.dart';
import '../api.dart';

ScreenTransaction transactionReducer(ScreenTransaction tx, dynamic action) {
  if (action is AddScreenTxKeyAction) {
    return addScreenTxKey(tx, action);
  } else if (action is AddScreenTxRowAction) {
    return addScreenTxRow(tx, action);
  } else if (action is DeleteScreenTxRowAction) {
    return deleteScreenTxRow(tx, action);
  } else if (action is DeleteAllScreenTxRowAction) {
    return deleteAllScreenTxRow(tx);
  } else if (action is UpdateScreenTxAction) {
    return updateScreenTx(tx, action);
  } else if (action is SaveSendTxAction) {
    return saveSendTx(tx, action);
  } else if (action is SaveTxAction) {
    return saveTx(tx, action);
  }
  return tx;
} // end of transactionReducer

ScreenTransaction addScreenTxKey(
    ScreenTransaction tx, AddScreenTxKeyAction action) {
  ScreenTransaction newTx = ScreenTransaction(Map.from(tx.screenTx));
//  newTx.screenTx = json.decode(json.encode(tx.screenTx));
  action.screenRecord.screenTx.forEach((k, v) {
    newTx.screenTx[k] = v;
  });
  return newTx;
} // end of addScreenTxKey

ScreenTransaction addScreenTxRow(
    ScreenTransaction tx, AddScreenTxRowAction action) {
//  ScreenTransaction _newTx=ScreenTransaction(Map());
//  _newTx.screenTx = json.decode(json.encode(tx.screenTx));
  ScreenTransaction newTx = ScreenTransaction(Map.from(tx.screenTx));
  action.screenRow.screenTx.forEach((k, v) {
    if (newTx.screenTx[k] == null) {
      newTx.screenTx[k] = v;
    } else {
      for (int i = 0; i < v.length; i++) {
        newTx.screenTx[k].add(v[i]);
      }
    }
  });
  return newTx;
} // end of addScreenTxRow

ScreenTransaction deleteScreenTxRow(
    ScreenTransaction tx, DeleteScreenTxRowAction action) {
//  ScreenTransaction _newTx=ScreenTransaction(Map());
//  _newTx.screenTx = json.decode(json.encode(tx.screenTx));
  ScreenTransaction newTx = ScreenTransaction(Map.from(tx.screenTx));
  newTx.screenTx.remove(action.screenName);
  return newTx;
} // end of deleteScreenTxRow

ScreenTransaction deleteAllScreenTxRow(ScreenTransaction tx) {
  ScreenTransaction newTx = ScreenTransaction({});
  tx.screenTx.forEach((k, v) {
    if (isSystemState(k)) {
      newTx.screenTx[k] = v;
    }
  });
  return newTx;
} // end of deleteScreenTxRow

ScreenTransaction updateScreenTx(
    ScreenTransaction tx, UpdateScreenTxAction action) {
//  ScreenTransaction _newTx=ScreenTransaction(Map());
//  _newTx.screenTx = json.decode(json.encode(tx.screenTx));
  ScreenTransaction newTx = ScreenTransaction(Map.from(tx.screenTx));
  action.screenRow.screenTx.forEach((k, v) {
    newTx.screenTx[k] = v;
  });
  return newTx;
} // end of updateScreenTx

ScreenTransaction saveSendTx(ScreenTransaction tx, SaveSendTxAction action) {
  // not used anymore (201027 HH) widget will call appendToSheet directly
  ScreenTransaction newTx =
      ScreenTransaction(Map.from(tx.screenTx)); // copy all current state
   appendToSheetOld(action.screenRow.screenTx['screenName']);
  return newTx;
} // end of saveSendTx

ScreenTransaction saveTx(ScreenTransaction tx, SaveTxAction action) {
  ScreenTransaction newTx =
      ScreenTransaction(Map.from(tx.screenTx)); // copy all current state
  action.screenRow.screenTx.forEach((k, v) {
    // add each screen input to state
    if (newTx.screenTx[k] == null) {
      newTx.screenTx[k] = v;
    } else {
      for (int i = 0; i < v.length; i++) {
        newTx.screenTx[k].add(v[i]);
      }
    }
  });
  return newTx;
} // end of saveTx

bool isSystemState(String key) {
  bool result = false;

  var f = key.codeUnitAt(0);
  if (33 <= f && f <= 47) {
    result = true;
  }
  return result;
}
