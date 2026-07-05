import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/spaces/services/space_menu_actions.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';

/// Loads restricted/knock join-rule capabilities for the subspace dialog.
///
/// Parent-side code: calls `SpaceAccessService` to determine whether the
/// server supports restricted join rules and which room version to use.
Future<SubspaceCapabilities> loadSubspaceCapabilities(
  MatrixService matrix,
) async {
  final access = matrix.spaceAccess;
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
/// Delegates all SDK operations to [SpaceMenuActions.createSubspace].
/// Throws on failure (the dialog catches and displays the error).
Future<void> createSubspace(
  MatrixService matrix,
  String parentSpaceId,
  CreateSubspaceRequest request,
) async {
  await SpaceMenuActions(matrix).createSubspace(
    parentSpaceId: parentSpaceId,
    request: request,
  );
}
