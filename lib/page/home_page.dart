import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import '../global.dart';
import '../api.dart';
import '../otq_icons.dart';
import '../widget/otq_bottom_nav_bar.dart';
import '../widget/ui_component.dart';
import '../redux/screen_transaction.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc_timer/bloc.dart';
import '../page/wait_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({required Key key, required this.pageName}) : super(key: key);
  //  AnyPage({Key key, this.store, this.pageName}) : super(key: key);
  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".
  final String pageName;
  // final List<Widget> component;
  //  final DevToolsStore store;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  Key key = UniqueKey();

//  var pageState = 1;
//  var lastPageState = 1; // 1=init
//  var state;

//  final _formKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    // double gridWith = 25;
    // double mainVerticalSpacing = 1;
    // double gridSize = 120;
    // double gridRow = 2;
    // double gridFontSize = 12;
    // double gridWidth = 100;
    // double bannerImageAspectRatio = 4 / 1;
    // double bannerAspectRatio = 1.08 / bannerImageAspectRatio;
    var state0 = transactionStore.state.screenTx;
    if (widget.pageName != state0['#CURRENT_ROUTE']) {
//      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
//          {'#CURRENT_ROUTE': widget.pageName}))); // set state #CURRENT_ROUTE
    }
    var title = screenUIComponent[widget.pageName]['title'];
    double lPad = systemUIComponent['Mobile']['leftPad'].toDouble();
    double tPad = systemUIComponent['Mobile']['topPad'].toDouble();
    double rPad = systemUIComponent['Mobile']['rightPad'].toDouble();
    double bPad = systemUIComponent['Mobile']['bottomPad'].toDouble();
    rootThis = this;
    List<Widget> page;
//    var page = buildPage(context,
//        screenUIComponent[widget.pageName]['children'], widget.pageName);

    appRefresh() {
      var state = transactionStore.state.screenTx;
      if (state['#REFRESH']) {
        oldSettingUpShouldBeDeleted().then((aRes) {
          var state = transactionStore.state;
          var lifKey = state.screenTx['#INTERFACE_KEY'];
          readSettings(lifKey, 1).then((_) {
            setState(() {
              key = UniqueKey();
            });
          });
        });
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
            {'#REFRESH': false}))); // set state #INTERFACE_KEY
      }
    }

    void handleNavTap(int i) {
      appRefresh();
      var pgName = systemUIComponent[mobile]['bottomBar'][i]['route'];
      if (pgName == home) {
        transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
            {'#CURRENT_ROUTE': pgName})));
        Navigator.popUntil(
            context, ModalRoute.withName(Navigator.defaultRouteName));
      } else {
        gotoRoute(pgName);
      }
    }

    return StoreConnector<ScreenTransaction, ScreenTransaction>(
      converter: (transactionStore) => transactionStore.state,
      builder: (context, list) {
//        return
//          BlocBuilder<TimerBloc, TimerState>(
//          condition: (previousState, currentState) =>
//              currentState.runtimeType != previousState.runtimeType,
//          builder: (context2, state) {
        Scaffold v;
//        TimerBloc timerBloc = _state['#TIMER_BLOC']; // timer bloc from main
//        if (state is Finished) {}
        page = buildPage(
            screenUIComponent[widget.pageName]['children'], widget.pageName);
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
                    readSettings(lifKey, 1).then((_) {});
                  });
                },
              ),
            ],
          ),
          bottomNavigationBar: OtqBottomNavBar(
            selectedIndex: 0,
            items: (systemUIComponent[mobile]['bottomBar'] as List)
                .map<OtqNavItem>((item) {
              final iconKey = item['icon'].toString();
              final route = item['route']?.toString() ?? '';
              final label = item['label']?.toString() ??
                  route.replaceAll('_', ' ');
              return OtqNavItem(
                icon: otqIcons[iconKey] ?? Icons.circle_outlined,
                label: label,
              );
            }).toList(),
            onTap: handleNavTap,
          ),
          body: Stack(
            children: <Widget>[
              Container(
                padding: EdgeInsets.fromLTRB(lPad, tPad, rPad, bPad),
                child: Builder(
                  builder: (context) => ListView.builder(
                    key: const PageStorageKey(
                        'MyHomePage'), // use PageStorageKey to preserve scroll offset
                    controller: myScrollController,
                    itemCount: page.length,
                    itemBuilder: (context, position) {
                      return page[position];
                    },
                  ),
                ),
              ),
              BlocBuilder<TimerBloc, TimerState>(
                buildWhen: (previousState, currentState) =>
                currentState.runtimeType != previousState.runtimeType,
                builder: (context, state) {
                  StatelessWidget ret;
                  if (state is Running) {
                    ret = const WaitScreen();
                  } else {
                    if (state is Finished) {
                      oldSettingUpShouldBeDeleted().then((aRes) {
                        var state = transactionStore.state;
                        var lifKey = state.screenTx['#INTERFACE_KEY'];
                        readSettings(lifKey, 1).then((_) {
                          key = UniqueKey();
                          var state0 = transactionStore.state.screenTx;
                          var nxPage = state0['#NEXTROUTE'];
                          transactionStore.dispatch(UpdateScreenTxAction(
                              ScreenTransaction({
                                '#CURRENT_ROUTE': nxPage
                              }))); // set state #CURRENT_ROUTE
                          page = buildPage(
                              screenUIComponent[nxPage]['children'], nxPage);
                          title = screenUIComponent[nxPage]['title'];
                          try {
                            myScrollController.jumpTo(0.0);
                          } catch (e) {
                            // do nothing
                          }
                          state0['#TIMER_BLOC']
                              .dispatch(Reset()); // reset timer state to Ready
                        });
                      });
                    }
                    ret = const SizedBox(
                      width: 0.0,
                      height: 0.0,
                    ) as StatelessWidget;
                  }
                  return ret;
                },
              ),
            ],
          ),
        );
        return v;
      },
    );
  }
}
