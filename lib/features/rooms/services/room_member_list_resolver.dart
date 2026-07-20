import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:matrix/matrix.dart';

// ── RoomMemberListResolver ───────────────────────────────────

/// Converts a Matrix SDK `Room` into a Kohera-owned
/// [KoheraRoomMemberList] at the conversion boundary.
///
/// Calls `room.requestParticipants()` (async, fetches from server) and
/// maps each `User` to a [KoheraRoomMember] with pre-computed display
/// name, avatar URL, membership, and power level.
class RoomMemberListResolver {
  const RoomMemberListResolver();

  Future<KoheraRoomMemberList> resolve(Room room) async {
    final users = await room.requestParticipants([Membership.join]);
    final bannedUsers = await room.requestParticipants([Membership.ban]);

    final members = users.map((u) {
      return KoheraRoomMember(
        userId: u.id,
        displayname: u.calcDisplayname(),
        avatarUrl: u.avatarUrl?.toString(),
        membership: u.membership.name,
        powerLevel: room.getPowerLevelByUserId(u.id).level,
      );
    }).toList();

    final bannedMembers = bannedUsers.map((u) {
      return KoheraRoomMember(
        userId: u.id,
        displayname: u.calcDisplayname(),
        avatarUrl: u.avatarUrl?.toString(),
        membership: u.membership.name,
        powerLevel: room.getPowerLevelByUserId(u.id).level,
      );
    }).toList()
      ..sort((a, b) => a.displayname.compareTo(b.displayname));

    // Sort: admins first, then mods, then alphabetical by displayname.
    members.sort((a, b) {
      if (a.powerLevel != b.powerLevel) return b.powerLevel.compareTo(a.powerLevel);
      return a.displayname.compareTo(b.displayname);
    });

    return KoheraRoomMemberList(
      members: members,
      bannedMembers: bannedMembers,
      participantListComplete: room.participantListComplete,
      memberCount: room.summary.mJoinedMemberCount ?? 0,
    );
  }
}
