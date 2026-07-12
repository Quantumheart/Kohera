import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/core/utils/safe_url_launcher.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/widgets/audio_bubble.dart';
import 'package:kohera/features/chat/widgets/file_bubble.dart';
import 'package:kohera/features/chat/widgets/image_bubble.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/swipeable_message.dart';
import 'package:kohera/features/chat/widgets/video_bubble.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';

const _msgtypeNotice = 'm.notice';
const _msgtypeEmote = 'm.emote';
const _msgtypeImage = 'm.image';
const _msgtypeAudio = 'm.audio';
const _msgtypeVideo = 'm.video';
const _msgtypeFile = 'm.file';

const Set<String> _mediaMessageTypes = {
  _msgtypeImage,
  _msgtypeAudio,
  _msgtypeVideo,
  _msgtypeFile,
};

/// Renders one timeline message as a compact, monospaced IRC-style line:
/// `HH:MM <nick> body`.
///
/// Own messages use a `>` marker; emotes render as `* nick action`; notices as
/// `-nick- body`. Media collapses to `[type: name]` labels. Reactions appear
/// as trailing `emoji count` chips. Edits/redactions get inline markers.
///
/// Interactions (reply, edit, react, pin, delete, forward, thread, context
/// menu, tap-sender) are preserved via the same callbacks as [ChatMessageItem].
class IrcMessageTile extends StatelessWidget {
  const IrcMessageTile({
    required this.message,
    required this.reactions,
    required this.media,
    required this.isMe,
    required this.isFirst,
    required this.isMobile,
    required this.isPinned,
    required this.canPin,
    required this.canRedact,
    required this.hasThread,
    required this.threadReplyCount,
    required this.threadUnreadCount,
    required this.inThread,
    required this.highlightedEventId,
    required this.avatarResolver,
    required this.mediaController,
    required this.mentionResolver,
    required this.onToggleReaction,
    this.poll,
    this.replyPreviewText,
    this.onReply,
    this.onEdit,
    this.onPin,
    this.onReplyInThread,
    this.onOpenThread,
    this.onForward,
    this.onDelete,
    this.onTapSender,
    this.onOpenContextMenu,
    this.onShowMobileActions,
    this.onTapReply,
    super.key,
  });

  final KoheraMessageDisplay message;
  final KoheraReactionList? reactions;
  final KoheraMediaContent? media;
  final bool isMe;
  final bool isFirst;
  final bool isMobile;
  final bool isPinned;
  final bool canPin;
  final bool canRedact;
  final bool hasThread;
  final int threadReplyCount;
  final int threadUnreadCount;
  final bool inThread;
  final String? highlightedEventId;
  final AvatarResolver? avatarResolver;
  final MediaController? mediaController;
  final KoheraPoll? poll;
  final String? Function(String identifier)? mentionResolver;

  /// One-line reply preview text (already resolved), or null.
  final String? replyPreviewText;

  final void Function(String emoji)? onToggleReaction;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;
  final VoidCallback? onReplyInThread;
  final VoidCallback? onOpenThread;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final void Function(BuildContext, String eventId)? onTapSender;
  final void Function(Offset position)? onOpenContextMenu;
  final void Function(Rect rect)? onShowMobileActions;
  final void Function(String eventId)? onTapReply;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = KoheraPalette.of(context);

    const mono = TextStyle(
      fontFamily: 'RobotoMono',
      fontFamilyFallback: ['monospace'],
      fontSize: 13,
      height: 1.35,
    );

    final isRedacted = message.isRedacted;
    final isEmote = message.messageType == _msgtypeEmote;
    final isNotice = message.messageType == _msgtypeNotice;
    final isHighlighted = message.eventId == highlightedEventId;

    final nickColor = senderColor(message.senderId, cs);
    final nick = message.senderName.isEmpty
        ? message.senderId
        : message.senderName;

    // ── Line fragments ──────────────────────────────────────
    final spans = <InlineSpan>[];

    // Timestamp prefix.
    spans.add(TextSpan(
      text: '${formatMessageTime(message.timestamp)} ',
      style: mono.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
    ));

