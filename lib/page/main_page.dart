import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:get/get.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';

import '../api.dart';
import '../bloc_timer/bloc.dart';
import '../different_code/different_code.dart';
import '../global.dart';
import '../login/bloc_authentication/bloc.dart';
import '../login/bloc_login/bloc.dart';
import '../main_bloc/bloc.dart';
import '../model/connection_data.dart';
import '../notification/bloc.dart';
import '../otq_icons.dart';
import '../page/wait_screen.dart';
import '../redux/screen_transaction.dart';
import '../widget/approver_sticky_bar.dart';
import '../widget/build_theme.dart';
import '../widget/link_widget.dart';
import '../widget/logout_transition_support.dart';
import '../widget/offline_banner.dart';
import '../widget/otq_bottom_nav_bar.dart';

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
  // NOT `linkElement[home]!`. linkElement is only ever filled, never cleared,
  // so a null here means constructPageElements(home) has not succeeded ONCE in
  // this process — i.e. the startup page load failed (that fetch is 27-38s on
  // the heaviest tenant against a 15s budget, and signOut wipes @screenUI, so a
  // logout→cold-start reliably lands here). Force-unwrapping turned that into a
  // fatal while MainPageState was being constructed, before any UI existed to
  // report it. Empty is the honest value: userPagesLoaded() is false in that
  // state, so the shell renders its loading/retry gate instead of crashing.
  List<Widget> pageElements = List<Widget>.of(
    (linkElement[home] ?? const <Widget>[]).map((widget) => widget),
  );
  bool wait = false; // if true, display wait screen (circular or other)
  bool _refreshing =
      false; // ponytail: amber dot while background refresh in-flight (also double-tap guard)
  // Post-auth page-fetch state, driven by UserRepository._loginPagesReady via
  // rootThis. Authentication and page availability are SEPARATE facts: the bloc
  // flips to Authenticated the moment Firebase succeeds, while the user's pages
  // arrive later over the network (or not at all). Rendering `pageElements` on
  // auth alone painted the sign-in form — which still occupies the `home` slot
  // at that moment — underneath a live navbar.
  bool pagesFetching = false;
  bool pagesFetchFailed = false;
  // Scoped logout spinner flag. Set true by signOut()'s cold/corrupt-snapshot
  // path (no warm guest UI cached → it must re-fetch the login page over the
  // network) and cleared inside showSignInPage() on BOTH success and failure.
  // Gates ONLY the overlay below — deliberately NOT the broad `|| this.wait`
  // TimerBloc gate, whose `wait` field is driven live by
  // image_upload/qr_gps/invitation and is out of scope here. The warm-cache
  // restore path leaves this false (instant, spinner-free).
  static bool logoutInProgress = false;
  // Memo for the per-build authed navbar restore below. _authedRawMemo is the
  // raw @authedSystemUI prefs string last parsed; _authedBarLenMemo is the
  // authed bottomBar length from it (-1 = absent/invalid). Re-parsed only when
  // the raw string changes, so the restore's length check stays cheap every
  // build instead of a full JSON decode per frame.
  String? _authedRawMemo;
  int _authedBarLenMemo = -1;
  ScrollController scrollController = ScrollController();
  bool touch = false;
  String _lastScrolledPage = home;
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
    subscribeToProxy(
      transactionStore.state.screenTx['#INTERFACE_KEY'],
    ); // subscribe to firebase proxy
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

  /// Route of bottom-bar slot [i] in [sysUI], or `''` when that slot no longer
  /// exists.
  ///
  /// The navbar PAINTS from the bottomBar live at build time, but a tap reads
  /// that list again LATER. In between, a guest-scoped readSettings / proxy
  /// refresh can revert the global to the guest bar (home-only, 1 item) without
  /// an intervening rebuild, so the bar on screen still shows 4 icons while the
  /// list behind it holds 1. The unguarded `bottomBar[i]['route']` then threw
  /// (Crashlytics: `handleNavTap`, "RangeError ... Only valid value is 0: 3").
  static String navRouteAt(dynamic sysUI, int i) {
    try {
      final dynamic bar = sysUI?[mobile]?['bottomBar'];
      if (bar is! List || i < 0 || i >= bar.length) return '';
      final dynamic item = bar[i];
      if (item is! Map) return '';
      return (item['route'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

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
    // While the user's pages are missing, `title` is read from the sign-in page
    // still sitting in the `home` slot — the AppBar would read "Sign In" over a
    // loading screen. Blank it until the real pages are up.
    if (pagesFetching || pagesFetchFailed) title = '';
    // Scroll-to-top on page change only (not every rebuild). Deferred to a
    // post-frame callback so it runs after the new content is laid out, and
    // gated on actual page change so unrelated rebuilds (wait toggle, dataColor)
    // skip it. Reads the already-set `pageName` field, so it catches every page
    // change regardless of which setState site triggered it.
    if (pageName != _lastScrolledPage) {
      _lastScrolledPage = pageName;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0.0);
        }
      });
    }

    void handleNavTap(int i) {
      if (i == 0) {
        bool changePage = true;
        if (byPass != 0) {
          changePage = false;
        }
        final String pgName = navRouteAt(systemUIComponent, 0);
        if (pgName.isEmpty) {
          // Live bar no longer has this slot. Rebuild so the build-time
          // @authedSystemUI restore repaints the real bar; drop this tap.
          setState(() {});
          return;
        }
        if (pgName != pageName) {
          var state = transactionStore.state.screenTx;
          if (state['#REFRESH']) {
            oldSettingUpShouldBeDeleted().then((aRes) {
              var state = transactionStore.state;
              var lifKey = state.screenTx['#INTERFACE_KEY'];
              readSettings(lifKey, 1).then((_) {
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({
                      '#REFRESH': false,
                      '#CURRENT_ROUTE': pgName,
                    }),
                  ),
                );
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
          // Deliberately does NOT write _selectedNavIndex. Slot 1 is the only
          // bar item with no page of its own — it is a body swap (byPass), so
          // its highlight is DERIVED from byPass at render time. Persisting it
          // here left the bell lit after every exit that does not go through
          // handleNavTap (the inbox AppBar back / a tapped row's route, both in
          // notification_list.dart). Keeping the last real page's slot here
          // means any exit path restores the right highlight for free.
          setState(() {
            byPassWidget = const NotificationList();
            byPass = 1;
          });
        } else {
          final String pgName = navRouteAt(systemUIComponent, i);
          if (pgName.isEmpty) {
            // Tapped slot is gone from the live bar (guest-bar clobber after
            // the navbar painted the authed bar) -- rebuild, drop the tap.
            setState(() {});
            return;
          }
          if (pgName != pageName) {
            var state = transactionStore.state.screenTx;
            if (state['#REFRESH']) {
              oldSettingUpShouldBeDeleted().then((aRes) {
                var state = transactionStore.state;
                var lifKey = state.screenTx['#INTERFACE_KEY'];
                readSettings(lifKey, 1).then((_) {
                  transactionStore.dispatch(
                    UpdateScreenTxAction(
                      ScreenTransaction({
                        '#REFRESH': false,
                        '#CURRENT_ROUTE': pgName,
                      }),
                    ),
                  );
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
            // Leave the notification inbox when a different destination is
            // tapped. The navbar is now visible while byPass > 0, so this path
            // is reachable and must clear the body swap — otherwise the inbox
            // stays on screen under the new page's title.
            byPass = 0;
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
                List<Widget> newElementList = reloadPage(
                  pgName,
                ); // reload current page
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

    return StoreConnector<ScreenTransaction, int>(
      distinct: true,
      // The builder reads no Redux key at render time; every visible update
      // flows via rootThis.setState + nested Bloc/Obx/ValueListenable
      // builders. Constant converter + distinct:true => the shell renders
      // once and is NOT rebuilt on each of the ~200+ dispatches. If a future
      // edit needs a # key at render time, switch this converter to a
      // value-comparable record of exactly those keys and keep distinct:true.
      converter: (store) => 0,
      builder: (context, _) {
        PopScope v;

        v = PopScope(
          canPop: _canPop,
          onPopInvoked: (canPop) => onWillPop(canPop),
          // byPass (notification inbox) swaps only the Scaffold BODY, never the
          // whole shell. Replacing the Scaffold took its bottomNavigationBar
          // with it — that is why the navbar vanished on the notification page.
          child: Scaffold(
            //                  endDrawer: ReduxDevTools<ScreenTransaction>(transactionStore),
            //                  key: key,
            key: mainScaffoldKey,
            // The bar is a floating pill (rounded + margin + shadow), so
            // let the body run underneath it: without this the strip
            // around the pill is scaffoldBackgroundColor and the pill
            // reads as sitting ON a cream band instead of over content.
            // Scaffold pays for it by handing the body a MediaQuery
            // bottom padding equal to the bar height — every padding:null
            // ListView below consumes that on its own; the one explicit
            // padding (the SDUI list) adds it back by hand.
            extendBody: true,
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
            // byPassWidget (NotificationList) brings its own AppBar
            // ("Notification" + back arrow), so suppress the shell's one
            // instead of stacking two headers.
            appBar: byPass > 0
                ? null
                : AppBar(
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
                              List<Widget> newElementList = reloadPage(pgName);
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // Android (Roboto) renders titleLarge wider than
                            // iOS (SF); pin 18sp on Android, keep iOS default.
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: andrew ? 18 : null,
                            ),
                          )
                        : Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: andrew ? 18 : null,
                            ),
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
                      Obx(() {
                        // Read the observable BEFORE the ternary: when
                        // _refreshing is true the amber branch short-circuits
                        // and Obx would register zero observables → GetX
                        // "improper use of a GetX" throw.
                        final txOK = transactionOKFlag.value;
                        return Icon(
                          Icons.fiber_manual_record,
                          color: _refreshing
                              ? Colors.amber
                              : (txOK ? readyColor : notReadyColor),
                        );
                      }),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                        ), //= refresh icon
                        onPressed: () async {
                          if (_refreshing)
                            return; // ponytail: ignore tap while refresh in-flight
                          if (!(transactionStore.state.screenTx['#CAMERA'] ??
                              false)) {
                            // Claim the in-flight flag BEFORE the first await:
                            // a second tap during getConnection's await used to
                            // slip past the guard above and double-fire the
                            // whole refresh (two readSS pulls, two clearData).
                            setState(() {
                              _refreshing = true;
                            });
                            try {
                              await ConnectionData().getConnection(
                                false,
                                false,
                                awaitImages: false,
                              );
                            } catch (e) {
                              // Flag already claimed — a throw here would
                              // leave the button amber/locked forever.
                              if (mounted) {
                                setState(() {
                                  _refreshing = false;
                                });
                              }
                              return;
                            }
                            if (internetConnected()) {
                              // ponytail: non-blocking refresh — amber dot, page stays usable
                              setState(() {
                                touch = !touch;
                                if (scrollController.hasClients) {
                                  scrollController.jumpTo(0.0);
                                }
                              });
                              // Refresh pulls the sheet directly via
                              // readSettingsContext (fresh, small 3-range
                              // job); amber holds until the repaint lands.
                              try {
                                var lifKey = transactionStore
                                    .state
                                    .screenTx['#INTERFACE_KEY'];
                                readSettingsContext(context, lifKey, 1)
                                    // readSS is bursty (median ~19s, tail 79s)
                                    // and its socket can hang with no reply at
                                    // all — without a cap the dot sticks amber
                                    // for minutes. A post-timeout completion
                                    // (value or error) is discarded by
                                    // Future.timeout, never unhandled.
                                    .timeout(const Duration(seconds: 60))
                                    .then((_) {
                                      transactionStore.dispatch(
                                        UpdateScreenTxAction(
                                          ScreenTransaction({
                                            '#REFRESH': false,
                                          }),
                                        ),
                                      );
                                      _endRefresh(
                                        elements: reloadPage(pageName),
                                        tag: 'refresh icon',
                                      );
                                    })
                                    .catchError((e) async {
                                      // reloadPage can throw (linkElement
                                      // force-unwrap); an un-catchError'd
                                      // .then makes that a FATAL async error
                                      // (project_callhttppost_clientexception_fatal).
                                      try {
                                        if (e is TimeoutException &&
                                            lifKey is String &&
                                            lifKey.isNotEmpty) {
                                          // readSS hung — serve the
                                          // backend-pushed Firestore proxy
                                          // (the ~1s login loader) instead of
                                          // an error: same pages, at worst
                                          // one sync-cadence behind the sheet.
                                          devPrint(
                                            'refresh: readSS timeout, proxy fallback',
                                          );
                                          if (await loadPagesFromProxy(
                                            lifKey,
                                          )) {
                                            transactionStore.dispatch(
                                              UpdateScreenTxAction(
                                                ScreenTransaction({
                                                  '#REFRESH': false,
                                                }),
                                              ),
                                            );
                                            _endRefresh(
                                              elements: reloadPage(pageName),
                                              tag: 'refresh proxy fallback',
                                            );
                                            return;
                                          }
                                        }
                                      } catch (e2) {
                                        devPrint(
                                          'refresh proxy fallback failed: $e2',
                                        );
                                      }
                                      _endRefresh(
                                        alert: true,
                                        tag: 'refresh icon catch',
                                      );
                                    });
                              } catch (e) {
                                _endRefresh(
                                  alert: true,
                                  tag: 'refresh icon catch',
                                );
                              }
                            } else {
                              // No internet: release the claim or the button
                              // stays amber/locked for the session.
                              setState(() {
                                _refreshing = false;
                              });
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    // display dialog that data is not ready
                                    title: Text(textList["NoInternetTitle"]),
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
                                },
                              );
                            } // end if internetConnected
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
                    // Authenticated but the user's pages are not up yet (or
                    // failed): every nav destination would route into pages
                    // that were never loaded, so keep the bar hidden until
                    // there is something real behind it.
                    if (!userPagesLoaded()) {
                      return const SizedBox.shrink();
                    }
                    // --- cache-first navbar restore (one-shot) ---
                    // On the first authenticated frame the in-memory
                    // systemUIComponent may still hold the guest snapshot
                    // (signOut replaced it + removed @systemUI). Restore the
                    // last authed snapshot from @authedSystemUI synchronously
                    // (prefs reads are sync after init) so the full bottomBar
                    // paints immediately instead of staggering in after the
                    // live readSettings round-trip.
                    // Re-evaluated EVERY build (NOT one-shot): the live
                    // in-memory bottomBar can be reverted to the guest
                    // (home-only) bar by a guest-scoped proxy refresh or a
                    // guest-key readSettings that fires AFTER login, and a
                    // one-shot restore could never recover from that late
                    // clobber (the reported "home navbar shows only a single
                    // home icon" bug). Decoding @authedSystemUI every frame
                    // would be wasteful, so the authed bar length is memoized
                    // and re-parsed only when the raw prefs string changes.
                    try {
                      final cachedAuthed = prefs.getString('@authedSystemUI');
                      if (cachedAuthed != _authedRawMemo) {
                        _authedRawMemo = cachedAuthed;
                        _authedBarLenMemo =
                            shouldRestoreAuthedSystemUI(cachedAuthed)
                            ? (json.decode(cachedAuthed!)[mobile]['bottomBar']
                                      as List)
                                  .length
                            : -1;
                      }
                      final currentBar =
                          systemUIComponent[mobile]?['bottomBar'];
                      // Restore only when the cached authed bar has MORE
                      // items than the live bar (live is stale/guest). A
                      // legit authed update keeps the full bar, so the gate
                      // fails and never clobbers it.
                      //
                      // ASSUMPTION (QA note): the guest bottomBar is strictly
                      // SHORTER than the authed one (guest = home-only,
                      // authed = full). A tenant whose guest bar equals the
                      // authed item count would NOT trigger the restore.
                      if (_authedBarLenMemo > 0 &&
                          (currentBar is! List ||
                              _authedBarLenMemo > currentBar.length)) {
                        // Fresh decode (not aliasing the memo) so a later
                        // in-place proxy write to systemUIComponent can't
                        // corrupt the comparison baseline. Mutating the
                        // global (vs a read-only pick) keeps handleNavTap's
                        // bottomBar[i] route lookup in range with the bar the
                        // navbar just rendered.
                        systemUIComponent = json.decode(_authedRawMemo!);
                      }
                    } catch (e) {
                      devPrint('navbar authed-bar restore failed: $e');
                    }
                    // --- end cache-first restore ---
                    // hideBottomBar is a property of the SDUI page, not of the
                    // notification inbox: when byPass > 0 the body is the
                    // inbox (a nav destination), so it keeps its bar even if
                    // the page underneath opted out.
                    if (byPass == 0 &&
                        screenUIComponent[pageName]?['hideBottomBar'] == true) {
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
                        final navItems = List<OtqNavItem>.generate(
                          barItems.length,
                          (i) {
                            final iconKey = barItems[i]['icon'].toString();
                            final route =
                                barItems[i]['route']?.toString() ?? '';
                            final label =
                                barItems[i]['label']?.toString() ??
                                route.replaceAll('_', ' ');
                            return OtqNavItem(
                              // Slot 1 is the notification inbox (badge is
                              // hardwired to i==1 below) — always a bell,
                              // regardless of the server JSON icon key.
                              icon: i == 1
                                  ? Icons.notifications_outlined
                                  : (otqIcons[iconKey] ??
                                        Icons.circle_outlined),
                              label: label,
                              badgeCount: i == 1 ? unread : null,
                            );
                          },
                        );
                        return OtqBottomNavBar(
                          // Inbox highlight is derived, not stored: byPass is
                          // the single source of truth for "am I in the
                          // inbox", so it can never disagree with the body.
                          selectedIndex: byPass > 0 ? 1 : _selectedNavIndex,
                          items: navItems,
                          onTap: handleNavTap,
                        );
                      },
                    );
                  },
                ),
            body: OfflineBannerHost(
              child: byPass > 0
                  ? byPassWidget
                  : Stack(
                      children: <Widget>[
                        // Text(gpsTime),
                        // Text(displayRefresher.toString()),
                        BlocBuilder<AuthenticationBloc, AuthenticationState>(
                          builder: (context, authState) {
                            if (authState is Unauthenticated) {
                              return Container(
                                padding: EdgeInsets.fromLTRB(
                                  lPad,
                                  tPad,
                                  rPad,
                                  bPad,
                                ),
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
                            // Signed in, but `home` still holds the
                            // sign-in page because the user's pages have
                            // not landed. Show the real state instead of
                            // a login form the user already got past.
                            if (!userPagesLoaded()) {
                              return _buildPagesGate();
                            }
                            // Padding sits on the ListView (not a wrapping
                            // Container) so the list clips to the FULL
                            // viewport. Inset items look identical; items
                            // that opt out via a negative margin (e.g. the
                            // full-bleed admin header) can reach the screen
                            // edge / AppBar without being re-clipped.
                            return Builder(
                              builder: (context) => ListView.builder(
                                controller: scrollController,
                                padding: EdgeInsets.fromLTRB(
                                  lPad,
                                  tPad,
                                  rPad,
                                  // extendBody lets the list paint under
                                  // the floating bar; an explicit padding
                                  // opts out of the automatic MediaQuery
                                  // inset, so add the bar height back or
                                  // the last row hides behind the pill.
                                  // 0 when the bar is hidden.
                                  bPad + MediaQuery.of(context).padding.bottom,
                                ),
                                itemCount: pageElements.length,
                                itemBuilder: (context, position) {
                                  return pageElements[position];
                                },
                              ),
                            );
                          },
                        ),
                        // Sticky bottom bar (approval/incident buttons)
                        ValueListenableBuilder<String>(
                          valueListenable: ApproverStickyBar.activeBarScreen,
                          builder: (_, route, _) => ValueListenableBuilder<int>(
                            valueListenable: ApproverStickyBar.version,
                            builder: (_, _, _) => ValueListenableBuilder<bool>(
                              valueListenable: ApproverStickyBar.overlaysHidden,
                              builder: (ctx, hidden, _) =>
                                  ValueListenableBuilder<WidgetBuilder?>(
                                    valueListenable: ApproverStickyBar.slot,
                                    builder: (ctx, slotBuilder, _) {
                                      final configs =
                                          ApproverStickyBar.getConfigs(route);
                                      debugPrint(
                                        '[StickyBar] activeBarScreen='
                                        '"$route" configs=${configs?.length} '
                                        'hidden=$hidden',
                                      );
                                      // Slot mode (commentbox screens): the
                                      // timeline's bottom comment-box overlay
                                      // already hosts the approve/reject bar via
                                      // ApproverStickyBar.slot. Suppress this
                                      // body-level copy, else the bar renders
                                      // twice (stacked) at the screen bottom.
                                      if (slotBuilder != null) {
                                        return const SizedBox.shrink();
                                      }
                                      if (hidden ||
                                          configs == null ||
                                          configs.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      final bottomInset = MediaQuery.of(
                                        ctx,
                                      ).viewInsets.bottom;
                                      if (bottomInset > 0) {
                                        return const SizedBox.shrink();
                                      }
                                      return Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Material(
                                          color: Colors.white,
                                          elevation: 8,
                                          child: SafeArea(
                                            top: false,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: StickyBarRenderer(
                                                configs: configs,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                            ),
                          ),
                        ),
                        //------ Login bloc listener---------
                        BlocListener(
                          bloc: _loginBloc,
                          listener: (BuildContext contextLogin, LoginState loginState) {
                            if (loginState.isFailure) {
                              if (loginState.loginStatus == 2) {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text("Other user logged in"),
                                      content: const Text(
                                        "Ada pemakai lain yang sedang memakai invitasi ini. Silahkan pergunakan nomor invitasi lain",
                                      ), // show dialog
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            setState(() {
                                              wait = false;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
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
                                        "Invitation Code Not Match",
                                      ),
                                      content: const Text(
                                        "Kode Undangan tidak ada.",
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            BlocProvider.of<LoginBloc>(
                                              context,
                                            ).add(
                                              const TosOKTabbed(tosOk: true),
                                            );
                                            setState(() {
                                              wait = false;
                                              touch = !touch;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
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
                                        "Invitation Code has been used before",
                                      ),
                                      content: const Text(
                                        "Kode undangan telah dipakai oleh pengguna lain. Silahkan hubungi bagian administrasi.",
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            setState(() {
                                              wait = false;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
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
                                        "Wah!, banyak sekali yang mendaftar. Sementara ini tidak dapat menambah pemakai baru. Kami sedang terus menambah kapasitas, silahkan coba beberapa jam lagi",
                                      ), // show dialog
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            setState(() {
                                              wait = false;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
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
                                        "Terjadi kesalahan pada saat sign in, silahkan coba beberapa jam lagi",
                                      ), // show dialog
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            setState(() {
                                              wait = false;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
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
                                        "Terjadi kesalahan pada saat autorisasi akun Google, silahkan coba lagi",
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            setState(() {
                                              wait = false;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
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
                                        "Login anda gagal. Kemungkinan karena koneksi internet anda terganggu. Silahkan coba beberapa saat lagi",
                                      ), // show dialog
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text("OK"),
                                          onPressed: () {
                                            setState(() {
                                              wait = false;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            } else if (loginState.isSuccess) {
                              BlocProvider.of<AuthenticationBloc>(
                                context,
                              ).add(LoggedIn());
                              BlocProvider.of<NotificationBloc>(
                                context,
                              ).add(LoadNotification());
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
                              if ((state is Running && state.duration > 0)) {
                                // || this.wait) {
                                ret = const WaitScreen();
                              } else {
                                if (state is Finished) {
                                  oldSettingUpShouldBeDeleted().then((aRes) {
                                    var state = transactionStore.state.screenTx;
                                    var lifKey = state['#INTERFACE_KEY'];
                                    readSettings(lifKey, 1).then((_) {
                                      var nxPage = state['#NEXTROUTE'];
                                      routeStack.push(nxPage); //?
                                      transactionStore.add(
                                        UpdateScreenTxAction(
                                          ScreenTransaction({
                                            '#REFRESH': false,
                                          }),
                                        ),
                                      );
                                      List<Widget> newElementList = reloadPage(
                                        nxPage,
                                      );
                                      setState(() {
                                        pageName = nxPage;
                                        pageElements = newElementList;
                                        wait = false;
                                      });

                                      transactionStore.dispatch(
                                        UpdateScreenTxAction(
                                          ScreenTransaction({
                                            '#CURRENT_ROUTE': nxPage,
                                          }),
                                        ),
                                      ); // set state #CURRENT_ROUTE
                                      if (scrollController.hasClients) {
                                        scrollController.jumpTo(0.0);
                                      }
                                      state['#TIMER_BLOC'].dispatch(
                                        Reset(),
                                      ); // reset timer state to Ready
                                    });
                                  });
                                }
                                ret = const SizedBox(width: 0.0, height: 0.0);
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
                                          mState.str2,
                                        ), // show dialog
                                        actions: <Widget>[
                                          TextButton(
                                            child: const Text("OK"),
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                          ),
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
                                          return linkElement['_NewPin']![position];
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
                        // The login spinner overlay was removed: it
                        // watched the TOP-LEVEL LoginBloc, but the
                        // loading state (isSubmitting) is only ever
                        // emitted by the social/credential handlers on the
                        // NESTED LoginForm bloc, so this overlay never
                        // fired in the live flow. The login_form /
                        // invitation_form modal dialog (PopScope, blocks
                        // back) is the real single spinner.
                        // Logout spinner overlay: shown only while
                        // signOut() is re-fetching the login page over the
                        // network (cold/corrupt guest snapshot). Gated on
                        // the scoped MainPageState.logoutInProgress flag,
                        // which signOut() toggles via rootThis.setState.
                        // The warm-cache restore never sets it, so the
                        // common logout stays instant (no overlay). Last in
                        // the Stack so it paints over the stale home body.
                        if (MainPageState.logoutInProgress) const WaitScreen(),
                      ],
                    ), // Stack closure=========
            ), // end OfflineBannerHost
          ),
        );
        return v;
      }, // end of builder,
    );
  } // end of build

  /// Common tail of every refresh completion path: tx-ok flags, green dot,
  /// optional repaint payload, optional error alert. Replaces three verbatim
  /// copies that used to live inline in the refresh onPressed.
  void _endRefresh({
    List<Widget>? elements,
    bool alert = false,
    required String tag,
  }) {
    setTransactionOK(tag);
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#DATA_OK': true})),
    );
    if (mounted) {
      setState(() {
        if (elements != null) {
          pageElements = elements;
        }
        _refreshing = false;
        wait = false;
        touch = !touch;
        dataColor = readyColor;
      });
      if (alert) {
        showAlert(context, textList["ErrorLoading"]);
      }
    }
  }

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
        // ssid switch: cancel the OLD ssid's listener BEFORE subscribing to the
        // new one. The dispatch at the bottom of this branch only overwrites the
        // HANDLE in #PROXY_LISTENER — the old subscription itself stays live, so
        // the device would listen to BOTH proxies. The old listener's reload
        // writes ITS tenant's Page/System docs into the shared
        // screenUIComponent/systemUIComponent globals => silent cross-tenant UI
        // bleed (no error, no crash). Also unfixable via #PROXY_LISTENER_CS,
        // which is a single global slot both listeners would fight over.
        // No-op today (one caller: initState, which runs once per launch);
        // insurance for the moment a second caller re-subscribes on login or
        // tenant switch. try/catch because subscribeToProxy is fire-and-forget,
        // so a rejected cancel() would surface as an uncaught fatal.
        try {
          await state['#PROXY_LISTENER']?.cancel();
        } catch (e) {
          devPrint('proxy old-listener cancel failed (skipped): $e');
        }
        dynamic docRef = firestoreDb.collection(proxyCollectionName).doc(ssid);
        bool docExist;
        try {
          docExist = (await docRef.get()).exists;
        } catch (e) {
          // Firestore [unavailable]/transient network on cold start: one-shot
          // .get() rejects → uncaught (caller is fire-and-forget) → fatal. Skip
          // this attempt; subscribeToProxy re-runs on the next readSettings/
          // refresh. Retryable blip — don't crash, don't spam Crashlytics.
          devPrint('subscribeToProxy get failed (skipped): $e');
          return;
        }
        if (docExist) {
          // Restore the last-seen proxy checksum for THIS ssid before the
          // listener can fire. #PROXY_LISTENER_CS lives only in transactionStore
          // (in-memory), so without this it is null on every cold start and the
          // first snapshot ALWAYS passes the change-gate below — re-applying an
          // UNCHANGED (proxy lags the sheet) snapshot over the fresh /readSS
          // refresh the user just pulled, reverting it. Keyed by ssid so a
          // restored checksum can't leak across tenants.
          final int? savedProxyCs = prefs.getInt('@proxyCS_$ssid');
          if (savedProxyCs != null) {
            transactionStore.dispatch(
              UpdateScreenTxAction(
                ScreenTransaction({'#PROXY_LISTENER_CS': savedProxyCs}),
              ),
            );
          }
          final proxyListener = docRef.snapshots().listen((event) {
            if (event.data() != null) {
              // process event data
              dynamic rec = event.data();
              // actionLock();

              if (rec['t'] !=
                  transactionStore.state.screenTx['#PROXY_LISTENER_CS']) {
                // proxy change detected
                // update profile
                asHomeArray = jsonDecode(
                  rec['u'] ?? '[]',
                ); // set singleton asHomeArray
                devPrint("Proxy change detected in : Proxy/$ssid");
                transactionStore.dispatch(
                  UpdateScreenTxAction(
                    ScreenTransaction({
                      '#NAME': rec['n'],
                      '#EMAIL': rec['e'],
                      '#PHONE': rec['p'],
                      '#PROXY_LISTENER_CS': rec['t'],
                    }),
                  ),
                );
                // Persist the checksum so the next cold start can tell an
                // unchanged proxy from a real change (see restore above). Epoch
                // 't' is integral; if it ever isn't an int, fall back to the old
                // (non-persisted) behavior rather than crash.
                if (rec['t'] is int) {
                  try {
                    prefs.setInt('@proxyCS_$ssid', rec['t']);
                  } catch (e) {
                    devPrint('persist @proxyCS failed: $e');
                  }
                }
                // check and update system
                // actionUnLock();
                Map<String, dynamic> newItem = {};
                dynamic collectionRef = FirebaseFirestore.instance.collection(
                  '$proxyCollectionName/$ssid/System',
                );
                collectionRef
                    .get()
                    .then((value) {
                      systemUIComponent = {};
                      for (final doc in value.docs) {
                        dynamic systemData = doc.data();
                        newItem[systemData['p']] = {
                          'c': systemData['c'],
                          't': systemData['t'],
                          'v': systemData['v'],
                        };
                        systemUIComponent[systemData['p']] = json.decode(
                          systemData['c'],
                        );
                      } // end for (final doc in value.docs)
                      storage.write(
                        key: 'ui_systems',
                        value: jsonEncode(newItem),
                      ); // store systems in secure storage
                      buildTheme(systemUIComponent[theme]);
                      // Persist authed system snapshot for cache-first navbar
                      // restore. Gated on the guest signup ssid (mirrors the
                      // readSettings/readSettingsContext non-guest gate) so a guest
                      // proxy refresh — the same case the Page block handles at
                      // `ssid == state['#SIGNUP_KEY']` below — never overwrites the
                      // last authenticated session's bottomBar in @authedSystemUI.
                      if (ssid != state['#SIGNUP_KEY']) {
                        try {
                          prefs.setString(
                            '@authedSystemUI',
                            json.encode(systemUIComponent),
                          );
                        } catch (e) {
                          devPrint('proxy persist @authedSystemUI failed: $e');
                        }
                      }
                    })
                    .catchError((e) {
                      // transient [unavailable]/network — proxy re-fires on next
                      // change; uncaught .then() reject would be fatal.
                      devPrint('proxy System reload failed (skipped): $e');
                    }); // end of system then

                // check and update pages
                newItem = {};
                collectionRef = FirebaseFirestore.instance.collection(
                  '$proxyCollectionName/$ssid/Page',
                );
                collectionRef
                    .get()
                    .then((value) {
                      screenUIComponent = {};
                      for (final doc in value.docs) {
                        dynamic pageData = doc.data();
                        newItem[pageData['p']] = {
                          'c': pageData['c'],
                          't': pageData['t'],
                          'v': pageData['v'],
                        };
                        try {
                          screenUIComponent[pageData['p']] = json.decode(
                            pageData['c'],
                          );
                          // devPrint("Page ${pageData['p']} => updated");
                        } catch (e) {
                          // devPrint("Error in page ${pageData['p']} => $e");
                          screenUIComponent[pageData['p']] = json.decode(
                            errorPage,
                          );
                        }
                      } // end for (final doc in value.docs)
                      storage.write(
                        key: 'ui_pages',
                        value: jsonEncode(newItem),
                      ); // store pages in secure storage
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
                    })
                    .catchError((e) {
                      // transient [unavailable]/network — proxy re-fires on next
                      // change; uncaught .then() reject would be fatal.
                      devPrint('proxy Page reload failed (skipped): $e');
                    }); // end of then
              } // end if (rec['t'] != state['#PROXY_LISTENER_CS'])
              // actionUnLock();
            } // end if (event.data() == null)
          }); // end of listener
          // devPrint("Subscribed to  : Proxy/$ssid");
          transactionStore.dispatch(
            UpdateScreenTxAction(
              ScreenTransaction({
                '#PROXY_LISTENER': proxyListener,
                '#PROXY_LISTENER_SSID': ssid,
              }),
            ),
          );
        } // end if (docExist)
      } // end if (ssid == state['#PROXY_LISTENER_SSID'])
    } else {
      // no ssid and unsubscribe from current proxy
      if (state['#PROXY_LISTENER'] != null) {
        dynamic tableListener =
            transactionStore.state.screenTx['#PROXY_LISTENER'];
        tableListener?.cancel();
        tableListener = null;
        transactionStore.dispatch(
          UpdateScreenTxAction(
            ScreenTransaction({
              '#PROXY_LISTENER': null,
              '#PROXY_LISTENER_SSID': null,
            }),
          ),
        );
        // devPrint("Unsubscribe from Proxy/${state['#PROXY_LISTENER_SSID']}");
      } // end if ((state['#PROXY_LISTENER_SSID']??'') != '')
    }
  } // end of subscribeToProxy

  /// Shown when the user is signed in but their pages are not loaded.
  ///
  /// Deliberately NOT the sign-in form: the user has already authenticated, so
  /// showing login again reads as "your login failed" when it in fact succeeded.
  Widget _buildPagesGate() {
    final bool failed = pagesFetchFailed && !pagesFetching;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (!failed) ...<Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                textList['LoadingPages'] ?? 'Memuat halaman Anda…',
                textAlign: TextAlign.center,
              ),
            ] else ...<Widget>[
              Icon(
                Icons.cloud_off,
                size: 48,
                color: Theme.of(context).disabledColor,
              ),
              const SizedBox(height: 20),
              Text(
                textList['LoadPagesFailed'] ??
                    'Gagal memuat halaman Anda.\nPeriksa koneksi, lalu coba lagi.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _retryUserPages,
                child: Text(textList['TryAgain'] ?? 'Coba Lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retryUserPages() async {
    if (pagesFetching)
      return; // ponytail: ignore taps while a fetch is in-flight
    setState(() {
      pagesFetching = true;
      pagesFetchFailed = false;
    });
    bool ok = false;
    try {
      ok = await retryUserPages();
    } catch (e) {
      // retryUserPages already rebuilds the shell on success; a throw here just
      // means we stay on the retry state.
      devPrint('retryUserPages threw: $e');
    }
    if (!mounted) return;
    setState(() {
      pagesFetching = false;
      pagesFetchFailed = !ok;
    });
  }

  void rePaintScreen(String source) {
    if (!mounted) return;
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
