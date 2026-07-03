import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/screens/thread_list_screen.dart';
import 'package:kohera/features/chat/screens/thread_screen.dart';
import 'package:kohera/features/chat/services/chat_message_actions.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/services/thread_roots_service.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/features/chat/services/typing_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_mixin.dart';
import 'package:kohera/features/chat/widgets/attachment_source_sheet.dart';
import 'package:kohera/features/chat/widgets/chat_app_bar.dart';
import 'package:kohera/features/chat/widgets/compose_bar_section.dart';
import 'package:kohera/features/chat/widgets/desktop_drop_wrapper.dart';
import 'package:kohera/features/chat/widgets/file_send_handler.dart';
import 'package:kohera/features/chat/widgets/forward_message_dialog.dart';
import 'package:kohera/features/chat/widgets/gif_send_handler.dart';
import 'package:kohera/features/chat/widgets/join_call_banner.dart';
import 'package:kohera/features/chat/widgets/message_list_view.dart';
import 'package:kohera/features/chat/widgets/paste_image_handler.dart';
import 'package:kohera/features/chat/widgets/photo_send_handler.dart';
import 'package:kohera/features/chat/widgets/search_results_body.dart';
import 'package:kohera/features/chat/widgets/sticker_picker_overlay.dart';
import 'package:kohera/features/chat/widgets/typing_indicator.dart';
import 'package:kohera/features/chat/widgets/web_image_paste.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:matrix/matrix.dart';
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

