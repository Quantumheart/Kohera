import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';

/// A [Listenable] that forwards notifications from the currently active
/// [MatrixService] (and its [ChatBackupService]), re-binding automatically
/// when the active account changes. Lets the router use a stable
/// `refreshListenable` across account switches.
class ActiveMatrixListenable extends ChangeNotifier {
  ActiveMatrixListenable(this._manager) {
    _manager.addListener(_onManagerChanged);
    _attach(_manager.activeService);
  }

  final ClientManager _manager;
  MatrixService? _attachedService;

  void _onManagerChanged() {
    final nextService = _manager.activeService;
    if (!identical(nextService, _attachedService)) {
      _detach();
      _attach(nextService);
    }
    notifyListeners();
  }

  void _attach(MatrixService service) {
    service.addListener(notifyListeners);
    service.chatBackup.addListener(notifyListeners);
    _attachedService = service;
  }

  void _detach() {
    final previousService = _attachedService;
    if (previousService == null) return;
    previousService.removeListener(notifyListeners);
    previousService.chatBackup.removeListener(notifyListeners);
    _attachedService = null;
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _detach();
    super.dispose();
  }
}
