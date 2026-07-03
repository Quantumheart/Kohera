import 'package:kohera/core/utils/known_contacts.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/shared/models/kohera_user_summary.dart';
import 'package:matrix/matrix.dart';

/// Builds SDK-free [InviteUserDialogParams] for a Matrix [room].
///
/// This is parent-side code: it performs the SDK calls (members, contacts,
/// user-directory search) that the SDK-free [InviteUserDialog] delegates out.
/// Callers which still hold a [Room] use this; widgets that are themselves
/// SDK-free source their params from a controller instead.
InviteUserDialogParams inviteUserDialogParams(Room room) {
  final client = room.client;

  Set<String> existingMemberIds() {
    try {
      return room.getParticipants().map((u) => u.id).toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  List<KoheraUserSummary> contacts() {
    try {
      return knownContacts(client).map(_toSummary).toList(growable: false);
    } catch (_) {
      return const <KoheraUserSummary>[];
    }
  }

  final dmContacts = contacts();
  final dmIds = dmContacts.map((c) => c.userId).toSet();

  List<KoheraUserSummary> groupContacts() {
    try {
      return roomContacts(client, excludeMxids: dmIds)
          .map(_toSummary)
          .toList(growable: false);
    } catch (_) {
      return const <KoheraUserSummary>[];
    }
  }

  return InviteUserDialogParams(
    roomId: room.id,
    existingMemberIds: existingMemberIds(),
    knownContacts: dmContacts,
    roomContacts: groupContacts(),
    onSearchUserDirectory: (query) async {
      final response = await client.searchUserDirectory(query, limit: 20);
      return response.results.map(_toSummary).toList(growable: false);
    },
  );
}

KoheraUserSummary _toSummary(Profile p) => KoheraUserSummary(
      userId: p.userId,
      displayname: p.displayName ?? p.userId,
      avatarUrl: p.avatarUrl?.toString(),
    );
