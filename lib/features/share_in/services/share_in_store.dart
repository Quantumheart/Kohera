import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kohera/features/share_in/models/incoming_share.dart';

/// Dart-side bridge over the `kohera/share` platform channel.
///
/// The iOS Share Extension stages a single [IncomingShare] into the App-Group
/// `UserDefaults` suite `group.io.github.quantumheart.kohera` and redirects to
/// the host app. The main app reads it here and clears it once sent. On
/// platforms without a native handler (Android/desktop/web) every call
/// degrades to a no-op so callers never branch on platform.
class ShareInStore {
  ShareInStore({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('kohera/share');

  final MethodChannel _channel;

  Future<IncomingShare?> readIncomingShare() async {
    final raw = await _invokeJson<String>('readIncomingShare');
    if (raw == null || raw.isEmpty) return null;
    try {
      return IncomingShare.decode(raw);
    } catch (e) {
      debugPrint('[Kohera] ShareInStore decode incomingShare failed: $e');
      return null;
    }
  }

  Future<void> clearIncomingShare() async => _invokeVoid('clearIncomingShare', null);

  Future<T?> _invokeJson<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException catch (e) {
      debugPrint('[Kohera] ShareInStore $method unavailable: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _invokeVoid(String method, Object? arg) async {
    try {
      await _channel.invokeMethod<void>(method, arg);
    } on PlatformException catch (e) {
      debugPrint('[Kohera] ShareInStore $method unavailable: $e');
    } on MissingPluginException {
      // No native handler on this platform — share-in is iOS-only for now.
    }
  }
}
