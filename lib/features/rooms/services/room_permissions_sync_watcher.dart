import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

/// Watches sync updates for changes to room permissions-related state events
/// and invokes a callback when relevant changes occur.
///
/// Encapsulates `SyncUpdate` handling so screens don't need to import
/// `package:matrix/matrix.dart`.
class RoomPermissionsSyncWatcher {
  RoomPermissionsSyncWatcher({required this.matrix});

  final MatrixService matrix;

  static const Set<String> _watchedTypes = {
    EventTypes.RoomPowerLevels,
    EventTypes.RoomJoinRules,
    EventTypes.Encryption,
  };

  StreamSubscription<SyncUpdate>? _sub;
  Timer? _debounce;

  /// Starts watching. Calls [onChanged] (debounced) when permission-related
  /// state events arrive for [roomId].
  void watch(String roomId, VoidCallback onChanged) {
    _sub = matrix.client.onSync.stream.listen((update) {
      final stateEvents =
          update.rooms?.join?[roomId]?.state ?? [];
      if (!stateEvents.any((e) => _watchedTypes.contains(e.type))) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), onChanged);
    });
  }

  void dispose() {
    _debounce?.cancel();
    unawaited(_sub?.cancel());
  }
}
