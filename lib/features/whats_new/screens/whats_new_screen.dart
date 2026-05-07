import 'package:flutter/material.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/features/whats_new/widgets/release_notes_markdown.dart';
import 'package:provider/provider.dart';

/// Full-page release notes view reachable from the home banner.
///
/// This is the minimal scaffolding; richer presentation (hero header,
/// version timeline, etc.) lands in the dedicated detail-page sub-issue.
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  late Future<ReleaseNotes?> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<GitHubReleasesService>().fetchLatest();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: FutureBuilder<ReleaseNotes?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final notes = snapshot.data;
          if (notes == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Couldn't load release notes. Check your connection and "
                  'try again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notes.name.isNotEmpty ? notes.name : notes.tagName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                ReleaseNotesMarkdown(data: notes.body),
              ],
            ),
          );
        },
      ),
    );
  }
}
