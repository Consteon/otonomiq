import 'package:flutter/material.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../page/any_page.dart';
import '../page/home_page.dart';
import '../redux/screen_transaction.dart';
import '../widget/all_widget.dart';
import '../widget/approver_sticky_bar.dart';

void constructPageElements(String scrName) {
  // initiate txfController and linkElement of a page (scrName)
  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  }
  if (screenUIComponent[scrName] == null) {
    screenUIComponent[scrName] = {};
  }
  if (screenUIComponent[scrName]['children'] != null) {
    linkElement[scrName] = buildPage(
      screenUIComponent[scrName]['children'],
      scrName,
    );
  } // end if children
} // end of constructPageElements

void constructHomeElements() {
  constructPageElements(home);
}

void constructAllPageElements() {
  screenUIComponent.forEach((k, v) {
    // Isolate per screen. One throwing screen used to abort this forEach, so
    // every screen after it was never built (linkElement missing -> blank page)
    // and the log named the caller, never the screen. Report the screen name.
    try {
      constructPageElements(k);
    } catch (e, s) {
      errorReport('constructAllPageElements failed on screen "$k": $e', s);
    }
  });
}

// -------

void constructPage(String scrName) {
  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  }
  if (scrName == home) {
    linkPage[scrName] = HomePage(key: UniqueKey(), pageName: scrName);
  } else {
    linkPage[scrName] = AnyPage(key: UniqueKey(), pageName: scrName);
  }
} // end of constructPage

void constructAllNotHomePages() async {
  screenUIComponent.forEach((k, v) {
    if (k != home) {
      constructPage(k);
    }
  });
}

void constructAllNotHomePagesSync() {
  screenUIComponent.forEach((k, v) {
    if (k != home) {
      constructPage(k);
    }
  });
}

void constructAllPages() async {
  screenUIComponent.forEach((k, v) {
    constructPage(k);
  });
}

void constructAllPagesSync() {
  screenUIComponent.forEach((k, v) {
    constructPage(k);
  });
}

dynamic getAllPages(BuildContext context, String scrName) {
  Map<String, List<Widget>> pages = {};
  screenUIComponent.forEach((k, v) {
    pages[k] = buildPage(v['children'], scrName);
  });
  return pages;
}

void buildAllPages(BuildContext context, String scrName) async {
  linkPage = getAllPages(context, scrName);
  //  poxPage = await compute(getAllPages,screenUIComponent);
}

Alignment getComponentAlignment(String? alg) {
  Alignment result = Alignment.topLeft;
  String inpAlg = (alg ?? "").toLowerCase().trim();

  if (inpAlg == 'start') {
    result = Alignment.topLeft;
  } else if (inpAlg == 'center' || inpAlg == 'centre') {
    result = Alignment.topCenter;
  } else if (inpAlg == 'end') {
    result = Alignment.topRight;
  } else if (inpAlg == 'spaceevenly' ||
      inpAlg == 'spacebetween' ||
      inpAlg == 'spacearound') {
    result = Alignment.topCenter;
  }
  return result;
} // end of getComponentAlignment

List<Widget> buildColumnPage(
  var componentList,
  String scrName, {
  bool? dialog,
}) {
  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  } // end if
  var myState = transactionStore.state.screenTx;
  var userRepository = myState['#USER_REPOSITORY'];
  var pageComponent = [
    Align(
      alignment: getComponentAlignment(componentList[0]['alignment']),
      child: buildDisplayComponent(componentList[0], scrName, userRepository),
    ),
  ];
  for (var i = 1; i < componentList.length; i++) {
    pageComponent.add(
      Align(
        alignment: getComponentAlignment(componentList[i]['alignment']),
        child: buildDisplayComponent(
          componentList[i],
          scrName,
          userRepository,
          dialog: dialog ?? false,
        ),
      ),
    );
  } // end for
  return pageComponent;
} // end of buildColumnPage

