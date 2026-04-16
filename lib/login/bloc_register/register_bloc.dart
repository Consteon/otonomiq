// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'dart:async';
import 'package:bloc/bloc.dart';
//import 'package:rxdart/rxdart.dart';
import '../../login/api/user_repository.dart';
import '../../login/page/login/validator.dart';
import '../../login/page/register/register.dart';

class RegisterBloc extends Bloc<RegisterEvent, RegisterState> {
  final UserRepository _userRepository;

  RegisterBloc({required UserRepository userRepository})
      : _userRepository = userRepository, super(RegisterState.empty());

//  @override
//  RegisterState get initialState => RegisterState.empty();

//  @override
//  Stream<RegisterState> transform(
//      Stream<RegisterEvent> events,
//      Stream<RegisterState> Function(RegisterEvent event) next,
//      ) {
//    final observableStream = events as Observable<RegisterEvent>;
//    final nonDebounceStream = observableStream.where((event) {
//      return (event is! EmailChanged && event is! PasswordChanged);
//    });
//    final debounceStream = observableStream.where((event) {
//      return (event is EmailChanged || event is PasswordChanged);
//    }).debounceTime(Duration(milliseconds: 300));
//    return super.transform(nonDebounceStream.mergeWith([debounceStream]), next);
//  }

  @override
  Stream<RegisterState> mapEventToState(
      RegisterEvent event,
      ) async* {
    if (event is EmailChanged) {
      yield* _mapEmailChangedToState(event.email);
    } else if (event is PasswordChanged) {
      yield* _mapPasswordChangedToState(event.password);
    } else if (event is Submitted) {
      yield* _mapFormSubmittedToState(event.email, event.password);
    } else if (event is VidChanged) {
      yield* _mapVidChangedToState(event.vid);
    }else if (event is PinChanged) {
      yield* _mapPinChangedToState(event.pin);
    }
  }

  Stream<RegisterState> _mapEmailChangedToState(String email) async* {
    yield state.update(
      isEmailValid: Validators.isValidEmail(email),
    );
  }

  Stream<RegisterState> _mapPasswordChangedToState(String password) async* {
    yield state.update(
      isPasswordValid: Validators.isValidPassword(password),
    );
  }

  Stream<RegisterState> _mapFormSubmittedToState(
      String email,
      String password,
      ) async* {
    yield RegisterState.loading();
    try {
      await _userRepository.signUp(
        email: email,
        password: password,
      );
      yield RegisterState.success();
    } catch (_) {
      yield RegisterState.failure();
    }
  }

  Stream<RegisterState> _mapVidChangedToState(String vid) async* {
    yield state.update(
      isVidValid: Validators.isValidPassword(vid),
    );
  }

  Stream<RegisterState> _mapPinChangedToState(String vid) async* {
    yield state.update(
      isPinValid: Validators.isValidPassword(vid),
    );
  }
}
