// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/cupertino.dart';
import 'package:meta/meta.dart';

@immutable
class RegisterState {
  final bool isEmailValid;
  final bool isPasswordValid;
  final bool isSubmitting;
  final bool isSuccess;
  final bool isFailure;
  final bool isVidValid;
  final bool isPinValid;

  bool get isFormValid => isVidValid && isPinValid;

  const RegisterState({
    required this.isEmailValid,
    required this.isPasswordValid,
    required this.isSubmitting,
    required this.isSuccess,
    required this.isFailure,
    required this.isVidValid,
    required this.isPinValid,
  });

  factory RegisterState.empty() {
    return const RegisterState(
      isEmailValid: true,
      isPasswordValid: true,
      isSubmitting: false,
      isSuccess: false,
      isFailure: false,
      isVidValid: false,
      isPinValid: false,
    );
  }

  factory RegisterState.loading() {
    return const RegisterState(
      isEmailValid: true,
      isPasswordValid: true,
      isSubmitting: true,
      isSuccess: false,
      isFailure: false,
      isVidValid: false,
      isPinValid: false,
    );
  }

  factory RegisterState.failure() {
    return const RegisterState(
      isEmailValid: true,
      isPasswordValid: true,
      isSubmitting: false,
      isSuccess: false,
      isFailure: true,
      isVidValid: false,
      isPinValid: false,
    );
  }

  factory RegisterState.success() {
    return const RegisterState(
      isEmailValid: true,
      isPasswordValid: true,
      isSubmitting: false,
      isSuccess: true,
      isFailure: false,
      isVidValid: false,
      isPinValid: false,
    );
  }

  RegisterState update({
    bool? isEmailValid,
    bool? isPasswordValid,
    bool? isVidValid,
    bool? isPinValid,
  }) {
    return copyWith(
      isEmailValid: isEmailValid,
      isPasswordValid: isPasswordValid,
      isVidValid: isVidValid,
      isPinValid: isPinValid,
      isSubmitting: false,
      isSuccess: false,
      isFailure: false,
    );
  }

  RegisterState copyWith({
    bool? isEmailValid,
    bool? isPasswordValid,
    bool? isSubmitEnabled,
    bool? isSubmitting,
    bool? isSuccess,
    bool? isFailure,
    bool? isVidValid,
    bool? isPinValid,
  }) {
    return RegisterState(
      isEmailValid: isEmailValid ?? this.isEmailValid,
      isPasswordValid: isPasswordValid ?? this.isPasswordValid,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSuccess: isSuccess ?? this.isSuccess,
      isFailure: isFailure ?? this.isFailure,
      isVidValid: isVidValid ?? this.isVidValid,
      isPinValid: isPinValid ?? this.isPinValid,
    );
  }

  @override
  String toString() {
    return '''RegisterState {
      isEmailValid: $isEmailValid,
      isPasswordValid: $isPasswordValid,
      isSubmitting: $isSubmitting,
      isSuccess: $isSuccess,
      isFailure: $isFailure,
      isVidValid: $isVidValid,
      isPinValid: $isPinValid,
    }''';
  }
}
