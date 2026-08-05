import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../api.dart';
import '../../firestore_repository/firestore_generic_repository.dart';
import '../../firestore_repository/proxy_repository.dart';
import '../../firestore_repository/table_repository.dart';
import '../../ftz_secret.dart';
import '../../global.dart';
import '../../redux/screen_transaction.dart';
// idea from https://medium.flutterdevs.com/google-sign-in-with-flutter-8960580dec96

class UserRepository {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  String? verificationId;

  /// Enable [LOGINPERF] timing logs for the login critical path.
  /// Set to false (or remove) after root-cause confirmation.
  static bool loginPerfTrace = true;

  UserRepository({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignin})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignin ?? GoogleSignIn.instance;

  /// Fetch the freshly-authenticated user's LIF pages. Returns FALSE when the
  /// fetch failed, and every login path MUST skip its page swap on false.
  ///
  /// Why this exists: readSettings swallows TimeoutException internally and
  /// returns normally, so a timed-out fetch is indistinguishable from a good
  /// one at the call site. At login the in-memory screenUIComponent is still
  /// the GUEST LIF, so an ungated swap rebuilds the sign-in form and installs
  /// it as home — nav bar on, body stuck on the login screen.
  ///
  /// Fetch the signed-in user's pages, twice on a generous budget.
  ///
  /// A long wait is acceptable here BECAUSE the shell now shows an explicit
  /// "loading your pages" state while this runs (`rootThis.pagesFetching`)
  /// instead of leaving the sign-in form on screen. Correctness of the
  /// transition was chosen over speed.
  ///
  /// ★ The 60s budget is LOAD-BEARING, not padding. Measured 2026-07-27 on the
  /// heaviest tenant (`1hdcFg4…`, 71-tab workbook) across two successful
  /// logins: this fetch took **32.8s and 37.1s**, both succeeding on the first
  /// attempt, while the sign-in LIF took 4.5s. Earlier budgets of 8s and 20s
  /// both timed out — and 20s-with-retry was the worst of all, burning 40s on
  /// two attempts each capped below the ~35s the call actually needs. Anyone
  /// lowering this below ~45s reintroduces the "logged in but stuck on the
  /// sign-in page" bug.
  ///
  /// On failure it flips the shell to its retry state rather than letting the
  /// caller paint a home that was never loaded.
  Future<bool> _loginPagesReady(String sk) async {
    // The fetch spans tens of seconds, so the shell can be disposed mid-flight
    // (app killed, route torn down). setState on a dead State throws.
    void shellState(void Function() mutate) {
      if (rootThis == null || rootThis.mounted != true) return;
      rootThis.setState(mutate);
    }

    shellState(() {
      rootThis.pagesFetching = true;
      rootThis.pagesFetchFailed = false;
    });
    // ★ Firestore FIRST, Sheets only as fallback. `/Proxy/<lif>/{System,Page}`
    // holds the same page definitions the Sheets fetch returns, and reads in
    // ~0.2-0.5s against 66-90s for the 181 KB readSS payload (measured
    // 2026-08-03; one of three runs returned a 24-byte junk body). The proxy
    // listener in main_page.dart already applies these documents in production
    // — this just reads them once, at the moment login actually needs them.
    bool ok = await loadPagesFromProxy(sk);
    if (!ok) {
      devPrint('proxy pages unavailable — falling back to readSettings');
      ok = await readSettings(sk, 1, timeoutSec: 60);
      if (!ok) {
        devPrint('readSettings login attempt 1 failed, retrying');
        ok = await readSettings(sk, 1, timeoutSec: 60);
      }
    }
    // Leave pageName/#CURRENT_ROUTE alone on failure: claiming `home` while the
    // sign-in pages are still loaded makes the AppBar title and rePaintScreen
    // lie about which page is actually up.
    if (!ok) devPrint('readSettings login FAILED twice — pages not swapped');
    shellState(() {
      rootThis.pagesFetching = false;
      rootThis.pagesFetchFailed = !ok;
      rootThis.wait = false;
      rootThis.touch = !rootThis.touch;
    });
    return ok;
  }
  // GoogleSignIn();
  // signInOption: SignInOption.standard,
  // scopes: [
  //                'https://www.googleapis.com/auth/drive',
  //                'https://www.googleapis.com/auth/drive.appdata',
  //                'https://www.googleapis.com/auth/spreadsheets',
  //               ],
  //             );

