import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';

class StickerPackRepository extends ChangeNotifier {
  StickerPackRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.stickerPacks.addListener(_onStickerPacksChanged);
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.stickerPacks.removeListener(_onStickerPacksChanged);
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.stickerPacks.addListener(_onStickerPacksChanged);
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onStickerPacksChanged() {
    if (!_disposed) notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  StickerPackService get stickerPacks => _matrix.stickerPacks;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.stickerPacks.removeListener(_onStickerPacksChanged);
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}
