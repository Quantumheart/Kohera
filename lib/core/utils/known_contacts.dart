import 'package:matrix/matrix.dart';

/// Returns a list of [Profile] objects for users the client has existing
/// direct-message rooms with. Useful for populating "recent contacts" in
/// DM and invite dialogs.
List<Profile> knownContacts(Client client) {
  final seen = <String>{};
  final contacts = <Profile>[];
  for (final room in client.rooms) {
    if (!room.isDirectChat) continue;
    final mxid = room.directChatMatrixID;
    if (mxid == null || !seen.add(mxid)) continue;
    contacts.add(Profile(
      userId: mxid,
      displayName: room.getLocalizedDisplayname(),
      avatarUrl: room.avatar,
    ),);
  }
  return contacts;
}

/// Returns profiles of members from joined group rooms (non-DM), excluding
/// [excludeMxids] and the client's own user ID. Prefers more recently active
/// rooms and caps the result at [limit] unique profiles.
List<Profile> roomContacts(
  Client client, {
  Set<String> excludeMxids = const {},
  int limit = 50,
}) {
  final myId = client.userID;
  final seen = <String>{...excludeMxids, ?myId};
  final contacts = <Profile>[];

  final groupRooms = client.rooms
      .where((r) => !r.isDirectChat)
      .toList()
    ..sort((a, b) => (b.lastEvent?.originServerTs ?? DateTime(0))
        .compareTo(a.lastEvent?.originServerTs ?? DateTime(0)),);

  for (final room in groupRooms) {
    if (contacts.length >= limit) break;
    for (final user in room.getParticipants()) {
      if (contacts.length >= limit) break;
      if (!seen.add(user.id)) continue;
      contacts.add(Profile(
        userId: user.id,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
      ),);
    }
  }
  return contacts;
}
