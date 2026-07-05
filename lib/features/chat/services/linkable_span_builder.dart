import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/core/utils/safe_url_launcher.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:kohera/features/chat/widgets/mention_pill.dart';

typedef RecognizerFactory = TapGestureRecognizer Function(VoidCallback onTap);

/// Resolves a Matrix identifier (`@user:server`, `!room:server`, `#alias:server`)
/// to a display name for mention pills. Returns `null` if not resolvable — the
/// caller falls back to the raw identifier.
typedef MentionDisplayNameResolver = String? Function(String identifier);

class LinkableSpanBuilder {
  LinkableSpanBuilder({
    required this.resolveDisplayName,
    required this.isMe,
    required this.createRecognizer,
  });

  final MentionDisplayNameResolver? resolveDisplayName;
  final bool isMe;
  final RecognizerFactory createRecognizer;

  static final _matrixToRegex = RegExp(
    r'^https://matrix\.to/#/([^?]+)',
  );

  void addTextWithLinks(
    String text,
    TextStyle currentStyle,
    Color linkColor,
    List<InlineSpan> spans,
  ) {
    final matches = LinkableText.urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      spans.addAll(buildEmojiSpans(text, currentStyle));
      return;
    }

    var lastEnd = 0;
    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final cleanedUrl = LinkableText.cleanUrl(rawUrl);
      final urlEnd = match.start + cleanedUrl.length;

      if (match.start > lastEnd) {
        spans.addAll(
            buildEmojiSpans(text.substring(lastEnd, match.start), currentStyle),);
      }

      spans.add(TextSpan(
        text: cleanedUrl,
        style: currentStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: createRecognizer(() {
          unawaited(safeLaunchUrl(cleanedUrl));
        }),
      ),);

      lastEnd = urlEnd;
    }

    if (lastEnd < text.length) {
      spans.addAll(buildEmojiSpans(text.substring(lastEnd), currentStyle));
    }
  }

  void addAnchor(
    dom.Element node,
    TextStyle currentStyle,
    Color linkColor,
    List<InlineSpan> spans, {
    required void Function(dom.Node, TextStyle, Color, List<InlineSpan>) buildSpans,
  }
  ) {
    final href = node.attributes['href'];
    if (href != null && href.isNotEmpty) {
      final mentionMatch = _matrixToRegex.firstMatch(href);
      if (mentionMatch != null) {
        final identifier = Uri.decodeComponent(mentionMatch.group(1)!);
        final pill = buildMentionPill(identifier, currentStyle);
        if (pill != null) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: pill,
          ),);
          return;
        }
      }

      final aStyle = currentStyle.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      );
      final text = node.text;
      spans.add(TextSpan(
        text: text,
        style: aStyle,
        recognizer: createRecognizer(() {
          unawaited(safeLaunchUrl(href));
        }),
      ),);
      return;
    }
    for (final child in node.nodes) {
      buildSpans(child, currentStyle, linkColor, spans);
    }
  }

  Widget? buildMentionPill(String identifier, TextStyle currentStyle) {
    if (identifier.startsWith('@')) {
      final displayName = resolveDisplayName?.call(identifier) ?? identifier;
      return MentionPill(
        displayName: displayName,
        matrixId: identifier,
        type: MentionType.user,
        isMe: isMe,
        style: currentStyle,
      );
    } else if (identifier.startsWith('!') || identifier.startsWith('#')) {
      const type = MentionType.room;
      String displayName;
      if (identifier.startsWith('#')) {
        displayName = identifier.substring(1);
      } else {
        displayName = resolveDisplayName?.call(identifier) ?? identifier;
      }
      return MentionPill(
        displayName: displayName,
        matrixId: identifier,
        type: type,
        isMe: isMe,
        style: currentStyle,
      );
    }
    return null;
  }
}
