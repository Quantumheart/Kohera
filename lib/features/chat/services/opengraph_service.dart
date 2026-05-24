import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:kohera/features/chat/services/opengraph_io.dart'
    if (dart.library.js_interop) 'package:kohera/features/chat/services/opengraph_web.dart';
import 'package:matrix/matrix.dart';

// ── OpenGraph data model ─────────────────────────────────────

class OpenGraphData {
  OpenGraphData({
    required this.url, this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String url;
  final DateTime fetchedAt;

  bool get isEmpty => title == null && description == null && imageUrl == null;
}

// ── Cache entry wrapper ──────────────────────────────────────

class _CacheEntry {
  _CacheEntry(this.data) : cachedAt = DateTime.now();
  final OpenGraphData? data;
  final DateTime cachedAt;
}

// ── OpenGraph fetching service ───────────────────────────────

class OpenGraphService {
  OpenGraphService({http.Client? client, Client? matrixClient})
      : _client = client ?? http.Client(),
        _matrixClient = matrixClient;

  static const _maxCacheSize = 200;
  static const _fetchTimeout = Duration(seconds: 5);
  static const int _maxBytes = 50 * 1024; // 50 KB
  static const _maxRedirects = 5;
  static const _cacheTtl = Duration(minutes: 30);

  final _cache = <String, _CacheEntry>{};
  final _inFlight = <String, Future<OpenGraphData?>>{};

  final http.Client _client;
  final Client? _matrixClient;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _client.close();
  }

  /// Fetch OpenGraph metadata for the given [url].
  ///
  /// Returns `null` if the URL is unsupported, unreachable, or has no OG tags.
  Future<OpenGraphData?> fetch(String url) async {
    if (_disposed || !_isSupported(url)) return null;

    // Cache hit — move to end for LRU behaviour.
    if (_cache.containsKey(url)) {
      final entry = _cache.remove(url)!;
      // Evict stale entries (applies to both positive and negative results).
      if (DateTime.now().difference(entry.cachedAt) > _cacheTtl) {
        // Fall through to re-fetch.
      } else {
        _cache[url] = entry;
        return entry.data;
      }
    }

    // Deduplicate concurrent fetches for the same URL.
    if (_inFlight.containsKey(url)) return _inFlight[url];

    final future = _doFetch(url);
    _inFlight[url] = future;
    try {
      final result = await future;
      _putCache(url, result);
      return result;
    } finally {
      unawaited(_inFlight.remove(url));
    }
  }

  // ── Homeserver URL preview (primary path) ─────────────────

  Future<OpenGraphData?> _fetchViaHomeserver(String url) async {
    final client = _matrixClient;
    final token = client?.accessToken;
    final base = client?.baseUri;
    if (token == null || base == null) return null;

    try {
      final requestUri = Uri(
        path: '_matrix/client/v1/media/preview_url',
        queryParameters: {'url': url},
      );
      final request = http.Request('GET', base.resolveUri(requestUri));
      request.headers['authorization'] = 'Bearer $token';

      final streamed = await _client.send(request).timeout(_fetchTimeout);
      if (streamed.statusCode != 200) return null;

      final body = await streamed.stream.toBytes();
      final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;

      var imageUrl = json['og:image'] as String?;

      // Convert mxc:// to an authenticated thumbnail HTTPS URL.
      if (imageUrl != null && imageUrl.startsWith('mxc://')) {
        final mxcUri = Uri.tryParse(imageUrl);
        final resolved = mxcUri != null
            ? (await mxcUri.getThumbnailUri(client!, width: 60, height: 60))
                .toString()
            : null;
        imageUrl = (resolved?.isEmpty ?? true) ? null : resolved;
      }

      final data = OpenGraphData(
        url: url,
        title: json['og:title'] as String?,
        description: json['og:description'] as String?,
        imageUrl: imageUrl,
        siteName: json['og:site_name'] as String?,
      );
      return data.isEmpty ? null : data;
    } catch (e) {
      debugPrint('[Kohera] Homeserver URL preview failed for $url: $e');
      return null;
    }
  }

  // ── Internal helpers ───────────────────────────────────────

  @visibleForTesting
  static bool isSupported(String url) => _isSupported(url);

  static bool _isSupported(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    // Skip Matrix links.
    if (uri.host == 'matrix.to') return false;
    // Reject obvious private/loopback hostnames.
    if (_isPrivateHost(uri.host)) return false;
    return true;
  }

  /// Returns `true` if [host] is a known private or loopback hostname.
  @visibleForTesting
  static bool isPrivateHost(String host) => _isPrivateHost(host);

  static bool _isPrivateHost(String host) {
    if (host == 'localhost') return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;
    return _isPrivateAddress(ip);
  }

  /// Returns `true` if [address] is loopback, link-local, or RFC 1918 private.
  @visibleForTesting
  static bool isPrivateAddress(InternetAddress address) =>
      _isPrivateAddress(address);

  static bool _isPrivateAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    if (address.type == InternetAddressType.IPv4) {
      final bytes = address.rawAddress;
      // 10.0.0.0/8
      if (bytes[0] == 10) return true;
      // 172.16.0.0/12
      if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return true;
      // 192.168.0.0/16
      if (bytes[0] == 192 && bytes[1] == 168) return true;
      // 169.254.0.0/16 (link-local / cloud metadata)
      if (bytes[0] == 169 && bytes[1] == 254) return true;
    }
    if (address.type == InternetAddressType.IPv6) {
      final bytes = address.rawAddress;
      // fc00::/7 (unique local)
      if ((bytes[0] & 0xFE) == 0xFC) return true;
      // fe80::/10 (link-local)
      if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return true;
    }
    return false;
  }

