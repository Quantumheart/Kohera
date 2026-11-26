import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/avatar_cache_service.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';

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
    required RoomRepository rooms,
    required RoomSnapshotSink sink,
    Duration flushInterval = const Duration(seconds: 10),
    AvatarCacheService? avatarCache,
  })  : _rooms = rooms,
        _sink = sink,
        _flushInterval = flushInterval,
        _avatarCache = avatarCache;

  final RoomRepository _rooms;
  final RoomSnapshotSink _sink;
  final Duration _flushInterval;
  final AvatarCacheService? _avatarCache;

  Timer? _flush;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _rooms.addListener(_scheduleFlush);
    unawaited(_initialFlush());
  }

  Future<void> _initialFlush() async {
    try {
      await _rooms.roomsLoaded;
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
    return _rooms.roomSummaries
        .map(
          (s) => RoomSnapshot(
            roomId: s.roomId,
            displayname: s.displayname,
            avatarMxc: s.avatarUrl,
            avatarPath: avatarPaths[s.roomId],
          ),
        )
        .toList(growable: false);
  }

  void dispose() {
    _disposed = true;
    _rooms.removeListener(_scheduleFlush);
    _flush?.cancel();
    _flush = null;
  }
}
