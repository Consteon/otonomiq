import 'package:flutter/material.dart';
import 'package:get/get.dart'; // Obx — MENU BADGE live rebuild in buildGridList

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../page/any_page.dart';
import '../page/home_page.dart';
import '../redux/screen_transaction.dart';
import '../widget/all_widget.dart';
import '../screen_session.dart';

void constructPageElements(String scrName) {
  // initiate txfController and linkElement of a page (scrName)
  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  }
  if (screenUIComponent[scrName] == null) {
    screenUIComponent[scrName] = {};
  }
  if (screenUIComponent[scrName]['children'] != null) {
    linkElement[scrName] =
        buildPage(screenUIComponent[scrName]['children'], scrName);
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

List<Widget> buildColumnPage(var componentList, String scrName,
    {bool? dialog}) {
  if (txfController[scrName] == null) {
    txfController[scrName] = {};
  } // end if
  var myState = transactionStore.state.screenTx;
  var userRepository = myState['#USER_REPOSITORY'];
  var pageComponent = [
    Align(
        alignment: getComponentAlignment(componentList[0]['alignment']),
        child: buildDisplayComponent(componentList[0], scrName, userRepository))
  ];
  for (var i = 1; i < componentList.length; i++) {
    pageComponent.add(Align(
        alignment: getComponentAlignment(componentList[i]['alignment']),
        child: buildDisplayComponent(componentList[i], scrName, userRepository,
            dialog: dialog ?? false)));
  } // end for
  return pageComponent;
} // end of buildColumnPage

List<Widget> buildPage(var componentList, String scrName,
    {bool? dialog, bool clear = true}) {
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
    // ScreenSession.pageBuild iterates all registered stores whose
    // RebuildPolicy is screen and fires their clear function. The ponytail
    // comment about clearAllDrafts has moved to AdminCreateTaskSupport's
    // registerScreenSession (persistent:true rationale).
    ScreenSession.pageBuild(scrName);
  }

  dynamic userRepository = myState['#USER_REPOSITORY'];
  List<Widget> pageComponent = [
    buildDisplayComponent(componentList[0], scrName, userRepository)
  ];
  for (var i = 1; i < componentList.length; i++) {
    pageComponent.add(buildDisplayComponent(
        componentList[i], scrName, userRepository,
        dialog: dialog ?? false));
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
            UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})));
        List<Widget> newElementList = List<Widget>.of(
            linkElement[rootThis.pageName]!.map((widget) => widget));
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
                      openInWebView(context, bannerList[0]['route'],
                          bannerList[0]['title'] ?? 'Web');
                    } else {
                      var state = transactionStore.state.screenTx;
                      if (state['#REFRESH']) {
                        oldSettingUpShouldBeDeleted().then((aRes) {
                          var state = transactionStore.state;
                          var lifKey = state.screenTx['#INTERFACE_KEY'];
                          readSettings(lifKey, 1).then((_) {
                            // constructAllPageElements();
                            transactionStore.dispatch(UpdateScreenTxAction(
                                ScreenTransaction({'#REFRESH': false})));
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
                          cached: true),
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
      )
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
      bannerComponent.add(Builder(
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
                        bannerList[i]['route'].substring(0, 4).toLowerCase() ==
                            'http') {
                      openInWebView(context, bannerList[i]['route'],
                          bannerList[i]['title'] ?? 'Web');
                    } else {
                      var state = transactionStore.state.screenTx;
                      if (state['#REFRESH']) {
                        oldSettingUpShouldBeDeleted().then((aRes) {
                          var state = transactionStore.state;
                          var lifKey = state.screenTx['#INTERFACE_KEY'];
                          readSettings(lifKey, 1).then((_) {
                            transactionStore.dispatch(UpdateScreenTxAction(
                                ScreenTransaction({'#REFRESH': false})));
                            String newRoute = bannerList[i]['route'];
                            List<Widget> newElementList = reloadPage(newRoute);
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
                          cached: true),
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
      ));
    } catch (_) {
      bannerComponent.add(Container(
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
      ));
    }
  }
  return bannerComponent;
}

/// [scrName] is required by the MENU BADGE path: `filterDriverHomeDocs`
/// resolves `{driverVid}` / `{vehicleId}` / `{today}` per screen. Both call
/// sites (`vgr` and `hgr` in build_display_component.dart) already have it in
/// scope as the `buildDisplayComponent` parameter.
List<Widget> buildGridList(var gridList, double fontSize, String scrName) {
  // gridList is server JSON (component['children']); empty/null/non-List →
  // the deferred Builder/onTap closures below index gridList[i] at LAYOUT time,
  // outside the try/catch, throwing RangeError → fatal. Guard at the source.
  if (gridList is! List || gridList.isEmpty) {
    return <Widget>[];
  }
  List<Widget> gridComponent = [];
  for (var i = 0; i < gridList.length; i++) {
    try {
      final item = gridList[i];
      final bool first = i == 0;
      // MENU BADGE: resolve the vid-scoped code and start the stream ONCE, here
      // at page-build time (buildGridList runs from constructPageElements, not
      // per frame). '' = this child has no `badgeTable` -> the tile below takes
      // the pre-badge path with no Obx and no subscription.
      final String badgeCode = MenuBadge.codeFor(item);
      gridComponent.add(Builder(
        builder: (BuildContext context) {
          // ONE definition of the card so the tap body below is written once.
          Widget buildCard(int badgeCount) => menuIconCard(
            imageUrl: (item['url'] ?? defaultImage).toString(),
            label: (item['text'] ?? '').toString(),
            fontSize: fontSize,
            badgeCount: badgeCount,
            onTap: () {
              final route = item['route'];
              if (route != null &&
                  route != rootThis.pageName &&
                  routeExist(route)) {
                // MENU BADGE: stamp "visited now" INSIDE the navigate guard and
                // BEFORE routeStack.push — a tap that does not navigate (same
                // page, unknown route) must NOT clear the badge. This is not a
                // navigation call, so routeStack.push remains first among the
                // navigation calls (the AppBar back button pops routeStack, not
                // the Flutter Navigator). Runs off build, so the seenRev bump
                // is safe.
                MenuBadge.markSeen(route.toString());
                routeStack.push(route);
                if (route.length >= 4 &&
                    route.substring(0, 4).toLowerCase() == 'http') {
                  openInWebView(context, route, item['title'] ?? 'Web');
                } else {
                  var state = transactionStore.state.screenTx;
                  if (state['#REFRESH']) {
                    oldSettingUpShouldBeDeleted().then((aRes) {
                      var lifKey =
                          transactionStore.state.screenTx['#INTERFACE_KEY'];
                      readSettings(lifKey, 1).then((_) {
                        transactionStore.dispatch(UpdateScreenTxAction(
                            ScreenTransaction({'#REFRESH': false})));
                        List<Widget> newElementList = reloadPage(route);
                        rootThis.setState(() {
                          rootThis.pageName = route;
                          rootThis.pageElements = newElementList;
                          rootThis.wait = false;
                        });
                      });
                    });
                  } else {
                    List<Widget> newElementList = reloadPage(route);
                    rootThis.setState(() {
                      rootThis.pageName = route;
                      rootThis.pageElements = newElementList;
                      rootThis.wait = false;
                      // legacy quirk kept verbatim: only the first grid item
                      // toggled the touch flag before the dedup rewrite
                      if (first) {
                        rootThis.touch = !rootThis.touch;
                      }
                    });
                  }
                }
              }
            },
          );
          // No badgeTable on this child -> exactly the pre-change widget tree:
          // badgeCount 0 takes menuIconCard's original SizedBox/displayImage
          // subtree, and there is no Obx and no subscription.
          if (badgeCode.isEmpty) return buildCard(0);
          return Obx(() {
            // ★ FIRST unconditional observable reads. An Obx closure that
            // registers ZERO observables throws "[Get] the improper use of a
            // GetX has been detected" — NEVER hoist a guard, early return,
            // ternary or `??` short-circuit above these two lines.
            //
            // RxMap.operator[] routes through the reporting `value` getter
            // (get-4.7.3 rx_map.dart:29), so this registers even while `code`
            // is absent from the map — which is exactly the first-frame case.
            final List<Map<String, dynamic>> docs =
                List<Map<String, dynamic>>.from(
                    mapTableContent[badgeCode] ??
                        const <Map<String, dynamic>>[]);
            // Repaint dependency for markSeen(); `prefs` is not reactive.
            MenuBadge.seenRev.value;
            return buildCard(MenuBadge.countFor(
              badgeTable: (item['badgeTable'] ?? '').toString(),
              docs: docs,
              // RAW — filterDriverHomeDocs runs autheniumDecode internally.
              rawSearch: (item['badgeSearch'] ?? '').toString(),
              tsField: (item['badgeTs'] ?? '').toString(),
              seen: MenuBadge.seenEpoch((item['route'] ?? '').toString()),
              scrName: scrName,
            ));
          });
        },
      ));
    } catch (_) {
      gridComponent.add(menuIconCard(
        imageUrl: errorUrl,
        label: '--GRID--',
        fontSize: 10,
        onTap: () {},
      ));
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
  String dimmedImage =
      'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/c%2Fautsorz%2Fring-icon-dimmed-90x90.png?alt=media&token=73ddfd91-0286-409f-be1d-86dbc7f8ee3a';
  return Opacity(
    opacity: 0.55,
    child: menuIconCard(
      imageUrl: (url == '') ? dimmedImage : url,
      label: iText,
      fontSize: fontSize,
      onTap: () {},
    ),
  );
} // end of DisabledIcon
