import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/services/auth_service.dart';
import 'package:kohera/core/state/key_backup_setup_state.dart';
import 'package:kohera/data/models/kohera_auth_exception.dart';
import 'package:kohera/data/models/kohera_uia_auth.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

class AuthRepository extends ChangeNotifier {
  AuthRepository({
    required MatrixClientService clientService,
    required AuthService auth,
    required KeyBackupSetupState setupState,
  })  : _clientService = clientService,
        _auth = auth,
        _setupState = setupState {
    _auth.addListener(_onAuthChanged);
  }

  final MatrixClientService _clientService;
  final AuthService _auth;
  final KeyBackupSetupState _setupState;
  bool _disposed = false;

  Client get _client => _clientService.client;

  void _onAuthChanged() {
    if (!_disposed) notifyListeners();
  }

  bool get isLoggedIn => _auth.isLoggedIn;
  bool get hasSkippedSetup => _setupState.setupSkipped;
  void skipSetup() => unawaited(_setupState.markSetupSkipped());

  Future<ServerAuthCapabilities> getServerAuthCapabilities(String homeserver) =>
      _auth.getServerAuthCapabilities(homeserver, isLoggedIn: _auth.isLoggedIn);

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
    bool rememberCredentials = false,
  }) {
    return _auth.login(
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
    return _auth.completeSsoLogin(
      homeserver: homeserver,
      loginToken: loginToken,
    );
  }

  Future<void> checkHomeserver(Uri homeserver) =>
      _client.checkHomeserver(homeserver);

  /// Registers a new account and completes the login on success.
  ///
  /// Throws [KoheraAuthException] when the homeserver rejects the call.
  /// A UIA challenge arrives as a [KoheraAuthException] whose [raw]
  /// payload contains `flows`, `session`, and `completed`.
  Future<void> registerAndComplete({
    String? username,
    String? password,
    String? initialDeviceDisplayName,
    KoheraUiaAuth? auth,
  }) async {
    try {
      final response = await _client.register(
        username: username,
        password: password,
        initialDeviceDisplayName: initialDeviceDisplayName,
        auth: auth == null
            ? null
            : AuthenticationData(
                type: auth.type,
                session: auth.session,
                additionalFields: auth.params,
              ),
      );
      await _auth.completeRegistration(response, password: password);
    } on MatrixException catch (e) {
      throw KoheraAuthException(
        e.errorMessage,
        errcode: e.errcode,
        raw: e.raw,
      );
    }
  }

  Future<void> logout() => _auth.logout();

  static String friendlyAuthError(Object e) => AuthService.friendlyAuthError(e);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
