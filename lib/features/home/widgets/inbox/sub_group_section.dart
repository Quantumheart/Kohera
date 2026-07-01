import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/home/widgets/inbox/notification_tile.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/models/thread_sub_group.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;

class SubGroupSection extends StatefulWidget {
  const SubGroupSection({
    required this.roomId,
    required this.subGroup,
    required this.client,
    required this.controller,
    super.key,
  });

  final String roomId;
  final ThreadSubGroup subGroup;
  final matrix_sdk.Client client;
  final InboxController controller;

  @override
  State<SubGroupSection> createState() => _SubGroupSectionState();
}

class _SubGroupSectionState extends State<SubGroupSection> {
  String? _rootPreview;

  @override
  void initState() {
    super.initState();
    final id = widget.subGroup.threadRootId;
    if (id != null) {
      _rootPreview = widget.controller.rootPreviewFor(id);
      if (_rootPreview == null) unawaited(_loadRoot(id));
    }
  }

  Future<void> _loadRoot(String eventId) async {
    final room = widget.client.getRoomById(widget.roomId);
    if (room == null) return;
    try {
      final event = await room.getEventById(eventId);
      if (event == null || !mounted) return;
      final body = stripReplyFallback(event.body).trim();
      if (body.isEmpty) return;
      final truncated = body.length > 80 ? '${body.substring(0, 80)}…' : body;
      final preview = InboxText.inReplyTo(truncated);
      widget.controller.setRootPreview(eventId, preview);
      if (mounted) setState(() => _rootPreview = preview);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final threadRootId = widget.subGroup.threadRootId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (threadRootId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 12, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.forum_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _rootPreview ?? InboxText.inThread,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  InboxText.threadCount(widget.subGroup.notifications.length),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        for (final notification in widget.subGroup.notifications)
          NotificationTile(
            notification: notification,
            client: widget.client,
            threadRootId: threadRootId,
          ),
      ],
    );
  }
}
