import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/account_session.dart';
import 'package:kohera/core/services/secure_storage.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/core/services/sub_services/call_push_rule_manager.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/global_push_rule_manager.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/sync_service.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/media_resolver.dart';
import 'package:matrix/matrix.dart';

String koheraKey(String clientName, String suffix) =>
    'kohera_${clientName}_$suffix';

/// Lifecycle coordinator for a single account. Owns app-lifecycle wiring,
/// auth-state reactions, and session restore hand-off; the sub-service graph
/// lives in [AccountSession]. Sub-service and client access is forwarded so
/// existing consumers keep working while the graph is composed elsewhere.
class MatrixService extends ChangeNotifier with WidgetsBindingObserver {
  static String friendlyAuthError(Object e) => AuthService.friendlyAuthError(e);

  MatrixService({
    required AccountSession accountSession,
    FlutterSecureStorage? storage,
    this.clientName = 'default',
  }) : _accountSession = accountSession,
       _storage =
           storage ??
           KoheraSecureStorage(
             iOptions: const IOSOptions(
               groupId: 'group.io.github.quantumheart.kohera',
               accessibility: KeychainAccessibility.first_unlock,
             ),
             webOptions: const WebOptions(
               dbName: 'KoheraEncryptedStorage',
               publicKey: 'KoheraSecureStorage',
             ),
           ) {
    auth.addListener(_onAuthChanged);
  }

  // ── Fields ──────────────────────────────────────────────────────

  // ignore: unused_field, retained for session-backup helpers in restore path
  final FlutterSecureStorage _storage;
  final String clientName;

  final AccountSession _accountSession;

  StreamSubscription<LoginState>? _loginStateSub;
  bool _foregroundSyncStarted = false;
  bool _lifecycleObserverRegistered = false;
  Timer? _pauseDebounce;

  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ── Composition root + client accessors ─────────────────────────

  AccountSession get session => _accountSession;
  MatrixClientService get matrixClientService =>
      _accountSession.matrixClientService;

  // ── Sub-service forwarding ──────────────────────────────────────

  UiaService get uia => _accountSession.uia;
  ChatBackupService get chatBackup => _accountSession.chatBackup;
  SelectionService get selection => _accountSession.selection;
  SyncService get sync => _accountSession.sync;
  AuthService get auth => _accountSession.auth;
  AvatarResolver get avatarResolver => _accountSession.avatarResolver;
  MediaResolver get mediaResolver => _accountSession.mediaResolver;
  StickerPackService get stickerPacks => _accountSession.stickerPacks;
  CallPushRuleManager get callPushRuleManager =>
      _accountSession.callPushRuleManager;
  GlobalPushRuleManager get globalPushRuleManager =>
      _accountSession.globalPushRuleManager;

  bool get isLoggedIn => auth.isLoggedIn;

  /// The Matrix user ID of this account, or null before login.
  String? get userID => _accountSession.userID;

  bool get hasSkippedSetup => chatBackup.setupSkipped;
  void skipSetup() {
    unawaited(chatBackup.markSetupSkipped());
  }

  @visibleForTesting
  set isLoggedInForTest(bool value) {
    auth.isLoggedIn = value;
    auth.notifyListeners();
  }

  @visibleForTesting
  Future<void> activateSessionForTest() => _activateSession();

  // ── Public API ──────────────────────────────────────────────────

