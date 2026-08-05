import 'package:meta/meta.dart';

/*
  MainBloc will display something based on mainState
  mainState:
   0 = nothing interesting happens (default)
 -99 = no pin hash defined. Must display newPinPage
  -1 = Wrong Pin (txf - pin); display str1(title) & str2 on dialog box
   1 = Display continuous QR scanner for employee attendance,
     str1 = exitRoute, str2 = crypto, condition1 = front,
     condition2 = flash, action = action,
       subState:
         0 = scanning mode
         1 = get result (string result put in result1)
         2 = bloc give feedback (string feedback message put in result)
           result2 =  1 => short beep ACK
                     -1 => 2 short beep NACK
                     -2 => Alert sound
                     -3 => Panic sound
      action : position# to put in savesend
      option1 : seconds, before now
      option2 : seconds, interval after now() - option1
 */
@immutable
class MainState {
  final int mainState; // main application state
  final int subState; // state's sub state
  final String str1; // string to process, usually title
  final String str2; // string to process
  final String str3; // string to process
  final int option1; // option parameter, default = 0
  final int option2; // option2, default = 0
  final int option3; // optin3, default = 0
  final bool condition1; // condition parameter, default = false
  final bool condition2; // condition parameter, default = false
  final int action; // parameter for action
  final String result1; // the result, can be jason string
  final int result2; // result option in integer
  final int duration; // duration in second (when timer implemented)
  final String scrName; // screen name of the event

  // timer bloc inside MainBloc to utilize duration

  const MainState({
    required this.mainState,
    required this.subState,
    required this.str1,
    required this.str2,
    required this.str3,
    required this.option1,
    required this.option2,
    required this.option3,
    required this.condition1,
    required this.condition2,
    required this.action,
    required this.result1,
    required this.result2,
    required this.duration,
    required this.scrName,
  });

  factory MainState.empty() {
    return const MainState(
      mainState: 0,
      subState: 0,
      str1: '',
      str2: '',
      str3: '',
      option1: 0,
      option2: 0,
      option3: 0,
      condition1: false,
      condition2: false,
      action: 0,
      result1: '',
      result2: 0,
      duration: 0,
      scrName: '',
    );
  }

  factory MainState.contScan(
    String exitRoute,
    String crypto,
    bool front,
    bool flash,
    int position,
    String scrName,
    int size,
    int fSize,
    int exitSize,
    String exitString,
  ) {
    return MainState(
      mainState: 1,
      subState: 0,
      str1: exitRoute,
      str2: crypto,
      str3: exitString,
      option1: size,
      option2: fSize,
      option3: exitSize,
      condition1: front,
      condition2: flash,
      action: position,
      result1: '',
      result2: 0,
      duration: 0,
      scrName: scrName,
    );
  }

  factory MainState.scanFeedBack(
    String exitRoute,
    String crypto,
    bool front,
    bool flash,
    int action,
    String feedBackResult,
    int feedBackAction,
    int duration,
    String scrName,
    int size,
    int fSize,
    int exitSize,
    String exitString,
  ) {
    return MainState(
      mainState: 1,
      subState: 2,
      str1: exitRoute,
      str2: crypto,
      str3: exitString,
      option1: size,
      option2: fSize,
      option3: exitSize,
      condition1: front,
      condition2: flash,
      action: action,
      result1: feedBackResult,
      result2: feedBackAction,
      duration: duration,
      scrName: scrName,
    );
  }

  factory MainState.needPin() {
    return const MainState(
      mainState: 900,
      subState: 0,
      str1: '',
      str2: '',
      str3: '',
      option1: 0,
      option2: 0,
      option3: 0,
      condition1: false,
      condition2: false,
      action: 0,
      result1: '',
      result2: 0,
      duration: 0,
      scrName: '',
    );
  }

  factory MainState.wrongPin(String title, String message) {
    return MainState(
      mainState: -1,
      subState: 0,
      str1: title,
      str2: message,
      str3: '',
      option1: 0,
      option2: 0,
      option3: 0,
      condition1: false,
      condition2: false,
      action: 0,
      result1: '',
      result2: 0,
      duration: 0,
      scrName: '',
    );
  }

  MainState update({
    int? mainState,
    int? subState,
    String? str1,
    String? str2,
    String? str3,
    int? option1,
    int? option2,
    int? option3,
    bool? condition1,
    bool? condition2,
    int? action,
    String? result1,
    int? result2,
    int? duration,
    String? scrName,
  }) {
    return copyWith(
      mainState: mainState!,
      subState: subState!,
      str1: str1!,
      str2: str2!,
      str3: str3!,
      option1: option1!,
      option2: option2!,
      option3: option3!,
      condition1: condition1!,
      action: action!,
      result1: result1!,
      result2: result2!,
      duration: duration!,
      scrName: scrName!,
    );
  }

  MainState copyWith({
    int? mainState,
    int? subState,
    String? str1,
    String? str2,
    String? str3,
    int? option1,
    int? option2,
    int? option3,
    bool? condition1,
    bool? condition2,
    int? action,
    String? result1,
    int? result2,
    int? duration,
    String? scrName,
  }) {
    return MainState(
      mainState: mainState ?? this.mainState,
      subState: subState ?? this.subState,
      str1: str1 ?? this.str1,
      str2: str2 ?? this.str2,
      str3: str3 ?? this.str3,
      option1: option1 ?? this.option1,
      option2: option2 ?? this.option2,
      option3: option3 ?? this.option3,
      condition1: condition1 ?? this.condition1,
      condition2: condition2 ?? this.condition2,
      action: action ?? this.action,
      result1: result1 ?? this.result1,
      result2: result2 ?? this.result2,
      duration: duration ?? this.duration,
      scrName: scrName ?? this.scrName,
    );
  }

  @override
  String toString() {
    return '''MainState {
      mainState: $mainState, subState: $subState,
      message1: $str1, message2: $str2, str3 = $str3,
      option1: $option1, option2: $option2, option3: $option3
      condition1: $condition1, condition2: $condition2,
      action: $action,
      result1: $result1, result2: $result2,
      duration: $duration, scrName: $scrName
    }''';
  }
} // end of MainState
