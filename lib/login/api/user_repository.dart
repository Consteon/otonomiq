import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../global.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../redux/screen_transaction.dart';
import '../../api.dart';
import 'package:flutter/material.dart';
import '../../ftz_secret.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../firestore_repository/firestore_generic_repository.dart';
import '../../firestore_repository/proxy_repository.dart';
import '../../firestore_repository/table_repository.dart';
// idea from https://medium.flutterdevs.com/google-sign-in-with-flutter-8960580dec96

class UserRepository {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  String? verificationId;

  UserRepository({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignin})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignin ?? GoogleSignIn.instance;
            // GoogleSignIn();
              // signInOption: SignInOption.standard,
              // scopes: [
//                'https://www.googleapis.com/auth/drive',
//                'https://www.googleapis.com/auth/drive.appdata',
//                'https://www.googleapis.com/auth/spreadsheets',
//               ],
//             );

  Future<User?> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    User? currentUser;
    const List<String> scopes = <String>[
      'email',
      // 'https://www.googleapis.com/auth/drive',
      // 'https://www.googleapis.com/auth/drive.appdata',
      // 'https://www.googleapis.com/auth/spreadsheets',
    ];
    try {
      // googleUser = await _googleSignIn.authenticate(scopeHint: scopes);
      googleUser = await _googleSignIn.authenticate();
    } catch (er) {
      devPrint('signInWithGoogle error : $er');
    }

    if (googleUser != null) {
      final GoogleSignInClientAuthorization? auth =
      await googleUser.authorizationClient.authorizeScopes(scopes);
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? accessToken = auth?.accessToken;
      final String? idToken = googleAuth.idToken;

      // Ensure both tokens are available before creating the credential.
      if (accessToken == null || idToken == null) {
        devPrint('Missing Google Auth Token after authorization.');
        return null;
      }
      final AuthCredential credential = GoogleAuthProvider.credential(
        // accessToken: googleAuth.accessToken,
        accessToken: accessToken,
        idToken: googleAuth.idToken,
      );
      devPrint(googleUser);
      devPrint(googleAuth);
      devPrint(credential);
      late UserCredential userAuth;
      try {
        userAuth = await _firebaseAuth.signInWithCredential(credential);
      } catch (e) {
        devPrint(e);
      }
      User? user;
      try {
        user = userAuth.user;
      } catch (e) {
        devPrint(e);
      }
      assert(user!.email != null);
      assert(user!.displayName != null);
      assert(!user!.isAnonymous);
      // assert(await user!.getIdToken() != null);
      devPrint('${user!.displayName} => ${user.uid}');

      currentUser = _firebaseAuth.currentUser!;
      assert(user.uid == currentUser.uid);
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#FIREBASE_USER': currentUser,
        '#AUTH_METHOD': 'Google',
      }))); // Set currentUser as FIREBASE_USER
