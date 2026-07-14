import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_skin.dart';
import 'package:provider/provider.dart';

/// Rendering of an MSC3381 poll-start event as a bubble.
///
/// Shows the question, answer options, a disclosed/undisclosed badge, and the
/// open/ended state. Per-option tallies are rendered for disclosed polls and
/// for ended undisclosed polls. When [onVote] is provided and the poll has not
/// ended, options are tappable: single-select replaces the prior choice,
/// multi-select toggles selections up to [KoheraPoll.maxSelections]. Tapping
/// the only selected option retracts the vote (sends an empty answer list).
class PollMessageItem extends StatefulWidget {
  const PollMessageItem({
    required this.poll,
    required this.isMe,
    required this.isFirst,
    this.onVote,
    this.onEnd,
    super.key,
  });

  final KoheraPoll poll;
  final bool isMe;
  final bool isFirst;

  /// Called with the full new answer-id list when the user changes their
  /// selection. `null` (or the poll being ended) disables interaction.
  final void Function(List<String> answerIds)? onVote;

  /// Called when the user ends the poll. Only invoked when [KoheraPoll.canEnd]
  /// is true and the poll has not already ended. `null` hides the affordance.
  final Future<void> Function()? onEnd;

  @override
  State<PollMessageItem> createState() => _PollMessageItemState();
}

class _PollMessageItemState extends State<PollMessageItem> {
  late Set<String> _selections;

  @override
  void initState() {
    super.initState();
    _selections = widget.poll.mySelections;
  }

  @override
  void didUpdateWidget(covariant PollMessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll.mySelections != widget.poll.mySelections) {
      _selections = widget.poll.mySelections;
    }
  }

  bool get _interactive => !widget.poll.ended && widget.onVote != null;

  bool get _canEnd =>
      widget.onEnd != null && widget.poll.canEnd && !widget.poll.ended;

  void _tap(String answerId) {
    if (!_interactive) return;
    final next = computeNextSelection(
      current: _selections,
      answerId: answerId,
      maxSelections: widget.poll.maxSelections,
    );
    if (listEquals(next, _selections.toList())) return;
    setState(() => _selections = next.toSet());
    widget.onVote!.call(next);
  }

  bool _ending = false;

  Future<void> _endPoll() async {
    if (_ending || !_canEnd) return;
    setState(() => _ending = true);
    try {
      await widget.onEnd!();
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = DensityMetrics.of(density);
    final body = _PollBody(
      poll: widget.poll,
      selections: _selections,
      interactive: _interactive,
      canEnd: _canEnd,
      ending: _ending,
      onTap: _tap,
      onEnd: _endPoll,
    );

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: MessageBubbleSkin(
        isMe: widget.isMe,
        isFirst: widget.isFirst,
        metrics: metrics,
        child: body,
      ),
    );
  }
}

/// Pure selection computation shared with tests.
///
/// Single-select (`maxSelections == 1`): tapping the selected option retracts
/// (returns `[]`); tapping any other returns `[answerId]`.
///
/// Multi-select: tapping a selected option removes it; tapping an unselected
/// option adds it only if the current count is below `maxSelections`,
/// otherwise the selection is unchanged.
List<String> computeNextSelection({
  required Set<String> current,
  required String answerId,
  required int maxSelections,
}) {
  if (maxSelections <= 1) {
    if (current.contains(answerId)) return const [];
    return [answerId];
  }
  if (current.contains(answerId)) {
    return current.where((id) => id != answerId).toList();
  }
  if (current.length >= maxSelections) {
    return current.toList();
  }
  return [...current, answerId];
}

class _PollBody extends StatelessWidget {
  const _PollBody({
    required this.poll,
    required this.selections,
    required this.interactive,
    required this.canEnd,
    required this.ending,
    required this.onTap,
    required this.onEnd,
  });

  final KoheraPoll poll;
  final Set<String> selections;
  final bool interactive;
  final bool canEnd;
  final bool ending;
  final void Function(String answerId) onTap;
  final Future<void> Function() onEnd;

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
            selected: selections.contains(answer.id),
            interactive: interactive,
            count: poll.tallies[answer.id] ?? 0,
            maxVotes: maxVotes,
            showTally: showTally,
            palette: palette,
            onTap: () => onTap(answer.id),
          ),
          const SizedBox(height: 6),
        ],
        if (showTally)
          Text(
            '${poll.responseCount} ${poll.responseCount == 1 ? "vote" : "votes"}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        if (poll.ended)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Final results',
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else if (canEnd)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: ending ? null : onEnd,
                icon: ending
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('End poll'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
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
    required this.selected,
    required this.interactive,
    required this.count,
    required this.maxVotes,
    required this.showTally,
    required this.palette,
    required this.onTap,
  });

  final KoheraPollAnswer answer;
  final bool selected;
  final bool interactive;
  final int count;
  final int maxVotes;
  final bool showTally;
  final KoheraPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final fraction = maxVotes > 0 ? count / maxVotes : 0.0;
    final fillColor = selected
        ? cs.primary.withValues(alpha: 0.35)
        : cs.primary.withValues(alpha: 0.25);

    Widget row = ClipRect(
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (showTally && fraction > 0)
            FractionallySizedBox(
              widthFactor: fraction,
              child: Container(height: 22, color: fillColor),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    answer.label,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
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

    if (interactive) {
      row = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(0),
        child: row,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? cs.primary : palette.borderStrong,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(0),
      ),
      child: row,
    );
  }
}
