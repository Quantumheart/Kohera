import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/home/widgets/inbox/notification_tile.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/models/thread_sub_group.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';

class SubGroupSection extends StatefulWidget {
  const SubGroupSection({
    required this.roomId,
    required this.subGroup,
    required this.controller,
    super.key,
  });

  final String roomId;
  final ThreadSubGroup subGroup;
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
    final preview =
        await widget.controller.loadRootPreview(widget.roomId, eventId);
    if (mounted && preview != null) setState(() => _rootPreview = preview);
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
        for (final item in widget.subGroup.notifications)
          NotificationTile(
            item: item,
            threadRootId: threadRootId,
          ),
      ],
    );
  }
}
