import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:provider/provider.dart';

/// Dismissible banner that announces a new app release.
///
/// Visible only when [PreferencesService.hasVersionBumped] is `true` AND
/// release notes have been fetched, so it never flickers on slow networks.
class WhatsNewBanner extends StatefulWidget {
  const WhatsNewBanner({super.key});

  @override
  State<WhatsNewBanner> createState() => _WhatsNewBannerState();
}

class _WhatsNewBannerState extends State<WhatsNewBanner> {
  ReleaseNotes? _notes;
  bool _loading = false;
  bool _attempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesService>();
    if (prefs.hasVersionBumped && !_attempted) {
      _attempted = true;
      unawaited(_loadNotes());
    }
  }

  Future<void> _loadNotes() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final service = context.read<GitHubReleasesService>();
      final notes = await service.fetchLatest();
      if (!mounted) return;
      setState(() => _notes = notes);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dismiss() async {
    final prefs = context.read<PreferencesService>();
    final current = prefs.currentVersion;
    if (current != null) {
      await prefs.markVersionSeen(current);
    }
  }

  void _viewDetails() {
    unawaited(context.pushNamed(Routes.whatsNew));
  }

  @override
  Widget build(BuildContext context) {
    final hasBump = context.select<PreferencesService, bool>(
      (p) => p.hasVersionBumped,
    );
    final notes = _notes;
    final visible = hasBump && notes != null && !_loading;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: visible
          ? _BannerContent(
              tagName: notes.tagName,
              onView: _viewDetails,
              onDismiss: _dismiss,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({
    required this.tagName,
    required this.onView,
    required this.onDismiss,
  });

  final String tagName;
  final VoidCallback onView;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        label: "What's new in $tagName. Tap View for details.",
        button: true,
        child: InkWell(
          onTap: onView,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "What's new in $tagName",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onView,
                  child: const Text('View'),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
