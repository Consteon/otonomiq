import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
abstract class TimerState extends Equatable {
  const TimerState();
  final int duration=0;

  @override
  List<Object> get props => [];
}
//abstract class TimerState extends Equatable {
//  final int duration;
//
//  TimerState(this.duration, [List props = const []])
//      : super([duration]..addAll(props));
//}

class Ready extends TimerState {
  const Ready(int duration);// : super(duration);

  @override
  String toString() => 'Ready { duration: $duration }';
}

class Paused extends TimerState {
  const Paused(int duration);// : super(duration);

  @override
  String toString() => 'Paused { duration: $duration }';
}

class Running extends TimerState {
  const Running(int duration);// : super(duration);

  @override
  String toString() => 'Running { duration: $duration }';
}

class Finished extends TimerState {
  const Finished();// : super(0);

  @override
  String toString() => 'Finished';
}

class StandBy extends TimerState {
  const StandBy();// : super(0);

  @override
  String toString() => 'StandBy';
}