//    var sKey = await getUserDataFirebase(currentUser);
    } // end of googleUser
    return currentUser;
  } // end of signInWithGoogle

  Future<User?> signInWithApple() async {
    User? currentUser;
    late UserCredential userAuth;
    dynamic appleCredential;
    dynamic oauthCredential;
    try {
      try {
        appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          // nonce: 'YOUR_NONCE', // (Optional) Generate and use a nonce for additional security
        );
      } catch (eApple) {
        devPrint(eApple);
      }
      // 2. Create an `OAuthCredential` from the credential returned by Apple
      try {
        oauthCredential = OAuthProvider("apple.com").credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode,
        );
      } catch (eAuth) {
        devPrint(eAuth);
      }
      userAuth = await _firebaseAuth.signInWithCredential(oauthCredential);
      // userAuth = await _firebaseAuth.signInWithProvider(AppleAuthProvider());
    } catch (e) {
      devPrint(e);
    }
    User? user;
    try {
      user = userAuth.user;
    } catch (e) {
      devPrint(e);
    }
    // assert(user!.email != null);
    // assert(user!.displayName != null);
    // assert(!user!.isAnonymous);
    devPrint('${user!.displayName} => ${user.uid}');

    currentUser = _firebaseAuth.currentUser!;
    assert(user.uid == currentUser.uid);
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#FIREBASE_USER': currentUser,
      '#AUTH_METHOD': 'Apple ID',
    }))); // Set currentUser as FIREBASE_USER
    return currentUser;
  } // end of signInWithApple

  Future<User> signInWithFacebook(String facebookAcc) async {
    final AuthCredential credential =
        FacebookAuthProvider.credential(facebookAcc);
    final UserCredential userAuth =
        await _firebaseAuth.signInWithCredential(credential);
    final User user = userAuth.user!;
    assert(user.email != null);
    assert(user.displayName != null);
    assert(!user.isAnonymous);
    // assert(await user.getIdToken() != null);
    devPrint('${user.displayName} => ${user.email}');

    final User currentUser = _firebaseAuth.currentUser!;
    assert(user.uid == currentUser.uid);
    return currentUser;
  } // end of signInWithFacebook

  Future<User> signInWithTwitter(String twitterAcc, String twitterPass) async {
    final AuthCredential credential = TwitterAuthProvider.credential(
        accessToken: twitterAcc, secret: twitterPass);

    final UserCredential userAuth =
        await _firebaseAuth.signInWithCredential(credential);
    final User user = userAuth.user!;
    assert(user.email != null);
    assert(user.displayName != null);
    assert(!user.isAnonymous);
    devPrint('${user.displayName} => ${user.email}');

    final User currentUser = _firebaseAuth.currentUser!;
    assert(user.uid == currentUser.uid);
    return currentUser;
  } // end of signInWithFacebook

  Future<void> signInWithCredentials(String email, String password) {
    return _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Sends the code to the specified phone number.
  Future<void> sendCodeToPhoneNumber(String phone) async {
    verificationCompleted(AuthCredential user) {
//      setState(() {
//        devPrint('Inside _sendCodeToPhoneNumber: signInWithPhoneNumber auto succeeded: $user');
//      });
      devPrint(
          'Inside _sendCodeToPhoneNumber: signInWithPhoneNumber auto succeeded: $user');
    }

    verificationFailed(FirebaseAuthException authException) {
//      setState(() {
//        devPrint('Phone number verification failed. Code: ${authException.code}. Message: ${authException.message}');}
//      );
      devPrint(
          'Phone number verification failed. Code: ${authException.code}. Message: ${authException.message}');
    }

    codeSent(String verificationId, [int? forceResendingToken = 1]) async {
      this.verificationId = verificationId;
      devPrint("code sent to $phone");
    }

    codeAutoRetrievalTimeout(String verificationId) {
      this.verificationId = verificationId;
      devPrint("time out");
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 5),
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed,
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout);
  }

  Future<User> signInWithPhone(String smsCode) async {
    final FirebaseAuth auth = FirebaseAuth.instance;
//    await sendCodeToPhoneNumber(phone);
    final AuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId!,
      smsCode: smsCode,
    );
    final UserCredential currentUserAuth =
        await auth.signInWithCredential(credential);
    final User currentUser = currentUserAuth.user!;
