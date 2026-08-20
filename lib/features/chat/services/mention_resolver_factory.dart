import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';
import 'package:matrix/matrix.dart';

/// Builds a [MentionDisplayNameResolver] from a Matrix [Room].
///
/// Resolves `@user:server` via `Room.unsafeGetUserFromMemoryOrFallback` and
/// `!room:server` via [RoomRepository.rawRoom]. This is the boundary
/// construction — callers that still have SDK access use this to produce the
/// resolver.
MentionDisplayNameResolver mentionResolverFromRoom(
  Room? room,
  RoomRepository rooms,
) {
  if (room == null) return (_) => null;
  return (String identifier) {
    if (identifier.startsWith('@')) {
      try {
        return room.unsafeGetUserFromMemoryOrFallback(identifier).displayName;
      } catch (_) {
        return null;
      }
    } else if (identifier.startsWith('!')) {
      try {
        return rooms.rawRoom(identifier)?.getLocalizedDisplayname();
      } catch (_) {
        return null;
      }
    }
    return null;
  };
}
