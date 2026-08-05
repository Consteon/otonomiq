import '../redux/link_state.dart';

List<LinkState> linkReducers(List<LinkState> tx, dynamic action) {
  if (action is AddScreenKeyAction) {
    return addScreenKey(tx, action);
    // } else if (action is AddScreenRowAction) {
    //   return addScreenRow(tx, action);
  }
  return tx;
} // end of tx Reducers

List<LinkState> addScreenKey(List<LinkState> tx, AddScreenKeyAction action) {
  return List.from(tx)..add(action.screenRecord);
} // end of addScreenKey
