import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/features/rooms/widgets/member_sheet_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// ── Member sheet launcher ─────────────────────────────────────

/// Opens the member profile sheet for [member] in [room].
///
/// This is the SDK boundary helper — it computes permissions from the
/// [Room], wires all SDK callbacks (start DM, role change, kick, ban,
/// unban), and delegates to the SDK-free [showMemberSheetDialog].
///
/// Use this from any widget that has a `Room` + `KoheraRoomMember`
/// and needs to show the member profile sheet.
Future<void> showRoomMemberSheet(
  BuildContext context, {
  required Room room,
  required KoheraRoomMember member,
}) {
  final client = room.client;
  final isMe = member.userId == client.userID;
  final ownLevel = room.getPowerLevelByUserId(client.userID ?? '').level;
  final isIgnored = client.ignoredUsers.contains(member.userId);

  return showMemberSheetDialog(
    context,
    member: member,
    isMe: isMe,
    ownLevel: ownLevel,
    canChangeRole:
        !isMe && room.canChangePowerLevel && member.powerLevel < ownLevel,
    canKick: !isMe &&
        room.canKick &&
        member.powerLevel < ownLevel &&
        !member.isBanned,
    canBan: !isMe &&
        room.canBan &&
        member.powerLevel < ownLevel &&
        !member.isBanned,
    avatarResolver: context.read<MatrixService>().avatarResolver,
    presence: context.read<MatrixService>().presence,
    isIgnored: isIgnored,
    formatError: MatrixService.friendlyAuthError,
    onStartDm: isMe
        ? null
        : () async {
            final dmRoomId = await client.startDirectChat(
              member.userId,
              enableEncryption: true,
            );
            if (client.getRoomById(dmRoomId) == null) {
              await client
                  .waitForRoomInSync(dmRoomId, join: true)
                  .timeout(const Duration(seconds: 30));
            }
            if (!context.mounted) return;
            context.read<SelectionService>().selectRoom(dmRoomId);
            context.goNamed(
              Routes.room,
              pathParameters: {RouteParams.roomId: dmRoomId},
            );
          },
    onRoleChange: (level) => PowerLevelService.update(
      room,
      PowerLevelPatch(users: {member.userId: level}),
    ),
    onKick: (reason) => client.kick(room.id, member.userId, reason: reason),
    onBan: (reason) => client.ban(room.id, member.userId, reason: reason),
    onUnban: (_) => client.unban(room.id, member.userId),
    onIgnore: isMe ? null : () => client.ignoreUser(member.userId, leaveRooms: false),
    onUnignore: isMe ? null : () => client.unignoreUser(member.userId),
  );
}
