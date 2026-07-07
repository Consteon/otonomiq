import 'dart:core';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../api.dart';
import '../bloc_submit/bloc.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';

abstract class SubmitRepository {
  Future<void> addNewSubmit2(Submit message);
  Future<void> addNewSubmit(Submit message);
  Future<void> deleteSubmit(Submit message);
  Stream<List<Submit>> submit();
  Future<void> updateSubmit(Submit message);
}

class FirebaseSubmitRepository implements SubmitRepository {
  // final submitInstance = FirebaseFirestore.instance;

  final submitCollection = FirebaseFirestore.instance.collection(
    firestoreEventCollection,
  );
  // final submitDoc =FirebaseFirestore.instance.doc(eventDoc);
  final submitDoc = FirebaseFirestore.instance
      .collection(firestoreEventCollection)
      .where(
        'ss',
        isEqualTo: transactionStore.state.screenTx['#INTERFACE_KEY'],
      );

  @override
  Future<void> addNewSubmit2(Submit submit) async {
    // add document to firestore
    // return submitCollection.add(submit.toEntity().toDocument());
    // return submitCollection.doc(submit.ss).set(submit.toEntity().toDocument());
    List<dynamic> newEvent = [
      submit.t,
      submit.p,
      submit.c2,
      submit.w,
      submit.f,
      submit.tb,
    ];
    devPrint('********** begin historyAdd');
    await historyAdd(newEvent);
    if (await internetConnectedCheck()) {
      // final firestoreEventCollection2 =
      //     '$proxyCollectionName/${submit.ss}/$eventCollectionName';
      // final docName = getEventDocName('${submit.appVid}${submit.t}');
      // final docReference = FirebaseFirestore.instance
      //     .collection(firestoreEventCollection2)
      //     .doc(docName);
      await sendImagesInImageMap();
      historySync('addNewSubmit2', false);
      // return submitCollection2
      //     .doc(docName)
      //     .set(submit.toEntity().toDocument2());
      // setDataOK('2');
    } // end if (internetConnected())
    actionUnLock('addNewSubmit2');
    // FirebaseFirestore.instance.settings =
    //     const Settings(persistenceEnabled: false);
    return;
    // return docReference.set(submit.toEntity().toDocument2()).then((value) {
    //   docReference.snapshots().listen((event) {
    //     if (event.exists) {
    //       historySent(submit.t);
    //       Timer timer = Timer(const Duration(seconds: 2), () {
    //         dynamic qParams = {"ssid": submit.ss};
    //         devPrint('=== call $eventFunctionName with param=$qParams');
    //         dynamic uri = Uri.https(functionFront, eventFunctionName);
    //         http.post(uri, body: qParams);
    //       });
    //       historyCloudReceived(submit.t);
    //       historyProcessed(submit.t);
    //     } // end if (event.exists)
    //   }); // end of listen
    // }); // end of docReference.then
  } // end of addNewSubmit2

  @override
  Future<void> addNewSubmit(Submit submit) {
    // add document to firestore
    // return submitCollection.add(submit.toEntity().toDocument());
    // return submitCollection.doc(submit.ss).set(submit.toEntity().toDocument());
    return submitCollection.doc(submit.ss).set(submit.toEntity().toDocument());
  }

  @override
  Future<void> deleteSubmit(Submit submit) async {
    return submitCollection.doc(submit.ss).delete();
  }

  @override
  Stream<List<Submit>> submit() {
    // the only submit document (with ssid as id)
    var state = transactionStore.state.screenTx;
    return FirebaseFirestore.instance
        .collection(firestoreEventCollection)
        .where('ss', isEqualTo: state['#INTERFACE_KEY'])
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Submit.fromEntity(SubmitEntity.fromSnapshot(doc)))
              .toList();
        });
  }

  @override
  Future<void> updateSubmit(Submit update) {
    return safeFsUpdate(
      submitCollection.doc(update.ss),
      update.toEntity().toDocument(),
      'updateSubmit',
    );
  }
}