    // Nick / prefix.
    if (isEmote) {
      spans.add(TextSpan(text: '* ', style: mono.copyWith(color: cs.onSurfaceVariant)));
      spans.add(TextSpan(
        text: '$nick ',
        style: mono.copyWith(color: nickColor, fontWeight: FontWeight.w600),
      ));
    } else if (isNotice) {
      spans.add(TextSpan(
        text: '-$nick- ',
        style: mono.copyWith(color: nickColor, fontWeight: FontWeight.w600),
      ));
    } else {
      final marker = isMe ? '>' : '<';
      final close = isMe ? '<' : '>';
      spans.add(TextSpan(
        text: '$marker$nick$close ',
        style: mono.copyWith(color: nickColor, fontWeight: FontWeight.w600),
        recognizer: onTapSender == null
            ? null
            : (TapGestureRecognizer()
              ..onTap = () => onTapSender!(context, message.eventId)),
      ));
    }

    // Reply marker.
    if (message.replyEventId != null && !isRedacted && replyPreviewText != null) {
      final preview = replyPreviewText!.replaceAll('\n', ' ');
      final trimmed = preview.length > 60 ? '${preview.substring(0, 57)}...' : preview;
      spans.add(TextSpan(
        text: '↳ $trimmed ',
        style: mono.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
        recognizer: onTapReply == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onTapReply!(message.replyEventId!)),
      ));
    }

    // Body.
    final isMediaMessage = !isRedacted &&
        _mediaMessageTypes.contains(message.messageType) &&
        media != null &&
        mediaController != null;

    if (isRedacted) {
      spans.add(TextSpan(
        text: '• redacted',
        style: mono.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        ),
      ));
      if (message.redactionReason != null && message.redactionReason!.isNotEmpty) {
        spans.add(TextSpan(
          text: ' (${message.redactionReason})',
          style: mono.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
        ));
      }
    } else if (isMediaMessage) {
      // Media messages render the attachment below the log line; show a
      // compact label inline so the line is still readable.
      spans.add(_mediaLabel(media!, mono, palette));
    } else if (poll != null) {
      spans.add(_pollLabel(poll!, mono, palette));
    } else {
      _addLinkableText(message.body, mono, cs, palette, spans);
      if (message.isEdited) {
        spans.add(TextSpan(
          text: ' (edited)',
          style: mono.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ));
      }
    }

    // Thread indicator.
    if (hasThread && !inThread) {
      spans.add(TextSpan(
        text: ' [$threadReplyCount replies]',
        style: mono.copyWith(color: palette.link),
        recognizer: onOpenThread == null
            ? null
            : (TapGestureRecognizer()..onTap = onOpenThread),
      ));
      if (threadUnreadCount > 0) {
        spans.add(TextSpan(
          text: ' ($threadUnreadCount unread)',
          style: mono.copyWith(color: palette.danger),
        ));
      }
    }

    // Pinned marker.
    if (isPinned) {
      spans.add(TextSpan(
        text: ' 📌',
        style: mono.copyWith(color: cs.tertiary),
      ));
    }

    // Reaction chips (trailing).
    if (reactions != null && reactions!.isNotEmpty) {
      for (final r in reactions!.reactions) {
        spans.add(const TextSpan(text: '  '));
        spans.add(TextSpan(
          text: '${r.key} ${r.count}',
          style: mono.copyWith(
            color: r.reactedByMe ? palette.link : cs.onSurfaceVariant,
            fontWeight: r.reactedByMe ? FontWeight.w600 : FontWeight.w400,
          ),
          recognizer: onToggleReaction == null
              ? null
              : (TapGestureRecognizer()..onTap = () => onToggleReaction!(r.key)),
        ));
      }
    }

    final line = Padding(
      padding: EdgeInsets.fromLTRB(4, isFirst ? 2 : 0, 4, 0),
      child: Container(
        decoration: isHighlighted
            ? BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.25),
                border: Border(left: BorderSide(color: cs.primary, width: 2)),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: SelectionArea(
          child: Text.rich(
            TextSpan(children: spans),
            style: mono.copyWith(color: cs.onSurface),
          ),
        ),
      ),
    );

    // Media attachment rendered below the log line so images/gifs load.
    final mediaWidget = isMediaMessage
        ? _buildMediaWidget(media!, mediaController!, cs)
        : null;

    final body = mediaWidget == null
        ? line
        : Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line,
                Padding(
                  padding: const EdgeInsets.only(left: 64, top: 1),
                  child: mediaWidget,
                ),
              ],
            ),
          );

    // ── Interactions ─────────────────────────────────────
    final content = isMobile
        ? SwipeableMessage(
            onReply: () => onReply?.call(),
            child: LongPressWrapper(
              onLongPress: (rect) => onShowMobileActions?.call(rect),
              child: body,
            ),
          )
        : Listener(
            onPointerDown: (event) {
              if (event.buttons == kSecondaryMouseButton && !isRedacted) {
                onOpenContextMenu?.call(event.position);
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: body,
            ),
          );

    return KeyedSubtree(key: ValueKey(message.eventId), child: content);
  }

  /// Adds the message body as linkable, emoji-aware inline spans.
  void _addLinkableText(
    String text,
    TextStyle style,
    ColorScheme cs,
    KoheraPalette palette,
    List<InlineSpan> spans,
  ) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      spans.addAll(buildEmojiSpans(text, style));
      return;
    }
    var lastEnd = 0;
    for (final match in matches) {
      final raw = match.group(0)!;
      final cleaned = _cleanUrl(raw);
      final urlEnd = match.start + cleaned.length;
      if (match.start > lastEnd) {
        spans.addAll(buildEmojiSpans(text.substring(lastEnd, match.start), style));
      }
      spans.add(TextSpan(
        text: cleaned,
        style: style.copyWith(
          color: palette.link,
          decoration: TextDecoration.underline,
          decorationColor: palette.link,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => unawaited(safeLaunchUrl(cleaned)),
      ));
      lastEnd = urlEnd;
    }
    if (lastEnd < text.length) {
      spans.addAll(buildEmojiSpans(text.substring(lastEnd), style));
    }
  }

  /// Compact inline label for the log line (e.g. `[image: photo.png]`).
  TextSpan _mediaLabel(KoheraMediaContent m, TextStyle style, KoheraPalette palette) {
    final label = switch (m.mediaType) {
      KoheraMediaType.image => '[image]',
      KoheraMediaType.video => '[video]',
      KoheraMediaType.audio => '[audio]',
      KoheraMediaType.file => '[file]',
      KoheraMediaType.sticker => '[sticker]',
    };
    final name = m.fileName ?? '';
    return TextSpan(
      text: name.isEmpty ? label : '$label: $name',
      style: style.copyWith(color: palette.link, fontWeight: FontWeight.w600),
    );
  }

  /// Compact inline label for a poll-start event (`[poll] question`).
  TextSpan _pollLabel(KoheraPoll p, TextStyle style, KoheraPalette palette) {
    final state = p.ended ? 'ended' : 'open';
    return TextSpan(
      text: '[poll: $state] ${p.question}',
      style: style.copyWith(color: palette.link, fontWeight: FontWeight.w600),
    );
  }

  /// Renders the actual media attachment so images/gifs load and display.
  Widget _buildMediaWidget(
    KoheraMediaContent m,
    MediaController controller,
    ColorScheme cs,
  ) {
    switch (m.mediaType) {
      case KoheraMediaType.image:
        return ImageBubble(
          media: m,
          controller: controller,
          avatarResolver: avatarResolver!,
        );
      case KoheraMediaType.video:
        return VideoBubble(
          media: m,
          controller: controller,
          isMe: isMe,
          avatarResolver: avatarResolver!,
        );
      case KoheraMediaType.audio:
        return AudioBubble(media: m, controller: controller, isMe: isMe);
      case KoheraMediaType.file:
        return FileBubble(media: m, controller: controller, isMe: isMe);
      case KoheraMediaType.sticker:
        return FileBubble(media: m, controller: controller, isMe: isMe);
    }
  }

  static final _urlRegex = RegExp(r'https?://[^\s)<>]+', caseSensitive: false);

  static String _cleanUrl(String raw) {
    while (raw.isNotEmpty && '.,;:!?\'"'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }
}
