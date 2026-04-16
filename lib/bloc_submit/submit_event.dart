import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import './bloc.dart';

@immutable
abstract class SubmitEvent extends Equatable {
  const SubmitEvent();
  @override
  List<Object> get props => [];
}
//abstract class MessageEvent extends Equatable {
//   MessageEvent([List props = const <dynamic>[]]) : super(props);
//}

class LoadSubmit extends SubmitEvent {
  @override
  String toString() => 'LoadSubmit';
}

class AddSubmit extends SubmitEvent {
  final Submit submit;

  const AddSubmit(this.submit);// : super([submit]);

  @override
  String toString() => 'AddSubmit { submit: $submit }';
}

class UpdateSubmit extends SubmitEvent {
  final Submit submit;

  const UpdateSubmit(this.submit);// : super([submit]);

  @override
  String toString() => 'UpdateSubmit { UpdateSubmit: $submit }';
}

class DeleteSubmit extends SubmitEvent {
  final Submit submit;

  const DeleteSubmit(this.submit);// : super([submit]);

  @override
  String toString() => 'DeleteSubmit { submit: $submit }';
}

class MessageClearCompleted extends SubmitEvent {
  @override
  String toString() => 'SubmitClearCompleted';
}

class SubmitUpdated extends SubmitEvent {
  final List<Submit> submit;

  const SubmitUpdated(this.submit);

  @override
  String toString() => 'SubmitUpdated';
}
