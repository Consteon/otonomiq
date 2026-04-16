import '../redux/link_state.dart';

List<LinkState> linkReducers(List<LinkState> tx, dynamic action) {
  if (action is AddScreenKeyAction) {
    return addScreenKey(tx, action);
  // } else if (action is AddScreenRowAction) {
  //   return addScreenRow(tx, action);
  }
  return tx;
} // end of tx Reducers

List<LinkState> addScreenKey(
    List<LinkState> tx, AddScreenKeyAction action) {

  return List.from(tx)..add(action.screenRecord);
} // end of addScreenKey

// List<LinkState> addScreenRow(
//     List<LinkState> tx, AddScreenRowAction action) {
//   List<LinkState> screenRowNew =
//        // tx.map((tx) => tx.screen == action.screen ? action.screen : tx).toList();
//   tx.map((trans) => trans.screen == action.screen ? action.screen : trans).toList();
//   // TODO put proper add row here
//   return screenRowNew;
// } // end of addScreenRow

/*
  Method txReducers() delegates the action to proper methods.
  All methods(addScreenKey,addScreenRow) return new lists?????????that???s our
  new application state. As you can see, you shouldn???t modify current list.
  Instead of it, we create new lists every time.
 */

