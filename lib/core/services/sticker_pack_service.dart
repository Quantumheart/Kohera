import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/emoji_gg_pack.dart';
import 'package:kohera/core/models/openmoji_pack.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/services/emoji_gg_service.dart';
import 'package:kohera/core/services/openmoji_service.dart';
import 'package:matrix/matrix.dart';

class ImportProgress {
  const ImportProgress({required this.done, required this.total});
  final int done;
  final int total;
  double get fraction => total == 0 ? 1.0 : done / total;
  bool get isComplete => done >= total;
}

class StickerPackService extends ChangeNotifier {
  StickerPackService({required Client client}) : _client = client {
    _sub = client.onSync.stream.listen((sync) {
      final relevant =
          sync.accountData?.any(
            (e) =>
                e.type == _kUserEmotesType ||
                e.type == _kSubscriptionsType ||
                e.type == _kImportedPacksType,
          ) ??
          false;
      if (relevant) notifyListeners();
    });
  }

  static const _kUserEmotesType = 'im.ponies.user_emotes';
  static const _kRoomEmotesType = 'im.ponies.room_emotes';
  static const _kSubscriptionsType = 'kohera.sticker_pack_subscriptions';
  static const _kImportedPacksType = 'kohera.imported_packs';

  final Client _client;
  StreamSubscription<SyncUpdate>? _sub;

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future.value());
    super.dispose();
  }

  // ── Account packs ────────────────────────────────────────────

  /// Personal pack + imported emoji.gg packs + subscribed room packs.
  List<StickerPack> get accountPacks {
    final packs = <StickerPack>[];

    final userContent = _client.accountData[_kUserEmotesType]?.content;
    if (userContent != null) {
      final pack = StickerPack.fromContent(
        id: _kUserEmotesType,
        content: userContent,
      );
      if (pack != null) packs.add(pack);
    }

    packs.addAll(importedPacks);

    for (final roomId in _subscribedRoomIds) {
      final room = _client.getRoomById(roomId);
      if (room == null) continue;
      final pack = _packForRoom(room);
      if (pack != null) packs.add(pack);
    }

    return packs;
  }

  /// Packs imported from emoji.gg or OpenMoji, stored in account data.
  /// A pack with `usage: 'emoticon'` is exposed as emoji; otherwise stickers.
  List<StickerPack> get importedPacks {
    final content = _client.accountData[_kImportedPacksType]?.content;
    if (content == null) return [];

    final rawPacks =
        (content['packs'] as List?)?.cast<Map<String, Object?>>() ?? [];
    final packs = <StickerPack>[];

    for (final raw in rawPacks) {
      final id = raw['id'] as String?;
      final displayName = raw['display_name'] as String?;
      final rawImages = raw['images'] as Map<String, Object?>?;

      if (id == null || displayName == null || rawImages == null) continue;

      final asEmoji = (raw['usage'] as String?) == 'emoticon';
      final stickers = <PackImage>[];
      final emoji = <PackImage>[];

      for (final entry in rawImages.entries) {
        final imageData = entry.value as Map<String, Object?>?;
        if (imageData == null) continue;

        final urlStr = imageData['url'] as String?;
        if (urlStr == null) continue;
        final url = Uri.tryParse(urlStr);
        if (url == null) continue;

        final image = PackImage(
          shortcode: entry.key,
          url: url,
          body: imageData['body'] as String?,
          isSticker: !asEmoji,
          isEmoji: asEmoji,
        );
        (asEmoji ? emoji : stickers).add(image);
      }

      if (stickers.isEmpty && emoji.isEmpty) continue;

      packs.add(StickerPack(
        id: id,
        displayName: displayName,
        stickers: stickers,
        emoji: emoji,
      ),);
    }

    return packs;
  }

  /// Slugs of emoji.gg packs already imported by the user.
  Set<String> get importedEmojiGgSlugs => _importedSlugsForSource('emojigg');

  /// Ids of OpenMoji default packs already imported by the user.
  Set<String> get importedOpenMojiSlugs => _importedSlugsForSource('openmoji');

  Set<String> _importedSlugsForSource(String source) {
    final content = _client.accountData[_kImportedPacksType]?.content;
    if (content == null) return {};

    final rawPacks =
        (content['packs'] as List?)?.cast<Map<String, Object?>>() ?? [];
    return rawPacks
        .where((p) => p['source'] == source)
        .map((p) => p['source_slug'] as String?)
        .whereType<String>()
        .toSet();
  }

  // ── Room packs ───────────────────────────────────────────────

  /// All packs visible in a room context: account packs + room pack + space packs.
  List<StickerPack> packsForRoom(Room room) {
    final packs = <StickerPack>[...accountPacks];
    final seen = {for (final p in packs) p.id};

    final roomPack = _packForRoom(room);
    if (roomPack != null && seen.add(roomPack.id)) {
      packs.add(roomPack);
    }

    for (final parent in room.spaceParents) {
      final parentId = parent.roomId;
      if (parentId == null) continue;
      final space = _client.getRoomById(parentId);
      if (space == null) continue;
      final spacePack = _packForRoom(space);
      if (spacePack != null && seen.add(spacePack.id)) {
        packs.add(spacePack);
      }
    }

    return packs;
  }

  /// Room/space packs from joined rooms not yet subscribed at account level.
  List<StickerPack> availableRoomPacks() {
    final subscribedIds = {_kUserEmotesType, ..._subscribedRoomIds};
    final packs = <StickerPack>[];
    for (final room in _client.rooms) {
      if (subscribedIds.contains(room.id)) continue;
      final pack = _packForRoom(room);
      if (pack != null) packs.add(pack);
    }
    return packs;
  }

  // ── Subscriptions ─────────────────────────────────────────────

  Future<void> subscribeToRoomPack(String roomId) async {
    final ids = [..._subscribedRoomIds];
    if (ids.contains(roomId)) return;
    await _writeSubscriptions([...ids, roomId]);
  }

  Future<void> unsubscribeFromRoomPack(String roomId) async {
    final ids = _subscribedRoomIds.where((id) => id != roomId).toList();
    await _writeSubscriptions(ids);
  }

  Future<void> reorderSubscriptions(List<String> orderedIds) async {
    await _writeSubscriptions(orderedIds);
  }

  // ── Emoji.gg import ───────────────────────────────────────────

  /// Downloads each emoji from [pack] via [emojiGgService], uploads them to
  /// the user's homeserver, and saves the pack to account data.
  ///
  /// Yields [ImportProgress] after each image. The final event has
  /// [ImportProgress.isComplete] == true.
  Stream<ImportProgress> importEmojiGgPack(
    EmojiGgPack pack,
    EmojiGgService emojiGgService,
  ) async* {
    final emojis = pack.emojis;
    final total = emojis.length;
    final images = <String, Object?>{};
    var done = 0;

    for (final emoji in emojis) {
      try {
        final bytes = await emojiGgService.downloadImage(emoji.imageUrl);
        final mxcUri = await _client.uploadContent(
          bytes,
          filename: '${emoji.slug}.png',
          contentType: 'image/png',
        );
        images[emoji.shortcode] = {
          'url': mxcUri.toString(),
          'body': emoji.title,
        };
      } catch (e) {
        debugPrint('[Kohera] Failed to import ${emoji.slug}: $e');
      }
      done++;
      yield ImportProgress(done: done, total: total);
    }

    if (images.isNotEmpty) {
      await _writeImportedPack(pack, images);
    }
  }

  // ── OpenMoji default packs ────────────────────────────────────

  /// Downloads each emoji from the OpenMoji [pack] via [openMojiService],
  /// uploads them to the user's homeserver, and saves the pack to account
  /// data as an emoji (emoticon) pack.
  ///
  /// Yields [ImportProgress] after each image. The final event has
  /// [ImportProgress.isComplete] == true.
  Stream<ImportProgress> importOpenMojiPack(
    OpenMojiPack pack,
    OpenMojiService openMojiService,
  ) async* {
    final emojis = pack.emojis;
    final total = emojis.length;
    final images = <String, Object?>{};
    var done = 0;

    for (final emoji in emojis) {
      try {
        final bytes =
            await openMojiService.downloadImage(openMojiService.imageUrl(emoji));
        final mxcUri = await _client.uploadContent(
          bytes,
          filename: '${emoji.hexcode}.png',
          contentType: 'image/png',
        );
        images[emoji.shortcode] = {
          'url': mxcUri.toString(),
          'body': emoji.annotation,
        };
      } catch (e) {
        debugPrint('[Kohera] Failed to import OpenMoji ${emoji.hexcode}: $e');
      }
      done++;
      yield ImportProgress(done: done, total: total);
    }

    if (images.isNotEmpty) {
      await _writeImportedOpenMojiPack(pack, images);
    }
  }

  Future<void> removeImportedPack(String packId) async {
    final content =
        _client.accountData[_kImportedPacksType]?.content ?? {};
    final rawPacks =
        (content['packs'] as List?)?.cast<Map<String, Object?>>() ?? [];
    final updated = rawPacks.where((p) => p['id'] != packId).toList();
    await _client.setAccountData(
      _client.userID!,
      _kImportedPacksType,
      {'packs': updated},
    );
  }

  // ── Private helpers ──────────────────────────────────────────

  List<String> get _subscribedRoomIds =>
      _client.accountData[_kSubscriptionsType]
          ?.content
          .tryGetList<String>('room_ids') ??
      [];

  StickerPack? _packForRoom(Room room) {
    final state = room.getState(_kRoomEmotesType);
    if (state == null) return null;
    return StickerPack.fromContent(id: room.id, content: state.content);
  }

  Future<void> _writeSubscriptions(List<String> roomIds) async {
    await _client.setAccountData(
      _client.userID!,
      _kSubscriptionsType,
      {'room_ids': roomIds},
    );
  }

  Future<void> _writeImportedPack(
    EmojiGgPack pack,
    Map<String, Object?> images,
  ) async {
    final content =
        _client.accountData[_kImportedPacksType]?.content ?? {};
    final rawPacks =
        (content['packs'] as List?)?.cast<Map<String, Object?>>() ?? [];

    // Replace existing entry for the same source pack, if any.
    final updated = rawPacks
        .where((p) => p['source_id'] != pack.id)
        .toList()
      ..add({
        'id': 'emojigg_${pack.id}',
        'display_name': pack.name,
        'source': 'emojigg',
        'source_id': pack.id,
        'source_slug': pack.slug,
        'images': images,
      });

    await _client.setAccountData(
      _client.userID!,
      _kImportedPacksType,
      {'packs': updated},
    );
  }

  Future<void> _writeImportedOpenMojiPack(
    OpenMojiPack pack,
    Map<String, Object?> images,
  ) async {
    final content =
        _client.accountData[_kImportedPacksType]?.content ?? {};
    final rawPacks =
        (content['packs'] as List?)?.cast<Map<String, Object?>>() ?? [];

    final id = 'openmoji_${pack.id}';
    final updated = rawPacks.where((p) => p['id'] != id).toList()
      ..add({
        'id': id,
        'display_name': pack.name,
        'source': 'openmoji',
        'source_slug': pack.id,
        'usage': 'emoticon',
        'images': images,
      });

    await _client.setAccountData(
      _client.userID!,
      _kImportedPacksType,
      {'packs': updated},
    );
  }
}
