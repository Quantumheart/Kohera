import 'package:flutter/material.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

class StickerPickerOverlay extends StatefulWidget {
  const StickerPickerOverlay({
    required this.packs,
    required this.mediaResolver,
    required this.onStickerTapped,
    required this.onEmojiTapped,
    required this.onManagePacks,
    super.key,
    this.skinTone = SkinTone.none,
  });

  final List<StickerPack> packs;
  final MediaResolver mediaResolver;
  final void Function(PackImage) onStickerTapped;
  final void Function(PackImage) onEmojiTapped;
  final VoidCallback onManagePacks;
  final SkinTone skinTone;

  @override
  State<StickerPickerOverlay> createState() => _StickerPickerOverlayState();
}

class _StickerPickerOverlayState extends State<StickerPickerOverlay> with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  TabController? _tabController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.packs.isNotEmpty) {
      _tabController = TabController(length: widget.packs.length, vsync: this);
    }
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void didUpdateWidget(StickerPickerOverlay old) {
    super.didUpdateWidget(old);
    if (old.packs.length != widget.packs.length) {
      _tabController?.dispose();
      _tabController = widget.packs.isEmpty ? null : TabController(length: widget.packs.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(PackImage img) {
    if (_query.isEmpty) return true;
    return img.shortcode.toLowerCase().contains(_query) || (img.body?.toLowerCase().contains(_query) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return widget.packs.isEmpty ? _buildEmptyState(cs) : _buildPicker(cs);
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 48,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No sticker packs configured',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onManagePacks,
            child: const Text('Manage packs'),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(ColorScheme cs) {
    return Column(
      children: [
        _buildSearchField(cs),
        if (_query.isEmpty) ...[
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final pack in widget.packs)
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pack.avatarUrl != null) ...[
                              MxcImage(
                                mxcUrl: pack.avatarUrl!.toString(),
                                mediaResolver: widget.mediaResolver,
                                width: 18,
                                height: 18,
                                fallbackText: '',
                                fallbackStyle: null,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(pack.displayName),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                iconSize: 20,
                tooltip: 'Manage packs',
                onPressed: widget.onManagePacks,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (final pack in widget.packs) _buildPackView(pack),
              ],
            ),
          ),
        ] else
          Expanded(child: _buildSearchResults(cs)),
      ],
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search stickers & emoji…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: _searchCtrl.clear,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildPackView(StickerPack pack) {
    return CustomScrollView(
      slivers: [
        if (pack.stickers.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader('Stickers')),
          SliverGrid.builder(
            itemCount: pack.stickers.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 80,
              mainAxisExtent: 80,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (ctx, i) => _stickerItem(pack.stickers[i]),
          ),
        ],
        if (pack.emoji.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader('Emoji')),
          SliverGrid.builder(
            itemCount: pack.emoji.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 56,
              mainAxisExtent: 56,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (ctx, i) => _emojiItem(pack.emoji[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    final matchingStickers = [
      for (final p in widget.packs)
        for (final s in p.stickers)
          if (_matches(s)) s,
    ];
    final matchingEmoji = [
      for (final p in widget.packs)
        for (final e in p.emoji)
          if (_matches(e)) e,
    ];

    if (matchingStickers.isEmpty && matchingEmoji.isEmpty) {
      return Center(
        child: Text(
          'No results for "$_query"',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (matchingStickers.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader('Stickers')),
          SliverGrid.builder(
            itemCount: matchingStickers.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 80,
              mainAxisExtent: 80,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (ctx, i) => _stickerItem(matchingStickers[i]),
          ),
        ],
        if (matchingEmoji.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader('Emoji')),
          SliverGrid.builder(
            itemCount: matchingEmoji.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 56,
              mainAxisExtent: 56,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (ctx, i) => _emojiItem(matchingEmoji[i]),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _stickerItem(PackImage sticker) {
    return Tooltip(
      message: sticker.altText,
      child: GestureDetector(
        onTap: () => widget.onStickerTapped(sticker),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: MxcImage(
            mxcUrl: sticker.url.toString(),
            mediaResolver: widget.mediaResolver,
            width: 64,
            height: 64,
            fit: BoxFit.contain,
            fallbackText: sticker.altText,
            fallbackStyle: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }

  Widget _emojiItem(PackImage emoji) {
    final base = emoji.emoji;
    final toned = base == null ? null : applySkinTone(base, widget.skinTone);
    return Tooltip(
      message: emoji.altText,
      child: GestureDetector(
        onTap: () => widget.onEmojiTapped(
          toned == null ? emoji : _withGrapheme(emoji, toned),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: toned != null
              ? OpenMojiImage(grapheme: toned, size: 40)
              : MxcImage(
                  mxcUrl: emoji.url.toString(),
                  mediaResolver: widget.mediaResolver,
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  fallbackText: emoji.altText,
                  fallbackStyle: Theme.of(context).textTheme.bodySmall,
                ),
        ),
      ),
    );
  }

  PackImage _withGrapheme(PackImage source, String grapheme) => PackImage(
        shortcode: source.shortcode,
        url: source.url,
        isSticker: source.isSticker,
        isEmoji: source.isEmoji,
        body: source.body,
        emoji: grapheme,
      );
}