//    final GoogleSignInAccount googleUser = await _googleSignIn.signIn();
//    final GoogleSignInAuthentication googleAuth =
//        await googleUser.authentication;
//    final AuthCredential credential = GoogleAuthProvider.getCredential(
//      accessToken: googleAuth.accessToken,
//      idToken: googleAuth.idToken,
//    );
//    await _firebaseAuth.signInWithCredential(credential);
    return currentUser;
  }

  Future<UserCredential> signUp(
      {required String email, required String password}) async {
    return await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<List<void>> systemSignOut() async {
    return Future.wait([
      _firebaseAuth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Future<bool> isSignedIn() async {
    final currentUser = _firebaseAuth.currentUser;
    return currentUser != null;
  }

  Future<String> getUser() async {
//    return (await _firebaseAuth.currentUser()).phoneNumber;
//    return (await _firebaseAuth.currentUser()).displayName;
    return 'Demo';
  }

  Future<String> getUserUid() async {
    return (_firebaseAuth.currentUser)!.uid;
  }

  Future<int> aumLogin(String country, String inv) async {
    /*
      output :
        0 = login successful
        1 = No previous login
        2 = fail, logged in other device
        3 = fail, developer / demo account can't find matching deviceId
     */
    var state = transactionStore.state.screenTx;
    var cUser = state['#FIREBASE_USER']; // get current firebase user data
    var myUid = cUser.uid;
    var myEmail = cUser.email ?? '${myUid}_no_email@authenium.io';
    String myVid;
    var myDoc;
    var result = 2; // default 1 = No previous login
    String sk0;
    String cl;
    String ak0;
    var ds;
//    var msg;
    var myUid0;
//    var myDeviceId;
    var userData;
//    var updateData = Map<String, dynamic>();
    String myPath;

    try {
      bool loginOK = false;
      ds = await getFirestoreUserData(
          myUid,
          myEmail,
          country,
          phoneCleanup(
              inv)); //= get user data. If uid not defined, will try search email, if fail get new vid
      if (ds is String || ds is int) {
        loginOK = false;
      } else {
        loginOK = true;
      } // end if recFound

      devPrint('loginOK = $loginOK');
      if (loginOK) {
        result = 0;

        myDoc = ds.id; //= get document ID
        var docRef = ds.reference;
        myPath = ds.reference.parent.path; //= get path to this dvc document
        userData = ds.data();
        myVid = "${userData['vid']}";
        myUid0 = myUid;
        sk0 = userData['lif'];
        cl = userData['clt'];
        ak0 = userData['acc'];
        fsMsgCollection = "$msgPrefix${userData["clt"]}";
        // firestoreEventCollection = '$eventPrefix${userData["clt"]}';
        var messageRef = await getFirestoreMessageRef(myVid);
        firestoreIO = messageRef.path +
            "/io"; //= set firestoreIO singleton from global.dart
        eventDoc = '$firestoreEventCollection/$sk0';
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
          '#EMAIL': cUser.email,
          '#INTERFACE_KEY': sk0,
          '#ACC_KEY': ak0,
          '#FS_DOC': myDoc,
          '#FS_IO': firestoreIO,
          '#FS_PATH': myPath,
          '#ADDRESS': myVid,
          '#FS_REF': docRef,
          '#CLUSTER': userData["clt"],
          '#MSG_REF': messageRef,
          '#CURRENT_ROUTE': home,
          '#FS_USER_DOC_ID': ds,
        }))); //   set state #INTERFACE_KEY
        // await prefs.remove('@pages');
        await prefs.remove('@systemUI');
        await prefs.remove('@screenUI');
        subscribeToEvent(sk0); // subscribe to user's proxy event
        await runSheetStartup(sk0, userData["clt"]);
        state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        var ak = state['#ACC_KEY'];
        storage.write(
            key: 'myAcc', value: ak); //   put Account key in secure storage
        storage.write(
            key: 'myCluster', value: cl); //   put cluster id in secure storage
        storage.write(
            key: 'myLif',
            value: sk); //   put interface key as default LIF in secure storage
        storage.write(
            key: 'myPath',
            value: myPath); //= firebase full path collection /dvc
        storage.write(key: 'myDoc', value: myDoc); //= documentId from /dvc
        storage.write(key: 'myMsgId', value: messageRef.id);
        storage.write(
            key: 'sd1',
            value: ftzSecretOneSeed); //   put Account key in secure storage
        var nxPage = home; //   set default page = Home
        loadHistory(clearHistory, 'aumLogin (user_repository) <= async' );
        readSettings(sk, 1).then((_) {
          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
              {'#REFRESH': false, '#CURRENT_ROUTE': nxPage})));
          List<Widget> newElementList = reloadPage(nxPage);
          rootThis.setState(() {
            rootThis.pageName = nxPage;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
            rootThis.touch = !rootThis.touch;
          });
        });
        result = await reLogin();
        subscribeToUserReset(getDevicePath(ds));
      } else {
        result = ds;
        // 1;
      }
    } catch (err) {
      result = 2;
    }
    return result;
  } // end of vertrizLogin

  Future reLogin() async {
    // TODO finish justReLogin procedure
    // after logged out then re login
    // Set vid in transactionStore
    // save sheetKey to persistence.storage
    //X save FirebaseUser to persistence.storage 'myFirebaseData'
    // save uid, imei, in to firebase
    await getMyImei(); // put imei in #IMEI
    var state = transactionStore.state.screenTx;
    var sheetData = await getLifProfileData(state['#INTERFACE_KEY']);
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#VID': sheetData['vid'],
//      '#ADDRESS': sheetData['address'],
      '#PINHASH': sheetData['pinHash'],
      '#CIPHERTEXT': sheetData['cipherText'],
      '#PUBLICKEY': sheetData['publicKey'],
    })));
    storage.write(key: 'myLif', value: state['#INTERFACE_KEY']);
