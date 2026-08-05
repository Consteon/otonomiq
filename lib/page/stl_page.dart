import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import '../api.dart';
import '../bloc_timer/bloc.dart';
import '../global.dart';
import '../otq_icons.dart';
import '../page/wait_screen.dart';
import '../redux/screen_transaction.dart';
import '../widget/otq_bottom_nav_bar.dart';
import '../widget/ui_component.dart';

class StlPage extends StatelessWidget {
  const StlPage({
    super.key,
    required this.pageName,
    this.timerState,
    required this.component,
  });
  //  AnyPage({Key key, this.store, this.pageName}) : super(key: key);
  // This widget is the home page of application. It is stateless.
  // This page is rebuild when pageName = refreshState.

  final String pageName;
  final timerState;
  final List<Widget> component;
  //  final DevToolsStore store;

  @override
  Widget build(BuildContext context) {
    double gridWith = 25;
    double mainVerticalSpacing = 1;
    double gridSize = 120;
    double gridRow = 2;
    double gridFontSize = 12;
    double gridWidth = 100;
    double bannerImageAspectRatio = 4 / 1;
    double bannerAspectRatio = 1.08 / bannerImageAspectRatio;
    var state0 = transactionStore.state.screenTx;
    var state = timerState;
    var title = screenUIComponent[pageName]['title'];
    double lPad = systemUIComponent['Mobile']['leftPad'].toDouble();
    double tPad = systemUIComponent['Mobile']['topPad'].toDouble();
    double rPad = systemUIComponent['Mobile']['rightPad'].toDouble();
    double bPad = systemUIComponent['Mobile']['bottomPad'].toDouble();
    rootThis = this;
    List<Widget> page;
    //    var page = buildPage(context,
    //        screenUIComponent[widget.pageName]['children'], widget.pageName);
    ScrollController scrollController = ScrollController();

    appRefresh() {
      var state = transactionStore.state.screenTx;
      if (state['#REFRESH']) {
        oldSettingUpShouldBeDeleted().then((aRes) {
          var state = transactionStore.state;
          var lifKey = state.screenTx['#INTERFACE_KEY'];
          readSettings(lifKey, 1).then((_) {
            //            this.setState(() {    // change to bloc dispatch
            //              key = UniqueKey();
            //            });
          });
        });
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#REFRESH': false})),
        ); // set state #INTERFACE_KEY
      }
    }

    void handleNavTap(int i) {
      appRefresh();
      var pgName = systemUIComponent[mobile]['bottomBar'][i]['route'];
      if (pgName == home) {
        transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'#CURRENT_ROUTE': pgName})),
        );
        Navigator.popUntil(
          context,
          ModalRoute.withName(Navigator.defaultRouteName),
        );
      } else {
        gotoRoute(pgName);
      }
    }

    OtqBottomNavBar buildNavBar() {
      return OtqBottomNavBar(
        selectedIndex: 0,
        items: (systemUIComponent[mobile]['bottomBar'] as List).map<OtqNavItem>(
          (item) {
            final iconKey = item['icon'].toString();
            final route = item['route']?.toString() ?? '';
            final label =
                item['label']?.toString() ?? route.replaceAll('_', ' ');
            return OtqNavItem(
              icon: otqIcons[iconKey] ?? Icons.circle_outlined,
              label: label,
            );
          },
        ).toList(),
        onTap: handleNavTap,
      );
    }

    return StoreConnector<ScreenTransaction, ScreenTransaction>(
      converter: (transactionStore) => transactionStore.state,
      builder: (context, list) {
        Scaffold v;

        TimerBloc timerBloc = state0['#TIMER_BLOC']; // timer bloc from main
        if (state is Finished) {
          oldSettingUpShouldBeDeleted().then((aRes) {
            var state = transactionStore.state;
            var lifKey = state.screenTx['#INTERFACE_KEY'];
            readSettings(lifKey, 1).then((_) {
              constructAllNotHomePagesSync();
              var state0 = transactionStore.state.screenTx;
              var nxPage = state0['#NEXTROUTE'];
              transactionStore.dispatch(
                UpdateScreenTxAction(
                  ScreenTransaction({'#CURRENT_ROUTE': nxPage}),
                ),
              ); // set state #CURRENT_ROUTE
              page = buildPage(screenUIComponent[nxPage]['children'], nxPage);
              title = screenUIComponent[nxPage]['title'];
              try {
                scrollController.jumpTo(0.0);
              } catch (e) {}
              timerBloc.add(Reset()); // reset timer state to Ready
            });
          });
        }
        page = buildPage(screenUIComponent[pageName]['children'], pageName);
        if (state is Ready) {
          v = Scaffold(
            key: key,
            appBar: AppBar(
              // Here we take the value from the MyHomePage object that was created by
              // the App.build method, and use it to set our appbar title.
              title: Text(title),
              actions: <Widget>[
                IconButton(
                  icon: bitIcon,
                  onPressed: () {
                    oldSettingUpShouldBeDeleted().then((aRes) {
                      var state = transactionStore.state;
                      var lifKey = state.screenTx['#INTERFACE_KEY'];
                      readSettings(lifKey, 1).then((_) {
                        constructAllNotHomePages();
                        timerBloc.add(Reset()); // reset timer state to Ready
                      });
                    });
                  },
                ),
              ],
            ),
            bottomNavigationBar: buildNavBar(),
            body: Container(
              padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
              child: Builder(
                builder: (context) => ListView.builder(
                  controller: scrollController,
                  itemCount: page.length,
                  itemBuilder: (context, position) {
                    return page[position];
                  },
                ),
              ),
            ),
          );
        } else {
          v = Scaffold(
            key: key,
            appBar: AppBar(
              title: Text(title),
              actions: <Widget>[
                IconButton(
                  icon: bitIcon,
                  onPressed: () {
                    oldSettingUpShouldBeDeleted().then((aRes) {
                      var state = transactionStore.state;
                      var lifKey = state.screenTx['#INTERFACE_KEY'];
                      readSettings(lifKey, 1).then((_) {
                        timerBloc.add(Reset()); // reset timer state to Ready
                      });
                    });
                  },
                ),
              ],
            ),
            bottomNavigationBar: buildNavBar(),
            body: Stack(
              children: <Widget>[
                Container(
                  padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
                  child: Builder(
                    builder: (context) => ListView.builder(
                      controller: scrollController,
                      itemCount: page.length,
                      itemBuilder: (context, position) {
                        return page[position];
                      },
                    ),
                  ),
                ),
                const WaitScreen(),
              ],
            ),
          );
        }
        return v;
      },
    );
  }
}
