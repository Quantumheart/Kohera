import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/widgets/inline_reply_preview.dart';

/// Renders an inline reply preview for a message that replies to another
/// event.
///
/// Takes the reply event ID and an async resolver that produces a
/// [KoheraReplyPreview] (or `null` if the parent is unavailable). The resolver
/// is called once on mount and again if the reply event ID changes.
class ReplyPreviewHost extends StatefulWidget {
  const ReplyPreviewHost({
    required this.replyEventId,
    required this.resolvePreview,
    required this.isMe,
    this.onParentTap,
    super.key,
  });

  final String replyEventId;
  final Future<KoheraReplyPreview?> Function(String replyEventId)
      resolvePreview;
  final bool isMe;
  final void Function(String parentEventId)? onParentTap;

  @override
  State<ReplyPreviewHost> createState() => _ReplyPreviewHostState();
}

class _ReplyPreviewHostState extends State<ReplyPreviewHost> {
  KoheraReplyPreview? _preview;
  bool _loaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(ReplyPreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replyEventId != widget.replyEventId) {
      _generation++;
      _loaded = false;
      _preview = null;
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final gen = _generation;
    try {
      final preview = await widget.resolvePreview(widget.replyEventId);
      if (mounted && gen == _generation) {
        setState(() {
          _preview = preview;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to load reply parent: $e');
      if (mounted && gen == _generation) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return InlineReplyPreview(
      preview: _preview,
      isMe: widget.isMe,
      onTap: _preview != null
          ? () => widget.onParentTap?.call(_preview!.parentMessageId)
          : null,
    );
  }
}