List<Widget> buildPage(
  var componentList,
  String scrName, {
  bool? dialog,
  bool clear = true,
}) {
  // main page should omit clear (=true),
  // sub page like dialog or widgetList should set clear = false

  // A screen whose `children` is an empty array threw
  // `RangeError (length): Invalid value: Valid value range is empty: 0` on the
  // unguarded `componentList[0]` below. constructPageElements only checks
  // `children != null`, and constructAllPageElements iterates every screen in
  // one forEach — so a single empty-children screen aborted the whole loop and
  // left every screen after it unbuilt, on cache load, on opt-2 startup and on
  // every refresh. Render it as an empty page instead.
  if (componentList is! List || componentList.isEmpty) {
    devPrint('buildPage: "$scrName" has no children — rendering empty page');
    return <Widget>[];
  }

  dynamic myState = transactionStore.state.screenTx;

  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  } else {
    if (clear && canInitializePage(scrName)) {
      txfController[scrName]!.clear();
    }
  } // end if (txfController[scrName] == null
  if (clear) {
    ApproverStickyBar.clearConfigs(scrName);
    clearDriverHomeState(scrName);
    TaskManifestList.clearExpandState(scrName);
    CustodyCountList.clearCountStore(scrName);
    CustodyReveal.clearEditState(scrName);
    CustodyEventSubmit.clearState(scrName);
    ItemExecutionList.clearExecutionStore(scrName);
    ItemExecutionSubmit.clearState(scrName);
    // ponytail: do NOT clearAllDrafts() here. buildPage(clear:true) runs once
    // per screen on every readSettings refresh (constructPageElements), so a
    // background refresh mid-wizard wiped the in-flight customer/vehicle and P4
    // rendered null. The real resets are per-wizardKey and already covered:
    // P1 customer-pick clearDraft (task_feed_list) + submit-success clearDraft
    // (task_create_submit). Re-add a scoped clear only if a tenant switch must
    // drop a half-done draft.
    TaskItemBuilder.resetClientPublished(scrName);
    TaskCreateSubmit.resetWriting(scrName);
    NotaCreateSubmit.resetWriting(scrName);
    TaskFeedList.clearFlatSearch(scrName);
    CustomerOutstandingList.clearState(scrName);
    AssetStockList.clearState(scrName);
    TablePicker.clearState(scrName);
    GroupPicker.clearState(scrName);
    WhatsAppSend.clearSentState(scrName);
    PayoutList.clearState(scrName);
    ListActionCard.clearState(scrName);
  }

  dynamic userRepository = myState['#USER_REPOSITORY'];
  List<Widget> pageComponent = [
    buildDisplayComponent(componentList[0], scrName, userRepository),
  ];
  for (var i = 1; i < componentList.length; i++) {
    pageComponent.add(
      buildDisplayComponent(
        componentList[i],
        scrName,
        userRepository,
        dialog: dialog ?? false,
      ),
    );
  }
  return pageComponent;
} // end of buildPage

void appRefresh() {
  var state = transactionStore.state.screenTx;
  if (state['#REFRESH'] || true) {
    oldSettingUpShouldBeDeleted().then((aRes) {
      var state = transactionStore.state;
      var lifKey = state.screenTx['#INTERFACE_KEY'];
      readSettings(lifKey, 1).then((_) {
        // constructAllPageElements();
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})),
        );
        List<Widget> newElementList = List<Widget>.of(
          linkElement[rootThis.pageName]!.map((widget) => widget),
        );
        // List<Widget> newElementList = List<Widget>.empty(growable: true);
        // newElementList.addAll(linkElement[rootThis.pageName]!);
        rootThis.setState(() {
          rootThis.pageElements = newElementList;
          rootThis.wait = false;
        });
      });
    });
  }
} // end of appRefresh

