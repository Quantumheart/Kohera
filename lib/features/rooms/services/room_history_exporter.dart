import 'package:kohera/data/models/kohera_room_history.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/models/kohera_room_export.dart';

/// Conversion boundary for chat history export.
///
/// Paginates the full history through [RoomRepository.roomHistory],
/// filters by the user's [KoheraExportOptions], and converts domain
/// [KoheraHistoryEvent]s into [KoheraExportedMessage]s. Formatters below
/// the boundary consume the returned [KoheraRoomExport] and never import
/// `package:matrix`.
class RoomHistoryExporter {
  RoomHistoryExporter({required this.rooms});

  final RoomRepository rooms;

  /// Fetches and converts the full message history of [roomId].
  ///
  /// [onProgress] receives the running count of collected messages and a
  /// best-effort total (currently `null` — Matrix does not advertise a
  /// reliable total ahead of pagination).
  Future<KoheraRoomExport> export({
    required String roomId,
    required KoheraExportOptions options,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    final history = await rooms.roomHistory(
      roomId,
      onProgress: (loaded) => onProgress?.call(loaded, null),
    );

    final messages = [
      for (final event in history.events)
        if (options.inRange(event.timestamp)) _convert(event, options),
    ];

    // history.events is newest-first; sort chronologically for export.
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return KoheraRoomExport(
      meta: KoheraExportRoomMeta(
        roomId: history.roomId,
        displayname: history.displayname,
        canonicalAlias: history.canonicalAlias,
        topic: history.topic,
        exportedAt: DateTime.now().toUtc(),
      ),
      messages: List.unmodifiable(messages),
      options: options,
    );
  }

  KoheraExportedMessage _convert(
    KoheraHistoryEvent event,
    KoheraExportOptions options,
  ) {
    final includeMedia = options.includeMedia && event.hasAttachment;
    return KoheraExportedMessage(
      eventId: event.eventId,
      senderId: event.senderId,
      senderDisplayname: event.senderDisplayname,
      timestamp: event.timestamp,
      messageType: event.messageType,
      body: event.body,
      formattedBody: event.formattedBody,
      mediaUrl: includeMedia ? event.mediaUrl : null,
      mediaFileName: includeMedia ? event.mediaFileName : null,
      mediaMimetype: includeMedia ? event.mediaMimetype : null,
    );
  }
}
