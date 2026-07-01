import 'dart:async';

import 'package:bloc/bloc.dart';

import '../bloc_savesend/bloc.dart';
import '../global.dart';

class SavesendBloc extends Bloc<SavesendEvent, SavesendState> {
  SavesendBloc(SavesendState initialState) : super(const RebuildPage('a'));

  @override
  void onTransition(Transition<SavesendEvent, SavesendState> transition) {
    super.onTransition(transition);
    devPrint(transition);
  }

  @override
  Stream<SavesendState> mapEventToState(SavesendEvent event) async* {
    if (event is Update) {
      yield* _mapUpdateToState(event);
    }
  }

  Stream<SavesendState> _mapUpdateToState(Update update) async* {
    yield RebuildPage(update.rebuildPage);
  }
}
