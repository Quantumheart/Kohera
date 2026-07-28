import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One staged inbound share handed off from the iOS Share Extension.
///
/// The extension stages file payloads into the App-Group container and writes
/// a single `incomingShare` JSON record carrying the room the user picked
/// plus the text/files to send; the main app reads it on wake (via the
/// `koherashare://` URL scheme redirect) and sends it to [roomId] through the
/// Matrix SDK, then navigates to the room. There is no queue: the app is
/// foregrounded immediately by the redirect, so a single record suffices.
@immutable
class IncomingShareFile {
  const IncomingShareFile({
    required this.filePath,
    required this.name,
    this.mimeType,
  });

  /// Absolute path inside the App-Group container.
  final String filePath;
  final String name;
  final String? mimeType;

  Map<String, Object?> toJson() => {
        'filePath': filePath,
        'name': name,
        if (mimeType != null) 'mimeType': mimeType,
      };

  factory IncomingShareFile.fromJson(Map<String, Object?> json) =>
      IncomingShareFile(
        filePath: json['filePath']! as String,
        name: (json['name'] as String?) ?? json['filePath']! as String,
        mimeType: json['mimeType'] as String?,
      );
}

@immutable
class IncomingShare {
  const IncomingShare({
    required this.roomId,
    this.text,
    this.files = const [],
  });

  /// Room the user picked in the extension.
  final String roomId;

  /// Optional message body (text/url attachments folded in).
  final String? text;

  /// Staged file payloads to send as `m.room.message` file events.
  final List<IncomingShareFile> files;

  bool get isEmpty => (text == null || text!.isEmpty) && files.isEmpty;

  Map<String, Object?> toJson() => {
        'roomId': roomId,
        if (text != null && text!.isNotEmpty) 'text': text,
        if (files.isNotEmpty)
          'files': files.map((f) => f.toJson()).toList(),
      };

  factory IncomingShare.fromJson(Map<String, Object?> json) => IncomingShare(
        roomId: json['roomId']! as String,
        text: json['text'] as String?,
        files: ((json['files'] as List?) ?? const [])
            .whereType<Map<String, Object?>>()
            .map(IncomingShareFile.fromJson)
            .toList(growable: false),
      );

  String encode() => jsonEncode(toJson());

  factory IncomingShare.decode(String raw) =>
      IncomingShare.fromJson(jsonDecode(raw) as Map<String, Object?>);
}
