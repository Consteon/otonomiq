import 'dart:async';
import 'package:bloc/bloc.dart';
import './bloc.dart';
//import 'package:meta/meta.dart';

class SubmitBloc extends Bloc<SubmitEvent, SubmitState> {
  final SubmitRepository _submitRepository;
  // ignore: cancel_subscriptions
  StreamSubscription? _messageSubscription;

  SubmitBloc({required SubmitRepository submitRepository})
      : _submitRepository = submitRepository,
        super(SubmitNotLoaded());

  SubmitState get initialState => SubmitLoading();

  @override
  Stream<SubmitState> mapEventToState(
    SubmitEvent event,
  ) async* {
    if (event is LoadSubmit) {
      yield* _mapLoadSubmitToState();
    } else if (event is AddSubmit) {
      yield* _mapAddMessageToState(event);
    } else if (event is UpdateSubmit) {
      yield* _mapUpdateMessageToState(event);
    } else if (event is DeleteSubmit) {
      yield* _mapDeleteMessageToState(event);
    } else if (event is SubmitUpdated) {
      yield* _mapSubmitUpdatedToState(event);
    }
  }

  Stream<SubmitState> _mapLoadSubmitToState() async* {
    yield SubmitLoading();
    // if (_messageSubscription != null){
    //   await _messageSubscription!.cancel();
    //   _messageSubscription = null;
    // }
    // _messageSubscription = _submitRepository.submit().listen(
    //   (messages) {
    //     add(
    //       SubmitUpdated(messages),
    //     );
    //   },
    // );
    /*
    _messageSubscription ??= _submitRepository.submit().listen(
            (messages) {
              add(
                SubmitUpdated(messages),
              );
            },
          ); // end if (_messageSubscription == null)

     */
  }// end of _mapLoadSubmitToState

  Stream<SubmitState> _mapAddMessageToState(AddSubmit event) async* {
    // _submitRepository.addNewSubmit(event.submit);
    _submitRepository.addNewSubmit2(event.submit);
  }

  Stream<SubmitState> _mapUpdateMessageToState(UpdateSubmit event) async* {
    _submitRepository.updateSubmit(event.submit);
  }

  Stream<SubmitState> _mapDeleteMessageToState(DeleteSubmit event) async* {
    _submitRepository.deleteSubmit(event.submit);
  }

  Stream<SubmitState> _mapSubmitUpdatedToState(SubmitUpdated event) async* {
//    event.messages.sort((a,b) => a.lastMessageTime.compareTo(b.lastMessageTime));
  /*
    for (var rec in event.submit) {
      if (rec.st == 101) {
        // record already appended and processed
        if (kDebugMode) {
          devPrint('Deleting ${rec.ss})');
        }
        _submitRepository.deleteSubmit(rec); // delete event record in firestore
        setDataOK('1'); // reload and set green light
      }
    }
    */
    yield SubmitLoaded(event.submit);
  }
}
