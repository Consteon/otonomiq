import 'global.dart';
import 'redux/screen_transaction.dart';

class RouteStack {
  late List<String> routeStack;

  RouteStack(String bottom) {
    routeStack = [bottom];
  }

  void push(String scrName) {
    if (scrName == home) {
      routeStack = routeStack.sublist(0,1);
    } else {
      if (routeStack.last != scrName) {
        if (linkElement[scrName] != null){
          routeStack.add(scrName);
        }
      }
    }
  }

  String pop() {
    // #CAMERA:true will deactivate refresh button. Reset #CAMERA when change page
    //   page _OtqQR1 is dedicated for qr. Press back will cancel the qr operation
    //     so, #CAMERA flag should reset to false
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction(
        {'#CAMERA': false})));
    String last;
    if (routeStack.length <= 1) {
      last = routeStack[0];
    } else {
      last = routeStack.removeLast();
      last = routeStack.last;
    }
    return last;
  }

  String get() {
    // get current page
    String last;
    if (routeStack.length <= 1) {
      last = routeStack[0];
    } else {
      last = routeStack.last;
    }
    return last;
  }

  String popAll() {
    routeStack = routeStack.sublist(0,1);
    return routeStack[0];
  }
}
