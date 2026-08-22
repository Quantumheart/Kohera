import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_room_member.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/features/rooms/widgets/member_sheet_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// ── Member sheet launcher ─────────────────────────────────────

/// Opens the member profile sheet for [member] in the room identified by
/// [roomId].
///
/// This is the SDK boundary helper — it computes permissions from the
/// raw [Room] (obtained via [RoomRepository.rawRoom]), wires all SDK
/// callbacks (start DM, role change, kick, ban, unban), and delegates
/// to the SDK-free [showMemberSheetDialog].
///
/// Use this from any widget that has a `roomId` + `KoheraRoomMember`
/// and needs to show the member profile sheet.
Future<void> showRoomMemberSheet(
  BuildContext context, {
  required String roomId,
  required KoheraRoomMember member,
}) {
  final roomRepo = context.read<RoomRepository>();
  final room = roomRepo.rawRoom(roomId)!;
  final mediaRepo = context.read<MediaRepository>();
  final userRepo = context.read<UserRepository>();

  final myUserId = roomRepo.userId;
  final isMe = member.userId == myUserId;
  final ownLevel = room.getPowerLevelByUserId(myUserId ?? '').level;
  final isIgnored = userRepo.ignoredUsers.contains(member.userId);

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
    avatarResolver: mediaRepo.avatarResolver,
    presence: context.read<UserRepository>(),
    isIgnored: isIgnored,
    formatError: MatrixService.friendlyAuthError,
    onStartDm: isMe
        ? null
        : () async {
            final dmRoomId = await roomRepo.startDirectChat(
              member.userId,
            );
            if (roomRepo.rawRoom(dmRoomId) == null) {
              await roomRepo
                  .waitForRoomInSync(dmRoomId, join: true)
                  .timeout(const Duration(seconds: 30));
            }
            if (!context.mounted) return;
            context.read<MatrixService>().selection.selectRoom(dmRoomId);
            context.goNamed(
              Routes.room,
              pathParameters: {RouteParams.roomId: dmRoomId},
            );
          },
    onRoleChange: (level) => PowerLevelService.update(
      roomRepo,
      room,
      PowerLevelPatch(users: {member.userId: level}),
    ),
    onKick: (reason) => roomRepo.kick(room.id, member.userId, reason: reason),
    onBan: (reason) => roomRepo.ban(room.id, member.userId, reason: reason),
    onUnban: (_) => roomRepo.unban(room.id, member.userId),
    onIgnore: isMe ? null : () => userRepo.ignoreUser(member.userId),
    onUnignore: isMe ? null : () => userRepo.unignoreUser(member.userId),
  );
}

// ── Inline unban launcher ───────────────────────────────────────

/// Unbans [member] from the room identified by [roomId] via [roomRepo]
/// and surfaces the result via snackbar.
///
/// Used by the banned-users section of [RoomMembersSection] so the snackbar,
/// error formatting, and [Kohera] logging live in one place. The caller is
/// responsible for reloading its member list after this returns.
Future<void> unbanRoomMember(
  BuildContext context,
  RoomRepository roomRepo,
  String roomId,
  KoheraRoomMember member, {
  String? reason,
}) async {
  try {
    final room = roomRepo.rawRoom(roomId)!;
    await roomRepo.unban(room.id, member.userId, reason: reason);
    if (context.mounted) context.showSnack('Unbanned ${member.displayname}');
  } catch (e) {
    debugPrint('[Kohera] Unban failed: $e');
    if (context.mounted) {
      context.showSnack(
        'Failed to unban: ${MatrixService.friendlyAuthError(e)}',
      );
    }
  }
}
