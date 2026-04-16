
class LinkState {
  String screen;
  List<List<dynamic>> tx;

  LinkState(this.screen, this.tx);

  @override
  String toString() {
    return "Redux state store for Link apps $screen";
  }
} // end of ScreenTransaction

class AddScreenKeyAction {
  final LinkState screenRecord;

  AddScreenKeyAction(this.screenRecord);
} // end of AddScreenKey

class AddScreenRowAction {
  final String screen;

  AddScreenRowAction(this.screen);
}
