import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/megolm_key_mirror.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class KeyBackupRepository extends ChangeNotifier {
  KeyBackupRepository({
    required MatrixClientService clientService,
    required ChatBackupService chatBackup,
    required MegolmKeyMirror keyMirror,
    required UiaService uia,
  })  : _clientService = clientService,
        _chatBackup = chatBackup,
        _keyMirror = keyMirror,
        _uia = uia {
    _chatBackup.addListener(_onChatBackupChanged);
  }

  final MatrixClientService _clientService;
  final ChatBackupService _chatBackup;
  final MegolmKeyMirror _keyMirror;
  final UiaService _uia;
  bool _disposed = false;

  Client get _client => _clientService.client;

  void _onChatBackupChanged() {
    if (!_disposed) notifyListeners();
  }

  ChatBackupService get chatBackup => _chatBackup;
  MegolmKeyMirror get keyMirror => _keyMirror;
  UiaService get uia => _uia;

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
    _chatBackup.removeListener(_onChatBackupChanged);
    super.dispose();
  }
}
