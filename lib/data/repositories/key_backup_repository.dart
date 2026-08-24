import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/backup_version_manager.dart';
import 'package:kohera/core/services/key_backup_signer.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/megolm_key_mirror.dart';
import 'package:kohera/data/services/password_cache.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Owns an account's E2EE key-backup domain: backup status, recovery-key
/// storage, key restoration, and the megolm key mirror. Source of truth for
/// whether chat backup is set up; [AccountSession] builds one per account.
class KeyBackupRepository extends ChangeNotifier {
  KeyBackupRepository({
    required MatrixClientService clientService,
    required String clientName,
    required FlutterSecureStorage storage,
    required PasswordCache passwordCache,
    MegolmKeyMirror? keyMirrorOverride,
    BackupVersionManager? backupVersion,
  })  : _clientService = clientService,
        _storage = storage,
        _passwordCache = passwordCache,
        _backupVersion =
            backupVersion ?? BackupVersionManager(client: clientService.client),
        _keyMirror = keyMirrorOverride ??
            MegolmKeyMirror(
              matrixClientService: clientService,
              clientName: clientName,
            );

  final MatrixClientService _clientService;
  final FlutterSecureStorage _storage;
  final PasswordCache _passwordCache;
  final BackupVersionManager _backupVersion;
  final MegolmKeyMirror _keyMirror;
  bool _disposed = false;

  Client get _client => _clientService.client;

  // ── Backup status ─────────────────────────────────────────────
  bool? _chatBackupNeeded;
  bool? get chatBackupNeeded => _chatBackupNeeded;
  bool get chatBackupEnabled => _chatBackupNeeded == false;

  bool _chatBackupLoading = false;
  bool get chatBackupLoading => _chatBackupLoading;

  String? _chatBackupError;
  String? get chatBackupError => _chatBackupError;

  // ── Key mirror (iOS megolm key export for push decryption) ────

  /// Starts mirroring megolm session keys to the shared App Group store so
  /// the iOS notification extension can decrypt pushed events. No-op off iOS.
  Future<void> startKeyMirror() => _keyMirror.start();

  /// Tears down the key mirror (on logout); safe to call repeatedly.
  Future<void> stopKeyMirror() => _keyMirror.dispose();

  // ── Backup status operations ──────────────────────────────────

