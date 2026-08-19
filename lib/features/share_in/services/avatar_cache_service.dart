import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kohera/data/services/media_resolver.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:path/path.dart' as p;

/// Pre-renders room avatar thumbnails into the App-Group container so the
/// iOS Share Extension can display real avatars without the Matrix SDK or
/// access token (which stay in the main app).
///
/// Thumbnails are 48x48, fetched via [MediaResolver] (which produces an
/// authenticated HTTP URL + headers) and written to
/// `<appGroup>/avatars/<roomId>.<ext>`. An index (`avatars/index.json`) maps
/// `roomId -> {mxc, file}` so unchanged avatars are skipped on subsequent
/// syncs and avatar changes (a different mxc) replace the old file.
class AvatarCacheService {
  AvatarCacheService({
    required MediaResolver mediaResolver,
    required Future<String?> Function() getAppGroupPath,
    http.Client? httpClient,
  })  : _mediaResolver = mediaResolver,
        _getAppGroupPath = getAppGroupPath,
        _httpClient = httpClient ?? http.Client();

  final MediaResolver _mediaResolver;
  final Future<String?> Function() _getAppGroupPath;
  final http.Client _httpClient;

  String? _avatarsDir;
  bool _loaded = false;
  final Map<String, _Entry> _index = {};

  // ── Init ────────────────────────────────────────────────────

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final root = await _getAppGroupPath();
      if (root == null) return;
      _avatarsDir = p.join(root, 'avatars');
      await Directory(_avatarsDir!).create(recursive: true);
      await _loadIndex();
    } catch (e) {
      debugPrint('[Kohera] AvatarCache init failed: $e');
    }
  }

  Future<void> _loadIndex() async {
    final f = File(p.join(_avatarsDir!, 'index.json'));
    if (!f.existsSync()) return;
    try {
      final raw = await f.readAsString();
      final map = jsonDecode(raw);
      if (map is! Map) return;
      _index.clear();
      map.forEach((roomId, v) {
        if (roomId is String && v is Map) {
          final mxc = v['mxc'];
          final file = v['file'];
          if (mxc is String && file is String) {
            _index[roomId] = _Entry(mxc, file);
          }
        }
      });
    } catch (e) {
      debugPrint('[Kohera] AvatarCache index load failed: $e');
    }
  }

  Future<void> _persistIndex() async {
    if (_avatarsDir == null) return;
    final f = File(p.join(_avatarsDir!, 'index.json'));
    final map = <String, Map<String, String>>{};
    for (final e in _index.entries) {
      map[e.key] = {'mxc': e.value.mxc, 'file': e.value.file};
    }
    try {
      await f.writeAsString(jsonEncode(map));
    } catch (e) {
      debugPrint('[Kohera] AvatarCache index persist failed: $e');
    }
  }

  // ── Public API ──────────────────────────────────────────────

  /// Synchronous map of `roomId -> absolute avatar file path` for entries
  /// whose file currently exists. Read by `RoomSnapshotService` when
  /// projecting snapshots so [RoomSnapshot.avatarPath] is filled without
  /// blocking on IO.
  Map<String, String> cachedPaths() {
    final out = <String, String>{};
    if (_avatarsDir == null) return out;
    for (final e in _index.entries) {
      final abs = p.join(_avatarsDir!, e.value.file);
      if (File(abs).existsSync()) out[e.key] = abs;
    }
    return out;
  }

  /// Ensures avatars for the given rooms are cached. Skips rooms whose mxc is
  /// unchanged and whose file still exists; re-downloads on mxc change;
  /// deletes the file when a room's avatar becomes null. Returns when all
  /// pending downloads finish (failures are tolerated, not thrown).
  Future<void> ensureFor(List<RoomSnapshot> rooms) async {
    await init();
    if (_avatarsDir == null) return;

    final byRoom = {for (final r in rooms) r.roomId: r};
    final futures = <Future<void>>[];

    for (final entry in byRoom.entries) {
      final roomId = entry.key;
      final mxc = entry.value.avatarMxc;
      if (mxc == null || mxc.isEmpty) {
        // Room lost its avatar — drop the cached file + index entry.
        await _deleteCached(roomId);
        continue;
      }
      final existing = _index[roomId];
      if (existing != null && existing.mxc == mxc) {
        if (File(p.join(_avatarsDir!, existing.file)).existsSync()) continue;
      }
      futures.add(_download(roomId, mxc));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
      await _persistIndex();
    }
  }

  // ── Download ────────────────────────────────────────────────

  Future<void> _download(String roomId, String mxc) async {
    try {
      final thumb = await _mediaResolver.resolve(
        mxc,
        width: 48,
        height: 48,
      );
      if (thumb == null) return;
      final resp = await _httpClient.get(
        Uri.parse(thumb.url),
        headers: thumb.headers ?? const {},
      );
      if (resp.statusCode != 200) {
        debugPrint('[Kohera] AvatarCache $roomId HTTP ${resp.statusCode}');
        return;
      }
      final ext = _extFor(resp.headers['content-type']);
      final file = '$roomId.$ext';
      final abs = p.join(_avatarsDir!, file);
      final old = _index[roomId];
      if (old != null && old.file != file) {
        final oldAbs = p.join(_avatarsDir!, old.file);
        try {
          await File(oldAbs).delete();
        } catch (_) {}
      }
      await File(abs).writeAsBytes(resp.bodyBytes);
      _index[roomId] = _Entry(mxc, file);
    } catch (e) {
      debugPrint('[Kohera] AvatarCache download failed for $roomId: $e');
    }
  }

  Future<void> _deleteCached(String roomId) async {
    final entry = _index.remove(roomId);
    if (entry == null) return;
    try {
      await File(p.join(_avatarsDir!, entry.file)).delete();
    } catch (_) {}
  }

  String _extFor(String? contentType) {
    if (contentType != null) {
      final ct = contentType.toLowerCase().split(';').first.trim();
      if (ct.contains('jpeg') || ct.contains('jpg')) return 'jpg';
      if (ct.contains('png')) return 'png';
      if (ct.contains('webp')) return 'webp';
      if (ct.contains('gif')) return 'gif';
    }
    return 'png';
  }

  Future<void> dispose() async {
    _httpClient.close();
  }
}

class _Entry {
  const _Entry(this.mxc, this.file);
  final String mxc;
  final String file;
}
