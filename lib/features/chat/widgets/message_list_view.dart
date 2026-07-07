import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/models/chat_message_data.dart';
import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';
import 'package:kohera/features/chat/widgets/call_event_tile.dart';
import 'package:kohera/features/chat/widgets/chat_message_item.dart';
import 'package:kohera/features/chat/widgets/irc_message_tile.dart';
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:kohera/features/chat/widgets/state_event_tile.dart';
import 'package:kohera/features/chat/widgets/sticker_bubble.dart';
import 'package:kohera/features/chat/widgets/sticker_message_item.dart';
import 'package:kohera/features/chat/widgets/unread_divider.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class MessageListView extends StatefulWidget {
  const MessageListView({
    required this.controller,
    required this.mentionResolver,
    required this.onReply,
    required this.onEdit,
    required this.onToggleReaction,
    required this.onPin,
    required this.onHighlight,
    this.highlightedEventId,
    this.onScrollBack,
    this.onReplyInThread,
    this.onOpenThread,
    this.onForward,
    this.emptyText,
    this.extraLoading = false,
    this.onLoadMoreExtra,
    this.onOpenContextMenu,
    this.onShowMobileActions,
    this.onTapSender,
    this.onDelete,
    this.buildReplyPreview,
    this.onStickerContextMenu,
    this.onStickerMobileActions,
    super.key,
  });

  final MessageTimelineController controller;
  final MentionDisplayNameResolver? mentionResolver;
  final String? highlightedEventId;
  final void Function(String eventId) onReply;
  final void Function(String eventId) onEdit;
  final Future<void> Function(String eventId, String emoji) onToggleReaction;
  final Future<void> Function(String eventId) onPin;
  final void Function(String eventId) onHighlight;
  final VoidCallback? onScrollBack;
  final void Function(String eventId)? onReplyInThread;
  final void Function(String eventId)? onOpenThread;
  final void Function(String eventId)? onForward;
  final String? emptyText;
  final bool extraLoading;
  final VoidCallback? onLoadMoreExtra;

  final void Function(
    BuildContext,
    String eventId,
    Offset position,
    bool isPinned,
    bool canPin,
  )? onOpenContextMenu;
  final void Function(
    BuildContext,
    String eventId,
    Rect rect,
    bool isPinned,
    bool canPin,
  )? onShowMobileActions;
  final void Function(BuildContext, String eventId)? onTapSender;
  final void Function(BuildContext, String eventId)? onDelete;
  final Widget? Function(
    String eventId,
    bool isMe,
    void Function(String)? onParentTap,
  )? buildReplyPreview;
  final void Function(BuildContext, String eventId, Offset)?
      onStickerContextMenu;
  final void Function(BuildContext, String eventId, Rect)?
      onStickerMobileActions;

  @override
  State<MessageListView> createState() => MessageListViewState();
}

class MessageListViewState extends State<MessageListView> {
  static const _historyLoadThreshold = 15;
  static const _scrollAnimationDuration = Duration(milliseconds: 400);
  static const _scrollBackDismissThreshold = 120.0;

  final _itemScrollCtrl = ItemScrollController();
  final _itemPosListener = ItemPositionsListener.create();
  double _scrollBackDelta = 0;
  bool _scrollBackFired = false;

