import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/models/emoji_gg_pack.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/emoji_gg_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:provider/provider.dart';

class EmojiGgBrowseScreen extends StatefulWidget {
  const EmojiGgBrowseScreen({super.key});

  @override
  State<EmojiGgBrowseScreen> createState() => _EmojiGgBrowseScreenState();
}

class _EmojiGgBrowseScreenState extends State<EmojiGgBrowseScreen> {
  final _emojiGgService = EmojiGgService();
  final _searchCtrl = TextEditingController();

  List<EmojiGgPack>? _packs;
  String _query = '';
  bool _loadError = false;

  // slug → 0.0–1.0 while importing; absent when idle or done
  final Map<String, double> _importing = {};
  Set<String> _importedSlugs = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
    unawaited(_loadPacks());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _importedSlugs =
        context.read<StickerPackService>().importedEmojiGgSlugs;
  }

  @override
  void dispose() {
    _emojiGgService.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPacks({bool forceRefresh = false}) async {
    setState(() {
      _packs = null;
      _loadError = false;
    });
    try {
      final packs =
          await _emojiGgService.fetchPacks(forceRefresh: forceRefresh);
      if (mounted) setState(() => _packs = packs);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  Future<void> _importPack(EmojiGgPack pack) async {
    if (pack.emojiSlugs.isEmpty) {
      context.showSnack('Pack details not available — try again later');
      return;
    }

    setState(() => _importing[pack.slug] = 0.0);

    final service = context.read<StickerPackService>();
    var succeeded = 0;

    await for (final progress
        in service.importEmojiGgPack(pack, _emojiGgService)) {
      if (!mounted) return;
      setState(() => _importing[pack.slug] = progress.fraction);
      if (progress.isComplete) succeeded = progress.done;
    }

    if (!mounted) return;
    setState(() {
      _importing.remove(pack.slug);
      _importedSlugs = service.importedEmojiGgSlugs;
    });

    context.showSnack(
      succeeded == 0
          ? 'Import failed — no images could be uploaded'
          : 'Imported $succeeded sticker${succeeded == 1 ? '' : 's'} '
              'from ${pack.name}',
    );
  }

  List<EmojiGgPack> get _filtered {
    final all = _packs ?? [];
    if (_query.isEmpty) return all;
    return all.where((p) {
      return p.name.toLowerCase().contains(_query) ||
          p.description.toLowerCase().contains(_query) ||
          (p.category?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(Routes.settingsStickerPacks),
        ),
        title: const Text('Browse emoji.gg'),
        actions: [
          if (_packs != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => _loadPacks(forceRefresh: true),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchField(cs),
          Expanded(child: _buildBody(cs)),
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search packs…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: _searchCtrl.clear,
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  Widget _buildBody(ColorScheme cs) {
    if (_packs == null && !_loadError) {
      return const Center(child: KoheraLoader());
    }

    if (_loadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              'Could not load packs',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadPacks,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final packs = _filtered;

    if (packs.isEmpty) {
      return Center(
        child: Text(
          'No packs found for "$_query"',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: packs.length,
      itemBuilder: (context, index) => _PackCard(
        pack: packs[index],
        isImported: _importedSlugs.contains(packs[index].slug),
        importProgress: _importing[packs[index].slug],
        onImport: () => _importPack(packs[index]),
      ),
    );
  }
}

// ── Pack card ────────────────────────────────────────────────────

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.isImported,
    required this.onImport,
    this.importProgress,
  });

  final EmojiGgPack pack;
  final bool isImported;
  final double? importProgress; // null = idle
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isImporting = importProgress != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview thumbnail
                _PackThumbnail(pack: pack),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pack.name, style: tt.titleSmall),
                      if (pack.category != null && pack.category!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            pack.category!,
                            style: tt.labelSmall?.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${pack.amount} emoji',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Action
                if (isImported)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: cs.primary,
                      size: 20,
                    ),
                  )
                else if (isImporting)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: importProgress,
                      strokeWidth: 2,
                    ),
                  )
                else
                  TextButton(
                    onPressed: pack.emojiSlugs.isEmpty ? null : onImport,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Import'),
                  ),
              ],
            ),
            // Description
            if (pack.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pack.description,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Emoji preview strip
            if (pack.emojiSlugs.length > 1) ...[
              const SizedBox(height: 10),
              _EmojiPreviewStrip(slugs: pack.emojiSlugs),
            ],
            // Progress bar
            if (isImporting) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: importProgress),
              const SizedBox(height: 2),
              Text(
                'Uploading… ${((importProgress ?? 0) * 100).toInt()}%',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Scrollable preview strip ─────────────────────────────────────

class _EmojiPreviewStrip extends StatelessWidget {
  const _EmojiPreviewStrip({required this.slugs});
  final List<String> slugs;

  static const _maxPreview = 12;
  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final preview = slugs.take(_maxPreview).toList();
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: preview.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            'https://cdn3.emoji.gg/emojis/${preview[i]}.png',
            width: _size,
            height: _size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Container(
              width: _size,
              height: _size,
              color: cs.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image_outlined,
                size: 20,
                color: cs.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pack thumbnail — first emoji in the pack ─────────────────────

class _PackThumbnail extends StatelessWidget {
  const _PackThumbnail({required this.pack});
  final EmojiGgPack pack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstSlug = pack.emojiSlugs.isNotEmpty ? pack.emojiSlugs.first : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        color: cs.secondaryContainer,
        child: firstSlug != null
            ? Image.network(
                'https://cdn3.emoji.gg/emojis/$firstSlug.png',
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.emoji_emotions_outlined,
                  color: cs.onSecondaryContainer,
                ),
              )
            : Icon(
                Icons.emoji_emotions_outlined,
                color: cs.onSecondaryContainer,
              ),
      ),
    );
  }
}
