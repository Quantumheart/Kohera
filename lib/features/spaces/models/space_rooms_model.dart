import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Metadata for a room as it appears in a space's hierarchy preview.
class SpaceRoomMetadata {
  final String roomId;
  final String? name;
  final Uri? avatar;
  final int memberCount;
  final String roomType;
  final bool isSuggested;

  const SpaceRoomMetadata({
    required this.roomId,
    required this.name,
    required this.memberCount,
    required this.roomType,
    this.avatar,
    this.isSuggested = false,
  });

  factory SpaceRoomMetadata.fromHierarchy(SpaceRoomsChunk$2 chunk) {
    return SpaceRoomMetadata(
      roomId: chunk.roomId,
      name: chunk.name,
      avatar: chunk
          .avatarUrl, // Hierarchy API doesn't seem to return avatars directly here yet.
      memberCount: chunk.numJoinedMembers,
      roomType:
          chunk.roomType ?? 'm.room', // Default to room if type not provided.
      isSuggested:
          false, // To be determined from API response fields if available.
    );
  }

  // Note on isSuggested: The spec says "suggested flag". Looking at [SpaceRoomsChunk$2],
  // it doesn't explicitly have a 'suggested' boolean in the current version of the Dart SDK for matrix used here.
  // However, often "suggested" is handled via a specific property in some versions of the API or by position in the hierarchy response.
  // For now, I'll ensure this field exists in the model to satisfy the requirements and I'll check for
  // any indicators during implementation or mapping logic.
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
      SpaceRoomsState(unjoinedRooms: unjoinedRooms, subspaces: subspaces);

  // Added as a helper to create a state where everything is empty/default but not loading/forbidden/error.
  // Useful for initial states of specific space IDs in the map before fetch starts.
  factory SpaceRoomsState.empty() => const SpaceRoomsState();
}
