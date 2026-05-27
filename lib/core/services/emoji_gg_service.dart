import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kohera/core/models/emoji_gg_pack.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EmojiGgService {
  EmojiGgService({
    http.Client? client,
    Duration? cacheTtl,
    Duration? requestTimeout,
  })  : _client = client ?? http.Client(),
        _cacheTtl = cacheTtl ?? const Duration(hours: 24),
        _requestTimeout = requestTimeout ?? const Duration(seconds: 15);

  static final Uri _packsEndpoint = Uri.parse('https://emoji.gg/api/packs');
  static const _cacheFileName = 'emojigg_packs_cache.json';

  final http.Client _client;
  final Duration _cacheTtl;
  final Duration _requestTimeout;

  List<EmojiGgPack>? _memoryCache;
  DateTime? _memoryCachedAt;
  Future<List<EmojiGgPack>>? _inFlight;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _client.close();
  }

  Future<List<EmojiGgPack>> fetchPacks({bool forceRefresh = false}) {
    if (_disposed) return Future.value([]);
    return _inFlight ??= _fetchPacks(forceRefresh: forceRefresh)
        .whenComplete(() => _inFlight = null);
  }

  Future<Uint8List> downloadImage(String imageUrl) async {
    final response = await _client
        .get(Uri.parse(imageUrl))
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'emoji.gg image download failed (${response.statusCode}): $imageUrl',
      );
    }
    return response.bodyBytes;
  }

  // ── Private ──────────────────────────────────────────────────

  bool _isCacheFresh() =>
      _memoryCachedAt != null &&
      DateTime.now().difference(_memoryCachedAt!) < _cacheTtl;

  Future<List<EmojiGgPack>> _fetchPacks({required bool forceRefresh}) async {
    if (!forceRefresh && _memoryCache != null && _isCacheFresh()) {
      return _memoryCache!;
    }

    if (!forceRefresh) {
      final disk = await _readDiskCache();
      if (disk != null) {
        _memoryCache = disk;
        _memoryCachedAt = DateTime.now();
        return disk;
      }
    }

    try {
      final response = await _client
          .get(_packsEndpoint, headers: {'Accept': 'application/json'})
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final raw = jsonDecode(response.body) as List<dynamic>;
        final packs = raw
            .cast<Map<String, dynamic>>()
            .map(EmojiGgPack.fromJson)
            .whereType<EmojiGgPack>()
            .where((pack) => pack.amount > 0)
            .toList();

        _memoryCache = packs;
        _memoryCachedAt = DateTime.now();
        unawaited(_writeDiskCache(raw));
        return packs;
      }

      debugPrint('[Kohera] emoji.gg API returned ${response.statusCode}');
      return _memoryCache ?? [];
    } catch (e) {
      debugPrint('[Kohera] emoji.gg fetch failed: $e');
      return _memoryCache ?? [];
    }
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _cacheFileName));
  }

  Future<List<EmojiGgPack>?> _readDiskCache() async {
    try {
      final file = await _cacheFile();
      if (!file.existsSync()) return null;

      final age = DateTime.now().difference(file.statSync().modified);
      if (age > _cacheTtl) return null;

      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw
          .cast<Map<String, dynamic>>()
          .map(EmojiGgPack.fromJson)
          .whereType<EmojiGgPack>()
          .where((pack) => pack.amount > 0)
          .toList();
    } catch (e) {
      debugPrint('[Kohera] emoji.gg cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeDiskCache(List<dynamic> raw) async {
    try {
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(raw));
    } catch (e) {
      debugPrint('[Kohera] emoji.gg cache write failed: $e');
    }
  }
}

// Dart 3 unawaited helper (mirrors dart:async behaviour).
void unawaited(Future<void> future) => future.ignore();
