import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

// ── Intent types ──────────────────────────────────────────────

sealed class DeepLinkIntent {
  const DeepLinkIntent();
}

class RegisterInviteIntent extends DeepLinkIntent {
  const RegisterInviteIntent({required this.server, required this.token});

  final String server;
  final String token;
}

// ── URI source abstraction ────────────────────────────────────

abstract class DeepLinkSource {
  Future<Uri?> getInitialLink();
  Stream<Uri> get uriLinkStream;
}

class AppLinksSource implements DeepLinkSource {
  AppLinksSource() : _impl = AppLinks();

  final AppLinks _impl;

  @override
  Future<Uri?> getInitialLink() => _impl.getInitialLink();

  @override
  Stream<Uri> get uriLinkStream => _impl.uriLinkStream;
}

// ── Service ───────────────────────────────────────────────────

class DeepLinkService extends ChangeNotifier {
  DeepLinkService({DeepLinkSource? source, DateTime Function()? now})
      : _source = source ?? AppLinksSource(),
        _now = now ?? DateTime.now;

  final DeepLinkSource _source;
  final DateTime Function() _now;

  StreamSubscription<Uri>? _sub;
  final Map<String, DateTime> _recent = {};
  static const _dedupWindow = Duration(seconds: 30);

  DeepLinkIntent? _pending;
  DeepLinkIntent? get pending => _pending;

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final initial = await _source.getInitialLink();
      if (initial != null) _ingest(initial);
    } catch (e) {
      debugPrint('[Kohera] DeepLinkService getInitialLink failed: $e');
    }
    _sub = _source.uriLinkStream.listen(
      _ingest,
      onError: (Object e) =>
          debugPrint('[Kohera] DeepLinkService stream error: $e'),
    );
  }

  void _ingest(Uri uri) {
    if (uri.scheme != 'kohera') return;

    final key = uri.toString();
    final now = _now();
    final last = _recent[key];
    if (last != null && now.difference(last) < _dedupWindow) return;
    _recent[key] = now;
    _recent.removeWhere((_, t) => now.difference(t) > _dedupWindow);

    if (uri.host == 'register') {
      final server = uri.queryParameters['server']?.trim() ?? '';
      final token = uri.queryParameters['token']?.trim() ?? '';
      if (server.isEmpty || token.isEmpty) {
        debugPrint(
          '[Kohera] Ignored invite deep link (missing server/token)',
        );
        return;
      }
      _pending = RegisterInviteIntent(server: server, token: token);
      notifyListeners();
    } else {
      debugPrint('[Kohera] Ignored unknown deep-link host: ${uri.host}');
    }
  }

  void consume() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
