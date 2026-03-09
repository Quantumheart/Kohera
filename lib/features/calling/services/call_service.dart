import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/features/calling/services/call_controller.dart';
import 'package:lattice/features/calling/services/call_permission_service.dart';

class CallService extends ChangeNotifier {
  CallController? _activeCall;
  String? _activeRoomId;
  String? _activeDisplayName;

  // ── Public getters ────────────────────────────────────────────

  CallController? get activeCall => _activeCall;
  String? get activeRoomId => _activeRoomId;
  String? get activeDisplayName => _activeDisplayName;
  bool get hasActiveCall => _activeCall != null;

  // ── Lifecycle ─────────────────────────────────────────────────

  Future<void> startCall(String roomId, String displayName) async {
    if (_activeCall != null) {
      debugPrint('[Lattice] CallService: ending existing call before starting new one');
      await endCall();
    }

    _activeRoomId = roomId;
    _activeDisplayName = displayName;
    _activeCall = CallController(roomId: roomId, displayName: displayName);
    _activeCall!.addListener(_onControllerChanged);
    notifyListeners();

    final granted = await CallPermissionService.request();
    if (!granted) {
      _activeCall?.endWithError('Camera and microphone permissions are required');
      return;
    }
    await _activeCall?.join();
  }

  Future<void> endCall() async {
    final call = _activeCall;
    if (call == null) return;

    call.removeListener(_onControllerChanged);
    if (call.state != CallState.ended) {
      call.hangUp();
    }
    call.dispose();

    _activeCall = null;
    _activeRoomId = null;
    _activeDisplayName = null;
    notifyListeners();
  }

  void _onControllerChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _activeCall?.removeListener(_onControllerChanged);
    _activeCall?.dispose();
    super.dispose();
  }
}
