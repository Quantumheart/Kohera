import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

typedef WhatsNewLinkLauncher = Future<bool> Function(Uri uri);

/// Dismissible banner with two modes:
///
/// 1. **Post-update** — installed version > last-seen version. Shows
///    "What's new in vX" linking to the in-app release notes screen.
/// 2. **Update-available** — latest GitHub release tag > installed
///    version. Shows "Update available vX" linking to the GitHub
///    release page.
///
/// Hidden until release notes have been fetched, so it never flickers
/// on slow networks.
class WhatsNewBanner extends StatefulWidget {
  const WhatsNewBanner({
    super.key,
    @visibleForTesting this.linkLauncher,
  });

  final WhatsNewLinkLauncher? linkLauncher;

  @override
  State<WhatsNewBanner> createState() => _WhatsNewBannerState();
}

class _WhatsNewBannerState extends State<WhatsNewBanner> {
  ReleaseNotes? _notes;
  bool _attempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_attempted) {
      _attempted = true;
      unawaited(_loadNotes());
    }
  }

  Future<void> _loadNotes() async {
    if (!mounted) return;
    final GitHubReleasesService service;
    try {
      service = context.read<GitHubReleasesService>();
    } on ProviderNotFoundException {
      return;
    }
    final notes = await service.fetchLatest();
    if (!mounted) return;
    setState(() => _notes = notes);
  }

  Future<void> _dismissPostUpdate() async {
    final prefs = context.read<PreferencesService>();
    final current = prefs.currentVersion;
    if (current == null) return;
    try {
      await prefs.markVersionSeen(current);
    } catch (e) {
      debugPrint('[Kohera] Failed to mark version seen: $e');
    }
  }

  Future<void> _dismissUpdateAvailable() async {
    final prefs = context.read<PreferencesService>();
    final tag = _notes?.tagName;
    if (tag == null || tag.isEmpty) return;
    try {
      await prefs.markUpdateDismissed(tag);
    } catch (e) {
      debugPrint('[Kohera] Failed to dismiss update notice: $e');
    }
  }

  void _viewReleaseNotes() {
    unawaited(context.pushNamed(Routes.whatsNew));
  }

  Future<void> _openLatestRelease() async {
    final url = _notes?.htmlUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final launcher = widget.linkLauncher ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    unawaited(launcher(uri));
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final notes = _notes;
    final currentVersion = prefs.currentVersion;

    Widget? content;
    if (notes != null && currentVersion != null) {
      if (prefs.hasVersionBumped) {
        content = _BannerContent(
          key: const ValueKey('post-update'),
          icon: Icons.auto_awesome,
          label: "What's new in v$currentVersion",
          semanticsLabel:
              "What's new in v$currentVersion. Tap View for details.",
          actionLabel: 'View',
          onAction: _viewReleaseNotes,
          onDismiss: _dismissPostUpdate,
        );
      } else if (prefs.isUpdateAvailable(notes.tagName)) {
        content = _BannerContent(
          key: const ValueKey('update-available'),
          icon: Icons.system_update_alt,
          label: 'Update available · ${notes.tagName}',
          semanticsLabel:
              'Update available ${notes.tagName}. Tap Open to view the release.',
          actionLabel: 'Open',
          onAction: _openLatestRelease,
          onDismiss: _dismissUpdateAvailable,
        );
      }
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: content ?? const SizedBox.shrink(),
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    super.key,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        label: semanticsLabel,
        button: true,
        child: InkWell(
          onTap: onAction,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
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
