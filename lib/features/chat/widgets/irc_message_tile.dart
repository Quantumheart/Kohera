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
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/swipeable_message.dart';

const _msgtypeNotice = 'm.notice';
const _msgtypeEmote = 'm.emote';

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
    required this.mentionResolver,
    required this.onToggleReaction,
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
    } else if (media != null) {
      spans.add(_mediaSpan(media!, mono, cs, palette));
      final caption = media!.caption ?? media!.fileName;
      if (caption != null && caption.isNotEmpty && caption != media!.fileName) {
        spans.add(const TextSpan(text: ' '));
        _addLinkableText(caption, mono, cs, palette, spans);
      }
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

    // ── Interactions ────────────────────────────────────────
    Widget content = line;
    if (isMobile) {
      content = SwipeableMessage(
        onReply: () => onReply?.call(),
        child: LongPressWrapper(
          onLongPress: (rect) => onShowMobileActions?.call(rect),
          child: content,
        ),
      );
    } else {
      content = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton && !isRedacted) {
            onOpenContextMenu?.call(event.position);
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: content,
        ),
      );
    }

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

  TextSpan _mediaSpan(
    KoheraMediaContent m,
    TextStyle style,
    ColorScheme cs,
    KoheraPalette palette,
  ) {
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

  static final _urlRegex = RegExp(r'https?://[^\s)<>]+', caseSensitive: false);

  static String _cleanUrl(String raw) {
    while (raw.isNotEmpty && '.,;:!?\'"'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }
}
