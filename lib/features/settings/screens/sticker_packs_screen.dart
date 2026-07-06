import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/shared/models/kohera_sticker_pack.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:provider/provider.dart';

class StickerPacksScreen extends StatelessWidget {
  const StickerPacksScreen({super.key});

  static const _kPersonalPackId = 'im.ponies.user_emotes';

  @override
  Widget build(BuildContext context) {
    final mediaResolver = context.read<MatrixService>().mediaResolver;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(Routes.settings),
        ),
        title: const Text('Sticker & emoji packs'),
      ),
      body: Consumer<StickerPackService>(
        builder: (context, service, _) {
          final accountPacks = service.koheraAccountPacks;
          final availablePacks = service.koheraAvailableRoomPacks();

          final personalPack = accountPacks.where((p) => p.id == _kPersonalPackId).firstOrNull;
          final importedPacks = accountPacks.where((p) => p.id.startsWith('emojigg_')).toList();
          final subscribedPacks = accountPacks
              .where(
                (p) => p.id != _kPersonalPackId && !p.id.startsWith('emojigg_'),
              )
              .toList();
          final openMojiPack = service.koheraOpenMojiPack;
          final myPackCount = accountPacks.length + (openMojiPack != null ? 1 : 0);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── My Packs ──────────────────────────────────────
              _SectionLabel(
                label: 'MY PACKS',
                trailing: myPackCount == 0
                    ? null
                    : Text(
                        '$myPackCount pack${myPackCount == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
              ),

              if (accountPacks.isEmpty && openMojiPack == null)
                const _EmptyState(
                  icon: Icons.emoji_emotions_outlined,
                  message: 'No packs added yet.\nBrowse available packs below.',
                )
              else
                Card(
                  child: Column(
                    children: [
                      if (openMojiPack != null)
                        _PackTile(
                          pack: openMojiPack,
                          mediaResolver: mediaResolver,
                          trailing: Tooltip(
                            message: 'Built-in pack — always available',
                            child: Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      if (personalPack != null) ...[
                        if (openMojiPack != null) const Divider(height: 1, indent: 56),
                        _PackTile(
                          pack: personalPack,
                          mediaResolver: mediaResolver,
                          trailing: Tooltip(
                            message: 'Personal pack — cannot be removed',
                            child: Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                      for (var i = 0; i < importedPacks.length; i++) ...[
                        const Divider(height: 1, indent: 56),
                        _PackTile(
                          pack: importedPacks[i],
                          mediaResolver: mediaResolver,
                          trailing: _RemoveButton(
                            onTap: () => service.removeImportedPack(
                              importedPacks[i].id,
                            ),
                          ),
                        ),
                      ],
                      if (subscribedPacks.isNotEmpty) ...[
                        if (openMojiPack != null || personalPack != null || importedPacks.isNotEmpty)
                          const Divider(height: 1, indent: 56),
                        _ReorderablePackList(
                          packs: subscribedPacks,
                          mediaResolver: mediaResolver,
                          service: service,
                          hasLeadingPack: openMojiPack != null || personalPack != null || importedPacks.isNotEmpty,
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // ── Available Packs ───────────────────────────────
              const _SectionLabel(label: 'AVAILABLE PACKS'),

              if (availablePacks.isEmpty)
                _EmptyState(
                  icon: Icons.search_off_rounded,
                  message: availablePacks.isEmpty && accountPacks.isNotEmpty
                      ? 'All available packs have been added.'
                      : 'No packs found in your rooms.\nAsk a room admin to add one.',
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < availablePacks.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        _PackTile(
                          pack: availablePacks[i],
                          mediaResolver: mediaResolver,
                          trailing: _AddButton(
                            onTap: () => service.subscribeToRoomPack(
                              availablePacks[i].id,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // ── Browse online ─────────────────────────────────
              const _SectionLabel(label: 'BROWSE ONLINE'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: const Text('Browse emoji.gg packs'),
                  subtitle: const Text(
                    'Import sticker packs from the emoji.gg library',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushOrGo(Routes.settingsEmojiGgBrowse),
                ),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

// ── Reorderable list for subscribed room packs ──────────────────

class _ReorderablePackList extends StatelessWidget {
  const _ReorderablePackList({
    required this.packs,
    required this.mediaResolver,
    required this.service,
    required this.hasLeadingPack,
  });

  final List<KoheraStickerPack> packs;
  final MediaResolver mediaResolver;
  final StickerPackService service;
  final bool hasLeadingPack;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: packs.length,
      onReorderItem: (oldIndex, newIndex) {
        final reordered = [...packs];
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        unawaited(service.reorderSubscriptions(reordered.map((p) => p.id).toList()));
      },
      itemBuilder: (context, index) {
        final pack = packs[index];
        return Column(
          key: ValueKey(pack.id),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index > 0 || hasLeadingPack) const Divider(height: 1, indent: 56),
            _PackTile(
              pack: pack,
              mediaResolver: mediaResolver,
              leading: ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              trailing: _RemoveButton(
                onTap: () => service.unsubscribeFromRoomPack(pack.id),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Pack tile ───────────────────────────────────────────────────

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.pack,
    required this.mediaResolver,
    this.leading,
    this.trailing,
  });

  final KoheraStickerPack pack;
  final MediaResolver mediaResolver;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final stickerCount = pack.stickers.length;
    final emojiCount = pack.emoji.length;
    final parts = <String>[
      if (stickerCount > 0) '$stickerCount sticker${stickerCount == 1 ? '' : 's'}',
      if (emojiCount > 0) '$emojiCount emoji',
    ];
    final subtitle = parts.isEmpty ? 'Empty pack' : parts.join(', ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: leading != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading!,
                const SizedBox(width: 8),
                _PackAvatar(pack: pack, mediaResolver: mediaResolver),
              ],
            )
          : _PackAvatar(pack: pack, mediaResolver: mediaResolver),
      title: Text(pack.displayName, style: tt.bodyMedium),
      subtitle: Text(
        subtitle,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: trailing,
    );
  }
}

class _PackAvatar extends StatelessWidget {
  const _PackAvatar({required this.pack, required this.mediaResolver});

  final KoheraStickerPack pack;
  final MediaResolver mediaResolver;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (pack.iconUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: MxcImage(
          mxcUrl: pack.iconUrl!,
          mediaResolver: mediaResolver,
          width: 40,
          height: 40,
          fallbackText: pack.displayName,
          fallbackStyle: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.emoji_emotions_outlined,
        color: cs.onSecondaryContainer,
        size: 22,
      ),
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Add'),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.remove_circle_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      onPressed: onTap,
      tooltip: 'Remove pack',
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            message,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