//  storage.write(key: 'myFirebaseData', value: jsonEncode(state['#FIREBASE_USER']));
//    await setUidImeiEmail(sheetData['vid'].toString()); // To Firestore
    return launchCheck();
  }

  Future<int> invitationLoginDemo(String inv) async {
    /*
      output :
        0 = login successful
        1 = user full error (no more available user to be assigned for the new user
        2 = vid is wrong (no such vid in firestore)
        3 = pin is wrong (pin not match with corresponding pin in firestore vid
        4 = vertriz login fail (other error, vertriz login failure)
        5 = general login failure
     */
    var result = 4; // default 4 = Vertriz Fail
    var state = transactionStore.state.screenTx;
    var cUser = state['#FIREBASE_USER']; // get current firebase user data
    var myUid = cUser.uid;
    var vid;
//    var _address;
    try {
      var ds = await FirebaseFirestore.instance
          .collection(
              fsCollection) // search data in firebase with corresponding inv
          .where('inv', isEqualTo: inv)
          .get();
      if (ds.docs.isNotEmpty) {
        // invitation# found in firestore
//          _address = ds.docs[0].id;
        vid = ds.docs[0].data()['vid'];
        var sheetKey = ds.docs[0].data()['sheetKey'];
        int now = DateTime.now().millisecondsSinceEpoch;
        if (now <= ds.docs[0].data()['inv_exp']) {
          if (ds.docs[0].data()['in'] && ds.docs[0].data()['uid'] != myUid) {
            result = 2; // other user logged in with this invitation
          } else {
            await firstLoginDemo(vid, sheetKey);
            result = 0;
          }
        } else {
          result = 7; // expired
        }
      } else {
        result = 6; // invitation # not valid
      }
    } catch (_) {
      result = 4;
    }

    if (result == 0) {
      // if success
      try {
        // TODO write to handle
        // TODO execute instruction2 in Lif, Hub & Account
        state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        await readSettings(sk, 1); //   read new interface key
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
          '#REFRESH': false
        }))); //   refresh flag to false because this is a refresh
        // List<Widget> newElementList =
        //     List<Widget>.empty(); //   prepare new element list
        var nxPage = home; //   set default page = Home
        List<Widget> newElementList = List<Widget>.of(linkElement[nxPage]!.map(
            (widget) =>
                widget)); //   get all page element from global linkElement map
        // newElementList.addAll(linkElement[
        //     nxPage]!); //   get all page element from global linkElement map
        routeStack.push(nxPage); //   put in routStack
        rootThis.setState(() {
          //   update state in main page to trigger a refresh
          rootThis.pageName = nxPage;
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
          rootThis.touch = !rootThis.touch;
        });
      } catch (err) {
        result = 4;
      }
    }
    return result;
  } // end of invitationLoginDemo

  Future<int> invitationLoginWithUid(String inv) async {
    /*
      output :
        0 = login successful
        1 = user full error (no more available user to be assigned for the new user
        2 = vid is wrong (no such vid in firestore)
        3 = pin is wrong (pin not match with corresponding pin in firestore vid
        4 = vertriz login fail (other error, vertriz login failure)
        5 = general login failure
     */
    var result = 4; // default 4 = Vertriz Fail
    var state = transactionStore.state.screenTx;
    var cUser = state['#FIREBASE_USER']; // get current firebase user data
    var myUid = cUser.uid;
    var vid;
    if (inv == "") {
      // new user
//      _result = 6;
      try {
        var userData = await getNewVid(myUid, cUser.displayName,
            cUser.email); // get new vid & add firestore/users
        var res = json.decode(userData.body);
        if (res['vid'] == 'Full') {
          result = 1;
        } else {
          vid = res['vid'];
          var sKey = res['sheetKey'];
//          if (state['#SHEET_API']) {
//            // Write to Lif for first time.
//            ValueRange vu = new ValueRange.fromJson({
//              "values": [
//                [cUser.displayName],
//                [cUser.email]
//              ]
//            });
//            sheetApi.spreadsheets.values.update(vu, _sKey, 'Settings!B2:B3',
//                valueInputOption: 'USER_ENTERED');
//            ValueRange profile = new ValueRange.fromJson({
//              "values": [
//                [state['#IMEI'] ?? '-'],
//                [cUser.photoUrl ?? ''],
//                [state['#LOCATION'].lat ?? 0],
//                [state['#LOCATION'].lng ?? 0]
//              ]
//            });
//            sheetApi.spreadsheets.values.update(
//                profile, _sKey, 'Settings!G1:G4',
//                valueInputOption: 'USER_ENTERED');
//          }
//          transactionStore.dispatch(
//              UpdateScreenTxAction(ScreenTransaction({'#VID': _vid})));
//          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
//            '#INTERFACE_KEY': _sKey,
//            '#VID': _vid,
//          })));
          state = transactionStore.state.screenTx;
          var sk = state['#INTERFACE_KEY'];
//          storage.write(
//              key: 'myLif',
//              value:
//                  _sKey); //   put interface key as default LIF in secure storage
          var nxPage = home; //   set default page = Home
          readSettings(sk, 1).then((_) {
            transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
                {'#REFRESH': false, '#CURRENT_ROUTE': nxPage})));
            List<Widget> newElementList = reloadPage(nxPage);
            rootThis.setState(() {
              rootThis.pageName = nxPage;
              rootThis.pageElements = newElementList;
              rootThis.wait = false;
              rootThis.touch = !rootThis.touch;
            });
          });
          await firstLogin(vid, sKey);
          result = 0;
        }
      } catch (_) {
        result = 4;
      }
    } else {
      // invited user
      try {
        var ds = await FirebaseFirestore.instance
            .collection(
                fsCollection) // search data in firebase with corresponding uid
            .where('inv', isEqualTo: inv)
            .get();
        if (ds.docs.isNotEmpty) {
          // invitation# found in firestore
          vid = ds.docs[0].id;
          var sheetKey = ds.docs[0].data()['sheetKey'];
          int now = DateTime.now().millisecondsSinceEpoch;
          if (now <= ds.docs[0].data()['inv_exp']) {
            await firstLogin(vid, sheetKey);
            result = 0;
          } else {
            result = 7; // expired
          }
        } else {
          result = 6; // invitation # not valid
        }
      } catch (_) {
        result = 4;
      }
    }

    if (result == 0) {
      // if success
      try {
        // TODO write to handle
        // TODO execute instruction2 in Lif, Hub & Account
        state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        await readSettings(sk, 1); //   read new interface key
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
          '#REFRESH': false
        }))); //   refresh flag to false because this is a refresh
        // List<Widget> newElementList =
        //     List<Widget>.empty(); //   prepare new element list
        var nxPage = home; //   set default page = Home
        List<Widget> newElementList = List<Widget>.of(linkElement[nxPage]!.map(
            (widget) =>
                widget)); //   get all page element from global linkElement map
        // newElementList.addAll(linkElement[
        //     nxPage]!); //   get all page element from global linkElement map
        routeStack.push(nxPage); //   put in routStack
        rootThis.setState(() {
          //   update state in main page to trigger a refresh
          rootThis.pageName = nxPage;
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
          rootThis.touch = !rootThis.touch;
        });
      } catch (err) {
        result = 4;
      }
    }
    return result;
  }

  Future<int> invitationLogin(String inv) async {
    /*
      output :
        0 = login successful
        1 = user full error (no more available user to be assigned for the new user
        2 = vid is wrong (no such vid in firestore)
        3 = pin is wrong (pin not match with corresponding pin in firestore vid
        4 = vertriz login fail (other error, vertriz login failure)
        5 = general login failure
     */
    var result = 4; // default 4 = Vertriz Fail

    // invited user
    var ds = await FirebaseFirestore.instance
        .collection(
            fsCollection) // search data in firebase with corresponding uid
        .where('inv', isEqualTo: inv)
        .get();
    if (ds.docs.isNotEmpty) {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now <= ds.docs[0].data()['inv_exp']) {
        transactionStore.dispatch(UpdateScreenTxAction(
            ScreenTransaction({'#VID': ds.docs[0].id}))); //   set state #VID
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
          '#INTERFACE_KEY': ds.docs[0].data()['sheetKey']
        }))); //   set state #INTERFACE_KEY
