/*
Please put trash VV down there

Future getDeviceIdCore() async {
  var deviceId = '-';
  DeviceInfoPlugin deviceInfo;

  if (transactionStore.state.screenTx['#DID'] != null) {
    deviceId = transactionStore.state.screenTx['#DID'];
  } else {
    try {
      deviceInfo = DeviceInfoPlugin();
      if (andrew) {
        try {
          // TODO need to change to https://pub.dev/packages/android_id
          AndroidDeviceInfo deviceData = await deviceInfo.androidInfo;
          deviceId = deviceData.id ?? emptyString;
        } catch (e) {
          errorReport(e);
        }
      } else if (sinner) {
        IosDeviceInfo deviceData = await deviceInfo.iosInfo;
        deviceId = deviceData.identifierForVendor ?? emptyString;
      }
    } on PlatformException {
      deviceId = '--';
    }
    transactionStore.dispatch(UpdateScreenTxAction(
        ScreenTransaction({'#DID': deviceId}))); //  set #device id
  } // end if (transactionStore.state.screenTx['#DID'] != null)
  return deviceId;
} // end of getDeviceId

Future<Position?> getLocation() async {
  // from api.dart
  // get gps location, until #LASTGPSTIME <> current readings>
  Position? pos;
  int tempGpsTime;
  try {
    devPrint('=====getLocation()');
    int beginTest = DateTime.timestamp().millisecondsSinceEpoch;
    bool gpsEnabled = await Geolocator.isLocationServiceEnabled();
    int elapsed = DateTime.timestamp().millisecondsSinceEpoch - beginTest;
    devPrint('=====Elapsed2 1:$elapsed');
    dynamic gpsPermission = await Geolocator.checkPermission();
    elapsed = DateTime.timestamp().millisecondsSinceEpoch - beginTest;
    devPrint('=====Elapsed2 2:$elapsed');
    if (gpsPermission == LocationPermission.denied ||
        gpsPermission == LocationPermission.deniedForever) {
      gpsPermission = await Geolocator.requestPermission();
    }
    if (gpsEnabled &
        ((gpsPermission == LocationPermission.always) |
            (gpsPermission == LocationPermission.whileInUse))) {
      // int lastGpsTime = state["#LASTGPSTIME"];
      int lastGpsTime = gpsTime.value;
      int delay = 500;
      if (lastGpsTime == 0) {
        late Position pos2;
        try {
          pos2 = await Geolocator.getCurrentPosition();
          lastGpsTime = pos2.timestamp.millisecondsSinceEpoch;
        } catch (errP) {
          dynamic p = errP;
        }
        transactionStore.dispatch(UpdateScreenTxAction(
            ScreenTransaction({'#LASTGPSTIME': lastGpsTime})));
        await prefs.setInt('@lastGpsTime', lastGpsTime);
        gpsData = pos2;
        gpsTime.value = lastGpsTime;
        await Future.delayed(Duration(milliseconds: delay));
      }
      pos = await Geolocator.getCurrentPosition();
      tempGpsTime = pos.timestamp.millisecondsSinceEpoch;
      int loopCount = 0;
      const loopMax = 10;
      while (loopCount < loopMax && lastGpsTime == tempGpsTime) {
        await Future.delayed(Duration(milliseconds: min(700, delay)));
        pos = await Geolocator.getCurrentPosition();
        tempGpsTime = pos.timestamp.millisecondsSinceEpoch;
        delay += 50;
        loopCount++;
      }
      transactionStore.dispatch(UpdateScreenTxAction(
          ScreenTransaction({'#LASTGPSTIME': tempGpsTime})));

      // await prefs.setInt('@lastGpsTime', tempGpsTime);
    }
  } catch (e) {
    // setDataOK('2');
    // // reload pages and display green anyway. So the app will not lock up
    // pos = null;
    // errorReport(e);
    try {
      pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        tempGpsTime = pos.timestamp.millisecondsSinceEpoch;
        transactionStore.dispatch(UpdateScreenTxAction(
            ScreenTransaction({'#LASTGPSTIME': tempGpsTime})));
        // await prefs.setInt('@lastGpsTime', tempGpsTime);
      } else {
        throw ('Geolocator.getLastKnownPosition() returns null.');
      }
    } catch (e2) {
      setDataOK('2');
      // reload pages and display green anyway. So the app will not lock up
      pos = null;
      errorReport(e2);
    }
  }
  if (pos != null && ((pos.timestamp.millisecondsSinceEpoch) ?? 0) != 0) {
    int tempTime = pos.timestamp.millisecondsSinceEpoch;
    if (tempTime != gpsTime.value) {
      gpsData = positionCopy(pos);
      try {
        List<Placemark> temp =
            await placemarkFromCoordinates(gpsData.latitude, gpsData.longitude);
        gpsPlaceMark = placeMarkCopy(temp[0]);
      } catch (e) {
        gpsPlaceMark = placeMarkCopy(null);
      }
      gpsTime.value = (gpsData.timestamp.millisecondsSinceEpoch) ?? 0;
      await storage.write(key: 'gpsData', value: json.encode(gpsData));
      await storage.write(
          key: 'gpsPlaceMark', value: json.encode(gpsPlaceMark));
      await prefs.setInt('@lastGpsTime', gpsTime.value);
      debugPrint('gpsLocation updated from getLocation()');
    } // end if tempTime != gpsTime.value
  } // if (pos != null && ((pos?.timestamp?.millisecondsSinceEpoch) ?? 0) != 0)
  return pos;
} // end of getLocation


Future<int> old_vertrizLogin() async {
  /* not used anymore
      output :
        0 = login successful
        1 = No previous login
        2 = fail
     */
  var state = transactionStore.state.screenTx;
  var cUser = state['#FIREBASE_USER']; // get current firebase user data
  var myUid = cUser.uid;
  var myVid;
  var myAddress;
  var _result = 2; // default 1 = No previous login
  String _sk;
  String _hk;
  String _ak;

  try {
    var ds;
    var _myUid;
    bool uidFound = false;
    ds = await Firestore.instance
        .collection(
        topCollection) // search data in firebase with corresponding uid
        .where('uid', isEqualTo: myUid)
        .getDocuments(source: Source.server);
    if (ds.documents.length > 0) {
      myAddress = ds.documents[0].documentID.toString(); // get first record
      final DocumentReference vidRef =
      Firestore.instance.collection(fsCollection).document(myAddress);
      await Firestore.instance.runTransaction((Transaction tx) async {
        DocumentSnapshot vidSnapshot = await tx.get(vidRef);
        myVid = vidSnapshot.data['vid'];
        _myUid = vidSnapshot.data['uid'];
        _sk = vidSnapshot.data['sheetKey'];
        _hk = vidSnapshot.data['hubKey'];
        _ak = vidSnapshot.data['accKey'];
        devPrint('snaphot uid = $_myUid , sk = $_sk');
        if (vidSnapshot.data['uid'] == myUid) {
          var updateData = {
            "in": true,
          };
          tx.update(vidRef, updateData);
          uidFound = true;
        } else {
          uidFound = false;
        }
      }); // end of firebase transaction
    } else {
      uidFound = false;
    }
    devPrint('uidFound = $uidFound');
//      var ds = await Firestore.instance
//          .collection('users') // search data in firebase with corresponding uid
//          .where('uid', isEqualTo: myUid)
//      .getDocuments(source: Source.server);
//          .getDocuments();
//      if (ds.documents.length > 0) {
    if (uidFound) {
      // if uid found in firebase docs
//        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
//          '#INTERFACE_KEY': ds.documents[0]['sheetKey'],
//          '#ACC_KEY': ds.documents[0]['accKey'],
//          '#HUB_KEY': ds.documents[0]['hubKey'],
//        }))); //   set state #INTERFACE_KEY
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#INTERFACE_KEY': _sk,
        '#ACC_KEY': _ak,
        '#HUB_KEY': _hk,
        '#ADDRESS': myAddress,
      }))); //   set state #INTERFACE_KEY
      _result = 0; //   set output to login successful
      // TODO handle if more than 1 entry found in firestore
      state = transactionStore.state.screenTx;
      var sk = state['#INTERFACE_KEY'];
      var hk = state['#HUB_KEY'];
      var ak = state['#ACC_KEY'];
      storage.write(
          key: 'myAcc', value: ak); //   put Account key in secure storage
      storage.write(key: 'myHub', value: hk); //   put Hub key in secure storage
      storage.write(
          key: 'myLif',
          value: sk); //   put interface key as default LIF in secure storage

      var nxPage = home; //   set default page = Home
      readSettings(sk).then((_) {
        constructAllPageElements();
        transactionStore.dispatch(UpdateScreenTxAction(
            ScreenTransaction({'#REFRESH': false, '#CURRENT_ROUTE': nxPage})));
        List<Widget> newElementList = reloadPage(nxPage);
        rootThis.setState(() {
          rootThis.pageName = nxPage;
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
          rootThis.touch = !rootThis.touch;
        });
      });
    } else {
      _result =
      1; // TODO do not return 1 (user not found) change with user getter function

    }
  } catch (err) {
    _result = 2;
  }
  return _result;
} // end of old_vertrizlogin

