import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';

/// Builds SDK-free [InviteUserDialogParams] for a Matrix room.
///
/// This is parent-side code: it performs the SDK calls (members, contacts,
/// user-directory search) that the SDK-free [InviteUserDialog] delegates out.
/// Callers pass a `roomId` and repositories; the room is looked up
/// internally via [RoomRepository] and never exposed to the widget layer.
InviteUserDialogParams inviteUserDialogParams(
  String roomId,
  RoomRepository roomRepo,
  UserRepository userRepo,
) {
  final dm = userRepo.knownContacts();
  final dmIds = dm.map((c) => c.userId).toSet();

  return InviteUserDialogParams(
    roomId: roomId,
    existingMemberIds: roomRepo.existingMemberIds(roomId),
    knownContacts: dm,
    roomContacts: userRepo.roomContacts(excludeMxids: dmIds),
    canonicalAlias: roomRepo.canonicalAlias(roomId),
    onSearchUserDirectory: (query) => userRepo.searchUserDirectory(query),
  );
}
