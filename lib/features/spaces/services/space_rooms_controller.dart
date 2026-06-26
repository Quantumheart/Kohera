import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:matrix/matrix.dart';

/// Controller that manages the hierarchy of rooms within a space for previewing purposes.
/// It handles fetching, filtering, ordering, and automatic synchronization of unjoined rooms and subspaces.
class SpaceRoomsController extends ChangeNotifier {
  final SpaceDiscoveryDataSource _dataSource;
  final Client _client;

  SpaceRoomsController({
    required SpaceDiscoveryDataSource dataSource,
    required Client client,
  })  : _client = client,
        _dataSource = dataSource;

  /// Internal cache mapping space ID to its current preview state.
  final Map<String, SpaceRoomsState> _cache = {};

  /// The state for a specific space's room hierarchy. Returns empty if not fetched yet.
  SpaceRoomsState getRoomState(String spaceId) {
    return _cache[spaceId] ?? SpaceRoomsState.empty();
  }

  /// Fetches the child room hierarchy for a given space and updates its cached state.
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

      final unjoined = <SpaceRoomMetadata>[];
      final subspaces = <SpaceRoomMetadata>[];

      for (final chunk in response.rooms) {
        // Exclude the parent space itself from unjoined list (it is always first in children if it's a space).
        if (chunk.roomId == spaceId) continue;

        // Skip if the user is already a member of the room (join/admin/etc).
        if (_dataSource.isMember(chunk.roomId)) continue;

        final metadata = SpaceRoomMetadata.fromHierarchy(chunk);

        if (chunk.roomType == 'm.space') {
          subspaces.add(metadata);
        } else {
          unjoined.add(metadata);
        }
      }

      // Sorting logic: 1. Suggested first, 2. Otherwise rely on API order (m.space.child order). 
      unjoined.sort((a, b) {
        if (a.isSuggested != b.isSuggested) return a.isSuggested ? -1 : 1;
        return 0;
      });

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

  /// Forces a refresh of a space's hierarchy cache. Useful for manual refresh or after joins.
  Future<void> refresh(String spaceId) async {
    await fetchSpaceRooms(spaceId);
  }

  /// Joins a room and automatically refreshes the parent space's hierarchy state upon success.
  /// [parentSpaceId] is the space ID to refresh upon success. If null, no automatic refresh is performed.
  Future<String?> join({
    required String roomId,
    List<String>? via,
    String? parentSpaceId,
  }) async {
    try {
      final joinedId = await _dataSource.joinRoom(roomId, via: via);
      if (parentSpaceId != null) {
        await refresh(parentSpaceId);
      }
      return joinedId;
    } catch (e) {
      debugPrint('[SpaceRoomsController] Join failed: $e');
      return null;
    }
  }

  /// Listen to sync events and invalidate relevant cache entries.
  void listenToSync() {
    _client.onSync.stream.listen((update) {
      // Check if any membership changes occurred in the sync update.
      // If so, clear the hierarchy cache as membership affects unjoined room counts.
      final joined = update.rooms?.join;
      final leave = update.rooms?.leave;
      final invite = update.rooms?.invite;

      if (joined != null && joined.isNotEmpty) {
        _cache.clear();
        notifyListeners();
      } else if (leave != null && leave.isNotEmpty) {
        _cache.clear();
        notifyListeners();
      } else if (invite != null && invite.isNotEmpty) {
        _cache.clear();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _cache.clear();
    super.dispose();
  }
}
