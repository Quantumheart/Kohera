import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class SyncService {
  SyncService({
    required Client client,
    required VoidCallback onChanged,
    required VoidCallback onSyncEvent,
    required Future<void> Function() onPostSyncBackup,
  })  : _client = client,
        _onChanged = onChanged,
        _onSyncEvent = onSyncEvent,
        _onPostSyncBackup = onPostSyncBackup;

  final Client _client;
  final VoidCallback _onChanged;
  final VoidCallback _onSyncEvent;
  final Future<void> Function() _onPostSyncBackup;

  // ── Sync ─────────────────────────────────────────────────────
  bool _syncing = false;
  bool get syncing => _syncing;

  String? _autoUnlockError;
  String? get autoUnlockError => _autoUnlockError;

  StreamSubscription<SyncUpdate>? _syncSub;

  Future<void> startSync({Duration? timeout = const Duration(seconds: 30)}) async {
    _syncing = true;
    _onChanged();

    final firstSync = Completer<void>();
    unawaited(_syncSub?.cancel());
    _syncSub = _client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) firstSync.complete();
      _onSyncEvent();
    });

    if (timeout != null) {
      await firstSync.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('[Lattice] First sync timed out after ${timeout.inSeconds}s');
          throw TimeoutException('Initial sync timed out. Check your connection.');
        },
      );
    } else {
      await firstSync.future;
    }

    _autoUnlockError = null;
    unawaited(_onPostSyncBackup().catchError((Object e) {
      debugPrint('[Lattice] Background E2EE auto-unlock error: $e');
      _autoUnlockError = e.toString();
      _onChanged();
    },),);
  }

  void cancelSyncSub() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    _syncing = false;
  }
}
