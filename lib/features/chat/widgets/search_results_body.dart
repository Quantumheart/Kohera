import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/widgets/search_result_tile.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

class SearchResultsBody extends StatefulWidget {
  const SearchResultsBody({
    required this.search,
    required this.avatarResolver,
    required this.onTapResult,
    required this.onClose,
    this.onRecentQuerySelected,
    super.key,
  });

  final ChatSearchController search;
  final AvatarResolver avatarResolver;
  final ValueChanged<String> onTapResult;
  final VoidCallback onClose;
  final ValueChanged<String>? onRecentQuerySelected;

  @override
  State<SearchResultsBody> createState() => _SearchResultsBodyState();
}

class _SearchResultsBodyState extends State<SearchResultsBody> {
  final _scrollController = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'search-results');
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    widget.search.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      _selectedIndex = 0;
      setState(() {});
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200 &&
        widget.search.nextBatch != null &&
        !widget.search.isLoading) {
      unawaited(widget.search.performSearch(loadMore: true));
    }
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final target = _selectedIndex * 80.0;
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = widget.search;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final query = search.query;

    if (query.isEmpty && search.recentQueries.isNotEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16, left: 16, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent searches',
                style: tt.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: search.recentQueries.length,
              itemBuilder: (context, i) {
                final q = search.recentQueries[i];
                return ListTile(
                  leading: Icon(Icons.history_rounded,
                      size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  title: Text(q, style: tt.bodyMedium),
                  trailing: IconButton(
                    icon: Icon(Icons.close_rounded, size: 18,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    onPressed: () {
                      unawaited(search.removeRecentQuery(q));
                    },
                  ),
                  onTap: () {
                    widget.onRecentQuerySelected?.call(q);
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    if (query.length < ChatSearchController.minQueryLength) {
      return _centerMessage(
        'Type at least ${ChatSearchController.minQueryLength} characters to search',
        tt, cs,
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

    final items = _buildItems(search.results);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        children: [
          if (search.isEncryptedRoom)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
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
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length + (search.nextBatch != null ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: search.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const SizedBox.shrink(),
                    ),
                  );
                }

                final item = items[i];
                if (item is _DateSeparator) {
                  return _DateSeparatorWidget(label: item.label, cs: cs, tt: tt);
                }

                final result = (item as _ResultItem).result;
                final resultIndex = item.resultIndex;
                final isSelected = resultIndex == _selectedIndex;

                return Container(
                  color: isSelected
                      ? cs.primaryContainer.withValues(alpha: 0.3)
                      : null,
                  child: SearchResultTile(
                    result: result,
                    avatarResolver: widget.avatarResolver,
                    highlights: search.highlights,
                    query: query,
                    onTap: () => widget.onTapResult(result.message.eventId),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Object> _buildItems(List<RoomSearchResult> results) {
    final items = <Object>[];
    DateTime? lastDate;
    var resultIndex = 0;

    for (final result in results) {
      final ts = result.message.timestamp;
      if (lastDate == null || !isSameDay(lastDate, ts)) {
        items.add(_DateSeparator(formatDateLabel(ts)));
        lastDate = ts;
      }
      items.add(_ResultItem(result, resultIndex));
      resultIndex++;
    }

    return items;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final search = widget.search;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1)
            .clamp(0, search.results.length - 1);
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, search.results.length - 1);
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex < search.results.length) {
        widget.onTapResult(search.results[_selectedIndex].message.eventId);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _centerMessage(String text, TextTheme tt, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DateSeparator {
  const _DateSeparator(this.label);
  final String label;
}

class _ResultItem {
  const _ResultItem(this.result, this.resultIndex);
  final RoomSearchResult result;
  final int resultIndex;
}

class _DateSeparatorWidget extends StatelessWidget {
  const _DateSeparatorWidget({
    required this.label,
    required this.cs,
    required this.tt,
  });

  final String label;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label.toUpperCase(),
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
        ],
      ),
    );
  }
}
