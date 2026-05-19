import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../api.dart';
import '../login/bloc_login/bloc.dart';
import '../redux/screen_transaction.dart';
import '../login/bloc_authentication/bloc.dart';
import '../bloc_timer/bloc.dart';
import '../page/wait_screen.dart';
import '../page/login_wait_screen.dart';
import '../main_bloc/bloc.dart';
import '../notification/bloc.dart';
import '../widget/link_widget.dart';
import '../model/connection_data.dart';
import '../different_code/different_code.dart';
import '../otq_icons.dart';
import '../widget/build_theme.dart';
import '../widget/otq_bottom_nav_bar.dart';
import 'package:get/get.dart';

class MainPage extends StatefulWidget {
  const MainPage({required Key key}) : super(key: key);
  /*
    This is main page that always facing user.
    Page routing is done by updating pageElements list to current page in linkPage
 */

  @override
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  String pageName = home;
  // List<Widget> pageElements = linkElement[
  //     home]!; // page elements to display. Got this from Link Interface load home for start
  List<Widget> pageElements =
  List<Widget>.of(linkElement[home]!.map((widget) => widget));
  bool wait = false; // if true, display wait screen (circular or other)
  ScrollController scrollController = ScrollController();
  bool touch = false;
  late LoginBloc _loginBloc;
  // late MainBloc _mainBloc;
  bool toggle = true;
  late Color dataColor;
  int debugNum = 0;
  int lastNum = 0;
  dynamic notificationList;
  int byPass =
  0; // 0 = no by pass, 1 = NotificationList, 2 = NotificationDetail
  late Widget byPassWidget;
  int _selectedNavIndex = 0;
  // final Connectivity _connectivity = Connectivity();
  // late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  String gpsTime = separator[0];
  final bool _canPop = true; // Initial state

  @override
  void initState() {
    super.initState();
    _loginBloc = BlocProvider.of<LoginBloc>(context);
    // _mainBloc = BlocProvider.of<MainBloc>(context);
    //** transactionStore
    //     .dispatch(UpdateScreenTxAction(ScreenTransaction({'#DATA_OK': false})));
    // dataColor = transactionStore.state.screenTx['#DATA_OK']
    //     ? readyColor
    //     : notReadyColor;
    dataColor = notReadyColor;
    rootThis = this;
    // initConnectivity();
    asyncAppStartup2();
    // _connectivitySubscription =
    //     _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    // positionStream
    //     .listen((Position position) {
    //   setState(() {
    //     gpsTime = position.latitude.toString() +
    //         separator[0] +
    //         position.longitude.toString() +
    //         separator[0] +
    //         position.timestamp!.millisecondsSinceEpoch.toString();
    //   });
    // });
    // devPrint('Location stream listened and displayed.');
    subscribeToProxy(transactionStore
        .state.screenTx['#INTERFACE_KEY']); // subscribe to firebase proxy
  } // end of initState

  // Platform messages are asynchronous, so we initialize in an async method.
  // Future<void> initConnectivity() async {
  //   late ConnectivityResult result;
  //   // Platform messages may fail, so we use a try/catch PlatformException.
  //   try {
  //     result = await _connectivity.checkConnectivity();
  //   } on PlatformException catch (e) {
  //     errorReport(e);
  //   }
  //
  //   // If the widget was removed from the tree while the asynchronous platform
  //   // message was in flight, we want to discard the reply rather than calling
  //   // setState to update our non-existent appearance.
  //   if (!mounted) {
  //     return Future.value(null);
  //   }
  //
  //   return _updateConnectionStatus(result);
  // }

