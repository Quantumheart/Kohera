import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:matrix/matrix.dart';

class AuthRepository extends ChangeNotifier {
  AuthRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  bool get isLoggedIn => _matrix.isLoggedIn;
  bool get hasSkippedSetup => _matrix.hasSkippedSetup;
  void skipSetup() => _matrix.skipSetup();

  AuthService get auth => _matrix.auth;
  UiaService get uia => _matrix.uia;

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
    bool rememberCredentials = false,
  }) {
    return _matrix.login(
      homeserver: homeserver,
      username: username,
      password: password,
      rememberCredentials: rememberCredentials,
    );
  }

  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) {
    return _matrix.completeSsoLogin(
      homeserver: homeserver,
      loginToken: loginToken,
    );
  }

  Future<void> checkHomeserver(Uri homeserver) =>
      _matrix.client.checkHomeserver(homeserver);

  Future<RegisterResponse> register({
    String? username,
    String? password,
    String? initialDeviceDisplayName,
    AuthenticationData? auth,
  }) =>
      _matrix.client.register(
        username: username,
        password: password,
        initialDeviceDisplayName: initialDeviceDisplayName,
        auth: auth,
      );

  Future<void> completeRegistration(
    RegisterResponse response, {
    String? password,
  }) {
    return _matrix.completeRegistration(response, password: password);
  }

  Future<void> logout() => _matrix.logout();

  static String friendlyAuthError(Object e) => MatrixService.friendlyAuthError(e);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}
