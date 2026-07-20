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
    final users = await room.requestParticipants([
      Membership.join,
      Membership.ban,
    ]);

    KoheraRoomMember toMember(User u) => KoheraRoomMember(
      userId: u.id,
      displayname: u.calcDisplayname(),
      avatarUrl: u.avatarUrl?.toString(),
      membership: u.membership.name,
      powerLevel: room.getPowerLevelByUserId(u.id).level,
    );

    final members = <KoheraRoomMember>[];
    final bannedMembers = <KoheraRoomMember>[];
    for (final u in users) {
      if (u.membership == Membership.ban) {
        bannedMembers.add(toMember(u));
      } else {
        members.add(toMember(u));
      }
    }
    bannedMembers.sort((a, b) => a.displayname.compareTo(b.displayname));

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
