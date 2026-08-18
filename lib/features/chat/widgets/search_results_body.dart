import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/widgets/search_result_tile.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

/// Displays search results for in-room message search.
///
/// Shows contextual states: minimum query prompt, loading spinner,
/// error, empty results, or a scrollable results list with a result count
/// header, date separators, and infinite-scroll pagination.
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
    widget.search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    // Auto-scroll to keep the selected result visible.
    final idx = widget.search.selectedIndex;
    if (idx >= 0 && idx < widget.search.results.length && _scrollController.hasClients) {
      final items = _buildItems(widget.search.results);
      // Find the flat-list index for this result.
      var flatIndex = 0;
      var resultIdx = 0;
      for (final item in items) {
        if (!item.isSeparator) {
          if (resultIdx == idx) break;
          resultIdx++;
        }
        flatIndex++;
      }
      _scrollController.animateTo(
        flatIndex * 72.0, // approximate tile height
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      );
    }
    setState(() {});
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

  /// Pre-processes results into a flat list of list items, inserting a date
  /// separator before any result whose timestamp falls on a different day
  /// than the previous result.
  List<_ListItem> _buildItems(List<RoomSearchResult> results) {
    final items = <_ListItem>[];
    DateTime? prevDay;
    for (final result in results) {
      final ts = result.message.timestamp;
      final day = DateTime(ts.year, ts.month, ts.day);
      if (prevDay == null || day != prevDay) {
        items.add(_ListItem.separator(formatDateLabel(ts)));
      }
      items.add(_ListItem.result(result));
      prevDay = day;
    }
    return items;
  }

  // ── Filter chips ────────────────────────────────────────────

  /// Extracts unique senders from the current results as a map of
  /// sender ID → display name.
  Map<String, String> _extractSenders() {
    final senders = <String, String>{};
    for (final result in widget.search.results) {
      senders[result.message.senderId] = result.message.senderName;
    }
    return senders;
  }

  /// Formats a [DateTimeRange] as a compact label for the filter chip.
  String _formatDateRangeLabel(DateTimeRange range) {
    final start = formatDateLabel(range.start);
    final end = formatDateLabel(range.end);
    if (start == end) return start;
    return '$start – $end';
  }

  /// Builds the horizontally scrollable row of filter chips shown below
  /// the result count header.
  Widget _buildFilterChips(
    BuildContext context,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final search = widget.search;
    final senders = _extractSenders();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Sender filter chip.
          FilterChip(
            label: Text(
              search.senderFilter != null
                  ? senders[search.senderFilter] ?? 'Sender'
                  : 'All senders',
            ),
            selected: search.senderFilter != null,
            avatar: Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onSelected: (_) => _showSenderPicker(context, senders),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          // Date range filter chip.
          FilterChip(
            label: Text(
              search.dateRange != null
                  ? _formatDateRangeLabel(search.dateRange!)
                  : 'All dates',
            ),
            selected: search.dateRange != null,
            avatar: Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onSelected: (_) => _showDateRangePicker(context),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          // Clear filters chip.
          if (search.hasActiveFilters) ...[
            const SizedBox(width: 8),
            ActionChip(
              label: const Text('Clear filters'),
              avatar: Icon(
                Icons.filter_alt_off_outlined,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              onPressed: search.clearFilters,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  /// Shows a dialog listing all senders found in the current results,
  /// allowing the user to narrow results to a specific sender.
  Future<void> _showSenderPicker(
    BuildContext context,
    Map<String, String> senders,
  ) async {
    final search = widget.search;
    final currentFilter = search.senderFilter;

    final selectedId = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Filter by sender'),
          children: [
            // "All senders" option.
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Row(
                children: [
                  Icon(
                    currentFilter == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: Theme.of(dialogContext).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Text('All senders'),
                ],
              ),
            ),
            const Divider(height: 1),
            // Individual senders.
            for (final entry in senders.entries)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(entry.key),
                child: Row(
                  children: [
                    Icon(
                      currentFilter == entry.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry.value)),
                  ],
                ),
              ),
          ],
        );
      },
    );

    if (selectedId != null || currentFilter != null) {
      search.senderFilter = selectedId;
    }
  }

  /// Shows the Material date-range picker and applies the selected range
  /// as a date filter.
  Future<void> _showDateRangePicker(BuildContext context) async {
    final search = widget.search;
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5);
    final lastDate = DateTime(now.year, now.month, now.day);

    final range = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: search.dateRange,
      helpText: 'Filter by date range',
    );

    if (range != null) {
      search.dateRange = range;
    }
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

    // Results list with count header, date separators, and infinite scroll.
    final showLoadingMore =
        widget.search.isLoading && widget.search.nextBatch != null;
    final items = _buildItems(widget.search.results);
    final itemCount = items.length + (showLoadingMore ? 1 : 0);

    return Column(
      children: [
        // Result count header.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _countText(widget.search),
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.search.isIndexingRoom)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Indexing messages for search…',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Filter chips (only visible when results are present).
        if (widget.search.results.isNotEmpty)
          _buildFilterChips(context, cs, tt),
        // Results list.
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: itemCount,
            itemBuilder: (context, i) {
              // Loading indicator at the bottom while fetching more.
              if (i == items.length) {
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

              final item = items[i];
              if (item.isSeparator) {
                return _DateSeparator(label: item.label!);
              }

              final result = item.result!;
              // Compute the result-only index for selection matching.
              var resultIndex = 0;
              for (var j = 0; j < i; j++) {
                if (!items[j].isSeparator) resultIndex++;
              }
              return SearchResultTile(
                result: result,
                avatarResolver: widget.avatarResolver,
                query: query,
                highlights: widget.search.highlights,
                isSelected: resultIndex == widget.search.selectedIndex,
                onTap: () => widget.onTapResult(result.message.eventId),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A single item in the flattened search results list — either a date
/// separator header or a search result tile.
class _ListItem {
  _ListItem.separator(this.label) : result = null;
  _ListItem.result(this.result) : label = null;

  final String? label;
  final RoomSearchResult? result;

  bool get isSeparator => label != null;
}

/// A date separator header rendered between results on different days.
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
        ],
      ),
    );
  }
}
