import 'dart:async';

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
    Duration debounce = const Duration(seconds: 10),
  })  : _client = client,
        _sink = sink,
        _debounce = debounce;

  final Client _client;
  final RoomSnapshotSink _sink;
  final Duration _debounce;

  StreamSubscription<SyncUpdate>? _sub;
  Timer? _flush;
  bool _disposed = false;

  void start() {
    _sub ??= _client.onSync.stream.listen((_) => _scheduleFlush());
  }

  void _scheduleFlush() {
    if (_disposed) return;
    _flush?.cancel();
    _flush = Timer(_debounce, () => unawaited(_flushSnapshots()));
  }

  Future<void> _flushSnapshots() async {
    if (_disposed) return;
    await _sink.writeRoomSnapshot(_buildSnapshots());
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