//        if (ds.documents[0]['email'] == null) {
//          Firestore.instance.collection('users').document(_inv).updateData({'email':ds.documents[0]['email']});  // put email in vid's data
//        }
        result = 0;
      } else {
        result = 7; // expired
      }
    } else {
      result = 6; // invitation # not valid
    }

    if (result == 0) {
      try {
        // TODO write to handle
        var state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        await storage.write(
            key: 'myLif',
            value: sk); //   put interface key as default LIF in secure storage
        await readSettings(sk, 1); //   read new interface key
        // constructAllPageElements(); //   construct all page element for the new user
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
          '#REFRESH': false
        }))); //   refresh flag to false because this is a refresh
        // List<Widget> newElementList =
        //     List<Widget>.empty(); //   prepare new element list
        var nxPage = home; //   set default page = Home
        // newElementList.addAll(linkElement[
        //     nxPage]!); //   get all page element from global linkElement map
        List<Widget> newElementList = List<Widget>.of(linkElement[nxPage]!.map(
            (widget) =>
                widget)); //   get all page element from global linkElement map
        routeStack.push(nxPage); //   put in routStack
        rootThis.setState(() {
          //   update state in main page to trigger a refresh
          rootThis.pageName = nxPage;
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
        });
      } catch (err) {
        result = 4;
      }
    }
    return result;
  }

