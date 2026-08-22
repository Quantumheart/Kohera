import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';

/// Loads restricted/knock join-rule capabilities for the subspace dialog.
///
/// Parent-side code: calls `SpaceAccessService` to determine whether the
/// server supports restricted join rules and which room version to use.
Future<SubspaceCapabilities> loadSubspaceCapabilities(
  SpaceRepository access,
) async {
  final knockVersion =
      await access.pickRestrictedRoomVersion(wantKnock: true);
  final basicVersion =
      await access.pickRestrictedRoomVersion(wantKnock: false);
  return SubspaceCapabilities(
    restrictedRoomVersion: knockVersion ?? basicVersion,
    disabledModes: knockVersion == null
        ? const {JoinMode.knockRestricted: 'Not supported by this server'}
        : const <JoinMode, String>{},
  );
}

/// Creates a subspace room and registers it as a child of [parentSpaceId].
///
/// Delegates all SDK operations to [SpaceRepository.createSubspace].
/// Throws on failure (the dialog catches and displays the error).
Future<void> createSubspace(
  SpaceRepository spaceRepo,
  String parentSpaceId,
  CreateSubspaceRequest request,
) async {
  await spaceRepo.createSubspace(
    parentSpaceId: parentSpaceId,
    name: request.name,
    joinMode: request.joinMode,
    allowedSpaceIds: request.allowedSpaceIds,
    topic: request.topic,
    restrictedRoomVersion: request.restrictedRoomVersion,
  );
}
