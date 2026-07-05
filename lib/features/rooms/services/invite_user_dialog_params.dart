import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/known_contacts.dart' as contacts;
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/shared/models/kohera_user_summary.dart';

/// Builds SDK-free [InviteUserDialogParams] for a Matrix room.
///
/// This is parent-side code: it performs the SDK calls (members, contacts,
/// user-directory search) that the SDK-free [InviteUserDialog] delegates out.
/// Callers pass a `roomId` and `MatrixService`; the room is looked up
/// internally and never exposed to the widget layer.
InviteUserDialogParams inviteUserDialogParams(
  String roomId,
  MatrixService matrix,
) {
  final client = matrix.client;
  final room = client.getRoomById(roomId);

  Set<String> existingMemberIds() {
    if (room == null) return const <String>{};
    try {
      return room.getParticipants().map((u) => u.id).toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  final dm = contacts
      .knownContacts(client)
      .map(
        (p) => KoheraUserSummary(
          userId: p.userId,
          displayname: p.displayName ?? p.userId,
          avatarUrl: p.avatarUrl?.toString(),
        ),
      )
      .toList(growable: false);
  final dmIds = dm.map((c) => c.userId).toSet();

  List<KoheraUserSummary> groupContacts() {
    if (room == null) return const <KoheraUserSummary>[];
    try {
      return contacts
          .roomContacts(client, excludeMxids: dmIds)
          .map(
            (p) => KoheraUserSummary(
              userId: p.userId,
              displayname: p.displayName ?? p.userId,
              avatarUrl: p.avatarUrl?.toString(),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <KoheraUserSummary>[];
    }
  }

  return InviteUserDialogParams(
    roomId: roomId,
    existingMemberIds: existingMemberIds(),
    knownContacts: dm,
    roomContacts: groupContacts(),
    onSearchUserDirectory: (query) async {
      final response = await client.searchUserDirectory(query, limit: 20);
      return response.results
          .map(
            (p) => KoheraUserSummary(
              userId: p.userId,
              displayname: p.displayName ?? p.userId,
              avatarUrl: p.avatarUrl?.toString(),
            ),
          )
          .toList(growable: false);
    },
  );
}
