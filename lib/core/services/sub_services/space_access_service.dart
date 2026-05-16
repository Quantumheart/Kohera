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
  }) async {
    _validateForMode(mode, allowSpaceIds);
    final existingForeign = mode.isRestrictedFamily
        ? _foreignAllowEntries(roomId)
        : const <Map<String, Object?>>[];
    final payload = buildJoinRulesPayload(
      mode,
      mode.isRestrictedFamily ? allowSpaceIds : const [],
      preserveEntries: existingForeign,
    );
    await _client.setRoomStateWithKey(
      roomId,
      EventTypes.RoomJoinRules,
      '',
      payload,
    );
  }

  /// Builds an `m.room.join_rules` content payload. Shared by [applyJoinMode]
  /// and creation flows that bundle the event into `initial_state`.
  Map<String, Object?> buildJoinRulesPayload(
    JoinMode mode,
    List<String> allowSpaceIds, {
    List<Map<String, Object?>> preserveEntries = const [],
  }) {
    _validateForMode(mode, allowSpaceIds);
    final allow = mode.isRestrictedFamily
        ? [
            ...preserveEntries,
            for (final id in allowSpaceIds)
              <String, Object?>{'type': 'm.room_membership', 'room_id': id},
          ]
        : const <Map<String, Object?>>[];
    return <String, Object?>{
      'join_rule': mode.wire,
      if (allow.isNotEmpty) 'allow': allow,
    };
  }

  /// Same payload, wrapped as a [StateEvent] for `createRoom`'s
  /// `initial_state` parameter.
  StateEvent buildJoinRulesStateEvent(
    JoinMode mode,
    List<String> allowSpaceIds,
  ) {
    return StateEvent(
      type: EventTypes.RoomJoinRules,
      content: buildJoinRulesPayload(mode, allowSpaceIds),
    );
  }

  void _validateForMode(JoinMode mode, List<String> allowSpaceIds) {
    if (mode.isRestrictedFamily && allowSpaceIds.isEmpty) {
      throw ArgumentError(
        'allowSpaceIds must contain at least one space for $mode',
      );
    }
  }

  List<Map<String, Object?>> _foreignAllowEntries(String roomId) {
    final existing = _client
            .getRoomById(roomId)
            ?.getState(EventTypes.RoomJoinRules)
            ?.content
            .tryGetList<Map<String, Object?>>('allow') ??
        const <Map<String, Object?>>[];
    return existing
        .where((e) => e['type'] != 'm.room_membership')
        .toList(growable: false);
  }

  Future<String> upgradeRoomTo(Room room, String newVersion) {
    return _client.upgradeRoom(room.id, newVersion);
  }

  Future<void> rewireParentSpaces({
    required String oldRoomId,
    required String newRoomId,
    required List<Room> parents,
  }) async {
    for (final parent in parents) {
      await parent.setSpaceChild(newRoomId);
      await parent.removeSpaceChild(oldRoomId);
    }
  }

  /// Pick the highest server-supported room version usable for restricted /
  /// knock_restricted joins. Returns null if the server supports neither.
  Future<String?> pickRestrictedRoomVersion({required bool wantKnock}) async {
    final available = await serverSupportedRoomVersions();
    final numeric = available
        .map((v) => MapEntry(v, int.tryParse(v)))
        .where((e) => e.value != null)
        .toList()
      ..sort((a, b) => b.value!.compareTo(a.value!));
    final threshold = wantKnock ? 10 : 8;
    for (final entry in numeric) {
      if (entry.value! >= threshold) return entry.key;
    }
    return null;
  }

  Future<List<String>> serverSupportedRoomVersions() async {
    final cached = _supportedVersionsCache;
    if (cached != null) return cached;
    try {
      final caps = await _client.getCapabilities();
      final keys =
          caps.mRoomVersions?.available.keys.toList(growable: false) ??
              const <String>[];
      return _supportedVersionsCache = List.unmodifiable(keys);
    } catch (e) {
      // Don't poison the cache — let the next call retry.
      return const <String>[];
    }
  }
}
