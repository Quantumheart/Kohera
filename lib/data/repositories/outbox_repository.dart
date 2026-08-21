import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';

class OutboxRepository extends ChangeNotifier {
  OutboxRepository({required OutboxService outbox}) : _outbox = outbox {
    _outbox.addListener(_onOutboxChanged);
  }

  final OutboxService _outbox;
  bool _disposed = false;

  void _onOutboxChanged() {
    if (!_disposed) notifyListeners();
  }

  OutboxService get outbox => _outbox;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _outbox.removeListener(_onOutboxChanged);
    super.dispose();
  }
}
