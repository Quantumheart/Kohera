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

  Future<void> setInviteOnly(Room room) =>
      applyJoinMode(roomId: room.id, mode: JoinMode.invite);

  Future<void> setPublic(Room room) =>
      applyJoinMode(roomId: room.id, mode: JoinMode.public);

  Future<void> setRestrictedJoin(Room room, List<Room> allowSpaces) =>
      applyJoinMode(
        roomId: room.id,
        mode: JoinMode.restricted,
        allowSpaceIds: allowSpaces.map((r) => r.id).toList(growable: false),
      );

  Future<void> setKnockRestricted(Room room, List<Room> allowSpaces) =>
      applyJoinMode(
        roomId: room.id,
        mode: JoinMode.knockRestricted,
        allowSpaceIds: allowSpaces.map((r) => r.id).toList(growable: false),
      );

  Future<void> applyJoinMode({
    required String roomId,
    required JoinMode mode,
    List<String> allowSpaceIds = const [],
  }) {
    final restrictedFamily =
        mode == JoinMode.restricted || mode == JoinMode.knockRestricted;
    if (restrictedFamily && allowSpaceIds.isEmpty) {
      throw ArgumentError(
        'allowSpaceIds must contain at least one space for $mode',
      );
    }
    final joinRule = switch (mode) {
      JoinMode.invite => 'invite',
      JoinMode.public => 'public',
      JoinMode.knock => 'knock',
      JoinMode.restricted => 'restricted',
      JoinMode.knockRestricted => 'knock_restricted',
    };
    return _writeJoinRule(
      roomId,
      joinRule,
      allowSpaceIds: restrictedFamily ? allowSpaceIds : const [],
    );
  }

  Future<void> _writeJoinRule(
    String roomId,
    String joinRule, {
    required List<String> allowSpaceIds,
  }) async {
    final existing = _client
            .getRoomById(roomId)
            ?.getState(EventTypes.RoomJoinRules)
            ?.content
            .tryGetList<Map<String, Object?>>('allow') ??
        const <Map<String, Object?>>[];
    final preserved = existing
        .where((e) => e['type'] != 'm.room_membership')
        .toList(growable: true);
    final newAllow = [
      ...preserved,
      for (final id in allowSpaceIds)
        <String, Object?>{'type': 'm.room_membership', 'room_id': id},
    ];

    final payload = <String, Object?>{
      'join_rule': joinRule,
      if (newAllow.isNotEmpty) 'allow': newAllow,
    };
    await _client.setRoomStateWithKey(
      roomId,
      EventTypes.RoomJoinRules,
      '',
      payload,
    );
  }

  Future<String> upgradeRoomTo(Room room, String newVersion) {
    return _client.upgradeRoom(room.id, newVersion);
  }

  Future<void> rewireParentSpaces(String oldRoomId, String newRoomId) async {
    final parents = _client.rooms
        .where((r) =>
            r.isSpace && r.spaceChildren.any((c) => c.roomId == oldRoomId),)
        .toList();
    for (final parent in parents) {
      await parent.setSpaceChild(newRoomId);
      await parent.removeSpaceChild(oldRoomId);
    }
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
