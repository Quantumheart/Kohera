import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/rooms/widgets/invite_tile.dart';
import 'package:provider/provider.dart';

class InvitationsView extends StatelessWidget {
  const InvitationsView({
    required this.cs,
    required this.tt,
    super.key,
  });

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionService>();
    final invitedRooms = selection.invitedRooms;
    final invitedSpaces = selection.invitedSpaces;

    if (invitedRooms.isEmpty && invitedSpaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded,
                size: 56,
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),),
            const SizedBox(height: 16),
            Text(
              InboxText.noPendingInvitations,
              style: tt.titleMedium?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        if (invitedSpaces.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              InboxText.sectionSpaces,
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final space in invitedSpaces) InviteTile(room: space),
        ],
        if (invitedRooms.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              InboxText.sectionRooms,
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final room in invitedRooms) InviteTile(room: room),
        ],
      ],
    );
  }
}
