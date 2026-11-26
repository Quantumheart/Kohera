import 'package:kohera/core/extensions/auth_error_formatter.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/models/kohera_poll_draft.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/services/file_send_handler.dart';
import 'package:material_ui/material_ui.dart';

class ChatMessageActions {
  ChatMessageActions({
    required this.getRoomId,
    required this.compose,
    required this.msgCtrl,
    required this.getScaffold,
    required this.getRoomRepository,
    required this.getMessageRepository,
  });

  final String Function() getRoomId;
  final ComposeStateController compose;
  final TextEditingController msgCtrl;
  final ScaffoldMessengerState Function() getScaffold;
  final RoomRepository Function() getRoomRepository;
  final MessageRepository Function() getMessageRepository;

  // ── Reactions ──────────────────────────────────────

  Future<void> toggleReaction(String eventId, String emoji) async {
    try {
      await getMessageRepository().toggleReaction(getRoomId(), eventId, emoji);
    } catch (e) {
      getScaffold().showSnackBar(
        SnackBar(
          content: Text(
            'Failed to react: ${AuthErrorFormatter.friendlyAuthError(e)}',
          ),
        ),
      );
    }
  }

  // ── Pin ──────────────────────────────────────────────

  Future<void> togglePin(String eventId) async {
    final rooms = getRoomRepository();
    final roomId = getRoomId();
    final wasPinned = rooms.isPinned(roomId, eventId);
    try {
      await rooms.setPinned(roomId, eventId, !wasPinned);
    } catch (e) {
      getScaffold().showSnackBar(
        SnackBar(
          content: Text(
            wasPinned ? 'Failed to unpin message' : 'Failed to pin message',
          ),
        ),
      );
    }
  }

  // ── Send ───────────────────────────────────────────────

  Future<void> send() async {
    final text = msgCtrl.text.trim();
    final attachments =
        List<PendingAttachment>.from(compose.pendingAttachments.value);
    if (text.isEmpty && attachments.isEmpty) return;

    msgCtrl.clear();
    compose.pendingAttachments.value = [];

    final replyPreview = compose.replyNotifier.value;
    compose.replyNotifier.value = null;

    final editPreview = compose.editNotifier.value;
    compose.editNotifier.value = null;

    final roomId = getRoomId();
    final messages = getMessageRepository();
    final threadRootId = compose.threadRootEventId;
    final threadLastId = threadRootId == null
        ? null
        : await messages.latestThreadEventId(roomId, threadRootId) ??
            threadRootId;

    final scaffold = getScaffold();

    for (var i = 0; i < attachments.length; i++) {
      final ok = await sendFileBytes(
        scaffold: scaffold,
        rooms: getRoomRepository(),
        roomId: roomId,
        name: attachments[i].name,
        bytes: attachments[i].bytes,
        uploadNotifier: compose.uploadNotifier,
        threadRootEventId: threadRootId,
        threadLastEventId: threadLastId,
      );
      if (!ok) {
        compose.pendingAttachments.value = attachments.sublist(i);
        if (text.isNotEmpty) {
          msgCtrl.text = text;
          compose.replyNotifier.value = replyPreview;
          compose.editNotifier.value = editPreview;
        }
        return;
      }
    }

    if (text.isNotEmpty) {
      try {
        await messages.sendText(
          roomId,
          text,
          inReplyToEventId:
              editPreview == null ? replyPreview?.parentMessageId : null,
          editEventId: editPreview?.parentMessageId,
          threadRootEventId: threadRootId,
          threadLastEventId: threadLastId,
        );
      } catch (e) {
        msgCtrl.text = text;
        compose.replyNotifier.value = replyPreview;
        compose.editNotifier.value = editPreview;
        scaffold.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send: ${AuthErrorFormatter.friendlyAuthError(e)}',
            ),
          ),
        );
      }
    }
  }

  // ── Polls ────────────────────────────────────────────

  Future<void> sendPoll(KoheraPollDraft draft) async {
    final scaffold = getScaffold();
    try {
      await getMessageRepository().startPoll(
        getRoomId(),
        question: draft.question,
        answers: draft.answers,
        disclosed: draft.disclosed,
        maxSelections: draft.maxSelections,
      );
    } catch (e) {
      debugPrint('[Kohera] Failed to send poll: $e');
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send poll: ${AuthErrorFormatter.friendlyAuthError(e)}',
          ),
        ),
      );
    }
  }

  Future<void> votePoll(String eventId, List<String> answerIds) async {
    final scaffold = getScaffold();
    try {
      await getMessageRepository().answerPoll(getRoomId(), eventId, answerIds);
    } catch (e) {
      debugPrint('[Kohera] Failed to submit poll vote: $e');
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to vote: ${AuthErrorFormatter.friendlyAuthError(e)}',
          ),
        ),
      );
    }
  }

  /// Ends the MSC3381 poll whose start event has [eventId].
  Future<void> endPoll(String eventId) async {
    final scaffold = getScaffold();
    try {
      await getMessageRepository().endPoll(getRoomId(), eventId);
    } catch (e) {
      debugPrint('[Kohera] Failed to end poll: $e');
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to end poll: ${AuthErrorFormatter.friendlyAuthError(e)}',
          ),
        ),
      );
    }
  }
}
