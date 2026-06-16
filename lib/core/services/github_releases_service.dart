import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ── Release notes data model ─────────────────────────────────

class ReleaseNotes {
  ReleaseNotes({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.htmlUrl,
    required this.fetchedAt,
    this.etag,
  });

  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final String htmlUrl;
  final DateTime fetchedAt;
  final String? etag;

  factory ReleaseNotes.fromGitHubJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
    String? etag,
  }) {
    return ReleaseNotes(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
              fetchedAt,
      htmlUrl: json['html_url'] as String? ?? '',
      fetchedAt: fetchedAt,
      etag: etag,
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'tag_name': tagName,
        'name': name,
        'body': body,
        'published_at': publishedAt.toIso8601String(),
        'html_url': htmlUrl,
        'fetched_at': fetchedAt.toIso8601String(),
        if (etag != null) 'etag': etag,
      };

  factory ReleaseNotes.fromCacheJson(Map<String, dynamic> json) {
    return ReleaseNotes(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      htmlUrl: json['html_url'] as String? ?? '',
      fetchedAt:
          DateTime.tryParse(json['fetched_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      etag: json['etag'] as String?,
    );
  }

  ReleaseNotes copyWith({DateTime? fetchedAt, String? etag}) => ReleaseNotes(
        tagName: tagName,
        name: name,
        body: body,
        publishedAt: publishedAt,
        htmlUrl: htmlUrl,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        etag: etag ?? this.etag,
      );
}

// ── Service ──────────────────────────────────────────────────

typedef CacheDirProvider = Future<Directory> Function();

/// Fetches the latest release notes from the Kohera GitHub repository,
/// with on-disk caching and ETag-based revalidation.
class GitHubReleasesService {
  GitHubReleasesService({
    http.Client? client,
    CacheDirProvider? cacheDirProvider,
    Uri? endpoint,
    Duration? cacheTtl,
    Duration? requestTimeout,
  })  : _client = client ?? http.Client(),
        _cacheDirProvider = cacheDirProvider ?? getApplicationSupportDirectory,
        _endpoint = endpoint ?? _defaultEndpoint,
        _cacheTtl = cacheTtl ?? const Duration(hours: 6),
        _requestTimeout = requestTimeout ?? const Duration(seconds: 10);

  static final Uri _defaultEndpoint = Uri.parse(
    'https://api.github.com/repos/Quantumheart/Kohera/releases/latest',
  );
  static const _cacheFileName = 'whats_new_cache.json';

  final http.Client _client;
  final CacheDirProvider _cacheDirProvider;
  final Uri _endpoint;
  final Duration _cacheTtl;
  final Duration _requestTimeout;

  final Map<String, ReleaseNotes> _memoryCache = {};
  final Map<String, Future<ReleaseNotes?>> _inFlight = {};
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _client.close();
  }

  /// Returns the latest release. Prefers cache within [_cacheTtl].
  /// On expiry, revalidates with `If-None-Match` and falls back to cache
  /// on network errors.
  Future<ReleaseNotes?> fetchLatest({bool forceRefresh = false}) =>
      fetchRelease(forceRefresh: forceRefresh);

  /// Returns the release for [tag] (e.g. `v1.6.1`), or the latest release
  /// when [tag] is null. Caches each tag separately so the latest-release
  /// lookup used by the update banner never overwrites a version-specific
  /// lookup used by the release-notes screen.
  Future<ReleaseNotes?> fetchRelease({String? tag, bool forceRefresh = false}) {
    if (_disposed) return Future<ReleaseNotes?>.value();
    final key = _cacheKey(tag);
    final existing = _inFlight[key];
    if (existing != null && !forceRefresh) return existing;
    final future = _fetch(tag: tag, forceRefresh: forceRefresh)
        .whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = future;
    return future;
  }

  /// Reads the cached release without touching the network.
  Future<ReleaseNotes?> getCached({String? tag}) async {
    final key = _cacheKey(tag);
    final mem = _memoryCache[key];
    if (mem != null) return mem;
    return _readDiskCache(tag);
  }

  Future<ReleaseNotes?> _fetch({
    required String? tag,
    required bool forceRefresh,
  }) async {
    final key = _cacheKey(tag);
    final cached = await getCached(tag: tag);
    if (!forceRefresh && cached != null && _isFresh(cached)) {
      return cached;
    }

    try {
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Kohera (Flutter Matrix client)',
        'X-GitHub-Api-Version': '2022-11-28',
      };
      if (cached?.etag != null) {
        headers['If-None-Match'] = cached!.etag!;
      }

      final response = await _client
          .get(_endpointFor(tag), headers: headers)
          .timeout(_requestTimeout);

      if (response.statusCode == 304 && cached != null) {
        final refreshed = cached.copyWith(fetchedAt: DateTime.now());
        await _writeDiskCache(tag, refreshed);
        _memoryCache[key] = refreshed;
        return refreshed;
      }

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final etag = response.headers['etag'];
        final notes = ReleaseNotes.fromGitHubJson(
          json,
          fetchedAt: DateTime.now(),
          etag: etag,
        );
        await _writeDiskCache(tag, notes);
        _memoryCache[key] = notes;
        return notes;
      }

      debugPrint(
        '[Kohera] GitHub releases fetch returned ${response.statusCode}',
      );
      return cached;
    } catch (e) {
      debugPrint('[Kohera] GitHub releases fetch failed: $e');
      return cached;
    }
  }

  bool _isFresh(ReleaseNotes notes) =>
      DateTime.now().difference(notes.fetchedAt) < _cacheTtl;

  String _cacheKey(String? tag) => tag == null ? 'latest' : 'tag:$tag';

  Uri _endpointFor(String? tag) {
    if (tag == null) return _endpoint;
    final base = _endpoint.toString();
    final trimmed = base.endsWith('/latest')
        ? base.substring(0, base.length - '/latest'.length)
        : base;
    return Uri.parse('$trimmed/tags/$tag');
  }

  Future<File> _cacheFile(String? tag) async {
    final dir = await _cacheDirProvider();
    final name = tag == null
        ? _cacheFileName
        : 'whats_new_cache_${tag.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.json';
    return File(p.join(dir.path, name));
  }

  Future<ReleaseNotes?> _readDiskCache(String? tag) async {
    try {
      final file = await _cacheFile(tag);
      if (!file.existsSync()) return null;
      final contents = await file.readAsString();
      if (contents.isEmpty) return null;
      final json = jsonDecode(contents) as Map<String, dynamic>;
      final notes = ReleaseNotes.fromCacheJson(json);
      _memoryCache[_cacheKey(tag)] = notes;
      return notes;
    } catch (e) {
      debugPrint('[Kohera] GitHub releases cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeDiskCache(String? tag, ReleaseNotes notes) async {
    try {
      final file = await _cacheFile(tag);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(notes.toCacheJson()));
    } catch (e) {
      debugPrint('[Kohera] GitHub releases cache write failed: $e');
    }
  }
}
