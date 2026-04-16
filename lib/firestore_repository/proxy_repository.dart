import 'dart:async';
import '../global.dart';
import '../redux/screen_transaction.dart';

Future subscribeToEvent(String ssid) async {
  try {
    // the only submit document (with ssid as id)
    devPrint("===== setting event stream");
    var state = transactionStore.state.screenTx;
    if (state['#EVENT_LISTENER'] != null) {
      dynamic oldEventListener = state['#EVENT_LISTENER'];
      oldEventListener.cancel();
      devPrint('== Delete old event listener');
    } // end ((state['#EVENT_LISTENER']??'') != '')
    final docRef = firestoreDb.collection(firestoreEventCollection).doc(ssid);
    devPrint('== Listen to event in doc $ssid');
    try {
      final dynamic eventListener = docRef.snapshots().listen(
        (event) {
          devPrint("===== event listener run : ${event.data()}");
          if (event.data() != null) {
            // process event data
            dynamic rec = event.data();
            devPrint("===== START event processing : ${event.data()}");
            if (rec['st'] == 101) {
              // record already appended and processed
              devPrint('Deleting ${rec['ss']})');
              docRef.delete();
              //_submitRepository.deleteSubmit(rec); // delete event record in firestore
              // setDataOK('1'); // reload and set green light
            } // end iif (rec['st'] == 101)
            devPrint("========= END event processing");
          } // end if (event.data() == null)
        },
        onError: (error) => devPrint("Listen failed: $error"),
      ); // end of listener
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#EVENT_LISTENER': eventListener,
      })));
    } catch (e1) {
      devPrint ('====Listener error e1 $e1');
    } // end try
  } catch (e) {
    devPrint('=======Listener error e $e');
  }
} // end of Future listenToTable(String tableCode) {

Future unSubscribeToEvent() async {
  var state = transactionStore.state.screenTx;
  if (state['#EVENT_LISTENER'] != null) {
    dynamic oldEventListener = state['#EVENT_LISTENER'];
    oldEventListener.cancel();
    devPrint('== Unsubscribe old event listener');
  } // end ((state['#EVENT_LISTENER']??'') != '')
} // end of unSubscribeToEvent