Future<String> checkerDataProcess(
        List checkies, String originalScrName, List<dynamic> tArray) async {
      String resultOk = empty;
      String finalQrText = empty;
      String mock = 'Unknown';
      int nowTime = 0;
      String message = tArray[4];
      dynamic state = transactionStore.state.screenTx;
      if (checkies.length == 1) {
        int i = 0;
        String checkieVid = '';
        String checkerVid = '';
        try {
          //nowTime = getNowMillisecondFromEpoch();
          checkerVid = state['#VID'].toString().trim();
          checkieVid = checkies[i][0].toString().trim();
          selfieUrl = checkies[i][1];
          nowTime = checkies[i][2];
          if (position != null) {
            mock = position!.isMocked ? 'Mocked location' : 'True location';
            // if (!state['#DATA_OK']) {
            //   // wait until green light
            //   sleep(const Duration(milliseconds: 500));
            // } // end if (!state['#DATA_OK'])
            actionLock();
            // pool.play(scannerBeep);
            String content = widget.component['flag'] ?? 'location';
            txfController[originalScrName]![1] = InputController(
                1, TextEditingController(text: content), content, content);
            content = nowTime.toString();
            txfController[originalScrName]![2] = InputController(
                2, TextEditingController(text: content), content, content);
            content = widget.component['category'] ?? 'checkpoint';
            txfController[originalScrName]![3] = InputController(
                3, TextEditingController(text: content), content, content);
            content = finalQrText == empty ? '' : finalQrText;
            txfController[originalScrName]![4] = InputController(
                4, TextEditingController(text: content), content, content);
            content = position!.latitude.toString();
            txfController[originalScrName]![5] = InputController(
                5, TextEditingController(text: content), content, content);
            content = position!.longitude.toString();
            txfController[originalScrName]![6] = InputController(
                6, TextEditingController(text: content), content, content);
            content = selfieUrl ?? '';
            txfController[originalScrName]![7] = InputController(
                7, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty
                ? placeMark[0].isoCountryCode!
                : invalidCountry;
            txfController[originalScrName]![8] = InputController(
                8, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty ? placeMark[0].postalCode! : "";
            txfController[originalScrName]![9] = InputController(
                9, TextEditingController(text: content), content, content);
            content =
                placeMark.isNotEmpty ? placeMark[0].administrativeArea! : "";
            txfController[originalScrName]![10] = InputController(
                10, TextEditingController(text: content), content, content);
            content =
                placeMark.isNotEmpty ? placeMark[0].subAdministrativeArea! : "";
            txfController[originalScrName]![11] = InputController(
                11, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty ? placeMark[0].locality! : "";
            txfController[originalScrName]![12] = InputController(
                12, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty ? placeMark[0].subLocality! : "";
            txfController[originalScrName]![13] = InputController(
                13, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty ? placeMark[0].thoroughfare! : "";
            txfController[originalScrName]![14] = InputController(
                14, TextEditingController(text: content), content, content);
            content = placeMark.isNotEmpty ? placeMark[0].subThoroughfare! : "";
            txfController[originalScrName]![15] = InputController(
                15, TextEditingController(text: content), content, content);
            content = mock;
            txfController[originalScrName]![15] = InputController(
                16, TextEditingController(text: content), content, content);

            widget.component['route'] =
                widget.component['route'] ?? home; //= default route = Home
            widget.component['checker'] = checkerVid;
            widget.component['checkie'] = checkieVid;
            checkerSaveData(originalScrName); //= send record to FromLink
            // routeStack.pop();
            // await checkerSuccessDialog(
            //   title: tArray[10],
            //   message: tArray[4],
            //   okString: tArray[7],
            // );
          } else {
            setDataOK(
                '1'); // reload pages and display green anyway. So the app will not lock up
            //checkerDialog(message: tArray[5], okString: tArray[7]);
            await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    // dialog 3
                    title: Text(tArray[11] ?? 'Fail'),
                    content: Container(
                      alignment: const Alignment(0.0, 0.0),
                      height: dialogHeight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("Gagal, tidak dapat membaca lokasi GPS."),
                        ],
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        child: Text(tArray[7] ?? "Ok"),
                        onPressed: () {
                          routeStack.pop();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                });
            resultOk = errorString;
          } // end if position
        } catch (e) {
          // TODO display dialog fail, and play wrong beep
          errorReport(e);
          setDataOK(
              '1'); // reload pages and display green anyway. So the app will not lock up

          await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  // dialog 3
                  title: Text(textList["Fail"]), // Scan lagi
                  // title: const Text("Error test1"), // Scan lagi
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(textList["Retry"]),
                      Text("System: (${e.toString()})"),
                      const Text("Position: otq_qr1(1)"),
                      Text(textList["ScreenShot"]),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              });
          resultOk = errorString;
        }
        if ((nowTime - (lastPositionTime ?? 0)) > 600000) {
          // more than 10 minutes
          getLocation().then((res) {
            position = res;
            lastPositionTime = nowTime;
            placemarkFromCoordinates(position!.latitude, position!.longitude)
                .then((pm) {
              placeMark = pm;
            }); // end of placemarkFromCoordinates
          }); // end of getLocation
        } // end if  > 600000

      } else {
        // multiple checkies data
        setDataOK('1'); // delete this for production
      }
      return resultOk;
    } // end of qrDataProcess



 please put  trash ^^ up there
*/
