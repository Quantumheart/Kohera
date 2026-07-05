import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:matrix/matrix.dart';

/// Loads pinned messages for a room and converts them to
/// [KoheraMessageDisplay] at the SDK boundary.
class PinnedMessagesLoader {
  const PinnedMessagesLoader._();

  /// Loads all pinned events for [roomId] and returns them as
  /// [KoheraMessageDisplay] models, or `null` if the room is not found.
  static Future<List<KoheraMessageDisplay>?> load(
    MatrixService matrix,
    String roomId,
  ) async {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) return null;

    final ids = room.pinnedEventIds;
    final results = await Future.wait(
      ids.map((id) async {
        try {
          return await room.getEventById(id);
        } catch (e) {
          debugPrint('[Kohera] Failed to load pinned event $id: $e');
          return null;
        }
      }),
    );

    final events = results.whereType<Event>().toList();
    const resolver = MessageDisplayResolver();
    return events.map((e) => resolver(e)).toList();
  }

  /// Returns whether the current user can pin/unpin messages in [roomId].
  static bool canPin(MatrixService matrix, String roomId) {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) return false;
    return room.canChangeStateEvent('m.room.pinned_events');
  }

  /// Removes [eventId] from the pinned events list for [roomId].
  static Future<void> unpin(
    MatrixService matrix,
    String roomId,
    String eventId,
  ) async {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) return;
    final pinned = List<String>.from(room.pinnedEventIds);
    pinned.remove(eventId);
    await room.setPinnedEvents(pinned);
  }
}