  // Future<void> _updateConnectionStatus(ConnectivityResult result) async {
  // dynamic dColor = readyColor;
  // dynamic state = transactionStore.state.screenTx;
  // debugPrint ('>>>>> Connectivity change, result: ${result.toString()}');
  // ConnectionData con = await ConnectionData().getConnection(false, true);
  // getLocation();
  // switch (result) {
  //   case ConnectivityResult.wifi:
  //     if (con.internet) {
  //       dColor = transactionOK() ? readyColor : notReadyColor;
  //     } else {
  //       //dColor = notReadyColor;
  //     }
  //     break;
  //
  //   case ConnectivityResult.mobile:
  //     if (con.internet) {
  //       dColor = transactionOK() ? readyColor : notReadyColor;
  //     } else {
  //       //dColor = notReadyColor;
  //     }
  //     break;
  //
  //   case ConnectivityResult.none:
  //     //dColor = notReadyColor;
  //     dColor = transactionOK() ? readyColor : notReadyColor;
  //     break;
  //
  //   default:
  //     //dColor = notReadyColor;
  //     dColor = transactionOK() ? readyColor : notReadyColor;
  //     break;
  //
  //   // case ConnectivityResult.none:
  //   //   dColor = notReadyColor;
  //   //   break;
  //   //
  //   // default:
  //   //   dColor = notReadyColor;
  //   //   break;
  // }
  // dColor = transactionOK() ? readyColor : notReadyColor;
  // setState(() {
  //   dataColor = dColor;
  // });
  // }

