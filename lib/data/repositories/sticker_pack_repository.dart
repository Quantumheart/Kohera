import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';

class StickerPackRepository extends ChangeNotifier {
  StickerPackRepository({required StickerPackService stickerPacks})
      : _stickerPacks = stickerPacks {
    _stickerPacks.addListener(_onStickerPacksChanged);
  }

  final StickerPackService _stickerPacks;
  bool _disposed = false;

  void _onStickerPacksChanged() {
    if (!_disposed) notifyListeners();
  }

  StickerPackService get stickerPacks => _stickerPacks;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stickerPacks.removeListener(_onStickerPacksChanged);
    super.dispose();
  }
}
