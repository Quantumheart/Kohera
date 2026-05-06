import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/chat/services/chat_message_actions.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/widgets/compose_bar_section.dart';
import 'package:kohera/features/chat/widgets/file_send_handler.dart';
import 'package:kohera/features/chat/widgets/message_list_view.dart';
import 'package:provider/provider.dart';

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    required this.roomId,
    required this.threadRootEventId,
    super.key,
    this.onClose,
    this.initialReplyEventId,
  });

  final String roomId;
  final String threadRootEventId;
  final VoidCallback? onClose;
  final String? initialReplyEventId;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _msgCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _messageListKey = GlobalKey<MessageListViewState>();
  final _compose = ComposeStateController();

  late ChatMessageActions _actions;
  bool _loadingRoot = true;
  bool _focusReady = false;

  @override
  void initState() {
    super.initState();
    _actions = ChatMessageActions(
      getRoomId: () => widget.roomId,
      getRoom: () =>
          context.read<MatrixService>().client.getRoomById(widget.roomId),
      getTimeline: () => _messageListKey.currentState?.timeline,
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
      final root = await room.getEventById(widget.threadRootEventId);
      if (!mounted) return;
      setState(() {
        _loadingRoot = false;
        if (root != null) _compose.setThreadRoot(root);
      });
      _scheduleFocusReady();
    } catch (e) {
      debugPrint('[Kohera] Thread root load failed: $e');
      if (!mounted) return;
      setState(() => _loadingRoot = false);
      _scheduleFocusReady();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load thread')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Maximum ${ComposeStateController.maxAttachments} attachments allowed',
          ),
        ),
      );
    } else if (result == AddAttachmentResult.tooLarge) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File exceeds 25 MB limit')),
      );
    }
  }

  Future<void> _handleAttach() async {
    final attachment = await pickFileAsAttachment();
    if (attachment != null && mounted) _addAttachment(attachment);
  }

  @override
  void dispose() {
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
        body: const Center(child: CircularProgressIndicator()),
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
              room: room,
              matrix: matrix,
              threadRootEventId: widget.threadRootEventId,
              initialEventId:
                  widget.initialReplyEventId ?? widget.threadRootEventId,
              emptyText: 'No replies yet.\nStart the conversation.',
              onReply: _compose.setReplyTo,
              onEdit: (event, timeline) =>
                  _compose.setEditEvent(event, timeline, _msgCtrl),
              onToggleReaction: _actions.toggleReaction,
              onPin: _actions.togglePin,
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
