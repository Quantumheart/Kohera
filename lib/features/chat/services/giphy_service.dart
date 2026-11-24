import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GiphyGif {
  const GiphyGif({
    required this.id,
    required this.title,
    required this.downsizedUrl,
    required this.originalUrl,
  });

  factory GiphyGif.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>? ?? const {};
    final downsized = images['downsized'] as Map<String, dynamic>?;
    final original = images['original'] as Map<String, dynamic>?;
    return GiphyGif(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      downsizedUrl: downsized?['url'] as String? ?? '',
      originalUrl: original?['url'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final String downsizedUrl;
  final String originalUrl;

  String get previewUrl =>
      downsizedUrl.isNotEmpty ? downsizedUrl : originalUrl;

  String get sendUrl => downsizedUrl.isNotEmpty ? downsizedUrl : originalUrl;
}

class GiphyException implements Exception {
  const GiphyException(this.message);

  final String message;

  @override
  String toString() => 'GiphyException: $message';
}

class GiphyService {
  GiphyService({required String apiKey, http.Client? client})
    : _apiKey = apiKey,
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const _host = 'api.giphy.com';
  static const pageSize = 25;
  static const _timeout = Duration(seconds: 10);

  final String _apiKey;
  final http.Client _client;
  final bool _ownsClient;

  Future<List<GiphyGif>> trending({int offset = 0}) =>
      _get('/v1/gifs/trending', offset: offset);

  Future<List<GiphyGif>> search(String query, {int offset = 0}) =>
      _get('/v1/gifs/search', query: query, offset: offset);

  Future<List<GiphyGif>> _get(
    String path, {
    String? query,
    int offset = 0,
  }) async {
    final uri = Uri.https(_host, path, {
      'api_key': _apiKey,
      'limit': '$pageSize',
      'offset': '$offset',
      'rating': 'pg-13',
      if (query != null && query.isNotEmpty) 'q': query,
    });
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const GiphyException('Request timed out');
    }
    if (response.statusCode != 200) {
      throw GiphyException('GIPHY request failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(GiphyGif.fromJson)
        .where((gif) => gif.sendUrl.isNotEmpty)
        .toList();
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
