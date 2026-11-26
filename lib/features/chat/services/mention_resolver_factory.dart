import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';

/// Builds a [MentionDisplayNameResolver] bound to [roomId].
///
/// Resolves `@user:server` via the room's member display names and
/// `!room:server` via the room's localized display name. Returns a
/// null-resolver when [roomId] is unknown.
MentionDisplayNameResolver mentionResolverFromRoom(
  String? roomId,
  RoomRepository rooms,
) {
  if (roomId == null || !rooms.roomExists(roomId)) return (_) => null;
  return (String identifier) {
    if (identifier.startsWith('@')) {
      return rooms.userDisplayNameInRoom(roomId, identifier);
    } else if (identifier.startsWith('!')) {
      return rooms.roomDisplayName(identifier);
    }
    return null;
  };
}
