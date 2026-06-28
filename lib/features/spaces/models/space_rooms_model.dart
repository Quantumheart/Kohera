import 'package:matrix/matrix.dart';

/// Metadata for a room as it appears in a space's hierarchy preview.
class SpaceRoomMetadata {
  final String roomId;
  final String? name;
  final String? canonicalAlias;
  final Uri? avatar;
  final int memberCount;
  final String roomType;
  final bool isSuggested;
  final List<String> viaServers;

  const SpaceRoomMetadata({
    required this.roomId,
    required this.name,
    required this.memberCount,
    required this.roomType,
    this.canonicalAlias,
    this.avatar,
    this.isSuggested = false,
    this.viaServers = const [],
  });

  factory SpaceRoomMetadata.fromHierarchy(
    SpaceRoomsChunk$2 chunk, {
    bool isSuggested = false,
    List<String> viaServers = const [],
  }) {
    return SpaceRoomMetadata(
      roomId: chunk.roomId,
      name: chunk.name,
      canonicalAlias: chunk.canonicalAlias,
      avatar: chunk.avatarUrl,
      memberCount: chunk.numJoinedMembers,
      roomType: chunk.roomType ?? 'm.room',
      isSuggested: isSuggested,
      viaServers: viaServers,
    );
  }
}

/// State representing a space's child room hierarchy preview.
class SpaceRoomsState {
  final bool loading;
  final String? error;
  final bool previewForbidden;
  final List<SpaceRoomMetadata> unjoinedRooms;
  final List<SpaceRoomMetadata> subspaces;

  const SpaceRoomsState({
    this.loading = false,
    this.error,
    this.previewForbidden = false,
    this.unjoinedRooms = const [],
    this.subspaces = const [],
  });

  /// Create a loading state.
  factory SpaceRoomsState.loading() => const SpaceRoomsState(loading: true);

  /// Create an error state.
  factory SpaceRoomsState.error(String message) =>
      SpaceRoomsState(error: message);

  /// Create a forbidden state (e.g., M_FORBIDDEN).
  factory SpaceRoomsState.forbidden() =>
      const SpaceRoomsState(previewForbidden: true);

  /// Create a success state with results.
  factory SpaceRoomsState.success({
    required List<SpaceRoomMetadata> unjoinedRooms,
    required List<SpaceRoomMetadata> subspaces,
  }) =>
      SpaceRoomsState(
        unjoinedRooms: unjoinedRooms,
        subspaces: subspaces,
      );

  /// Create an empty state (not loading, not error, not forbidden).
  /// Useful for initial states before a fetch is triggered.
  factory SpaceRoomsState.empty() => const SpaceRoomsState();
}
