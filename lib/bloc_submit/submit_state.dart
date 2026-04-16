import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import './bloc.dart';

@immutable
abstract class SubmitState extends Equatable {
  const SubmitState();
  @override
  List<Object> get props => [];
}

class SubmitLoading extends SubmitState {
  @override
  String toString() => 'SubmitLoading';
}

class SubmitLoaded extends SubmitState {
  final List<Submit> submit;

  const SubmitLoaded([this.submit = const []]);
//      : super([messages]);

  @override
  List<Object> get props => [submit]; // This line make messages updated lively

  @override
  String toString() =>
      'SubmitLoaded { Submit: $submit}';
}

class SubmitNotLoaded extends SubmitState {
  @override
  String toString() => 'SubmitNotLoaded';
}
