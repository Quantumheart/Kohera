import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/services/chat_backup_service.dart';
import 'package:kohera/core/services/matrix_service.dart' show koheraKey;
import 'package:kohera/core/services/session_backup.dart';
import 'package:kohera/core/services/sync_service.dart';
import 'package:kohera/core/utils/network_error.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/password_cache.dart';
import 'package:kohera/data/services/presence_service.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports, no public API for ClientInitException
import 'package:matrix/src/utils/client_init_exception.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    required MatrixClientService matrixClientService,
    required FlutterSecureStorage storage,
    required String clientName,
    required SyncService sync,
    required PresenceService presence,
    required PasswordCache passwordCache,
    required ChatBackupService chatBackup,
  })  : _matrixClientService = matrixClientService,
        _storage = storage,
        _clientName = clientName,
        _sync = sync,
        _presence = presence,
        _passwordCache = passwordCache,
        _chatBackup = chatBackup;

  final MatrixClientService _matrixClientService;
  final FlutterSecureStorage _storage;
  final String _clientName;
  final SyncService _sync;
  final PresenceService _presence;
  final PasswordCache _passwordCache;
  final ChatBackupService _chatBackup;

  Client get _client => _matrixClientService.client;

  static String friendlyAuthError(Object e) {
    if (isNetworkError(e)) return 'Could not reach server';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is FormatException) return 'Invalid server response';
    return e.toString();
  }

  // ── Auth state ────────────────────────────────────────────────
  bool isLoggedIn = false;

  String? _loginError;
  String? get loginError => _loginError;
  set loginError(String? value) {
    _loginError = value;
    notifyListeners();
  }

  Completer<void>? _capabilitiesLock;

  // ── Login ─────────────────────────────────────────────────────

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
    bool rememberCredentials = false,
  }) async {
    loginError = null;

    try {
      var hs = homeserver.trim();
      if (hs.isEmpty) throw ArgumentError('Homeserver cannot be empty');
      if (!hs.startsWith('http')) hs = 'https://$hs';

      debugPrint('[Kohera] Checking homeserver: $hs');
      await _matrixClientService.client.checkHomeserver(Uri.parse(hs));
      debugPrint('[Kohera] Homeserver OK');

      await _resetStaleClientState();

      debugPrint('[Kohera] Logging in as $username ...');
      await _matrixClientService.client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: 'Kohera Flutter',
        refreshToken: true,
      );
      debugPrint('[Kohera] Login complete – '
          'deviceId=${_matrixClientService.client.deviceID}, '
          'userId=${_matrixClientService.client.userID}, '
          'encryption=${_matrixClientService.client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${_matrixClientService.client.encryptionEnabled}');

      // Save before notifyListeners() so the credential is stored before
      // the router redirect fires and the login screen is disposed.
      if (rememberCredentials) {
        await saveLoginCredentials(
          homeserver: homeserver,
          username: username,
          password: password,
        );
      } else {
        await clearLoginCredentials(homeserver);
      }

      isLoggedIn = true;
      notifyListeners();

      try {
        await persistCredentials();
      } catch (e) {
        debugPrint('[Kohera] Credential persistence failed (non-fatal): $e');
      }

      _passwordCache.setCachedPassword(password);
      try {
        await _sync.startSync(timeout: const Duration(minutes: 5));
        _presence.setOnline();
        await saveSessionBackup();
      } catch (e) {
        debugPrint('[Kohera] Post-login sync error: $e');
      }

      return true;
    } catch (e, s) {
      debugPrint('[Kohera] Login failed: $e');
      debugPrint('[Kohera] Stack trace:\n$s');
      loginError = e.toString();
      return false;
    }
  }

  Future<void> _resetStaleClientState() async {
    if (isLoggedIn) return;
    if (_matrixClientService.client.onLoginStateChanged.value != LoginState.loggedIn) return;
    debugPrint('[Kohera] Detected stale SDK login state before login; '
        'clearing client to allow fresh sign-in');
    try {
      await _matrixClientService.client.clear();
    } catch (e) {
      debugPrint('[Kohera] Failed to clear stale client state: $e');
    }
  }

  // ── SSO Login ─────────────────────────────────────────────────

  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) async {
    loginError = null;

    try {
      var hs = homeserver.trim();
      if (hs.isEmpty) throw ArgumentError('Homeserver cannot be empty');
      if (!hs.startsWith('http')) hs = 'https://$hs';

      await _matrixClientService.client.checkHomeserver(Uri.parse(hs));

      await _resetStaleClientState();

      debugPrint('[Kohera] Completing SSO login ...');
      await _matrixClientService.client.login(
        LoginType.mLoginToken,
        token: loginToken,
        initialDeviceDisplayName: 'Kohera Flutter',
        refreshToken: true,
      );
      debugPrint('[Kohera] SSO login complete – '
          'deviceId=${_matrixClientService.client.deviceID}, '
          'userId=${_matrixClientService.client.userID}');

      isLoggedIn = true;
      notifyListeners();

      try {
        await persistCredentials();
      } catch (e) {
        debugPrint('[Kohera] Credential persistence failed (non-fatal): $e');
      }

      try {
        await _sync.startSync(timeout: const Duration(minutes: 5));
        _presence.setOnline();
        await saveSessionBackup();
      } catch (e) {
        debugPrint('[Kohera] Post-login sync error: $e');
      }

      return true;
    } catch (e, s) {
      debugPrint('[Kohera] SSO login failed: $e');
      debugPrint('[Kohera] Stack trace:\n$s');
      loginError = e.toString();
      return false;
    }
  }

  // ── Registration ──────────────────────────────────────────────

  Future<void> completeRegistration(
    RegisterResponse response, {
    String? password,
  }) async {
    debugPrint('[Kohera] Registration complete – userId=${response.userId}');

    if (_matrixClientService.client.accessToken == null || _matrixClientService.client.userID == null) {
      throw StateError('MatrixClientService was not initialized after register(). '
          'accessToken=${_matrixClientService.client.accessToken}, userID=${_matrixClientService.client.userID}');
    }

    if (password != null) _passwordCache.setCachedPassword(password);

    isLoggedIn = true;
    notifyListeners();

    try {
      await persistCredentials();
    } catch (e) {
      debugPrint('[Kohera] Credential persistence failed (non-fatal): $e');
    }

    try {
      await _sync.startSync(timeout: const Duration(minutes: 5));
      await saveSessionBackup();
    } catch (e) {
      debugPrint('[Kohera] Post-login sync error: $e');
    }
  }

  // ── Session Restore ───────────────────────────────────────────

  void activateRestoredSession() {
    isLoggedIn = true;
    notifyListeners();
  }

  /// Restores a persisted session into the SDK client. Returns whether a live
  /// session was restored; the caller (MatrixService) wires runtime activation
  /// only when this is true.
  Future<bool> restoreSession() async {
    // Tokens live in two places: the SDK database (rewritten on every automatic
    // token refresh) and the keychain (only rewritten on explicit persist). The
    // database therefore holds the freshest tokens, so restore from it whenever
    // it has a session. Seeding a stale keychain token via init(newToken:) would
    // overwrite the database's fresh tokens and trigger a spurious logout.
    if (await _hasDatabaseSession()) {
      return _restoreFromDatabase();
    } else {
      return _restoreFromKeychain();
    }
  }

  Future<bool> _hasDatabaseSession() async {
    try {
      final stored = await _client.database.getClient(_clientName);
      if (stored == null) return false;
      return stored.tryGet<String>('token') != null ||
          stored.tryGet<String>('refresh_token') != null;
    } catch (e) {
      debugPrint('[Kohera] Database session probe failed: $e');
      return false;
    }
  }

  Future<bool> _restoreFromDatabase() async {
    debugPrint('[Kohera] Restoring session from database for $_clientName');
    try {
      // Defer database loading and first sync to background so the UI renders
      // immediately instead of blocking on device-key verification.
      await _client.init(
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      if (!_client.isLogged()) {
        debugPrint('[Kohera] Database restore produced no logged-in session');
        isLoggedIn = false;
        return false;
      }
      debugPrint(
        '[Kohera] Session restored from database – '
        'encryption=${_client.encryption != null ? "available" : "null"}, '
        'encryptionEnabled=${_client.encryptionEnabled}',
      );
      activateRestoredSession();
      await _persistRestoredSession();
      return true;
    } catch (e, s) {
      debugPrint('[Kohera] Database session restore failed: $e');
      debugPrint('[Kohera] Stack trace:\n$s');
      final cause = _unwrapInitException(e);
      isLoggedIn = false;
      if (isPermanentAuthFailure(cause)) {
        await _clearSessionAndBackup();
      }
      return false;
    }
  }

  Future<bool> _restoreFromKeychain() async {
    final ({
      String? token,
      String? refreshToken,
      String? userId,
      String? homeserver,
      String? deviceId,
    })
    keys;
    try {
      keys = await _readSessionKeys();
    } catch (e) {
      debugPrint('[Kohera] Failed to read session keys: $e');
      return false;
    }

    if (keys.token == null || keys.userId == null || keys.homeserver == null) {
      return false;
    }

    final backup = await SessionBackup.load(
      clientName: _clientName,
      storage: _storage,
    );

    debugPrint(
      '[Kohera] Database restore unavailable; seeding session from keychain '
      'for ${keys.userId} on ${keys.homeserver} '
      '(deviceId=${keys.deviceId}, clientName=$_clientName)',
    );

    try {
      final homeserverUri = Uri.parse(keys.homeserver!);
      _client.homeserver = homeserverUri;
      await _client.init(
        newToken: keys.token,
        newRefreshToken: keys.refreshToken ?? backup?.refreshToken,
        newUserID: keys.userId,
        newDeviceID: keys.deviceId,
        newHomeserver: homeserverUri,
        newDeviceName: 'Kohera Flutter',
        newOlmAccount: backup?.olmAccount,
      );
      debugPrint(
        '[Kohera] Session restored from keychain – '
        'encryption=${_client.encryption != null ? "available" : "null"}, '
        'encryptionEnabled=${_client.encryptionEnabled}',
      );
      activateRestoredSession();
      await _persistRestoredSession();
      return true;
    } catch (e, s) {
      debugPrint('[Kohera] Keychain session restore failed: $e');
      debugPrint('[Kohera] Stack trace:\n$s');

      final cause = _unwrapInitException(e);
      isLoggedIn = false;
      if (isPermanentAuthFailure(cause)) {
        await _clearSessionAndBackup();
      }
      return false;
    }
  }

  Future<void> _persistRestoredSession() async {
    try {
      if (_client.accessToken != null) {
        await persistCredentials();
      }
      await saveSessionBackup();
    } catch (e) {
      debugPrint('[Kohera] Persisting restored session failed (non-fatal): $e');
    }
  }

  Future<
    ({
      String? token,
      String? refreshToken,
      String? userId,
      String? homeserver,
      String? deviceId,
    })
  >
  _readSessionKeys() async {
    final results = await Future.wait([
      _storage.read(key: koheraKey(_clientName, 'access_token')),
      _storage.read(key: koheraKey(_clientName, 'refresh_token')),
      _storage.read(key: koheraKey(_clientName, 'user_id')),
      _storage.read(key: koheraKey(_clientName, 'homeserver')),
      _storage.read(key: koheraKey(_clientName, 'device_id')),
    ]);
    return (
      token: results[0],
      refreshToken: results[1],
      userId: results[2],
      homeserver: results[3],
      deviceId: results[4],
    );
  }

  // ── Soft Logout ──────────────────────────────────────────────

  Future<void> handleSoftLogout() async {
    debugPrint('[Kohera] Soft logout detected, attempting token refresh...');
    try {
      await _client.refreshAccessToken();
      await persistCredentials();
      await saveSessionBackup();
      debugPrint('[Kohera] Token refreshed successfully');
    } catch (e) {
      debugPrint('[Kohera] Token refresh failed: $e');
      final cause = _unwrapInitException(e);
      if (isPermanentAuthFailure(cause)) {
        await logout();
      } else {
        debugPrint(
          '[Kohera] Transient refresh failure, keeping session '
          'for next sync/refresh retry',
        );
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────────

  Future<void> logout() async {
    isLoggedIn = false;
    notifyListeners();

    try {
      if (_matrixClientService.client.homeserver != null && _matrixClientService.client.accessToken != null) {
        await _matrixClientService.client.logout();
      }
    } catch (e) {
      debugPrint('[Kohera] Logout error: $e');
    }
    await _clearSessionAndBackup();
    await _chatBackup.deleteStoredRecoveryKey();
    await _chatBackup.deleteDismissalState();
  }

  Future<void> handleServerLogout() async {
    isLoggedIn = false;
    notifyListeners();

    await _clearSessionAndBackup();
  }

  Future<void> _clearSessionAndBackup() async {
    await clearSessionKeys();
    await SessionBackup.delete(clientName: _clientName, storage: _storage);
  }

  static Object _unwrapInitException(Object e) =>
      e is ClientInitException ? e.originalException : e;

  // ── Session Backup ────────────────────────────────────────────

  Future<void> saveSessionBackup() async {
    final backup = SessionBackup(
      accessToken: _matrixClientService.client.accessToken!,
      refreshToken: await _readRefreshToken(),
      userId: _matrixClientService.client.userID!,
      homeserver: _matrixClientService.client.homeserver.toString(),
      deviceId: _matrixClientService.client.deviceID!,
      deviceName: 'Kohera Flutter',
      olmAccount: _matrixClientService.client.encryption?.pickledOlmAccount,
    );
    await SessionBackup.save(
      backup,
      clientName: _clientName,
      storage: _storage,
    );
    debugPrint('[Kohera] Session backup saved for $_clientName');
  }

  Future<String?> _readRefreshToken() async {
    final stored = await _matrixClientService.client.database.getClient(_clientName);
    return stored?.tryGet<String>('refresh_token');
  }

  // ── Server Capabilities ──────────────────────────────────────

  Future<ServerAuthCapabilities> getServerAuthCapabilities(
    String homeserver, {
    required bool isLoggedIn,
  }) async {
    if (isLoggedIn) {
      debugPrint('[Kohera] getServerAuthCapabilities called while logged in, '
          'skipping to avoid mutating shared client state');
      return const ServerAuthCapabilities();
    }

    var hs = homeserver.trim();
    if (hs.isEmpty) throw ArgumentError('Homeserver cannot be empty');
    if (!hs.startsWith('http')) hs = 'https://$hs';

    while (_capabilitiesLock != null) {
      await _capabilitiesLock!.future;
    }
    final lock = Completer<void>();
    _capabilitiesLock = lock;

    final previousHomeserver = _matrixClientService.client.homeserver;
    try {
      await _matrixClientService.client.checkHomeserver(Uri.parse(hs));

      final loginFlows = await _matrixClientService.client.getLoginFlows();
      final supportsPassword =
          loginFlows?.any((f) => f.type == AuthenticationTypes.password) ??
              false;
      final supportsSso =
          loginFlows?.any((f) => f.type == AuthenticationTypes.sso) ?? false;

      final ssoFlow = loginFlows
          ?.where((f) => f.type == AuthenticationTypes.sso)
          .firstOrNull;
      final idProviders = <SsoIdentityProvider>[];
      if (ssoFlow != null) {
        final providers = ssoFlow.additionalProperties['identity_providers'];
        if (providers is List) {
          for (final p in providers) {
            if (p is Map && p['id'] is String && p['name'] is String) {
              idProviders.add(SsoIdentityProvider(
                id: p['id'] as String,
                name: p['name'] as String,
                icon: p['icon'] as String?,
              ),);
            }
          }
        }
      }

      var supportsRegistration = false;
      var registrationStages = <String>[];
      try {
        await _matrixClientService.client.request(
          RequestType.POST,
          '/client/v3/register',
          data: <String, dynamic>{},
        );
      } on MatrixException catch (e) {
        if (e.raw.containsKey('flows')) {
          supportsRegistration = true;
          final flows = e.raw['flows'];
          if (flows is List && flows.isNotEmpty) {
            final allStages = <String>{};
            for (final flow in flows) {
              if (flow is Map && flow['stages'] is List) {
                allStages.addAll((flow['stages'] as List).cast<String>());
              }
            }
            registrationStages = allStages.toList();
          }
        }
      } catch (_) {}

      final resolvedHomeserver = _matrixClientService.client.homeserver;

      return ServerAuthCapabilities(
        supportsPassword: supportsPassword,
        supportsSso: supportsSso,
        supportsRegistration: supportsRegistration,
        ssoIdentityProviders: idProviders,
        registrationStages: registrationStages,
        resolvedHomeserver: resolvedHomeserver,
      );
    } finally {
      _matrixClientService.client.homeserver = previousHomeserver;
      lock.complete();
      _capabilitiesLock = null;
    }
  }

  // ── Session Key Management ────────────────────────────────────

  bool isPermanentAuthFailure(Object error) {
    final e =
        error is ClientInitException ? error.originalException : error;
    if (e is MatrixException) {
      return e.errcode == 'M_UNKNOWN_TOKEN' ||
          e.errcode == 'M_FORBIDDEN' ||
          e.errcode == 'M_USER_DEACTIVATED';
    }
    return false;
  }

  Future<void> clearSessionKeys() async {
    await Future.wait([
      _storage.delete(key: koheraKey(_clientName, 'access_token')),
      _storage.delete(key: koheraKey(_clientName, 'refresh_token')),
      _storage.delete(key: koheraKey(_clientName, 'user_id')),
      _storage.delete(key: koheraKey(_clientName, 'homeserver')),
      _storage.delete(key: koheraKey(_clientName, 'device_id')),
      _storage.delete(key: koheraKey(_clientName, 'olm_account')),
    ]);
  }

  // ── Saved Login Credentials ──────────────────────────────────

  static String _savedLoginKey(String homeserver, String suffix) =>
      'kohera_saved_login_${homeserver.trim().toLowerCase()}_$suffix';

  Future<void> saveLoginCredentials({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    await Future.wait([
      _storage.write(
          key: _savedLoginKey(homeserver, 'username'), value: username,),
      _storage.write(
          key: _savedLoginKey(homeserver, 'password'), value: password,),
    ]);
  }

  Future<({String username, String password})?> loadLoginCredentials(
      String homeserver,) async {
    final results = await Future.wait([
      _storage.read(key: _savedLoginKey(homeserver, 'username')),
      _storage.read(key: _savedLoginKey(homeserver, 'password')),
    ]);
    final username = results[0];
    final password = results[1];
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  Future<void> clearLoginCredentials(String homeserver) async {
    await Future.wait([
      _storage.delete(key: _savedLoginKey(homeserver, 'username')),
      _storage.delete(key: _savedLoginKey(homeserver, 'password')),
    ]);
  }

  // ── Storage Key Migration ─────────────────────────────────────

  Future<void> migrateStorageKeys() async {
    if (_clientName != 'default') return;

    final oldToken = await _storage.read(key: 'kohera_access_token');
    if (oldToken == null) return;

    debugPrint('[Kohera] Migrating old storage keys to namespaced format');

    const migrations = {
      'kohera_access_token': 'kohera_default_access_token',
      'kohera_user_id': 'kohera_default_user_id',
      'kohera_homeserver': 'kohera_default_homeserver',
      'kohera_device_id': 'kohera_default_device_id',
      'kohera_olm_account': 'kohera_default_olm_account',
    };

    for (final entry in migrations.entries) {
      final value = await _storage.read(key: entry.key);
      if (value != null) {
        await _storage.write(key: entry.value, value: value);
        await _storage.delete(key: entry.key);
      }
    }
  }

  // ── Credential Persistence ──────────────────────────────────

  Future<void> persistCredentials() async {
    final stored = await _matrixClientService.client.database.getClient(_clientName);
    final refreshToken = stored?.tryGet<String>('refresh_token');
    await Future.wait([
      _storage.write(
          key: koheraKey(_clientName, 'access_token'),
          value: _matrixClientService.client.accessToken,),
      _storage.write(
          key: koheraKey(_clientName, 'refresh_token'),
          value: refreshToken,),
      _storage.write(
          key: koheraKey(_clientName, 'user_id'), value: _matrixClientService.client.userID,),
      _storage.write(
          key: koheraKey(_clientName, 'homeserver'),
          value: _matrixClientService.client.homeserver.toString(),),
      _storage.write(
          key: koheraKey(_clientName, 'device_id'), value: _matrixClientService.client.deviceID,),
    ]);
  }

}
