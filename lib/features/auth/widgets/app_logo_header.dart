import 'package:flutter/material.dart';

import 'package:kohera/core/brand/brand_constants.dart';
import 'package:kohera/shared/widgets/kohera_mark.dart';
import 'package:kohera/shared/widgets/kohera_wordmark.dart';

/// Stacked brand lockup shown on auth screens: mark on top, wordmark below,
/// tagline under the wordmark, then the per-screen contextual subtitle.
/// See `plans/brand_wordmark_brief.md` §3.1 (stacked, 0.8:1 mark:wordmark).
class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({required this.subtitle, super.key});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Mark is rendered at an integer scale of the 32-grid (32px = 1px/cell) to
    // keep crispEdges intact; wordmark is sized 0.8:1 (mark smaller) per the
    // stacked-lockup spec.
    const markSize = 32.0;
    const wordmarkSize = 40.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KoheraMark(size: markSize),
        const SizedBox(height: 8),
        const KoheraWordmark(size: wordmarkSize),
        const SizedBox(height: 10),
        Text(
          BrandConstants.tagline,
          style: TextStyle(
            fontFamily: 'DepartureMono',
            fontSize: 13,
            height: 1.4,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 40),
      ],
    );
  }
}
