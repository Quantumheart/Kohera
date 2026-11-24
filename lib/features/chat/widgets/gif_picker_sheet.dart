import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:kohera/features/chat/services/giphy_service.dart';
import 'package:material_ui/material_ui.dart';

Future<GiphyGif?> showGifPickerSheet(
  BuildContext context, {
  required GiphyService service,
}) {
  return showModalBottomSheet<GiphyGif>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.8,
      child: GifPickerSheet(service: service),
    ),
  );
}

class GifPickerSheet extends StatefulWidget {
  const GifPickerSheet({required this.service, super.key});

  final GiphyService service;

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  static const _debounce = Duration(milliseconds: 350);

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final _gifs = <GiphyGif>[];
  String _query = '';
  int _offset = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _gifs.clear();
      _offset = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = _query.isEmpty
          ? await widget.service.trending(offset: _offset)
          : await widget.service.search(_query, offset: _offset);
      if (!mounted) return;
      setState(() {
        _gifs.addAll(batch);
        _offset += batch.length;
        _hasMore = batch.length >= GiphyService.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted || value.trim() == _query) return;
      _query = value.trim();
      unawaited(_loadInitial());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search GIFs',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildBody(theme)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Powered by GIPHY',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_gifs.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_gifs.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load GIFs', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _loadMore,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_gifs.isEmpty) {
      return const Center(child: Text('No GIFs found'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 180).ceil().clamp(2, 6);
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _gifs.length + (_loading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _gifs.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final gif = _gifs[index];
            return InkWell(
              onTap: () => Navigator.of(context).pop(gif),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: gif.previewUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, _, _) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