  MessageTimelineController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _itemPosListener.itemPositions.addListener(_onScroll);
    controller.addListener(_onControllerChanged);
    unawaited(_initAndJump());
  }

  Future<void> _initAndJump() async {
    await controller.init();
    if (mounted && controller.initialEventId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) navigateToEventById(controller.initialEventId!);
      });
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      controller.addListener(_onControllerChanged);
    }
  }

  // ── Scroll & history ───────────────────────────────────

  void _onScroll() {
    final positions = _itemPosListener.itemPositions.value;
    if (positions.isEmpty) return;
    final maxIndex =
        positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (maxIndex < controller.messageCount - _historyLoadThreshold) return;
    if (controller.isThread) {
      if (!widget.extraLoading) widget.onLoadMoreExtra?.call();
      return;
    }
    if (!controller.isLoadingHistory) {
      unawaited(
        controller.loadMore(
          shouldContinue: () {
            if (!mounted) return false;
            final pos = _itemPosListener.itemPositions.value;
            if (pos.isEmpty) return false;
            final maxIdx =
                pos.map((p) => p.index).reduce((a, b) => a > b ? a : b);
            return maxIdx >= controller.messageCount - _historyLoadThreshold;
          },
        ),
      );
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.onScrollBack == null) return false;
    if (notification is ScrollStartNotification) {
      _scrollBackDelta = 0;
      _scrollBackFired = false;
    } else if (notification is ScrollUpdateNotification) {
      _scrollBackDelta += notification.scrollDelta ?? 0;
      if (!_scrollBackFired &&
          _scrollBackDelta >= _scrollBackDismissThreshold) {
        _scrollBackFired = true;
        widget.onScrollBack!.call();
      }
    }
    return false;
  }

  // ── Navigation ─────────────────────────────────────────

  void navigateToEventById(String eventId) {
    unawaited(_navigateToEventById(eventId));
  }

  Future<void> _navigateToEventById(String eventId) async {
    var index = controller.indexOf(eventId);
    if (index == -1) {
      debugPrint('[Kohera] Event not in loaded timeline, reloading: $eventId');
      await controller.reloadTimelineAt(eventId);
      index = controller.indexOf(eventId);
    }
    if (index == -1) {
      debugPrint('[Kohera] Event not found after context load: $eventId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the target message'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _scrollToIndex(index, eventId);
  }

  void _scrollToIndex(int index, String eventId) {
    widget.onHighlight(eventId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollCtrl.isAttached) {
        unawaited(
          _itemScrollCtrl.scrollTo(
            index: index,
            duration: _scrollAnimationDuration,
            curve: Curves.easeInOut,
            alignment: 0.5,
          ),
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!controller.isReady) {
      return const Center(child: KoheraLoader());
    }

    final messages = controller.messages;
    if (messages.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      return Center(
        child: Text(
          widget.emptyText ?? 'No messages yet.\nSay hello!',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final isMobile = isTouchDevice;
    final matrix = context.read<MatrixService>();
    final timelineStyle = context.watch<PreferencesService>().timelineStyle;
    final avatarResolver = matrix.avatarResolver;
    final mediaResolver = matrix.mediaResolver;
    final receiptMap = controller.receipts;
    final hasLoadingIndicator =
        controller.isLoadingHistory || widget.extraLoading;
    final totalCount = messages.length + (hasLoadingIndicator ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollCtrl,
        itemPositionsListener: _itemPosListener,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: totalCount,
        itemBuilder: (context, i) {
          if (hasLoadingIndicator && i == totalCount - 1) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final data = messages[i];
          final tile = _buildTile(
            context,
            data,
            isMobile,
            avatarResolver,
            mediaResolver,
            receiptMap,
            timelineStyle,
          );

          if (_shouldShowUnreadDivider(data, i)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                const UnreadDivider(),
              ],
            );
          }
          return tile;
        },
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    ChatMessageData data,
    bool isMobile,
    AvatarResolver avatarResolver,
    MediaResolver mediaResolver,
    Map<String, List<KoheraReadReceipt>> receiptMap,
    TimelineStyle timelineStyle,
  ) {
    switch (data.category) {
      case MessageCategory.callEvent:
        return CallEventTile(
          message: data.message,
          isMe: data.isMe,
          duration: data.callDuration,
        );
      case MessageCategory.stateEvent:
        return StateEventTile(item: data.stateEventText!);
      case MessageCategory.sticker:
        return _buildStickerTile(
          context,
          data,
          isMobile,
          avatarResolver,
        );
      case MessageCategory.message:
        return timelineStyle == TimelineStyle.irc
            ? _buildIrcMessageTile(context, data, isMobile)
            : _buildMessageTile(
                context,
                data,
                isMobile,
                avatarResolver,
                mediaResolver,
                receiptMap,
              );
    }
  }

  Widget _buildStickerTile(
    BuildContext context,
    ChatMessageData data,
    bool isMobile,
    AvatarResolver avatarResolver,
  ) {
    return StickerMessageItem(
      key: ValueKey(data.eventId),
      message: data.message,
      stickerWidget: StickerBubble(
        media: data.media!,
        controller: data.mediaController!,
        isMe: data.isMe,
      ),
      isMe: data.isMe,
      isMobile: isMobile,
      reactionWidget: (data.reactions != null && data.reactions!.isNotEmpty)
          ? ReactionChips(
              reactions: data.reactions!,
              isMe: data.isMe,
              avatarResolver: avatarResolver,
              onToggle: (emoji) => widget.onToggleReaction(data.eventId, emoji),
            )
          : null,
      onToggleReaction: (eventId, emoji) =>
          widget.onToggleReaction(data.eventId, emoji),
      onReply: (eventId) => widget.onReply(data.eventId),
      onPin: (eventId) => widget.onPin(data.eventId),
      onForward: widget.onForward != null
          ? (eventId) => widget.onForward!(data.eventId)
          : null,
      onOpenContextMenu: (position) =>
          widget.onStickerContextMenu?.call(context, data.eventId, position),
      onShowMobileActions: (rect) =>
          widget.onStickerMobileActions?.call(context, data.eventId, rect),
      highlightedEventId: widget.highlightedEventId,
      isPinned: data.isPinned,
    );
  }

  Widget _buildIrcMessageTile(
    BuildContext context,
    ChatMessageData data,
    bool isMobile,
  ) {
    return IrcMessageTile(
      message: data.message,
      reactions: data.reactions,
      media: data.media,
      isMe: data.isMe,
      isFirst: data.isFirst,
      isMobile: isMobile,
      isPinned: data.isPinned,
      canPin: data.canPin,
      canRedact: data.canRedact,
      hasThread: data.hasThread,
      threadReplyCount: data.threadReplyCount,
      threadUnreadCount: data.threadUnreadCount,
      inThread: controller.isThread,
      highlightedEventId: widget.highlightedEventId,
      mentionResolver: widget.mentionResolver,
      onToggleReaction: (emoji) => widget.onToggleReaction(data.eventId, emoji),
      onReply: () => widget.onReply(data.eventId),
      onEdit: () => widget.onEdit(data.eventId),
      onPin: () => widget.onPin(data.eventId),
      onReplyInThread: widget.onReplyInThread != null
          ? () => widget.onReplyInThread!(data.eventId)
          : null,
      onOpenThread: widget.onOpenThread != null
          ? () => widget.onOpenThread!(data.eventId)
          : null,
      onForward: widget.onForward != null
          ? () => widget.onForward!(data.eventId)
          : null,
      onOpenContextMenu: (position) => widget.onOpenContextMenu
          ?.call(context, data.eventId, position, data.isPinned, data.canPin),
      onShowMobileActions: (rect) => widget.onShowMobileActions
          ?.call(context, data.eventId, rect, data.isPinned, data.canPin),
      onTapSender: widget.onTapSender,
      onDelete: () => widget.onDelete?.call(context, data.eventId),
      onTapReply: navigateToEventById,
    );
  }

  Widget _buildMessageTile(
    BuildContext context,
    ChatMessageData data,
    bool isMobile,
    AvatarResolver avatarResolver,
    MediaResolver mediaResolver,
    Map<String, List<KoheraReadReceipt>> receiptMap,
  ) {
    return ChatMessageItem(
      message: data.message,
      reactions: data.reactions,
      media: data.media,
      mediaController: data.mediaController,
      replyPreview:
          data.message.replyEventId != null && !data.message.isRedacted
              ? widget.buildReplyPreview?.call(
                  data.eventId,
                  data.isMe,
                  navigateToEventById,
                )
              : null,
      isMe: data.isMe,
      isFirst: data.isFirst,
      isMobile: isMobile,
      isPinned: data.isPinned,
      canPin: data.canPin,
      canRedact: data.canRedact,
      hasThread: data.hasThread,
      threadReplyCount: data.threadReplyCount,
      threadUnreadCount: data.threadUnreadCount,
      inThread: controller.isThread,
      highlightedEventId: widget.highlightedEventId,
      receiptMap: receiptMap,
      avatarResolver: avatarResolver,
      mediaResolver: mediaResolver,
      mentionResolver: widget.mentionResolver ?? (_) => null,
      onToggleReaction: (emoji) => widget.onToggleReaction(data.eventId, emoji),
      onReply: () => widget.onReply(data.eventId),
      onEdit: () => widget.onEdit(data.eventId),
      onPin: () => widget.onPin(data.eventId),
      onReplyInThread: widget.onReplyInThread != null
          ? () => widget.onReplyInThread!(data.eventId)
          : null,
      onOpenThread: widget.onOpenThread != null
          ? () => widget.onOpenThread!(data.eventId)
          : null,
      onForward: widget.onForward != null
          ? () => widget.onForward!(data.eventId)
          : null,
      onOpenContextMenu: (position) => widget.onOpenContextMenu
          ?.call(context, data.eventId, position, data.isPinned, data.canPin),
      onShowMobileActions: (rect) => widget.onShowMobileActions
          ?.call(context, data.eventId, rect, data.isPinned, data.canPin),
      onTapSender: () => widget.onTapSender?.call(context, data.eventId),
      onDelete: () => widget.onDelete?.call(context, data.eventId),
      onTapReply: navigateToEventById,
    );
  }

  bool _shouldShowUnreadDivider(ChatMessageData data, int index) {
    final markerId = controller.fullyReadMarkerId;
    if (markerId == null) return false;
    if (data.eventId != markerId) return false;
    if (index == 0) return false;
    return true;
  }

  @override
  void dispose() {
    _itemPosListener.itemPositions.removeListener(_onScroll);
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }
}
