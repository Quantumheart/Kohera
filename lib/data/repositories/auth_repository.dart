import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

class AuthRepository extends ChangeNotifier {
  AuthRepository({
    required MatrixClientService clientService,
    required AuthService auth,
    required ChatBackupService chatBackup,
  })  : _clientService = clientService,
        _auth = auth,
        _chatBackup = chatBackup {
    _auth.addListener(_onAuthChanged);
  }

  final MatrixClientService _clientService;
  final AuthService _auth;
  final ChatBackupService _chatBackup;
  bool _disposed = false;

  Client get _client => _clientService.client;

  void _onAuthChanged() {
    if (!_disposed) notifyListeners();
  }

  bool get isLoggedIn => _auth.isLoggedIn;
  bool get hasSkippedSetup => _chatBackup.setupSkipped;
  void skipSetup() => unawaited(_chatBackup.markSetupSkipped());

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

  Future<RegisterResponse> register({
    String? username,
    String? password,
    String? initialDeviceDisplayName,
    AuthenticationData? auth,
  }) =>
      _client.register(
        username: username,
        password: password,
        initialDeviceDisplayName: initialDeviceDisplayName,
        auth: auth,
      );

  Future<void> completeRegistration(
    RegisterResponse response, {
    String? password,
  }) {
    return _auth.completeRegistration(response, password: password);
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
