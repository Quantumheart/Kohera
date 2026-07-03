import 'package:kohera/features/rooms/models/kohera_room_permissions.dart';
import 'package:matrix/matrix.dart';

// ── RoomPermissionsResolver ─────────────────────────────────

/// Converts a Matrix SDK `Room` into a Kohera-owned
/// [KoheraRoomPermissions] at the conversion boundary.
///
/// Widgets below the boundary depend only on [KoheraRoomPermissions]
/// and action callbacks — never on `Room`.
class RoomPermissionsResolver {
  const RoomPermissionsResolver();

  KoheraRoomPermissions convert(
    Room room, {
    required String myUserId,
  }) {
    final powerLevelsContent =
        room.getState(EventTypes.RoomPowerLevels)?.content ?? {};

    final participants = room.getParticipants().map((u) {
      return KoheraRoomMember(
        userId: u.id,
        displayName: u.displayName,
        powerLevel: room.getPowerLevelByUserId(u.id),
      );
    }).toList();

    return KoheraRoomPermissions(
      roomId: room.id,
      displayName: room.getLocalizedDisplayname(),
      topic: room.topic,
      canEditName: room.canChangeStateEvent(EventTypes.RoomName),
      canEditTopic: room.canChangeStateEvent(EventTypes.RoomTopic),
      canEditAvatar: room.canChangeStateEvent(EventTypes.RoomAvatar),
      canInvite: room.canChangeStateEvent('m.room.invite') ||
          room.getPowerLevelByUserId(myUserId) >=
              (powerLevelsContent['invite'] as int? ?? 0),
      canChangeJoinRules: room.canChangeJoinRules,
      canChangePowerLevels: room.canChangePowerLevel,
      canEnableEncryption:
          !room.encrypted && room.canChangeStateEvent(EventTypes.Encryption),
      joinRule: _toKoheraJoinRule(room.joinRules),
      isEncrypted: room.encrypted,
      powerLevelsContent: powerLevelsContent,
      participants: participants,
      myPowerLevel: room.getPowerLevelByUserId(myUserId),
    );
  }

  KoheraJoinRule? _toKoheraJoinRule(JoinRules? rule) {
    if (rule == null) return null;
    return switch (rule) {
      JoinRules.public => KoheraJoinRule.public,
      JoinRules.invite => KoheraJoinRule.invite,
      JoinRules.knock => KoheraJoinRule.knock,
      JoinRules.restricted => KoheraJoinRule.restricted,
      _ => null,
    };
  }
}
