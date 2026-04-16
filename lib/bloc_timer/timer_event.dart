import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
abstract class TimerEvent extends Equatable {
  const TimerEvent();
  @override
  List<Object> get props => [];
}
//abstract class TimerEvent extends Equatable {
//  TimerEvent([List props = const []]) : super(props);
//}

class Start extends TimerEvent {
  final int duration;

  const Start({required this.duration});// : super([duration]);

  @override
  String toString() => "Start { duration: $duration }";
}

class Pause extends TimerEvent {
  @override
  String toString() => "Pause";
}

class Resume extends TimerEvent {
  @override
  String toString() => "Resume";
}

class Reset extends TimerEvent {
  @override
  String toString() => "Reset";
}

class Quiet extends TimerEvent {
  @override
  String toString() => "Quiet";
}

class Tick extends TimerEvent {
  final int duration;

  const Tick({required this.duration});// : super([duration]);

  @override
  String toString() => "Tick { duration: $duration }";
}
