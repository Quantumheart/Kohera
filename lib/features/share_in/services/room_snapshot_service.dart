import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/avatar_cache_service.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:matrix/matrix.dart';

/// Persists a [RoomSnapshot] list of the active account's joined, non-space
/// rooms into the App-Group shared store on sync, throttled so we never
/// write on every tick.
///
/// The iOS Share Extension reads this list to render its room picker without
/// running the Matrix SDK. Only the active account syncs (see
/// `ClientManager`), so the store always reflects the rooms the user would
/// actually share into.
///
/// When an [AvatarCacheService] is supplied, each flush also kicks avatar
/// pre-rendering into the App-Group container and schedules a follow-up
/// flush so the cached [RoomSnapshot.avatarPath] values land in the store.
class RoomSnapshotService {
  RoomSnapshotService({
    required Client client,
    required RoomSnapshotSink sink,
    Duration flushInterval = const Duration(seconds: 10),
    AvatarCacheService? avatarCache,
  })  : _client = client,
        _sink = sink,
        _flushInterval = flushInterval,
        _avatarCache = avatarCache;

  final Client _client;
  final RoomSnapshotSink _sink;
  final Duration _flushInterval;
  final AvatarCacheService? _avatarCache;

  StreamSubscription<SyncUpdate>? _sub;
  Timer? _flush;
  bool _disposed = false;

  void start() {
    if (_sub != null) return;
    _sub = _client.onSync.stream.listen((_) => _scheduleFlush());
    unawaited(_initialFlush());
  }

  Future<void> _initialFlush() async {
    try {
      await _client.roomsLoading;
    } catch (e) {
      debugPrint('[Kohera] RoomSnapshot roomsLoading wait failed: $e');
    }
    if (_disposed) return;
    await _flushSnapshots();
  }

  /// Trailing throttle: the first sync after a flush schedules a write
  /// after [_flushInterval]; syncs within that window are coalesced so a
  /// continuously long-polling client (events every few seconds) still
  /// flushes instead of resetting a debounce forever.
  void _scheduleFlush() {
    if (_disposed || _flush != null) return;
    _flush = Timer(_flushInterval, () => unawaited(_flushSnapshots()));
  }

  Future<void> _flushSnapshots() async {
    _flush = null;
    if (_disposed) return;
    final snapshots = _buildSnapshots();
    await _sink.writeRoomSnapshot(snapshots);
    // Kick avatar pre-render for rooms with avatars, then re-flush so the
    // newly cached avatarPath values land in the store. Fire-and-forget.
    final cache = _avatarCache;
    if (cache == null) return;
    unawaited(
      cache.ensureFor(snapshots).then((_) {
        if (!_disposed) _scheduleFlush();
      }),
    );
  }

  List<RoomSnapshot> _buildSnapshots() {
    final avatarPaths = _avatarCache?.cachedPaths() ?? const <String, String>{};
    return _client.rooms
        .where((r) => r.membership == Membership.join && !r.isSpace)
        .map(
          (r) => RoomSnapshot(
            roomId: r.id,
            displayname: r.getLocalizedDisplayname(),
            avatarMxc: r.avatar?.toString(),
            avatarPath: avatarPaths[r.id],
          ),
        )
        .toList(growable: false);
  }

  void dispose() {
    _disposed = true;
    _flush?.cancel();
    _flush = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
