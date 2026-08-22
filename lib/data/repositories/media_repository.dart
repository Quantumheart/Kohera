import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/data/services/media_resolver.dart';

class MediaRepository extends ChangeNotifier {
  MediaRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  AvatarResolver get avatarResolver => _matrix.avatarResolver;
  MediaResolver get mediaResolver => _matrix.mediaResolver;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}
