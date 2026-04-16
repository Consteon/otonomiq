import 'dart:async';
import 'package:bloc/bloc.dart';
import './bloc.dart';

class MessageBloc extends Bloc<MessageEvent, MessageState> {
  final MessageRepository _messageRepository;
  StreamSubscription? _messageSubscription;

  MessageBloc({required MessageRepository messageRepository})
      : _messageRepository = messageRepository, super(MessageLoading());

  MessageState get initialState => MessageLoading();

  @override
  Stream<MessageState> mapEventToState(
      MessageEvent event,
      ) async* {
    if(event is LoadMessage) {
      yield* _mapLoadMessageToState();
    } else if(event is AddMessage) {
      yield* _mapAddMessageToState(event);
    } else if(event is UpdateMessage) {
      yield* _mapUpdateMessageToState(event);
    } else if(event is DeleteMessage) {
      yield* _mapDeleteMessageToState(event);
    } else if(event is MessageUpdated) {
      yield* _mapMessageUpdatedToState(event);
    }
  }

  Stream<MessageState> _mapLoadMessageToState() async* {
    yield MessageLoading();
    _messageSubscription?.cancel();
    _messageSubscription = _messageRepository.messages().listen(
          (messages) {
        add(
          MessageUpdated(messages),
        );
      },
    );
  }

  Stream<MessageState> _mapAddMessageToState(AddMessage event) async* {
    _messageRepository.addNewMessage(event.messages);
  }

  Stream<MessageState> _mapUpdateMessageToState(UpdateMessage event) async* {
    _messageRepository.updateMessage(event.messages);
  }

  Stream<MessageState> _mapDeleteMessageToState(DeleteMessage event) async* {
    _messageRepository.deleteMessage(event.messages);
  }

  Stream<MessageState> _mapMessageUpdatedToState(MessageUpdated event) async* {
//    event.messages.sort((a,b) => a.lastMessageTime.compareTo(b.lastMessageTime));
    yield MessageLoaded(event.messages);
  }
}


