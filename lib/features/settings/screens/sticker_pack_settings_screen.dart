import 'package:flutter/material.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:kohera/shared/widgets/section_header.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class StickerPackSettingsScreen extends StatelessWidget {
  const StickerPackSettingsScreen({super.key});

  static const _kUserEmotesType = 'im.ponies.user_emotes';

  String _itemCount(StickerPack pack) {
    final parts = <String>[];
    if (pack.emoji.isNotEmpty) {
      parts.add('${pack.emoji.length} emoji');
    }
    if (pack.stickers.isNotEmpty) {
      parts.add('${pack.stickers.length} stickers');
    }
    if (parts.isEmpty) return 'Empty';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<StickerPackService>();
    final client = context.read<MatrixService>().client;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final accountPacks = service.accountPacks;
    StickerPack? ownPack;
    for (final pack in accountPacks) {
      if (pack.id == _kUserEmotesType) {
        ownPack = pack;
        break;
      }
    }
    final roomPacks =
        accountPacks.where((p) => p.id != _kUserEmotesType).toList();
    final available = service.availableRoomPacks();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(Routes.settings),
        ),
        title: const Text('Stickers & Emoji'),
      ),
      body: accountPacks.isEmpty && available.isEmpty
          ? _EmptyState(cs: cs, tt: tt)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader(label: 'YOUR PACKS'),
                if (accountPacks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 16),
                    child: Text(
                      'No packs added yet',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        if (ownPack != null)
                          _PackTile(
                            pack: ownPack,
                            client: client,
                            subtitle: _itemCount(ownPack),
                          ),
                        if (ownPack != null && roomPacks.isNotEmpty)
                          const Divider(height: 1, indent: 56),
                        if (roomPacks.isNotEmpty)
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: roomPacks.length,
                            onReorder: (oldIndex, newIndex) {
                              final ids =
                                  roomPacks.map((p) => p.id).toList();
                              if (newIndex > oldIndex) newIndex -= 1;
                              final moved = ids.removeAt(oldIndex);
                              ids.insert(newIndex, moved);
                              service.reorderSubscriptions(ids);
                            },
                            itemBuilder: (context, index) {
                              final pack = roomPacks[index];
                              return _PackTile(
                                key: ValueKey(pack.id),
                                pack: pack,
                                client: client,
                                subtitle: _itemCount(pack),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      tooltip: 'Remove pack',
                                      onPressed: () =>
                                          service.unsubscribeFromRoomPack(
                                        pack.id,
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_handle,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                if (available.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const SectionHeader(label: 'AVAILABLE PACKS'),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Packs from rooms and spaces you have joined',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < available.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 56),
                          _PackTile(
                            pack: available[i],
                            client: client,
                            subtitle: _itemCount(available[i]),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Add pack',
                              onPressed: () => service
                                  .subscribeToRoomPack(available[i].id),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.pack,
    required this.client,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final StickerPack pack;
  final Client client;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = pack.avatarUrl;
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: avatarUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MxcImage(
                  mxcUrl: avatarUrl.toString(),
                  client: client,
                  fallbackText: pack.displayName.isNotEmpty
                      ? pack.displayName[0].toUpperCase()
                      : '?',
                  fallbackStyle: TextStyle(color: cs.onSurfaceVariant),
                  width: 40,
                  height: 40,
                ),
              )
            : Icon(Icons.emoji_emotions_outlined, color: cs.onSurfaceVariant),
      ),
      title: Text(pack.displayName),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.emoji_emotions_outlined,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No sticker or emoji packs',
              style: tt.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Packs from rooms and spaces you join will appear here.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
