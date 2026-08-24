import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/emoji_gg_pack.dart';
import 'package:kohera/core/services/emoji_gg_service.dart';
import 'package:kohera/data/models/kohera_sticker_pack.dart';
import 'package:kohera/data/models/sticker_pack.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/sticker_pack_service.dart';
import 'package:matrix/matrix.dart';

export 'package:kohera/data/services/sticker_pack_service.dart'
    show ImportProgress;

/// Owns an account's sticker/emoji packs — personal, imported, subscribed
/// room packs, and the built-in OpenMoji pack. Wraps the [StickerPackService]
/// that tracks account-data state and re-broadcasts its changes;
/// [AccountSession] builds one per account.
class StickerPackRepository extends ChangeNotifier {
  StickerPackRepository({
    required MatrixClientService clientService,
    StickerPackService? serviceOverride,
  }) : _service = serviceOverride ??
            StickerPackService(matrixClientService: clientService) {
    _service.addListener(_onServiceChanged);
  }

  final StickerPackService _service;
  bool _disposed = false;

  void _onServiceChanged() {
    if (!_disposed) notifyListeners();
  }

  // ── Domain-model reads (SDK-free) ─────────────────────────────

  /// Account packs (personal + imported + subscribed) as installed packs.
  List<KoheraStickerPack> get koheraAccountPacks => _service.koheraAccountPacks;

  /// The built-in OpenMoji pack, or null until the catalog has loaded.
  KoheraStickerPack? get koheraOpenMojiPack => _service.koheraOpenMojiPack;

  /// Room/space packs not yet subscribed at account level.
  List<KoheraStickerPack> koheraAvailableRoomPacks() =>
      _service.koheraAvailableRoomPacks();

  /// Slugs of emoji.gg packs already imported.
  Set<String> get importedEmojiGgSlugs => _service.importedEmojiGgSlugs;

  // ── SDK-typed reads (compose bar / settings count) ────────────

  /// Account packs as SDK [StickerPack]s (personal + imported + subscribed).
  List<StickerPack> get accountPacks => _service.accountPacks;

  /// Packs available in [room] (account + room state emotes).
  List<StickerPack> packsForRoom(Room room) => _service.packsForRoom(room);

  // ── Mutations ─────────────────────────────────────────────────

  Future<void> subscribeToRoomPack(String roomId) =>
      _service.subscribeToRoomPack(roomId);

  Future<void> unsubscribeFromRoomPack(String roomId) =>
      _service.unsubscribeFromRoomPack(roomId);

  Future<void> reorderSubscriptions(List<String> orderedIds) =>
      _service.reorderSubscriptions(orderedIds);

  Stream<ImportProgress> importEmojiGgPack(
    EmojiGgPack pack,
    EmojiGgService emojiGgService,
  ) =>
      _service.importEmojiGgPack(pack, emojiGgService);

  Future<void> removeImportedPack(String packId) =>
      _service.removeImportedPack(packId);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    super.dispose();
  }
}
