import '../global.dart';
import './bloc.dart';
import 'dart:async';
import 'package:bloc/bloc.dart';
import '../ticker.dart';

class TimerBloc extends Bloc<TimerEvent, TimerState> {
  static int initial = 10;
  final Ticker _ticker;
  final int _duration = initial;

  late StreamSubscription<int> _tickerSubscription;

  TimerBloc({required Ticker ticker})
      : _ticker = ticker, super(Ready(initial));

//  @override
//  TimerState get initialState => Ready(_duration);

  @override
  void onTransition(Transition<TimerEvent, TimerState> transition) {
    super.onTransition(transition);
    devPrint(transition);
  }

  @override
  Stream<TimerState> mapEventToState(
      TimerEvent event,
      ) async* {
    if (event is Start) {
      yield* _mapStartToState(event);
    } else if (event is Pause) {
      yield* _mapPauseToState(event);
    } else if (event is Resume) {
      yield* _mapResumeToState(event);
    } else if (event is Reset) {
      yield* _mapResetToState(event);
    } else if (event is Tick) {
      yield* _mapTickToState(event);
    } else if (event is Quiet) {
      yield* _mapQuietToState(event);
    }
  }

  //@override
  //void dispose() {
  //  _tickerSubscription?.cancel();
  //  super.dispose();
  //}

  Stream<TimerState> _mapStartToState(Start start) async* {
    yield Running(start.duration);
    try{
      _tickerSubscription.cancel();
    } catch (e){}
    _tickerSubscription = _ticker.tick(ticks: start.duration).listen(
          (duration) {
//        dispatch(Tick(duration: duration));
            Tick(duration: duration);
      },
    );
  }

  Stream<TimerState> _mapPauseToState(Pause pause) async* {
//    final state = currentState;
    if (state is Running) {
      _tickerSubscription.pause();
      yield Paused(state.duration);
    }
  }

  Stream<TimerState> _mapResumeToState(Resume pause) async* {
//    final state = currentState;
    if (state is Paused) {
      _tickerSubscription.resume();
      yield Running(state.duration);
    }
  }

  Stream<TimerState> _mapResetToState(Reset reset) async* {
//    final state = currentState;
    if (state is! Ready) {
      _tickerSubscription.cancel();
      yield Ready(_duration);
    }
  }

  Stream<TimerState> _mapTickToState(Tick tick) async* {
//    final state = currentState;
    if (state is Running) {
      yield tick.duration > 0 ? Running(tick.duration) : const Finished();
    }
  }

  Stream<TimerState> _mapQuietToState(Quiet quiet) async* {
//    final state = currentState;
    if (state is! StandBy) {
      _tickerSubscription.cancel();
      yield const StandBy();
    }
  }
}