  Future<User?> signInWithGoogle() async {
    try {
      // 1. Interactive sign-in. authenticate() runs the OpenID sign-in and
      //    yields the ID token Firebase needs; basic email/profile claims come
      //    with it.
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // 2. Read the ID token (`.authentication` is sync). We deliberately do
      //    NOT call authorizationClient.authorizeScopes() here: on iOS that
      //    opens a SECOND ASWebAuthenticationSession — the duplicate "wants to
      //    use google.com to Sign In" consent popup seen after picking the
      //    account — purely to mint an OAuth access token. Firebase sign-in only
      //    needs the ID token; authorization (access token / extra scopes) is
      //    only required to call Google APIs such as Drive/Sheets, which this
      //    flow does not. Re-add authorizeScopes(<scopes>) only if/when those
      //    Google-API scopes are actually needed.
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      if (idToken == null) {
        throw StateError('Missing Google ID token after authentication.');
      }

      // 3. Exchange for a Firebase credential and sign in.
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );
      final UserCredential userAuth = await _firebaseAuth.signInWithCredential(
        credential,
      );
      final User? user = userAuth.user;
      if (user == null) {
        throw StateError(
          'Firebase returned no user for the Google credential.',
        );
      }
      devPrint('${user.displayName} => ${user.uid}');

      final User currentUser = _firebaseAuth.currentUser ?? user;
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            '#FIREBASE_USER': currentUser,
            '#AUTH_METHOD': 'Google',
          }),
        ),
      ); // Set currentUser as FIREBASE_USER
      return currentUser;
    } on Object catch (e) {
      // User dismissed the picker / scope grant -> null (bloc emits
      // `cancelled`, silent). Any genuine failure rethrows -> error dialog.
      if (isSocialSignInCancellation(e)) {
        return null;
      }
      rethrow;
    }
  } // end of signInWithGoogle

  Future<User?> signInWithApple() async {
    // 1. Request the Apple ID credential. A user cancel returns null (-> bloc
    //    emits `cancelled`, silent); any other failure rethrows (-> error
    //    dialog). Mirrors signInWithGoogle.
    final AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        // nonce: 'YOUR_NONCE', // (Optional) nonce for additional security
      );
    } on Object catch (eApple) {
      if (isSocialSignInCancellation(eApple)) {
        return null;
      }
      rethrow;
    }

    // 2. Create an `OAuthCredential` from the credential returned by Apple.
    final OAuthCredential oauthCredential = OAuthProvider("apple.com")
        .credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode,
        );

    // 3. Sign in to Firebase. A genuine failure propagates -> error dialog.
    final UserCredential userAuth = await _firebaseAuth.signInWithCredential(
      oauthCredential,
    );
    final User? user = userAuth.user;
    if (user == null) {
      throw StateError('Firebase returned no user for the Apple credential.');
    }
    devPrint('${user.displayName} => ${user.uid}');

    final User currentUser = _firebaseAuth.currentUser ?? user;
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#FIREBASE_USER': currentUser,
          '#AUTH_METHOD': 'Apple ID',
        }),
      ),
    ); // Set currentUser as FIREBASE_USER
    return currentUser;
  } // end of signInWithApple

  Future<User> signInWithFacebook(String facebookAcc) async {
    final AuthCredential credential = FacebookAuthProvider.credential(
      facebookAcc,
    );
    final UserCredential userAuth = await _firebaseAuth.signInWithCredential(
      credential,
    );
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
      accessToken: twitterAcc,
      secret: twitterPass,
    );

    final UserCredential userAuth = await _firebaseAuth.signInWithCredential(
      credential,
    );
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

  bool isSocialSignInCancellation(Object error) {
    if (error is GoogleSignInException) {
      return error.code == GoogleSignInExceptionCode.canceled;
    }
    if (error is SignInWithAppleAuthorizationException) {
      return error.code == AuthorizationErrorCode.canceled;
    }
    return false;
  }

  /// Sends the code to the specified phone number.
  Future<void> sendCodeToPhoneNumber(String phone) async {
    verificationCompleted(AuthCredential user) {
      //      setState(() {
      //        devPrint('Inside _sendCodeToPhoneNumber: signInWithPhoneNumber auto succeeded: $user');
      //      });
      devPrint(
        'Inside _sendCodeToPhoneNumber: signInWithPhoneNumber auto succeeded: $user',
      );
    }

    verificationFailed(FirebaseAuthException authException) {
      //      setState(() {
      //        devPrint('Phone number verification failed. Code: ${authException.code}. Message: ${authException.message}');}
      //      );
      devPrint(
        'Phone number verification failed. Code: ${authException.code}. Message: ${authException.message}',
      );
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
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  Future<User> signInWithPhone(String smsCode) async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    //    await sendCodeToPhoneNumber(phone);
    final AuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId!,
      smsCode: smsCode,
    );
    final UserCredential currentUserAuth = await auth.signInWithCredential(
      credential,
    );
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

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    return await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<List<void>> systemSignOut() async {
    return Future.wait([_firebaseAuth.signOut(), _googleSignIn.signOut()]);
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

    final swTotal = loginPerfTrace ? (Stopwatch()..start()) : null;
    try {
      bool loginOK = false;
      final sw1 = loginPerfTrace ? (Stopwatch()..start()) : null;
      ds = await getFirestoreUserData(
        myUid,
        myEmail,
        country,
        inv,
      ); //= get user data. If uid not defined, will try search email, if fail get new vid
      if (sw1 != null) {
        debugPrint(
          '[LOGINPERF] getFirestoreUserData = ${sw1.elapsedMilliseconds}ms',
        );
      }
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
        final sw2 = loginPerfTrace ? (Stopwatch()..start()) : null;
        var messageRef = await getFirestoreMessageRef(myVid);
        if (sw2 != null) {
          debugPrint(
            '[LOGINPERF] getFirestoreMessageRef = ${sw2.elapsedMilliseconds}ms',
          );
        }
        firestoreIO =
            messageRef.path +
            "/io"; //= set firestoreIO singleton from global.dart
        eventDoc = '$firestoreEventCollection/$sk0';
        transactionStore.dispatch(
          UpdateScreenTxAction(
            ScreenTransaction({
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
            }),
          ),
        ); //   set state #INTERFACE_KEY
        // await prefs.remove('@pages');
        // F2: Do NOT clear @systemUI/@screenUI before the fetch. readSettings
        // overwrites them on success (api.dart:2160-2167). On failure, the
        // prior cache survives for warm-reopen (readSettingsStart, api.dart:1794
        // reads @screenUI -- if empty, forces a blocking network fetch).
        // Logout still clears both keys (api.dart:2622-2623, 2744-2745).
        subscribeToEvent(sk0); // subscribe to user's proxy event
        final sw3 = loginPerfTrace ? (Stopwatch()..start()) : null;
        await runSheetStartup(sk0, userData["clt"]);
        if (sw3 != null) {
          debugPrint(
            '[LOGINPERF] runSheetStartup = ${sw3.elapsedMilliseconds}ms',
          );
        }
        state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        var ak = state['#ACC_KEY'];
        storage.write(
          key: 'myAcc',
          value: ak,
        ); //   put Account key in secure storage
        storage.write(
          key: 'myCluster',
          value: cl,
        ); //   put cluster id in secure storage
        storage.write(
          key: 'myLif',
          value: sk,
        ); //   put interface key as default LIF in secure storage
        storage.write(
          key: 'myPath',
          value: myPath,
        ); //= firebase full path collection /dvc
        storage.write(key: 'myDoc', value: myDoc); //= documentId from /dvc
        storage.write(key: 'myMsgId', value: messageRef.id);
        storage.write(
          key: 'sd1',
          value: ftzSecretOneSeed,
        ); //   put Account key in secure storage
        var nxPage = home; //   set default page = Home
        loadHistory(clearHistory, 'aumLogin (user_repository) <= async');
        final sw4 = loginPerfTrace ? (Stopwatch()..start()) : null;
        result = await reLogin();
        if (sw4 != null) {
          debugPrint('[LOGINPERF] reLogin = ${sw4.elapsedMilliseconds}ms');
        }
        // ★ The page fetch runs AFTER reLogin, NOT concurrently with it, and it
        // must stay that way. It was originally a detached `settingsReady`
        // future launched beside reLogin; when reLogin threw, control jumped to
        // the outer catch and that orphan future kept running, landing minutes
        // later to setState home over a login that had already failed and
        // signed out — home painted with no #VID, "Login fail" dialog on top.
        // Awaiting it inline makes that state unreachable.
        //
        // reLogin no longer performs any Sheets I/O (see the note there), so
        // sequencing costs essentially nothing now.
        //
        // The loader persists the @screenUI/@systemUI cache when it completes —
        // login must not report success until that cache is written, otherwise
        // a kill right after login leaves an empty cache and the next warm
        // reopen is forced onto the slow network page-fetch path.
        final sw5 = loginPerfTrace ? (Stopwatch()..start()) : null;
        try {
          if (await _loginPagesReady(sk)) {
            transactionStore.dispatch(
              UpdateScreenTxAction(
                ScreenTransaction({
                  '#REFRESH': false,
                  '#CURRENT_ROUTE': nxPage,
                }),
              ),
            );
            List<Widget> newElementList = reloadPage(nxPage);
            rootThis.setState(() {
              rootThis.pageName = nxPage;
              rootThis.pageElements = newElementList;
              rootThis.wait = false;
              rootThis.touch = !rootThis.touch;
            });
          } // else pages not swapped; _loginPagesReady set the retry state
        } catch (e) {
          // A page-fetch failure shouldn't fail the login (warm reopen falls
          // back to the now-timed-out network path); just log it.
          devPrint('readSettings during login failed: $e');
        }
        if (sw5 != null) {
          debugPrint(
            '[LOGINPERF] settingsReady = ${sw5.elapsedMilliseconds}ms',
          );
        }
        subscribeToUserReset(getDevicePath(ds));
      } else {
        result = ds;
        // 1;
      }
    } catch (err) {
      // Everything that goes wrong in this method funnels here and becomes the
      // generic "koneksi internet terganggu" dialog (loginStatus 99 -> the else
      // branch in main_page). Without this line a TimeoutException, a Firestore
      // error and a genuine `result = ds` type error are indistinguishable in
      // the field. Log it, then keep the existing behaviour.
      devPrint('[LOGINPERF] aumLogin failed: $err');
      result = 2;
    }
    if (swTotal != null) {
      debugPrint(
        '[LOGINPERF] aumLogin.total = ${swTotal.elapsedMilliseconds}ms',
      );
    }
    return result;
  } // end of vertrizLogin

  Future<int> reLogin() async {
    // justReLogin procedure
    // after logged out then re login
    // Set vid in transactionStore
    // save sheetKey to persistence.storage
    //X save FirebaseUser to persistence.storage 'myFirebaseData'
    // save uid, imei, in to firebase
    final sw = loginPerfTrace ? (Stopwatch()..start()) : null;

    final sw1 = loginPerfTrace ? (Stopwatch()..start()) : null;
    await getMyImei(); // put imei in #IMEI
    if (sw1 != null) {
      debugPrint('[LOGINPERF] getMyImei = ${sw1.elapsedMilliseconds}ms');
    }

    var state = transactionStore.state.screenTx;

    // ★★ THE SHEET IS OFF THE LOGIN CRITICAL PATH.
    //
    // #VID used to come from getLifProfileData() — a readSS call on the tenant
    // workbook measured at 4-79s, and the ONLY call on this path that THROWS,
    // so its latency turned straight into "Login anda gagal. Kemungkinan
    // karena koneksi internet anda terganggu".
    //
    // It was also redundant. Of the four keys it dispatched, #PINHASH /
    // #CIPHERTEXT / #PUBLICKEY have ZERO readers anywhere in lib/ (and the
    // Settings!G range feeding them is empty on the live sheet — measured).
    // The fourth, #VID, is set again moments later by whichever page loader
    // runs next: readSettings dispatches it from settingCell(Settings!B1) and
    // loadPagesFromProxy from the proxy doc's `v`. Those run LAST, so their
    // value always won regardless.
    //
    // aumLogin already holds the same vid for free, from the Firestore user
    // doc it read seconds ago (dispatched as #ADDRESS). String, to match
    // settingCell()'s `row[0].toString()` — the setter every successful login
    // has always ended on. Set here rather than later because launchCheck()
    // below is fire-and-forget and reads #VID via getVidData().
    final String fsVid = '${state['#ADDRESS'] ?? ''}';
    if (fsVid.isEmpty) {
      // Should not happen: aumLogin sets #ADDRESS from userData['vid'] before
      // calling reLogin. Log rather than dispatch an empty vid over a good one.
      devPrint('[LOGINPERF] #ADDRESS empty — #VID left unset by reLogin');
    } else {
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'#VID': fsVid})),
      );
    }
    storage.write(key: 'myLif', value: state['#INTERFACE_KEY']);
    //  storage.write(key: 'myFirebaseData', value: jsonEncode(state['#FIREBASE_USER']));
    //    await setUidImeiEmail(sheetData['vid'].toString()); // To Firestore

    // F4: Defer launchCheck to run AFTER LoginState.success() fires.
    // launchCheck sets up FCM, reads pinHash from Sheets, updates Firestore
    // device doc, writes QR seeds -- none of which blocks home rendering.
    // On failure, log but do not strand the user; the same work runs on next
    // warm-reopen (main.dart already calls launchCheck via readSettingsStart).
    unawaited(
      launchCheck()
          .then((launchOk) {
            if (launchOk > 0) {
              debugPrint('[LOGINPERF] deferred launchCheck returned $launchOk');
            }
          })
          .catchError((e) {
            debugPrint('[LOGINPERF] deferred launchCheck error: $e');
          }),
    );

    if (sw != null) {
      debugPrint('[LOGINPERF] reLogin.total = ${sw.elapsedMilliseconds}ms');
    }
    return 0; // login ok; launchCheck runs in background
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
            fsCollection,
          ) // search data in firebase with corresponding inv
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
        // write to handle
        // execute instruction2 in Lif, Hub & Account
        state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        // Gated on a real fetch — see _loginPagesReady. Ungated, a timed-out
        // readSettings leaves the GUEST LIF in memory and the block below
        // installs the sign-in page as home.
        if (await _loginPagesReady(sk)) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})),
          ); //   refresh flag to false because this is a refresh
          var nxPage = home; //   set default page = Home
          List<Widget> newElementList = List<Widget>.of(
            linkElement[nxPage]!.map((widget) => widget),
          ); //   get all page element from global linkElement map
          routeStack.push(nxPage); //   put in routStack
          rootThis.setState(() {
            //   update state in main page to trigger a refresh
            rootThis.pageName = nxPage;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
            rootThis.touch = !rootThis.touch;
          });
        }
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
        var userData = await getNewVid(
          myUid,
          cUser.displayName,
          cUser.email,
        ); // get new vid & add firestore/users
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
          _loginPagesReady(sk).then((ok) {
            if (!ok) return; // pages not swapped — stale guest LIF in memory
            transactionStore.dispatch(
              UpdateScreenTxAction(
                ScreenTransaction({
                  '#REFRESH': false,
                  '#CURRENT_ROUTE': nxPage,
                }),
              ),
            );
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
              fsCollection,
            ) // search data in firebase with corresponding uid
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
        // write to handle
        // execute instruction2 in Lif, Hub & Account
        state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        // Gated on a real fetch — see _loginPagesReady. Ungated, a timed-out
        // readSettings leaves the GUEST LIF in memory and the block below
        // installs the sign-in page as home.
        if (await _loginPagesReady(sk)) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})),
          ); //   refresh flag to false because this is a refresh
          var nxPage = home; //   set default page = Home
          List<Widget> newElementList = List<Widget>.of(
            linkElement[nxPage]!.map((widget) => widget),
          ); //   get all page element from global linkElement map
          routeStack.push(nxPage); //   put in routStack
          rootThis.setState(() {
            //   update state in main page to trigger a refresh
            rootThis.pageName = nxPage;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
            rootThis.touch = !rootThis.touch;
          });
        }
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
          fsCollection,
        ) // search data in firebase with corresponding uid
        .where('inv', isEqualTo: inv)
        .get();
    if (ds.docs.isNotEmpty) {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now <= ds.docs[0].data()['inv_exp']) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#VID': ds.docs[0].id})),
        ); //   set state #VID
        transactionStore.dispatch(
          UpdateScreenTxAction(
            ScreenTransaction({
              '#INTERFACE_KEY': ds.docs[0].data()['sheetKey'],
            }),
          ),
        ); //   set state #INTERFACE_KEY
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
        // write to handle
        var state = transactionStore.state.screenTx;
        var sk = state['#INTERFACE_KEY'];
        await storage.write(
          key: 'myLif',
          value: sk,
        ); //   put interface key as default LIF in secure storage
        // Gated on a real fetch — see _loginPagesReady. Ungated, a timed-out
        // readSettings leaves the GUEST LIF in memory and the block below
        // installs the sign-in page as home.
        if (await _loginPagesReady(sk)) {
          transactionStore.dispatch(
            UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})),
          ); //   refresh flag to false because this is a refresh
          var nxPage = home; //   set default page = Home
          List<Widget> newElementList = List<Widget>.of(
            linkElement[nxPage]!.map((widget) => widget),
          ); //   get all page element from global linkElement map
          routeStack.push(nxPage); //   put in routStack
          rootThis.setState(() {
            //   update state in main page to trigger a refresh
            rootThis.pageName = nxPage;
            rootThis.pageElements = newElementList;
            rootThis.wait = false;
          });
        }
      } catch (err) {
        result = 4;
      }
    }
    return result;
  }
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
