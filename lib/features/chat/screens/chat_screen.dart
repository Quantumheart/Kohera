import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/chat/screens/thread_list_screen.dart';
import 'package:kohera/features/chat/screens/thread_screen.dart';
import 'package:kohera/features/chat/services/chat_message_actions.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/services/emoji_autocomplete_controller.dart';
import 'package:kohera/features/chat/services/file_send_handler.dart';
import 'package:kohera/features/chat/services/gif_send_handler.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';
import 'package:kohera/features/chat/services/mention_autocomplete_controller.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:kohera/features/chat/services/message_forwarder.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';
import 'package:kohera/features/chat/services/paste_image_handler.dart';
import 'package:kohera/features/chat/services/photo_send_handler.dart';
import 'package:kohera/features/chat/services/reply_preview_resolver.dart';
import 'package:kohera/features/chat/services/thread_roots_service.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/features/chat/services/typing_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_mixin.dart';
import 'package:kohera/features/chat/services/web_image_paste.dart';
import 'package:kohera/features/chat/widgets/attachment_source_sheet.dart';
import 'package:kohera/features/chat/widgets/chat_app_bar.dart';
import 'package:kohera/features/chat/widgets/compose_bar_section.dart';
import 'package:kohera/features/chat/widgets/create_poll_dialog.dart';
import 'package:kohera/features/chat/widgets/delete_event_dialog.dart';
import 'package:kohera/features/chat/widgets/desktop_drop_wrapper.dart';
import 'package:kohera/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:kohera/features/chat/widgets/forward_message_dialog.dart';
import 'package:kohera/features/chat/widgets/join_call_banner.dart';
import 'package:kohera/features/chat/widgets/message_action_sheet.dart';
import 'package:kohera/features/chat/widgets/message_bubble_context_menu.dart';
import 'package:kohera/features/chat/widgets/message_list_view.dart';
import 'package:kohera/features/chat/widgets/reply_preview_host.dart';
import 'package:kohera/features/chat/widgets/search_results_body.dart';
import 'package:kohera/features/chat/widgets/sticker_picker_overlay.dart';
import 'package:kohera/features/chat/widgets/typing_indicator.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/services/member_sheet_launcher.dart';
import 'package:kohera/shared/services/room_summary_resolver.dart';
import 'package:provider/provider.dart';