  /// Override DNS resolution for testing. When set, replaces
  /// [InternetAddress.lookup] in [_resolvePublicAddresses].
  @visibleForTesting
  Future<List<InternetAddress>> Function(String host)? dnsResolver;

  /// Resolves [host] and returns the list of public addresses.
  /// Returns `null` if any resolved address is private (SSRF protection).
  Future<List<InternetAddress>?> _resolvePublicAddresses(String host) async {
    final resolve = dnsResolver ?? InternetAddress.lookup;
    final addresses = await resolve(host).timeout(_fetchTimeout);
    if (addresses.isEmpty) return null;
    if (addresses.any(_isPrivateAddress)) {
      debugPrint('[Kohera] OpenGraph blocked private IP for $host');
      return null;
    }
    return addresses;
  }

  Future<OpenGraphData?> _doFetch(String url) async {
    var result = await _fetchViaHomeserver(url) ?? await _doDirectFetch(url);

    // For YouTube video URLs, fetch oEmbed data to get the accurate title,
    // channel name, and video-specific thumbnail (the homeserver returns generic
    // YouTube branding instead of per-video metadata).
    if (result != null && _youtubeVideoId(url) != null) {
      final oembed = await _fetchYouTubeOEmbed(url, result);
      if (oembed != null) result = oembed;
    }

    return result;
  }

  /// Extracts the YouTube video ID from [url], or `null` if not a YouTube video.
  @visibleForTesting
  static String? youtubeVideoId(String url) => _youtubeVideoId(url);

  static String? _youtubeVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final host = uri.host
        .replaceFirst('www.', '')
        .replaceFirst('m.', '');

