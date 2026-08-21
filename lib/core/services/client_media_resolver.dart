import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/media_resolver.dart';
import 'package:matrix/matrix.dart';

/// [MediaResolver] backed by a Matrix SDK [MatrixClientService].
///
/// Resolves `mxc://` URIs via `Uri.getThumbnailUri` (for small images) or
/// `Uri.getDownloadUri` (for larger ones) and attaches auth headers via
/// [mediaAuthHeaders] (scoped to the homeserver host to prevent token
/// leakage to federated media servers).
class ClientMediaResolver implements MediaResolver {
  ClientMediaResolver(this._matrixClientService);

  final MatrixClientService _matrixClientService;

  @override
  Future<MediaThumbnail?> resolve(
    String? mxcUrl, {
    required double? width,
    required double? height,
  }) async {
    if (mxcUrl == null) return null;
    if (!mxcUrl.startsWith('mxc://')) {
      return MediaThumbnail(url: mxcUrl);
    }

    final mxc = Uri.tryParse(mxcUrl);
    if (mxc == null) return null;

    try {
      final useThumb =
          width != null && height != null && width <= 96 && height <= 96;
      final Uri uri;
      if (useThumb) {
        uri = await mxc.getThumbnailUri(
          _matrixClientService.client,
          width: 48,
          height: 48,
          method: ThumbnailMethod.scale,
        );
      } else {
        uri = await mxc.getDownloadUri(_matrixClientService.client);
      }
      final url = uri.toString();
      return MediaThumbnail(url: url, headers: mediaAuthHeaders(_matrixClientService.client, url));
    } catch (e) {
      debugPrint('[Kohera] Failed to resolve mxc image: $e');
      return null;
    }
  }
}
