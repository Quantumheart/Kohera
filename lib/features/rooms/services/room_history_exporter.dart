import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/models/kohera_room_export.dart';
import 'package:matrix/matrix.dart';

/// Conversion boundary for chat history export.
///
/// Owns the SDK `Room`/`Timeline`, paginates full history, filters by the
/// user's [KoheraExportOptions], and converts SDK [Event]s into SDK-free
/// [KoheraExportedMessage]s. Formatters below the boundary consume the
/// returned [KoheraRoomExport] and never import `package:matrix`.
class RoomHistoryExporter {
  RoomHistoryExporter({required this.matrix});

  final MatrixService matrix;

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
    final room = matrix.client.getRoomById(roomId);
    if (room == null) {
      throw StateError('Room $roomId not found');
    }

    final timeline = await room.getTimeline();
    final seen = <String>{};
    final messages = <KoheraExportedMessage>[];

    void consume() {
      for (final event in timeline.events) {
        if (!seen.add(event.eventId)) continue;
        if (event.type != EventTypes.Message) continue;
        if (!options.inRange(event.originServerTs)) continue;
        messages.add(_convert(room, event, options));
      }
      onProgress?.call(messages.length, null);
    }

    consume();
    while (timeline.canRequestHistory) {
      await timeline.requestHistory(historyCount: 100);
      if (!timeline.canRequestHistory) {
        consume();
        break;
      }
      consume();
    }

    // timeline.events is newest-first; sort chronologically for export.
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return KoheraRoomExport(
      meta: KoheraExportRoomMeta(
        roomId: room.id,
        displayname: room.getLocalizedDisplayname(),
        canonicalAlias: room.canonicalAlias.isEmpty ? null : room.canonicalAlias,
        topic: room.topic,
        exportedAt: DateTime.now().toUtc(),
      ),
      messages: List.unmodifiable(messages),
      options: options,
    );
  }

  KoheraExportedMessage _convert(
    Room room,
    Event event,
    KoheraExportOptions options,
  ) {
    final sender = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
    String? mediaUrl;
    String? mediaFileName;
    String? mediaMimetype;
    if (options.includeMedia && event.hasAttachment) {
      final mxc = event.attachmentMxcUrl;
      mediaUrl = mxc?.toString();
      mediaFileName = event.text.isNotEmpty ? event.text : null;
      mediaMimetype = event.attachmentMimetype.isNotEmpty
          ? event.attachmentMimetype
          : null;
    }
    return KoheraExportedMessage(
      eventId: event.eventId,
      senderId: event.senderId,
      senderDisplayname: sender.calcDisplayname(),
      timestamp: event.originServerTs,
      messageType: event.messageType,
      body: event.body,
      formattedBody:
          event.formattedText.isNotEmpty ? event.formattedText : null,
      mediaUrl: mediaUrl,
      mediaFileName: mediaFileName,
      mediaMimetype: mediaMimetype,
    );
  }
}