class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.roomId,
    super.key,
    this.initialEventId,
    this.onBack,
    this.onShowDetails,
  });

  final String roomId;
  final String? initialEventId;

  /// On narrow layouts, called to pop back to room list.
  final VoidCallback? onBack;

  /// On desktop, called to toggle the room details side panel.
  final VoidCallback? onShowDetails;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with VoiceRecordingMixin<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _composeFocusNode = FocusNode(debugLabel: 'chat-compose');
  final _messageListKey = GlobalKey<MessageListViewState>();

  late MessageTimelineController _timelineController;

  // ── Compose state ───────────────────────────────────────
  final _compose = ComposeStateController();

  /// Whether the inline emoji & sticker panel is shown above the compose bar.
  bool _emojiPanelOpen = false;

  // ── Typing ─────────────────────────────────────────────
  TypingController? _typingCtrl;

  // ── Voice recording ─────────────────────────────────────
  VoiceRecordingController? _voiceCtrl;

  @override
  VoiceRecordingController? get voiceController => _voiceCtrl;
  @override
  ValueNotifier<UploadState?> get voiceUploadNotifier =>
      _compose.uploadNotifier;
  @override
  String get voiceRoomId => widget.roomId;

  bool get _isDesktop => isNativeDesktop;

  // ── Message actions ──────────────────────────────────────
  late ChatMessageActions _actions;

  // ── Thread side pane (desktop) ─────────────────────────
  String? _activeThreadEventId;
  bool _showThreadList = false;

  // ── Thread unread count (fetched from server) ───────────
  int _threadUnreadCount = 0;
  StreamSubscription<dynamic>? _threadCountSyncSub;
  Timer? _threadCountDebounce;

  // ── Web paste ───────────────────────────────────────────
  StreamSubscription<ClipboardImageData>? _webPasteSub;

  // ── Search ─────────────────────────────────────────────
  late ChatSearchController _search;
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'chat-search');

  @override
  void initState() {
    super.initState();
    final matrix = context.read<MatrixService>();
    final prefs = context.read<PreferencesService>();
    _timelineController = MessageTimelineController(
      matrix: matrix,
      roomId: widget.roomId,
      sendPublicReadReceipts: prefs.readReceipts,
      initialEventId: widget.initialEventId,
      onTimelineChanged: _onTimelineChanged,
    );
    _actions = _createActions();
    _search = _createSearchController();
    _initControllers();
    _composeFocusNode.addListener(_onComposeFocusChanged);
    unawaited(_timelineController.init());
    if (kIsWeb) {
      initWebPasteListener();
      _webPasteSub = webPasteImageStream.listen(_onWebPasteImage);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _refreshThreadUnreadCount());
  }

  Future<void> _refreshThreadUnreadCount() async {
    if (!mounted) return;
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;
    try {
      final summaries = await fetchThreadSummaries(
        client: matrix.client,
        room: room,
      );
      if (!mounted) return;
      setState(() => _threadUnreadCount = totalThreadUnread(summaries));
      _threadCountSyncSub ??= matrix.client.onSync.stream.listen((_) {
        if (!mounted) return;
        _threadCountDebounce?.cancel();
        _threadCountDebounce = Timer(
          const Duration(seconds: 30),
          () => unawaited(_refreshThreadUnreadCount()),
        );
      });
    } catch (_) {}
  }

  void _onComposeFocusChanged() {
    // Focusing the input (e.g. to type) closes the inline emoji panel so the
    // keyboard can take its place.
    if (_composeFocusNode.hasFocus && _emojiPanelOpen) {
      setState(() => _emojiPanelOpen = false);
    }
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.roomId != widget.roomId ||
        old.initialEventId != widget.initialEventId) {
      _timelineController.dispose();
      final matrix = context.read<MatrixService>();
      final prefs = context.read<PreferencesService>();
      _timelineController = MessageTimelineController(
        matrix: matrix,
        roomId: widget.roomId,
        sendPublicReadReceipts: prefs.readReceipts,
        initialEventId: widget.initialEventId,
        onTimelineChanged: _onTimelineChanged,
      );
      unawaited(_timelineController.init());
      _compose.reset(_msgCtrl);
      _typingCtrl?.dispose();
      _voiceCtrl?.dispose();
      _mentionController?.dispose();
      _emojiController?.dispose();
      _initControllers();
      _search.removeListener(_onSearchChanged);
      _search.dispose();
      _actions = _createActions();
      _search = _createSearchController();
      unawaited(_threadCountSyncSub?.cancel() ?? Future.value());
      _threadCountSyncSub = null;
      _threadCountDebounce?.cancel();
      _threadCountDebounce = null;
      _threadUnreadCount = 0;
      unawaited(_refreshThreadUnreadCount());
    }
  }

  MentionAutocompleteController? _mentionController;
  EmojiAutocompleteController? _emojiController;

  void _initControllers() {
    final room =
        context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room != null) {
      _typingCtrl = TypingController(room: room);
      _voiceCtrl = VoiceRecordingController();
      final joinedRooms = context.read<SelectionService>().rooms;
      _mentionController = MentionAutocompleteController(
        textController: _msgCtrl,
        room: room,
        joinedRooms: joinedRooms,
      );
      final stickerService = context.read<StickerPackService>();
      _emojiController = EmojiAutocompleteController(
        textController: _msgCtrl,
        stickerPackService: stickerService,
        room: room,
      );
    }
  }

  ChatMessageActions _createActions() {
    return ChatMessageActions(
      getRoomId: () => widget.roomId,
      getRoom: () =>
          context.read<MatrixService>().client.getRoomById(widget.roomId),
      getTimeline: () => _timelineController.timeline,
      compose: _compose,
      msgCtrl: _msgCtrl,
      getScaffold: () => ScaffoldMessenger.of(context),
      getMatrixService: () => context.read<MatrixService>(),
    );
  }

  ChatSearchController _createSearchController() {
    return ChatSearchController(
      roomId: widget.roomId,
      getRoom: () =>
          context.read<MatrixService>().client.getRoomById(widget.roomId),
    )..addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  // ── Reply / Edit helpers ────────────────────────────────

  void _setReplyTo(String eventId) {
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    _compose.setReplyTo(event);
    _composeFocusNode.requestFocus();
  }

  void _openThread(String eventId) {
    if (_isDesktop) {
      setState(() {
        _activeThreadEventId = eventId;
        _showThreadList = false;
      });
      return;
    }
    unawaited(
      context.pushNamed(
        Routes.roomThread,
        pathParameters: {
          RouteParams.roomId: widget.roomId,
          RouteParams.eventId: eventId,
        },
      ),
    );
  }

  void _closeThread() {
    setState(() => _activeThreadEventId = null);
  }

  void _onTimelineChanged() {
    if (mounted) setState(() {});
  }

  void _openThreadList() {
    if (_isDesktop) {
      setState(() {
        _showThreadList = true;
        _activeThreadEventId = null;
      });
      return;
    }
    unawaited(
      context.pushNamed(
        Routes.roomThreads,
        pathParameters: {RouteParams.roomId: widget.roomId},
      ),
    );
  }

  void _closeThreadList() {
    setState(() => _showThreadList = false);
  }

  void _replyInThread(String eventId) {
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    final timeline = _timelineController.timeline;
    final rootId = event.relationshipType == 'm.thread'
        ? (event.relationshipEventId ?? event.eventId)
        : event.eventId;
    final root = timeline?.events.firstWhere(
          (e) => e.eventId == rootId,
          orElse: () => event,
        ) ??
        event;
    _openThread(root.eventId);
  }

  void _forwardMessage(String eventId) {
    final matrix = context.read<MatrixService>();
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    final timeline = _timelineController.timeline;
    const resolver = RoomSummaryResolver();
    final myUserId = matrix.client.userID;
    final targets = matrix.client.rooms
        .where((r) => r.membership.name == 'join' && !r.isSpace)
        .map((r) => resolver(r, myUserId: myUserId))
        .toList();
    unawaited(
      ForwardMessageDialog.show(
        context,
        targets: targets,
        avatarResolver: matrix.avatarResolver,
        onForward: (roomId) async {
          final target = matrix.client.getRoomById(roomId);
          if (target == null) return;
          await MessageForwarder.forward(
            event: event,
            target: target,
            timeline: timeline,
          );
        },
      ),
    );
  }

  void _dismissKeyboard() {
    if (_composeFocusNode.hasFocus) _composeFocusNode.unfocus();
  }

  // ── Mention resolver ───────────────────────────────────

  MentionDisplayNameResolver _buildMentionResolver(String roomId) {
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(roomId);
    if (room == null) {
      return (_) => null;
    }
    return (String identifier) {
      if (identifier.startsWith('@')) {
        try {
          return room.unsafeGetUserFromMemoryOrFallback(identifier).displayName;
        } catch (_) {
          return null;
        }
      } else if (identifier.startsWith('!')) {
        try {
          return room.client.getRoomById(identifier)?.getLocalizedDisplayname();
        } catch (_) {
          return null;
        }
      }
      return null;
    };
  }

  // ── Message action helpers ─────────────────────────────

  void _showContextMenu(
    BuildContext context,
    String eventId,
    Offset position,
    bool isPinned,
    bool canPin,
  ) {
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    final isMe = event.senderId == _timelineController.myUserId;
    final isRedacted = event.redacted;
    final isFailed = event.status.name == 'error';
    final copyableBody = stripReplyFallback(
      _timelineController.timeline != null
          ? event.getDisplayEvent(_timelineController.timeline!).body
          : event.body,
    );
    unawaited(
      showMessageContextMenu(
        context,
        isMe: isMe,
        isPinned: isPinned,
        isFailed: isFailed,
        isRedacted: isRedacted,
        copyableBody: copyableBody,
        position: position,
        onReply: isRedacted ? null : () => _setReplyTo(eventId),
        onEdit: !isRedacted && isMe
            ? () => _compose.setEditEvent(
                  event,
                  _timelineController.timeline,
                  _msgCtrl,
                )
            : null,
        onReact: isRedacted
            ? null
            : () => showEmojiPickerSheet(
                  context,
                  (emoji) => unawaited(_actions.toggleReaction(event, emoji)),
                ),
        onPin: canPin ? () => unawaited(_actions.togglePin(event)) : null,
        onDelete: !isRedacted && event.canRedact
            ? () => confirmAndDeleteEvent(
                  context,
                  isMe: isMe,
                  onRedact: () => event.room.redactEvent(event.eventId),
                )
            : null,
        onReplyInThread: isRedacted ? null : () => _replyInThread(eventId),
        onForward: isRedacted
            ? null
            : () => _forwardMessage(eventId),
        onRetrySend: () async {
          try {
            await event.sendAgain();
          } catch (e) {
            debugPrint('[Kohera] outbox: retry from menu failed: $e');
          }
        },
        onDiscardSend: () async {
          try {
            await event.cancelSend();
          } catch (e) {
            debugPrint('[Kohera] outbox: discard from menu failed: $e');
          }
        },
      ),
    );
  }

  void _showMobileActions(
    BuildContext context,
    String eventId,
    Rect bubbleRect,
    bool isPinned,
    bool canPin,
  ) {
    final event = _timelineController.getEventById(eventId);
    if (event == null || event.redacted) return;
    final isMe = event.senderId == _timelineController.myUserId;
    final cs = Theme.of(context).colorScheme;
    final List<MessageAction> actions;
    if (event.status.name == 'error') {
      actions = [
        MessageAction(
          label: 'Retry sending',
          icon: Icons.refresh_rounded,
          onTap: () async {
            try {
              await event.sendAgain();
            } catch (e) {
              debugPrint('[Kohera] outbox: retry from menu failed: $e');
            }
          },
        ),
        MessageAction(
          label: 'Discard message',
          icon: Icons.delete_outline_rounded,
          onTap: () async {
            try {
              await event.cancelSend();
            } catch (e) {
              debugPrint('[Kohera] outbox: discard from menu failed: $e');
            }
          },
          color: cs.error,
        ),
      ];
    } else {
      actions = [
        MessageAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          onTap: () => _setReplyTo(eventId),
        ),
        MessageAction(
          label: 'Reply in thread',
          icon: Icons.forum_outlined,
          onTap: () => _replyInThread(eventId),
        ),
        MessageAction(
          label: 'Forward',
          icon: Icons.forward_rounded,
          onTap: () => _forwardMessage(eventId),
        ),
        if (isMe)
          MessageAction(
            label: 'Edit',
            icon: Icons.edit_rounded,
            onTap: () => _compose.setEditEvent(
              event,
              _timelineController.timeline,
              _msgCtrl,
            ),
          ),
        MessageAction(
          label: 'React',
          icon: Icons.add_reaction_outlined,
          onTap: () => showEmojiPickerSheet(
            context,
            (emoji) => unawaited(_actions.toggleReaction(event, emoji)),
          ),
        ),
        if (canPin)
          MessageAction(
            label: isPinned ? 'Unpin' : 'Pin',
            icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            onTap: () => unawaited(_actions.togglePin(event)),
          ),
        MessageAction(
          label: 'Copy',
          icon: Icons.copy_rounded,
          onTap: () {
            final displayEvent = _timelineController.timeline != null
                ? event.getDisplayEvent(_timelineController.timeline!)
                : event;
            unawaited(
              Clipboard.setData(
                ClipboardData(text: stripReplyFallback(displayEvent.body)),
              ),
            );
          },
        ),
        if (event.canRedact)
          MessageAction(
            label: isMe ? 'Delete' : 'Remove',
            icon: Icons.delete_outline_rounded,
            onTap: () => confirmAndDeleteEvent(
                  context,
                  isMe: isMe,
                  onRedact: () => event.room.redactEvent(event.eventId),
                ),
            color: cs.error,
          ),
      ];
    }
    final matrix = context.read<MatrixService>();
    final message = const MessageDisplayResolver()(
      event,
      timeline: _timelineController.timeline,
    );
    showMessageActionSheet(
      context: context,
      message: message,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      avatarResolver: matrix.avatarResolver,
      mentionResolver: _buildMentionResolver(event.room.id),
      mediaResolver: matrix.mediaResolver,
      onQuickReact: (emoji) => unawaited(_actions.toggleReaction(event, emoji)),
    );
  }

  void _showSenderSheet(BuildContext context, String eventId) {
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    final sender = event.senderFromMemoryOrFallback;
    final room = event.room;
    final member = KoheraRoomMember(
      userId: sender.id,
      displayname: sender.calcDisplayname(),
      avatarUrl: sender.avatarUrl?.toString(),
      membership: sender.membership.name,
      powerLevel: room.getPowerLevelByUserId(sender.id).level,
    );
    unawaited(showRoomMemberSheet(context, room: room, member: member));
  }

  void _showStickerContextMenu(
    BuildContext context,
    String eventId,
    Offset position,
  ) {
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    final isMe = event.senderId == _timelineController.myUserId;
    final isPinned = event.room.pinnedEventIds.contains(event.eventId);
    final copyableBody = event.content['url'] as String? ?? '';
    unawaited(
      showMessageContextMenu(
        context,
        isMe: isMe,
        isPinned: isPinned,
        isFailed: event.status.name == 'error',
        isRedacted: event.redacted,
        copyableBody: copyableBody,
        position: position,
        onReply: () => _setReplyTo(eventId),
        onReact: () => showEmojiPickerSheet(
          context,
          (emoji) => unawaited(_actions.toggleReaction(event, emoji)),
        ),
        onPin: () => unawaited(_actions.togglePin(event)),
        onForward: () => _forwardMessage(eventId),
      ),
    );
  }

  void _showStickerMobileActions(
    BuildContext context,
    String eventId,
    Rect bubbleRect,
  ) {
    final event = _timelineController.getEventById(eventId);
    if (event == null) return;
    final isMe = event.senderId == _timelineController.myUserId;
    final cs = Theme.of(context).colorScheme;
    final isPinned = event.room.pinnedEventIds.contains(event.eventId);
    final matrix = context.read<MatrixService>();
    final message = const MessageDisplayResolver()(
      event,
      timeline: _timelineController.timeline,
    );
    showMessageActionSheet(
      context: context,
      message: message,
      isMe: isMe,
      bubbleRect: bubbleRect,
      avatarResolver: matrix.avatarResolver,
      mentionResolver: _buildMentionResolver(event.room.id),
      mediaResolver: matrix.mediaResolver,
      onQuickReact: (emoji) => unawaited(_actions.toggleReaction(event, emoji)),
      actions: [
        MessageAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          onTap: () => _setReplyTo(eventId),
        ),
        MessageAction(
          label: 'React',
          icon: Icons.add_reaction_outlined,
          onTap: () => showEmojiPickerSheet(
            context,
            (emoji) => unawaited(_actions.toggleReaction(event, emoji)),
          ),
        ),
        MessageAction(
          label: 'Forward',
          icon: Icons.forward_rounded,
          onTap: () => _forwardMessage(eventId),
        ),
        MessageAction(
          label: isPinned ? 'Unpin' : 'Pin',
          icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          onTap: () => unawaited(_actions.togglePin(event)),
        ),
        MessageAction(
          label: 'Copy link',
          icon: Icons.link_rounded,
          onTap: () {
            unawaited(
              Clipboard.setData(
                ClipboardData(
                  text: event.content['url'] as String? ?? '',
                ),
              ),
            );
          },
          color: cs.onSurface,
        ),
      ],
    );
  }

  // ── Attachments ─────────────────────────────────────────

  void _addAttachment(PendingAttachment attachment) {
    _showAttachmentError(_compose.addAttachment(attachment));
  }

  Future<void> _handleAttachPressed() async {
    final isMobileTouch = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    if (!isMobileTouch) {
      final attachment = await pickFileAsAttachment();
      if (attachment != null && mounted) _addAttachment(attachment);
      return;
    }

    final source = await showAttachmentSourceSheet(
      context,
      showGif: _giphyEnabled,
      showSticker: true,
    );
    if (source == null || !mounted) return;

    switch (source) {
      case AttachmentSource.gif:
        await _handleGifPressed();
      case AttachmentSource.sticker:
        _toggleStickerPicker();
      case AttachmentSource.poll:
        final draft = await CreatePollDialog.show(context);
        if (draft != null && mounted) await _actions.sendPoll(draft);
      case AttachmentSource.file:
        final attachment = await pickFileAsAttachment();
        if (attachment != null && mounted) _addAttachment(attachment);
      case AttachmentSource.camera:
        final attachment = await takePhotoWithCamera();
        if (attachment != null && mounted) _addAttachment(attachment);
      case AttachmentSource.gallery:
        final remaining = ComposeStateController.maxAttachments -
            _compose.pendingAttachments.value.length;
        if (remaining <= 0) {
          _showAttachmentError(AddAttachmentResult.tooMany);
          return;
        }
        final picked = await pickMediaFromGallery(limit: remaining);
        if (!mounted) return;
        for (final attachment in picked) {
          final result = _compose.addAttachment(attachment);
          if (result != AddAttachmentResult.ok) {
            _showAttachmentError(result);
            break;
          }
        }
    }
  }

  Future<void> _handlePasteImage() async {
    final result = await _compose.handlePasteImage();
    if (mounted && result != null) _showAttachmentError(result);
  }

  void _onWebPasteImage(ClipboardImageData data) {
    if (!mounted || !_composeFocusNode.hasFocus) return;
    final name = generatePasteFilename(data.mimeType);
    _showAttachmentError(
      _compose.addAttachment(
        PendingAttachment.fromBytes(bytes: data.bytes, name: name),
      ),
    );
  }

  void _showAttachmentError(AddAttachmentResult result) {
    switch (result) {
      case AddAttachmentResult.ok:
        return;
      case AddAttachmentResult.tooMany:
        context.showSnack(
          'Maximum ${ComposeStateController.maxAttachments} attachments allowed',
        );
      case AddAttachmentResult.tooLarge:
        context.showSnack('File exceeds 25 MB limit');
    }
  }

  // ── Search methods ────────────────────────────────────────

  void _openSearch() {
    _search.open();
    _searchCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _search.close();
    _searchCtrl.clear();
  }

  void _scrollToEventById(String eventId, {bool closeSearch = true}) {
    if (closeSearch) _closeSearch();
    _messageListKey.currentState?.navigateToEventById(eventId);
  }

  // ── GIF ───────────────────────────────────────────────────

  bool get _giphyEnabled =>
      AppConfig.isInitialized && AppConfig.instance.giphyEnabled;

  Future<void> _handleGifPressed() async {
    final room =
        context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) return;
    final gif = await GiphyGet.getGif(
      context: context,
      apiKey: AppConfig.instance.giphyApiKey!,
    );
    if (gif == null || !mounted) return;
    final url = gif.images?.downsized?.url ?? gif.images?.original?.url;
    if (url == null) return;
    await sendGifFromUrl(
      scaffold: ScaffoldMessenger.of(context),
      room: room,
      url: url,
      title: gif.title ?? 'giphy',
      uploadNotifier: _compose.uploadNotifier,
    );
  }

  // ── Sticker picker ────────────────────────────────────────

  void _toggleStickerPicker() {
    final isNarrow =
        MediaQuery.sizeOf(context).width < HomeShell.wideBreakpoint;
    if (isNarrow) {
      final matrix = context.read<MatrixService>();
      final room = matrix.client.getRoomById(widget.roomId);
      if (room != null) _openStickerSheet(matrix, room.id);
      return;
    }
    setState(() => _emojiPanelOpen = !_emojiPanelOpen);
    if (_emojiPanelOpen) {
      _composeFocusNode.unfocus();
    }
  }

  void _openStickerSheet(MatrixService matrix, String roomId) {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) return;
    final stickerService = context.read<StickerPackService>();
    final skinTone = context.read<PreferencesService>().skinTone;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetCtx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (_, _) => StickerPickerOverlay(
            packs: stickerService.packsForRoom(room),
            mediaResolver: matrix.mediaResolver,
            skinTone: skinTone,
            onStickerTapped: (sticker) {
              Navigator.of(sheetCtx).pop();
              unawaited(_handleStickerSelected(sticker));
            },
            onEmojiTapped: (emoji) {
              Navigator.of(sheetCtx).pop();
              _handleEmojiSelected(emoji);
            },
            onManagePacks: () {
              Navigator.of(sheetCtx).pop();
              context.goNamed(Routes.settingsStickerPacks);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiPanel(MatrixService matrix, String roomId) {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final stickerService = context.watch<StickerPackService>();
    final skinTone = context.watch<PreferencesService>().skinTone;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 16).clamp(0.0, 360.0);
    final height = (size.height * 0.45).clamp(240.0, 360.0);

    return Material(
      elevation: 8,
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: StickerPickerOverlay(
          packs: stickerService.packsForRoom(room),
          mediaResolver: matrix.mediaResolver,
          skinTone: skinTone,
          onStickerTapped: (sticker) {
            setState(() => _emojiPanelOpen = false);
            unawaited(_handleStickerSelected(sticker));
          },
          onEmojiTapped: _handleEmojiSelected,
          onManagePacks: () {
            setState(() => _emojiPanelOpen = false);
            context.goNamed(Routes.settingsStickerPacks);
          },
        ),
      ),
    );
  }

  Future<void> _handleStickerSelected(PackImage sticker) async {
    final room =
        context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) return;
    try {
      await room.sendEvent(
        {
          'body': sticker.altText,
          'url': sticker.url.toString(),
          'info': <String, Object?>{},
        },
        type: 'm.sticker',
      );
    } catch (e) {
      if (mounted) {
        context.showSnack(
          'Failed to send sticker: ${MatrixService.friendlyAuthError(e)}',
        );
      }
    }
  }

  void _handleEmojiSelected(PackImage emoji) {
    final text = _msgCtrl.text;
    final sel = _msgCtrl.selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final insertion =
        emoji.emoji != null ? '${emoji.emoji} ' : ':${emoji.shortcode}: ';
    _msgCtrl.value = TextEditingValue(
      text: text.substring(0, pos) + insertion + text.substring(pos),
      selection: TextSelection.collapsed(offset: pos + insertion.length),
    );
    _composeFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _timelineController.dispose();
    unawaited(_webPasteSub?.cancel() ?? Future.value());
    unawaited(_threadCountSyncSub?.cancel() ?? Future.value());
    _threadCountDebounce?.cancel();
    _msgCtrl.dispose();
    _compose.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _composeFocusNode.removeListener(_onComposeFocusChanged);
    _composeFocusNode.dispose();
    _typingCtrl?.dispose();
    _voiceCtrl?.dispose();
    _mentionController?.dispose();
    _emojiController?.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      return Scaffold(
        body: Center(child: Text('Room not found', style: tt.bodyLarge)),
      );
    }

    late final PreferredSizeWidget appBar;
    if (_search.isSearching) {
      appBar = ChatSearchAppBar(
        controller: _searchCtrl,
        focusNode: _searchFocusNode,
        onChanged: _search.onQueryChanged,
        onClose: _closeSearch,
      );
    } else {
      appBar = ChatAppBar(
        summary: matrix.selection.summaryFor(room),
        onBack: widget.onBack,
        onShowDetails: widget.onShowDetails,
        onSearch: _openSearch,
        onPinnedEvent: (eventId) async {
          final event = await room.getEventById(eventId);
          if (event != null && mounted) {
            _messageListKey.currentState?.navigateToEventById(eventId);
          }
        },
        onShowThreads: _openThreadList,
        threadUnreadCount: _threadUnreadCount,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildChatBody(matrix, room.id),
          if (_search.isSearching)
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: SearchResultsBody(
                search: _search,
                avatarResolver: matrix.avatarResolver,
                onTapResult: _scrollToEventById,
              ),
            ),
        ],
      ),
    );
  }

  // ── Chat body (messages + compose) ────────────────────────

  Widget _buildChatBody(MatrixService matrix, String roomId) {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) {
      return Center(
        child: Text(
          'Room not found',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    final callService = context.watch<CallService>();
    final roomHasCall = callService.roomHasActiveCall(room.id);
    final isInCall = callService.activeCallRoomId == room.id;

    final column = Column(
      children: [
        if (roomHasCall && !isInCall)
          JoinCallBanner(roomId: room.id, callService: callService),
        Expanded(
          child: Stack(
            children: [
              MessageListView(
                key: _messageListKey,
                controller: _timelineController,
                mentionResolver: _buildMentionResolver(room.id),
                highlightedEventId: _search.highlightedEventId,
                onReply: _setReplyTo,
                onEdit: (eventId) {
                  final event = _timelineController.getEventById(eventId);
                  if (event != null) {
                    _compose.setEditEvent(
                      event,
                      _timelineController.timeline,
                      _msgCtrl,
                    );
                  }
                },
                onToggleReaction: (eventId, emoji) async {
                  final event = _timelineController.getEventById(eventId);
                  if (event != null) {
                    await _actions.toggleReaction(event, emoji);
                  }
                },
                onPin: (eventId) async {
                  final event = _timelineController.getEventById(eventId);
                  if (event != null) await _actions.togglePin(event);
                },
                onHighlight: _search.setHighlight,
                onScrollBack: isTouchDevice ? _dismissKeyboard : null,
                onOpenThread: _openThread,
                onReplyInThread: _replyInThread,
                onForward: _forwardMessage,
                onOpenContextMenu: _showContextMenu,
                onShowMobileActions: _showMobileActions,
                onTapSender: _showSenderSheet,
                onDelete: (ctx, eventId) {
                  final event = _timelineController.getEventById(eventId);
                  if (event != null) {
                    unawaited(
                      confirmAndDeleteEvent(
                        ctx,
                        isMe: event.senderId == _timelineController.myUserId,
                        onRedact: () => event.room.redactEvent(event.eventId),
                      ),
                    );
                  }
                },
                buildReplyPreview: (eventId, isMe, onParentTap) {
                  return ReplyPreviewHost(
                    replyEventId: eventId,
                    resolvePreview: (id) async {
                      final event = _timelineController.getEventById(id);
                      final timeline = _timelineController.timeline;
                      if (event == null || timeline == null) return null;
                      return const ReplyPreviewResolver()
                          .resolveParent(event, timeline);
                    },
                    isMe: isMe,
                    onParentTap: onParentTap,
                  );
                },
                onStickerContextMenu: _showStickerContextMenu,
                onStickerMobileActions: _showStickerMobileActions,
              ),
              if (_emojiPanelOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _emojiPanelOpen = false),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: _buildEmojiPanel(matrix, room.id),
                ),
              ],
            ],
          ),
        ),
        TypingIndicator(
          typingDisplayNamesProvider: () =>
              matrix.selection.summaryFor(room).typingDisplayNames,
          syncStream: matrix.client.onSync.stream,
        ),
        ComposeBarSection(
          replyNotifier: _compose.replyNotifier,
          editNotifier: _compose.editNotifier,
          pendingAttachments: _compose.pendingAttachments,
          controller: _msgCtrl,
          onSend: _actions.send,
          onCancelReply: _compose.cancelReply,
          onCancelEdit: () => _compose.cancelEdit(_msgCtrl),
          onAttach: _handleAttachPressed,
          onSticker: _toggleStickerPicker,
          stickerPackService: context.read<StickerPackService>(),
          onGif: _giphyEnabled ? _handleGifPressed : null,
          onPasteImage: _isDesktop ? _handlePasteImage : null,
          uploadNotifier: _compose.uploadNotifier,
          avatarResolver: matrix.avatarResolver,
          mediaResolver: matrix.mediaResolver,
          mentionController: _mentionController,
          emojiController: _emojiController,
          typingController: _typingCtrl,
          focusNode: _composeFocusNode,
          voiceController: _voiceCtrl,
          onMicTap: startVoiceRecording,
          onVoiceStop: stopAndSendVoiceMessage,
          onVoiceCancel: cancelVoiceRecording,
          onRemoveAttachment: _compose.removeAttachment,
          onClearAttachments: _compose.clearAttachments,
        ),
      ],
    );

    final body = DesktopDropWrapper(
      enabled: _isDesktop || kIsWeb,
      onFileDropped: _addAttachment,
      child: column,
    );

    final threadId = _activeThreadEventId;
    if (_isDesktop && (threadId != null || _showThreadList)) {
      final cs = Theme.of(context).colorScheme;
      final Widget pane;
      if (threadId != null) {
        pane = ThreadScreen(
          roomId: widget.roomId,
          threadRootEventId: threadId,
          onClose: _closeThread,
          key: ValueKey('thread-${widget.roomId}-$threadId'),
        );
      } else {
        pane = ThreadListScreen(
          roomId: widget.roomId,
          onOpenThread: (id) => setState(() {
            _activeThreadEventId = id;
            _showThreadList = false;
          }),
          onClose: _closeThreadList,
          key: ValueKey('threads-${widget.roomId}'),
        );
      }
      return Row(
        children: [
          Expanded(child: body),
          VerticalDivider(
            width: 1,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
          SizedBox(width: 380, child: pane),
        ],
      );
    }
    return body;
  }
}
