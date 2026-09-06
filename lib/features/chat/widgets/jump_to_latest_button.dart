import 'package:flutter/material.dart';

/// A small circular affordance shown over the timeline when the view is a
/// fragmented context jump (e.g. after navigating to a search result). Tapping
/// reloads the live timeline and scrolls to the newest message.
class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({
    required this.onTap,
    this.isLoading = false,
    super.key,
  });

  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: const ValueKey('jump_to_latest'),
      onPressed: onTap,
      tooltip: 'Jump to latest',
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      child: isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(cs.onPrimaryContainer),
              ),
            )
          : const Icon(Icons.arrow_downward_rounded),
    );
  }
}
