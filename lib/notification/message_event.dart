import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import './bloc.dart';

@immutable
abstract class MessageEvent extends Equatable {
  const MessageEvent();
  @override
  List<Object> get props => [];
}
//abstract class MessageEvent extends Equatable {
//   MessageEvent([List props = const <dynamic>[]]) : super(props);
//}

class LoadMessage extends MessageEvent {
  @override
  String toString() => 'LoadMessages';
}

class AddMessage extends MessageEvent {
  final Message messages;

  const AddMessage(this.messages);// : super([messages]);

  @override
  String toString() => 'AddMessage { messages: $messages }';
}

class UpdateMessage extends MessageEvent {
  final Message messages;

  const UpdateMessage(this.messages);// : super([messages]);

  @override
  String toString() => 'UpdateMessage { UpdateMessage: $messages }';
}

class DeleteMessage extends MessageEvent {
  final Message messages;

  const DeleteMessage(this.messages);// : super([messages]);

  @override
  String toString() => 'DeleteMessage { message: $messages }';
}

class MessageClearCompleted extends MessageEvent {
  @override
  String toString() => 'MessageClearCompleted';
}

class MessageUpdated extends MessageEvent {
  final List<Message> messages;

  const MessageUpdated(this.messages);

  @override
  String toString() => 'MessageUpdated';
}