//  Future<String> getUserDataFirebase(FirebaseUser cUser) async {
//    var loginOk = false;
//    var myUid = cUser.uid;
//    var state = transactionStore.state.screenTx;
//    var _result = state['#INTERFACE_KEY'];                      // get current Interface Key as current result
//    var ds = await Firestore.instance.collection('users')       // search data in firebase with corresponding uid
//        .where('uid',isEqualTo: myUid).getDocuments();
//    if (ds.documents.length > 0) {                              // if uid found in firebase docs
//      _result = ds.documents[0]['sheetKey'];                    //   get sheetKey from firebase
//      if (ds.documents[0]['email'] == null) {
//        Firestore.instance.collection('users').document(state['#VID']).updateData({'email':ds.documents[0]['email']});  // put email in vid's data
//      }
//      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
//          {'#INTERFACE_KEY': _result})));                       //   set state #INTERFACE_KEY
//      // TODO handle if more than 1 entry found in firestore
//      loginOk = true;
//    } else {                                                    // else (uid not found in firebase docs)
//      if (state['#VID']== ''){                                // if vid input is empty
//        try {
//          var userData = await getNewVid(myUid, cUser.displayName,
//              cUser.email); // get new vid & add firestore/users
//          var _res = json.decode(userData.body);
//          var _vid = _res['vid'];
//          _result = _res['sheetKey'];
//          if (state['#SHEET_API']) {
//            ValueRange vu = new ValueRange.fromJson({
//              "values": [[cUser.displayName], [cUser.email]]
//            });
//            sheetApi.spreadsheets.values
//                .update(vu, _result, 'Settings!B2:B3',
//                valueInputOption: 'USER_ENTERED');
//          }
//          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
//              {'#VID': _vid})));
//          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
//              {'#INTERFACE_KEY': _result})));
//          loginOk = true;
//        } catch (_) {
//          _result = '0';
//        }
//      } else {                                                   // if user fill vid
//        var existingUser = await Firestore.instance.collection('users').document(state['#VID']).get();
//        var pname = cUser.displayName;
//        var pemail = cUser.email;
//        if (existingUser.exists && existingUser.data['pin'] == state['#PIN'] ) {
//          if(!existingUser.data.containsKey('email')) {
//            Firestore.instance.collection('users').document(state['#VID'])
//                .updateData({'uid':myUid,'email':cUser.email});  // put uid & email in vid's data
//          } else {
//            Firestore.instance.collection('users').document(state['#VID'])
//                .updateData({'uid':myUid});                      // put uid in vid's data
//          }
//          _result = existingUser.data['sheetKey'];
//          if (state['#SHEET_API']) {
//            ValueRange vu = new ValueRange.fromJson({
//              "values": [[cUser.email]]
//            });
//            sheetApi.spreadsheets.values
//                .update(vu, _result, 'Settings!B3',
//                valueInputOption: 'USER_ENTERED');
//          }
//          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
//              {'#INTERFACE_KEY': _result})));
//          loginOk = true;
//        } else {
//          var vidMessage;
//          var vidTitle;
//          if(existingUser.exists) {
//            BlocProvider.of<LoginBloc>(context).dispatch(WrongVid());
//            vidTitle = 'Pin not match';
//            vidMessage = 'Pin salah, masukan sekali lagi.';
//          } else {
//            BlocProvider.of<LoginBloc>(context).dispatch(WrongPin());
//            vidTitle = 'User not found';
//            vidMessage = 'Vid tidak ditemukan.';
//          }
//          devPrint ('$vidTitle => $vidMessage');
//        }
//      }
//
//    }
//    if (loginOk) {
//      await storage.write(key: 'myLif', value: _result);        //   put interface key as default LIF in secure storage
//      await readSettings(_result);                              //   read new interface key
//      constructPage(home);                                    //   construct home
//      constructAllNotHomePages();                               //   construct other pages async
//    }
//    return _result;
//  }