List<Widget> buildBannerList(var bannerList, double aspectRatio) {
  dynamic bannerComponent;

  try {
    bannerComponent = [
      Builder(
        builder: (BuildContext context) {
          return Container(
            alignment: const FractionalOffset(0.5, 0.5),
            child: Card(
              child: InkWell(
                onTap: () {
                  if (bannerList[0]['route'] != null &&
                      bannerList[0]['route'] != rootThis.pageName &&
                      routeExist(bannerList[0]['route'])) {
                    routeStack.push(bannerList[0]['route']);
                    if (bannerList[0]['route'].length >= 4 &&
                        bannerList[0]['route'].substring(0, 4).toLowerCase() ==
                            'http') {
                      openInWebView(
                        context,
                        bannerList[0]['route'],
                        bannerList[0]['title'] ?? 'Web',
                      );
                    } else {
                      var state = transactionStore.state.screenTx;
                      if (state['#REFRESH']) {
                        oldSettingUpShouldBeDeleted().then((aRes) {
                          var state = transactionStore.state;
                          var lifKey = state.screenTx['#INTERFACE_KEY'];
                          readSettings(lifKey, 1).then((_) {
                            // constructAllPageElements();
                            transactionStore.dispatch(
                              UpdateScreenTxAction(
                                ScreenTransaction({'#REFRESH': false}),
                              ),
                            );
                            //                            List<Widget> newElementList = List<Widget>();
                            String newRoute = bannerList[0]['route'];
                            List<Widget> newElementList = reloadPage(newRoute);
                            //                            newElementList.addAll(linkElement[newRoute]);
                            rootThis.setState(() {
                              rootThis.pageName = newRoute;
                              rootThis.pageElements = newElementList;
                              rootThis.wait = false;
                            });
                          });
                        });
                      } else {
                        String newRoute = bannerList[0]['route'];
                        if (routeExist(newRoute)) {
                          // test if route exist
                          List<Widget> newElementList = reloadPage(newRoute);
                          rootThis.setState(() {
                            rootThis.pageName = newRoute;
                            rootThis.pageElements = newElementList;
                            rootThis.wait = false;
                          });
                        }
                      }
                    }
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    AspectRatio(
                      aspectRatio: aspectRatio,
                      child: displayImage(
                        imageUrl: bannerList[0]['url'] ?? defaultImage,
                        cached: true,
                      ),
                      //   child: FadeInImage.memoryNetwork(
                      //       placeholder: kTransparentImage,
                      //       image: _bannerList[0]['url']),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  } catch (_) {
    bannerComponent = Container(
      alignment: const FractionalOffset(0.5, 0.5),
      child: Card(
        child: InkWell(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              AspectRatio(
                aspectRatio: aspectRatio,
                child: displayImage(imageUrl: errorUrl, cached: true),
                // child: FadeInImage.memoryNetwork(
                //     placeholder: kTransparentImage, image: errorUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  for (var i = 1; i < bannerList.length; i++) {
    try {
      bannerComponent.add(
        Builder(
          builder: (BuildContext context) {
            return Container(
              alignment: const FractionalOffset(0.5, 0.5),
              child: Card(
                child: InkWell(
                  onTap: () {
                    if (bannerList[i]['route'] != null &&
                        bannerList[i]['route'] != rootThis.pageName &&
                        routeExist(bannerList[i]['route'])) {
                      routeStack.push(bannerList[i]['route']);
                      if (bannerList[i]['route'].length >= 4 &&
                          bannerList[i]['route']
                                  .substring(0, 4)
                                  .toLowerCase() ==
                              'http') {
                        openInWebView(
                          context,
                          bannerList[i]['route'],
                          bannerList[i]['title'] ?? 'Web',
                        );
                      } else {
                        var state = transactionStore.state.screenTx;
                        if (state['#REFRESH']) {
                          oldSettingUpShouldBeDeleted().then((aRes) {
                            var state = transactionStore.state;
                            var lifKey = state.screenTx['#INTERFACE_KEY'];
                            readSettings(lifKey, 1).then((_) {
                              transactionStore.dispatch(
                                UpdateScreenTxAction(
                                  ScreenTransaction({'#REFRESH': false}),
                                ),
                              );
                              String newRoute = bannerList[i]['route'];
                              List<Widget> newElementList = reloadPage(
                                newRoute,
                              );
                              rootThis.setState(() {
                                rootThis.pageName = newRoute;
                                rootThis.pageElements = newElementList;
                                rootThis.wait = false;
                              });
                            });
                          });
                        } else {
                          String newRoute = bannerList[i]['route'];
                          // Was linkElement[linkElement[newRoute]!]! — a double
                          // index that null-deref crashed on the 2nd+ banner of a
                          // multi-banner home. reloadPage matches the sibling
                          // banner[0]/grid[0] branches above.
                          List<Widget> newElementList = reloadPage(newRoute);
                          rootThis.setState(() {
                            rootThis.pageName = newRoute;
                            rootThis.pageElements = newElementList;
                            rootThis.wait = false;
                          });
                        }
                      }
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      AspectRatio(
                        aspectRatio: aspectRatio,
                        child: displayImage(
                          imageUrl: bannerList[i]['url'] ?? defaultImage,
                          cached: true,
                        ),
                        // child: FadeInImage.memoryNetwork(
                        //     placeholder: kTransparentImage,
                        //     image: _bannerList[i]['url']),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (_) {
      bannerComponent.add(
        Container(
          alignment: const FractionalOffset(0.5, 0.5),
          child: Card(
            child: InkWell(
              onTap: () {},
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: aspectRatio,
                    child: displayImage(imageUrl: errorUrl, cached: true),
                    // child: FadeInImage.memoryNetwork(
                    //     placeholder: kTransparentImage, image: errorUrl),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
  return bannerComponent;
}

List<Widget> buildGridList(var gridList, double fontSize) {
  // gridList is server JSON (component['children']); empty/null/non-List →
  // the deferred Builder/onTap closures below index gridList[0] at LAYOUT time,
  // outside the try/catch, throwing RangeError → fatal. Guard at the source.
  if (gridList is! List || gridList.isEmpty) {
    return <Widget>[];
  }
  const double defaultAspectRatio = 18 / 12;
  var topPad = 6.0;
  dynamic gridComponent;

  try {
    gridComponent = [
      Builder(
        builder: (BuildContext context) {
          return Container(
            alignment: const Alignment(0.0, 0.0),
            child: Card(
              child: InkWell(
                onTap: () {
                  if (gridList[0]['route'] != null &&
                      gridList[0]['route'] != rootThis.pageName &&
                      routeExist(gridList[0]['route'])) {
                    routeStack.push(gridList[0]['route']);
                    if (gridList[0]['route'].length >= 4 &&
                        gridList[0]['route'].substring(0, 4).toLowerCase() ==
                            'http') {
                      openInWebView(
                        context,
                        gridList[0]['route'],
                        gridList[0]['title'] ?? 'Web',
                      );
                    } else {
                      var state = transactionStore.state.screenTx;
                      if (state['#REFRESH']) {
                        oldSettingUpShouldBeDeleted().then((aRes) {
                          var state = transactionStore.state;
                          var lifKey = state.screenTx['#INTERFACE_KEY'];
                          readSettings(lifKey, 1).then((_) {
                            // constructAllPageElements();
                            transactionStore.dispatch(
                              UpdateScreenTxAction(
                                ScreenTransaction({'#REFRESH': false}),
                              ),
                            );
                            String newRoute = gridList[0]['route'];
                            List<Widget> newElementList = reloadPage(newRoute);
                            rootThis.setState(() {
                              rootThis.pageName = newRoute;
                              rootThis.pageElements = newElementList;
                              rootThis.wait = false;
                            });
                          });
                        });
                      } else {
                        String newRoute = gridList[0]['route'];
                        List<Widget> newElementList = reloadPage(newRoute);
                        rootThis.setState(() {
                          rootThis.pageName = newRoute;
                          rootThis.pageElements = newElementList;
                          rootThis.wait = false;
                          rootThis.touch = !rootThis.touch;
                        });
                      }
                    }
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(height: topPad),
                    AspectRatio(
                      aspectRatio: defaultAspectRatio,
                      child: displayImage(
                        imageUrl: gridList[0]['url'] ?? defaultImage,
                        cached: true,
                      ),
                      // child: FadeInImage.memoryNetwork(
                      //     placeholder: kTransparentImage,
                      //     image: _gridList[0]['url']),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        gridList[0]['text'],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: fontSize),
                      ),
                    ),
                    // Text(
                    //   gridList[0]['text'],
                    //   textAlign: TextAlign.center,
                    //   style: TextStyle(fontSize: fontSize),
                    // ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  } catch (_) {
    gridComponent = Container(
      alignment: const Alignment(0.0, 0.0),
      child: Card(
        child: InkWell(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(height: topPad),
              AspectRatio(
                aspectRatio: defaultAspectRatio,
                child: displayImage(imageUrl: errorUrl, cached: true),
                // child: FadeInImage.memoryNetwork(
                //     placeholder: kTransparentImage, image: errorUrl),
              ),
              const Text(
                '--GRID--',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  for (var i = 1; i < gridList.length; i++) {
    try {
      gridComponent.add(
        Builder(
          builder: (BuildContext context) {
            return Container(
              alignment: const Alignment(0.0, 0.0),
              child: Card(
                child: InkWell(
                  onTap: () {
                    if (gridList[i]['route'] != null &&
                        gridList[i]['route'] != rootThis.pageName &&
                        routeExist(gridList[i]['route'])) {
                      routeStack.push(gridList[i]['route']);
                      if (gridList[i]['route'].length >= 4 &&
                          gridList[i]['route'].substring(0, 4).toLowerCase() ==
                              'http') {
                        openInWebView(
                          context,
                          gridList[i]['route'],
                          gridList[i]['title'] ?? 'Web',
                        );
                      } else {
                        var state = transactionStore.state.screenTx;
                        if (state['#REFRESH']) {
                          oldSettingUpShouldBeDeleted().then((aRes) {
                            var state = transactionStore.state;
                            var lifKey = state.screenTx['#INTERFACE_KEY'];
                            readSettings(lifKey, 1).then((_) {
                              // constructAllPageElements();
                              transactionStore.dispatch(
                                UpdateScreenTxAction(
                                  ScreenTransaction({'#REFRESH': false}),
                                ),
                              );
                              //                            List<Widget> newElementList = List<Widget>();
                              String newRoute = gridList[i]['route'];
                              List<Widget> newElementList = reloadPage(
                                newRoute,
                              );
                              //                            newElementList.addAll(linkElement[newRoute]);
                              rootThis.setState(() {
                                rootThis.pageName = newRoute;
                                rootThis.pageElements = newElementList;
                                rootThis.wait = false;
                              });
                            });
                          });
                        } else {
                          //                        List<Widget> newElementList = List<Widget>();
                          String newRoute = gridList[i]['route'];
                          List<Widget> newElementList = reloadPage(newRoute);
                          //                        newElementList.addAll(linkElement[newRoute]);
                          rootThis.setState(() {
                            rootThis.pageName = newRoute;
                            rootThis.pageElements = newElementList;
                            rootThis.wait = false;
                          });
                        }
                      }
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Container(height: topPad),
                      AspectRatio(
                        aspectRatio: defaultAspectRatio,
                        child: displayImage(
                          imageUrl: gridList[i]['url'] ?? defaultImage,
                          cached: true,
                        ),
                        // child: FadeInImage.memoryNetwork(
                        //     placeholder: kTransparentImage,
                        //     image: _gridList[i]['url']),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          gridList[i]['text'],
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: fontSize),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (_) {
      gridComponent.add(
        Container(
          alignment: const Alignment(0.0, 0.0),
          child: Card(
            child: InkWell(
              onTap: () {},
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(height: topPad),
                  AspectRatio(
                    aspectRatio: defaultAspectRatio,
                    child: displayImage(imageUrl: errorUrl, cached: true),
                    // child: FadeInImage.memoryNetwork(
                    //     placeholder: kTransparentImage, image: errorUrl),
                  ),
                  const Text(
                    '--GRID--',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
  return gridComponent;
}

MainAxisAlignment maaSwitch(String alignment) {
  MainAxisAlignment result;
  switch (alignment) {
    case 'center':
      result = MainAxisAlignment.center;
      break;
    case 'start':
      result = MainAxisAlignment.start;
      break;
    case 'end':
      result = MainAxisAlignment.end;
      break;
    case 'spaceBetween':
      result = MainAxisAlignment.spaceBetween;
      break;
    case 'spaceEvenly':
      result = MainAxisAlignment.spaceEvenly;
      break;
    case 'spaceAround':
      result = MainAxisAlignment.spaceAround;
      break;
    default:
      result = MainAxisAlignment.start;
  }
  return result;
} // end of maaSwitch

Widget disabledIcon(String url, String iText, double fontSize) {
  const double defaultAspectRatio = 18 / 12;
  var topPad = 6.0;
  String dimmedImage =
      'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/c%2Fautsorz%2Fring-icon-dimmed-90x90.png?alt=media&token=73ddfd91-0286-409f-be1d-86dbc7f8ee3a';
  return Container(
    alignment: const Alignment(0.0, 0.0),
    child: Card(
      child: InkWell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(height: topPad),
            AspectRatio(
              aspectRatio: defaultAspectRatio,
              child: displayImage(
                imageUrl: (url == '') ? dimmedImage : url,
                cached: true,
              ),
              // child: FadeInImage.memoryNetwork(
              //   placeholder: kTransparentImage,
              //   image: (url == '') ? dimmedImage : url,
              // ),
            ),
            Text(
              iText,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: fontSize),
            ),
          ],
        ),
        onTap: () {},
      ),
    ),
  );
} // end of DisabledIcon
