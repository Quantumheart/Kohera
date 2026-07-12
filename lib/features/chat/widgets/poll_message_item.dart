import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_skin.dart';
import 'package:provider/provider.dart';

/// Read-only rendering of an MSC3381 poll-start event as a bubble.
///
/// Shows the question, answer options, a disclosed/undisclosed badge, and the
/// open/ended state. Per-option tallies are rendered for disclosed polls and
/// for ended undisclosed polls. Voting/ending is out of scope.
class PollMessageItem extends StatelessWidget {
  const PollMessageItem({
    required this.poll,
    required this.isMe,
    required this.isFirst,
    super.key,
  });

  final KoheraPoll poll;
  final bool isMe;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = DensityMetrics.of(density);
    final body = _PollBody(poll: poll);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: MessageBubbleSkin(
        isMe: isMe,
        isFirst: isFirst,
        metrics: metrics,
        child: body,
      ),
    );
  }
}

class _PollBody extends StatelessWidget {
  const _PollBody({required this.poll});

  final KoheraPoll poll;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final palette = KoheraPalette.of(context);

    final showTally = poll.showsTally;
    final maxVotes = poll.tallies.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.poll, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                poll.question,
                style: tt.titleSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _StateBadge(poll: poll),
        const SizedBox(height: 8),
        for (final answer in poll.answers) ...[
          _AnswerRow(
            answer: answer,
            count: poll.tallies[answer.id] ?? 0,
            maxVotes: maxVotes,
            showTally: showTally,
            palette: palette,
          ),
          const SizedBox(height: 6),
        ],
        if (showTally)
          Text(
            '${poll.responseCount} ${poll.responseCount == 1 ? "vote" : "votes"}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.poll});

  final KoheraPoll poll;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final disclosed = poll.kind == KoheraPollKind.disclosed;
    final label = disclosed
        ? (poll.ended ? 'Disclosed · ended' : 'Disclosed · open')
        : (poll.ended ? 'Undisclosed · ended' : 'Undisclosed · open');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.answer,
    required this.count,
    required this.maxVotes,
    required this.showTally,
    required this.palette,
  });

  final KoheraPollAnswer answer;
  final int count;
  final int maxVotes;
  final bool showTally;
  final KoheraPalette palette;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final fraction = maxVotes > 0 ? count / maxVotes : 0.0;

    return ClipRect(
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (showTally && fraction > 0)
            FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                height: 22,
                color: cs.primary.withValues(alpha: 0.25),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    answer.label,
                    style: tt.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showTally)
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.end,
                      style: tt.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
