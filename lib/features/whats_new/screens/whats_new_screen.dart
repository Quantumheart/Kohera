import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/features/whats_new/widgets/release_notes_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

typedef WhatsNewLinkLauncher = Future<bool> Function(Uri uri);

class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({
    super.key,
    @visibleForTesting this.linkLauncher,
  });

  final WhatsNewLinkLauncher? linkLauncher;

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  ReleaseNotes? _notes;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final service = context.read<GitHubReleasesService>();
    try {
      final result = await service.fetchLatest(forceRefresh: forceRefresh);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = 'No release notes available.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _notes = result;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[Kohera] WhatsNew load failed: $e');
      debugPrintStack(stackTrace: st);
      ReleaseNotes? cached;
      try {
        cached = await service.getCached();
      } catch (_) {
        cached = null;
      }
      if (!mounted) return;
      setState(() {
        _error = e;
        if (cached != null) _notes = cached;
        _loading = false;
      });
    }
  }

  Future<void> _openHtmlUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final launcher = widget.linkLauncher ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    unawaited(launcher(uri));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_notes == null) {
      if (_loading) return const _ScrollableCenter(child: _LoadingView());
      return _ScrollableCenter(
        child: _ErrorView(
          message: _errorMessage(),
          onRetry: () => _load(forceRefresh: true),
        ),
      );
    }
    return _NotesView(
      notes: _notes!,
      staleNotice: _error != null,
      onOpenGitHub: () => _openHtmlUrl(_notes!.htmlUrl),
    );
  }

  String _errorMessage() {
    final err = _error;
    if (err is String) return err;
    return "Couldn't load release notes. Check your connection and try again.";
  }
}

class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) =>
      const CircularProgressIndicator.adaptive();
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class _NotesView extends StatelessWidget {
  const _NotesView({
    required this.notes,
    required this.staleNotice,
    required this.onOpenGitHub,
  });

  final ReleaseNotes notes;
  final bool staleNotice;
  final VoidCallback onOpenGitHub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = notes.name.isNotEmpty ? notes.name : notes.tagName;
    final published =
        MaterialLocalizations.of(context).formatMediumDate(notes.publishedAt);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '${notes.tagName} · $published',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (staleNotice) ...[
          const _StaleBanner(),
          const SizedBox(height: 12),
        ],
        ReleaseNotesMarkdown(data: notes.body),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onOpenGitHub,
            icon: const Icon(Icons.open_in_new),
            label: const Text('View on GitHub'),
          ),
        ),
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing cached release notes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
