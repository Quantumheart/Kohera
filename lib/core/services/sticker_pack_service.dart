import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:matrix/matrix.dart';

class StickerPackService extends ChangeNotifier {
  StickerPackService({required Client client}) : _client = client {
    _sub = client.onSync.stream.listen((sync) {
      final relevant =
          sync.accountData?.any(
            (e) => e.type == _kUserEmotesType || e.type == _kSubscriptionsType,
          ) ??
          false;
      if (relevant) notifyListeners();
    });
  }

  static const _kUserEmotesType = 'im.ponies.user_emotes';
  static const _kRoomEmotesType = 'im.ponies.room_emotes';
  static const _kSubscriptionsType = 'kohera.sticker_pack_subscriptions';

  final Client _client;
  StreamSubscription<SyncUpdate>? _sub;

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  /// The user's personal pack plus all subscribed room packs.
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

    for (final roomId in _subscribedRoomIds) {
      final room = _client.getRoomById(roomId);
      if (room == null) continue;
      final pack = _packForRoom(room);
      if (pack != null) packs.add(pack);
    }

    return packs;
  }

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

  /// Room/space packs from joined rooms that are not yet subscribed at account level.
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
}
