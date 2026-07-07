import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:provider/provider.dart';
enum _Phase { sent, sending, retrying, failed }

class MessageBubbleOutboxStatus extends StatelessWidget {
  const MessageBubbleOutboxStatus({
    required this.eventId,
    required this.transactionId,
    required this.status,
    required this.metrics,
    super.key,
  });

  final String eventId;
  final String? transactionId;
  final KoheraMessageStatus status;
  final DensityMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = KoheraPalette.of(context);
    final onBubble = palette.onOwnBubble;
    OutboxService? outbox;
    try {
      outbox = context.watch<OutboxService>();
    } on ProviderNotFoundException {
      outbox = null;
    }
    final entry = outbox == null ? null : _lookup(outbox);
    final phase = _phaseFor(entry);

    switch (phase) {
      case _Phase.sent:
        return Icon(
          status == KoheraMessageStatus.sent
              ? KIcons.doneAllRounded
              : KIcons.doneRounded,
          size: metrics.statusIconSize,
          color: onBubble.withValues(alpha: 0.6),
        );
      case _Phase.sending:
        return Semantics(
          label: 'Sending',
          child: Icon(
            KIcons.scheduleRounded,
            size: metrics.statusIconSize,
            color: onBubble.withValues(alpha: 0.6),
          ),
        );
      case _Phase.retrying:
        final next = entry?.nextRetryAt;
        final eta =
            next?.difference(DateTime.now()).inSeconds.clamp(0, 1 << 31);
        return Tooltip(
          message: eta == null
              ? 'Retrying'
              : 'Retrying in ${eta}s (attempt ${entry!.attempts + 1})',
          child: Semantics(
            label: eta == null
                ? 'Retrying to send'
                : 'Retrying to send, next attempt in $eta seconds',
            child: Icon(
              KIcons.scheduleRounded,
              size: metrics.statusIconSize,
              color: onBubble.withValues(alpha: 0.4),
            ),
          ),
        );
      case _Phase.failed:
        return Semantics(
          label: 'Failed to send',
          child: Icon(
            KIcons.errorOutlineRounded,
            size: metrics.statusIconSize,
            color: palette.danger,
          ),
        );
    }
  }

  OutboxEntryView? _lookup(OutboxService outbox) {
    final entries = outbox.entries;
    if (transactionId != null && entries.containsKey(transactionId)) {
      return entries[transactionId];
    }
    return entries[eventId];
  }

  _Phase _phaseFor(OutboxEntryView? entry) {
    if (entry == null) {
      if (status == KoheraMessageStatus.sent) return _Phase.sent;
      return _Phase.sending;
    }
    if (entry.finalFailed) return _Phase.failed;
    if (entry.attempts > 0) return _Phase.retrying;
    return _Phase.sending;
  }
}

@visibleForTesting
String debugPhaseFor(
  OutboxEntryView? entry,
  KoheraMessageStatus status,
  String eventId,
  String? transactionId,
) {
  if (entry == null) {
    if (status == KoheraMessageStatus.sent) return 'sent';
    return 'sending';
  }
  if (entry.finalFailed) return 'failed';
  if (entry.attempts > 0) return 'retrying';
  return 'sending';
}
