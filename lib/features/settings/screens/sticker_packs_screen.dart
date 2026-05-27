import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class StickerPacksScreen extends StatelessWidget {
  const StickerPacksScreen({super.key});

  static const _kPersonalPackId = 'im.ponies.user_emotes';

  @override
  Widget build(BuildContext context) {
    final client = context.read<MatrixService>().client;

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
          final accountPacks = service.accountPacks;
          final availablePacks = service.availableRoomPacks();

          final personalPack = accountPacks
              .where((p) => p.id == _kPersonalPackId)
              .firstOrNull;
          final subscribedPacks = accountPacks
              .where((p) => p.id != _kPersonalPackId)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── My Packs ──────────────────────────────────────
              _SectionLabel(
                label: 'MY PACKS',
                trailing: subscribedPacks.isEmpty && personalPack == null
                    ? null
                    : Text(
                        '${accountPacks.length} pack${accountPacks.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
              ),

              if (accountPacks.isEmpty)
                const _EmptyState(
                  icon: Icons.emoji_emotions_outlined,
                  message: 'No packs added yet.\nBrowse available packs below.',
                )
              else
                Card(
                  child: Column(
                    children: [
                      if (personalPack != null) ...[
                        _PackTile(
                          pack: personalPack,
                          client: client,
                          trailing: Tooltip(
                            message: 'Personal pack — cannot be removed',
                            child: Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                        if (subscribedPacks.isNotEmpty)
                          const Divider(height: 1, indent: 56),
                      ],
                      if (subscribedPacks.isNotEmpty)
                        _ReorderablePackList(
                          packs: subscribedPacks,
                          client: client,
                          service: service,
                          personalPackPresent: personalPack != null,
                        ),
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
                          client: client,
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
    required this.client,
    required this.service,
    required this.personalPackPresent,
  });

  final List<StickerPack> packs;
  final Client client;
  final StickerPackService service;
  final bool personalPackPresent;

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
            if (index > 0 || personalPackPresent)
              const Divider(height: 1, indent: 56),
            _PackTile(
              pack: pack,
              client: client,
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
    required this.client,
    this.leading,
    this.trailing,
  });

  final StickerPack pack;
  final Client client;
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
                _PackAvatar(pack: pack, client: client),
              ],
            )
          : _PackAvatar(pack: pack, client: client),
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
  const _PackAvatar({required this.pack, required this.client});

  final StickerPack pack;
  final Client client;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (pack.avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: MxcImage(
          mxcUrl: pack.avatarUrl.toString(),
          client: client,
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
          if (trailing != null) trailing!,
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
