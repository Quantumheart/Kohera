import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sub_services/outbox_connectivity.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:kohera/data/services/matrix_client_service.dart';

export 'package:kohera/core/services/sub_services/outbox_service.dart'
    show OutboxEntryView;

/// Tracks stuck (retrying / failed) outgoing messages so bubbles can show
/// send status. Owns the [OutboxService] that runs the retry loop and
/// re-broadcasts its changes; [AccountSession] builds one per account.
class OutboxRepository extends ChangeNotifier {
  OutboxRepository({
    required MatrixClientService clientService,
    required String clientName,
    OutboxService? outboxOverride,
  }) : _outbox = outboxOverride ??
            OutboxService(
              matrixClientService: clientService,
              clientName: clientName,
              connectivity: RealOutboxConnectivity(),
            ) {
    _outbox.addListener(_onOutboxChanged);
  }

  final OutboxService _outbox;
  bool _disposed = false;

  /// The currently-tracked outbox entries, keyed by transaction id.
  Map<String, OutboxEntryView> get entries => _outbox.entries;

  /// Starts the retry loop (on login). Safe to call repeatedly.
  Future<void> start() => _outbox.start();

  void _onOutboxChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _outbox.removeListener(_onOutboxChanged);
    _outbox.dispose();
    super.dispose();
  }
}
