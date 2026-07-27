import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One staged inbound share awaiting a Matrix send from the main app.
///
/// Written by the iOS Share Extension into the App-Group shared store and
/// drained by the main app on foreground/launch. The Matrix SDK never runs
/// inside the extension, so this record only carries enough metadata for
/// the main app to resolve the target [Room] and replay the send.
@immutable
class PendingShare {
  const PendingShare({
    required this.id,
    required this.targetRoomId,
    required this.accountId,
    required this.kind,
    required this.createdAt,
    this.text,
    this.filePath,
    this.mimeType,
    this.originalFileName,
  });

  /// Stable unique id; used for idempotent drain dedupe.
  final String id;

  /// Room the user picked in the extension's room picker.
  final String targetRoomId;

  /// Client name of the account that owns [targetRoomId]; matches the
  /// `clientName` used by `MatrixService` / `ClientManager`.
  final String accountId;

  /// Payload shape. Text shares carry [text]; file shares carry [filePath].
  final PendingShareKind kind;

  final String? text;

  /// Absolute path inside the App-Group container for staged file payloads.
  final String? filePath;

  final String? mimeType;
  final String? originalFileName;

  /// Epoch milliseconds when the extension staged this share.
  final int createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'targetRoomId': targetRoomId,
        'accountId': accountId,
        'kind': kind.name,
        if (text != null) 'text': text,
        if (filePath != null) 'filePath': filePath,
        if (mimeType != null) 'mimeType': mimeType,
        if (originalFileName != null) 'originalFileName': originalFileName,
        'createdAt': createdAt,
      };

  factory PendingShare.fromJson(Map<String, Object?> json) => PendingShare(
        id: json['id']! as String,
        targetRoomId: json['targetRoomId']! as String,
        accountId: json['accountId']! as String,
        kind: PendingShareKind.values.byName(json['kind']! as String),
        text: json['text'] as String?,
        filePath: json['filePath'] as String?,
        mimeType: json['mimeType'] as String?,
        originalFileName: json['originalFileName'] as String?,
        createdAt: json['createdAt']! as int,
      );

  String encode() => jsonEncode(toJson());

  factory PendingShare.decode(String raw) =>
      PendingShare.fromJson(jsonDecode(raw) as Map<String, Object?>);

  @override
  bool operator ==(Object other) =>
      other is PendingShare && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum PendingShareKind { text, file }
