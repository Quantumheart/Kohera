import 'dart:convert';

import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/models/kohera_room_export.dart';

/// Pure, SDK-free formatters that render a [KoheraRoomExport] to a String.
class HistoryExportFormatters {
  const HistoryExportFormatters();

  String format(KoheraRoomExport export) => switch (export.options.format) {
        KoheraExportFormat.json => _json(export),
        KoheraExportFormat.html => _html(export),
        KoheraExportFormat.plaintext => _plaintext(export),
      };

  // ── JSON ──────────────────────────────────────────────────

  String _json(KoheraRoomExport export) {
    final map = <String, Object?>{
      'room': <String, Object?>{
        'room_id': export.meta.roomId,
        'displayname': export.meta.displayname,
        if (export.meta.canonicalAlias != null)
          'canonical_alias': export.meta.canonicalAlias,
        if (export.meta.topic != null) 'topic': export.meta.topic,
      },
      'exported_at': export.meta.exportedAt?.toIso8601String(),
      'options': <String, Object?>{
        'format': export.options.format.name,
        'include_media': export.options.includeMedia,
        if (export.options.start != null)
          'start': export.options.start!.toIso8601String(),
        if (export.options.end != null)
          'end': export.options.end!.toIso8601String(),
      },
      'messages': export.messages
          .map((m) => <String, Object?>{
                'event_id': m.eventId,
                'sender': m.senderId,
                'sender_displayname': m.senderDisplayname,
                'timestamp': m.timestamp.toIso8601String(),
                'message_type': m.messageType,
                'body': m.body,
                if (m.formattedBody != null)
                  'formatted_body': m.formattedBody,
                if (m.hasMedia) ..._mediaEntries(m),
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Map<String, Object?> _mediaEntries(KoheraExportedMessage m) {
    final entries = <String, Object?>{'media_url': m.mediaUrl};
    if (m.mediaFileName != null) {
      entries['media_file_name'] = m.mediaFileName;
    }
    if (m.mediaMimetype != null) {
      entries['media_mimetype'] = m.mediaMimetype;
    }
    return entries;
  }

  // ── HTML ──────────────────────────────────────────────────

  String _html(KoheraRoomExport export) {
    final sb = StringBuffer();
    sb.writeln('<!DOCTYPE html>');
    sb.writeln('<html lang="en">');
    sb.writeln('<head>');
    sb.writeln('<meta charset="utf-8">');
    sb.writeln('<meta name="viewport" content="width=device-width">');
    sb.writeln(
      '<title>${_escape(export.meta.displayname)} — chat export</title>',
    );
    sb.writeln('<style>');
    sb.writeln(
      'body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;max-width:760px;margin:24px auto;padding:0 12px;color:#111;}',
    );
    sb.writeln(
      'header{margin-bottom:16px;border-bottom:1px solid #ddd;padding-bottom:12px;}',
    );
    sb.writeln('h1{margin:0 0 4px;font-size:20px;}');
    sb.writeln('.meta{color:#666;font-size:13px;}');
    sb.writeln('ul{list-style:none;padding:0;}');
    sb.writeln('li{padding:8px 0;border-bottom:1px solid #eee;}');
    sb.writeln(
      '.ts{color:#999;font-size:12px;font-family:monospace;margin-right:8px;}',
    );
    sb.writeln('.sender{font-weight:600;margin-right:8px;}');
    sb.writeln('.media{font-size:13px;color:#0366d6;}');
    sb.writeln('</style>');
    sb.writeln('</head>');
    sb.writeln('<body>');
    sb.writeln('<header>');
    sb.writeln('<h1>${_escape(export.meta.displayname)}</h1>');
    sb.write('<div class="meta">Room ID: ${_escape(export.meta.roomId)}');
    if (export.meta.canonicalAlias != null) {
      sb.write(' &middot; ${_escape(export.meta.canonicalAlias!)}');
    }
    sb.writeln('</div>');
    if (export.meta.topic != null && export.meta.topic!.isNotEmpty) {
      sb.writeln('<div class="meta">${_escape(export.meta.topic!)}</div>');
    }
    if (export.meta.exportedAt != null) {
      sb.writeln(
        '<div class="meta">Exported: '
        '${_escape(export.meta.exportedAt!.toIso8601String())}</div>',
      );
    }
    sb.writeln('</header>');
    sb.writeln('<ul>');
    for (final m in export.messages) {
      sb.writeln('<li>');
      sb.writeln(
        '<span class="ts">${_escape(m.timestamp.toIso8601String())}</span>',
      );
      sb.write(
        '<span class="sender">${_escape(m.senderDisplayname)}</span>',
      );
      sb.write('<span class="body">${_bodyHtml(m)}</span>');
      sb.writeln('</li>');
    }
    sb.writeln('</ul>');
    if (export.messages.isEmpty) {
      sb.writeln('<p>No messages in the selected range.</p>');
    }
    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  String _bodyHtml(KoheraExportedMessage m) {
    if (m.hasMedia) {
      final name = m.mediaFileName ?? 'media';
      final url = m.mediaUrl ?? '';
      final mime = m.mediaMimetype ?? '';
      final label = _escape(
        '[media: $name${mime.isNotEmpty ? ' ($mime)' : ''}]',
      );
      if (url.isNotEmpty) {
        return '<a class="media" href="${_escape(url)}">$label</a>';
      }
      return label;
    }
    return _escape(m.body).replaceAll('\n', '<br>');
  }

  // ── Plaintext ─────────────────────────────────────────────

  String _plaintext(KoheraRoomExport export) {
    final sb = StringBuffer();
    sb.writeln('# ${export.meta.displayname}');
    sb.writeln('Room ID: ${export.meta.roomId}');
    if (export.meta.canonicalAlias != null) {
      sb.writeln('Alias: ${export.meta.canonicalAlias}');
    }
    if (export.meta.topic != null && export.meta.topic!.isNotEmpty) {
      sb.writeln('Topic: ${export.meta.topic}');
    }
    if (export.meta.exportedAt != null) {
      sb.writeln('Exported: ${export.meta.exportedAt!.toIso8601String()}');
    }
    if (export.options.hasRange) {
      if (export.options.start != null) {
        sb.writeln('From: ${export.options.start!.toIso8601String()}');
      }
      if (export.options.end != null) {
        sb.writeln('Until: ${export.options.end!.toIso8601String()}');
      }
    }
    sb.writeln('-' * 40);
    if (export.messages.isEmpty) {
      sb.writeln('(no messages in the selected range)');
      return sb.toString();
    }
    for (final m in export.messages) {
      sb.write('[${m.timestamp.toIso8601String()}] ${m.senderDisplayname}: ');
      if (m.hasMedia) {
        final name = m.mediaFileName ?? 'media';
        final url = m.mediaUrl ?? '';
        sb.write('[media: $name]');
        if (url.isNotEmpty) sb.write(' <$url>');
        if (m.mediaMimetype != null) sb.write(' (${m.mediaMimetype})');
      } else {
        sb.write(m.body.replaceAll('\r', ''));
      }
      sb.writeln();
    }
    return sb.toString();
  }

  // ── Helpers ───────────────────────────────────────────────

  static String _escape(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