  @override
  Widget build(BuildContext context) {
    double lPad = (systemUIComponent['Mobile']['leftPad'] ?? 0.0).toDouble();
    double tPad = (systemUIComponent['Mobile']['topPad'] ?? 0.0).toDouble();
    double rPad = (systemUIComponent['Mobile']['rightPad'] ?? 0.0).toDouble();
    double bPad = (systemUIComponent['Mobile']['bottomPad'] ?? 0.0).toDouble();
    String title = emptyString;
    try {
      title = screenUIComponent == null
          ? emptyString
          : screenUIComponent[pageName]['title'] ?? emptyString;
    } catch (e) {
      // do nothing
    }
    if (title.substring(0, 1) == '_') title = '';
    try {
      scrollController.jumpTo(0.0);
    } catch (e) {
      errorReport(e);
    }

    void handleNavTap(int i) {
      if (i == 0) {
        bool changePage = true;
        if (byPass != 0) {
          changePage = false;
        }
        var pgName = systemUIComponent[mobile]['bottomBar'][0]['route'];
        if (pgName != pageName) {
          var state = transactionStore.state.screenTx;
          if (state['#REFRESH']) {
            oldSettingUpShouldBeDeleted().then((aRes) {
              var state = transactionStore.state;
              var lifKey = state.screenTx['#INTERFACE_KEY'];
              readSettings(lifKey, 1).then((_) {
                transactionStore.dispatch(UpdateScreenTxAction(
                    ScreenTransaction(
                        {'#REFRESH': false, '#CURRENT_ROUTE': pgName})));
                List<Widget> newElementList = reloadPage(pgName);
                setState(() {
                  _selectedNavIndex = i;
                  byPass = 0;
                  pageName = pgName;
                  pageElements = newElementList;
                });
              });
            });
          } else {
            List<Widget> newElementList = reloadPage(pgName);
            setState(() {
              _selectedNavIndex = i;
              pageName = pgName;
              pageElements = newElementList;
              byPass = 0;
            });
          }
          if (changePage) {
            routeStack.push(pgName);
          }
        }
        setState(() {
          _selectedNavIndex = i;
          byPass = 0;
        });
      } else if (needUpgrade == empty) {
        if (i == 1) {
          setState(() {
            _selectedNavIndex = i;
            byPassWidget = const NotificationList();
            byPass = 1;
          });
        } else {
          var pgName = systemUIComponent[mobile]['bottomBar'][i]['route'];
          if (pgName != pageName) {
            var state = transactionStore.state.screenTx;
            if (state['#REFRESH']) {
              oldSettingUpShouldBeDeleted().then((aRes) {
                var state = transactionStore.state;
                var lifKey = state.screenTx['#INTERFACE_KEY'];
                readSettings(lifKey, 1).then((_) {
                  transactionStore.dispatch(UpdateScreenTxAction(
                      ScreenTransaction({
                        '#REFRESH': false,
                        '#CURRENT_ROUTE': pgName
                      })));
                  List<Widget> newElementList = reloadPage(pgName);
                  setState(() {
                    _selectedNavIndex = i;
                    pageName = pgName;
                    pageElements = newElementList;
                    byPass = 0;
                  });
                });
              });
            } else {
              List<Widget> newElementList = reloadPage(pgName);
              setState(() {
                _selectedNavIndex = i;
                pageName = pgName;
                pageElements = newElementList;
              });
            }
            routeStack.push(pgName);
          }
          setState(() {
            _selectedNavIndex = i;
          });
        }
      }
    }

    void onWillPop(canPop) async {
      if (canPop) {
        if (pageName != home || byPass != 0) {
          switch (byPass) {
            case 1: // in Notification List before
              {
                var pgName = routeStack.get(); // get current page
                List<Widget> newElementList =
                reloadPage(pgName); // reload current page
                setState(() {
                  byPass = 0;
                  pageName = pgName;
                  pageElements = newElementList;
                  touch = !touch;
                });
              }
              break;

            case 2: // in Notification Detail before
              {
                setState(() {
                  byPass = 1;
                  byPassWidget = const NotificationList();
                });
              }
              break;

            default:
              {
                var dotColor = dataColor;
                if (routeStack.get() == '_OtqQR1') {
                  dotColor = readyColor;
                  setDataOK('2');
                }
                var pgName = routeStack.pop();
                List<Widget> newElementList = reloadPage(pgName);
                setState(() {
                  pageName = pgName;
                  pageElements = newElementList;
                  dataColor = dotColor;
                });
              }
          }
        } else {
          // retVal = true;
          // retVal = await showDialog(
          //     context: context,
          //     builder: (context) =>
          //         AlertDialog(title: Text(textList["ExitConfirmation"]), actions: <Widget>[
          //           TextButton(
          //               child: Text(textList["Exit"]),
          //               onPressed: () => Navigator.of(context).pop(true)),
          //           TextButton(
          //               child: Text(textList["Cancel"]),
          //               onPressed: () => Navigator.of(context).pop(false)),
          //         ]));
        }
      } // end if _canPop
      // return retVal;
    } // end of onWillPop

    return StoreConnector<ScreenTransaction, ScreenTransaction>(
        converter: (transactionStore) => transactionStore.state,
        builder: (context, list) {
          PopScope v;

          v = PopScope(
            canPop: _canPop,
            onPopInvoked: (canPop) => onWillPop(canPop),
            child: byPass > 0
                ? byPassWidget
                : Scaffold(
//                  endDrawer: ReduxDevTools<ScreenTransaction>(transactionStore),
//                  key: key,
              key: mainScaffoldKey,
//            floatingActionButton: FloatingActionButton(
//              onPressed: () {
//                if (this.toggle) {
//                  this.toggle = !this.toggle;
//                  BlocProvider.of<MainBloc>(context)
//                      .add(ContinuousScan());
//                } else {
//                  this.toggle = !this.toggle;
//                  BlocProvider.of<MainBloc>(context)
//                      .add(ResetAll());
//                }
//
//              },
//              tooltip: 'Scan',
//              child: Icon(Icons.add),
//            ),
//            floatingActionButton: FloatingActionButton(
//              onPressed: () {
//                var state = transactionStore.state.screenTx;
//                resetVidUid(state['#FIREBASE_USER'].uid);
//              },
//              tooltip: 'Reset',
//              child: Icon(Icons.cancel),
//            ), // This trailing comma makes auto-formatting nicer for build methods.
              appBar: AppBar(
                backgroundColor: Theme.of(context).primaryColor,
                leading: pageName == home
                    ? null
                    : IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                  ), //= back icon
                  onPressed: () {
                    // BlocProvider.of<MainBloc>(context)
                    //     .add(ResetAll());
                    var dotColor = dataColor;
                    if (routeStack.get() == '_OtqQR1') {
                      dotColor = readyColor;
                      setDataOK('2');
                    }
                    var pgName = routeStack.pop();
                    List<Widget> newElementList =
                    reloadPage(pgName);
                    setState(() {
                      byPass = 0;
                      wait = false;
                      pageName = pgName;
                      pageElements = newElementList;
                      dataColor = dotColor;
                    });
                  },
                ),
                title: pageName == home
                    ? Text(
                  '$title $versionShown',
                  style: const TextStyle(color: Colors.white),
                )
                    : Text(
                  title,
                  style: const TextStyle(color: Colors.white),
                ),
                actions: <Widget>[
                  // IconButton( // archive history for debugging
                  //     onPressed: (() async {
                  //       archiveHistory(); // // archive history to firestore proxy h2
                  //       Get.defaultDialog(
                  //         title: "History",
                  //         content: const Text("History archived."),
                  //       );
                  //     }),
                  //     icon: const Icon(
                  //       Icons.send,
                  //       color: Colors.redAccent,
                  //     )),
                  // IconButton( // sync history for debugging
                  //     onPressed: (() async {
                  //       historySync('Connection Data',true);
                  //       Get.defaultDialog(
                  //         title: "History",
                  //         content: const Text("History synced."),
                  //       );
                  //       // historyClear();
                  //     }),
                  //     icon: const Icon(
                  //       Icons.history_toggle_off,
                  //       color: Colors.redAccent,
                  //     )),
                  // IconButton( // archive history for debugging
                  //     onPressed: (() async {
                  //       historyClear(); // clear history
                  //       Get.defaultDialog(
                  //         title: "History",
                  //         content: const Text("History cleared."),
                  //       );
                  //     }),
                  //     icon: const Icon(
                  //       Icons.phonelink_erase,
                  //       color: Colors.redAccent,
                  //     )),
                  // IconButton(
                  //   icon: const Icon(
                  //     Icons.info_outline,
                  //     color: Colors.white,
                  //   ), //= refresh icon
                  //   onPressed: () async {
                  //     // need to run  flutter pub run flutter_oss_licenses:generate.dart
                  //     showLicensePage(context: context);
                  //   }, // end of onPressed
                  // ),
                  Obx(() => Icon(
                    Icons.fiber_manual_record,
                    color: transactionOKFlag.value
                        ? readyColor
                        : notReadyColor,
                  )),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                    ), //= refresh icon
                    onPressed: () async {
                      if (!(transactionStore.state.screenTx['#CAMERA'] ??
                          false)) {
                        await ConnectionData().getConnection(true, true);
                        if (internetConnected()) {
                          setTransactionNotOK('refresh icon');
                          transactionStore.dispatch(UpdateScreenTxAction(
                              ScreenTransaction({'#DATA_OK': false})));
                          // transactionStore.dispatch(UpdateScreenTxAction(
                          //     ScreenTransaction({'#DATA_OK': true})));
                          setState(() {
                            wait = true;
                            touch = !touch;
                            scrollController.jumpTo(0.0);
                            dataColor = notReadyColor;
                            // dataColor = readyColor;
                          });
                          // refresh current page
                          try {
                            oldSettingUpShouldBeDeleted().then((aRes) {
                              var state = transactionStore.state;
                              var lifKey =
                              state.screenTx['#INTERFACE_KEY'];
                              // readSettings(lifKey, 1).then((_) {
                              readSettingsContext(context, lifKey, 1)
                                  .then((_) {
                                transactionStore.dispatch(
                                    UpdateScreenTxAction(
                                        ScreenTransaction(
                                            {'#REFRESH': false})));
                                List<Widget> newElementList =
                                reloadPage(pageName);
                                setTransactionOK('refresh icon');
                                transactionStore.dispatch(
                                    UpdateScreenTxAction(
                                        ScreenTransaction(
                                            {'#DATA_OK': true})));
                                setState(() {
                                  pageElements = newElementList;
                                  wait = false;
                                  touch = !touch;
                                  dataColor = readyColor;
                                  // dataColor = Colors.lightGreenAccent;
                                });
                              });
                            });
                          } catch (e) {
                            setTransactionOK('refresh icon catch');
                            transactionStore.dispatch(
                                UpdateScreenTxAction(ScreenTransaction(
                                    {'#DATA_OK': true})));
                            setState(() {
                              wait = false;
                              touch = !touch;
                              dataColor = readyColor;
                              // dataColor = Colors.lightGreenAccent;
                            });
                            showAlert(context, textList["ErrorLoading"]);
                          }
                        } else {
                          await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  // display dialog that data is not ready
                                  title:
                                  Text(textList["NoInternetTitle"]),
                                  content: Container(
                                    alignment: const Alignment(0.0, 0.0),
                                    height: 100,
                                    child: Text(textList["NoInternet"]),
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
                        } // end if transactionOK
                      } // end if #CAMERA
                    }, // end of onPressed
                  ),
                ],
              ),
              bottomNavigationBar:
              BlocBuilder<AuthenticationBloc, AuthenticationState>(
                builder: (context, authState) {
                  if (authState is Unauthenticated) {
                    return const SizedBox.shrink();
                  }
                  if (screenUIComponent[pageName]?['hideBottomBar'] ==
                      true) {
                    return const SizedBox.shrink();
                  }
                  return BlocBuilder<NotificationBloc, NotificationState>(
                    builder: (context, notifState) {
                      int unread = 0;
                      if (notifState is NotificationLoaded) {
                        unread = notifState.unReadNumber;
                        if (unread > lastNum) {
                          lastNum = unread;
                        }
                        lastNum = unread;
                      }
                      final barItems =
                      systemUIComponent[mobile]['bottomBar'] as List;
                      final navItems =
                      List<OtqNavItem>.generate(barItems.length, (i) {
                        final iconKey = barItems[i]['icon'].toString();
                        final route =
                            barItems[i]['route']?.toString() ?? '';
                        final label = barItems[i]['label']?.toString() ??
                            route.replaceAll('_', ' ');
                        return OtqNavItem(
                          icon:
                          otqIcons[iconKey] ?? Icons.circle_outlined,
                          label: label,
                          badgeCount: i == 1 ? unread : null,
                        );
                      });
                      return OtqBottomNavBar(
                        selectedIndex: _selectedNavIndex,
                        items: navItems,
                        onTap: handleNavTap,
                      );
                    },
                  );
                },
              ),
              body: byPass == 1
                  ? const NotificationList()
                  : Stack(
                children: <Widget>[
                  // Text(gpsTime),
                  // Text(displayRefresher.toString()),
                  BlocBuilder<AuthenticationBloc,
                      AuthenticationState>(
                    builder: (context, authState) {
                      if (authState is Unauthenticated) {
                        return Container(
                          padding: EdgeInsets.fromLTRB(
                              lPad, tPad, rPad, bPad),
                          child: Center(
                            child: SingleChildScrollView(
                              controller: scrollController,
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: pageElements,
                              ),
                            ),
                          ),
                        );
                      }
                      return Container(
                        padding: EdgeInsets.fromLTRB(
                            lPad, tPad, rPad, bPad),
                        child: Builder(
                          builder: (context) => ListView.builder(
                            controller: scrollController,
                            itemCount: pageElements.length,
                            itemBuilder: (context, position) {
                              return pageElements[position];
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  //------ Login bloc listener---------
                  BlocListener(
                    bloc: _loginBloc,
                    listener: (BuildContext contextLogin,
                        LoginState loginState) {
                      if (loginState.isFailure) {
                        if (loginState.loginStatus == 2) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text(
                                    "Other user logged in"),
                                content: const Text(
                                    "Ada pemakai lain yang sedang memakai invitasi ini. Silahkan pergunakan nomor invitasi lain"), // show dialog
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      setState(() {
                                        wait = false;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        } else if (loginState.loginStatus == 3) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text(
                                    "Invitation Code Not Match"),
                                content: const Text(
                                    "Kode Undangan tidak ada."),
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      BlocProvider.of<LoginBloc>(
                                          context)
                                          .add(
                                        const TosOKTabbed(
                                            tosOk: true),
                                      );
                                      setState(() {
                                        wait = false;
                                        touch = !touch;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        } else if (loginState.loginStatus == 7) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text(
                                    "Invitation Code has been used before"),
                                content: const Text(
                                    "Kode undangan telah dipakai oleh pengguna lain. Silahkan hubungi bagian administrasi."),
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      setState(() {
                                        wait = false;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        } else if (loginState.loginStatus == 1) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text("Full !"),
                                content: const Text(
                                    "Wah!, banyak sekali yang mendaftar. Sementara ini tidak dapat menambah pemakai baru. Kami sedang terus menambah kapasitas, silahkan coba beberapa jam lagi"), // show dialog
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      setState(() {
                                        wait = false;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        } else if (loginState.loginStatus == 4) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text("Sign in error"),
                                content: const Text(
                                    "Terjadi kesalahan pada saat sign in, silahkan coba beberapa jam lagi"), // show dialog
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      setState(() {
                                        wait = false;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        } else if (loginState.loginStatus == 5) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text("Sign in error"),
                                content: const Text(
                                    "Terjadi kesalahan pada saat autorisasi akun Google, silahkan coba lagi"),
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      setState(() {
                                        wait = false;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        } else {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text("Login failed"),
                                content: const Text(
                                    "Login anda gagal. Kemungkinan karena koneksi internet anda terganggu. Silahkan coba beberapa saat lagi"), // show dialog
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text("OK"),
                                    onPressed: () {
                                      setState(() {
                                        wait = false;
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  )
                                ],
                              );
                            },
                          );
                        }
                      } else if (loginState.isSuccess) {
                        BlocProvider.of<AuthenticationBloc>(context)
                            .add(LoggedIn());
                        BlocProvider.of<NotificationBloc>(context)
                            .add(LoadNotification());
                        // } else if (loginState.inLoginProcess) {
                        //   return LoginWaitScreen();
                      } // end if loginState.isFailure
                    },
                    child: BlocBuilder<TimerBloc, TimerState>(
                      buildWhen: (previousState, currentState) =>
                      currentState.runtimeType !=
                          previousState.runtimeType,
                      builder: (context, state) {
                        Widget ret;
                        if (state is Finished) {
                          wait = false;
                        }
                        if ((state is Running &&
                            state.duration > 0)) {
                          // || this.wait) {
                          ret = const WaitScreen();
                        } else {
                          if (state is Finished) {
                            oldSettingUpShouldBeDeleted()
                                .then((aRes) {
                              var state =
                                  transactionStore.state.screenTx;
                              var lifKey = state['#INTERFACE_KEY'];
                              readSettings(lifKey, 1).then((_) {
                                var nxPage = state['#NEXTROUTE'];
                                routeStack.push(nxPage); //?
                                transactionStore.add(
                                    UpdateScreenTxAction(
                                        ScreenTransaction(
                                            {'#REFRESH': false})));
                                List<Widget> newElementList =
                                reloadPage(nxPage);
                                setState(() {
                                  pageName = nxPage;
                                  pageElements = newElementList;
                                  wait = false;
                                });

                                transactionStore.dispatch(
                                    UpdateScreenTxAction(
                                        ScreenTransaction({
                                          '#CURRENT_ROUTE': nxPage
                                        }))); // set state #CURRENT_ROUTE
                                try {
                                  scrollController.jumpTo(0.0);
                                } catch (e) {
                                  errorReport(e);
                                }
                                state['#TIMER_BLOC'].dispatch(
                                    Reset()); // reset timer state to Ready
                              });
                            });
                          }
                          ret = const SizedBox(
                            width: 0.0,
                            height: 0.0,
                          );
                        }
                        return ret;
                      },
                    ),
                  ),

                  //======== MainBloc Listener & Builder ===========
                  BlocListener<MainBloc, MainState>(
                    listener: (context, mState) {
                      switch (mState.mainState) {
                        case -1: // wrong pin
                          {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(mState.str1),
                                  content: Text(
                                      mState.str2), // show dialog
                                  actions: <Widget>[
                                    TextButton(
                                      child: const Text("OK"),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    )
                                  ],
                                );
                              },
                            );
                          }
                          break;
                      }
                    },
                    child: BlocBuilder<MainBloc, MainState>(
                      builder: (context, mState) {
                        Widget displayScreen;
                        switch (mState.mainState) {
                          case 900: // need pin hash
                            {
//                                        displayScreen = Container(
//                                          height: 200,
//                                          width: 200,
//                                          color: Colors.green,
//                                        );
                              var np = linkElement['_NewPin'];
                              var len = np!.length;
                              displayScreen = Container(
                                color: Colors.white,
                                child: ListView.builder(
                                  controller: scrollController,
                                  itemCount: len,
                                  itemBuilder: (context, position) {
                                    return linkElement['_NewPin']![
                                    position];
                                  },
                                ),
                              );
                            }
                            break;

                          default:
                            {
                              displayScreen = const SizedBox(
                                width: 0.0,
                                height: 0.0,
                              ); // default
                            }
                        }
                        return displayScreen;
                      },
                    ),
                  ),
                  // WaitScreen(),
                  BlocBuilder<LoginBloc, LoginState>(
                    // buildWhen: (previousState, currentState) =>
                    //     currentState.inLoginProcess !=
                    //     previousState.inLoginProcess,
                    builder: (context, state) {
                      // if (state.inLoginProcess) {
                      // }
                      Widget retVal = state.inLoginProcess
                          ? const LoginWaitScreen()
                          : Container();
                      return retVal;
                    },
                  ),
                ],
              ), // Stack closure=========
            ),
          );
          return v;
        } // end of builder,
    );
  } // end of build

  Future subscribeToProxy(String? ssid) async {
    /*
    Listen to firestore /Proxy/<vid> collection
    This function is called from lib/main.dart
    Will delete old ssid proxy subscriber to current ssid
    store ssid to #PROXY_LISTENER_SSID in screenTx
    store listener to #PROXY_LISTENER in screenTx
    store checksum to #PROXY_LISTENER_CS in screenTx

    Structure:
    /Proxy/<vid>
      Event: (collection) not handled by this function
      Page: (collection)
        docId: sha3
          c: String, Encoded JSON of page's content
          p: String, page name
          t: integer, epoch time of last update, used as page checksum
          v: integer, vid of the page
      System
      e: String,email
      n: String,name
      p: integer, phone
      t: integer, epoch timestamp (global checksum)
      ty: String, type if user (not used)
      v: integer, vid
      z: numeric, UTC offset
      l: language/country code in ISO 639-1/3166-1 alpha-2 format (id_ID , en_US)
      f: String, final date,time,timezone format for this user in format
         {"+7":"UTC+7 format", "+8":"UTC+8 format, "default:"default format"}

    algorithm:
      if (page.t != old page.t) {
        if (e != old email) {
          update email
        }
        if (n != old name) {
          update name
        }
        if (p != old phone) {
          update phone
        }
        test every doc in System collection
          if (doc.t != old doc.t) {
            update systemUiComponent;
          }
        if system updated {
          buildTheme(systemUiComponent([theme]));
        }
        test every page in Page collection
          if (page.t != old page.t) {
            update screenUiComponent;
            update linkElement
          }
        if current date updated {
          refresh current page
        }
      }
  */
    dynamic state = transactionStore.state.screenTx;
    if (ssid != null) {
      if (ssid == state['#PROXY_LISTENER_SSID']) {
        // same ssid, do nothing
        devPrint("Proxy/${state['#PROXY_LISTENER_SSID']} already subscribed");
        return;
      } else {
        dynamic docRef = firestoreDb.collection(proxyCollectionName).doc(ssid);
        bool docExist = (await docRef.get()).exists;
        if (docExist) {
          final proxyListener = docRef.snapshots().listen((event) {
            if (event.data() != null) {
              // process event data
              dynamic rec = event.data();
              // actionLock();

              if (rec['t'] !=
                  transactionStore.state.screenTx['#PROXY_LISTENER_CS']) {
                // proxy change detected
                // update profile
                asHomeArray =
                    jsonDecode(rec['u'] ?? '[]'); // set singleton asHomeArray
                devPrint("Proxy change detected in : Proxy/$ssid");
                transactionStore
                    .dispatch(UpdateScreenTxAction(ScreenTransaction({
                  '#NAME': rec['n'],
                  '#EMAIL': rec['e'],
                  '#PHONE': rec['p'],
                  '#PROXY_LISTENER_CS': rec['t'],
                })));
                // check and update system
                // actionUnLock();
                Map<String, dynamic> newItem = {};
                dynamic collectionRef = FirebaseFirestore.instance
                    .collection('$proxyCollectionName/$ssid/System');
                collectionRef.get().then((value) {
                  systemUIComponent = {};
                  for (final doc in value.docs) {
                    dynamic systemData = doc.data();
                    newItem[systemData['p']] = {
                      'c': systemData['c'],
                      't': systemData['t'],
                      'v': systemData['v'],
                    };
                    systemUIComponent[systemData['p']] =
                        json.decode(systemData['c']);
                  } // end for (final doc in value.docs)
                  storage.write(
                      key: 'ui_systems',
                      value: jsonEncode(
                          newItem)); // store systems in secure storage
                  buildTheme(systemUIComponent[theme]);
                }); // end of system then

                // check and update pages
                newItem = {};
                collectionRef = FirebaseFirestore.instance
                    .collection('$proxyCollectionName/$ssid/Page');
                collectionRef.get().then((value) {
                  screenUIComponent = {};
                  for (final doc in value.docs) {
                    dynamic pageData = doc.data();
                    newItem[pageData['p']] = {
                      'c': pageData['c'],
                      't': pageData['t'],
                      'v': pageData['v'],
                    };
                    try {
                      screenUIComponent[pageData['p']] =
                          json.decode(pageData['c']);
                      // devPrint("Page ${pageData['p']} => updated");
                    } catch (e) {
                      // devPrint("Error in page ${pageData['p']} => $e");
                      screenUIComponent[pageData['p']] = json.decode(errorPage);
                    }
                  } // end for (final doc in value.docs)
                  storage.write(
                      key: 'ui_pages',
                      value:
                      jsonEncode(newItem)); // store pages in secure storage
                  devPrint("Proxy listener call constructAllPageElements");
                  constructAllPageElements();
                  if (ssid == state['#SIGNUP_KEY']) {
                    screenUIComponent[home] =
                    screenUIComponent[defaultGuestHome];
                    pageName = defaultGuestHome;
                  }
                  rePaintScreen('Page Listener, all pages');
                  // actionUnLock();
                  // setDataOK('4'); // reload and set green light
                }); // end of then
              } // end if (rec['t'] != state['#PROXY_LISTENER_CS'])
              // actionUnLock();
            } // end if (event.data() == null)
          }); // end of listener
          // devPrint("Subscribed to  : Proxy/$ssid");
          transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
            '#PROXY_LISTENER': proxyListener,
            '#PROXY_LISTENER_SSID': ssid,
          })));
        } // end if (docExist)
      } // end if (ssid == state['#PROXY_LISTENER_SSID'])
    } else {
      // no ssid and unsubscribe from current proxy
      if (state['#PROXY_LISTENER'] != null) {
        dynamic tableListener =
        transactionStore.state.screenTx['#PROXY_LISTENER'];
        tableListener?.cancel();
        tableListener = null;
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
            {'#PROXY_LISTENER': null, '#PROXY_LISTENER_SSID': null})));
        // devPrint("Unsubscribe from Proxy/${state['#PROXY_LISTENER_SSID']}");
      } // end if ((state['#PROXY_LISTENER_SSID']??'') != '')
    }
  } // end of subscribeToProxy

  void rePaintScreen(String source) {
    if (pageName == home || asHomeArray.contains(pageName)) {
      List<Widget> newElementList = reloadPage(pageName);
      setState(() {
        pageElements = newElementList;
        wait = false;
        touch = !touch;
        dataColor = readyColor;
        // dataColor = Colors.lightGreenAccent;
      });
      displayRefresher.value = !displayRefresher.value;
      // devPrint(
      //    'Repaint $pageName from $source = ${displayRefresher.value.toString()}');
    }
  }
} // end of class
