import 'package:flutter/material.dart';
import 'package:kohera/core/models/openmoji_pack.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/openmoji_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:provider/provider.dart';

class DefaultEmojiPacksScreen extends StatefulWidget {
  const DefaultEmojiPacksScreen({super.key});

  @override
  State<DefaultEmojiPacksScreen> createState() =>
      _DefaultEmojiPacksScreenState();
}

class _DefaultEmojiPacksScreenState extends State<DefaultEmojiPacksScreen> {
  final _openMojiService = OpenMojiService();

  // pack id → 0.0–1.0 while importing; absent when idle or done
  final Map<String, double> _importing = {};
  Set<String> _importedSlugs = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _importedSlugs = context.read<StickerPackService>().importedOpenMojiSlugs;
  }

  @override
  void dispose() {
    _openMojiService.dispose();
    super.dispose();
  }

  Future<void> _importPack(OpenMojiPack pack) async {
    setState(() => _importing[pack.id] = 0.0);

    final service = context.read<StickerPackService>();
    var succeeded = 0;

    await for (final progress
        in service.importOpenMojiPack(pack, _openMojiService)) {
      if (!mounted) return;
      setState(() => _importing[pack.id] = progress.fraction);
      if (progress.isComplete) succeeded = progress.done;
    }

    if (!mounted) return;
    setState(() {
      _importing.remove(pack.id);
      _importedSlugs = service.importedOpenMojiSlugs;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded == 0
              ? 'Import failed — no images could be uploaded'
              : 'Added ${pack.name} ($succeeded emoji)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final packs = _openMojiService.packs;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(Routes.settingsStickerPacks),
        ),
        title: const Text('Default emoji packs'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Curated emoji packs from OpenMoji, the open-source emoji '
              'project (CC BY-SA 4.0). Add a pack to use its emoji with '
              ':shortcode: anywhere.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          for (final pack in packs)
            _PackCard(
              pack: pack,
              imageUrlFor: _openMojiService.imageUrl,
              isImported: _importedSlugs.contains(pack.id),
              importProgress: _importing[pack.id],
              onImport: () => _importPack(pack),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Pack card ────────────────────────────────────────────────────

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.imageUrlFor,
    required this.isImported,
    required this.onImport,
    this.importProgress,
  });

  final OpenMojiPack pack;
  final String Function(OpenMojiEmoji) imageUrlFor;
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PackThumbnail(url: imageUrlFor(pack.emojis.first)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pack.name, style: tt.titleSmall),
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
                    onPressed: onImport,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Add'),
                  ),
              ],
            ),
            if (pack.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pack.description,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            _EmojiPreviewStrip(
              urls: pack.emojis.map(imageUrlFor).toList(),
            ),
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
  const _EmojiPreviewStrip({required this.urls});
  final List<String> urls;

  static const _maxPreview = 12;
  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final preview = urls.take(_maxPreview).toList();
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: preview.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            preview[i],
            width: _size,
            height: _size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
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
  const _PackThumbnail({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        color: cs.secondaryContainer,
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.emoji_emotions_outlined,
            color: cs.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
