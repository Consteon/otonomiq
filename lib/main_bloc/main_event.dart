import 'package:meta/meta.dart';
import 'package:equatable/equatable.dart';

@immutable
abstract class MainEvent extends Equatable {
  const MainEvent();
  @override
  List<Object> get props => [];
}
//abstract class MainEvent extends Equatable {
//  MainEvent([List props = const []]) : super(props);
//}

class ResetAll extends MainEvent {
  const ResetAll();// : super([]);
  @override
  String toString() => 'ResetAll {}';
}

class NeedPinHash extends MainEvent {
  @override
  String toString() => 'NeedPinHash {}';
}

class NewPinSubmit extends MainEvent {
  final String pin;

  const NewPinSubmit({
    required this.pin,
  });// : super([pin]);
  @override
  String toString() => 'NewPinSubmit {pin: $pin}';
}

class PinSubmit extends MainEvent {
  final String pin;
  final String errorMid;
  final String screenJson;
  final String route;
  final String scrName;
  final String mainTid;
  final String notifyText;
  final String targetVids;
  final String from;
  final String data;

  const PinSubmit({
    required this.pin,
    required this.errorMid,
    required this.screenJson,
    required this.route,
    required this.scrName,
    required this.mainTid,
    required this.notifyText,
    required this.targetVids,
    required this.from,
    required this.data,
  });

  @override
  String toString() => 'PinSubmit {pin: *****, '
      'errorMid: $errorMid, payload: $screenJson, '
      'route: $route, scrName: $scrName, mainTid: $mainTid, notifyText: $notifyText'
      ', targetVids: ${targetVids.toString()}, from: $from, data: ${data.toString()}}';
}

class WrongPin extends MainEvent {
  final String message1;
  final String message2;

  const WrongPin({required this.message1, required this.message2});
//      : super([message1, message2]);
  @override
  String toString() => 'WrongPin {message1 : $message1, message2 : $message2}';
}

class QrAttend1Scan extends MainEvent {
  final bool? front;
  final bool? flash;
  final int? size;
  final int? fSize;
  final int? exitSize;
  final String? exitRoute;
  final String? crypto;
  final String? exitString;
  final int? position;
  final String? screenName;
  final int? secBefore;
  final int? secInterval;

  const QrAttend1Scan({
    this.front,
    this.flash,
    this.size,
    this.fSize,
    this.exitSize,
    this.exitRoute,
    this.crypto,
    this.exitString,
    this.position,
    this.screenName,
    this.secBefore,
    this.secInterval,
  });

  @override
  String toString() => 'ContinuousScan {front: $front, flash: $flash, '
      'size: $size, fSize: $fSize, exitSize: $exitSize, exitRoute: $exitRoute, '
      'crypto: $crypto, exitString: $exitString, position: $position, screenName: $screenName}';
}

class ScanResult extends MainEvent {
  final bool? front;
  final bool? flash;
  final int? size;
  final int? fSize;
  final int? exitSize;
  final String? exitRoute;
  final String? crypto;
  final String? exitString;
  final String? result;
  final int? position;
  final String? scrName;

  const ScanResult({
    this.front,
    this.flash,
    this.size,
    this.fSize,
    this.exitSize,
    this.exitRoute,
    this.crypto,
    this.exitString,
    this.result,
    this.position,
    this.scrName,
  });// : super(
//            [front, flash, size, exitRoute, crypto, result, position, scrName]);
  @override
  String toString() => 'ContinuousScan {front: $front, flash: $flash, '
      'size: $size, fSize: $fSize, exitSize: $exitSize, exitRoute: $exitRoute, '
      'crypto: $crypto, exitString: $exitString, result: $result, position: $position, '
      'scrName: $scrName}';
}