//  Future<int> vertrizLogin() async {
//    /*
//      output :
//        0 = logini successfull
//        1 = user full error (no more available user to be assigned for the new user
//        2 = vid is wrong (no such vid in firestore)
//        3 = pin is wrong (pin not match with corresponding pin in firestore vid
//        4 = vertriz login fail (other error, vertriz login failure)
//     */
////    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
////        {'#VID': _vVid})));                       //   set state #INTERFACE_KEY
////    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
////        {'#PIN': _vPin})));                       //   set state #INTERFACE_KEY
//    var state = transactionStore.state.screenTx;
//    var cUser = state['#FIREBASE_USER']; // get current firebase user data
//    var myUid = cUser.uid;
//    var _result = 4; // default 4 = Vertriz Fail
//    var ds = await Firestore.instance
//        .collection('users') // search data in firebase with corresponding uid
//        .where('uid', isEqualTo: myUid)
//        .getDocuments();
//    if (ds.documents.length > 0) {
//      // if uid found in firebase docs
//      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
//        '#INTERFACE_KEY': ds.documents[0]['sheetKey']
//      }))); //   set state #INTERFACE_KEY
//      _result = 0; //   set output to successfull
//      if (ds.documents[0]['email'] == null) {
//        Firestore.instance.collection('users').document(_vVid).updateData(
//            {'email': ds.documents[0]['email']}); // put email in vid's data
//      }
//      // TODO handle if more than 1 entry found in firestore
//    } else {
//      // else (uid not found in firebase docs)
//      if (_vVid == '') {
//        // if vid input is empty
//        try {
//          var userData = await getNewVid(myUid, cUser.displayName,
//              cUser.email); // get new vid & add firestore/users
//          var _res = json.decode(userData.body);
//          if (_res['vid'] == 'Full') {
//            _result = 1;
//          } else {
//            var _vid = _res['vid'];
//            var _sKey = _res['sheetKey'];
//            if (state['#SHEET_API']) {
//              ValueRange vu = new ValueRange.fromJson({
//                "values": [
//                  [cUser.displayName],
//                  [cUser.email]
//                ]
//              });
//              sheetApi.spreadsheets.values.update(vu, _sKey, 'Settings!B2:B3',
//                  valueInputOption: 'USER_ENTERED');
//            }
//            transactionStore.dispatch(
//                UpdateScreenTxAction(ScreenTransaction({'#VID': _vid})));
//            transactionStore.dispatch(UpdateScreenTxAction(
//                ScreenTransaction({'#INTERFACE_KEY': _sKey})));
//            _result = 0;
//          }
//        } catch (_) {
//          _result = 4;
//        }
//      } else {
//        // if user fill vid
//        var existingUser =
//        await Firestore.instance.collection('users').document(_vVid).get();
//        var pname = cUser.displayName;
//        var pemail = cUser.email;
//        if (existingUser.exists && existingUser.data['pin'] == _vPin) {
//          if (!existingUser.data.containsKey('email')) {
//            Firestore.instance.collection('users').document(_vVid).updateData({
//              'uid': myUid,
//              'email': cUser.email
//            }); // put uid & email in vid's data
//          } else {
//            Firestore.instance
//                .collection('users')
//                .document(_vVid)
//                .updateData({'uid': myUid}); // put uid in vid's data
//          }
//          var sheetKey = existingUser.data['sheetKey'];
//          if (state['#SHEET_API']) {
//            ValueRange vu = new ValueRange.fromJson({
//              "values": [
//                [cUser.email]
//              ]
//            });
//            sheetApi.spreadsheets.values.update(vu, sheetKey, 'Settings!B3',
//                valueInputOption: 'USER_ENTERED');
//          }
//          transactionStore.dispatch(UpdateScreenTxAction(
//              ScreenTransaction({'#INTERFACE_KEY': sheetKey})));
//          _result = 0;
//        } else {
//          if (existingUser.exists) {
//            _result = 3; // pin not match
//          } else {
//            _result = 2; // no such vid
//          }
//        }
//      }
//    }
//    if (_result == 0) {
//      try {
//        state = transactionStore.state.screenTx;
//        var sk = state['#INTERFACE_KEY'];
//        await storage.write(
//            key: 'myLif',
//            value: sk); //   put interface key as default LIF in secure storage
//        await readSettings(sk); //   read new interface key
//        constructPage(home); //   construct home
//        constructAllNotHomePages(); //   construct other pages async
//      } catch (err) {
//        _result = 4;
//      }
//    }
//    return _result;
//  }
}

Future getFirebaseUser() async {
  FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  User? user;
  try {
    user = firebaseAuth.currentUser;
  } catch (_) {
    user = null;
  }
  return user;
}

Future firebaseSignOut() async {
  return FirebaseAuth.instance.signOut();
}
