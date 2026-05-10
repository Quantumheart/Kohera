import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/sub_services/backup_version_manager.dart';
import 'package:kohera/features/e2ee/widgets/key_backup_signer.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class ChatBackupService extends ChangeNotifier {
  ChatBackupService({
    required Client client,
    required FlutterSecureStorage storage,
    BackupVersionManager? backupVersion,
  })  : _client = client,
        _storage = storage,
        _backupVersion =
            backupVersion ?? BackupVersionManager(client: client) {
    _syncSub = _client.onSync.stream.listen(_onSyncUpdate);
  }

  final Client _client;
  final FlutterSecureStorage _storage;
  final BackupVersionManager _backupVersion;

  StreamSubscription<SyncUpdate>? _syncSub;
  DateTime? _lastResumeRefresh;
  static const Duration _resumeRefreshThrottle = Duration(seconds: 30);

  static const _backupAccountDataTypes = <String>{
    'm.megolm_backup.v1',
    'm.cross_signing.master',
    'm.cross_signing.self_signing',
    'm.cross_signing.user_signing',
  };

  // ── Chat Backup ─────────────────────────────────────────────
  bool? _chatBackupNeeded;
  bool? get chatBackupNeeded => _chatBackupNeeded;
  bool get chatBackupEnabled => _chatBackupNeeded == false;

  bool _chatBackupLoading = false;
  bool get chatBackupLoading => _chatBackupLoading;

  String? _chatBackupError;
  String? get chatBackupError => _chatBackupError;

  Future<void> checkChatBackupStatus() async {
    try {
      final hasBackupVersion = await _backupVersion.hasVersion();
      final state = await _client.getCryptoIdentityState();
      debugPrint(
        '[Kohera] Backup status: initialized=${state.initialized}, '
        'connected=${state.connected}, hasBackupVersion=$hasBackupVersion',
      );
      if (hasBackupVersion == null) {
        // Lookup failed — leave the previous value in place rather than
        // emitting a false-positive "backup needed".
        return;
      }
      _chatBackupNeeded =
          !state.initialized || !state.connected || !hasBackupVersion;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] checkChatBackupStatus error: $e');
      // Transient failure — keep the last known value. Forcing `true` here
      // produced false positives on sync hiccups and cross-signing rotations.
    }
  }

  void _onSyncUpdate(SyncUpdate update) {
    final events = update.accountData;
    if (events == null || events.isEmpty) return;
    final relevant = events.any(
      (e) => _backupAccountDataTypes.contains(e.type),
    );
    if (!relevant) return;
    debugPrint('[Kohera] Backup-relevant account-data observed in sync');
    _backupVersion.invalidateCache();
    unawaited(checkChatBackupStatus());
  }

  /// Refreshes backup status after the app returns to the foreground.
  /// Throttled so repeated resume events don't thrash the server.
  Future<void> refreshOnResume() async {
    final now = DateTime.now();
    if (_lastResumeRefresh != null &&
        now.difference(_lastResumeRefresh!) < _resumeRefreshThrottle) {
      return;
    }
    _lastResumeRefresh = now;
    _backupVersion.invalidateCache();
    await checkChatBackupStatus();
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    super.dispose();
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

  // ── Key Restoration ──────────────────────────────────────────

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
        events = await _client.database
            .getEventList(room, limit: _keyRequestScanLimit);
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

  // ── Recovery Key Storage ──────────────────────────────────────

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

}
