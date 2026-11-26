import 'package:kohera/data/models/kohera_space_hierarchy.dart';
import 'package:matrix/matrix.dart';

/// Converts SDK space-hierarchy payloads into domain models.
class SpaceHierarchyResolver {
  const SpaceHierarchyResolver();

  KoheraSpaceChildState convertChildState(ChildrenState state) =>
      KoheraSpaceChildState(
        type: state.type,
        stateKey: state.stateKey,
        isSuggested: state.content.tryGet<bool>('suggested') ?? false,
        order: state.content.tryGet<String>('order'),
        via: state.content.tryGetList<String>('via') ?? const [],
      );

  KoheraSpaceHierarchyChunk convert(SpaceRoomsChunk$2 chunk) =>
      KoheraSpaceHierarchyChunk(
        roomId: chunk.roomId,
        name: chunk.name,
        topic: chunk.topic,
        canonicalAlias: chunk.canonicalAlias,
        avatarUrl: chunk.avatarUrl,
        memberCount: chunk.numJoinedMembers,
        worldReadable: chunk.worldReadable,
        guestCanJoin: chunk.guestCanJoin,
        roomType: chunk.roomType,
        childrenState: [
          for (final state in chunk.childrenState) convertChildState(state),
        ],
      );

  KoheraSpaceHierarchy convertResponse(GetSpaceHierarchyResponse response) =>
      KoheraSpaceHierarchy(
        rooms: [for (final chunk in response.rooms) convert(chunk)],
      );
}
