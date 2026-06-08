import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/retry.dart';
import 'package:matrix/matrix.dart';

class SyncService extends ChangeNotifier {
  SyncService({
    required Client client,
    required Future<void> Function() onPostSyncBackup,
    SleepFn? sleep,
  })  : _client = client,
        _onPostSyncBackup = onPostSyncBackup,
        _sleep = sleep ?? Future<void>.delayed;

  final Client _client;
  final Future<void> Function() _onPostSyncBackup;
  final SleepFn _sleep;

  // ── Sync ─────────────────────────────────────────────────────
  bool _syncing = false;
  bool get syncing => _syncing;

  String? _autoUnlockError;
  String? get autoUnlockError => _autoUnlockError;

  StreamSubscription<SyncUpdate>? _syncSub;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> startSync({
    Duration? timeout = const Duration(seconds: 30),
    List<Duration> retrySchedule = const <Duration>[],
    RetryCallback? onRetry,
  }) async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();

    final firstSync = Completer<void>();
    unawaited(_syncSub?.cancel());
    _syncSub = _client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) firstSync.complete();
    });

    unawaited(firstSync.future.then((_) {
      _autoUnlockError = null;
      return _onPostSyncBackup();
    }).catchError((Object e) {
      debugPrint('[Kohera] Background E2EE auto-unlock error: $e');
      if (_disposed) return;
      _autoUnlockError = e.toString();
      notifyListeners();
    },),);

    if (timeout == null) {
      await firstSync.future;
      return;
    }

    // The subscription stays live across attempts, so a late first sync still
    // resolves and triggers the post-sync backup. Each attempt re-waits the
    // same future with a fresh timeout, backing off between tries.
    var attempt = 0;
    while (true) {
      try {
        await firstSync.future.timeout(timeout);
        return;
      } on TimeoutException catch (e) {
        if (_disposed) return;
        if (attempt >= retrySchedule.length) {
          debugPrint('[Kohera] First sync timed out after '
              '${timeout.inSeconds}s and $attempt retries');
          throw TimeoutException('Initial sync timed out. Check your connection.');
        }
        final delay = retrySchedule[attempt];
        attempt++;
        onRetry?.call(e, delay, attempt);
        debugPrint('[Kohera] First sync timed out (attempt $attempt), '
            'retrying in ${delay.inSeconds}s');
        await _sleep(delay);
      }
    }
  }

  void cancelSyncSub() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    _syncing = false;
  }
}
