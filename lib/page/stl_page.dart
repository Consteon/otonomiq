import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import '../global.dart';
import '../api.dart';
import '../otq_icons.dart';
import '../widget/ui_component.dart';
import '../redux/screen_transaction.dart';
import '../bloc_timer/bloc.dart';
import '../page/wait_screen.dart';

class StlPage extends StatelessWidget {
  const StlPage({super.key, required this.pageName, this.timerState, required this.component});
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
    double hPad = 8; // TODO get parameter from mobile sheet
    double vPad = 4;
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
          readSettings(lifKey,1).then((_) {
//            this.setState(() {    // TODO change to bloc dispatch
//              key = UniqueKey();
//            });
          });
        });
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
            {'#REFRESH': false}))); // set state #INTERFACE_KEY
      }
    }

    List<Widget> buildBottomIcon() {
      var bottomIcon = [
        IconButton(
          icon: Icon(otqIcons[systemUIComponent[mobile]['bottomBar'][0]['icon'].toString()]),
          onPressed: () {
            appRefresh();
            var pgName = systemUIComponent[mobile]['bottomBar'][0]['route'];
            if (pgName == home) {
              transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
                  {'#CURRENT_ROUTE': pgName}))); // set state #CURRENT_ROUTE
              Navigator.popUntil(
                  context, ModalRoute.withName(Navigator.defaultRouteName));
            } else {
              gotoRoute(pgName);
            }
          },
        )
      ];
      for (var i = 1; i < systemUIComponent[mobile]['bottomBar'].length; i++) {
        bottomIcon.add(IconButton(
          icon: Icon(otqIcons[systemUIComponent[mobile]['bottomBar'][i]['icon'].toString()]),
          onPressed: () {
            appRefresh();
            var pgName = systemUIComponent[mobile]['bottomBar'][i]['route'];
            if (pgName == home) {
              transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
                  {'#CURRENT_ROUTE': pgName}))); // set state #CURRENT_ROUTE
              Navigator.popUntil(
                  context, ModalRoute.withName(Navigator.defaultRouteName));
            } else {
              gotoRoute(pgName);
            }
          },
        ));
      }
      return bottomIcon;
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
            readSettings(lifKey,1).then((_) {
              constructAllNotHomePagesSync();
              var state0 = transactionStore.state.screenTx;
              var nxPage = state0['#NEXTROUTE'];
              transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
                  {'#CURRENT_ROUTE': nxPage}))); // set state #CURRENT_ROUTE
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
                      readSettings(lifKey,1).then((_) {
                        constructAllNotHomePages();
                        timerBloc.add(Reset()); // reset timer state to Ready
                      });
                    });
                  },
                ),
              ],
            ),
            bottomNavigationBar: BottomAppBar(
              child: Container(
                padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: buildBottomIcon(),
                ),
              ),
            ),
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
                      readSettings(lifKey,1).then((_) {
                        timerBloc.add(Reset()); // reset timer state to Ready
                      });
                    });
                  },
                ),
              ],
            ),
            bottomNavigationBar: BottomAppBar(
              child: Container(
                padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: buildBottomIcon(),
                ),
              ),
            ),
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