  Future<void> checkChatBackupStatus() async {
    try {
      final hasBackupVersion = await _backupVersion.hasVersion();
      final state = await _client.getCryptoIdentityState();
      debugPrint(
        '[Kohera] Backup status: initialized=${state.initialized}, '
        'connected=${state.connected}, hasBackupVersion=$hasBackupVersion',
      );
      _chatBackupNeeded =
          !state.initialized || !state.connected || !hasBackupVersion;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] checkChatBackupStatus error: $e');
      _chatBackupNeeded = true;
      notifyListeners();
    }
  }

  Future<void> disableChatBackup() async {
    _chatBackupError = null;
    _chatBackupLoading = true;
    notifyListeners();

    try {
      final encryption = _client.encryption;
      if (encryption == null) {
        throw Exception('Encryption is not available');
      }
      try {
        final info = await encryption.keyManager.getRoomKeysBackupInfo();
        await _client.deleteRoomKeysVersion(info.version);
      } on MatrixException catch (e) {
        if (e.errcode != 'M_NOT_FOUND') rethrow;
        debugPrint('[Kohera] No server-side key backup to delete');
      }
      _backupVersion.invalidateCache();
      await deleteStoredRecoveryKey();
      _chatBackupNeeded = true;
    } catch (e) {
      debugPrint('[Kohera] disableChatBackup error: $e');
      _chatBackupError = 'Failed to disable chat backup. Please try again.';
    } finally {
      _chatBackupLoading = false;
      notifyListeners();
    }
  }

  void resetChatBackupState() {
    _chatBackupNeeded = null;
  }

  // ── Key restoration ───────────────────────────────────────────

  Future<void> tryAutoUnlockBackup() async {
    final storedKey = await getStoredRecoveryKey();
    if (storedKey != null) {
      debugPrint('[Kohera] Attempting auto-unlock with stored key');
      try {
        final state = await _client.getCryptoIdentityState();
        if (state.connected &&
            await _backupVersion.cachedSecretMatchesServer()) {
          debugPrint('[Kohera] Skip restore: already connected and key valid');
        } else {
          await _client.restoreCryptoIdentity(storedKey);
        }
        await runKeyRecovery();
      } catch (e) {
        debugPrint('[Kohera] Failed: $e');
        await _handleStaleStoredKey();
      }
    } else {
      unawaited(requestMissingRoomKeys());
    }

    await checkChatBackupStatus();
    debugPrint('[Kohera] Complete, chatBackupNeeded=$_chatBackupNeeded');
  }

  Future<void> runKeyRecovery({OpenSSSS? ssssKey}) async {
    final encryption = _client.encryption;
    if (encryption == null) return;

    final backupInfo = await _backupVersion.ensureExists();

    await KeyBackupSigner.signWithCrossSigning(
      _client,
      encryption,
      ssssKey: ssssKey,
      backupInfo: backupInfo,
    );

    try {
      await encryption.keyManager.loadAllKeys();
      debugPrint('[Kohera] Room keys restored from online backup');
    } catch (e) {
      debugPrint('[Kohera] Failed to load keys from backup: $e');
    }

    await requestMissingRoomKeys(force: true);
  }

  Future<void> _handleStaleStoredKey() async {
    debugPrint('[Kohera] Stored recovery key is stale — clearing');
    await deleteStoredRecoveryKey();
    _chatBackupNeeded = true;
    notifyListeners();
  }

  static const int _keyRequestScanLimit = 200;
  static const Duration _keyRequestScanCooldown = Duration(minutes: 1);
  DateTime? _lastKeyRequestScan;

  Future<void> requestMissingRoomKeys({bool force = false}) async {
    final encryption = _client.encryption;
    if (encryption == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastKeyRequestScan != null &&
        now.difference(_lastKeyRequestScan!) < _keyRequestScanCooldown) {
      return;
    }
    _lastKeyRequestScan = now;

    final seen = <String>{};
    for (final room in _client.rooms) {
      List<Event> events;
      try {
        events =
            await _client.database.getEventList(room, limit: _keyRequestScanLimit);
      } catch (e) {
        debugPrint('[Kohera] getEventList failed for ${room.id}: $e');
        continue;
      }

      for (final event in events) {
        if (event.type != EventTypes.Encrypted ||
            event.messageType != MessageTypes.BadEncrypted ||
            event.content['can_request_session'] != true) {
          continue;
        }
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId == null || senderKey == null) continue;

        final dedupeKey = '${room.id}|$sessionId';
        if (!seen.add(dedupeKey)) continue;

        try {
          encryption.keyManager.maybeAutoRequest(
            room.id,
            sessionId,
            senderKey,
          );
        } catch (e) {
          debugPrint('[Kohera] Key request failed for ${room.id}: $e');
        }
      }
    }
  }

  // ── Recovery key storage ──────────────────────────────────────

  Future<String?> getStoredRecoveryKey() async {
    final userId = _client.userID;
    if (userId == null) return null;
    return _storage.read(key: 'ssss_recovery_key_$userId');
  }

  Future<void> storeRecoveryKey(String key) async {
    final userId = _client.userID;
    if (userId == null) return;
    await _storage.write(key: 'ssss_recovery_key_$userId', value: key);
  }

  Future<void> deleteStoredRecoveryKey() async {
    final userId = _client.userID;
    if (userId == null) return;
    await _storage.delete(key: 'ssss_recovery_key_$userId');
  }

  void clearCachedPassword() => _passwordCache.clearCachedPassword();

  Stream<KeyVerification> get onKeyVerificationRequest =>
      _client.onKeyVerificationRequest.stream;

  // ── E2EE bootstrap boundary ───────────────────────────────────

  /// The SDK [Encryption] handle, or null when encryption is unavailable.
  /// Escape hatch for the bootstrap/recovery flows that drive SSSS,
  /// cross-signing, and key backup directly.
  Encryption? get encryption => _client.encryption;

  /// The logged-in user's Matrix ID, or null before login.
  String? get userId => _client.userID;

  Future<void> updateUserDeviceKeys() => _client.updateUserDeviceKeys();

  /// Marks all locally stored inbound group sessions as needing backup upload.
  Future<void> markSessionsForBackupUpload() =>
      _client.database.markInboundGroupSessionsAsNeedingUpload();

  /// Waits for the client to finish initial loading before bootstrap.
  ///
  /// Mirrors the SDK's readiness futures (rooms, account data, device keys)
  /// and forces a first sync if none has happened yet. Throws
  /// [TimeoutException] if the first sync does not arrive within [timeout].
  Future<void> prepareForBootstrap({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _client;
    await client.roomsLoading;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first.timeout(timeout);
    }
    await client.updateUserDeviceKeys();
  }

  /// Whether a server-side room-keys backup already exists.
  ///
  /// Returns false when the server reports no backup (`M_NOT_FOUND`).
  Future<bool> hasServerKeyBackup() async {
    try {
      await encryption?.keyManager.getRoomKeysBackupInfo(false);
      return true;
    } on MatrixException catch (e) {
      if (e.errcode == 'M_NOT_FOUND') return false;
      rethrow;
    }
  }

  /// Starts a self-verification session across all of the user's own devices.
  ///
  /// Returns the SDK [KeyVerification] to drive the verification dialog, or
  /// null when encryption is unavailable.
  Future<KeyVerification?> startSelfVerification() async {
    final enc = encryption;
    if (enc == null) return null;
    await updateUserDeviceKeys();
    final verification = KeyVerification(
      encryption: enc,
      userId: _client.userID!,
      deviceId: '*',
    );
    await verification.start();
    enc.keyVerificationManager.addRequest(verification);
    return verification;
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_keyMirror.dispose());
    super.dispose();
  }
}
