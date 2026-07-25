import 'package:flutter/foundation.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';

/// Metadata about the exported room. SDK-free.
@immutable
class KoheraExportRoomMeta {
  const KoheraExportRoomMeta({
    required this.roomId,
    required this.displayname,
    this.canonicalAlias,
    this.topic,
    this.exportedAt,
  });

  final String roomId;
  final String displayname;
  final String? canonicalAlias;
  final String? topic;
  final DateTime? exportedAt;
}

/// Result of a room history export: room metadata + chronological messages.
@immutable
class KoheraRoomExport {
  const KoheraRoomExport({
    required this.meta,
    required this.messages,
    required this.options,
  });

  final KoheraExportRoomMeta meta;
  final List<KoheraExportedMessage> messages;
  final KoheraExportOptions options;
}