  Future<void> init({bool restoreSession = true}) async {
    if (restoreSession) {
      await auth.migrateStorageKeys();
      final restored = await auth.restoreSession();
      if (restored) await _activateSession();
      notifyListeners();
    }
  }

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
    bool rememberCredentials = false,
  }) => auth.login(
    homeserver: homeserver,
    username: username,
    password: password,
    rememberCredentials: rememberCredentials,
  );

  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) => auth.completeSsoLogin(homeserver: homeserver, loginToken: loginToken);

  Future<void> completeRegistration(
    RegisterResponse response, {
    String? password,
  }) => auth.completeRegistration(response, password: password);

  Future<void> logout() => auth.logout();

  Future<void> handleSoftLogout() => auth.handleSoftLogout();

  // ── Lifecycle ───────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _pauseDebounce?.cancel();
        _pauseDebounce = null;
        sync.resume();
        _startForegroundSync();
        _accountSession.presence.setOnline();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pauseDebounce?.cancel();
        _pauseDebounce = Timer(const Duration(seconds: 3), () {
          unawaited(sync.pause());
        });
        _accountSession.presence.setAway();
      case AppLifecycleState.detached:
        _pauseDebounce?.cancel();
        _pauseDebounce = null;
        unawaited(sync.pause());
        _accountSession.presence.setOffline();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pauseDebounce?.cancel();
    if (_lifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverRegistered = false;
    }
    auth.removeListener(_onAuthChanged);
    auth.isLoggedIn = false;
    sync.cancelSyncSub();
    unawaited(_loginStateSub?.cancel());
    _accountSession.dispose();
    super.dispose();
  }

  // ── Private: Auth Observer ──────────────────────────────────────

  void _onAuthChanged() {
    if (auth.isLoggedIn) {
      uia.listenForUia();
      _listenForLoginState();
      unawaited(chatBackup.loadDismissalState());
      unawaited(callPushRuleManager.ensureRule());
      unawaited(
        _accountSession.keyBackupRepository.startKeyMirror().catchError((Object e) {
          debugPrint('[Kohera] Key mirror start failed: $e');
        }),
      );
      unawaited(
        _accountSession.outboxRepository.start().catchError((Object e) {
          debugPrint('[Kohera] Outbox start failed: $e');
        }),
      );
      unawaited(
        _accountSession.messageRepository.initSearchIndex().catchError((Object e) {
          debugPrint('[Kohera] Message indexer init failed: $e');
        }),
      );
    } else {
      unawaited(_loginStateSub?.cancel());
      _loginStateSub = null;
      sync.cancelSyncSub();
      unawaited(_accountSession.keyBackupRepository.stopKeyMirror());
      uia.clearCachedPassword();
      uia.cancelUiaSub();
      selection.resetSelection();
      chatBackup.resetChatBackupState();
      _foregroundSyncStarted = false;
      if (_lifecycleObserverRegistered) {
        WidgetsBinding.instance.removeObserver(this);
        _lifecycleObserverRegistered = false;
      }
    }
    notifyListeners();
  }

  // ── Private: Login State Stream ─────────────────────────────────

  void _listenForLoginState() {
    if (_loginStateSub != null) return;
    _loginStateSub = _accountSession.client.onLoginStateChanged.stream.listen((
      state,
    ) async {
      if (state == LoginState.loggedOut && auth.isLoggedIn) {
        debugPrint('[Kohera] Server-side logout detected');
        await auth.handleServerLogout();
        await chatBackup.deleteStoredRecoveryKey();
        await chatBackup.deleteDismissalState();
      }
    });
  }

  // ── Private: Session Activation ─────────────────────────────────

  Future<void> _activateSession() async {
    if (!_lifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserverRegistered = true;
    }
    if (_isAppForegrounded()) {
      _startForegroundSync();
    } else {
      debugPrint(
        '[Kohera] Session activated in background — deferring sync until '
        'app is resumed (lifecycleState='
        '${WidgetsBinding.instance.lifecycleState})',
      );
    }
  }

  bool _isAppForegrounded() =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _startForegroundSync() {
    if (_foregroundSyncStarted || _disposed) return;
    _foregroundSyncStarted = true;
    unawaited(
      sync.startSync().catchError((Object e) {
        if (e is! TimeoutException) {
          debugPrint('[Kohera] Background sync error: $e');
        }
      }),
    );
    _accountSession.presence.setOnline();
  }
}
