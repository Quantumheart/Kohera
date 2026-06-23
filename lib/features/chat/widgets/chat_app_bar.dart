import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/features/calling/models/incoming_call_info.dart' as model;
import 'package:kohera/features/calling/services/call_navigator.dart';
import 'package:kohera/features/chat/widgets/pinned_messages_popup.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/shared/widgets/presence_dot.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    required this.room, required this.onSearch, super.key,
    this.onBack,
    this.onShowDetails,
    this.onPinnedEvent,
    this.onShowThreads,
    this.threadUnreadCount = 0,
  });

  final Room room;
  final VoidCallback? onBack;
  final VoidCallback? onShowDetails;
  final VoidCallback onSearch;
  final void Function(Event event)? onPinnedEvent;
  final VoidCallback? onShowThreads;
  final int threadUnreadCount;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isNarrow =
        MediaQuery.sizeOf(context).width < HomeShell.wideBreakpoint;
    final effectiveOnBack =
        onBack ?? (isNarrow ? () => context.popOrGo(Routes.home) : null);
    final dmUserId = room.isDirectChat ? room.directChatMatrixID : null;
    final presence =
        dmUserId != null ? context.read<MatrixService>().presence : null;

    return AppBar(
      leading: effectiveOnBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: effectiveOnBack,
            )
          : null,
      automaticallyImplyLeading: false,
      titleSpacing: effectiveOnBack != null ? 0 : 16,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final showAvatar = constraints.maxWidth > 100;
          return Row(
            children: [
              if (showAvatar) ...[
                PresenceOverlay(
                  size: 34,
                  presence: presence,
                  userId: dmUserId,
                  child: RoomAvatarWidget(room: room, size: 34),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.getLocalizedDisplayname(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium,
                    ),
                    _HeaderSubtitle(
                      room: room,
                      presence: presence,
                      userId: dmUserId,
                      style: tt.bodyMedium?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        if (!isNarrow && room.pinnedEventIds.isNotEmpty && onPinnedEvent != null)
          Builder(
            builder: (buttonContext) => IconButton(
              mouseCursor: SystemMouseCursors.click,
              icon: Badge.count(
                count: room.pinnedEventIds.length,
                child: const Icon(Icons.push_pin_rounded),
              ),
              tooltip: 'Pinned messages',
              onPressed: () => showPinnedMessagesPopup(
                buttonContext,
                room,
                onTap: onPinnedEvent!,
              ),
            ),
          ),
        if (context.select<CallService, bool>((s) => s.isCallingAvailable))
          _CallButton(room: room),
        if (!isNarrow && onShowThreads != null)
          IconButton(
            mouseCursor: SystemMouseCursors.click,
            tooltip: 'Threads',
            icon: threadUnreadCount > 0
                ? Badge.count(
                    count: threadUnreadCount,
                    child: const Icon(Icons.forum_outlined),
                  )
                : const Icon(Icons.forum_outlined),
            onPressed: onShowThreads,
          ),
        IconButton(
          mouseCursor: SystemMouseCursors.click,
          icon: const Icon(Icons.search_rounded),
          onPressed: onSearch,
        ),
        Builder(
          builder: (buttonContext) => PopupMenuButton<_ChatMenuAction>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onSelected: (action) {
              switch (action) {
                case _ChatMenuAction.pinned:
                  if (onPinnedEvent != null) {
                    showPinnedMessagesPopup(
                      buttonContext,
                      room,
                      onTap: onPinnedEvent!,
                    );
                  }
                case _ChatMenuAction.threads:
                  onShowThreads?.call();
                case _ChatMenuAction.details:
                  if (onShowDetails != null) {
                    onShowDetails!();
                  } else {
                    context.pushOrGo(
                      Routes.roomDetails,
                      pathParameters: {RouteParams.roomId: room.id},
                    );
                  }
              }
            },
            itemBuilder: (context) => [
              if (isNarrow &&
                  room.pinnedEventIds.isNotEmpty &&
                  onPinnedEvent != null)
                PopupMenuItem(
                  value: _ChatMenuAction.pinned,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Badge.count(
                      count: room.pinnedEventIds.length,
                      child: const Icon(Icons.push_pin_rounded),
                    ),
                    title: const Text('Pinned messages'),
                  ),
                ),
              if (isNarrow && onShowThreads != null)
                PopupMenuItem(
                  value: _ChatMenuAction.threads,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: threadUnreadCount > 0
                        ? Badge.count(
                            count: threadUnreadCount,
                            child: const Icon(Icons.forum_outlined),
                          )
                        : const Icon(Icons.forum_outlined),
                    title: const Text('Threads'),
                  ),
                ),
              const PopupMenuItem(
                value: _ChatMenuAction.details,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Room details'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

/// App bar subtitle: the counterpart's presence for a DM, falling back to the
/// member count when presence is unknown or the room is not a direct chat.
class _HeaderSubtitle extends StatelessWidget {
  const _HeaderSubtitle({
    required this.room,
    required this.style,
    this.presence,
    this.userId,
  });

  final Room room;
  final TextStyle? style;
  final PresenceService? presence;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final presence = this.presence;
    final userId = this.userId;
    if (presence == null || userId == null) {
      return Text(_memberCountLabel(room), style: style);
    }
    return ListenableBuilder(
      listenable: presence,
      builder: (context, _) {
        final label =
            _presenceLabel(presence.presenceFor(userId)) ?? _memberCountLabel(room);
        return Text(
          label,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

String _memberCountLabel(Room room) {
  final count = room.summary.mJoinedMemberCount ?? 0;
  if (count == 0) return '';
  if (count == 1) return '1 member';
  return '$count members';
}

/// Human-readable presence line for a DM counterpart, or null when unknown.
/// A "last seen" suffix is appended only when the server provided a timestamp.
String? _presenceLabel(CachedPresence? presence) {
  if (presence == null) return null;
  final lastSeen = presence.lastActiveTimestamp;
  switch (presence.presence) {
    case PresenceType.online:
      return 'Online';
    case PresenceType.unavailable:
      return lastSeen != null ? 'Away · last seen ${_ago(lastSeen)}' : 'Away';
    case PresenceType.offline:
      return lastSeen != null
          ? 'Offline · last seen ${_ago(lastSeen)}'
          : 'Offline';
  }
}

String _ago(DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

class _CallButton extends StatefulWidget {
  const _CallButton({required this.room});

  final Room room;

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton> {
  bool _starting = false;

  Future<void> _startCall(model.CallType type) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await CallNavigator.startCall(
        context,
        roomId: widget.room.id,
        type: type,
      );
    } catch (e) {
      if (mounted) context.showSnack('Failed to start call');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final callState = callService.callState;
    final roomHasCall = callService.roomHasActiveCall(widget.room.id);
    final isInCall = callService.activeCallRoomId == widget.room.id;
    final busy = _starting ||
        (callState != KoheraCallState.idle &&
            callState != KoheraCallState.failed &&
            !roomHasCall);

    if (roomHasCall && !isInCall) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: TextButton.icon(
          icon: const Icon(Icons.call_rounded),
          label: const Text('Join'),
          style: TextButton.styleFrom(foregroundColor: Colors.green),
          onPressed: busy ? null : () => _startCall(model.CallType.voice),
        ),
      );
    }

    if (isInCall) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PopupMenuButton<String>(
        icon: Icon(Icons.call_rounded, color: Colors.green.shade400),
        tooltip: 'In call',
        onSelected: (value) {
          if (value == 'go') {
            context.pushOrGo(
              Routes.call,
              pathParameters: {RouteParams.roomId: widget.room.id},
            );
          } else if (value == 'leave') {
            unawaited(CallNavigator.endCall(context));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'go',
            child: ListTile(
              leading: Icon(Icons.open_in_new_rounded),
              title: Text('Go to call'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'leave',
            child: ListTile(
              leading: Icon(Icons.call_end_rounded, color: Colors.red),
              title: Text('Leave call'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      );
    }

    return IconButton(
      mouseCursor: SystemMouseCursors.click,
      icon: const Icon(Icons.call_rounded),
      tooltip: 'Call',
      onPressed: busy ? null : () => _startCall(model.CallType.voice),
    );
  }
}

class ChatSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatSearchAppBar({
    required this.controller, required this.focusNode, required this.onChanged, required this.onClose, super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onClose,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: tt.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search messages…',
          border: InputBorder.none,
          hintStyle: tt.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      actions: [
        if (controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              controller.clear();
              onChanged('');
              focusNode.requestFocus();
            },
          ),
      ],
    );
  }
}

enum _ChatMenuAction { pinned, threads, details }
