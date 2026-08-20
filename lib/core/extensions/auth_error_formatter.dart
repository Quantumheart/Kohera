import 'dart:async';

import 'package:kohera/core/utils/network_error_native.dart';

class AuthErrorFormatter {
  const AuthErrorFormatter._();

  static const _networkErrorMessage = 'Could not reach server';
  static const _timeoutMessage = 'Connection timed out';
  static const _invalidResponseMessage = 'Invalid server response';

  static String friendlyAuthError(Object error) {
    if (isNetworkError(error)) return _networkErrorMessage;

    return switch (error) {
      TimeoutException() => _timeoutMessage,
      FormatException() => _invalidResponseMessage,
      _ => error.toString(),
    };
  }
}
