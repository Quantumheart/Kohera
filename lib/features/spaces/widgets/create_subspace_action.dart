import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';
import 'package:matrix/matrix.dart';

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

/// Creates a subspace room and registers it as a child of [parentSpace].
///
/// Parent-side code: performs the SDK `createRoom` (with optional restricted
/// join-rules initial state), waits for sync, and calls `setSpaceChild`.
/// Throws on failure (the dialog catches and displays the error).
Future<void> createSubspace(
  MatrixService matrix,
  Room parentSpace,
  CreateSubspaceRequest request,
) async {
  final client = matrix.client;

  final useRestricted = request.restrictedRoomVersion != null &&
      request.joinMode.isRestrictedFamily &&
      request.allowedSpaceIds.isNotEmpty;
  final joinRulesEvent = useRestricted
      ? matrix.spaceAccess.buildJoinRulesStateEvent(
          request.joinMode,
          request.allowedSpaceIds,
        )
      : null;

  final roomId = await client.createRoom(
    name: request.name,
    topic: request.topic,
    creationContent: {'type': 'm.space'},
    visibility: Visibility.private,
    roomVersion: useRestricted ? request.restrictedRoomVersion : null,
    initialState: [
      if (joinRulesEvent != null) joinRulesEvent,
    ],
    powerLevelContentOverride: {'events_default': 100},
  );

  await client
      .waitForRoomInSync(roomId, join: true)
      .timeout(const Duration(seconds: 30));

  await parentSpace.setSpaceChild(roomId);
  matrix.selection.invalidateSpaceTree();

  debugPrint('[Kohera] Subspace created: $roomId under ${parentSpace.id}');
}