class _ChatScreenState extends State<ChatScreen> with VoiceRecordingMixin<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _composeFocusNode = FocusNode(debugLabel: 'chat-compose');
  final _messageListKey = GlobalKey<MessageListViewState>();

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
  ValueNotifier<UploadState?> get voiceUploadNotifier => _compose.uploadNotifier;
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
    _actions = _createActions();
    _search = _createSearchController();
    _initControllers();
    _composeFocusNode.addListener(_onComposeFocusChanged);
    if (kIsWeb) {
      initWebPasteListener();
      _webPasteSub = webPasteImageStream.listen(_onWebPasteImage);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshThreadUnreadCount());
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
    if (old.roomId != widget.roomId || old.initialEventId != widget.initialEventId) {
      _compose.reset(_msgCtrl);
      _typingCtrl?.dispose();
      _voiceCtrl?.dispose();
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

  void _initControllers() {
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room != null) {
      _typingCtrl = TypingController(room: room);
      _voiceCtrl = VoiceRecordingController();
    }
  }

  ChatMessageActions _createActions() {
    return ChatMessageActions(
      getRoomId: () => widget.roomId,
      getRoom: () => context.read<MatrixService>().client.getRoomById(widget.roomId),
      getTimeline: () => _messageListKey.currentState?.timeline,
      compose: _compose,
      msgCtrl: _msgCtrl,
      getScaffold: () => ScaffoldMessenger.of(context),
      getMatrixService: () => context.read<MatrixService>(),
    );
  }

  ChatSearchController _createSearchController() {
    return ChatSearchController(
      roomId: widget.roomId,
      getRoom: () => context.read<MatrixService>().client.getRoomById(widget.roomId),
    )..addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  // ── Reply / Edit helpers ────────────────────────────────

  void _setReplyTo(Event event) {
    _compose.setReplyTo(event);
    _composeFocusNode.requestFocus();
  }

  void _openThread(Event rootEvent) {
    if (_isDesktop) {
      setState(() {
        _activeThreadEventId = rootEvent.eventId;
        _showThreadList = false;
      });
      return;
    }
    unawaited(
      context.pushNamed(
        Routes.roomThread,
        pathParameters: {
          RouteParams.roomId: widget.roomId,
          RouteParams.eventId: rootEvent.eventId,
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

  void _replyInThread(Event event) {
    final timeline = _messageListKey.currentState?.timeline;
    final rootId = event.relationshipType == RelationshipTypes.thread
        ? (event.relationshipEventId ?? event.eventId)
        : event.eventId;
    final root = timeline?.events.firstWhere(
          (e) => e.eventId == rootId,
          orElse: () => event,
        ) ??
        event;
    _openThread(root);
  }

  void _forwardMessage(Event event, Timeline? timeline) {
    unawaited(
      ForwardMessageDialog.show(
        context,
        event: event,
        timeline: timeline,
        matrixService: context.read<MatrixService>(),
      ),
    );
  }

  void _dismissKeyboard() {
    if (_composeFocusNode.hasFocus) _composeFocusNode.unfocus();
  }

  // ── Attachments ─────────────────────────────────────────

  void _addAttachment(PendingAttachment attachment) {
    _showAttachmentError(_compose.addAttachment(attachment));
  }

  Future<void> _handleAttachPressed() async {
    final isMobileTouch =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

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
      case AttachmentSource.file:
        final attachment = await pickFileAsAttachment();
        if (attachment != null && mounted) _addAttachment(attachment);
      case AttachmentSource.camera:
        final attachment = await takePhotoWithCamera();
        if (attachment != null && mounted) _addAttachment(attachment);
      case AttachmentSource.gallery:
        final remaining = ComposeStateController.maxAttachments - _compose.pendingAttachments.value.length;
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

  void _scrollToEvent(Event event, {bool closeSearch = true}) {
    if (closeSearch) _closeSearch();
    _messageListKey.currentState?.navigateToEvent(event);
  }

  // ── GIF ───────────────────────────────────────────────────

  bool get _giphyEnabled => AppConfig.isInitialized && AppConfig.instance.giphyEnabled;

  Future<void> _handleGifPressed() async {
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
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
    final isNarrow = MediaQuery.sizeOf(context).width < HomeShell.wideBreakpoint;
    if (isNarrow) {
      final matrix = context.read<MatrixService>();
      final room = matrix.client.getRoomById(widget.roomId);
      if (room != null) _openStickerSheet(matrix, room);
      return;
    }
    setState(() => _emojiPanelOpen = !_emojiPanelOpen);
    if (_emojiPanelOpen) {
      _composeFocusNode.unfocus();
    }
  }

  void _openStickerSheet(MatrixService matrix, Room room) {
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
          builder: (_, __) => StickerPickerOverlay(
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

  Widget _buildEmojiPanel(MatrixService matrix, Room room) {
    final cs = Theme.of(context).colorScheme;
    final stickerService = context.watch<StickerPackService>();
    final skinTone = context.watch<PreferencesService>().skinTone;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 16).clamp(0.0, 360.0);
    final height = (size.height * 0.45).clamp(240.0, 360.0);

    return Material(
      elevation: 8,
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
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
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
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
    final insertion = emoji.emoji != null ? '${emoji.emoji} ' : ':${emoji.shortcode}: ';
    _msgCtrl.value = TextEditingValue(
      text: text.substring(0, pos) + insertion + text.substring(pos),
      selection: TextSelection.collapsed(offset: pos + insertion.length),
    );
    _composeFocusNode.requestFocus();
  }

  @override
  void dispose() {
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
            _messageListKey.currentState?.navigateToEvent(event);
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
          _buildChatBody(matrix, room),
          if (_search.isSearching)
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: SearchResultsBody(
                search: _search,
                onTapResult: _scrollToEvent,
              ),
            ),
        ],
      ),
    );
  }

  // ── Chat body (messages + compose) ────────────────────────

  Widget _buildChatBody(MatrixService matrix, Room room) {
    final callService = context.watch<CallService>();
    final roomHasCall = callService.roomHasActiveCall(room.id);
    final isInCall = callService.activeCallRoomId == room.id;

    final column = Column(
      children: [
        if (roomHasCall && !isInCall) JoinCallBanner(roomId: room.id, callService: callService),
        Expanded(
          child: Stack(
            children: [
              MessageListView(
                key: _messageListKey,
                roomId: room.id,
                matrix: matrix,
                initialEventId: widget.initialEventId,
                highlightedEventId: _search.highlightedEventId,
                onReply: _setReplyTo,
                onEdit: (event, timeline) => _compose.setEditEvent(event, timeline, _msgCtrl),
                onToggleReaction: _actions.toggleReaction,
                onPin: _actions.togglePin,
                onHighlight: _search.setHighlight,
                onScrollBack: isTouchDevice ? _dismissKeyboard : null,
                onOpenThread: _openThread,
                onReplyInThread: _replyInThread,
                onForward: _forwardMessage,
                onTimelineChanged: _onTimelineChanged,
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
                  child: _buildEmojiPanel(matrix, room),
                ),
              ],
            ],
          ),
        ),
        TypingIndicator(
          typingDisplayNamesProvider: () => matrix.selection.summaryFor(room).typingDisplayNames,
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
          room: room,
          joinedRooms: context.read<SelectionService>().rooms,
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
