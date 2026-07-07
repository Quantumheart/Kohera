import 'package:flutter/material.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/utils/format_duration.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/shared/models/call_constants.dart';
class CallEventTile extends StatelessWidget {
  const CallEventTile({
    required this.message,
    required this.isMe,
    this.onTap,
    this.duration,
    super.key,
  });

  final KoheraMessageDisplay message;
  final bool isMe;
  final VoidCallback? onTap;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (icon, text) = _resolve();

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) const SizedBox(width: 40),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMessageTime(message.timestamp),
                      style: tt.bodySmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isMe) const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  (IconData, String) _resolve() {
    final sender = message.senderName;

    switch (message.eventType) {
      case kCallInvite:
        return (
          KIcons.callMissedRounded,
          'Missed call from $sender — legacy client',
        );

      case kCallHangup:
        final reason = message.content['reason'] as String?;
        if (reason == 'invite_timeout') {
          return (KIcons.callMissedRounded, 'Missed call from $sender');
        }
        final label = duration != null
            ? 'Call ended \u2014 '
                '${formatClockDuration(duration!, padMinutes: false)}'
            : 'Call ended';
        return (KIcons.callEndRounded, label);

      case kCallReject:
        return (KIcons.callEndRounded, '$sender declined the call');

      case kCallAnswer:
        return (KIcons.callRounded, '$sender answered the call');

      default:
        return (KIcons.callRounded, 'Call event');
    }
  }
}
