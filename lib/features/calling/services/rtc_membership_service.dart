import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:matrix/matrix.dart';

class RtcMembershipService {
  RtcMembershipService({required Client client}) : _client = client;

  Client _client;

  void updateClient(Client client) => _client = client;

  Timer? _membershipRenewalTimer;

  String get membershipStateKey =>
      '_${_client.userID!}_${_client.deviceID!}_m.call';

  Map<String, dynamic> makeMembershipContent(
    String livekitServiceUrl,
    String livekitAlias,
  ) => {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': _client.deviceID,
    'expires': membershipExpiresMs,
    'focus_active': {
      'type': 'livekit',
      'focus_selection': 'oldest_membership',
    },
    'foci_preferred': [
      {
        'type': 'livekit',
        'livekit_service_url': livekitServiceUrl,
        'livekit_alias': livekitAlias,
      },
    ],
  };

  Future<void> sendMembershipEvent(
    String roomId,
    String livekitAlias, {
    required String livekitServiceUrl,
  }) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      makeMembershipContent(livekitServiceUrl, livekitAlias),
    );
  }

  Future<void> removeMembershipEvent(String roomId) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      {},
    );
  }

  void startMembershipRenewal(
    String roomId,
    String livekitAlias, {
    required String livekitServiceUrl,
  }) {
    cancelMembershipRenewal();
    _membershipRenewalTimer = Timer.periodic(
      membershipRenewalInterval,
      (_) => sendMembershipEvent(
        roomId,
        livekitAlias,
        livekitServiceUrl: livekitServiceUrl,
      ).catchError(
        (Object e) => debugPrint('[Lattice] Failed to renew membership: $e'),
      ),
    );
  }

  void cancelMembershipRenewal() {
    _membershipRenewalTimer?.cancel();
    _membershipRenewalTimer = null;
  }
}
