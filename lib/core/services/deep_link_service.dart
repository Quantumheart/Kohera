import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Receives native deep links (`matrix:`, `io.github.quantumheart.kohera://`,
/// and `https://matrix.to/…`) and navigates to the matching room or user.
///
/// On desktop platforms the `matrix:` URI scheme is registered via the
/// `.desktop` file (Linux), Inno Setup registry entries (Windows), and
/// `CFBundleURLTypes` (macOS). On mobile the custom scheme
/// `io.github.quantumheart.kohera://` and `matrix:` are registered in the
/// platform manifests. Android additionally intercepts `matrix.to` HTTPS links.
class DeepLinkService {
  DeepLinkService(this._router);

  final GoRouter _router;
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _sub;

  /// Start listening for incoming deep links.
  void init() {
    _appLinks = AppLinks();
    _sub = _appLinks!.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => debugPrint('[DeepLink] Stream error: $e'),
    );
  }

  /// Process the initial link that launched the app (if any).
  Future<void> processInitialLink() async {
    try {
      final initial = await _appLinks?.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (e) {
      debugPrint('[DeepLink] Initial link error: $e');
    }
  }

  void _handleUri(Uri uri) {
    debugPrint('[DeepLink] Received: $uri');
    final target = _parseUri(uri);
    if (target == null) return;
    _router.go(target);
  }

  /// Convert a deep-link [Uri] into a go_router path, or `null` if unrecognised.
  ///
  /// Supported formats:
  /// - `matrix:u/<user>?action=chat` → user
  /// - `matrix:r/<alias>?action=join` → room alias
  /// - `matrix:roomid/<id>?action=join` → room ID
  /// - `matrix:r/<alias>/e/<event>` → event in room
  /// - `matrix:roomid/<id>/e/<event>` → event in room by ID
  /// - `io.github.quantumheart.kohera://chat/<identifier>` → room or user
  /// - `https://matrix.to/#/<identifier>` → room or user
  String? _parseUri(Uri uri) {
    final scheme = uri.scheme;

    if (scheme == 'matrix') {
      return _parseMatrixScheme(uri);
    }

    if (scheme == 'io.github.quantumheart.kohera') {
      // io.github.quantumheart.kohera://chat/<identifier>
      if (uri.host != 'chat') return null;
      final segments = uri.pathSegments;
      if (segments.isEmpty) return null;
      final identifier = Uri.decodeComponent(segments.first);
      return _routeForIdentifier(identifier);
    }

    if (scheme == 'https' && uri.host == 'matrix.to') {
      // https://matrix.to/#/<identifier>
      final fragment = uri.fragment;
      if (fragment.isEmpty) return null;
      // Strip leading "/" from the fragment
      var id = fragment;
      if (id.startsWith('/')) id = id.substring(1);
      // Strip event-id path if present
      final slash = id.indexOf('/');
      if (slash >= 0) id = id.substring(0, slash);
      id = Uri.decodeComponent(id);
      return _routeForIdentifier(id);
    }

    return null;
  }

  /// Parse a `matrix:` URI into a go_router path.
  String? _parseMatrixScheme(Uri uri) {
    // matrix: URIs use the format: matrix:<type>/<identifier>?action=...
    // The path is everything after "matrix:"
    final path = uri.toString().substring('matrix:'.length);
    final parts = path.split('/');
    if (parts.length < 2) return null;

    final type = parts[0];
    final encodedId = parts[1];
    final identifier = Uri.decodeComponent(encodedId);

    switch (type) {
      case 'u':
        // User: matrix:u/<user>?action=chat
        return _routeForIdentifier('@$identifier');
      case 'r':
        // Room alias: matrix:r/<alias>
        return _routeForIdentifier('#$identifier');
      case 'roomid':
        // Room ID: matrix:roomid/<id>
        return _routeForIdentifier('!$identifier');
      default:
        return null;
    }
  }

  /// Map a Matrix identifier (with sigil) to a go_router path.
  String? _routeForIdentifier(String identifier) {
    if (identifier.isEmpty) return null;
    final sigil = identifier[0];
    switch (sigil) {
      case '@':
        // Users go to home — the app can show a DM creation dialog.
        // For now, navigate home; a future improvement can deep-link
        // directly to a DM room if one already exists.
        return '/';
      case '#':
      case '!':
        // Rooms navigate to /rooms/<encoded identifier>.
        return '/rooms/${Uri.encodeComponent(identifier)}';
      default:
        return null;
    }
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
