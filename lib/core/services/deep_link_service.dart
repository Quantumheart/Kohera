import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

/// Receives native deep links (`matrix:`, `io.github.quantumheart.kohera://`,
/// and `https://matrix.to/…`) and navigates to the matching room or user.
///
/// On desktop platforms the `matrix:` URI scheme is registered via the
/// `.desktop` file (Linux), Inno Setup registry entries (Windows), and
/// `CFBundleURLTypes` (macOS). On mobile the custom scheme
/// `io.github.quantumheart.kohera://` and `matrix:` are registered in the
/// platform manifests. Android additionally intercepts `matrix.to` HTTPS links.
///
/// Links received before the user is ready (logged out or in E2EE setup) are
/// queued and replayed once auth/backup completes — otherwise the router
/// redirect would silently drop the target.
class DeepLinkService {
  DeepLinkService({
    required GoRouter router,
    required ClientManager clientManager,
    required Listenable refreshListenable,
  })  : _router = router,
        _clientManager = clientManager,
        _refresh = refreshListenable;

  final GoRouter _router;
  final ClientManager _clientManager;
  final Listenable _refresh;

  /// Lazily constructed so the platform plugin isn't touched until first use;
  /// the "must call [init] first" contract is then compile-time-enforced.
  late final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Target queued while the user isn't ready to navigate (logged out / E2EE
  /// setup); replayed from [_refresh].
  DeepLinkIntent? _pendingIntent;

  /// Duplicate-delivery guard: `app_links` has historically double-delivered
  /// the initial link and a stream event on some Android versions.
  Uri? _lastUri;
  DateTime? _lastHandledAt;
  static const _dedupeWindow = Duration(seconds: 2);

  MatrixService get _matrix => _clientManager.activeService;
  Client get _client => _matrix.client;

  /// `true` when a `/rooms/…` navigation won't be bounced to `/login` or
  /// `/e2ee-setup` by the router redirect.
  bool get _isReady =>
      _matrix.isLoggedIn &&
      (_matrix.chatBackup.chatBackupNeeded != true || _matrix.hasSkippedSetup);

  /// Start listening for incoming deep links.
  void init() {
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => debugPrint('[DeepLink] Stream error: $e'),
    );
    _refresh.addListener(_onRefresh);
  }

  /// Process the initial link that launched the app (if any).
  Future<void> processInitialLink() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleUri(initial);
    } catch (e) {
      debugPrint('[DeepLink] Initial link error: $e');
    }
  }

  // ── Handling ───────────────────────────────────────────────

  Future<void> _handleUri(Uri uri) async {
    if (_isDuplicate(uri)) return;
    _lastUri = uri;
    _lastHandledAt = DateTime.now();
    if (kDebugMode) debugPrint('[DeepLink] Received: $uri');

    final intent = parseDeepLinkUri(uri);
    if (intent == null) return;
    await _applyIntent(intent);
  }

  bool _isDuplicate(Uri uri) {
    final last = _lastUri;
    final at = _lastHandledAt;
    return last != null &&
        last.toString() == uri.toString() &&
        at != null &&
        DateTime.now().difference(at) < _dedupeWindow;
  }

  /// Resolve and navigate to [intent], or queue it if the user isn't ready.
  Future<void> _applyIntent(DeepLinkIntent intent) async {
    if (!_isReady) {
      // Queue; the router redirect would otherwise drop the target. Only the
      // latest intent is kept.
      _pendingIntent = intent;
      return;
    }
    final target = await _resolveIntent(intent);
    if (target != null) _router.go(target.path, extra: target.eventId);
  }

  /// Replayed when auth/backup state changes (login, E2EE setup done).
  void _onRefresh() {
    final pending = _pendingIntent;
    if (pending == null || !_isReady) return;
    _pendingIntent = null;
    unawaited(
      _resolveIntent(pending).then((target) {
        if (target != null) _router.go(target.path, extra: target.eventId);
      }),
    );
  }

  // ── Resolution (may hit the network) ───────────────────────

  /// Resolve an intent to a go_router target, resolving room aliases to
  /// canonical room IDs and joining when requested. Returns `null` when the
  /// link isn't actionable (e.g. an unjoined room without an explicit join
  /// intent) so a broken `ChatScreen` is never navigated to.
  Future<_DeepLinkTarget?> _resolveIntent(DeepLinkIntent intent) async {
    final id = intent.identifier;
    if (id.isEmpty) return null;
    switch (id[0]) {
      case '@':
        // Users go to home — the app can show a DM creation dialog. A future
        // improvement can deep-link directly to an existing DM room.
        return const _DeepLinkTarget(path: RoutePaths.home);
      case '#':
      case '!':
        final roomId = await _resolveRoomId(
          id,
          action: intent.action,
          via: intent.via,
        );
        if (roomId == null) return null;
        return _DeepLinkTarget(
          path: '$RoutePaths.roomPrefix${Uri.encodeComponent(roomId)}',
          eventId: intent.eventId,
        );
      default:
        return null;
    }
  }

  /// Resolve a room identifier (alias or `!id`) to a canonical room ID.
  ///
  /// Joined rooms resolve locally (no network). Unjoined rooms are only
  /// joined when [action] is `'join'` (with `?via=…` servers); otherwise the
  /// link isn't actionable.
  Future<String?> _resolveRoomId(
    String identifier, {
    String? action,
    List<String> via = const [],
  }) async {
    final client = _client;
    if (identifier.startsWith('!')) {
      if (client.getRoomById(identifier) != null) return identifier;
    } else {
      final room = client.getRoomByAlias(identifier);
      if (room != null) return room.id;
    }
    if (action == 'join') {
      return _join(identifier, via);
    }
    return null;
  }

  /// Join a room by alias or ID, waiting for it to appear in sync.
  Future<String?> _join(String address, List<String> via) async {
    try {
      final roomId = await _client.joinRoom(
        address,
        via: via.isEmpty ? null : via,
      );
      await _client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));
      return roomId;
    } catch (e) {
      debugPrint('[DeepLink] join "$address" failed: $e');
      return null;
    }
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    _refresh.removeListener(_onRefresh);
  }
}

