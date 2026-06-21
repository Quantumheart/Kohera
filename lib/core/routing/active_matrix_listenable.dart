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
  MatrixService? _attached;

  void _onManagerChanged() {
    final next = _manager.activeService;
    if (!identical(next, _attached)) {
      _detach();
      _attach(next);
    }
    notifyListeners();
  }

  void _attach(MatrixService service) {
    service.addListener(notifyListeners);
    service.chatBackup.addListener(notifyListeners);
    _attached = service;
  }

  void _detach() {
    final prev = _attached;
    if (prev == null) return;
    prev.removeListener(notifyListeners);
    prev.chatBackup.removeListener(notifyListeners);
    _attached = null;
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _detach();
    super.dispose();
  }
}
