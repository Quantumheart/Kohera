import 'package:flutter/foundation.dart';
import 'package:kohera/data/services/message_indexer_service.dart';

class MessageSearchRepository extends ChangeNotifier {
  MessageSearchRepository({required MessageIndexerService? messageIndexer})
      : _messageIndexer = messageIndexer;

  final MessageIndexerService? _messageIndexer;
  bool _disposed = false;

  MessageIndexerService? get messageIndexer => _messageIndexer;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
