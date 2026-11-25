import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_sync_event.dart';

/// SDK-free view of one sync cycle, scoped to what the notifications
/// feature consumes: joined-room timeline events, invite state, left rooms,
/// and whether any receipt ephemeral data arrived.
@immutable
class KoheraSyncUpdate {
  const KoheraSyncUpdate({
    required this.joinedRoomIds,
    required this.joinedTimelineEvents,
    required this.invitedRoomStates,
    required this.leftRoomIds,
    required this.hasReceiptEphemeral,
  });

  /// All joined room IDs in this sync, with or without timeline events.
  final Set<String> joinedRoomIds;

  /// Timeline events per joined room ID.
  final Map<String, List<KoheraSyncEvent>> joinedTimelineEvents;

  /// Invite-state events per invited room ID.
  final Map<String, List<KoheraSyncEvent>> invitedRoomStates;

  /// Room IDs the user left or declined in this sync.
  final Set<String> leftRoomIds;

  /// Whether any joined room carried an `m.receipt` ephemeral event.
  final bool hasReceiptEphemeral;
}
