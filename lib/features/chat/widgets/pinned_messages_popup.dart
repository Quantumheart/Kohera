import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';
import 'package:kohera/features/chat/services/pinned_messages_loader.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:provider/provider.dart';
/// Shows a popup panel anchored below the pin icon listing pinned messages.
void showPinnedMessagesPopup(
  BuildContext context,
  String roomId, {
  required void Function(String eventId) onTap,
}) {
  final button = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final buttonPos = button.localToGlobal(Offset.zero, ancestor: overlay);
  final anchor = Rect.fromLTWH(
    buttonPos.dx,
    buttonPos.dy,
    button.size.width,
    button.size.height,
  );

  unawaited(
    Navigator.of(context).push(
      _PinnedMessagesPopupRoute(
        anchor: anchor,
        overlaySize: overlay.size,
        roomId: roomId,
        onTap: onTap,
      ),
    ),
  );
}

// ── Route ───────────────────────────────────────────────────────────

class _PinnedMessagesPopupRoute extends PopupRoute<void> {
  _PinnedMessagesPopupRoute({
    required this.anchor,
    required this.overlaySize,
    required this.roomId,
    required this.onTap,
  });

  final Rect anchor;
  final Size overlaySize;
  final String roomId;
  final void Function(String eventId) onTap;

  @override
  Color? get barrierColor => Colors.black26;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss pinned messages';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomSingleChildLayout(
        delegate: _PopupLayoutDelegate(
          anchor: anchor,
          containerSize: constraints.biggest,
        ),
        child: FadeTransition(
          opacity: animation,
          child: _PinnedMessagesPanel(
            roomId: roomId,
            onTap: onTap,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

// ── Popup positioning ──────────────────────────────────────────────

class _PopupLayoutDelegate extends SingleChildLayoutDelegate {
  _PopupLayoutDelegate({required this.anchor, required this.containerSize});

  final Rect anchor;
  final Size containerSize;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: 420.0.clamp(0, constraints.maxWidth - 16),
      maxHeight: 400.0.clamp(0, constraints.maxHeight - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var dx = anchor.right - childSize.width;
    dx = dx.clamp(8.0, size.width - childSize.width - 8);

    var dy = anchor.bottom + 4;
    if (dy + childSize.height > size.height - 8) {
      dy = size.height - childSize.height - 8;
    }

    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_PopupLayoutDelegate oldDelegate) {
    return anchor != oldDelegate.anchor ||
        containerSize != oldDelegate.containerSize;
  }
}

// ── Panel content ──────────────────────────────────────────────────

class _PinnedMessagesPanel extends StatefulWidget {
  const _PinnedMessagesPanel({
    required this.roomId,
    required this.onTap,
    required this.onClose,
  });

  final String roomId;
  final void Function(String eventId) onTap;
  final VoidCallback onClose;

  @override
  State<_PinnedMessagesPanel> createState() => _PinnedMessagesPanelState();
}

class _PinnedMessagesPanelState extends State<_PinnedMessagesPanel> {
  List<KoheraMessageDisplay>? _messages;
  bool _loading = true;
  late bool _canUnpin;

  @override
  void initState() {
    super.initState();
    final matrix = context.read<MatrixService>();
    _canUnpin = PinnedMessagesLoader.canPin(matrix, widget.roomId);
    unawaited(_loadPinnedEvents());
  }

  Future<void> _loadPinnedEvents() async {
    final matrix = context.read<MatrixService>();
    final messages =
        await PinnedMessagesLoader.load(matrix, widget.roomId);
    if (mounted) {
      setState(() {
        _messages = messages;
        _loading = false;
      });
    }
  }

  Future<void> _unpin(String eventId) async {
    try {
      final matrix = context.read<MatrixService>();
      await PinnedMessagesLoader.unpin(matrix, widget.roomId, eventId);
      if (mounted) {
        setState(() {
          _messages?.removeWhere((m) => m.eventId == eventId);
        });
        if (_messages?.isEmpty ?? true) widget.onClose();
      }
    } catch (e) {
      if (mounted) context.showSnack('Failed to unpin message');
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.read<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      color: cs.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
            child: Row(
              children: [
                Text(
                  'Pinned Messages',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(KIcons.closeRounded, size: 18),
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_messages == null || _messages!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No pinned messages',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _messages!.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
                itemBuilder: (context, i) {
                  final message = _messages![i];
                  return _PinnedMessageTile(
                    message: message,
                    canUnpin: _canUnpin,
                    avatarResolver: matrix.avatarResolver,
                    mentionResolver: (_) => null,
                    mediaResolver: matrix.mediaResolver,
                    onOpen: () {
                      widget.onClose();
                      widget.onTap(message.eventId);
                    },
                    onUnpin: () => _unpin(message.eventId),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Individual pinned message tile ─────────────────────────────────

class _PinnedMessageTile extends StatelessWidget {
  const _PinnedMessageTile({
    required this.message,
    required this.canUnpin,
    required this.avatarResolver,
    required this.mentionResolver,
    required this.mediaResolver,
    required this.onOpen,
    required this.onUnpin,
  });

  final KoheraMessageDisplay message;
  final bool canUnpin;
  final AvatarResolver avatarResolver;
  final MentionDisplayNameResolver mentionResolver;
  final MediaResolver mediaResolver;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final displayName = message.senderName;
    final time = _formatDateTime(message.timestamp);

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        avatarResolver: avatarResolver,
                        avatarUrl: message.senderAvatarUrl,
                        userId: message.senderId,
                        displayname: displayName,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: tt.labelSmall?.copyWith(
                          color:
                              cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 2),
                    child: _buildBody(tt, cs),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionChip(
                  label: 'Open',
                  onTap: onOpen,
                ),
                if (canUnpin) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        KIcons.closeRounded,
                        size: 14,
                        color:
                            cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      onPressed: onUnpin,
                      tooltip: 'Unpin',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(TextTheme tt, ColorScheme cs) {
    final bodyStyle = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final formattedHtml = message.formattedHtml;

    if (formattedHtml != null) {
      return HtmlMessageText(
        html: formattedHtml,
        style: bodyStyle,
        isMe: false,
        mentionResolver: mentionResolver,
        mediaResolver: mediaResolver,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return LinkableText(
      text: stripReplyFallback(message.body),
      style: bodyStyle,
      isMe: false,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  static String _formatDateTime(DateTime ts) {
    final now = DateTime.now();
    final isToday =
        ts.year == now.year && ts.month == now.month && ts.day == now.day;
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    if (isToday) return '$h:$m';
    final d = ts.day.toString().padLeft(2, '0');
    final mo = ts.month.toString().padLeft(2, '0');
    if (ts.year != now.year) return '$d/$mo/${ts.year} $h:$m';
    return '$d/$mo $h:$m';
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        ),
        child: Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
