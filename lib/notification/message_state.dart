import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import './bloc.dart';

@immutable
abstract class MessageState extends Equatable {
  const MessageState();
  @override
  List<Object> get props => [];
}
//abstract class MessageState extends Equatable {
//  MessageState([List props = const <dynamic>[]]) : super(props);
//}

class MessageLoading extends MessageState {
  @override
  String toString() => 'MessageLoading';
}

class MessageLoaded extends MessageState {
  final List<Message> messages;

  const MessageLoaded([this.messages = const []]);
//      : super([messages]);

  @override
  List<Object> get props => [
    messages
  ]; // This line make messages updated lively

  @override
  String toString() =>
      'MessageLoaded { Messages: $messages}';
}

class MessagesNotLoaded extends MessageState {
  @override
  String toString() => 'MessagesNotLoaded';
}
