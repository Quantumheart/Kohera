import 'package:flutter/material.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/widgets/search_result_tile.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

class SearchResultsBody extends StatelessWidget {
  const SearchResultsBody({
    required this.search,
    required this.avatarResolver,
    required this.onTapResult,
    super.key,
  });

  final ChatSearchController search;
  final AvatarResolver avatarResolver;
  final ValueChanged<String> onTapResult;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final query = search.query;

    if (query.length < ChatSearchController.minQueryLength) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Type at least ${ChatSearchController.minQueryLength} characters to search',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (search.isEncryptedRoom &&
        search.results.isEmpty &&
        !search.isLoading &&
        search.count == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Search not available for encrypted rooms on this platform',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (search.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.error.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text(
                search.error!,
                style: tt.bodyMedium?.copyWith(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (search.isLoading && search.results.isEmpty) {
      return const Center(child: KoheraLoader());
    }

    if (search.results.isEmpty && !search.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'No messages found for "$query"',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              if (search.isEncryptedRoom) ...[
                const SizedBox(height: 8),
                Text(
                  'Only messages received on this device are searchable in encrypted rooms',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (search.isEncryptedRoom)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  'Searching indexed history (encrypted room)',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        if (search.count != null || search.results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              search.count != null
                  ? 'Found ${search.count} result${search.count == 1 ? '' : 's'}'
                  : 'Showing ${search.results.length} result${search.results.length == 1 ? '' : 's'}',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount:
                search.results.length + (search.nextBatch != null ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == search.results.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: search.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load more results'),
                  ),
                );
              }

              final result = search.results[i];
              return SearchResultTile(
                result: result,
                avatarResolver: avatarResolver,
                highlights: search.highlights,
                query: query,
                onTap: () => onTapResult(result.message.eventId),
              );
            },
          ),
        ),
      ],
    );
  }
}
