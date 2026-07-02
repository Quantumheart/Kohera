import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/services/reply_preview_resolver.dart';
import 'package:kohera/features/chat/widgets/inline_reply_preview.dart';
import 'package:matrix/matrix.dart';

/// Conversion boundary for inline reply previews.
///
/// Takes the replying [Event] + [Timeline], resolves the parent event
/// asynchronously via `getReplyEvent`, and renders [InlineReplyPreview] with
/// the pre-computed [KoheraReplyPreview]. Retains the parent `Event` for the
/// tap callback.
///
/// This widget imports `package:matrix/matrix.dart` — it IS the boundary.
/// [InlineReplyPreview] below it is SDK-free.
class ReplyPreviewHost extends StatefulWidget {
  const ReplyPreviewHost({
    required this.replyEvent,
    required this.timeline,
    required this.isMe,
    this.onParentTap,
    super.key,
  });

  final Event replyEvent;
  final Timeline? timeline;
  final bool isMe;
  final void Function(Event)? onParentTap;

  @override
  State<ReplyPreviewHost> createState() => _ReplyPreviewHostState();
}

class _ReplyPreviewHostState extends State<ReplyPreviewHost> {
  KoheraReplyPreview? _preview;
  Event? _parentEvent;
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
    if (oldWidget.replyEvent != widget.replyEvent ||
        oldWidget.timeline != widget.timeline) {
      _generation++;
      _loaded = false;
      _preview = null;
      _parentEvent = null;
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final gen = _generation;
    if (widget.timeline == null) {
      if (mounted && gen == _generation) setState(() => _loaded = true);
      return;
    }
    try {
      final parent = await widget.replyEvent.getReplyEvent(widget.timeline!);
      if (mounted && gen == _generation) {
        final available = parent != null &&
            parent.type != EventTypes.Redaction &&
            !parent.redacted;
        setState(() {
          _parentEvent = available ? parent : null;
          _preview = available
              ? const ReplyPreviewResolver().fromEvent(parent)
              : null;
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
      onTap: _preview != null && _parentEvent != null
          ? () => widget.onParentTap?.call(_parentEvent!)
          : null,
    );
  }
}
