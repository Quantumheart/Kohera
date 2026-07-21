import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class SyncService extends ChangeNotifier {
  SyncService({
    required Client client,
    required Future<void> Function() onPostSyncBackup,
    bool Function()? shouldRetryBackup,
    Duration retryDebounce = const Duration(seconds: 5),
  })  : _client = client,
        _onPostSyncBackup = onPostSyncBackup,
        _shouldRetryBackup = shouldRetryBackup,
        _retryDebounceDuration = retryDebounce;

  final Client _client;
  final Future<void> Function() _onPostSyncBackup;
  final bool Function()? _shouldRetryBackup;
  final Duration _retryDebounceDuration;

  // ── Sync ─────────────────────────────────────────────────────
  bool _syncing = false;
  bool get syncing => _syncing;

  String? _autoUnlockError;
  String? get autoUnlockError => _autoUnlockError;

  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _retryDebounce;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _retryDebounce?.cancel();
    super.dispose();
  }

  Future<void> startSync({Duration? timeout = const Duration(seconds: 30)}) async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();

    final firstSync = Completer<void>();
    unawaited(_syncSub?.cancel());
    _syncSub = _client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) firstSync.complete();
      _maybeRetryBackup();
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

    if (timeout != null) {
      await firstSync.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('[Kohera] First sync timed out after ${timeout.inSeconds}s');
          throw TimeoutException('Initial sync timed out. Check your connection.');
        },
      );
    } else {
      await firstSync.future;
    }
  }

  /// Retry auto-unlock backup on subsequent syncs, debounced, when the
  /// [shouldRetryBackup] predicate says the backup is still needed.
  /// Stops retrying once the predicate returns false.
  void _maybeRetryBackup() {
    final check = _shouldRetryBackup;
    if (check == null || !check()) return;

    _retryDebounce?.cancel();
    _retryDebounce = Timer(_retryDebounceDuration, () {
      if (_disposed) return;
      if (!check()) return;
      unawaited(
        _onPostSyncBackup().catchError((Object e) {
          debugPrint('[Kohera] Background E2EE auto-unlock retry error: $e');
        }),
      );
    });
  }

  Future<void> pause() async {
    if (!_syncing) return;
    _client.backgroundSync = false;
    if (!kIsWeb) {
      await _client.abortSync();
    }
  }

  void resume() {
    if (_disposed || !_syncing) return;
    _client.backgroundSync = true;
  }

  void cancelSyncSub() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    _syncing = false;
  }
}
