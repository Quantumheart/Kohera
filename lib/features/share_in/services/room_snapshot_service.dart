import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
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
class RoomSnapshotService {
  RoomSnapshotService({
    required Client client,
    required RoomSnapshotSink sink,
    Duration flushInterval = const Duration(seconds: 10),
  })  : _client = client,
        _sink = sink,
        _flushInterval = flushInterval;

  final Client _client;
  final RoomSnapshotSink _sink;
  final Duration _flushInterval;

  StreamSubscription<SyncUpdate>? _sub;
  Timer? _flush;
  bool _disposed = false;

  void start() {
    if (_sub != null) return;
    _sub = _client.onSync.stream.listen((_) => _scheduleFlush());
    // Write immediately at launch so the store is populated even when the
    // initial sync already completed before this listener attached (the
    // common case for an already-logged-in client). Subsequent updates ride
    // the throttled sync listener.
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
    if (kDebugMode) {
      debugPrint(
        '[Kohera] (debug) roomSnapshot wrote ${snapshots.length} rooms',
      );
    }
  }

  /// Exposed for tests: builds the snapshot projection from the client's
  /// current room state without writing.
  List<RoomSnapshot> _buildSnapshots() => _client.rooms
      .where((r) => r.membership == Membership.join && !r.isSpace)
      .map(
        (r) => RoomSnapshot(
          roomId: r.id,
          displayname: r.getLocalizedDisplayname(),
          avatarMxc: r.avatar?.toString(),
        ),
      )
      .toList(growable: false);

  void dispose() {
    _disposed = true;
    _flush?.cancel();
    _flush = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
