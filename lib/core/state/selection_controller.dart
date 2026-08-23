import 'package:flutter/foundation.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

/// App-wide navigation selection state: the active room and the set of
/// selected spaces. This is presentation state (View/ViewModel tier); it
/// depends only on the data-layer client boundary to resolve the selected
/// room by id. One instance per account, built by [AccountSession].
class SelectionController extends ChangeNotifier {
  SelectionController({required MatrixClientService clientService})
      : _clientService = clientService;

  final MatrixClientService _clientService;

  // ── Space multi-select ──────────────────────────────────────
  final Set<String> _selectedSpaceIds = {};
  Set<String> get selectedSpaceIds => Set.unmodifiable(_selectedSpaceIds);

  void selectSpace(String? spaceId) {
    if (spaceId == null) {
      _selectedSpaceIds.clear();
    } else if (_selectedSpaceIds.length == 1 &&
        _selectedSpaceIds.contains(spaceId)) {
      _selectedSpaceIds.clear();
    } else {
      _selectedSpaceIds
        ..clear()
        ..add(spaceId);
    }
    notifyListeners();
  }

  void toggleSpaceSelection(String spaceId) {
    if (!_selectedSpaceIds.remove(spaceId)) {
      _selectedSpaceIds.add(spaceId);
    }
    notifyListeners();
  }

  void clearSpaceSelection() {
    _selectedSpaceIds.clear();
    notifyListeners();
  }

  // ── Room selection ──────────────────────────────────────────
  String? _selectedRoomId;
  String? get selectedRoomId => _selectedRoomId;

  Room? get selectedRoom => _selectedRoomId != null
      ? _clientService.client.getRoomById(_selectedRoomId!)
      : null;

  void selectRoom(String? roomId) {
    _selectedRoomId = roomId;
    notifyListeners();
  }

  void resetSelection() {
    _selectedSpaceIds.clear();
    _selectedRoomId = null;
  }
}
