import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

/// [AvatarResolver] backed by a Matrix SDK [MatrixClientService].
///
/// Resolves `mxc://` URIs via `Uri.getThumbnailUri` and attaches auth headers
/// via [mediaAuthHeaders] (scoped to the homeserver host to prevent token
/// leakage to federated media servers).
class ClientAvatarResolver implements AvatarResolver {
  ClientAvatarResolver(this._matrixClientService);

  final MatrixClientService _matrixClientService;

  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size}) async {
    if (mxcUrl == null) return null;
    try {
      final uri = Uri.parse(mxcUrl);
      final thumb = await uri.getThumbnailUri(
        _matrixClientService.client,
        width: (size * 2).toInt(),
        height: (size * 2).toInt(),
      );
      final url = thumb.toString();
      return AvatarThumbnail(url: url, headers: mediaAuthHeaders(_matrixClientService.client, url));
    } catch (e) {
      debugPrint('[Kohera] Failed to resolve avatar thumbnail: $e');
      return null;
    }
  }
}
