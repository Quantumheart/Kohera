import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/megolm_key_mirror.dart';
import 'package:matrix/encryption.dart';

class KeyBackupRepository extends ChangeNotifier {
  KeyBackupRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.chatBackup.addListener(_onChatBackupChanged);
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.chatBackup.removeListener(_onChatBackupChanged);
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.chatBackup.addListener(_onChatBackupChanged);
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onChatBackupChanged() {
    if (!_disposed) notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  ChatBackupService get chatBackup => _matrix.chatBackup;
  MegolmKeyMirror get keyMirror => _matrix.keyMirror;

  Stream<KeyVerification> get onKeyVerificationRequest =>
      _matrix.client.onKeyVerificationRequest.stream;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.chatBackup.removeListener(_onChatBackupChanged);
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}
