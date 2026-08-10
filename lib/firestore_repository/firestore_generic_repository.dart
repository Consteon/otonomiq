import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../api.dart';
//import 'table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'table_repository.dart';

Future<String> uploadToCloudStorage(
  String localImage,
  String cloudFolder,
) async {
  // upload local image to cloud storage
  // return emptyImageUrl if failed; return cloud url if success
  // delete local file if success
  const String functionName = 'uploadToCloudStorage';
  List<dynamic>? imageMapEntry = imageMapGet(localImage);
  String result = emptyImageUrl;
  if (imageMapEntry != null && isValidImageUrl(imageMapEntry[1].toString())) {
    result = imageMapEntry[1].toString();
  } else {
    if (await imageFirebaseLock.itemLockWait(functionName, localImage)) {
      if (internetConnected()) {
        try {
          String currentLocal = localImage;
          File file = File(currentLocal);
          if (file.existsSync()) {
            dynamic storageBucket =
                transactionStore.state.screenTx['#STORAGE_BUCKET'];
            Reference storageRef = storageBucket.ref().child(cloudFolder);
            try {
              result = await storageRef.getDownloadURL();
            } catch (eu) {
              var c = eu.toString();
              if (c.contains('object-not-found')) {
                // Upload the file if it does not exist
                TaskSnapshot taskSnapshot = await storageRef.putFile(file);
                result = await taskSnapshot.ref.getDownloadURL();
                if (isValidImageUrl(result)) {
                  await imageMapUpdateUrl(currentLocal, result);
                  Future.delayed(const Duration(seconds: 5)).then((_) {
                    // delay file deletion
                    file.delete(); // file successfully uploaded, delete local file
                  });
                }
              } else {
                // Handle other errors
                rethrow;
              } // end if (c.contains('object-not-found'))
            } // end try eu
          } else {
            devPrint('$functionName: file not found $currentLocal');
          } // end if (file.existsSync())
        } catch (e) {
          devPrint('$functionName: error uploading $e');
        } // end try
      } else {
        devPrint('$functionName: no internet, skip upload');
      } // end if (internetConnected())
      imageFirebaseLock.itemUnlockWait(functionName, localImage);
    } else {
      devPrint('$functionName: lock failed for $localImage');
    } // end if (await imageFirebaseLock.itemLockWait(functionName, localImage))
  } // end if (imageMapEntry != null && isValidImageUrl(imageMapEntry[1]))
  return result;
} // end of uploadToCloudStorage

bool isValidImageUrl(String url) {
  final RegExp urlPattern = RegExp(
    r'^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^\/]+\/o\/[^?]+\?alt=media&token=[a-f0-9\-]+$',
    caseSensitive: false,
  );
  return urlPattern.hasMatch(url);
} // end of isValidImageUrl

Future<String?> checkIfUserReset(var user, String did) async {
  // check
  String? result;
  String path = topCollection;
  final query = await _getResilient(
    firestoreDb.collection(fsCollection).where("u", isEqualTo: user.uid),
  );
  if (query.docs.isNotEmpty) {
    path += '/${query.docs[0].id}';
    final device = await _getResilient(
      query.docs[0].reference.collection('dvc').where('did', isEqualTo: did),
    );
    if (device.docs.isNotEmpty) {
      result =
          '$path/dvc${separator[1]}${device.docs[0].id}'; // get first record
    }
  } // end if (query.docs.length >0)
  return result;
} // end of checkIfUserReset

// Read from the local Firestore cache first (instant on app reopen, even right
// after the process was killed), and only hit the server when the cache has no
// data yet (e.g. first run). Falls back to a server read with a timeout so a
// slow Firestore handshake can never block cold start indefinitely.
// Server-side changes (e.g. device reset on another phone) are still caught
// shortly after by the subscribeToUserReset() snapshot listener.
Future<QuerySnapshot<Map<String, dynamic>>> _getResilient(
  Query<Map<String, dynamic>> query,
) async {
  try {
    final cached = await query.get(const GetOptions(source: Source.cache));
    if (cached.docs.isNotEmpty) return cached;
  } catch (_) {
    // no cached data available -> fall through to a server read
  }
  return await query
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 12));
} // end of _getResilient

Future subscribeToUserReset(String docId) async {
  try {
    String myDid = await getDeviceId();
    List<String> docPath = docId.split(separator[1]);
    dynamic deviceListener =
        transactionStore.state.screenTx['#DEVICE_LISTENER'];
    bool needToListen = false;
    if (deviceListener == null) {
      devPrint('No DEVICE_LISTENER subscribed');
      needToListen = true;
    } else {
      devPrint('DEVICE_LISTENER has already subscribed');
    } // end if (deviceListener == null)
    if (needToListen) {
      devPrint('subscribe to DEVICE_LISTENER');
      final docRef = firestoreDb.collection(docPath[0]).doc(docPath[1]);
      if (docRef != null) {
        try {
          deviceListener = docRef.snapshots().listen(
            (event) {
              bool kicked = false;
              if (event.data() == null) {
                kicked = true;
              } else {
                if (event.data()['did'] != myDid) {
                  kicked = true;
                }
              } // end if (event.data() == null)
              if (kicked) {
                // Un-awaited inside a snapshot callback: anything kickedOut()
                // throws would surface as a FATAL crash with no app frames.
                safeUnawaited(kickedOut(), 'deviceListener kickedOut');
              }
            },
            onError: (error) => devPrint("Listen failed: $error"),
          ); // end of listener
          transactionStore.dispatch(
            UpdateScreenTxAction(
              ScreenTransaction({'#DEVICE_LISTENER': deviceListener}),
            ),
          );
        } catch (e1) {
          devPrint('error listening to device $e1');
        }
      } else {
        devPrint('No document $docId');
      } // end if (docRef != null)
    } // end if (needToListen)
  } catch (e) {
    devPrint(e);
  } // end try (e)
} // end of listenToUserReset

Future unsubscribeUserReset() async {
  try {
    var handle = transactionStore.state.screenTx['#DEVICE_LISTENER'];
    if (handle != null) {
      await handle.close();
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#DEVICE_LISTENER': null})),
      );
    } // end if (handle != null)
  } catch (e) {
    devPrint(e);
  }
} // end of unsubscribeTable

String getDevicePath(var device) {
  String result = '$fsCollection${separator[1]}${device.id}';
  return result;
}
