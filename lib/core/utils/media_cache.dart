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
    final playablePath = await _ensureIosPlayable(path, mimetype);
    _tempFiles[eventId] = playablePath;
    _evictOldest();
    return KoheraFileSource(playablePath);
  }

  // ── iOS Opus handling ───────────────────────────────────────
  // iOS AVPlayer cannot decode Ogg/Opus. Remux Ogg/Opus to CAF/Opus (CAF is
  // AVPlayer-supported on iOS 11+) so just_audio can play voice messages.
  // Falls back to the original path if the input is not valid Ogg/Opus.
  static Future<String> _ensureIosPlayable(String path, String? mime) async {
    if (!isNativeIOS || !_isOggOpus(mime)) return path;
    final cafPath = path.replaceAll(_oggOpusExt, '.caf');
    try {
      await OggCafConverter().convertOggToCaf(
        input: path,
        output: cafPath,
        deleteInput: true,
      );
      return cafPath;
    } catch (e) {
      debugPrint('[Kohera] iOS Ogg to CAF remux failed, using original: $e');
      return path;
    }
  }

  static bool _isOggOpus(String? mime) =>
      mime == 'audio/ogg' || mime == 'audio/opus';

  static final RegExp _oggOpusExt = RegExp(r'\.(ogg|opus)$');

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
