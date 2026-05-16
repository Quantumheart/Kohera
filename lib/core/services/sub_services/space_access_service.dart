import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:matrix/matrix.dart';

class SpaceAccessService {
  SpaceAccessService({required Client client}) : _client = client;

  final Client _client;
  List<String>? _supportedVersionsCache;

  JoinMode getJoinMode(Room room) {
    final raw = room
        .getState(EventTypes.RoomJoinRules)
        ?.content
        .tryGet<String>('join_rule');
    switch (raw) {
      case 'public':
        return JoinMode.public;
      case 'knock':
        return JoinMode.knock;
      case 'restricted':
        return JoinMode.restricted;
      case 'knock_restricted':
        return JoinMode.knockRestricted;
      case 'invite':
      default:
        return JoinMode.invite;
    }
  }

  List<String> allowedSpaceIds(Room room) {
    final allow = room
        .getState(EventTypes.RoomJoinRules)
        ?.content
        .tryGetList<Map<String, Object?>>('allow');
    if (allow == null) return const [];
    final ids = <String>[];
    for (final entry in allow) {
      if (entry['type'] != 'm.room_membership') continue;
      final roomId = entry['room_id'];
      if (roomId is String) ids.add(roomId);
    }
    return List.unmodifiable(ids);
  }

  bool needsUpgradeForRestricted(Room room, {required bool wantKnock}) {
    final version = int.tryParse(room.roomVersion ?? '1') ?? 0;
    final threshold = wantKnock ? 10 : 8;
    return version < threshold;
  }

  Future<List<String>> serverSupportedRoomVersions() async {
    final cached = _supportedVersionsCache;
    if (cached != null) return cached;
    try {
      final caps = await _client.getCapabilities();
      final keys = caps.mRoomVersions?.available.keys.toList(growable: false) ??
          const <String>[];
      return _supportedVersionsCache = List.unmodifiable(keys);
    } catch (e) {
      debugPrint('[Kohera] SpaceAccessService.serverSupportedRoomVersions failed: $e');
      return const <String>[];
    }
  }
}
