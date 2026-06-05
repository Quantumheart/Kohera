import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kohera/core/data/openmoji_catalog.dart';
import 'package:kohera/core/models/openmoji_pack.dart';

/// Provides the curated OpenMoji default emoji packs and downloads their
/// images from openmoji.org for import into the user's account.
class OpenMojiService {
  OpenMojiService({
    http.Client? client,
    Duration? requestTimeout,
    String? imageBaseUrl,
    List<OpenMojiPack>? catalog,
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout ?? const Duration(seconds: 15),
        _imageBaseUrl = imageBaseUrl ?? defaultImageBaseUrl,
        _catalog = catalog ?? kOpenMojiCatalog;

  static const defaultImageBaseUrl =
      'https://openmoji.org/data/color/72x72';

  final http.Client _client;
  final Duration _requestTimeout;
  final String _imageBaseUrl;
  final List<OpenMojiPack> _catalog;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _client.close();
  }

  /// The bundled OpenMoji packs offered to the user.
  List<OpenMojiPack> get packs => _catalog;

  String imageUrl(OpenMojiEmoji emoji) => emoji.imageUrl(_imageBaseUrl);

  Future<Uint8List> downloadImage(String imageUrl) async {
    if (_disposed) {
      throw StateError('OpenMojiService used after dispose');
    }
    final response =
        await _client.get(Uri.parse(imageUrl)).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'OpenMoji image download failed (${response.statusCode}): $imageUrl',
      );
    }
    return response.bodyBytes;
  }
}
