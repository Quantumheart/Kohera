import 'package:kohera/data/models/kohera_event_types.dart';
import 'package:kohera/data/models/kohera_sync_event.dart';
import 'package:kohera/data/models/kohera_sync_update.dart';
import 'package:matrix/matrix.dart';

/// Conversion boundary: SDK [SyncUpdate] to [KoheraSyncUpdate].
class SyncUpdateResolver {
  const SyncUpdateResolver();

  KoheraSyncUpdate convert(SyncUpdate update) {
    final rooms = update.rooms;

    final joined = <String, List<KoheraSyncEvent>>{};
    var hasReceiptEphemeral = false;
    final joinUpdates = rooms?.join;
    if (joinUpdates != null) {
      for (final entry in joinUpdates.entries) {
        final events = entry.value.timeline?.events;
        if (events != null && events.isNotEmpty) {
          joined[entry.key] = [for (final e in events) convertEvent(e)];
        }
        final ephemeral = entry.value.ephemeral;
        if (ephemeral != null &&
            ephemeral.any((e) => e.type == KoheraEventTypes.receipt)) {
          hasReceiptEphemeral = true;
        }
      }
    }

    final invited = <String, List<KoheraSyncEvent>>{};
    final inviteUpdates = rooms?.invite;
    if (inviteUpdates != null) {
      for (final entry in inviteUpdates.entries) {
        final state = entry.value.inviteState;
        invited[entry.key] =
            state == null ? [] : [for (final e in state) convertStripped(e)];
      }
    }

    return KoheraSyncUpdate(
      joinedRoomIds: Set.unmodifiable(joinUpdates?.keys ?? const <String>{}),
      joinedTimelineEvents: joined,
      invitedRoomStates: invited,
      leftRoomIds: Set.unmodifiable(rooms?.leave?.keys ?? const <String>{}),
      hasReceiptEphemeral: hasReceiptEphemeral,
    );
  }

  /// Converts an SDK [MatrixEvent] to its domain view.
  static KoheraSyncEvent convertEvent(MatrixEvent event) => KoheraSyncEvent(
        type: event.type,
        senderId: event.senderId,
        content: event.content,
        eventId: event.eventId,
        originServerTs: event.originServerTs,
      );

  /// Converts an SDK [StrippedStateEvent] (invite state) to its domain view.
  static KoheraSyncEvent convertStripped(StrippedStateEvent event) =>
      KoheraSyncEvent(
        type: event.type,
        senderId: event.senderId,
        content: event.content,
        stateKey: event.stateKey,
      );
}