    if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      final segments = uri.pathSegments;
      if (segments.isEmpty) return null;
      switch (segments.first) {
        case 'watch':
          return uri.queryParameters['v'];
        case 'shorts' || 'embed' || 'v':
          return segments.length > 1 ? segments[1] : null;
      }
    } else if (host == 'youtu.be') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }

    return null;
  }

  /// Calls the YouTube oEmbed API and overlays accurate title, channel name,
  /// and video thumbnail onto [base]. Returns `null` on any failure so the
  /// caller can fall back to [base] unchanged.
  Future<OpenGraphData?> _fetchYouTubeOEmbed(
      String url, OpenGraphData base,) async {
    try {
      final oEmbedUri = Uri.https('www.youtube.com', '/oembed', {
        'url': url,
        'format': 'json',
      });
      final response =
          await _client.get(oEmbedUri).timeout(_fetchTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, Object?>;
      final title = json['title'] as String?;
      final authorName = json['author_name'] as String?;
      final thumbnailUrl = json['thumbnail_url'] as String?;

      return OpenGraphData(
        url: base.url,
        title: title ?? base.title,
        description: base.description,
        siteName: authorName ?? base.siteName,
        imageUrl: thumbnailUrl ?? base.imageUrl,
        fetchedAt: base.fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<OpenGraphData?> _doDirectFetch(String url) async {
    try {
      var uri = Uri.parse(url);

      for (var i = 0; i <= _maxRedirects; i++) {
        final addresses = await _resolvePublicAddresses(uri.host);
        if (addresses == null) return null;

        final request = http.Request('GET', uri)
          ..headers['User-Agent'] = 'Kohera/1.0 (Flutter Matrix client)'
          ..followRedirects = false;
        final streamed =
            await _client.send(request).timeout(_fetchTimeout);

        if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
          if (i == _maxRedirects) return null;
          final location = streamed.headers['location'];
          if (location == null) return null;
          uri = uri.resolve(location);
          if (uri.scheme != 'http' && uri.scheme != 'https') return null;
          if (_isPrivateHost(uri.host)) return null;
          continue;
        }

        final result = await _readResponse(streamed, url);
        return await _validateImageUrl(result);
      }

      return null;
    } catch (e) {
      debugPrint('[Kohera] OpenGraph fetch failed for $url: $e');
      return null;
    }
  }

  Future<OpenGraphData?> _readResponse(
      http.StreamedResponse response, String url,) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    // Only parse HTML responses.
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('text/html') &&
        !contentType.contains('application/xhtml')) {
      return null;
    }

    // Read only the first ~50 KB to avoid downloading huge pages.
    final bytes = <int>[];
    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    void finish() {
      if (!done.isCompleted) done.complete();
    }
    subscription = response.stream.listen(
      (chunk) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxBytes) {
          unawaited(subscription.cancel());
          finish();
        }
      },
      onDone: finish,
      onError: (_, __) => finish(),
      cancelOnError: true,
    );
    try {
      await done.future.timeout(
        _fetchTimeout,
        onTimeout: () { unawaited(subscription.cancel()); },
      );
    } catch (_) {
      // Stream cancelled or timed out — parse whatever we have.
    }
    final truncated =
        bytes.length > _maxBytes ? bytes.sublist(0, _maxBytes) : bytes;
    if (truncated.isEmpty) return null;

    final body = utf8.decode(truncated, allowMalformed: true);
    return _parse(body, url);
  }

  @visibleForTesting
  OpenGraphData? parse(String html, String url) => _parse(html, url);

  OpenGraphData? _parse(String html, String url) {
    final document = html_parser.parse(html);
    final metas = document.querySelectorAll('meta');

    String? ogTitle;
    String? ogDescription;
    String? ogImage;
    String? ogSiteName;

    for (final meta in metas) {
      final property = meta.attributes['property'] ?? '';
      final name = meta.attributes['name'] ?? '';
      final content = meta.attributes['content'];
      if (content == null || content.isEmpty) continue;

      switch (property) {
        case 'og:title':
          ogTitle = content;
        case 'og:description':
          ogDescription = content;
        case 'og:image':
          ogImage = content;
        case 'og:site_name':
          ogSiteName = content;
      }

      // Fall back to <meta name="description"> if no og:description.
      if (name == 'description' && ogDescription == null) {
        ogDescription = content;
      }
    }

    // Fall back to <title> tag if no og:title.
    ogTitle ??= document.querySelector('title')?.text;

    // Resolve relative og:image URLs against the page origin.
    if (ogImage != null) {
      final imageUri = Uri.tryParse(ogImage);
      if (imageUri != null && !imageUri.hasScheme) {
        final base = Uri.tryParse(url);
        if (base != null) {
          ogImage = base.resolve(ogImage).toString();
        }
      }
    }

    // Validate og:image URL — reject private/non-http(s) schemes.
    if (ogImage != null && !_isSupported(ogImage)) {
      ogImage = null;
    }

    final data = OpenGraphData(
      title: ogTitle,
      description: ogDescription,
      imageUrl: ogImage,
      siteName: ogSiteName,
      url: url,
    );

    return data.isEmpty ? null : data;
  }

  /// DNS-resolve the og:image host and strip it if it points to a private IP.
  Future<OpenGraphData?> _validateImageUrl(OpenGraphData? data) async {
    if (data?.imageUrl == null) return data;
    final imageUri = Uri.tryParse(data!.imageUrl!);
    if (imageUri == null || imageUri.host.isEmpty) return data;
    try {
      final addresses = await _resolvePublicAddresses(imageUri.host);
      if (addresses == null) {
        return OpenGraphData(
          title: data.title,
          description: data.description,
          siteName: data.siteName,
          url: data.url,
          fetchedAt: data.fetchedAt,
        );
      }
    } catch (_) {
      return OpenGraphData(
        title: data.title,
        description: data.description,
        siteName: data.siteName,
        url: data.url,
        fetchedAt: data.fetchedAt,
      );
    }
    return data;
  }

  void _putCache(String url, OpenGraphData? data) {
    // Evict oldest entry if at capacity.
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = _CacheEntry(data);
  }
}
