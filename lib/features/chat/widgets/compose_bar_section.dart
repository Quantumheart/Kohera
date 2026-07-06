import 'package:flutter/material.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/services/emoji_autocomplete_controller.dart';
import 'package:kohera/features/chat/services/mention_autocomplete_controller.dart';
import 'package:kohera/features/chat/services/typing_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_controller.dart';
import 'package:kohera/features/chat/widgets/compose_bar.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_resolver.dart';

class ComposeBarSection extends StatelessWidget {
  const ComposeBarSection({
    required this.replyNotifier,
    required this.editNotifier,
    required this.pendingAttachments,
    required this.controller,
    required this.onSend,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onRemoveAttachment,
    required this.onClearAttachments,
    required this.avatarResolver,
    required this.mediaResolver,
    this.onAttach,
    this.onGif,
    this.onSticker,
    this.stickerPackService,
    this.onPasteImage,
    this.uploadNotifier,
    this.mentionController,
    this.emojiController,
    this.typingController,
    this.focusNode,
    this.voiceController,
    this.onMicTap,
    this.onVoiceStop,
    this.onVoiceCancel,
    super.key,
  });

  final ValueNotifier<KoheraReplyPreview?> replyNotifier;
  final ValueNotifier<KoheraReplyPreview?> editNotifier;
  final ValueNotifier<List<PendingAttachment>> pendingAttachments;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final VoidCallback? onAttach;
  final VoidCallback? onGif;
  final VoidCallback? onSticker;
  final StickerPackService? stickerPackService;
  final Future<void> Function()? onPasteImage;
  final ValueNotifier<UploadState?>? uploadNotifier;
  final AvatarResolver avatarResolver;
  final MediaResolver mediaResolver;
  final MentionAutocompleteController? mentionController;
  final EmojiAutocompleteController? emojiController;
  final TypingController? typingController;
  final FocusNode? focusNode;
  final VoiceRecordingController? voiceController;
  final VoidCallback? onMicTap;
  final VoidCallback? onVoiceStop;
  final VoidCallback? onVoiceCancel;
  final void Function(int index) onRemoveAttachment;
  final VoidCallback onClearAttachments;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([replyNotifier, editNotifier, pendingAttachments]),
      builder: (context, _) {
        return ComposeBar(
          controller: controller,
          onSend: onSend,
          replyPreview: replyNotifier.value,
          onCancelReply: onCancelReply,
          editPreview: editNotifier.value,
          onCancelEdit: onCancelEdit,
          onAttach: onAttach,
          onGif: onGif,
          onSticker: onSticker,
          stickerPackService: stickerPackService,
          onPasteImage: onPasteImage,
          uploadNotifier: uploadNotifier,
          avatarResolver: avatarResolver,
          mediaResolver: mediaResolver,
          mentionController: mentionController,
          emojiController: emojiController,
          typingController: typingController,
          focusNode: focusNode,
          voiceController: voiceController,
          onMicTap: onMicTap,
          onVoiceStop: onVoiceStop,
          onVoiceCancel: onVoiceCancel,
          pendingAttachments: pendingAttachments.value,
          onRemoveAttachment: onRemoveAttachment,
          onClearAttachments: onClearAttachments,
        );
      },
    );
  }
}
