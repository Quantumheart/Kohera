import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/widgets/search_result_tile.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

/// Displays search results for in-room message search.
///
/// Shows contextual states: minimum query prompt, loading spinner,
/// error, empty results, or a scrollable results list with a result count
/// header and infinite-scroll pagination.
class SearchResultsBody extends StatefulWidget {
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
  State<SearchResultsBody> createState() => _SearchResultsBodyState();
}

class _SearchResultsBodyState extends State<SearchResultsBody> {
  late final ScrollController _scrollController;

  /// Distance from the bottom (in pixels) that triggers a load-more.
  static const _loadMoreThreshold = 200;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold &&
        widget.search.nextBatch != null &&
        !widget.search.isLoading) {
      unawaited(widget.search.performSearch(loadMore: true));
    }
  }

  /// Builds the result count header text shown above the list.
  String _countText(ChatSearchController search) {
    final count = search.count;
    if (count != null) {
      if (count > search.results.length) {
        return 'Found $count results for "${search.query}"';
      }
      return 'Found $count results';
    }
    return 'Showing ${search.results.length} results';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final query = widget.search.query;

    // Not enough characters yet.
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

    // Error state.
    if (widget.search.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.error.withValues(alpha: 0.6),),
              const SizedBox(height: 12),
              Text(
                widget.search.error!,
                style: tt.bodyMedium?.copyWith(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Loading first batch.
    if (widget.search.isLoading && widget.search.results.isEmpty) {
      return const Center(child: KoheraLoader());
    }

    // Empty results.
    if (widget.search.results.isEmpty && !widget.search.isLoading) {
      // Encrypted room on a platform without the local FTS5 index (e.g. web).
      if (widget.search.isEncryptedRoom && !widget.search.hasLocalIndex) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4),),
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

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4),),
              const SizedBox(height: 12),
              Text(
                'No messages found for "$query"',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.search.isEncryptedRoom) ...[
                const SizedBox(height: 8),
                Text(
                  'Encrypted rooms are searched on this device only.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Results list with count header and infinite scroll.
    final showLoadingMore =
        widget.search.isLoading && widget.search.nextBatch != null;

    return Column(
      children: [
        // Result count header.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            _countText(widget.search),
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        // Results list.
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.search.results.length + (showLoadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              // Loading indicator at the bottom while fetching more.
              if (i == widget.search.results.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final result = widget.search.results[i];
              return SearchResultTile(
                result: result,
                avatarResolver: widget.avatarResolver,
                query: query,
                highlights: widget.search.highlights,
                onTap: () => widget.onTapResult(result.message.eventId),
              );
            },
          ),
        ),
      ],
    );
  }

}
