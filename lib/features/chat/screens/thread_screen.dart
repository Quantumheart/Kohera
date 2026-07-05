import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/chat/services/chat_message_actions.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';
import 'package:kohera/features/chat/services/thread_roots_service.dart';
import 'package:kohera/features/chat/widgets/compose_bar_section.dart';
import 'package:kohera/features/chat/widgets/file_send_handler.dart';
import 'package:kohera/features/chat/widgets/message_list_view.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    required this.roomId,
    required this.threadRootEventId,
    super.key,
    this.onClose,
  });

  final String roomId;
  final String threadRootEventId;
  final VoidCallback? onClose;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _msgCtrl = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'thread-compose');
  final _messageListKey = GlobalKey<MessageListViewState>();
  final _compose = ComposeStateController();

  late MessageTimelineController _timelineController;

  late ChatMessageActions _actions;
  bool _loadingRoot = true;
  bool _focusReady = false;
  bool _loadingMoreReplies = false;
  List<Event> _threadReplies = const [];
  Event? _threadRootEvent;
  String? _repliesNextBatch;

  List<Event> get _seedEvents {
    final root = _threadRootEvent;
    if (root == null) return _threadReplies;
    return [root, ..._threadReplies];
  }

  @override
  void initState() {
    super.initState();
    final matrix = context.read<MatrixService>();
    _timelineController = MessageTimelineController(
      matrix: matrix,
      roomId: widget.roomId,
      sendPublicReadReceipts: false,
      threadRootEventId: widget.threadRootEventId,
      onTimelineChanged: () {
        if (mounted) setState(() {});
      },
    );
    _actions = ChatMessageActions(
      getRoomId: () => widget.roomId,
      getRoom: () =>
          context.read<MatrixService>().client.getRoomById(widget.roomId),
      getTimeline: () => _timelineController.timeline,
      compose: _compose,
      msgCtrl: _msgCtrl,
      getScaffold: () => ScaffoldMessenger.of(context),
      getMatrixService: () => context.read<MatrixService>(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadRoot());
    });
  }

  Future<void> _loadRoot() async {
    final room = context
        .read<MatrixService>()
        .client
        .getRoomById(widget.roomId);
    if (room == null) {
      if (mounted) setState(() => _loadingRoot = false);
      _scheduleFocusReady();
      return;
    }
    try {
      final client = context.read<MatrixService>().client;
      final root = await room.getEventById(widget.threadRootEventId);
      final page = await fetchThreadChildrenPage(
        client,
        room,
        widget.threadRootEventId,
      );
      if (!mounted) return;
      setState(() {
        _loadingRoot = false;
        _threadReplies = page.events;
        _threadRootEvent = root;
        _repliesNextBatch = page.nextBatch;
        if (root != null) _compose.setThreadRoot(root);
      });
      _timelineController.updateExtraEvents(_seedEvents);
      unawaited(_timelineController.init());
      _scheduleFocusReady();
    } catch (e) {
      debugPrint('[Kohera] Thread root load failed: $e');
      if (!mounted) return;
      setState(() => _loadingRoot = false);
      _scheduleFocusReady();
      context.showSnack('Could not load thread');
    }
  }

  Future<void> _loadMoreReplies() async {
    if (_loadingMoreReplies) return;
    final from = _repliesNextBatch;
    if (from == null) return;
    final room = context
        .read<MatrixService>()
        .client
        .getRoomById(widget.roomId);
    if (room == null) return;
    setState(() => _loadingMoreReplies = true);
    try {
      final page = await fetchThreadChildrenPage(
        context.read<MatrixService>().client,
        room,
        widget.threadRootEventId,
        from: from,
      );
      if (!mounted) return;
      final seen = _threadReplies.map((e) => e.eventId).toSet();
      final merged = [
        ..._threadReplies,
        ...page.events.where((e) => seen.add(e.eventId)),
      ];
      setState(() {
        _threadReplies = merged;
        _repliesNextBatch = page.nextBatch;
      });
      _timelineController.updateExtraEvents(_seedEvents);
    } catch (e) {
      debugPrint('[Kohera] Thread reply pagination failed: $e');
    } finally {
      if (mounted) setState(() => _loadingMoreReplies = false);
    }
  }

  void _scheduleFocusReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusReady) return;
      setState(() => _focusReady = true);
    });
  }

  void _addAttachment(PendingAttachment attachment) {
    final result = _compose.addAttachment(attachment);
    if (result == AddAttachmentResult.tooMany) {
      context.showSnack(
        'Maximum ${ComposeStateController.maxAttachments} attachments allowed',
      );
    } else if (result == AddAttachmentResult.tooLarge) {
      context.showSnack('File exceeds 25 MB limit');
    }
  }

  Future<void> _handleAttach() async {
    final attachment = await pickFileAsAttachment();
    if (attachment != null && mounted) _addAttachment(attachment);
  }

  @override
  void dispose() {
    _timelineController.dispose();
    _msgCtrl.dispose();
    _focusNode.dispose();
    _compose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Thread')),
        body: Center(child: Text('Room not found', style: tt.bodyLarge)),
      );
    }

    if (_loadingRoot) {
      return Scaffold(
        appBar: AppBar(title: const Text('Thread')),
        body: const Center(child: KoheraLoader()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: widget.onClose != null
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close thread',
                onPressed: widget.onClose,
              )
            : null,
        title: const Text('Thread'),
      ),
      body: Column(
        children: [
          Expanded(
            child: MessageListView(
              key: _messageListKey,
              controller: _timelineController,
              mentionResolver: (_) => null,
              emptyText: 'No replies yet.\nStart the conversation.',
              extraLoading: _loadingMoreReplies,
              onLoadMoreExtra: () => unawaited(_loadMoreReplies()),
              onReply: (eventId) {
                final event = _timelineController.getEventById(eventId);
                if (event != null) _compose.setReplyTo(event);
              },
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
              onHighlight: (_) {},
            ),
          ),
          if (_focusReady)
            ComposeBarSection(
              replyNotifier: _compose.replyNotifier,
              editNotifier: _compose.editNotifier,
              pendingAttachments: _compose.pendingAttachments,
              controller: _msgCtrl,
              onSend: _actions.send,
              onCancelReply: _compose.cancelReply,
              onCancelEdit: () => _compose.cancelEdit(_msgCtrl),
              onAttach: _handleAttach,
              uploadNotifier: _compose.uploadNotifier,
              room: room,
              joinedRooms: context.read<SelectionService>().rooms,
              focusNode: _focusNode,
              onRemoveAttachment: _compose.removeAttachment,
              onClearAttachments: _compose.clearAttachments,
            ),
        ],
      ),
    );
  }
}
