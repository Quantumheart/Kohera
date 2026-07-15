import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/utils/media_cache_io.dart'
    if (dart.library.js_interop) 'package:kohera/core/utils/media_cache_web.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

// ── Media cache (download/decrypt → temp file or memory) ──────

class MediaCache {
  static const _maxEntries = 50;
  static final LinkedHashMap<String, String> _tempFiles = LinkedHashMap();

  static Future<KoheraMediaSource> resolve(MediaController controller) async {
    final cached = _tempFiles[controller.eventId];
    if (cached != null && !kIsWeb && File(cached).existsSync()) {
      _promote(controller.eventId);
      return KoheraFileSource(cached);
    }

    final bytes = await controller.downloadAndDecrypt();
    return _bytesToMedia(controller.eventId, bytes, controller.mimeType);
  }

  static Future<KoheraMediaSource> _bytesToMedia(
      String eventId, Uint8List bytes, String? mimetype,) async {
    if (kIsWeb) {
      return KoheraBytesSource(bytes, mimeType: mimetype);
    }
    final dir = await getTemporaryDirectory();
    final sanitized = eventId.replaceAll(RegExp(r'[^\w]'), '_');
    final ext = _extensionForMime(mimetype);
    final path = '${dir.path}/kohera_media_$sanitized$ext';
    final file = File(path);
    await file.writeAsBytes(bytes);
    final playablePath = await _ensureIosPlayable(path, bytes);
    _tempFiles[eventId] = playablePath;
    _evictOldest();
    return KoheraFileSource(playablePath);
  }

  // ── iOS playback prep ────────────────────────────────────────
  // iOS AVPlayer cannot decode the Ogg container. Sniff the actual content
  // (the mimetype label is unreliable: Kohera previously sent AAC/m4a bytes
  // labelled audio/ogg) and:
  //   - real Ogg/Opus → remux to CAF/Opus (AVPlayer-supported on iOS 11+)
  //   - real m4a/mp4 → rename to .m4a so AVPlayer decodes AAC natively
  // Falls back to the original path if the format is unknown.
  static Future<String> _ensureIosPlayable(String path, Uint8List bytes) async {
    if (!isNativeIOS) return path;
    final fmt = _sniffFormat(bytes);
    switch (fmt) {
      case _AudioFormat.ogg:
        final cafPath = _replaceExt(path, '.caf');
        try {
          await OggCafConverter().convertOggToCaf(
            input: path,
            output: cafPath,
            deleteInput: true,
          );
          return cafPath;
        } catch (e) {
          debugPrint('[Kohera] iOS Ogg to CAF remux failed: $e');
          return path;
        }
      case _AudioFormat.mp4:
        final m4aPath = _replaceExt(path, '.m4a');
        if (m4aPath == path) return path;
        try {
          await File(path).rename(m4aPath);
          return m4aPath;
        } catch (e) {
          debugPrint('[Kohera] iOS m4a rename failed: $e');
          return path;
        }
      case _AudioFormat.unknown:
        return path;
    }
  }

  static _AudioFormat _sniffFormat(Uint8List b) {
    if (b.length >= 4 &&
        b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return _AudioFormat.ogg;
    }
    if (b.length >= 8 &&
        b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return _AudioFormat.mp4;
    }
    return _AudioFormat.unknown;
  }

  static String _replaceExt(String path, String newExt) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? '${path.substring(0, dot)}$newExt' : '$path$newExt';
  }

  static String _extensionForMime(String? mime) {
    if (mime == null) return '';
    return switch (mime) {
      'audio/ogg' => '.ogg',
      'audio/opus' => '.opus',
      'audio/mpeg' => '.mp3',
      'audio/mp4' => '.m4a',
      'audio/aac' => '.aac',
      'audio/wav' => '.wav',
      'audio/webm' => '.webm',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'video/quicktime' => '.mov',
      _ => '',
    };
  }

  static void _promote(String eventId) {
    final path = _tempFiles.remove(eventId);
    if (path != null) _tempFiles[eventId] = path;
  }

  static void _evictOldest() {
    while (_tempFiles.length > _maxEntries) {
      final oldest = _tempFiles.keys.first;
      evict(oldest);
    }
  }

  static void evict(String eventId) {
    final path = _tempFiles.remove(eventId);
    if (path != null && !kIsWeb) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  static void clearAll() {
    for (final path in _tempFiles.values) {
      if (!kIsWeb) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
    _tempFiles.clear();
  }
}

enum _AudioFormat { ogg, mp4, unknown }
