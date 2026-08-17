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

  /// True between [startSync] and the first successful sync update.
  /// The UI can observe this to show a non-blocking "still catching up"
  /// state instead of a frozen loader. Unlike the old 30s timeout this
  /// never aborts the sync — it just reports progress.
  bool _initialSyncPending = false;
  bool get isInitialSyncPending => _initialSyncPending;

  /// Populated when the initial sync is aborted by an explicit [startSync]
  /// timeout. Null while waiting or after a successful first sync. Use
  /// [retrySync] to attempt again.
  String? _initialSyncError;
  String? get initialSyncError => _initialSyncError;

  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _retryDebounce;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _retryDebounce?.cancel();
    super.dispose();
  }

  /// Starts syncing and (by default) waits for the first sync update.
  ///
  /// [timeout] is *not* a sync deadline — when it elapses the sync is
  /// aborted cleanly (subscription cancelled, state reset) and
  /// [initialSyncError] is populated so the UI can offer a retry. Passing
  /// `null` (the default) waits indefinitely; the SDK's own network request
  /// timeout (`Client.defaultNetworkRequestTimeout`) still governs the
  /// underlying HTTP requests and the SDK retries transient failures on
  /// its own. The background-sync path uses `null` so a slow homeserver
  /// never produces a misleading "First sync timed out" state.
  Future<void> startSync({Duration? timeout}) async {
    if (_syncing) return;
    _syncing = true;
    _initialSyncPending = true;
    _initialSyncError = null;
    notifyListeners();

    final firstSync = Completer<void>();
    unawaited(_syncSub?.cancel());
    _syncSub = _client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) {
        firstSync.complete();
        _initialSyncPending = false;
        notifyListeners();
      }
      _maybeRetryBackup();
    });

    unawaited(firstSync.future.then((_) async {
      _autoUnlockError = null;
      // Defer the post-sync E2EE burst one event-loop turn so the sync-update
      // handler stack unwinds and the UI pumps before the (main-isolate) key
      // recovery runs. Otherwise the sync-processing block and the recovery
      // block compound into a single main-isolate stall that trips the OS
      // "not responding" watchdog. See issue #991.
      await Future<void>.delayed(Duration.zero);
      await _onPostSyncBackup();
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
          _initialSyncError =
              'Initial sync timed out after ${timeout.inSeconds}s. '
              'Check your connection.';
          _cancelAndReset();
          notifyListeners();
          throw TimeoutException('Initial sync timed out. Check your connection.');
        },
      );
    } else {
      await firstSync.future;
    }
  }

  /// Retries the initial sync after a [startSync] timeout aborted it.
  /// No-op if a sync is already running.
  Future<void> retrySync({Duration? timeout}) {
    if (_syncing) return Future<void>.value();
    return startSync(timeout: timeout);
  }

  void _cancelAndReset() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    _syncing = false;
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
    _cancelAndReset();
    _initialSyncPending = false;
    _initialSyncError = null;
  }
}