/// A parsed deep link before any resolution/network work.
class DeepLinkIntent {
  const DeepLinkIntent({
    required this.identifier,
    this.action,
    this.via = const [],
    this.eventId,
  });

  /// Matrix identifier with its sigil (`@user`, `#alias`, `!id`).
  final String identifier;

  /// `?action=` value (e.g. `chat`, `join`), if present.
  final String? action;

  /// `?via=server1&via=server2` servers, for joining rooms via alias.
  final List<String> via;

  /// Event ID for event links (`…/e/<event>` or matrix.to `…/<event>`).
  final String? eventId;

  @override
  String toString() =>
      'DeepLinkIntent(identifier: $identifier, action: $action, '
      'via: $via, eventId: $eventId)';
}

/// A resolved go_router destination.
class _DeepLinkTarget {
  const _DeepLinkTarget({required this.path, this.eventId});

  final String path;

  /// Passed as `state.extra` so `ChatScreen` reads it as `initialEventId`.
  final String? eventId;
}

/// Convert a deep-link [Uri] into a [DeepLinkIntent], or `null` if unrecognised.
///
/// Pure (no network, no platform) so it is unit-testable.
///
/// Supported formats:
/// - `matrix:u/<user>?action=chat` → user
/// - `matrix:r/<alias>?action=join&via=server` → room alias
/// - `matrix:roomid/<id>?action=join` → room ID
/// - `matrix:r/<alias>/e/<event>` / `matrix:roomid/<id>/e/<event>` → event
/// - `io.github.quantumheart.kohera://chat/<identifier>` → room or user
/// - `https://matrix.to/#/<identifier>[/<event>][?via=server]` → room or user
DeepLinkIntent? parseDeepLinkUri(Uri uri) {
  final scheme = uri.scheme;

  if (scheme == 'matrix') {
    return _parseMatrixScheme(uri);
  }

  if (scheme == 'io.github.quantumheart.kohera') {
    // io.github.quantumheart.kohera://chat/<identifier>
    if (uri.host != 'chat') return null;
    // pathSegments are already percent-decoded — don't decode twice.
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    return DeepLinkIntent(
      identifier: segments.first,
      action: uri.queryParameters['action'],
      via: uri.queryParametersAll['via'] ?? const [],
    );
  }

  if (scheme == 'https' && uri.host == 'matrix.to') {
    // https://matrix.to/#/<identifier>[/<event>][?via=server]
    // The query (?via=…) is inside the fragment, so split it off manually —
    // uri.queryParameters is empty here.
    var fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    var fragmentQuery = '';
    final q = fragment.indexOf('?');
    if (q >= 0) {
      fragmentQuery = fragment.substring(q + 1);
      fragment = fragment.substring(0, q);
    }
    if (fragment.startsWith('/')) fragment = fragment.substring(1);
    final segments = fragment.split('/');
    if (segments.isEmpty || segments.first.isEmpty) return null;
    final identifier = Uri.decodeComponent(segments.first);
    final eventId = segments.length >= 2 && segments[1].isNotEmpty
        ? _ensureEventSigil(Uri.decodeComponent(segments[1]))
        : null;
    final via = fragmentQuery.isEmpty
        ? const <String>[]
        : Uri.parse('?$fragmentQuery').queryParametersAll['via'] ?? const [];
    return DeepLinkIntent(
      identifier: identifier,
      eventId: eventId,
      via: via,
    );
  }

  return null;
}

/// Re-adds the leading `$` on an event id if the source omitted it. The Kohera
/// matrix.to fork strips the `$` from event ids when emitting `matrix:` URIs
/// (parallel to stripping room/user sigils); matrix.to HTTPS links keep it.
String _ensureEventSigil(String id) =>
    id.startsWith(r'$') ? id : r'$' + id;

/// Parse a `matrix:` URI into an intent.
///
/// Uses [Uri.path] (not `toString()`) so the query string (`?action=…`,
/// `?via=…`) isn't glued onto the identifier, and percent-encoding is
/// preserved for the single decode below.
DeepLinkIntent? _parseMatrixScheme(Uri uri) {
  final path = uri.path;
  final parts = path.split('/');
  if (parts.length < 2) return null;

  final type = parts[0];
  final identifier = Uri.decodeComponent(parts[1]);

  // Event segment: matrix:<type>/<id>/e/<event>
  String? eventId;
  if (parts.length >= 4 && parts[2] == 'e') {
    eventId = _ensureEventSigil(Uri.decodeComponent(parts[3]));
  }

  final action = uri.queryParameters['action'];
  final via = uri.queryParametersAll['via'] ?? const [];

  String? sigil;
  switch (type) {
    case 'u':
      sigil = '@';
    case 'r':
      sigil = '#';
    case 'roomid':
      sigil = '!';
  }
  if (sigil == null) return null;
  // The sigil is implied by the type segment, but accept it if the source
  // already includes it (the fork emits room-id URIs with a leading `!`).
  final full = identifier.startsWith(sigil) ? identifier : '$sigil$identifier';
  return DeepLinkIntent(
    identifier: full,
    action: action,
    via: via,
    eventId: eventId,
  );
}
