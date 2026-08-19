import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';

class OutboxRepository extends ChangeNotifier {
  OutboxRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.outbox.addListener(_onOutboxChanged);
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.outbox.removeListener(_onOutboxChanged);
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.outbox.addListener(_onOutboxChanged);
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onOutboxChanged() {
    if (!_disposed) notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  OutboxService get outbox => _matrix.outbox;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.outbox.removeListener(_onOutboxChanged);
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}
