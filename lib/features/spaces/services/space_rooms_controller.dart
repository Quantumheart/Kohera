import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:matrix/matrix.dart';

/// Controller that manages the hierarchy of rooms within a space for
/// previewing purposes. It handles fetching, filtering, ordering, and
/// automatic synchronization of unjoined rooms and subspaces.
class SpaceRoomsController extends ChangeNotifier {
  final SpaceDiscoveryDataSource _dataSource;
  final Client _client;
  StreamSubscription<SyncUpdate>? _syncSub;

  SpaceRoomsController({
    required SpaceDiscoveryDataSource dataSource,
    required Client client,
  })  : _client = client,
        _dataSource = dataSource;

  /// Internal cache mapping space ID to its current preview state.
  final Map<String, SpaceRoomsState> _cache = {};

  /// The state for a specific space's room hierarchy.
  /// Returns an empty state if not fetched yet.
  SpaceRoomsState getRoomState(String spaceId) {
    return _cache[spaceId] ?? SpaceRoomsState.empty();
  }

  /// Fetches the child room hierarchy for a given space and updates its
  /// cached state.
  Future<void> fetchSpaceRooms(String spaceId) async {
    if (_cache[spaceId]?.loading == true) return;

    _cache[spaceId] = SpaceRoomsState.loading();
    notifyListeners();

    try {
      final response = await _dataSource.getSpaceHierarchy(
        spaceId,
        maxDepth: 1,
        suggestedOnly: false,
      );

      // Extract suggested flags and order strings from the parent space's
      // m.space.child state events (childrenState on the parent's chunk).
      final childSuggested = <String, bool>{};
      final childOrder = <String, String>{};
      for (final chunk in response.rooms) {
        if (chunk.roomId == spaceId) {
          for (final child in chunk.childrenState) {
            if (child.type == EventTypes.SpaceChild && child.stateKey != null) {
              childSuggested[child.stateKey!] =
                  child.content.tryGet<bool>('suggested') ?? false;
              final order = child.content.tryGet<String>('order') ?? '';
              if (order.isNotEmpty) {
                childOrder[child.stateKey!] = order;
              }
            }
          }
          break;
        }
      }

      final unjoined = <SpaceRoomMetadata>[];
      final subspaces = <SpaceRoomMetadata>[];

      for (final chunk in response.rooms) {
        // Exclude the parent space itself.
        if (chunk.roomId == spaceId) continue;

        // Skip rooms the user is already a member of.
        if (_dataSource.isMember(chunk.roomId)) continue;

        final metadata = SpaceRoomMetadata.fromHierarchy(
          chunk,
          isSuggested: childSuggested[chunk.roomId] ?? false,
        );

        if (chunk.roomType == 'm.space') {
          subspaces.add(metadata);
        } else {
          unjoined.add(metadata);
        }
      }

      // Sort: suggested-first, then by m.space.child order string.
      // Rooms without an order string sort after those that have one.
      int compareByOrder(SpaceRoomMetadata a, SpaceRoomMetadata b) {
        if (a.isSuggested != b.isSuggested) {
          return a.isSuggested ? -1 : 1;
        }
        final aOrder = childOrder[a.roomId] ?? '';
        final bOrder = childOrder[b.roomId] ?? '';
        if (aOrder.isEmpty != bOrder.isEmpty) {
          return aOrder.isEmpty ? 1 : -1;
        }
        return aOrder.compareTo(bOrder);
      }

      unjoined.sort(compareByOrder);
      subspaces.sort(compareByOrder);

      _cache[spaceId] = SpaceRoomsState.success(
        unjoinedRooms: unjoined,
        subspaces: subspaces,
      );
    } on MatrixException catch (e) {
      if (e.errcode == 'M_FORBIDDEN') {
        _cache[spaceId] = SpaceRoomsState.forbidden();
      } else {
        _cache[spaceId] = SpaceRoomsState.error(e.toString());
      }
    } catch (e) {
      _cache[spaceId] = SpaceRoomsState.error(e.toString());
    }

    notifyListeners();
  }

  /// Forces a refresh of a space's hierarchy cache.
  Future<void> refresh(String spaceId) async {
    await fetchSpaceRooms(spaceId);
  }

  /// Joins a room and automatically refreshes the parent space's hierarchy
  /// state upon success.
  ///
  /// [alias] is the room's canonical alias (e.g. `#room:server.org`). When
  /// [via] is not provided, the server is derived from [alias] using the
  /// same pattern as `space_action_dialog.dart`'s `_viaFromAlias`.
  /// [parentSpaceId] is the space to refresh after a successful join. If
  /// null, no automatic refresh is performed.
  Future<String?> join({
    required String roomId,
    String? alias,
    List<String>? via,
    String? parentSpaceId,
  }) async {
    final effectiveVia = via ?? _viaFromAlias(alias);
    try {
      final joinedId = await _dataSource.joinRoom(roomId, via: effectiveVia);
      if (parentSpaceId != null) {
        await refresh(parentSpaceId);
      }
      return joinedId;
    } catch (e) {
      debugPrint('[SpaceRoomsController] Join failed: $e');
      return null;
    }
  }

  /// Derives a `via` server list from a canonical alias.
  /// Matches the pattern in `space_action_dialog.dart`'s `_viaFromAlias`.
  static List<String>? _viaFromAlias(String? alias) {
    if (alias == null) return null;
    final idx = alias.indexOf(':');
    if (idx == -1 || idx >= alias.length - 1) return null;
    return [alias.substring(idx + 1)];
  }

  /// Listen to sync events and invalidate caches for spaces whose children
  /// had a membership change (join, leave, or invite).
  void listenToSync() {
    _syncSub = _client.onSync.stream.listen((update) {
      final changedRoomIds = <String>{};
      final joined = update.rooms?.join;
      final leave = update.rooms?.leave;
      final invite = update.rooms?.invite;

      if (joined != null) changedRoomIds.addAll(joined.keys);
      if (leave != null) changedRoomIds.addAll(leave.keys);
      if (invite != null) changedRoomIds.addAll(invite.keys);

      if (changedRoomIds.isEmpty) return;

      // Invalidate only caches for spaces that contain the changed rooms.
      var didChange = false;
      for (final spaceId in _cache.keys.toList()) {
        final state = _cache[spaceId];
        if (state == null) continue;
        final childIds = {
          ...state.unjoinedRooms.map((r) => r.roomId),
          ...state.subspaces.map((r) => r.roomId),
        };
        if (changedRoomIds.any(childIds.contains)) {
          _cache.remove(spaceId);
          didChange = true;
        }
      }

      if (didChange) notifyListeners();
    });
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel());
    _cache.clear();
    super.dispose();
  }
}
