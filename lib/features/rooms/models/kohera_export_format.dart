import 'package:flutter/foundation.dart';

// ── KoheraExportFormat ────────────────────────────────────────

/// Output format for chat history export.
enum KoheraExportFormat {
  /// Machine-readable, one JSON document.
  json,

  /// Human-readable, styled HTML document.
  html,

  /// Plain text, one line per message.
  plaintext;

  /// File extension (without dot) for the exported artifact.
  String get extension => switch (this) {
        json => 'json',
        html => 'html',
        plaintext => 'txt',
      };

  /// Human-readable label for the export dialog.
  String get label => switch (this) {
        json => 'JSON',
        html => 'HTML',
        plaintext => 'Plaintext',
      };
}

// ── KoheraExportOptions ───────────────────────────────────────

/// User-selected export configuration. SDK-free.
@immutable
class KoheraExportOptions {
  const KoheraExportOptions({
    this.format = KoheraExportFormat.json,
    this.start,
    this.end,
    this.includeMedia = false,
  });

  /// Output format.
  final KoheraExportFormat format;

  /// Inclusive lower bound on event `origin_server_ts`, or `null` for no bound.
  final DateTime? start;

  /// Inclusive upper bound on event `origin_server_ts`, or `null` for no bound.
  final DateTime? end;

  /// When true, media events include their mxc URL, filename, and MIME type as
  /// references (no bytes are downloaded).
  final bool includeMedia;

  /// Whether a date range filter is active.
  bool get hasRange => start != null || end != null;

  /// Returns true if [ts] falls within the configured range.
  bool inRange(DateTime ts) {
    if (start != null && ts.isBefore(start!)) return false;
    if (end != null && ts.isAfter(end!)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraExportOptions &&
          format == other.format &&
          start == other.start &&
          end == other.end &&
          includeMedia == other.includeMedia;

  @override
  int get hashCode =>
      Object.hash(format, start, end, includeMedia);
}

// ── KoheraExportedMessage ─────────────────────────────────────

/// A single exported message, SDK-free. Built at the conversion boundary
/// from an SDK `Event`.
@immutable
class KoheraExportedMessage {
  const KoheraExportedMessage({
    required this.eventId,
    required this.senderId,
    required this.senderDisplayname,
    required this.timestamp,
    required this.messageType,
    required this.body,
    this.formattedBody,
    this.mediaUrl,
    this.mediaFileName,
    this.mediaMimetype,
  });

  final String eventId;
  final String senderId;
  final String senderDisplayname;
  final DateTime timestamp;
  final String messageType;
  final String body;
  final String? formattedBody;
  final String? mediaUrl;
  final String? mediaFileName;
  final String? mediaMimetype;

  /// Whether this event carries a media attachment (image/video/audio/file).
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraExportedMessage && eventId == other.eventId;

  @override
  int get hashCode => eventId.hashCode;
}
