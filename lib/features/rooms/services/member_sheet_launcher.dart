import 'dart:async';

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
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// ── Member sheet launcher ─────────────────────────────────────

/// Opens the member profile sheet for [member] in the room identified by
/// [roomId].
///
/// This is the boundary helper — it computes permissions through
/// [RoomRepository], wires all callbacks (start DM, role change, kick,
/// ban, unban), and delegates to the SDK-free [showMemberSheetDialog].
///
/// Use this from any widget that has a `roomId` + `KoheraRoomMember`
/// and needs to show the member profile sheet.
Future<void> showRoomMemberSheet(
  BuildContext context, {
  required String roomId,
  required KoheraRoomMember member,
}) {
  final roomRepo = context.read<RoomRepository>();
  final mediaRepo = context.read<MediaRepository>();
  final userRepo = context.read<UserRepository>();

  final myUserId = roomRepo.userId;
  final isMe = member.userId == myUserId;
  final ownLevel = roomRepo.myPowerLevelFor(roomId);
  final isIgnored = userRepo.ignoredUsers.contains(member.userId);

  return showMemberSheetDialog(
    context,
    member: member,
    isMe: isMe,
    ownLevel: ownLevel,
    canChangeRole: !isMe &&
        roomRepo.getRoomCanChangePowerLevel(roomId) &&
        member.powerLevel < ownLevel,
    canKick: !isMe &&
        roomRepo.getRoomCanKick(roomId) &&
        member.powerLevel < ownLevel &&
        !member.isBanned,
    canBan: !isMe &&
        roomRepo.getRoomCanBan(roomId) &&
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
            if (roomRepo.summaryFor(dmRoomId) == null) {
              await roomRepo
                  .waitForRoomInSync(dmRoomId, join: true)
                  .timeout(const Duration(seconds: 30));
            }
            if (!context.mounted) return;
            context.read<MatrixService>().selectionController.selectRoom(dmRoomId);
            context.goNamed(
              Routes.room,
              pathParameters: {RouteParams.roomId: dmRoomId},
            );
          },
    onRoleChange: (level) => PowerLevelService.update(
      roomRepo,
      roomId,
      PowerLevelPatch(users: {member.userId: level}),
    ),
    onKick: (reason) => roomRepo.kick(roomId, member.userId, reason: reason),
    onBan: (reason) => roomRepo.ban(roomId, member.userId, reason: reason),
    onUnban: (_) => roomRepo.unban(roomId, member.userId),
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
    await roomRepo.unban(roomId, member.userId, reason: reason);
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
